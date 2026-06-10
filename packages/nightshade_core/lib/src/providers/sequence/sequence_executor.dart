import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../backend/nightshade_backend.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/imaging/imaging_models.dart';
import '../../models/sequence/instruction_progress_detail.dart';
import '../../models/sequence/sequence_models.dart';
import '../../models/settings/app_settings.dart'
    show ObserverLocation, SafetyFailMode;
import '../../services/disk_space_guard.dart';
import '../../services/live_stacking_broadcast_service.dart';
import '../../services/live_stacking_service.dart' show LiveStackingConfig;
import '../../services/safe_rig_service.dart';
import '../../services/smart_night/guide_rms_collector.dart';
import '../../services/capture_preview_loader.dart';
import '../../services/logging_service.dart';
import '../thumbnail_sidecar_provider.dart';
import '../backend_provider.dart';
import '../database_provider.dart'
    show guideRmsHistoryDaoProvider, imagesDaoProvider;
import '../../database/daos/campaigns_dao.dart' show campaignsDaoProvider;
import '../disk_space_provider.dart';
import '../equipment_provider.dart';
// Wave 5 Agent 2 — sky-brightness poll reads the tracker via this
// provider (defined in flat_wizard_provider since the tracker is
// shared between flat-wizard and adaptive-exposure paths).
import '../flat_wizard_provider.dart' show skyBrightnessTrackerProvider;
import '../imaging_provider.dart';
import '../live_stacking_provider.dart';
import '../meridian_flip_provider.dart';
// Wave 6 Pack P — plugin-node dispatcher abstraction.
import '../plugin_node_dispatcher.dart';
import '../replay_debug_provider.dart';
import '../profiles_provider.dart';
import '../sequence_provider.dart'
    show
        currentSequenceProvider,
        sequenceExecutionStateProvider,
        sequenceProgressProvider;
import '../sequence_stats_provider.dart';
import '../session_handoff_provider.dart'
    show sessionCarryOverProvider, sessionHandoffDecisionProvider;
import '../../services/session_handoff_service.dart'
    show SessionCarryOver, SessionHandoffDecision;
import '../session_provider.dart';
import '../settings_provider.dart';
// Wave 5.5 — session-lifecycle hooks: optical-train baseline capture,
// post-session diagnostics summary, NotificationRouter active-sequence
// tracking, USB disconnect aggregation.
import '../../services/optical_train_diagnostics_service.dart'
    show OpticalTrainDiagnostics;
import '../notification_router_provider.dart';
import '../optical_train_diagnostics_provider.dart';
import '../preflight_providers.dart';
import '../science_provider.dart'
    show sessionPsfTilesProvider, sessionResidualVectorsProvider;
import '../usb_disconnect_log_provider.dart';
import 'sequence_validation.dart' as validation;
import 'sequencer_defaults.dart';
import 'sequence_executor/frame_attribution.dart';

part 'sequence_executor/serialization_operations.dart';
part 'sequence_executor/runtime_config_operations.dart';
part 'sequence_executor/event_operations.dart';
part 'sequence_executor/session_diagnostics_operations.dart';
part 'sequence_executor/checkpoint_watchdog_operations.dart';

// =============================================================================
// ETA SMOOTHING CONFIGURATION
// =============================================================================

/// Number of recent per-frame durations retained for the smoothed ETA.
/// Older samples are evicted FIFO. Larger window = smoother but slower to
/// react to genuine cadence changes (e.g. switching from 60s subs to 600s).
const int kEtaWindowSize = 10;

/// Exponential moving average weight applied to the most recent frame.
/// `0.0` would freeze on the first sample; `1.0` would always use the most
/// recent. `0.3` is the balance that absorbs transient outliers (downloads,
/// occasional dither stalls) while still tracking real shifts in cadence.
const double kEtaEmaAlpha = 0.3;

/// Temperature drift threshold for post-session cooler stability notes.
///
/// A one-degree band is tight enough to catch a cooler that is cycling or
/// saturated, while avoiding noise from normal sub-degree sensor wobble.
const double kCoolerSetpointBandDegC = 1.0;

