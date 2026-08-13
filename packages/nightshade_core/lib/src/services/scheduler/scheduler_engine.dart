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
part 'scheduler_engine/evaluation.dart';
part 'scheduler_engine/scoring.dart';

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

  /// Public so tests and the UI's "Preview" button can compute a decision
  /// without mutating state. Pass a pre-fetched candidate list.
  TargetScore scoreCandidate(SchedulerCandidate c, DateTime now) =>
      _scoreCandidate(c, now);

  double _localSiderealTime(DateTime time) =>
      SkyCalculations.localSiderealTimeHours(time, _site.longitudeDegrees);

  /// Normalise a filter name for an emitted node: the unfiltered sentinel (an
  /// empty or whitespace name) must reach the executor as null.
  static String? _nodeFilter(String? name) =>
      (name == null || name.trim().isEmpty) ? null : name;

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
