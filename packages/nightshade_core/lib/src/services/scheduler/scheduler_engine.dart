import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    show WeightedFactor, WeightedScore, WeightedScoreMode;
import 'package:uuid/uuid.dart';

import '../../models/scheduler/integration_goal.dart';
import '../../models/scheduler/scheduler_decision.dart';
import '../../models/scheduler/scheduler_status.dart';
import '../../models/scheduler/target_constraint.dart';
import '../../models/sequence/sequence_models.dart';
import 'horizon_profile.dart';
import 'sky_calculations.dart';

part 'scheduler_engine/contracts.dart';
part 'scheduler_engine/astronomy_helpers.dart';

/// The dynamic RoboTarget-class scheduler.
///
/// Pure-logic core. Wiring to Riverpod, the database, and the sequencer
/// lives in `providers/scheduler_provider.dart`. The engine owns:
///   * a periodic timer (the tick loop)
///   * a single re-evaluation lock so concurrent triggers don't interleave
///   * a `SchedulerStatus` stream (for the UI status panel)
///   * a `SchedulerDecision` stream (each tick emits the full breakdown)
class SchedulerEngine {
  SchedulerEngine({
    required SchedulerSite site,
    required SchedulerSequenceSink sequenceSink,
    SchedulerConfig config = SchedulerConfig.defaults,
    Future<List<SchedulerCandidate>> Function()? candidateLoader,
    Stream<SchedulerTriggerEvent>? triggerStream,
    DateTime Function()? clock,
  }) : _config = config,
       _sequenceSink = sequenceSink,
       _site = site,
       _candidateLoader = candidateLoader ?? (() async => const []),
       _clock = clock ?? DateTime.now {
    if (triggerStream != null) {
      _triggerSubscription = triggerStream.listen((evt) {
        // A natural sequence completion means the executor has STOPPED, but
        // currentTargetId still names the just-finished target. A plain
        // re-evaluation would then see isSwitch=false and never re-dispatch,
        // leaving the rig idle for the rest of the night. Clear the current
        // target (only while running, and only the autopilot's own target)
        // so the next evaluation re-dispatches the winner — the same target's
        // remaining work, or the next-best target if its goals are now done.
        // Loop-safe: 'SequenceStopped' is not mapped to this trigger, so the
        // engine's own stop-to-switch never reaches here.
        if (evt == SchedulerTriggerEvent.sequenceCompleted &&
            _status.state == SchedulerState.running &&
            _status.currentTargetId != null) {
          _updateStatus(_status.copyWith(clearCurrentTarget: true));
        }
        _evaluateWithReason('trigger: ${evt.name}');
      });
    }
  }

  SchedulerConfig _config;
  SchedulerSite _site;
  final SchedulerSequenceSink _sequenceSink;
  Future<List<SchedulerCandidate>> Function() _candidateLoader;
  final DateTime Function() _clock;
  StreamSubscription<SchedulerTriggerEvent>? _triggerSubscription;
  Timer? _tickTimer;
  bool _evaluating = false;
  final List<Completer<void>> _pendingEvaluations = [];
  // Debounce window used by [requestReevaluation]. A burst of provider
  // emissions (e.g. a goal upsert that also touches the constraint table)
  // should fire ONE re-evaluation, not N.
  static const Duration _reevaluationDebounce = Duration(milliseconds: 500);
  Timer? _reevaluationDebounceTimer;

  // True once [SchedulerSequenceSink.parkForEndOfNight] has fired for the
  // current dawn. Guards against re-parking on every subsequent tick while the
  // Sun stays up (the empty-eligible path runs each tick). Re-armed (set false)
  // the moment the engine successfully dispatches a target again — a new
  // observing night has begun, so the next dawn must park afresh.
  bool _parkedForEndOfNight = false;

  // A daytime start is an ARMED scheduler waiting for tonight, not evidence
  // that an observing night has just ended. Only a run that successfully
  // dispatched work owns a rig that needs the scheduler's dawn-safe action.
  bool _dispatchedSinceStart = false;

  SchedulerStatus _status = const SchedulerStatus();
  final _statusController = StreamController<SchedulerStatus>.broadcast(
    sync: false,
  );
  final _decisionController = StreamController<SchedulerDecision>.broadcast(
    sync: false,
  );
  SchedulerDecision? _lastDecision;

  SchedulerStatus get status => _status;
  SchedulerDecision? get lastDecision => _lastDecision;
  SchedulerConfig get config => _config;
  SchedulerSite get site => _site;
  Stream<SchedulerStatus> get statusStream => _statusController.stream;
  Stream<SchedulerDecision> get decisionStream => _decisionController.stream;

  void updateConfig(SchedulerConfig config) {
    _config = config;
    if (_status.state == SchedulerState.running) {
      _restartTimer();
    }
  }

  void updateSite(SchedulerSite site) {
    _site = site;
  }

  void setCandidateLoader(Future<List<SchedulerCandidate>> Function() loader) {
    _candidateLoader = loader;
  }

  Future<void> start() async {
    if (_status.state == SchedulerState.running) return;
    final candidates = await _candidateLoader();
    if (candidates.isEmpty) {
      throw const SchedulerStartException(
        'Add at least one target to the scheduler before starting autopilot.',
      );
    }
    // Fresh run: re-arm the end-of-night park so a previous dawn's park does
    // not suppress parking on this run's dawn.
    _parkedForEndOfNight = false;
    _dispatchedSinceStart = false;
    _updateStatus(
      _status.copyWith(
        state: SchedulerState.running,
        clearError: true,
        nextEvaluationAt: _clock().add(_config.tickInterval),
      ),
    );
    _restartTimer();
    await _evaluateWithReason('engine start', candidates: candidates);
  }

  Future<void> pause() async {
    if (_status.state != SchedulerState.running) return;
    _tickTimer?.cancel();
    _tickTimer = null;
    // Pause the underlying sequence FIRST. If the run already ended,
    // pauseSequence throws ('Cannot pause: sequence is not running'); in that
    // case do NOT flip the engine to paused — leaving status=paused while the
    // sequence is not actually paused diverges status from reality and a later
    // resume() would no-op against a non-existent run.
    await _sequenceSink.pauseSequence();
    _updateStatus(
      _status.copyWith(state: SchedulerState.paused, clearNextEvaluation: true),
    );
  }