/// Sequence executor that manages execution.
///
/// The provider wires `ref.onDispose(executor.dispose)` so owned timers and
/// the native event subscription are guaranteed to be torn down with the
/// provider lifetime, even if a sequence is invalidated mid-run.
final sequenceExecutorProvider = Provider<SequenceExecutor>((ref) {
  final executor = SequenceExecutor(ref);
  // Owned timers/subscriptions must be torn down with the provider lifetime —
  // otherwise an invalidation mid-sequence leaks the periodic progress timer,
  // the checkpoint timer, and the native event stream subscription past the
  // disposed Ref. stop() handles the running case; this handles teardown.
  ref.onDispose(executor.dispose);
  return executor;
});

class SequenceExecutor {
  final Ref _ref;
  Timer? _progressTimer;
  DateTime? _startTime;
  bool _isPaused = false;
  StreamSubscription? _nativeEventSubscription;
  StreamSubscription<DiskSpaceWatchdogEvent>? _diskWatchdogSubscription;
  Timer? _checkpointTimer;
  bool _runFinalized = false;
  bool _pauseResumeInProgress = false;

  /// Live-stacking auto-feed (2026-06-04 follow-up): whether the live
  /// stacker + LAN broadcast have been armed for the *current* run yet.
  /// The first accepted frame of a run that contains an enabled
  /// `LiveStackingNode` arms both (the frame becomes the stack
  /// reference); every later accepted frame is added to the existing
  /// stack. Reset to `false` in `start()` and torn down in `stop()` so a
  /// new run never inherits the previous run's reference frame.
  bool _liveStackingArmedForRun = false;

  /// Guards against concurrent re-entrant accepted-frame feeds. FFI
  /// stacking calls are async; without this a fast exposure cadence could
  /// interleave an `addFrameFromFile` with the initial `startFromFile`
  /// and corrupt the reference. We serialise feeds by chaining onto this
  /// future. `null` when no feed is in flight.
  Future<void>? _liveStackingFeedChain;

  /// Wave 5 Agent 2 — periodic poller that reads the latest sky brightness
  /// from `skyBrightnessTrackerProvider` and pushes it to the executor.
  /// The cadence is intentionally generous (10s) because sky brightness
  /// changes slowly; running it faster would just add CPU noise for no
  /// adaptive-exposure benefit.
  Timer? _skyBrightnessPollTimer;

  /// Last value pushed to the executor; we suppress redundant pushes
  /// so the runtime config event stream is quiet when conditions are
  /// stable.
  double? _lastPushedSkyMag;

  /// Sliding window of recent per-frame durations (seconds). Bounded to
  /// [kEtaWindowSize]; older samples are dropped FIFO when full.
  final Queue<double> _frameDurations = Queue<double>();

  /// Smoothed average secs-per-frame computed via exponential moving average
  /// over [_frameDurations]. `null` until at least one frame has completed.
  double? _smoothedSecsPerFrame;

  /// Last completed-frame count we observed; used to detect when a new
  /// frame finished so we can extract its duration without storing
  /// per-frame timestamps separately.
  int _lastFrameCount = 0;

  /// Wall-clock seconds at which the last completed frame was observed.
  /// Combined with `_startTime` and `_lastFrameCount` to derive the
  /// duration of each newly-completed frame inside `_recordFrameDuration`.
  double? _lastFrameElapsedSecs;

  /// Subscriptions for propagating settings changes to the backend mid-sequence
  final List<ProviderSubscription> _settingsSubscriptions = [];

  /// Wave 5.5 — sequence id of the currently running sequence. Held so
  /// the post-session diagnostics summary and the NotificationRouter
  /// override know which sequence just finished even after
  /// `currentSequenceProvider` has been cleared by the UI.
  String? _activeSequenceId;

  /// Wave 5.5 — wall-clock start time of the current run. Used to
  /// compute the per-session USB disconnect count when building the
  /// post-session diagnostics summary. Distinct from `_startTime`
  /// (which is reset on pause/resume); this one survives until the
  /// post-session hooks have run.
  DateTime? _sessionStartedAt;

  /// Wave 5.5 — pre-session optical-train snapshot captured at
  /// `start()`. Persists across the run so the post-session finalizer
  /// can publish the baseline alongside the post-session diagnostics
  /// (so the dialog can render "pre" and "post" side by side, even
  /// after the in-memory baseline provider has been overwritten by the
  /// next run).
  OpticalTrainBaseline? _sessionStartBaseline;
  LoggingService get _logger => _ref.read(loggingServiceProvider);

  SequenceExecutor(this._ref);

  /// Check if native execution is enabled in settings
  bool get _useNativeExecution {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useNativeExecution ?? false;
    } catch (error, stack) {
      _logger.warning(
        'Failed to read useNativeExecution setting; defaulting to false: $error\n$stack',
        source: 'SequenceExecutor',
      );
      return false;
    }
  }

  /// Check if simulation mode is enabled in settings
  bool get _useSimulationMode {
    if (kReleaseMode) {
      return false;
    }
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useSimulationMode ?? false;
    } catch (error, stack) {
      _logger.warning(
        'Failed to read useSimulationMode setting; defaulting to false: $error\n$stack',
        source: 'SequenceExecutor',
      );
      return false;
    }
  }

  /// Test-only entry point that returns the JSON the executor will send
  /// to the Rust backend. Exposed so unit tests can assert AppSettings
  /// defaults propagate correctly (audit-handoff §2.1 WIRE-UP #4/#5).
  @visibleForTesting
  String sequenceToJsonForTest(Sequence sequence) => _sequenceToJson(sequence);

  /// Wave 5.5 — test entry point for the session-start hooks. Lets
  /// integration tests exercise the optical-train baseline capture +
  /// NotificationRouter override + sessionStart timestamp without
  /// spinning up the full `start()` pipeline (which requires a current
  /// sequence, settings, validation, native backend, …).
  @visibleForTesting
  void captureSessionStartHooksForTest(String sequenceId) =>
      _captureSessionStartHooks(sequenceId);

  /// Wave 5.5 — test entry point for the session-end hooks.
  @visibleForTesting
  void captureSessionEndHooksForTest() => _captureSessionEndHooks();

  /// Wave 6 Pack P — test entry point that pumps a synthesised
  /// `NightshadeEvent` through the same handler the live native event
  /// subscription uses. Lets unit tests exercise the FrameAccepted /
  /// FrameRejected / PluginNodeRequested handlers without spinning up
  /// the full Rust backend.
  @visibleForTesting
  void handleSequencerEventForTest(NightshadeEvent event) =>
      _handleSequencerEvent(event);

  /// Wave 7.5 — test entry point for the session-handoff carry-over
  /// seed. Lets tests exercise the `Resume` / `Restart` / `ContinueNew`
  /// branches against a mock backend without driving a full sequence
  /// start (which requires Rust, validation, and live settings).
  @visibleForTesting
  Future<void> seedIntegrationCarryOverFromHandoffForTest(
    NightshadeBackend backend,
    Sequence sequence,
  ) => _seedIntegrationCarryOverFromHandoff(backend, sequence);

  /// Convert Dart sequence to JSON for native executor
  ///
  /// Why: this is the point where per-sequence and per-node values are
  /// combined with global AppSettings defaults. Per-node values always win;
  /// AppSettings is consulted only when the node provides no explicit value
  /// (audit-handoff §2.1 WIRE-UP items #4 and #5).
  Future<validation.ValidationResult> validateSequenceForStart(
    Sequence sequence,
  ) async {
    final validator = _ref.read(validation.sequenceValidatorProvider);
    return validator.validate(sequence);
  }

  /// Backwards-compatible structural-only validator. Kept because external
  /// callers (UI badges, tests) still depend on the sync semantics. Do
  /// NOT use from new code: this skips equipment / disk-space / dark-
  /// library checks.
  List<validation.ValidationIssue> validateSequence(Sequence sequence) =>
      validation.validateSequence(sequence);

  Future<void> start() async {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) {
      throw Exception('No sequence loaded');
    }

    // Audit C3 — full pre-flight pass. Every start path (UI button via
    // sequence_action_service, headless POST /api/sequencer/start,
    // scheduler autopilot) now reaches this code, so they all see the
    // same equipment / disk-space / dark-library / settings checks the
    // pre-flight dialog already enforced.
    final result = await validateSequenceForStart(sequence);
    if (result.hasErrors) {
      // CLAUDE.md: errors are a feature. Surface the entire
      // [ValidationResult] — counts + every issue — so the caller can
      // render all of them. The historical
      // `throw Exception('first error title')` silently dropped the
      // tail and trained users to ignore validation.
      throw validation.SequenceValidationException(result);
    }

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    progressNotifier.setTotals(
      sequence.totalExposures,
      sequence.totalIntegrationSecs,
    );
    progressNotifier.updateState(SequenceExecutionState.running);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    final sessionNotifier = _ref.read(sessionStateProvider.notifier);
    // Audit C3 — pick option (a): one sequence run == one session. The
    // session row is labelled with the sequence name (which is what the
    // user typed in the sequencer toolbar). Per-target coordinates
    // belong to per-target child rows that the scheduler emits as it
    // walks the tree — we deliberately leave targetRa/targetDec NULL
    // here for multi-target sequences instead of arbitrarily picking
    // targetHeaders.first, which would misrepresent the session in the
    // database. A single-target sequence still gets its coordinates so
    // the historical "single-target session" view keeps working.
    final isSingleTarget = sequence.targetHeaders.length == 1;
    await sessionNotifier.startSession(
      targetName: sequence.name,
      targetRa: isSingleTarget ? sequence.targetHeaders.first.raHours : null,
      targetDec: isSingleTarget
          ? sequence.targetHeaders.first.decDegrees
          : null,
    );
    sessionNotifier.setTotalExposures(sequence.totalExposures);
    final runId = await _ref
        .read(sequenceRunsDaoProvider)
        .startRun(sequenceId: sequence.databaseId, sequenceName: sequence.name);
    _ref.read(currentRunIdProvider.notifier).state = runId;
    _ref.read(liveSequenceStatsProvider.notifier).state = SequenceRunStats();
    _runFinalized = false;
    // A fresh run must never inherit the previous run's live stack /
    // reference frame. Arming happens lazily on the first accepted frame.
    _liveStackingArmedForRun = false;
    _liveStackingFeedChain = null;

    // Wave 8 Replay Debug — stamp the active sequence_runs.id onto the
    // Rust executor so every subsequent emitted DecisionEvent carries
    // the FK. We push it before sequencerStart() so the first
    // "Sequence started" lifecycle decision the executor emits already
    // has the right run id. Failure to push is logged but does not
    // abort the run — the replay log will simply have null run_ids
    // for the affected rows, and our Dart-side `_persistReplayDecision`
    // falls back to `currentRunIdProvider`.
    try {
      await _ref.read(backendProvider).sequencerSetActiveSequenceRunId(runId);
    } catch (e) {
      _logger.warning(
        'Failed to push active sequence_run_id to Rust executor: $e',
        source: 'SequenceExecutor',
      );
    }

    // Wave 5.5 — session-lifecycle hooks.
    //
    // Done AFTER the session notifier + run row exist so the optical
    // train baseline snapshot has a stable dbSessionId to anchor to,
    // and the NotificationRouter override fires while the session is
    // already in "running" state. Each hook is independent — a failure
    // in one is logged but does not abort the start path. The Rust
    // executor must still start even if diagnostics are unavailable.
    _captureSessionStartHooks(sequence.id);

    _startTime = DateTime.now();
    _isPaused = false;
    _resetEtaState();

    // Start progress timer. ETA computation uses an EMA over the last
    // [kEtaWindowSize] frame durations (alpha = [kEtaEmaAlpha]) so a single
    // slow download or fast-completing calibration frame doesn't yank the
    // estimate around.
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed = DateTime.now()
            .difference(_startTime!)
            .inSeconds
            .toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final eta = _computeSmoothedEta(elapsed, progress);
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    _startCheckpointTimer();
    _startDiskSpaceWatchdog();

    if (!_useNativeExecution) {
      _logger.warning(
        'Legacy Dart sequencer path is deprecated; forcing backend executor for deterministic behavior',
        source: 'SequenceExecutor',
      );
    }

    // Always use backend/native sequencer engine to avoid divergent semantics.
    await _startNativeExecution(sequence);
  }

  /// Wait for state change with timeout
  Future<bool> _awaitStateChange(
    SequenceExecutionState expectedState, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      final currentState = _ref.read(sequenceExecutionStateProvider);
      if (currentState == expectedState) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return false;
  }

  Future<void> pause() async {
    if (_pauseResumeInProgress) {
      throw Exception('Pause/Resume operation already in progress');
    }

    final currentState = _ref.read(sequenceExecutionStateProvider);
    if (currentState != SequenceExecutionState.running) {
      throw Exception('Cannot pause: sequence is not running');
    }

    _pauseResumeInProgress = true;

    try {
      final backend = _ref.read(backendProvider);
      await backend.sequencerPause();

      final confirmed = await _awaitStateChange(SequenceExecutionState.paused);
      if (!confirmed) {
        final status = await backend.sequencerGetStatus();
        if (status.state.toLowerCase() != 'paused') {
          throw Exception('Pause operation timed out - state not confirmed');
        }
        _ref
            .read(sequenceProgressProvider.notifier)
            .updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
      }

      _isPaused = true;
    } finally {
      _pauseResumeInProgress = false;
    }
  }

  Future<void> resume() async {
    if (_pauseResumeInProgress) {
      throw Exception('Pause/Resume operation already in progress');
    }

    final currentState = _ref.read(sequenceExecutionStateProvider);
    if (currentState != SequenceExecutionState.paused) {
      throw Exception('Cannot resume: sequence is not paused');
    }

    _pauseResumeInProgress = true;

    try {
      final backend = _ref.read(backendProvider);
      await backend.sequencerResume();

      final confirmed = await _awaitStateChange(SequenceExecutionState.running);
      if (!confirmed) {
        final status = await backend.sequencerGetStatus();
        if (status.state.toLowerCase() != 'running') {
          throw Exception('Resume operation timed out - state not confirmed');
        }
        _ref
            .read(sequenceProgressProvider.notifier)
            .updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
      }

      _isPaused = false;
    } finally {
      _pauseResumeInProgress = false;
    }
  }

  /// Stop the sequencer.
  ///
  /// Audit C3 — checkpoint preservation:
  ///
  /// Historical bug: this method unconditionally called
  /// `discardCheckpoint()` after stopping, which meant a user who paused
  /// the run, walked away, came back hours later and pressed Stop intending
  /// to resume the next night had their resume point silently destroyed.
  ///
  /// Resolution: callers now declare intent via [preserveCheckpoint].
  ///   * The UI Stop button (`SequenceActionService.stop`) passes
  ///     `preserveCheckpoint: true` — operator-initiated stops keep the
  ///     checkpoint so the user can resume later. The session row is
  ///     finalised as `paused-stopped`.
  ///   * The internal completion / error / cancellation finalisers call
  ///     `stop(preserveCheckpoint: false)` (the default) so a naturally-
  ///     ended run does not leave a stale checkpoint that the next
  ///     "resume?" prompt would mistake for an interrupted session.
  ///
  /// Conservative default: callers who do not pass the flag get the
  /// historical destructive behaviour, because every existing call site
  /// (the action service, the headless API, the scheduler) is updated in
  /// the same audit pass and the few remaining bare `stop()` invocations
  /// are deliberate hard-stops (e.g. reset()).
  Future<void> stop({bool preserveCheckpoint = false}) async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    final nativeEventSubscription = _nativeEventSubscription;
    _nativeEventSubscription = null;
    await nativeEventSubscription?.cancel();
    _stopDiskSpaceWatchdog();
    _stopSettingsWatchers();
    _startTime = null;
    _isPaused = false;
    _ref
        .read(sequenceProgressProvider.notifier)
        .updateState(SequenceExecutionState.idle);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;
    // When the operator chose to keep the checkpoint, label the run/
    // session so the post-session reporting tells the truth instead of
    // claiming a clean stop.
    final runStatus = preserveCheckpoint ? 'paused-stopped' : 'stopped';
    _finalizeRun(runStatus);

    // Live-stacking auto-feed teardown: stop the LAN broadcast and the
    // stacking engine so a stopped public-outreach run cannot keep
    // serving a stale stack, and the next run starts from a clean
    // reference. Done after `_finalizeRun` (which records run stats) but
    // before backend teardown.
    await _teardownLiveStacking();

    await _ref
        .read(sessionStateProvider.notifier)
        .endSession(status: runStatus);

    final backend = _ref.read(backendProvider);
    await backend.sequencerStop();

    if (preserveCheckpoint) {
      _logger.info(
        'Stop with preserveCheckpoint=true: leaving checkpoint on disk so '
        'the user can resume later',
        source: 'SequenceExecutor',
      );
      return;
    }

    // Clear checkpoint when stopped gracefully — only when the caller
    // confirmed this is a natural / abort stop with no intent to resume.
    try {
      await backend.discardCheckpoint();
    } catch (e) {
      // Cleanup-only error; the stop itself succeeded.
      _logger.warning(
        'Failed to clear checkpoint on stop: $e',
        source: 'SequenceExecutor',
      );
    }
  }

  Future<void> skip() async {
    final backend = _ref.read(backendProvider);
    await backend.sequencerSkip();
  }

  /// Wave 1.5 Pack A: jump to a specific node by id. Use from the sequence
  /// tree right-click context menu ("Skip to here"). Only meaningful while
  /// the sequence is running — the UI must gate the action on
  /// [SequenceExecutionState.running].
  Future<void> skipToNode(String nodeId) async {
    final backend = _ref.read(backendProvider);
    await backend.sequencerSkipToNode(nodeId);
  }

  /// Reset the sequence execution state without modifying the sequence
  /// configuration. Clears all execution progress (completed exposures, node
  /// statuses) while preserving the sequence structure.
  Future<void> reset() async {
    final currentState = _ref.read(sequenceExecutionStateProvider);

    if (currentState == SequenceExecutionState.running ||
        currentState == SequenceExecutionState.paused) {
      await stop();
    }

    _ref.read(sequenceProgressProvider.notifier).reset();

    final backend = _ref.read(backendProvider);
    try {
      await backend.sequencerReset();
    } catch (e) {
      _logger.warning(
        'Error resetting native sequencer: $e',
        source: 'SequenceExecutor',
      );
      // The Dart-side reset above is the authoritative source of truth.
    }

    try {
      await backend.discardCheckpoint();
    } catch (e) {
      _logger.warning(
        'Error clearing checkpoint on reset: $e',
        source: 'SequenceExecutor',
      );
    }

    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;

    _logger.info(
      'Sequence reset - ready to run from beginning',
      source: 'SequenceExecutor',
    );
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  /// Initialize checkpoint system with app's documents directory
  Future<void> initializeCheckpoints(String documentsPath) async {
    final backend = _ref.read(backendProvider);
    await backend.sequencerSetCheckpointDir(documentsPath);
  }

  /// Check if there's a checkpoint available to resume
  Future<bool> hasCheckpoint() async {
    final backend = _ref.read(backendProvider);
    return await backend.hasCheckpoint();
  }

  /// Get information about the current checkpoint
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final backend = _ref.read(backendProvider);
    return await backend.getCheckpointInfo();
  }

  /// Resume sequence from checkpoint
  ///
  /// The native `resumeFromCheckpoint()` only PREPARES the executor: it
  /// loads the checkpointed sequence, marks already-completed nodes, and
  /// restores trigger state / devices / save path / location from the
  /// snapshot. Execution only begins on the subsequent `sequencerStart()`,
  /// which walks the restored tree and short-circuits the marked nodes.
  /// Skipping that start call leaves the executor Idle while the UI says
  /// "running" — a resumed night that silently never images.
  Future<void> resumeFromCheckpoint() async {
    final backend = _ref.read(backendProvider);

    final info = await backend.getCheckpointInfo();
    if (info == null || !info.canResume) {
      throw Exception('No valid checkpoint to resume from');
    }

    // Prepare the native executor from the snapshot first, so the
    // re-seeding below overrides snapshot values rather than being
    // overwritten by the restore.
    await backend.resumeFromCheckpoint();

    // The snapshot reflects the world at checkpoint time. Settings the
    // user changed since — observer location, safety fail mode, AF
    // cadence, dither, grading thresholds — must win: the W1 daylight
    // gate and meridian-flip hour-angle math run off this location.
    final settings = _ref.read(appSettingsProvider).valueOrNull;
    if (settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0)) {
      await backend.setLocation(
        ObserverLocation(
          latitude: settings.latitude,
          longitude: settings.longitude,
          elevation: settings.elevation,
        ),
      );
    }
    if (kReleaseMode) {
      await backend.sequencerSetSimulationMode(false);
    } else {
      await backend.sequencerSetSimulationMode(_useSimulationMode);
    }
    if (settings != null) {
      await backend.sequencerSetSafetyFailMode(
        _safetyFailModeToBackendString(settings.safetyFailMode),
      );
    }
    // Save path: only override the checkpoint's restored path when the
    // user actually has one configured — pushing null here would clobber
    // a perfectly good snapshot path with "don't save".
    final savePath = settings?.imageOutputPath;
    if (savePath != null && savePath.isNotEmpty) {
      await backend.sequencerSetSavePath(savePath);
    }
    // Device IDs: the checkpoint restored the snapshot's mapping. Only
    // push fresher IDs when a camera is currently connected — in the
    // crash-recovery-at-startup case (equipment not reconnected yet) the
    // snapshot's IDs are the best information we have, and overwriting
    // them with nulls would strand the resumed run.
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      final mountState = _ref.read(mountStateProvider);
      final focuserState = _ref.read(focuserStateProvider);
      final filterwheelState = _ref.read(filterWheelStateProvider);
      final rotatorState = _ref.read(rotatorStateProvider);
      await backend.sequencerSetDevices(
        cameraId: cameraState.deviceId,
        mountId: mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : null,
        focuserId:
            focuserState.connectionState == DeviceConnectionState.connected
            ? focuserState.deviceId
            : null,
        filterwheelId:
            filterwheelState.connectionState == DeviceConnectionState.connected
            ? filterwheelState.deviceId
            : null,
        rotatorId:
            rotatorState.connectionState == DeviceConnectionState.connected
            ? rotatorState.deviceId
            : null,
      );
    }
    await _seedRuntimeConfigFromSettings(backend);

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    progressNotifier.updateState(SequenceExecutionState.running);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    progressNotifier.updateProgress(
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      message: 'Resuming from checkpoint...',
    );

    // A resumed run still needs a session + run row so frame stats,
    // replay decisions and the morning report have something to attach
    // to. sequenceId is unknown post-crash (the checkpoint stores the
    // Rust-side definition, not the Dart DB id) — null is accepted.
    final sessionNotifier = _ref.read(sessionStateProvider.notifier);
    await sessionNotifier.startSession(targetName: info.sequenceName);
    final runId = await _ref
        .read(sequenceRunsDaoProvider)
        .startRun(sequenceId: null, sequenceName: info.sequenceName);
    _ref.read(currentRunIdProvider.notifier).state = runId;
    _ref.read(liveSequenceStatsProvider.notifier).state = SequenceRunStats();
    _runFinalized = false;
    _liveStackingArmedForRun = false;
    _liveStackingFeedChain = null;
    try {
      await backend.sequencerSetActiveSequenceRunId(runId);
    } catch (e) {
      _logger.warning(
        'Failed to push active sequence_run_id to Rust executor on resume: $e',
        source: 'SequenceExecutor',
      );
    }

    _startTime = DateTime.now();
    _isPaused = false;
    // Reset the EMA so resume samples — which start from the checkpoint
    // mid-run cadence — aren't biased by stale samples from the original
    // session (different exposure length, focuser, etc.).
    _resetEtaState();
    // Seed the frame counter to the checkpoint's completed count so newly
    // completed frames during resume are correctly attributed.
    _lastFrameCount = info.completedExposures;
    _lastFrameElapsedSecs = 0.0;

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed = DateTime.now()
            .difference(_startTime!)
            .inSeconds
            .toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final eta = _computeSmoothedEta(elapsed, progress);
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    _startCheckpointTimer();
    _startDiskSpaceWatchdog();

    await _nativeEventSubscription?.cancel();
    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
      onError: (e) =>
          _logger.error('Event stream error: $e', source: 'SequenceExecutor'),
    );

    _startSettingsWatchers(backend);

    // Actually begin execution: start() walks the restored tree and
    // short-circuits already-completed nodes — that is what makes the
    // checkpoint resume real instead of a state-only restore.
    try {
      await backend.sequencerStart();
    } catch (e) {
      // Roll the UI back so the user sees the failure instead of a
      // permanently-"running" ghost sequence.
      _progressTimer?.cancel();
      _progressTimer = null;
      _stopSettingsWatchers();
      progressNotifier.updateState(SequenceExecutionState.failed);
      _ref.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.failed;
      rethrow;
    }
  }

  /// Discard the current checkpoint
  Future<void> discardCheckpoint() async {
    final backend = _ref.read(backendProvider);
    await backend.discardCheckpoint();
  }

  /// Start periodic checkpoint saves (every 30 seconds while running).
  void dispose() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;
    _stopDiskSpaceWatchdog();
  }
}