  Future<void> resume() async {
    if (_status.state != SchedulerState.paused) return;
    _updateStatus(
      _status.copyWith(
        state: SchedulerState.running,
        nextEvaluationAt: _clock().add(_config.tickInterval),
      ),
    );
    await _sequenceSink.resumeSequence();
    _restartTimer();
    await _evaluateWithReason('engine resume');
  }

  Future<void> stop() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _updateStatus(
      _status.copyWith(
        state: SchedulerState.idle,
        clearCurrentTarget: true,
        clearNextEvaluation: true,
      ),
    );
    // Autopilot fully disengaged: hand the editor slot back to the operator and
    // restore the manual sequence that dispatchSequence stashed on take-over.
    // This is the disengage path (not a per-target swap at _maybeStop), so
    // releasing here does not fight the mid-night transient stops.
    //
    // releaseSequenceOwnership() runs in a finally so a throwing stopSequence
    // (backend down, native fault) can never leave the editor owned by the
    // autopilot with the operator's stashed manual sequence orphaned behind a
    // stuck owner state.
    try {
      await _sequenceSink.stopSequence();
    } finally {
      await _sequenceSink.releaseSequenceOwnership();
    }
  }

  /// Trigger an immediate re-evaluation. Returns when the evaluation
  /// (including any queued evaluations behind it) has completed.
  Future<void> evaluateNow({String reason = 'manual'}) {
    return _evaluateWithReason(reason);
  }

  /// Debounced re-evaluation hook for data-change listeners (target catalog,
  /// integration goals, constraints). Multiple calls inside the
  /// [_reevaluationDebounce] window coalesce into a single evaluation.
  void requestReevaluation({String reason = 'data change'}) {
    _reevaluationDebounceTimer?.cancel();
    _reevaluationDebounceTimer = Timer(_reevaluationDebounce, () {
      _reevaluationDebounceTimer = null;
      // Errors must propagate to the engine's lifecycle so we don't
      // swallow background re-eval failures (silent fallbacks hide bugs);
      // _evaluateWithReason already serializes via the same lock the tick
      // timer uses, so this is safe to fire-and-forget.
      _evaluateWithReason(reason);
    });
  }

  Future<void> dispose() async {
    _tickTimer?.cancel();
    _reevaluationDebounceTimer?.cancel();
    _reevaluationDebounceTimer = null;
    // Engine teardown disengages the autopilot — release the editor slot back to
    // manual so a stashed sequence isn't orphaned across a provider rebuild.
    //
    // Guarded: releaseSequenceOwnership() reaches _setOwner -> ref.read(
    // activePlanOwnerProvider...), which can throw if that global provider is
    // already torn down in the same container disposal. If the throw escaped,
    // the subscription + both controllers below would leak — the exact
    // ref-after-teardown leak class scheduler_provider already had to fix once.
    // Resource teardown must run regardless, so swallow the best-effort release.
    try {
      await _sequenceSink.releaseSequenceOwnership();
    } catch (e) {
      // Teardown best-effort: ownership release can fail if the global owner
      // provider was disposed first. Resources below must still be released —
      // trace the swallowed error so the path is observable, not silent.
      developer.log(
        'Scheduler teardown: best-effort ownership release failed',
        name: 'SchedulerEngine',
        level: 500, // FINE / trace
        error: e,
      );
    }
    await _triggerSubscription?.cancel();
    await _statusController.close();
    await _decisionController.close();
  }

  void _restartTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_config.tickInterval, (_) {
      _updateStatus(
        _status.copyWith(nextEvaluationAt: _clock().add(_config.tickInterval)),
      );
      _evaluateWithReason('tick');
    });
  }

  Future<void> _evaluateWithReason(
    String reason, {
    List<SchedulerCandidate>? candidates,
  }) async {
    if (_evaluating) {
      // Queue this caller; they'll be released after the in-flight
      // evaluation finishes. This serializes evaluations without dropping
      // a triggering event.
      final c = Completer<void>();
      _pendingEvaluations.add(c);
      return c.future;
    }
    _evaluating = true;
    try {
      await _evaluateOnce(reason, candidates: candidates);
    } finally {
      _evaluating = false;
      if (_pendingEvaluations.isNotEmpty) {
        final next = _pendingEvaluations.removeAt(0);
        // Run the next evaluation in a microtask so the completer for the
        // current caller resolves first.
        scheduleMicrotask(() async {
          try {
            await _evaluateWithReason('coalesced');
            next.complete();
          } catch (e, st) {
            next.completeError(e, st);
          }
        });
      }
    }
  }

  Future<void> _evaluateOnce(
    String reason, {
    List<SchedulerCandidate>? candidates,
  }) async {
    final now = _clock();
    final loadedCandidates = candidates ?? await _candidateLoader();

    // Pure, side-effect-free evaluation against the engine's CURRENT
    // hysteresis state (_status.currentTargetId). This computes the exact
    // decision the autopilot will act on; the side effects (publishing the
    // decision, mutating _status, dispatching/parking) live below so the
    // read-only preview path (previewDecision/previewRanking) can reuse the
    // same _evaluate without ever touching them.
    final outcome = _evaluate(
      candidates: loadedCandidates,
      now: now,
      currentTargetId: _status.currentTargetId,
      reason: reason,
    );

    // Re-evaluate while idle/paused is a read-only operator preview. Mutating
    // currentTargetId here used to make a later Start see isSwitch=false and
    // skip dispatch entirely; paused re-evaluations could similarly claim a
    // target switch the sequencer never performed.
    if (_status.state != SchedulerState.running) {
      _publishDecision(outcome.decision);
      return;
    }

    if (outcome.winner == null) {
      // The empty path can stop imaging, so its decision is published AFTER the
      // side effect, carrying the sentence that explains it. `finally` so a
      // throwing park/stop still publishes the tick the operator is watching.
      String? note;
      try {
        note = await _handleNoEligibleTarget(now);
      } finally {
        _publishDecision(
          note == null
              ? outcome.decision
              : _withReasoning(outcome.decision, note),
        );
      }
      return;
    }

    _publishDecision(outcome.decision);

    if (outcome.isSwitch) {
      final winner = outcome.winner!;
      if (_status.state == SchedulerState.running) {
        final chosenCandidate = loadedCandidates.firstWhere(
          (c) => c.targetId == winner.targetId,
        );
        final seq = buildSequenceForCandidate(chosenCandidate);
        // Commit the winner into status ONLY after dispatch succeeds. If we
        // committed first and dispatch then threw (a transient pre-flight
        // failure: brief disk dip, momentarily disconnected filter wheel,
        // native start hiccup), the next tick would see
        // currentTargetId == winner and hysteresis would make isSwitch=false,
        // so the engine would never re-dispatch — the autopilot would believe
        // it is imaging a target that never started. By dispatching first and
        // rolling the status back on failure, the next tick retries the switch.
        try {
          await _sequenceSink.dispatchSequence(seq);
        } catch (e) {
          // Leave currentTargetId unchanged (it is NOT the failed winner) so
          // the next evaluation re-attempts the switch. Surface the failure on
          // the status panel and hand the editor slot back to the operator so
          // their stashed manual sequence is not orphaned behind a wedged
          // autopilot.
          _updateStatus(
            _status.copyWith(
              lastError: 'Failed to start ${winner.targetName}: $e',
            ),
          );
          await _sequenceSink.releaseSequenceOwnership();
          return;
        }
        _updateStatus(
          _status.copyWith(
            currentTargetId: winner.targetId,
            currentTargetName: winner.targetName,
            clearError: true,
          ),
        );
        // A target was dispatched: a (new) observing night is under way, so
        // re-arm the end-of-night park for the next dawn.
        _parkedForEndOfNight = false;
        _dispatchedSinceStart = true;
      }
    }
  }

  /// Pure, side-effect-free core of an evaluation: score every candidate,
  /// apply the SAME hard gates the autopilot applies (via [_scoreCandidate]:
  /// twilight Sun gate, min altitude, custom horizon, filter availability,
  /// time-window, moon), apply the scheduled-window override and hysteresis
  /// against [currentTargetId], and build the resulting [SchedulerDecision].
  ///
  /// This NEVER mutates `_status`, NEVER dispatches, and NEVER parks — those
  /// effects are applied by [_evaluateOnce] using the returned outcome. The
  /// read-only [previewDecision]/[previewRanking] reuse this verbatim so the
  /// human-facing preview is the autopilot's decision by construction.
  _EvaluationOutcome _evaluate({
    required List<SchedulerCandidate> candidates,
    required DateTime now,
    required int? currentTargetId,
    required String reason,
  }) {
    if (candidates.isEmpty) {
      return _EvaluationOutcome(
        decision: SchedulerDecision(
          chosenTargetId: null,
          chosenTargetName: null,
          score: 0,
          reasoning: const ['No candidate targets available'],
          scoredCandidates: const [],
          rejected: const [],
          evaluatedAt: now,
          isSwitch: currentTargetId != null,
        ),
        winner: null,
        isSwitch: false,
      );
    }

    final scored = <TargetScore>[];
    // Tracks which candidates fall inside an active scheduledWindow at
    // this tick. The first such target (preferring the higher base score
    // when multiple overlap) wins regardless of hysteresis.
    final scheduledWindowHits = <int>{};
    for (final c in candidates) {
      scored.add(_scoreCandidate(c, now));
      if (_hasActiveScheduledWindow(c, now)) {
        scheduledWindowHits.add(c.targetId);
      }
    }

    final eligible = scored.where((s) => !s.hardConstraintFailed).toList();
    eligible.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    if (eligible.isEmpty) {
      final reasons = <String>[
        'No eligible candidates at ${now.toIso8601String()} ($reason)',
        ...scored
            .where((s) => s.rejectionReasons.isNotEmpty)
            .take(3)
            .map((s) => '${s.targetName}: ${s.rejectionReasons.first}'),
      ];
      final rejectedAll = scored
          .map(
            (s) => _buildRejection(
              s,
              chosenScore: 0,
              primaryReasonOverride: s.hardConstraintFailed
                  ? null
                  : 'no eligible winner',
            ),
          )
          .toList();
      return _EvaluationOutcome(
        decision: SchedulerDecision(
          chosenTargetId: null,
          chosenTargetName: null,
          score: 0,
          reasoning: reasons,
          scoredCandidates: scored,
          rejected: rejectedAll,
          evaluatedAt: now,
          isSwitch: currentTargetId != null,
        ),
        winner: null,
        isSwitch: false,
      );
    }

    final challenger = eligible.first;
    final currentId = currentTargetId;
    TargetScore winner;
    bool isSwitch;
    // True when the chosen target was forced by an active scheduled
    // window — the UI labels this distinctly ("Forced by scheduled
    // window …") and we skip hysteresis.
    bool forcedByScheduledWindow = false;

    // Scheduled-window override path: any eligible candidate that has an
    // active scheduledWindow constraint MUST be selected, bypassing
    // hysteresis. When multiple targets are inside their windows at the
    // same instant, the higher base score (already applied in scoring)
    // wins — eligible[0] is sorted by totalScore so the first eligible
    // entry whose id is in scheduledWindowHits is the right pick.
    TargetScore? forced;
    for (final s in eligible) {
      if (scheduledWindowHits.contains(s.targetId)) {
        forced = s;
        break;
      }
    }

    if (forced != null) {
      winner = forced;
      isSwitch = currentId != forced.targetId;
      forcedByScheduledWindow = true;
    } else if (currentId == null) {
      winner = challenger;
      isSwitch = true;
    } else {
      final currentEntry = eligible
          .where((s) => s.targetId == currentId)
          .toList();
      if (currentEntry.isEmpty) {
        // Current target is no longer eligible: forced switch.
        winner = challenger;
        isSwitch = true;
      } else {
        final current = currentEntry.first;
        final ratio = current.totalScore > 0
            ? challenger.totalScore / current.totalScore
            : double.infinity;
        if (challenger.targetId == current.targetId) {
          winner = current;
          isSwitch = false;
        } else if (ratio >= _config.hysteresisRatio) {
          winner = challenger;
          isSwitch = true;
        } else {
          winner = current;
          isSwitch = false;
        }
      }
    }

    final reasoning = <String>[];
    reasoning.add(
      'Chose ${winner.targetName} (score ${winner.totalScore.toStringAsFixed(3)}) at ${now.toIso8601String()} ($reason)',
    );
    for (final f in winner.factors) {
      reasoning.add(
        '  ${f.name}: value=${f.value.toStringAsFixed(3)} weight=${f.weight.toStringAsFixed(2)} -> ${f.weighted.toStringAsFixed(3)}${f.detail != null ? "  ${f.detail}" : ""}',
      );
    }
    if (forcedByScheduledWindow) {
      reasoning.add(
        'Forced by scheduled window (hysteresis bypassed) on ${winner.targetName}',
      );
    }
    if (eligible.length > 1) {
      final next = eligible.firstWhere(
        (s) => s.targetId != winner.targetId,
        orElse: () => eligible[1],
      );
      reasoning.add(
        'Runner-up: ${next.targetName} score ${next.totalScore.toStringAsFixed(3)}',
      );
    }
    if (isSwitch && currentId != null && !forcedByScheduledWindow) {
      reasoning.add(
        'Switching from previous target id=$currentId (hysteresis ratio=${_config.hysteresisRatio.toStringAsFixed(2)} exceeded)',
      );
    }

    final orderedAll = [
      ...eligible,
      ...scored.where((s) => s.hardConstraintFailed),
    ];

    final rejected = <RejectedCandidate>[];
    for (final s in orderedAll) {
      if (s.targetId == winner.targetId) continue;
      rejected.add(_buildRejection(s, chosenScore: winner.totalScore));
    }

    return _EvaluationOutcome(
      decision: SchedulerDecision(
        chosenTargetId: winner.targetId,
        chosenTargetName: winner.targetName,
        score: winner.totalScore,
        reasoning: reasoning,
        scoredCandidates: orderedAll,
        rejected: rejected,
        evaluatedAt: now,
        isSwitch: isSwitch,
      ),
      winner: winner,
      isSwitch: isSwitch,
    );
  }

  /// Read-only preview of the decision the autopilot WOULD make at [now] for
  /// the current candidate set and the engine's CURRENT hysteresis state,
  /// WITHOUT dispatching, parking, or mutating `_status`/`_lastDecision`.
  ///
  /// The Planner surfaces this so what the human sees IS what the rig will
  /// slew to next: it runs the exact same [_evaluate] (same `_scoreCandidate`,
  /// same hard gates, same scheduled-window override and hysteresis) the live
  /// autopilot runs. The only inputs are `now` and the loaded candidates;
  /// loading candidates is the same read the autopilot performs and carries no
  /// side effects of its own.
  Future<SchedulerDecision> previewDecision(DateTime now) async {
    final candidates = await _candidateLoader();
    final outcome = _evaluate(
      candidates: candidates,
      now: now,
      currentTargetId: _status.currentTargetId,
      reason: 'preview',
    );
    return outcome.decision;
  }

  /// Read-only ranked list of every eligible candidate at [now], best-first,
  /// computed by the same pure [_evaluate] the autopilot uses (hard-rejected
  /// candidates are omitted — they cannot be selected). The headline pick is
  /// `result.first` and equals [previewDecision]'s `chosenTargetId` for the
  /// same clock and candidate set. Side-effect-free.
  Future<List<TargetScore>> previewRanking(DateTime now) async {
    final candidates = await _candidateLoader();
    final outcome = _evaluate(
      candidates: candidates,
      now: now,
      currentTargetId: _status.currentTargetId,
      reason: 'preview',
    );
    return outcome.decision.scoredCandidates
        .where((s) => !s.hardConstraintFailed)
        .toList();
  }

  /// True when the Sun has risen above the configured darkness limit at
  /// [now] — i.e. the observing night is over. This reuses the exact gate the
  /// per-candidate twilight check applies in [_scoreCandidate], so "every
  /// candidate Sun-rejected" and "end of night" are the same condition by
  /// construction. A transient empty-eligible at night (clouds rejecting a
  /// weather constraint, every goal momentarily complete) is NOT end-of-night
  /// because the Sun is still down, so this returns false and the engine only
  /// stops the sequence rather than parking.
  bool _isEndOfNight(DateTime now) {
    final (sunAlt, _) = SkyCalculations.sunAltAz(
      time: now,
      latitudeDegrees: _site.latitudeDegrees,
      longitudeDegrees: _site.longitudeDegrees,
    );
    return sunAlt > _config.maxSunAltitudeDegrees;
  }

  /// Shared handling for both empty paths in [_evaluateOnce] (no candidates at
  /// all, and candidates present but none eligible). Clears the current target,
  /// stops the sequence the autopilot itself dispatched, and — only when it is
  /// genuinely end-of-night (Sun up) and we have not already parked for this
  /// dawn — invokes the distinct end-of-night park hook exactly once.
  ///
  /// Returns the operator-facing sentence to append to this tick's reasoning
  /// when imaging was stopped, or null when the tick changed nothing.
  Future<String?> _handleNoEligibleTarget(DateTime now) async {
    final running = _status.state == SchedulerState.running;
    // Whether the autopilot has a run of its OWN in progress. A tick that
    // stopped unconditionally destroyed any sequence the operator had started
    // by hand — mid-exposure, every 60 s, all night — because the autopilot
    // shares one executor with the manual Start button and had no idea which
    // run it was ending.
    final ownedTarget = _status.currentTargetName;
    final ownsRun = _status.currentTargetId != null;
    if (ownsRun) {
      _updateStatus(_status.copyWith(clearCurrentTarget: true));
    }
    if (!running) return null;

    if (_isEndOfNight(now)) {
      // Starting the autopilot before sunset is an ordinary pre-arm workflow.
      // Until this run has actually dispatched a target there is no completed
      // observing night to safe, so wait quietly for a later eligible tick.
      if (!_dispatchedSinceStart) return null;
      // Dawn: park the mount so it stops tracking into the ground/daylight.
      // Guarded so we park once per dawn, not on every subsequent tick while
      // the Sun stays up. Park first (the safety-critical action), then the
      // stopSequence below is redundant on the park path but harmless — the
      // executor is idempotent on stop and parkForEndOfNight already pauses.
      if (!_parkedForEndOfNight) {
        _parkedForEndOfNight = true;
        await _sequenceSink.parkForEndOfNight();
        return 'The observing night is over — parked the mount and ended '
            'unattended imaging.';
      }
      return null;
    }

    // Transient no-eligible mid-night (clouds, all goals momentarily
    // complete): stop the autopilot's OWN sequence but never park — the night
    // isn't over and the next tick may re-dispatch. A run the operator started
    // by hand is not ours to end.
    if (!ownsRun) return null;
    await _sequenceSink.stopSequence();
    return 'Stopped ${ownedTarget ?? 'imaging'} — no target passes the '
        'scheduler right now; the next evaluation will re-check.';
  }

  /// [decision] with one more line on its reasoning list — how a side effect
  /// the pure [_evaluate] cannot know about (stopping imaging, parking at
  /// dawn) reaches the operator, since the decision panel renders `reasoning`
  /// and nothing else explains itself.
  SchedulerDecision _withReasoning(SchedulerDecision decision, String line) {
    return SchedulerDecision(
      chosenTargetId: decision.chosenTargetId,
      chosenTargetName: decision.chosenTargetName,
      score: decision.score,
      reasoning: [...decision.reasoning, line],
      scoredCandidates: decision.scoredCandidates,
      rejected: decision.rejected,
      evaluatedAt: decision.evaluatedAt,
      isSwitch: decision.isSwitch,
    );
  }

  /// Returns true if the candidate has an enabled scheduledWindow
  /// constraint whose absolute UTC range contains [now]. Caller uses this
  /// to bypass hysteresis and to surface the forced-selection state on
  /// the decision panel.
  bool _hasActiveScheduledWindow(SchedulerCandidate c, DateTime now) {
    for (final ct in c.constraints.where((x) => x.enabled)) {
      if (ct.kind != TargetConstraintKind.scheduledWindow) continue;
      final sw = ct.scheduledWindow;
      if (sw == null) continue;
      if (sw.containsUtc(now)) return true;
    }
    return false;
  }

  /// Build a [RejectedCandidate] entry that the UI will render under the
  /// "Other candidates considered" section. The reason text is derived
  /// from the same hard-constraint / soft-score logic that filtered them
  /// out of [_scoreCandidate].
  RejectedCandidate _buildRejection(
    TargetScore s, {
    required double chosenScore,
    String? primaryReasonOverride,
  }) {
    final String primary;
    if (primaryReasonOverride != null) {
      primary = primaryReasonOverride;
    } else if (s.hardConstraintFailed) {
      primary = _summarizeRejection(s.rejectionReasons);
    } else {
      // Eligible-but-lower-scoring. Expose the score gap as a percentage
      // so operators can sanity-check tight calls.
      if (chosenScore > 0) {
        final pct = (s.totalScore / chosenScore * 100).clamp(0, 999);
        primary =
            'lower score than chosen (${pct.toStringAsFixed(0)}% of winner)';
      } else {
        primary = 'lower score than chosen';
      }
    }
    return RejectedCandidate(
      targetId: s.targetId,
      targetName: s.targetName,
      score: s.totalScore,
      primaryReason: primary,
      hardConstraintFailures: List<String>.unmodifiable(s.rejectionReasons),
      factors: List<ScoreFactor>.unmodifiable(s.factors),
    );
  }

  /// Map the first per-constraint failure into a compact operator-facing
  /// chip. Falls back to the raw text when no shorter form fits.
  String _summarizeRejection(List<String> reasons) {
    if (reasons.isEmpty) return 'rejected';
    final first = reasons.first;
    if (first.contains('altitude') && first.contains('below site minimum')) {
      return 'below horizon';
    }
    if (first.contains('altitude') && first.contains('horizon profile')) {
      return 'behind custom horizon';
    }
    if (first.contains('moon illumination')) {
      return first; // already includes the "X% > Y%" detail
    }
    if (first.contains('outside time window')) {
      return first;
    }
    if (first.contains('filter')) {
      return 'required filter not in wheel';
    }
    if (first.contains('goals complete')) {
      return 'all integration goals complete';
    }
    return first;
  }

  /// Public so tests and the UI's "Preview" button can compute a decision
  /// without mutating state. Pass a pre-fetched candidate list.
  TargetScore scoreCandidate(SchedulerCandidate c, DateTime now) =>
      _scoreCandidate(c, now);

  TargetScore _scoreCandidate(SchedulerCandidate c, DateTime now) {
    final rejections = <String>[];

    // Altitude / azimuth.
    final (alt, az) = _calculateAltAz(
      raHours: c.raHours,
      decDegrees: c.decDegrees,
      time: now,
    );

    // Hard constraint: minimum altitude.
    if (alt < _config.minAltitudeDegrees) {
      rejections.add(
        'altitude ${alt.toStringAsFixed(1)}° below site minimum ${_config.minAltitudeDegrees.toStringAsFixed(1)}°',
      );
    }

    // Hard constraint: twilight / Sun altitude. Never image while the Sun is
    // above the configured darkness threshold. This makes the engine wait for
    // darkness at dusk and stop at dawn (the empty-eligible path in
    // _evaluateOnce stops the running sequence once every candidate is
    // rejected). Previously the engine scored at `now` with no Sun awareness
    // and would slew + expose in full daylight.
    final (sunAlt, _) = SkyCalculations.sunAltAz(
      time: now,
      latitudeDegrees: _site.latitudeDegrees,
      longitudeDegrees: _site.longitudeDegrees,
    );
    if (sunAlt > _config.maxSunAltitudeDegrees) {
      rejections.add(
        'Sun ${sunAlt.toStringAsFixed(1)}° above darkness limit ${_config.maxSunAltitudeDegrees.toStringAsFixed(1)}° — too bright to image',
      );
    }

    // Hard constraint: equipment / filter availability.
    final remainingByGoal = <IntegrationGoalProgress>[];
    for (var i = 0; i < c.goals.length; i++) {
      remainingByGoal.add(
        IntegrationGoalProgress(
          goal: c.goals[i],
          capturedCount: c.capturedCounts[i],
        ),
      );
    }
    final stillNeeded = remainingByGoal
        .where((p) => p.remainingFrames > 0)
        .toList();
    if (stillNeeded.isEmpty && c.goals.isNotEmpty) {
      rejections.add('all integration goals complete');
    }
    final filtersOnEquipmentLower = c.availableFilters
        .map((f) => f.toLowerCase())
        .toSet();
    final hasUsableGoal = stillNeeded.isEmpty
        ? c
              .goals
              .isEmpty // no goals at all is fine - free-form imaging
        : stillNeeded.any(
            (p) =>
                // An EMPTY goal filter means "no filter requirement", which is
                // what a rig with no filter wheel has to be able to express.
                // Matching it against the wheel's filter list rejected it —
                // `availableFilters` is empty on such a rig, so `contains('')`
                // is false — and the effect was inverted: a wheel-less target
                // that scheduled fine free-form became UNSCHEDULABLE the moment
                // the operator followed the empty-state prompt and added a goal.
                p.goal.filter.isEmpty ||
                filtersOnEquipmentLower.contains(p.goal.filter.toLowerCase()),
          );
    if (c.goals.isNotEmpty && !hasUsableGoal && stillNeeded.isNotEmpty) {
      rejections.add(
        'required filter(s) not in equipment wheel (${stillNeeded.map((p) => p.goal.filter).toSet().join(", ")})',
      );
    }

    // Hard constraint: time-window / moon / horizon.
    final localTime = now.toUtc().add(_site.localOffset);
    double scheduledWindowBoost = 0.0;
    for (final ct in c.constraints.where((x) => x.enabled)) {
      switch (ct.kind) {
        case TargetConstraintKind.timeWindow:
          if (ct.timeWindow != null &&
              !ct.timeWindow!.containsLocal(localTime)) {
            rejections.add(
              'outside time window ${ct.timeWindow!.startMinutes ~/ 60}:${(ct.timeWindow!.startMinutes % 60).toString().padLeft(2, '0')}-${ct.timeWindow!.endMinutes ~/ 60}:${(ct.timeWindow!.endMinutes % 60).toString().padLeft(2, '0')}',
            );
          }
          break;
        case TargetConstraintKind.moonIlluminationMax:
          final moon = _moonPosition(now);
          if (ct.moonIlluminationMax != null &&
              moon.illumination > ct.moonIlluminationMax!) {
            rejections.add(
              'moon illumination ${(moon.illumination * 100).toStringAsFixed(0)}% exceeds max ${(ct.moonIlluminationMax! * 100).toStringAsFixed(0)}%',
            );
          }
          break;
        case TargetConstraintKind.moonSeparationMin:
          final minSep = ct.moonSeparationMinDeg;
          if (minSep != null) {
            final moon = _moonPosition(now);
            final sep = _angularSeparation(
              ra1Hours: c.raHours,
              dec1Degrees: c.decDegrees,
              ra2Hours: moon.raHours,
              dec2Degrees: moon.decDegrees,
            );
            if (sep < minSep) {
              rejections.add(
                'moon separation ${sep.toStringAsFixed(0)}° below minimum '
                '${minSep.toStringAsFixed(0)}° '
                '(moon ${(moon.illumination * 100).toStringAsFixed(0)}% lit)',
              );
            }
          }
          break;
        case TargetConstraintKind.customHorizon:
          final profile = c.horizonProfiles[ct.customHorizonId];
          if (profile == null) {
            rejections.add(
              'horizon profile ${ct.customHorizonId} not loaded (orchestrator bug)',
            );
          } else {
            final minAlt = profile.minAltitudeAt(az);
            if (alt < minAlt) {
              rejections.add(
                'altitude ${alt.toStringAsFixed(1)}° below horizon profile "${profile.name}" (${minAlt.toStringAsFixed(1)}° at az ${az.toStringAsFixed(0)}°)',
              );
            }
          }
          break;
        case TargetConstraintKind.scheduledWindow:
          // Never a hard-fail — the window adds a score boost during its
          // active range and is silent otherwise. Selection forcing is
          // handled in _evaluateOnce via [_hasActiveScheduledWindow]. We
          // accumulate the boost here so an inactive window contributes
          // nothing.
          final sw = ct.scheduledWindow;
          if (sw != null && sw.containsUtc(now)) {
            scheduledWindowBoost += sw.priorityBoost.clamp(0.0, 1.0);
          }
          break;
      }
    }

    // Compute factors regardless so the UI can show them even on rejected
    // candidates.
    final altitudeFactor = _altitudeFactor(alt);
    final meridianFactor = _meridianFactor(raHours: c.raHours, now: now);
    final (moonFactor, moonDetail) = _moonFactor(
      raHours: c.raHours,
      decDegrees: c.decDegrees,
      now: now,
    );
    final (timeFactor, timeDetail) = _timeRemainingFactor(
      raHours: c.raHours,
      decDegrees: c.decDegrees,
      now: now,
    );
    final filterFactor = _filterCoverageFactor(
      remainingByGoal,
      c.availableFilters,
    );
    final priorityFactor = _userPriorityFactor(c.userPriority);

    final w = _config.weights;
    final factors = <ScoreFactor>[
      ScoreFactor(
        name: 'altitude',
        value: altitudeFactor,
        weight: w.altitude,
        weighted: altitudeFactor * w.altitude,
        detail: 'alt ${alt.toStringAsFixed(1)}°',
      ),
      ScoreFactor(
        name: 'meridian',
        value: meridianFactor,
        weight: w.meridian,
        weighted: meridianFactor * w.meridian,
      ),
      ScoreFactor(
        name: 'moon',
        value: moonFactor,
        weight: w.moon,
        weighted: moonFactor * w.moon,
        detail: moonDetail,
      ),
      ScoreFactor(
        name: 'timeRemaining',
        value: timeFactor,
        weight: w.timeRemaining,
        weighted: timeFactor * w.timeRemaining,
        detail: timeDetail,
      ),
      ScoreFactor(
        name: 'filterCoverage',
        value: filterFactor,
        weight: w.filterCoverage,
        weighted: filterFactor * w.filterCoverage,
      ),
      ScoreFactor(
        name: 'userPriority',
        value: priorityFactor,
        weight: w.userPriority,
        weighted: priorityFactor * w.userPriority,
      ),
      if (scheduledWindowBoost > 0)
        ScoreFactor(
          name: 'scheduledWindow',
          value: scheduledWindowBoost.clamp(0.0, 1.0),
          weight: 1.0,
          weighted: scheduledWindowBoost.clamp(0.0, 1.0),
          detail: 'forced-window boost',
        ),
    ];
    // Fold the soft factors into a total via the shared DECIDE aggregation
    // contract. The engine uses ADDITIVE mode (Σ of weighted factors, NOT
    // divided by the weight-sum) — that is the historical behaviour and is
    // intentionally different from the planner/node NORMALIZED model. Only the
    // aggregation primitive is shared; the weights and factor set are
    // unchanged.
    final total = WeightedScore.total([
      for (final f in factors)
        WeightedFactor(name: f.name, value: f.value, weight: f.weight),
    ], mode: WeightedScoreMode.additive);

    return TargetScore(
      targetId: c.targetId,
      targetName: c.name,
      totalScore: total,
      factors: factors,
      hardConstraintFailed: rejections.isNotEmpty,
      rejectionReasons: rejections,
    );
  }

  /// Altitude factor: 0 at minAltitude, 1 at 90°, sin² ramp between.
  double _altitudeFactor(double altDeg) {
    final minAlt = _config.minAltitudeDegrees;
    if (altDeg <= minAlt) return 0.0;
    if (altDeg >= 90.0) return 1.0;
    final normalized = (altDeg - minAlt) / (90.0 - minAlt);
    final s = math.sin(normalized * math.pi / 2);
    return s * s;
  }

  /// Meridian-proximity factor: 1 at the meridian, falling linearly to 0
  /// when hour angle reaches ±6h.
  double _meridianFactor({required double raHours, required DateTime now}) {
    final lst = _localSiderealTime(now);
    var ha = lst - raHours;
    while (ha > 12) {
      ha -= 24;
    }
    while (ha < -12) {
      ha += 24;
    }
    final absH = ha.abs();
    if (absH >= 6.0) return 0.0;
    return 1.0 - (absH / 6.0);
  }

  /// Moon factor: penalty for being close to the moon, weighted by lunar
  /// illumination. Returns 1.0 when target is outside the avoidance
  /// radius OR the moon is dark (illumination ~0).
  (double, String) _moonFactor({
    required double raHours,
    required double decDegrees,
    required DateTime now,
  }) {
    final moon = _moonPosition(now);
    final sep = _angularSeparation(
      ra1Hours: raHours,
      dec1Degrees: decDegrees,
      ra2Hours: moon.raHours,
      dec2Degrees: moon.decDegrees,
    );
    final radius = _config.moonAvoidanceRadiusDegrees;
    if (sep >= radius) {
      return (
        1.0,
        'sep ${sep.toStringAsFixed(0)}° ill ${(moon.illumination * 100).toStringAsFixed(0)}%',
      );
    }
    final closeness = 1.0 - (sep / radius);
    final penalty = closeness * moon.illumination;
    final factor = (1.0 - penalty).clamp(0.0, 1.0);
    return (
      factor,
      'sep ${sep.toStringAsFixed(0)}° ill ${(moon.illumination * 100).toStringAsFixed(0)}%',
    );
  }

  /// Time-remaining factor: how many hours the target stays above the
  /// engine's min altitude tonight, divided by 10 (saturating at 1.0).
  /// Targets with <30 minutes left score very low.
  (double, String) _timeRemainingFactor({
    required double raHours,
    required double decDegrees,
    required DateTime now,
  }) {
    final endHorizon = _hoursUntilSettingBelowMin(
      raHours: raHours,
      decDegrees: decDegrees,
      now: now,
    );
    final hours = endHorizon.clamp(0.0, 10.0);
    final factor = hours / 10.0;
    return (factor, 'visible ${hours.toStringAsFixed(2)} h');
  }

  /// Hours from `now` until the target's altitude drops below min.
  /// Returns 0 if already below, 24 if circumpolar above the threshold.
  double _hoursUntilSettingBelowMin({
    required double raHours,
    required double decDegrees,
    required DateTime now,
  }) {
    final lat = _site.latitudeDegrees * math.pi / 180.0;
    final dec = decDegrees * math.pi / 180.0;
    final minAlt = _config.minAltitudeDegrees * math.pi / 180.0;

    final sinThresh = math.sin(minAlt);
    final center = math.sin(dec) * math.sin(lat);
    final amplitude = (math.cos(dec) * math.cos(lat)).abs();
    final minSin = center - amplitude;
    final maxSin = center + amplitude;
    if (maxSin < sinThresh) return 0.0;
    if (minSin >= sinThresh) return 24.0;

    final denominator = math.cos(dec) * math.cos(lat);
    if (denominator.abs() < 1e-12) return 24.0;
    final cosH = (sinThresh - center) / denominator;
    if (cosH <= -1.0) return 24.0;
    if (cosH >= 1.0) return 0.0;
    final haHorizon = math.acos(cosH) * 180.0 / math.pi / 15.0; // hours

    final lst = _localSiderealTime(now);
    var ha = lst - raHours;
    while (ha > 12) {
      ha -= 24;
    }
    while (ha < -12) {
      ha += 24;
    }
    if (ha.abs() >= haHorizon) return 0.0;
    final hoursToSet = (haHorizon - ha) * 0.9972695663;
    if (hoursToSet < 0) return 0.0;
    return hoursToSet;
  }

  double _localSiderealTime(DateTime time) =>
      SkyCalculations.localSiderealTimeHours(time, _site.longitudeDegrees);

  /// Normalise a filter name for an emitted node: the unfiltered sentinel (an
  /// empty or whitespace name) must reach the executor as null.
  static String? _nodeFilter(String? name) =>
      (name == null || name.trim().isEmpty) ? null : name;

  /// Filter coverage factor: fraction of total goal frames still needed,
  /// gated by whether the equipment wheel can produce those filters.
  /// 1.0 when the target has the most uncaptured data available; 0.0 when
  /// fully imaged. Targets with no goals at all score a neutral 0.5 so
  /// they aren't ranked above an actively-incomplete target.
  double _filterCoverageFactor(
    List<IntegrationGoalProgress> progress,
    List<String> availableFilters,
  ) {
    if (progress.isEmpty) return 0.5;
    final available = availableFilters.map((f) => f.toLowerCase()).toSet();
    var totalNeeded = 0;
    var totalGoal = 0;
    for (final p in progress) {
      totalGoal += p.goal.frameCount;
      // Same rule as the admission check and buildSequenceForCandidate: an
      // empty goal filter means "no filter requirement". Testing it for
      // membership of the wheel's filter list scored an unfiltered goal on a
      // wheel-less rig as already-complete, so the autopilot ranked a target
      // it had never imaged below one that was finished.
      if (p.goal.filter.isNotEmpty &&
          !available.contains(p.goal.filter.toLowerCase())) {
        continue;
      }
      totalNeeded += p.remainingFrames;
    }
    if (totalGoal <= 0) return 0.5;
    return (totalNeeded / totalGoal).clamp(0.0, 1.0);
  }

  /// User priority factor: priority field (assumed 0..10) scaled into [0, 1].
  /// Values outside 0..10 are clamped — they're still meaningful, just
  /// saturated.
  double _userPriorityFactor(int priority) {
    final v = priority.clamp(0, 10);
    return v / 10.0;
  }

  void _updateStatus(SchedulerStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _publishDecision(SchedulerDecision decision) {
    _lastDecision = decision;
    if (!_decisionController.isClosed) {
      _decisionController.add(decision);
    }
  }

  /// Build a single-target sequence: slew → center → expose loop on the
  /// currently most-needed filter. This is what the engine hands to the
  /// SequencerService when it picks a target.
  Sequence buildSequenceForCandidate(SchedulerCandidate c) {
    final goalProgress = <IntegrationGoalProgress>[];
    for (var i = 0; i < c.goals.length; i++) {
      goalProgress.add(
        IntegrationGoalProgress(
          goal: c.goals[i],
          capturedCount: c.capturedCounts[i],
        ),
      );
    }
    final pending =
        goalProgress
            .where((p) => p.remainingFrames > 0)
            .where(
              // Same rule as the admission check above: an empty goal filter is
              // "no filter needed", not "a filter the wheel lacks". Dropping it
              // here would admit the candidate and then silently discard the
              // operator's exposure and frame count, falling back to a
              // defensive default frame.
              (p) =>
                  p.goal.filter.isEmpty ||
                  c.availableFilters
                      .map((f) => f.toLowerCase())
                      .contains(p.goal.filter.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final cmp = b.remainingFrames.compareTo(a.remainingFrames);
            if (cmp != 0) return cmp;
            return b.goal.priority.compareTo(a.goal.priority);
          });

    const uuid = Uuid();
    final targetId = uuid.v4();
    final slewId = uuid.v4();
    final centerId = uuid.v4();

    final nodes = <String, SequenceNode>{};

    final exposureIds = <String>[];

    final rowsToDispatch = c.isMosaicTarget
        ? pending
        : pending.isEmpty
        ? const <IntegrationGoalProgress>[]
        : [pending.first];

    if (rowsToDispatch.isEmpty) {
      // No goals or all complete; build a one-shot 30s luminance to keep
      // the operator productive. This is rare because the engine rejects
      // candidates with no usable goals, but we handle it defensively.
      final expId = uuid.v4();
      exposureIds.add(expId);
      nodes[expId] = ExposureNode(
        id: expId,
        name: 'Expose',
        durationSecs: 30.0,
        count: 1,
        filter: _nodeFilter(
          c.availableFilters.isNotEmpty ? c.availableFilters.first : null,
        ),
      );
    } else {
      for (final row in rowsToDispatch) {
        final expId = uuid.v4();
        exposureIds.add(expId);
        // `filter: null` — not the empty sentinel — is the wire contract for an
        // unfiltered row: it is what suppresses the filter-change instruction
        // and makes the executor render the ${filter} filename token as
        // "nofilter". Passing '' through emitted a node that asked a wheel-less
        // rig to select a filter named "".
        final unfiltered = row.goal.filter.trim().isEmpty;
        nodes[expId] = ExposureNode(
          id: expId,
          name: unfiltered ? 'Expose' : 'Expose ${row.goal.filter}',
          durationSecs: row.goal.exposureSeconds,
          count: row.remainingFrames,
          filter: unfiltered ? null : row.goal.filter,
        );
      }
    }

    nodes[slewId] = SlewNode(
      id: slewId,
      name: 'Slew to ${c.name}',
      useTargetCoords: true,
    );
    nodes[centerId] = CenterNode(
      id: centerId,
      name: 'Center on ${c.name}',
      useTargetCoords: true,
    );

    final target = TargetHeaderNode(
      id: targetId,
      name: c.name,
      targetName: c.name,
      raHours: c.raHours,
      decDegrees: c.decDegrees,
      priority: c.userPriority,
      childIds: [slewId, centerId, ...exposureIds],
      // Attribute every captured frame to this DB target row so
      // IntegrationGoalService.capturedFrameCount (WHERE target_id = ?)
      // advances and goals complete — otherwise frames land with
      // target_id=NULL and the engine images this one target all night.
      catalogTargetId: c.targetId,
    );
    nodes[targetId] = target;

    return Sequence.create(
      name: 'Scheduler / ${c.name}',
      description:
          'Auto-generated by the dynamic scheduler at ${_clock().toIso8601String()}',
      nodes: nodes,
      rootNodeId: targetId,
    );
  }
}
