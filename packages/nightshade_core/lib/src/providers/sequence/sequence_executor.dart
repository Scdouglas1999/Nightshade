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
import '../../services/smart_night/guide_rms_collector.dart';
import '../../services/capture_preview_loader.dart';
import '../../services/logging_service.dart';
import '../thumbnail_sidecar_provider.dart';
import '../backend_provider.dart';
import '../database_provider.dart'
    show guideRmsHistoryDaoProvider, imagesDaoProvider;
import '../disk_space_provider.dart';
import '../equipment_provider.dart';
// Wave 5 Agent 2 — sky-brightness poll reads the tracker via this
// provider (defined in flat_wizard_provider since the tracker is
// shared between flat-wizard and adaptive-exposure paths).
import '../flat_wizard_provider.dart' show skyBrightnessTrackerProvider;
import '../imaging_provider.dart';
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
  ) =>
      _seedIntegrationCarryOverFromHandoff(backend, sequence);

  /// Convert Dart sequence to JSON for native executor
  ///
  /// Why: this is the point where per-sequence and per-node values are
  /// combined with global AppSettings defaults. Per-node values always win;
  /// AppSettings is consulted only when the node provides no explicit value
  /// (audit-handoff §2.1 WIRE-UP items #4 and #5).
  String _sequenceToJson(Sequence sequence) {
    final appSettings = _ref.read(appSettingsProvider).valueOrNull;
    final autoFocusOnFilterChange =
        appSettings?.autoFocusOnFilterChange ?? false;
    final autoFocusEveryMinutes = appSettings?.autoFocusEveryMinutes ?? 0;

    final nodeDefinitions = <Map<String, dynamic>>[];

    // Track which FilterChangeNodes need a synthetic AutofocusNode appended
    // to their children. Why: when the user enables "Auto focus on filter
    // change" globally and a FilterChangeNode does not already have an
    // AutofocusNode following it in the sibling chain, we splice one in so
    // the executor runs AF after the filter is in place. Per-sequence
    // structure (an explicit AF node already present) always wins; we only
    // inject when no AF would otherwise run.
    final autoFocusInjectionParents = <String>{};

    void collectAfInjections(SequenceNode node) {
      for (var i = 0; i < node.childIds.length; i++) {
        final childId = node.childIds[i];
        final child = sequence.nodes[childId];
        if (child == null) continue;
        if (child is FilterChangeNode && autoFocusOnFilterChange) {
          // Look at the next sibling (if any) — if it's an AutofocusNode the
          // user already arranged for focus to follow the filter change.
          final nextChildId =
              i + 1 < node.childIds.length ? node.childIds[i + 1] : null;
          final nextSibling =
              nextChildId == null ? null : sequence.nodes[nextChildId];
          final alreadyFollowedByAf = nextSibling is AutofocusNode;
          if (!alreadyFollowedByAf) {
            autoFocusInjectionParents.add(node.id);
          }
        }
        collectAfInjections(child);
      }
    }

    if (sequence.rootNode != null) {
      collectAfInjections(sequence.rootNode!);
    }

    // Map of "after this FilterChange node id" -> synthetic AF node id, so we
    // can rewrite parent child lists deterministically. The synthetic id is
    // derived from the FilterChange id to keep checkpoint replay stable.
    final injectedAfNodes = <String, Map<String, dynamic>>{};

    void processNode(SequenceNode node) {
      final Map<String, dynamic> nodeType = _nodeToConfig(node);

      // If this node is a parent that contains FilterChange children needing
      // injection, rewrite its `children` list to splice an AF node id in
      // immediately after each affected FilterChange.
      final originalChildIds = node.childIds;
      final List<String> effectiveChildIds;
      if (autoFocusOnFilterChange &&
          autoFocusInjectionParents.contains(node.id)) {
        effectiveChildIds = <String>[];
        for (var i = 0; i < originalChildIds.length; i++) {
          final childId = originalChildIds[i];
          effectiveChildIds.add(childId);
          final child = sequence.nodes[childId];
          if (child is! FilterChangeNode) continue;
          final nextSiblingId =
              i + 1 < originalChildIds.length ? originalChildIds[i + 1] : null;
          final nextSibling =
              nextSiblingId == null ? null : sequence.nodes[nextSiblingId];
          if (nextSibling is AutofocusNode) continue;
          final syntheticId = 'af-auto-${child.id}';
          effectiveChildIds.add(syntheticId);
          injectedAfNodes[syntheticId] = {
            'id': syntheticId,
            'name': 'Autofocus (auto, post filter change)',
            'node_type': {
              'type': 'Autofocus',
              'method': _autofocusMethodToString(AutofocusMethod.vCurve),
              'step_size': 100,
              'steps_out': 7,
              'exposure_duration': 3.0,
              'filter': null,
              'binning': 'One',
            },
            'enabled': true,
            'children': const <String>[],
          };
        }
      } else {
        effectiveChildIds = originalChildIds;
      }

      nodeDefinitions.add({
        'id': node.id,
        'name': node.name,
        'node_type': nodeType,
        'enabled': node.isEnabled,
        'children': effectiveChildIds,
      });

      for (final childId in originalChildIds) {
        final child = sequence.nodes[childId];
        if (child != null) {
          processNode(child);
        }
      }
    }

    if (sequence.rootNode != null) {
      processNode(sequence.rootNode!);
    }

    // Append synthetic AF nodes after the real node list so the executor can
    // resolve their child ids when walking the tree.
    nodeDefinitions.addAll(injectedAfNodes.values);

    // Metadata propagates the AF-interval cadence to the Rust executor so
    // future trigger configuration can honor the user's preference. We
    // serialise even when zero so the executor sees an explicit "off"
    // signal rather than an absent key.
    final metadata = <String, String>{
      'autofocus_every_minutes': autoFocusEveryMinutes.toString(),
      'autofocus_on_filter_change': autoFocusOnFilterChange.toString(),
    };

    return jsonEncode({
      'id': sequence.id,
      'name': sequence.name,
      'description': sequence.description,
      'nodes': nodeDefinitions,
      'root_node_id': sequence.rootNodeId,
      'metadata': metadata,
    });
  }

  /// Look up filter index from profile by name (case-insensitive).
  ///
  /// Returns `null` when:
  ///   * [filterName] is null/empty,
  ///   * the active equipment profile has no filter list, or
  ///   * the name isn't found in the profile.
  ///
  /// In the latter two cases (and only those), emits a warning to the
  /// logger AND the live sequence stats blob so the user can see in the
  /// post-session report exactly which exposures fell back to literal
  /// filter names. The warning is rate-limited via
  /// [SequenceRunStats.recordWarning] which suppresses exact-duplicate
  /// consecutive entries.
  int? _lookupFilterIndex(String? filterName) {
    if (filterName == null || filterName.isEmpty) return null;
    final profile = _ref.read(activeEquipmentProfileProvider);
    if (profile == null) {
      _surfaceFilterLookupWarning(
        'Filter wheel profile not active; node will use filter name '
        '"$filterName" literally without a wheel index. Connect a filter '
        'wheel + activate its profile to enable index-based filter selection.',
      );
      return null;
    }
    final filterNames = profile.filterNames;
    if (filterNames.isEmpty) {
      _surfaceFilterLookupWarning(
        'Active profile has no filter list configured; node will use '
        'filter name "$filterName" literally. Configure the filter wheel '
        'slot names in the equipment profile.',
      );
      return null;
    }
    for (int i = 0; i < filterNames.length; i++) {
      if (filterNames[i].toLowerCase() == filterName.toLowerCase()) {
        return i;
      }
    }
    _surfaceFilterLookupWarning(
      'Filter "$filterName" not found in active profile '
      '(available: ${filterNames.join(", ")}); node will use the literal '
      'name without a wheel index.',
    );
    return null;
  }

  /// Emit a filter-lookup warning to both the logger and (if a run is
  /// live) the run stats. Centralized so the wording stays consistent
  /// across the three lookup failure modes.
  void _surfaceFilterLookupWarning(String message) {
    _logger.warning(message, source: 'SequenceExecutor');
    final stats = _ref.read(liveSequenceStatsProvider);
    if (stats != null) {
      stats.recordWarning(message);
      _ref.read(liveSequenceStatsProvider.notifier).state = stats;
      _persistLiveRunStats();
    }
  }

  /// Record the duration of a newly-completed frame and update the EMA.
  ///
  /// Called from the progress timer when `completedExposures` increases.
  /// Maintains a bounded queue of the [kEtaWindowSize] most recent frame
  /// durations and keeps `_smoothedSecsPerFrame` as the EMA over them with
  /// weight [kEtaEmaAlpha].
  ///
  /// Resilient to non-positive samples (e.g., when multiple frames complete
  /// inside a single timer tick) — only positive durations enter the EMA.
  void _recordFrameDurationSample(double secsForFrame) {
    if (!secsForFrame.isFinite || secsForFrame <= 0) return;
    _frameDurations.addLast(secsForFrame);
    if (_frameDurations.length > kEtaWindowSize) {
      _frameDurations.removeFirst();
    }
    final prior = _smoothedSecsPerFrame;
    if (prior == null) {
      // First sample bootstraps the EMA so we don't bias toward zero.
      _smoothedSecsPerFrame = secsForFrame;
    } else {
      _smoothedSecsPerFrame =
          (kEtaEmaAlpha * secsForFrame) + ((1.0 - kEtaEmaAlpha) * prior);
    }
  }

  /// Reset the ETA EMA state. Called when a new run starts (or resumes
  /// from a checkpoint) so the smoother doesn't carry stale samples
  /// from a previous run with different exposure cadence.
  void _resetEtaState() {
    _frameDurations.clear();
    _smoothedSecsPerFrame = null;
    _lastFrameCount = 0;
    _lastFrameElapsedSecs = null;
  }

  /// Compute the smoothed ETA in seconds for the supplied wall-clock
  /// elapsed total and progress snapshot.
  ///
  /// Detects newly-completed frames since the last call and feeds their
  /// per-frame elapsed delta into [_recordFrameDurationSample]. Returns
  /// the predicted remaining seconds = EMA-secs-per-frame × frames-left,
  /// or `null` when no frames have completed yet (so the UI can show
  /// `--` instead of misleading garbage).
  double? _computeSmoothedEta(double elapsedSecs, SequenceProgress progress) {
    final completedFrames = progress.completedExposures;
    final totalFrames = progress.totalExposures;
    if (completedFrames <= 0 || totalFrames <= 0) {
      return null;
    }

    // Feed any frames that completed since the previous tick into the EMA.
    if (completedFrames > _lastFrameCount) {
      final priorElapsed = _lastFrameElapsedSecs ?? 0.0;
      final delta = elapsedSecs - priorElapsed;
      final framesDelta = completedFrames - _lastFrameCount;
      if (framesDelta > 0 && delta > 0) {
        final perFrame = delta / framesDelta;
        for (var i = 0; i < framesDelta; i++) {
          _recordFrameDurationSample(perFrame);
        }
      }
      _lastFrameCount = completedFrames;
      _lastFrameElapsedSecs = elapsedSecs;
    }

    final remainingFrames = totalFrames - completedFrames;
    if (remainingFrames <= 0) return 0.0;

    final smoothed = _smoothedSecsPerFrame;
    if (smoothed == null) return null;
    return smoothed * remainingFrames;
  }

  /// Convert a Dart node to native config format.
  ///
  /// `SequenceNode` is sealed: every subtype must appear below or the
  /// compiler will reject the switch. Adding a new node type forces this
  /// site to be updated.
  Map<String, dynamic> _nodeToConfig(SequenceNode node) {
    switch (node) {
      case ExposureNode n:
        final defaults = _ref.read(sequencerDefaultsProvider);
        final appSettings = _ref.read(appSettingsProvider).valueOrNull;
        final ditherEvery = n.ditherEvery ??
            ((appSettings?.ditherEnabled ?? true)
                ? appSettings?.ditherEveryFrames
                : null);
        // Auto-populate filter_index from profile if not set
        final filterIndex = n.filterIndex ?? _lookupFilterIndex(n.filter);
        return {
          'type': 'TakeExposure',
          'duration_secs': n.durationSecs,
          'count': n.count,
          'filter': n.filter,
          'filter_index': filterIndex,
          'gain': n.gain,
          'offset': n.offset,
          'binning': _binningToString(n.binning),
          'dither_every': ditherEvery,
          'dither_pixels': defaults.ditherPixels,
          'dither_settle_pixels': defaults.ditherSettlePixels,
          'dither_settle_time': defaults.ditherSettleTime,
          'dither_settle_timeout': defaults.ditherSettleTimeout,
          'dither_ra_only': defaults.ditherRaOnly,
          'save_to': null,
          'triggers': n.triggers,
          // Wave 5 Agent 2: per-node sky-brightness adaptive exposure
          // override. `null` => use the global default pushed via
          // `sequencerUpdateDefaultAdaptiveExposure`. The Rust JSON
          // schema uses `serde(default)` so omitting the key is fine,
          // but emitting it explicitly keeps the wire shape visible
          // and the downstream tests reproducible.
          'adaptive_exposure': n.adaptiveExposure?.toJson(),
        };
      case SlewNode n:
        return {
          'type': 'SlewToTarget',
          'use_target_coords': n.useTargetCoords,
          'custom_ra': n.customRa,
          'custom_dec': n.customDec,
        };
      case CenterNode n:
        return {
          'type': 'CenterTarget',
          'use_target_coords': n.useTargetCoords,
          'accuracy_arcsec': n.accuracyArcsec,
          'max_attempts': n.maxAttempts,
          'exposure_duration': 3.0, // Default exposure for centering
          'filter': null,
        };
      case AutofocusNode n:
        return {
          'type': 'Autofocus',
          'method': _autofocusMethodToString(n.method),
          'step_size': n.stepSize,
          'steps_out': n.stepsOut,
          'exposure_duration': n.exposureDuration,
          'filter': null,
          'binning': 'One',
        };
      case DitherNode n:
        return {
          'type': 'Dither',
          'pixels': n.pixels,
          'settle_pixels': n.settlePixels,
          'settle_time': n.settleTime,
          'settle_timeout': n.settleTimeout,
          'ra_only': n.raOnly,
          // Rust DitherPattern enum is serialized as PascalCase variant names.
          'pattern': switch (n.pattern) {
            DitherPattern.random => 'Random',
            DitherPattern.grid => 'Grid',
          },
          'grid_size': n.gridSize,
        };
      case StartGuidingNode n:
        return {
          'type': 'StartGuiding',
          'settle_pixels': n.settlePixels,
          'settle_time': n.settleTime,
          'settle_timeout': n.settleTimeout,
          'auto_select_star': n.autoSelectStar,
        };
      case StopGuidingNode _:
        return {'type': 'StopGuiding'};
      case FilterChangeNode n:
        // Auto-populate filter_index from profile if not set
        final filterIndex =
            n.filterPosition ?? _lookupFilterIndex(n.filterName);
        return {
          'type': 'ChangeFilter',
          'filter_name': n.filterName,
          'filter_index': filterIndex,
        };
      case CoolCameraNode n:
        return {
          'type': 'CoolCamera',
          'target_temp': n.targetTemp,
          'duration_mins': n.durationMins,
        };
      case WarmCameraNode n:
        return {
          'type': 'WarmCamera',
          'rate_per_min': n.ratePerMin,
          'target_temp': n.targetTemp,
        };
      case RotatorNode n:
        return {
          'type': 'MoveRotator',
          'target_angle': n.targetAngle,
          'relative': n.relative,
        };
      case ParkNode _:
        return {'type': 'Park'};
      case UnparkNode _:
        return {'type': 'Unpark'};
      case WaitTimeNode n:
        return {
          'type': 'WaitForTime',
          'wait_until': n.waitUntil?.millisecondsSinceEpoch,
          'wait_for_twilight': n.waitForTwilight != null
              ? _twilightToString(n.waitForTwilight!)
              : null,
        };
      case DelayNode n:
        return {
          'type': 'Delay',
          'seconds': n.seconds,
        };
      case NotificationNode n:
        return {
          'type': 'Notification',
          'title': n.title,
          'message': n.message,
          'level': _notificationLevelToString(n.level),
          // Wave 5 Agent 5 — pass the per-node transport override through
          // to the Rust executor as a Custom-event `data` field so the
          // Dart-side notification router can honour it.
          if (n.explicitTransports != null)
            'explicit_transports':
                n.explicitTransports!.map((t) => t.storageKey).toList(),
        };
      case ScriptNode n:
        return {
          'type': 'RunScript',
          'script_path': n.scriptPath,
          'arguments': n.arguments,
          'timeout_secs': n.timeoutSecs,
        };
      case TargetHeaderNode n:
        return {
          'type': 'TargetHeader',
          'target_name': n.targetName,
          'ra_hours': n.raHours,
          'dec_degrees': n.decDegrees,
          'rotation': n.rotation,
          'min_altitude': n.minAltitude,
          'max_altitude': n.maxAltitude,
          'priority': n.priority,
          'start_after': n.startAfter?.millisecondsSinceEpoch,
          'end_before': n.endBefore?.millisecondsSinceEpoch,
          'mosaic_panel': n.mosaicPanel?.toJson(),
          // Wave 8 — adaptive swap brightness tier hint. Lowercase wire
          // string ('faint'/'medium'/'bright'); `null` => scheduler
          // infers (defaults to medium inside the decision engine).
          'brightness_tier_hint': n.brightnessTierHint?.wireValue,
        };
      case InstructionSetNode _:
        // InstructionSet maps to a Loop with count=1 on the backend
        return {
          'type': 'Loop',
          'iterations': 1,
          'condition': 'Count',
          'condition_value': 1,
        };
      case LoopNode n:
        dynamic conditionValue;
        switch (n.conditionType) {
          case LoopConditionType.count:
            conditionValue = n.repeatCount;
            break;
          case LoopConditionType.untilTime:
            conditionValue = n.repeatUntil?.millisecondsSinceEpoch;
            break;
          case LoopConditionType.untilAltitude:
          case LoopConditionType.altitudeAbove:
            conditionValue = n.repeatUntilAltitude;
            break;
          case LoopConditionType.integrationTime:
            conditionValue = n.repeatCount;
            break;
          case LoopConditionType.forever:
          case LoopConditionType.whileDark:
            conditionValue = null;
            break;
        }
        return {
          'type': 'Loop',
          'iterations': n.repeatCount,
          'condition': _loopConditionToString(n.conditionType),
          'condition_value': conditionValue,
        };
      case ParallelNode n:
        return {
          'type': 'Parallel',
          'required_successes': n.requiredSuccesses,
        };
      case ConditionalNode n:
        dynamic conditionValue;
        switch (n.conditionType) {
          case ConditionalType.always:
          case ConditionalType.weatherSafe:
          case ConditionalType.safetyMonitorSafe:
            conditionValue = null;
            break;
          case ConditionalType.altitudeAbove:
          case ConditionalType.guidingRmsBelow:
          case ConditionalType.hfrBelow:
          case ConditionalType.moonSeparationAbove:
            conditionValue = n.thresholdValue;
            break;
          case ConditionalType.timeAfter:
            conditionValue = n.thresholdTime?.millisecondsSinceEpoch;
            break;
        }
        // Audit C2: mirror the Rust `ConditionalConfig.safety_monitor_id`
        // field. Only emit it for the SafetyMonitorSafe variant so the
        // wire format stays unchanged for unrelated conditions (the Rust
        // dispatch ignores the field for other variants anyway, but
        // serialising it would be misleading). `#[serde(default)]` on
        // the Rust side keeps legacy sequences without the key parseable.
        final Map<String, dynamic> conditionalConfig = {
          'type': 'Conditional',
          'condition': {
            'type': _conditionalTypeToString(n.conditionType),
            'value': conditionValue,
          },
        };
        if (n.conditionType == ConditionalType.safetyMonitorSafe &&
            n.safetyMonitorId != null) {
          conditionalConfig['safety_monitor_id'] = n.safetyMonitorId;
        }
        return conditionalConfig;
      case RecoveryNode n:
        // Wave 1.5 Pack A: send the user-configured trigger to Rust. The
        // previous hardcoded `'trigger': null` meant the recovery node
        // matched ANY error, regardless of the UI selection — making the
        // trigger-type dropdown a placebo. `toRustTriggerConfig()` mirrors
        // the Rust serde-tagged `Option<TriggerType>` shape.
        return {
          'type': 'Recovery',
          'trigger': n.toRustTriggerConfig(),
          'recovery_action': _recoveryActionToString(n.recoveryAction),
          'max_retries': n.maxRetries,
        };
      case MeridianFlipNode n:
        return _buildMeridianFlipConfig(n);
      case OpenDomeNode n:
        return {
          'type': 'OpenDome',
          'shutter_only': n.shutterOnly,
        };
      case CloseDomeNode n:
        return {
          'type': 'CloseDome',
          'shutter_only': n.shutterOnly,
        };
      case ParkDomeNode n:
        return {
          'type': 'ParkDome',
          'shutter_only': n.shutterOnly,
        };
      case PolarAlignmentNode n:
        return {
          'type': 'PolarAlignment',
          'step_size': n.rotationStep,
          'exposure_time': n.exposureDuration,
          'solve_timeout': 60.0, // Default timeout
          'manual_rotation': n.manualSlew,
          'rotate_east': n.isNorth, // Use isNorth as direction hint
          'gain': n.gain,
          'offset': n.offset,
          'binning': n.binning,
        };
      case OpenCoverNode n:
        return {
          'type': 'OpenCover',
          'timeout_secs': n.timeoutSecs,
        };
      case CloseCoverNode n:
        return {
          'type': 'CloseCover',
          'timeout_secs': n.timeoutSecs,
        };
      case CalibratorOnNode n:
        return {
          'type': 'CalibratorOn',
          'brightness': n.brightness,
          'timeout_secs': n.timeoutSecs,
        };
      case CalibratorOffNode n:
        return {
          'type': 'CalibratorOff',
          'timeout_secs': n.timeoutSecs,
        };
      // Wave 3 Agent 1: TargetScheduler dynamic target picker.
      case TargetSchedulerNode n:
        return {
          'type': 'TargetScheduler',
          'altitude_weight': n.altitudeWeight,
          'moon_distance_weight': n.moonDistanceWeight,
          'transit_proximity_weight': n.transitProximityWeight,
          'darkness_weight': n.darknessWeight,
          'airmass_weight': n.airmassWeight,
          'min_score_to_run': n.minScoreToRun,
          'recompute_every_n_exposures': n.recomputeEveryNExposures,
          'finish_iteration_on_switch': n.finishIterationOnSwitch,
          // Wave 8 — adaptive sky-conditions swap. `null` swap threshold
          // disables the feature for this scheduler instance.
          'swap_on_conditions_below': n.swapOnConditionsBelow,
          'swap_hysteresis_secs': n.swapHysteresisSecs,
          'brightness_tier_preferences': n.brightnessTierPreferences.toJson(),
          'max_conditions_score_age_secs': n.maxConditionsScoreAgeSecs,
        };
      // Wave 7 Science: SciencePhotometry — cadence-enforced photometric capture.
      case SciencePhotometryNode n:
        return {
          'type': 'SciencePhotometry',
          ...n.toRustConfigJson(),
        };
      // Wave 3 Agent 2: SmartExposure multi-filter container instruction.
      case SmartExposureNode n:
        // Auto-resolve the filter index from the active equipment profile
        // when the row was authored without one — matches the
        // auto-population that ExposureNode and FilterChangeNode already
        // do. Persisting the resolved index makes the executor's
        // ChangeFilter step robust to filter-name typos at runtime.
        final resolvedPlans = n.plans
            .map(
              (p) => {
                'filter_name': p.filterName,
                'filter_index':
                    p.filterIndex ?? _lookupFilterIndex(p.filterName),
                'count': p.count,
                'duration_secs': p.durationSecs,
                'gain': p.gain,
                'offset': p.offset,
                'binning': _binningToString(p.binning),
                'dither_every': p.ditherEvery,
              },
            )
            .toList(growable: false);
        return {
          'type': 'SmartExposure',
          'plans': resolvedPlans,
          'rotate_filters': n.rotateFilters,
          'dither_on_filter_change': n.ditherOnFilterChange,
          'integration_budget_secs': n.integrationBudgetSecs,
          'batch_size': n.batchSize,
        };
      // Audit §11 — plugin-contributed instruction. We forward the
      // plugin id, node-type id, opaque config JSON, optional display
      // name, and optional per-node timeout verbatim. The Rust executor
      // does NOT introspect `config_json`; when execution reaches this
      // node it emits `PluginNodeRequested`, which the Dart-side
      // `pluginNodeDispatcherProvider` routes through
      // `PluginNodeExecutor` (in nightshade_plugins).
      case PluginInstructionNode n:
        return {
          'type': 'PluginNode',
          'plugin_id': n.pluginId,
          'node_type_id': n.nodeTypeId,
          'config_json': n.configJson,
          'display_name': n.name,
          'timeout_secs': n.timeoutSecs,
        };
      // Wave 7 Agent 2: LiveStacking — broadcast / EAA node. The Rust
      // side serialises field names in snake_case so we mirror that
      // here. `auth_token` and `watermark_text` are emitted as `null`
      // (vs. omitted) for round-trip fidelity with the Rust
      // `#[serde(default)] Option<String>` fields.
      case LiveStackingNode n:
        return {
          'type': 'LiveStacking',
          'mode': n.mode.storageKey,
          'stack_method': n.stackMethod.storageKey,
          'max_frames_to_stack': n.maxFramesToStack,
          'broadcast_enabled': n.broadcastEnabled,
          'broadcast_port': n.broadcastPort,
          'broadcast_path': n.broadcastPath,
          'auth_token': n.authToken,
          'watermark_text': n.watermarkText,
          'thumbnail_width': n.thumbnailWidth,
          'thumbnail_height': n.thumbnailHeight,
        };
    }
  }

  /// Build the Rust-side MeridianFlipConfig JSON for a [MeridianFlipNode].
  ///
  /// Why: the Rust struct [`MeridianFlipConfig`](native/.../lib.rs:875) has
  /// no `#[serde(default)]` annotations on most fields, so the JSON we send
  /// MUST include every required field. Two sources drive the final config:
  ///
  /// 1. When `node.useGlobalDefaults == true` (fresh nodes from the palette /
  ///    quick-start wizard / canonical importers that opt in), the effective
  ///    `globalMeridianFlipSettingsProvider` snapshot is the source of truth.
  ///    The 16 settings in Sequencer Settings -> Meridian Flip therefore
  ///    drive node behavior at execution time (audit §1.2).
  /// 2. When `node.useGlobalDefaults == false` (user-edited or legacy nodes),
  ///    the per-node fields take priority. The global retry-delays / tracking
  ///    wait minutes still flow through because the node model doesn't carry
  ///    them; the Rust struct requires both.
  ///
  /// Enum names are emitted PascalCase to match Rust's
  /// `#[derive(Deserialize)]` default form.
  Map<String, dynamic> _buildMeridianFlipConfig(MeridianFlipNode node) {
    final global = _ref.read(effectiveMeridianFlipSettingsProvider);
    final useGlobal = node.useGlobalDefaults;

    final triggerMethod = useGlobal ? global.triggerMethod : node.triggerMethod;
    final minutesPastMeridian =
        useGlobal ? global.minutesPastMeridian : node.minutesPastMeridian;
    final minutesBeforeLimit =
        useGlobal ? global.minutesBeforeLimit : node.minutesBeforeLimit;
    final hourAngleThreshold =
        useGlobal ? global.hourAngleThreshold : node.hourAngleThreshold;
    final pauseGuiding =
        useGlobal ? global.pauseGuidingBeforeFlip : node.pauseGuiding;
    final autoCenter = useGlobal ? global.recenterAfterFlip : node.autoCenter;
    final refocusAfter =
        useGlobal ? global.refocusAfterFlip : node.refocusAfter;
    final settleTime = useGlobal ? global.settleTimeSeconds : node.settleTime;
    final resumeGuiding =
        useGlobal ? global.resumeGuidingAfterFlip : node.resumeGuiding;
    final maxRetries = useGlobal ? global.maxRetries : node.maxRetries;
    final failureAction = useGlobal ? global.failureAction : node.failureAction;

    return {
      'type': 'MeridianFlip',
      'trigger_method': _meridianTriggerMethodToString(triggerMethod),
      'minutes_past_meridian': minutesPastMeridian,
      'minutes_before_limit': minutesBeforeLimit,
      'hour_angle_threshold': hourAngleThreshold,
      // Why: only the global model carries tracking-limit wait minutes and
      // retry delays — the per-node fields never existed. These are required
      // by MeridianFlipConfig regardless of useGlobalDefaults.
      'tracking_limit_wait_minutes': global.trackingLimitWaitMinutes,
      'pause_guiding': pauseGuiding,
      'auto_center': autoCenter,
      'refocus_after': refocusAfter,
      'settle_time': settleTime,
      'resume_guiding': resumeGuiding,
      'max_retries': maxRetries,
      'retry_delays_secs': global.retryDelaysSeconds,
      'failure_action': _flipFailureActionToString(failureAction),
    };
  }

  /// Rust expects PascalCase enum names; Dart's `.name` is camelCase. Map
  /// explicitly so this conversion never silently regresses.
  String _meridianTriggerMethodToString(MeridianTriggerMethod method) {
    switch (method) {
      case MeridianTriggerMethod.minutesPastMeridian:
        return 'MinutesPastMeridian';
      case MeridianTriggerMethod.minutesBeforeLimit:
        return 'MinutesBeforeLimit';
      case MeridianTriggerMethod.hourAngleThreshold:
        return 'HourAngleThreshold';
      case MeridianTriggerMethod.onTrackingLimitHit:
        return 'OnTrackingLimitHit';
    }
  }

  String _flipFailureActionToString(FlipFailureAction action) {
    switch (action) {
      case FlipFailureAction.pauseAndAlert:
        return 'PauseAndAlert';
      case FlipFailureAction.abortAndPark:
        return 'AbortAndPark';
    }
  }

  String _binningToString(BinningMode binning) {
    switch (binning) {
      case BinningMode.one:
        return 'One';
      case BinningMode.two:
        return 'Two';
      case BinningMode.three:
        return 'Three';
      case BinningMode.four:
        return 'Four';
    }
  }

  String _autofocusMethodToString(AutofocusMethod method) {
    switch (method) {
      case AutofocusMethod.vCurve:
        return 'VCurve';
      case AutofocusMethod.hyperbolic:
        return 'Hyperbolic';
      case AutofocusMethod.quadratic:
        return 'Quadratic';
    }
  }

  String _twilightToString(TwilightType type) {
    switch (type) {
      case TwilightType.civil:
        return 'Civil';
      case TwilightType.nautical:
        return 'Nautical';
      case TwilightType.astronomical:
        return 'Astronomical';
    }
  }

  String _notificationLevelToString(NotificationLevel level) {
    switch (level) {
      case NotificationLevel.info:
        return 'Info';
      case NotificationLevel.warning:
        return 'Warning';
      case NotificationLevel.error:
        return 'Error';
      case NotificationLevel.success:
        return 'Success';
    }
  }

  String _safetyFailModeToBackendString(SafetyFailMode mode) => switch (mode) {
        SafetyFailMode.failOpen => 'fail_open',
        SafetyFailMode.warnOnly => 'warn_only',
        SafetyFailMode.failClosed => 'fail_closed',
      };

  String _loopConditionToString(LoopConditionType type) {
    switch (type) {
      case LoopConditionType.count:
        return 'Count';
      case LoopConditionType.untilTime:
        return 'UntilTime';
      case LoopConditionType.untilAltitude:
        return 'AltitudeBelow';
      case LoopConditionType.altitudeAbove:
        return 'AltitudeAbove';
      case LoopConditionType.integrationTime:
        return 'IntegrationTime';
      case LoopConditionType.forever:
        return 'Forever';
      case LoopConditionType.whileDark:
        return 'WhileDark';
    }
  }

  String _conditionalTypeToString(ConditionalType type) {
    switch (type) {
      case ConditionalType.always:
        return 'Always';
      case ConditionalType.altitudeAbove:
        return 'AltitudeAbove';
      case ConditionalType.timeAfter:
        return 'TimeAfter';
      case ConditionalType.guidingRmsBelow:
        return 'GuidingRmsBelow';
      case ConditionalType.hfrBelow:
        return 'HfrBelow';
      case ConditionalType.weatherSafe:
        return 'WeatherSafe';
      case ConditionalType.moonSeparationAbove:
        return 'MoonSeparationAbove';
      case ConditionalType.safetyMonitorSafe:
        return 'SafetyMonitorSafe';
    }
  }

  String _recoveryActionToString(RecoveryActionType action) {
    switch (action) {
      case RecoveryActionType.continueExecution:
        return 'Continue';
      case RecoveryActionType.pause:
        return 'Pause';
      case RecoveryActionType.autofocus:
        return 'Autofocus';
      case RecoveryActionType.nextTarget:
        return 'NextTarget';
      case RecoveryActionType.retry:
        return 'Retry';
      case RecoveryActionType.parkAndAbort:
        return 'ParkAndAbort';
      case RecoveryActionType.customBranch:
        return 'CustomBranch';
      // Wave 5 Agent 4 — cloud-motion-aware recovery actions. Names match
      // the Rust enum variants so the deserialiser in nightshade_sequencer
      // accepts the bare-string form.
      case RecoveryActionType.pauseAndWaitForClear:
        return 'PauseAndWaitForClear';
      case RecoveryActionType.slewToGapAndContinue:
        return 'SlewToGapAndContinue';
      // Wave 7 Science — transparency-adaptive recovery. Bare-string
      // form because the Rust variant has no payload.
      case RecoveryActionType.switchTargetOrFilter:
        return 'SwitchTargetOrFilter';
    }
  }

  /// Validate the sequence about to run using the FULL validator stack
  /// (structural + ref-aware + async). This is the single source of truth
  /// for "is this sequence safe to start?".
  ///
  /// Audit C3 — before this consolidation, `start()` only ran the pure
  /// structural rules (`defaultSequenceValidators`), so equipment-
  /// connection, disk-space, dark-library, and pre-flight equipment-
  /// health rules were silently skipped for any start path that did not
  /// route through the pre-flight dialog (notably the headless API and
  /// the scheduler). The dialog itself called the same
  /// `SequenceValidatorService` we now invoke here, so the rigor is
  /// identical regardless of how the user kicked the sequence off.
  ///
  /// Returns the [validation.ValidationResult]. Callers decide what to
  /// do with warnings / info; only [validation.ValidationSeverity.error]
  /// blocks execution (enforced in [start]).
  Future<validation.ValidationResult> validateSequenceForStart(
      Sequence sequence) async {
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
      targetDec:
          isSingleTarget ? sequence.targetHeaders.first.decDegrees : null,
    );
    sessionNotifier.setTotalExposures(sequence.totalExposures);
    final runId = await _ref.read(sequenceRunsDaoProvider).startRun(
          sequenceId: sequence.databaseId,
          sequenceName: sequence.name,
        );
    _ref.read(currentRunIdProvider.notifier).state = runId;
    _ref.read(liveSequenceStatsProvider.notifier).state = SequenceRunStats();
    _runFinalized = false;

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
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
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

  Future<void> _startNativeExecution(Sequence sequence) async {
    final backend = _ref.read(backendProvider);

    // Sync observer location to Rust backend before starting sequence
    // This ensures the sequencer has access to the current location from settings
    final settingsAsync = _ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    _logger.debug(
        '_startNativeExecution: settings=${settings != null ? "loaded" : "null"}',
        source: 'SequenceExecutor');
    if (settings != null) {
      _logger.debug(
          'Location from settings: lat=${settings.latitude}, lon=${settings.longitude}, elev=${settings.elevation}',
          source: 'SequenceExecutor');
    }
    if (settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0)) {
      _logger.debug('Syncing location to backend...',
          source: 'SequenceExecutor');
      await backend.setLocation(ObserverLocation(
        latitude: settings.latitude,
        longitude: settings.longitude,
        elevation: settings.elevation,
      ));
      _logger.debug('Location sync complete', source: 'SequenceExecutor');
    } else {
      _logger.debug('Skipping location sync: settings null or location is 0,0',
          source: 'SequenceExecutor');
    }

    // Simulation is disabled in release builds.
    if (kReleaseMode) {
      await backend.sequencerSetSimulationMode(false);
    } else {
      await backend.sequencerSetSimulationMode(_useSimulationMode);
    }

    if (settings != null) {
      final safetyFailMode =
          _safetyFailModeToBackendString(settings.safetyFailMode);
      await backend.sequencerSetSafetyFailMode(safetyFailMode);
      _logger.debug('Safety fail mode set to: $safetyFailMode',
          source: 'SequenceExecutor');
    }

    final savePath = settings?.imageOutputPath;
    if (savePath != null && savePath.isNotEmpty) {
      await backend.sequencerSetSavePath(savePath);
      _logger.debug('Save path set to: $savePath', source: 'SequenceExecutor');
    } else {
      await backend.sequencerSetSavePath(null);
      _logger.warning(
          'No save path configured - images will NOT be saved to disk!',
          source: 'SequenceExecutor');
    }

    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final filterwheelState = _ref.read(filterWheelStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);

    final cameraId =
        cameraState.connectionState == DeviceConnectionState.connected
            ? cameraState.deviceId
            : null;
    final mountId =
        mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : null;
    final focuserId =
        focuserState.connectionState == DeviceConnectionState.connected
            ? focuserState.deviceId
            : null;
    final filterwheelId =
        filterwheelState.connectionState == DeviceConnectionState.connected
            ? filterwheelState.deviceId
            : null;
    final rotatorId =
        rotatorState.connectionState == DeviceConnectionState.connected
            ? rotatorState.deviceId
            : null;

    await backend.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
    );

    final json = _sequenceToJson(sequence);
    await backend.sequencerLoadJson(json);

    // Wave 1.5 Pack D: seed RuntimeConfig from persisted user settings BEFORE
    // start() so the trigger monitor's first poll honours the user's cadence
    // / dither / location / filter-offsets values instead of the Rust
    // defaults (autofocus_interval_frames=25, dither pixels=5, location 0/0,
    // empty filter offsets). Previously these were only pushed by the live
    // settings watchers, which fire only on subsequent changes — so a
    // headless start that never visits the Settings UI ran with the wrong
    // cadence silently. Failures are surfaced (not swallowed); a bad seed
    // means the user wants those values to apply and we must abort start
    // rather than run with the wrong cadence.
    await _seedRuntimeConfigFromSettings(backend);

    // Wave 7.5 — consult the session-handoff decision for every
    // TargetHeader with an `integrationBudget` configured. The operator's
    // pre-flight decision (Resume / Restart / Continue New) decides how
    // the Rust `BudgetRegistry` is seeded for this run.
    //
    // Resume      → pre-credit per-filter integration from the prior
    //               session's carry-over so "Lum: 4h done / 8h target"
    //               persists into the new run.
    // Restart     → push an empty per-filter map so any stale checkpoint
    //               carry-over is overwritten with zeros.
    // ContinueNew → omit the target (default behaviour: tracker starts
    //               from zero without zeroing prior state).
    //
    // Done AFTER `_seedRuntimeConfigFromSettings` so the carry-over write
    // overrides any default the runtime-config push might re-stamp, and
    // BEFORE `sequencerStart()` so the consumption hook at the top of
    // the spawned executor task sees the freshly-staged map.
    await _seedIntegrationCarryOverFromHandoff(backend, sequence);

    // The FfiBackend eagerly initializes the event stream in its constructor,
    // so the Rust api_event_stream() function should already be running and
    // subscribed to the event bus. We just subscribe to the broadcast stream
    // here.
    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
      onError: (e) =>
          _logger.error('Event stream error: $e', source: 'SequenceExecutor'),
    );

    _startSettingsWatchers(backend);

    await backend.sequencerStart();
  }

  /// Push every user-controlled RuntimeConfig field into the loaded executor.
  ///
  /// Why one method instead of inline: keeps the start path readable and
  /// makes the same seed sequence reusable from the headless start path
  /// (`DeviceService.sequencerStart`) once it grows past the simple wrapper.
  /// Each push is independent — a failure on one field still attempts the
  /// next, but the first failure is rethrown after the batch so the caller
  /// learns about the misconfiguration before sequencerStart() runs.
  Future<void> _seedRuntimeConfigFromSettings(NightshadeBackend backend) async {
    Object? firstError;
    StackTrace? firstStack;

    // Autofocus cadence: persisted in sequencer_autofocus_interval_frames; the
    // Rust default of 25 is wrong for both very-short and very-long subs.
    try {
      final defaults = _ref.read(sequencerDefaultsProvider);
      final frames = defaults.autofocusIntervalFrames < 1
          ? 1
          : defaults.autofocusIntervalFrames;
      await backend.sequencerUpdateAutofocusInterval(frames);
      _logger.debug(
        'Seeded autofocus interval: every $frames frames',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed autofocus interval: $e',
        source: 'SequenceExecutor',
      );
    }

    // Dither config: persisted in SequencerDefaults; the Rust defaults differ
    // from what the user sees in Settings, so without this seed an unattended
    // headless start uses a stale config.
    try {
      final defaults = _ref.read(sequencerDefaultsProvider);
      await backend.sequencerUpdateDitherConfig(
        pixels: defaults.ditherPixels,
        settlePixels: defaults.ditherSettlePixels,
        settleTime: defaults.ditherSettleTime,
        settleTimeout: defaults.ditherSettleTimeout,
        raOnly: defaults.ditherRaOnly,
      );
      _logger.debug(
        'Seeded dither config: pixels=${defaults.ditherPixels} settle=${defaults.ditherSettleTime}s',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed dither config: $e',
        source: 'SequenceExecutor',
      );
    }

    // Observer location: distinct from setLocation() above (which sets the
    // higher-level NightshadeBackend location). The sequencer's RuntimeConfig
    // owns its own lat/lon used by meridian-flip and altitude calculations.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateLocation(
          latitude: settings.latitude,
          longitude: settings.longitude,
        );
        _logger.debug(
          'Seeded sequencer location: lat=${settings.latitude} lon=${settings.longitude}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed sequencer location: $e',
        source: 'SequenceExecutor',
      );
    }

    // Filter focus offsets: persisted on the active equipment profile as a
    // `Map<String,int>` directly on `EquipmentProfileModel`. The Rust
    // default is an empty map, so an unattended start with no Settings
    // round-trip would not apply offsets.
    try {
      final profile = _ref.read(activeEquipmentProfileProvider);
      final offsets = profile?.filterFocusOffsets ?? const <String, int>{};
      await backend.sequencerUpdateFilterOffsets(offsets);
      _logger.debug(
        'Seeded filter focus offsets: ${offsets.length} entries',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed filter focus offsets: $e',
        source: 'SequenceExecutor',
      );
    }

    // Pack G — default image-grading thresholds + reject folder. Without
    // this seed the executor's RuntimeConfig stays at the all-None
    // default and "Enable image grading" in Settings has no effect on the
    // next sequence start.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateDefaultQualityCheck(
          hfrThreshold: settings.imageGradingHfrThresholdPx,
          hfrBaselinePercent: settings.imageGradingHfrBaselinePercent,
          eccentricityThreshold: settings.imageGradingEccentricityThreshold,
          starCountMin: settings.imageGradingStarCountMin,
          maxConsecutiveRejects: settings.imageGradingMaxConsecutiveRejects,
          enabled: settings.enableImageGrading,
        );
        _logger.debug(
          'Seeded default_quality_check: enabled=${settings.enableImageGrading}, hfr=${settings.imageGradingHfrThresholdPx}px, baseline=${settings.imageGradingHfrBaselinePercent}%',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed default_quality_check: $e',
        source: 'SequenceExecutor',
      );
    }

    // Pack G — reject folder path.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateRejectFolderPath(
          settings.imageGradingRejectFolderPath,
        );
        _logger.debug(
          'Seeded reject_folder_path: ${settings.imageGradingRejectFolderPath ?? "<default>"}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed reject_folder_path: $e',
        source: 'SequenceExecutor',
      );
    }

    // Pack G — observer / equipment identification so FITS headers carry
    // OBSERVER, TELESCOP, FOCALLEN, APTDIA, INSTRUME, SITEELEV. The
    // observer name comes from app settings; everything else from the
    // active equipment profile. Null / empty fields are honestly omitted
    // from FITS rather than emitted as sentinels.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      final profile = _ref.read(activeEquipmentProfileProvider);

      // Camera split: profile.cameraName is typically the user-friendly
      // device label (e.g. "ZWO ASI2600MM Pro"). We split on first space
      // for INSTRUME consumers; if there's no space the whole string
      // becomes the model and make is null.
      String? cameraMake;
      String? cameraModel;
      final rawCameraName = profile?.cameraName?.trim();
      if (rawCameraName != null && rawCameraName.isNotEmpty) {
        final spaceIdx = rawCameraName.indexOf(' ');
        if (spaceIdx > 0) {
          cameraMake = rawCameraName.substring(0, spaceIdx).trim();
          cameraModel = rawCameraName.substring(spaceIdx + 1).trim();
        } else {
          cameraModel = rawCameraName;
        }
      }

      // Telescope focal length / aperture: prefer the dedicated
      // telescope_* fields; fall back to focalLength / aperture (the
      // legacy generic fields on EquipmentProfileModel). 0.0 means
      // "not configured" — emit null in that case.
      double? focalLength;
      double? aperture;
      if (profile != null) {
        final tfl = profile.telescopeFocalLength;
        final fl = profile.focalLength;
        if (tfl != null && tfl > 0) {
          focalLength = tfl;
        } else if (fl > 0) {
          focalLength = fl;
        }

        final ta = profile.telescopeAperture;
        if (ta != null && ta > 0) {
          aperture = ta;
        }
      }

      await backend.sequencerUpdateObserverProfile(
        observerName: (settings == null || settings.observerName.isEmpty)
            ? null
            : settings.observerName,
        siteElevationM: (settings != null && settings.elevation > 0)
            ? settings.elevation
            : null,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        telescopeName: profile?.telescopeName,
        telescopeFocalLengthMm: focalLength,
        telescopeApertureMm: aperture,
      );
      _logger.debug(
        'Seeded observer_profile: observer=${settings?.observerName}, telescope=${profile?.telescopeName}, camera=$cameraMake $cameraModel, focal=${focalLength}mm, aperture=${aperture}mm',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed observer_profile: $e',
        source: 'SequenceExecutor',
      );
    }

    // Wave 5 Agent 2 — seed the global default sky-brightness adaptive
    // exposure config from app settings so a sequence start without a
    // settings round-trip still honours the user's choice. When the
    // master switch is off we explicitly clear the executor's value
    // (avoids a stale config sticking around from a prior run).
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        if (settings.adaptiveExposureEnabled) {
          await backend.sequencerUpdateDefaultAdaptiveExposure(
            enabled: settings.adaptiveExposureEnabled,
            targetSnr: settings.adaptiveExposureTargetSnr,
            referenceSkyBrightnessMag: settings.adaptiveExposureReferenceMag,
            minExposureSecs: settings.adaptiveExposureMinSecs,
            maxExposureSecs: settings.adaptiveExposureMaxSecs,
            perFilterEnabled: settings.adaptiveExposurePerFilterEnabled,
            perFilterMinSecs: settings.adaptiveExposurePerFilterMinSecs,
            perFilterMaxSecs: settings.adaptiveExposurePerFilterMaxSecs,
          );
          _logger.debug(
            'Seeded default_adaptive_exposure: enabled=${settings.adaptiveExposureEnabled}, ref=${settings.adaptiveExposureReferenceMag} mag/arcsec², min=${settings.adaptiveExposureMinSecs}s, max=${settings.adaptiveExposureMaxSecs}s',
            source: 'SequenceExecutor',
          );
        } else {
          await backend.sequencerClearDefaultAdaptiveExposure();
          _logger.debug(
            'Cleared default_adaptive_exposure (disabled in settings)',
            source: 'SequenceExecutor',
          );
        }
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed default_adaptive_exposure: $e',
        source: 'SequenceExecutor',
      );
    }

    if (firstError != null) {
      // Rethrow so sequencerStart() does not silently proceed with a partial
      // runtime config. The CLAUDE.md rule "errors are a feature" requires
      // the caller to learn about misconfiguration immediately.
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  /// Wave 7.5 — consume `sessionHandoffDecisionProvider` for every
  /// TargetHeader and push the resolved per-filter carry-over map to
  /// the Rust executor's `BudgetRegistry` seed.
  ///
  /// Three-way semantics, mirroring `SessionHandoffDecision`:
  ///
  ///   * `Resume`     → write the operator's
  ///                    `SessionCarryOver.perFilterIntegrationSecs` into
  ///                    the carry-over map. The Rust side credits those
  ///                    frames against the configured budget so the
  ///                    very first IntegrationBudget tick reads
  ///                    "Lum: 4h done / 8h target", not "Lum: 0h done".
  ///   * `Restart`    → write an explicit empty map for the target id
  ///                    so any pre-existing checkpoint state is
  ///                    overwritten with zeros.
  ///   * `ContinueNew` → omit the target entirely (no carry-over, no
  ///                    zeroing). Same effect as no prior decision.
  ///
  /// Joins `SessionCarryOver.targetName` against the sequence's
  /// `TargetHeaderNode.targetName` (case-insensitive) to resolve the
  /// Rust-side `TargetHeaderNode.id` that the BudgetRegistry keys on.
  ///
  /// Failure policy: a missing decision for a target is a no-op (the
  /// pre-flight dialog might have been dismissed); any other error is
  /// rethrown so the caller learns about misconfiguration before
  /// `sequencerStart()` runs (CLAUDE.md "errors are a feature").
  Future<void> _seedIntegrationCarryOverFromHandoff(
    NightshadeBackend backend,
    Sequence sequence,
  ) async {
    final headers = sequence.targetHeaders;
    if (headers.isEmpty) return;

    // Pull the carry-over snapshot. The provider is autoDispose +
    // FutureProvider; reading `.future` blocks until the first build
    // completes. An empty list means no prior session work to consider.
    final List<SessionCarryOver> carryOvers;
    try {
      carryOvers = await _ref.read(sessionCarryOverProvider.future);
    } catch (e, st) {
      // detectCarryOver already swallows DAO errors and returns []. A
      // throw here means the provider build itself failed (e.g. ref
      // disposal mid-start); surface so the operator sees it rather
      // than ship a stale runtime config to the executor.
      _logger.error(
        'Failed to read session carry-over snapshot: $e',
        source: 'SequenceExecutor',
      );
      Error.throwWithStackTrace(e, st);
    }
    if (carryOvers.isEmpty) return;

    // Build a name-keyed lookup so the matching step is O(carryOvers).
    // `TargetHeaderNode.targetName` is the display name we matched
    // against in `SessionHandoffService.detectCarryOver`, so the
    // case-insensitive comparison reproduces the same join.
    final headersByName = <String, TargetHeaderNode>{};
    for (final h in headers) {
      headersByName[h.targetName.toLowerCase()] = h;
    }

    final carryOverPayload = <String, Map<String, double>>{};
    for (final entry in carryOvers) {
      final header = headersByName[entry.targetName.toLowerCase()];
      if (header == null) {
        // The carry-over targets something the current sequence does
        // not image. Skip; the operator can't have meant to seed it.
        continue;
      }
      final key = (
        sequenceId: sequence.databaseId,
        targetId: entry.targetId,
      );
      final decision = _ref.read(sessionHandoffDecisionProvider(key));
      if (decision == null) {
        // No pre-flight decision recorded (dialog dismissed) — leave
        // the BudgetRegistry to its default zero-credit behaviour.
        continue;
      }
      switch (decision) {
        case SessionHandoffDecision.resume:
          // Copy the per-filter totals verbatim. The Rust side filters
          // non-finite / non-positive values defensively; we still
          // forward the operator's measurement honestly.
          carryOverPayload[header.id] =
              Map<String, double>.from(entry.perFilterIntegrationSecs);
          break;
        case SessionHandoffDecision.restart:
          // Empty map → Rust zeroes any prior per-target state. This is
          // distinct from "omit", which would leave a stale checkpoint
          // entry untouched.
          carryOverPayload[header.id] = const <String, double>{};
          break;
        case SessionHandoffDecision.continueNew:
          // Acknowledged but not reused — neither seed nor zero.
          break;
      }
    }

    if (carryOverPayload.isEmpty) return;
    try {
      await backend
          .sequencerUpdatePendingIntegrationCarryOver(carryOverPayload);
      _logger.info(
        'Staged integration carry-over for ${carryOverPayload.length} '
        'target(s) (handoff decisions applied)',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      _logger.error(
        'Failed to stage integration carry-over: $e',
        source: 'SequenceExecutor',
      );
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Start watching for settings changes that should be propagated to the
  /// backend executor during sequence execution (dither config, location,
  /// filter offsets).
  void _startSettingsWatchers(NightshadeBackend backend) {
    _stopSettingsWatchers();
    // Wave 5 Agent 2 — kick off the sky-brightness poll. The first
    // tick fires 10 s after start (matching the timer cadence); the
    // first user-visible adaptive-exposure decision uses whatever the
    // tracker has at TakeExposure time.
    _startSkyBrightnessPoll(backend);

    _settingsSubscriptions.add(
      _ref.listen(sequencerDefaultsProvider, (previous, next) {
        if (previous == null) return;
        if (previous.ditherPixels != next.ditherPixels ||
            previous.ditherSettlePixels != next.ditherSettlePixels ||
            previous.ditherSettleTime != next.ditherSettleTime ||
            previous.ditherSettleTimeout != next.ditherSettleTimeout ||
            previous.ditherRaOnly != next.ditherRaOnly) {
          _logger.debug(
            'Dither settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateDitherConfig(
            pixels: next.ditherPixels,
            settlePixels: next.ditherSettlePixels,
            settleTime: next.ditherSettleTime,
            settleTimeout: next.ditherSettleTimeout,
            raOnly: next.ditherRaOnly,
          );
        }
      }),
    );

    _settingsSubscriptions.add(
      _ref.listen(appSettingsProvider, (previous, next) {
        final prevSettings = previous?.valueOrNull;
        final nextSettings = next.valueOrNull;
        if (prevSettings == null || nextSettings == null) return;
        if (prevSettings.latitude != nextSettings.latitude ||
            prevSettings.longitude != nextSettings.longitude) {
          _logger.debug(
            'Location changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateLocation(
            latitude: nextSettings.latitude,
            longitude: nextSettings.longitude,
          );
        }

        if (prevSettings.safetyFailMode != nextSettings.safetyFailMode) {
          _logger.debug(
            'Safety fail mode changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerSetSafetyFailMode(
            _safetyFailModeToBackendString(nextSettings.safetyFailMode),
          );
        }

        // Pack G — propagate image-grading changes mid-run so the next
        // exposure honours the user's new thresholds.
        final gradingChanged = prevSettings.enableImageGrading !=
                nextSettings.enableImageGrading ||
            prevSettings.imageGradingHfrThresholdPx !=
                nextSettings.imageGradingHfrThresholdPx ||
            prevSettings.imageGradingHfrBaselinePercent !=
                nextSettings.imageGradingHfrBaselinePercent ||
            prevSettings.imageGradingEccentricityThreshold !=
                nextSettings.imageGradingEccentricityThreshold ||
            prevSettings.imageGradingStarCountMin !=
                nextSettings.imageGradingStarCountMin ||
            prevSettings.imageGradingMaxConsecutiveRejects !=
                nextSettings.imageGradingMaxConsecutiveRejects;
        if (gradingChanged) {
          _logger.debug(
            'Image-grading settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateDefaultQualityCheck(
            hfrThreshold: nextSettings.imageGradingHfrThresholdPx,
            hfrBaselinePercent: nextSettings.imageGradingHfrBaselinePercent,
            eccentricityThreshold:
                nextSettings.imageGradingEccentricityThreshold,
            starCountMin: nextSettings.imageGradingStarCountMin,
            maxConsecutiveRejects:
                nextSettings.imageGradingMaxConsecutiveRejects,
            enabled: nextSettings.enableImageGrading,
          );
        }
        if (prevSettings.imageGradingRejectFolderPath !=
            nextSettings.imageGradingRejectFolderPath) {
          _logger.debug(
            'Reject folder path changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateRejectFolderPath(
            nextSettings.imageGradingRejectFolderPath,
          );
        }

        // Pack G — propagate observer name + elevation changes so FITS
        // headers stay in sync if the user edits Settings mid-run.
        if (prevSettings.observerName != nextSettings.observerName ||
            prevSettings.elevation != nextSettings.elevation) {
          _logger.debug(
            'Observer name / elevation changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          _pushObserverProfile(backend);
        }

        // Wave 5 Agent 2 — propagate global adaptive-exposure setting
        // changes so the next exposure honours the user's edit. We
        // compare all eight inputs in one pass because the executor
        // expects the full config object on every push.
        final adaptiveChanged = prevSettings.adaptiveExposureEnabled !=
                nextSettings.adaptiveExposureEnabled ||
            prevSettings.adaptiveExposureTargetSnr !=
                nextSettings.adaptiveExposureTargetSnr ||
            prevSettings.adaptiveExposureReferenceMag !=
                nextSettings.adaptiveExposureReferenceMag ||
            prevSettings.adaptiveExposureMinSecs !=
                nextSettings.adaptiveExposureMinSecs ||
            prevSettings.adaptiveExposureMaxSecs !=
                nextSettings.adaptiveExposureMaxSecs ||
            !mapEquals(prevSettings.adaptiveExposurePerFilterEnabled,
                nextSettings.adaptiveExposurePerFilterEnabled) ||
            !mapEquals(prevSettings.adaptiveExposurePerFilterMinSecs,
                nextSettings.adaptiveExposurePerFilterMinSecs) ||
            !mapEquals(prevSettings.adaptiveExposurePerFilterMaxSecs,
                nextSettings.adaptiveExposurePerFilterMaxSecs);
        if (adaptiveChanged) {
          _logger.debug(
            'Adaptive-exposure settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          if (nextSettings.adaptiveExposureEnabled) {
            backend.sequencerUpdateDefaultAdaptiveExposure(
              enabled: nextSettings.adaptiveExposureEnabled,
              targetSnr: nextSettings.adaptiveExposureTargetSnr,
              referenceSkyBrightnessMag:
                  nextSettings.adaptiveExposureReferenceMag,
              minExposureSecs: nextSettings.adaptiveExposureMinSecs,
              maxExposureSecs: nextSettings.adaptiveExposureMaxSecs,
              perFilterEnabled: nextSettings.adaptiveExposurePerFilterEnabled,
              perFilterMinSecs: nextSettings.adaptiveExposurePerFilterMinSecs,
              perFilterMaxSecs: nextSettings.adaptiveExposurePerFilterMaxSecs,
            );
          } else {
            backend.sequencerClearDefaultAdaptiveExposure();
          }
        }
      }),
    );

    _settingsSubscriptions.add(
      _ref.listen(activeEquipmentProfileProvider, (previous, next) {
        if (previous == null || next == null) return;
        // EquipmentProfileModel.filterFocusOffsets is already a
        // Map<String,int> in memory; the legacy version of this code
        // decoded it as JSON which was a runtime bug — the analyzer now
        // catches that. Use map equality directly.
        final prevOffsets = previous.filterFocusOffsets;
        final nextOffsets = next.filterFocusOffsets;
        if (!mapEquals(prevOffsets, nextOffsets)) {
          _logger.debug(
            'Filter focus offsets changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateFilterOffsets(nextOffsets);
        }

        // Pack G — propagate telescope / camera identity changes so FITS
        // headers reflect the active equipment profile mid-run (rare but
        // possible when the user swaps profiles between targets).
        if (previous.cameraName != next.cameraName ||
            previous.telescopeName != next.telescopeName ||
            previous.telescopeFocalLength != next.telescopeFocalLength ||
            previous.telescopeAperture != next.telescopeAperture ||
            previous.focalLength != next.focalLength) {
          _logger.debug(
            'Equipment profile identity changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          _pushObserverProfile(backend);
        }
      }),
    );
  }

  /// Pack G — helper that recomputes the observer profile from the
  /// current settings + active equipment profile and pushes it to the
  /// backend. Used by both the appSettingsProvider and
  /// activeEquipmentProfileProvider watchers because the FITS observer
  /// profile is a *cross-product* of both sources.
  void _pushObserverProfile(NightshadeBackend backend) {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      final profile = _ref.read(activeEquipmentProfileProvider);

      String? cameraMake;
      String? cameraModel;
      final rawCameraName = profile?.cameraName?.trim();
      if (rawCameraName != null && rawCameraName.isNotEmpty) {
        final spaceIdx = rawCameraName.indexOf(' ');
        if (spaceIdx > 0) {
          cameraMake = rawCameraName.substring(0, spaceIdx).trim();
          cameraModel = rawCameraName.substring(spaceIdx + 1).trim();
        } else {
          cameraModel = rawCameraName;
        }
      }

      double? focalLength;
      double? aperture;
      if (profile != null) {
        final tfl = profile.telescopeFocalLength;
        final fl = profile.focalLength;
        if (tfl != null && tfl > 0) {
          focalLength = tfl;
        } else if (fl > 0) {
          focalLength = fl;
        }

        final ta = profile.telescopeAperture;
        if (ta != null && ta > 0) {
          aperture = ta;
        }
      }

      backend.sequencerUpdateObserverProfile(
        observerName: (settings == null || settings.observerName.isEmpty)
            ? null
            : settings.observerName,
        siteElevationM: (settings != null && settings.elevation > 0)
            ? settings.elevation
            : null,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        telescopeName: profile?.telescopeName,
        telescopeFocalLengthMm: focalLength,
        telescopeApertureMm: aperture,
      );
    } catch (e) {
      _logger.error(
        'Failed to propagate observer_profile mid-run: $e',
        source: 'SequenceExecutor',
      );
    }
  }

  void _stopSettingsWatchers() {
    for (final sub in _settingsSubscriptions) {
      sub.close();
    }
    _settingsSubscriptions.clear();
    // Wave 5 Agent 2 — tear down the sky-brightness poll so a stopped
    // executor stops pushing readings to the (possibly torn-down)
    // backend.
    _skyBrightnessPollTimer?.cancel();
    _skyBrightnessPollTimer = null;
    _lastPushedSkyMag = null;
  }

  /// Wave 5 Agent 2 — start the periodic poll that watches the
  /// `SkyBrightnessTracker` and pushes its mag/arcsec² reading to the
  /// executor whenever it changes. Suppresses redundant pushes so the
  /// runtime config event stream stays quiet under steady conditions.
  void _startSkyBrightnessPoll(NightshadeBackend backend) {
    _skyBrightnessPollTimer?.cancel();
    _skyBrightnessPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      try {
        final tracker = _ref.read(skyBrightnessTrackerProvider);
        final mag = tracker.currentMagPerArcsec2();
        // Throttle on absolute change > 0.05 mag/arcsec²; smaller
        // wobble is observational noise that the adapter doesn't need
        // to see on every tick.
        if (mag != _lastPushedSkyMag) {
          final changed = _lastPushedSkyMag == null ||
              mag == null ||
              (mag - (_lastPushedSkyMag ?? 0)).abs() > 0.05;
          if (changed) {
            _lastPushedSkyMag = mag;
            backend.sequencerUpdateSkyBrightness(mag: mag);
            _logger.debug(
              'Pushed sky brightness to executor: ${mag?.toStringAsFixed(2) ?? "<none>"} mag/arcsec²',
              source: 'SequenceExecutor',
            );
          }
        }
      } catch (e) {
        // Don't let a tracker read failure kill the periodic timer —
        // log and keep going. "Errors are a feature" applies to user-
        // visible faults; this is best-effort telemetry.
        _logger.debug(
          'Sky brightness poll failed: $e',
          source: 'SequenceExecutor',
        );
      }
    });
  }

  /// Handle events from the backend (native or remote)
  void _handleSequencerEvent(NightshadeEvent event) {
    _logger.debug(
        'Received event: type=${event.eventType}, category=${event.category}',
        source: 'SequenceExecutor');

    // Handle imaging events for image preview during sequences.
    // This MUST be before the category filter since ExposureComplete has
    // category=imaging.
    if (event.category == EventCategory.imaging &&
        event.eventType == 'ExposureComplete') {
      _logger.debug(
          'ExposureComplete imaging event received - fetching image for preview',
          source: 'SequenceExecutor');
      final durationSecs =
          (event.data['duration_secs'] as num?)?.toDouble() ?? 2.0;
      _fetchAndDisplaySequenceImage(durationSecs);
      return;
    }

    // Only process sequencer events for progress tracking
    if (event.category != EventCategory.sequencer) return;

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);

    switch (event.eventType) {
      case 'NodeStarted':
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final nodeName = event.data['node_type'] as String? ??
            event.data['nodeName'] as String?;
        if (nodeId != null) {
          progressNotifier.updateProgress(
            currentNodeId: nodeId,
            currentNodeName: nodeName,
            currentNodeStatus: NodeStatus.running,
          );
          progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
        }
        break;

      case 'NodeCompleted':
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final statusStr = event.data['status'] as String? ?? 'failed';
        final nodeStatus = switch (statusStr) {
          'success' => NodeStatus.success,
          'skipped' => NodeStatus.skipped,
          'cancelled' => NodeStatus.skipped,
          _ => NodeStatus.failure,
        };
        if (nodeId != null) {
          progressNotifier.updateNodeStatus(nodeId, nodeStatus);
        }
        break;

      case 'ExposureStarted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        final filter = event.data['filter'] as String?;
        final exposureDetail =
            'Frame $frame/$total${filter != null ? ' ($filter)' : ''}';
        progressNotifier.updateProgress(
          message: 'Exposing $exposureDetail',
          currentFilter: filter,
        );
        final exposureNodeId =
            _ref.read(sequenceProgressProvider).currentNodeId;
        if (exposureNodeId != null && total > 0) {
          // frame-1 because exposure just started
          final exposurePercent = (frame - 1) / total * 100.0;
          progressNotifier.updateNodeProgress(
              exposureNodeId, exposurePercent, exposureDetail);
        }
        break;

      case 'ExposureCompleted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 1;
        final durationSecs =
            (event.data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        _recordRunFrame(
          exposureSecs: durationSecs,
          filter: event.data['filter'] as String?,
          accepted: true,
        );
        final newCompletedIntegration =
            _ref.read(sequenceProgressProvider).completedIntegrationSecs +
                durationSecs;
        progressNotifier.updateProgress(
          completedExposures: frame,
          completedIntegrationSecs: newCompletedIntegration,
        );
        final completedNodeId =
            _ref.read(sequenceProgressProvider).currentNodeId;
        if (completedNodeId != null) {
          final completedPercent = total > 0 ? (frame / total * 100.0) : 100.0;
          progressNotifier.updateNodeProgress(
              completedNodeId, completedPercent, 'Completed $frame/$total');
        }

        _fetchAndDisplaySequenceImage(durationSecs);
        break;

      case 'Progress':
        final current = event.data['current'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        progressNotifier.updateProgress(
          completedExposures: current,
          message: 'Progress: $current/$total exposures',
        );
        break;

      case 'TargetStarted':
      case 'TargetChanged':
        final name = event.data['target_name'] as String? ??
            event.data['name'] as String?;
        final ra = (event.data['ra'] as num?)?.toDouble();
        final dec = (event.data['dec'] as num?)?.toDouble();
        progressNotifier.updateProgress(
          currentTarget: name,
          message: name != null ? 'Started target: $name' : null,
        );
        if (name != null && ra != null && dec != null) {
          _logger.debug(
            'Target changed: $name (RA=${ra.toStringAsFixed(4)}h, Dec=${dec.toStringAsFixed(4)}°)',
            source: 'SequenceExecutor',
          );
          final sessionNotifier = _ref.read(sessionStateProvider.notifier);
          sessionNotifier.updateTargetCoordinates(ra: ra, dec: dec);
        }
        break;

      case 'TargetCompleted':
        final name = event.data['target_name'] as String? ??
            event.data['name'] as String?;
        progressNotifier.updateProgress(
          message: 'Completed target: ${name ?? 'unknown'}',
        );
        break;

      case 'Error':
        final message = event.data['message'] as String? ?? 'Unknown error';
        _recordRunError(message);
        progressNotifier.updateProgress(message: 'Error: $message');
        final errorNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (errorNodeId != null) {
          progressNotifier.updateNodeProgress(
              errorNodeId, 0.0, 'Error: $message');
        }
        break;

      case 'InstructionProgressStructured':
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent =
            (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detailKind = event.data['detail_kind'] as String? ?? 'Unknown';
        final detailJson = _decodeStructuredProgressJson(
          event.data['detail_json'],
        );
        final detail = InstructionProgressDetail.fromStructuredData(
          detailKind: detailKind,
          detailJson: detailJson,
        );

        final targetNodeId =
            nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        if (targetNodeId != null) {
          progressNotifier.updateNodeStructuredProgress(
            targetNodeId,
            progressPercent,
            detail,
          );
          progressNotifier.updateProgress(
            message: '$instruction: $detailKind',
          );
        }
        break;

      case 'InstructionProgress':
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent =
            (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detail = event.data['detail'] as String? ?? '';

        _logger.debug(
            'InstructionProgress: nodeId=$nodeId, instruction=$instruction, progress=$progressPercent%, detail=$detail',
            source: 'SequenceExecutor');

        // Use node_id from event, fallback to currentNodeId for backwards compatibility
        final targetNodeId =
            nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        _logger.debug('Updating node progress for: $targetNodeId',
            source: 'SequenceExecutor');
        if (targetNodeId != null) {
          progressNotifier.updateNodeProgress(
              targetNodeId, progressPercent, detail);
          progressNotifier.updateProgress(
            message: '$instruction: $detail',
          );
        }
        break;

      case 'TriggerFired':
        final triggerName =
            event.data['trigger_name'] as String? ?? 'Unknown trigger';
        final action = event.data['action'] as String? ?? '';
        _incrementRunStat((stats) => stats.recordTriggerFire());
        _logger.info('Trigger fired: $triggerName -> $action',
            source: 'SequenceExecutor');
        progressNotifier.updateProgress(
          message: 'Trigger "$triggerName" fired: $action',
        );
        break;

      case 'Started':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Paused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
        break;

      case 'Resumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Completed':
      case 'SequenceCompleted':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('completed');
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.completed;
        break;

      case 'SequenceFailed':
        final error = event.data['error'] as String? ?? 'Unknown error';
        _stopSettingsWatchers();
        _recordRunError(error);
        _finalizeRun('failed');
        progressNotifier.updateProgress(message: error);
        progressNotifier.updateState(SequenceExecutionState.failed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.failed;
        break;

      case 'Stopped':
      case 'SequenceStopped':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('stopped');
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.idle;
        break;

      case 'FrameAccepted':
        // Wave 6 Pack P — the Rust grader now ships `save_path` for
        // accepted frames as well (it already did for rejected
        // frames). The thumbnail strip uses the on-disk path to load
        // an inline preview the same way it does for rejected frames
        // via `reject_path`.
        _registerSequenceFrame(
          event: event,
          isAccepted: true,
          grade: 'pass',
        );
        break;

      case 'FrameRejected':
        // Wave 6 Thumbnails — same as FrameAccepted, but with the
        // reject_path the Rust grader already ships so the strip can
        // surface a "REJECTED" tile that opens the actual file when
        // tapped.
        _registerSequenceFrame(
          event: event,
          isAccepted: false,
          grade: 'reject',
        );
        break;

      case 'PluginNodeRequested':
        // Wave 6 Pack P — the Rust executor reached a
        // `NodeType::PluginNode` and is waiting for us to run the
        // plugin and reply with the verdict. Route through the
        // dispatcher provider (overridden by the app layer to plug in
        // the real `PluginNodeExecutor`); the default stub fails
        // loudly so an un-wired environment surfaces immediately
        // instead of hanging until Rust's 10-minute timeout.
        _dispatchPluginNode(event);
        break;

      case 'PluginNodeProgress':
        // Wave 6 Pack P — informational; plugin-authored intermediate
        // progress payload. The run dashboard's plugin-node panel
        // listens via its own provider; the sequence executor just
        // logs it so the timeline has the breadcrumb.
        final pluginId = event.data['plugin_id'] as String? ?? '';
        final nodeTypeId = event.data['node_type_id'] as String? ?? '';
        final detailJson = event.data['detail_json'] as String? ?? '';
        _logger.debug(
          'PluginNodeProgress: $pluginId/$nodeTypeId $detailJson',
          source: 'SequenceExecutor',
        );
        break;

      case 'DecisionLogged':
        // Wave 8 Replay Debug — persist the structured decision into
        // the `sequence_decisions` Drift table so the Replay screen
        // can scrub through the run later.
        _persistReplayDecision(event);
        break;
    }
  }

  /// Wave 8 Replay Debug — persist a `DecisionLogged` payload into
  /// the `sequence_decisions` table via the [ReplayDebugService].
  /// `unawaited` because the executor's event loop must keep pumping;
  /// the service handles its own change-notification, and a write
  /// failure is logged at warn-level (loud-fail per CLAUDE.md without
  /// taking the executor down).
  Object? _decodeStructuredProgressJson(Object? raw) {
    if (raw is String) {
      if (raw.trim().isEmpty) return const <String, Object?>{};
      try {
        return jsonDecode(raw);
      } catch (_) {
        return {'raw': raw};
      }
    }
    return raw;
  }

  void _persistReplayDecision(NightshadeEvent event) {
    final timestampIso = event.data['timestamp_iso'] as String? ?? '';
    final category = event.data['category'] as String? ?? '';
    final summary = event.data['summary'] as String? ?? '';
    final detailsJson = event.data['details_json'] as String? ?? '{}';
    final nodeId = event.data['node_id'] as String?;
    final rustRunId = event.data['sequence_run_id'] as int?;
    final effectiveRunId = rustRunId ?? _ref.read(currentRunIdProvider);
    if (effectiveRunId == null) {
      // No active run id — the very first lifecycle "Sequence started"
      // decision falls into this window before the Dart row insert
      // completes. We intentionally drop these so the replay log never
      // has dangling rows that can't be joined back to a run.
      _logger.debug(
        'DecisionLogged dropped: no active sequence_run_id '
        '($category: $summary)',
        source: 'SequenceExecutor',
      );
      return;
    }
    final service = _ref.read(replayDebugServiceProvider);
    unawaited(
      service
          .persistFromBridgeEvent(
        timestampIso: timestampIso,
        categoryWireKey: category,
        summary: summary,
        detailsJson: detailsJson,
        nodeId: nodeId,
        sequenceRunId: effectiveRunId,
      )
          .catchError((Object e, StackTrace st) {
        _logger.warning(
          'Failed to persist replay decision ($category: $summary): $e',
          source: 'SequenceExecutor',
        );
        return -1;
      }),
    );
  }

  /// Wave 6 Pack P — route a `PluginNodeRequested` event into the
  /// configured dispatcher and post the verdict back through the
  /// bridge.
  ///
  /// Implementation contract:
  ///   * The dispatcher MUST not throw. If it does (e.g. provider
  ///     overrides went wrong), we still post a failure verdict so
  ///     the executor unblocks instead of timing out at the 10-minute
  ///     default.
  ///   * The verdict is posted via
  ///     `backend.sequencerPluginNodeFinished` — same channel pattern
  ///     as every other sequencer command.
  ///   * We fire-and-forget; the caller (`_handleSequencerEvent`)
  ///     returns immediately so other events keep flowing.
  void _dispatchPluginNode(NightshadeEvent event) {
    final nodeId = event.data['node_id'] as String? ?? '';
    final pluginId = event.data['plugin_id'] as String? ?? '';
    final nodeTypeId = event.data['node_type_id'] as String? ?? '';
    final configJson = event.data['config_json'] as String? ?? '';
    final displayName = event.data['display_name'] as String?;
    final timeoutSecs = event.data['timeout_secs'] as int? ?? 600;

    if (nodeId.isEmpty) {
      _logger.warning(
        'PluginNodeRequested event missing node_id; cannot dispatch '
        '(plugin=$pluginId, node_type=$nodeTypeId)',
        source: 'SequenceExecutor',
      );
      return;
    }

    final backend = _ref.read(backendProvider);
    if (!backend.dispatchPluginNodesLocally) {
      _logger.debug(
        'PluginNodeRequested ignored locally because the backend '
        'delegates plugin dispatch to the remote host '
        '(plugin=$pluginId, node_type=$nodeTypeId, node_id=$nodeId)',
        source: 'SequenceExecutor',
      );
      return;
    }

    final coordinator = _ref.read(pluginNodeDispatchCoordinatorProvider);
    if (!coordinator.claim(nodeId)) {
      _logger.debug(
        'PluginNodeRequested ignored because another local listener is '
        'already dispatching node_id=$nodeId',
        source: 'SequenceExecutor',
      );
      return;
    }
    final dispatcher = _ref.read(pluginNodeDispatcherProvider);

    unawaited(() async {
      late PluginNodeDispatchResult result;
      try {
        result = await dispatcher(
          PluginNodeDispatchRequest(
            nodeId: nodeId,
            pluginId: pluginId,
            nodeTypeId: nodeTypeId,
            configJson: configJson,
            displayName: displayName,
            timeoutSecs: timeoutSecs,
          ),
        );
      } catch (e, st) {
        _logger.error(
          'Plugin node dispatcher threw for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
          source: 'SequenceExecutor',
        );
        result = PluginNodeDispatchResult(
          success: false,
          message: 'dispatcher threw: $e',
        );
      }

      try {
        await backend.sequencerPluginNodeFinished(
          nodeId: nodeId,
          success: result.success,
          message: result.message,
          structuredDetailJson: result.structuredDetailJson,
        );
      } catch (e, st) {
        // The reply itself failed. The Rust executor will time out
        // the node at the configured timeout and surface its own
        // error — but we log loudly here so the operator sees the
        // cause-of-cause.
        _logger.error(
          'Failed to deliver plugin node verdict for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
          source: 'SequenceExecutor',
        );
      } finally {
        coordinator.release(nodeId);
      }
    }());
  }

  /// Wave 6 Thumbnails — translate a typed FrameAccepted / FrameRejected
  /// event into a captured_images row tagged with the producing node id.
  /// Fire-and-forget; failures are logged so the strip's "errors are a
  /// feature" contract holds, but they never block the run.
  void _registerSequenceFrame({
    required NightshadeEvent event,
    required bool isAccepted,
    required String grade,
  }) {
    final nodeId = event.data['node_id'] as String?;
    if (nodeId == null || nodeId.isEmpty) {
      // No producing node — typically a wizard-driven capture (flat
      // wizard, polar-align). Nothing for the sequence-tree strip to
      // hang the row off of, so we skip.
      return;
    }
    final hfr = (event.data['hfr'] as num?)?.toDouble();
    final eccentricity = (event.data['eccentricity'] as num?)?.toDouble();
    final starCount = event.data['star_count'] as int?;
    // Wave 6 Pack P — accepted frames now carry the on-disk save_path
    // alongside the existing rejected-frame reject_path. The thumbnail
    // strip uses whichever field is populated to load the inline
    // preview. `save_path` may legitimately be null on legacy emit
    // sites that did not thread the path through (defaulting to empty
    // string preserves the old "no thumbnail yet" colour-bordered
    // tile fallback rather than skipping the row entirely).
    final filePath = isAccepted
        ? (event.data['save_path'] as String? ?? '')
        : (event.data['reject_path'] as String? ?? '');
    final fileName = filePath.isEmpty ? '' : p.basename(filePath);
    final rejectionReason =
        isAccepted ? null : (event.data['reason'] as String?);
    final progress = _ref.read(sequenceProgressProvider);
    final filter = progress.currentFilter;
    final runId = _ref.read(currentRunIdProvider);
    final runIdString = runId?.toString();
    final dao = _ref.read(imagesDaoProvider);
    final sidecarService = _ref.read(thumbnailSidecarServiceProvider);

    unawaited(() async {
      try {
        await dao.insertSequenceFrame(
          filePath: filePath,
          fileName: fileName,
          fileFormat:
              filePath.toLowerCase().endsWith('.xisf') ? 'xisf' : 'fits',
          // Use a stand-in 1.0s when the grader didn't ship a duration —
          // the column is NOT NULL on the SQL side. The dashboard will
          // surface this as "1.0s" but the user's running sequence will
          // overwrite it on the next graded frame.
          exposureDuration: 1.0,
          capturedAt: DateTime.now(),
          isAccepted: isAccepted,
          producingNodeId: nodeId,
          producingRunId: runIdString,
          runtimeGrade: grade,
          rejectionReason: rejectionReason,
          filter: filter,
          frameType: 'light',
          hfr: hfr,
          starCount: starCount,
          eccentricity: eccentricity,
          logger: _logger,
          sidecarService: sidecarService,
        );
      } catch (e) {
        _logger.warning(
          'Wave 6 Thumbnails: failed to register sequence frame for '
          'node $nodeId ($grade): $e',
          source: 'SequenceExecutor',
        );
      }
    }());
  }

  void _recordRunFrame({
    required double exposureSecs,
    required bool accepted,
    String? filter,
  }) {
    _incrementRunStat((stats) {
      final progress = _ref.read(sequenceProgressProvider);
      stats.recordFrame(
        target: progress.currentTarget ??
            _ref.read(currentSequenceProvider)?.name ??
            'Sequence',
        filter: (filter != null && filter.isNotEmpty) ? filter : 'Unknown',
        exposureSecs: exposureSecs,
        accepted: accepted,
      );
    });
  }

  void _recordRunError(String message) {
    _incrementRunStat((stats) => stats.recordError(message));
  }

  void _incrementRunStat(void Function(SequenceRunStats stats) update) {
    final stats = _ref.read(liveSequenceStatsProvider);
    if (stats == null) {
      return;
    }
    update(stats);
    _ref.read(liveSequenceStatsProvider.notifier).state = stats;
    _persistLiveRunStats();
  }

  void _persistLiveRunStats() {
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    unawaited(
      _ref.read(sequenceRunsDaoProvider).updateStats(runId, stats.toJson()),
    );
  }

  void _finalizeRun(String status) {
    if (_runFinalized) {
      return;
    }
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    _runFinalized = true;
    stats.endTime = DateTime.now();
    final statsJson = stats.toJson();
    unawaited(
      _ref.read(sequenceRunsDaoProvider).finishRun(runId, status, statsJson),
    );
    // Wave 5.5 — surface post-session diagnostics + clear the
    // NotificationRouter override. `_finalizeRun` already early-returns
    // when called twice so these hooks fire exactly once per run.
    _captureSessionEndHooks();
  }

  // =========================================================================
  // Wave 5.5 — session lifecycle hooks
  // =========================================================================

  /// Capture the optical-train baseline + register the active sequence
  /// with the notification router at session start.
  ///
  /// Each step is wrapped in try/catch because failure is non-fatal:
  /// the user wants imaging to proceed even when diagnostics or
  /// notifications are unavailable. We surface a single info-level
  /// log per failure so the user can still trace why their post-
  /// session report is empty.
  void _captureSessionStartHooks(String sequenceId) {
    _activeSequenceId = sequenceId;
    _sessionStartedAt = DateTime.now();

    // --- Notification router active-sequence override -----------------
    try {
      final router = _ref.read(notificationRouterProvider);
      router.setActiveSequence(sequenceId);
      _logger.debug(
        'NotificationRouter.setActiveSequence($sequenceId) at session start',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      // Notification setup failure must never block imaging — log and
      // continue. The user gets a working sequence with global routing
      // rules instead of per-sequence overrides.
      _logger.warning(
        'Failed to register active sequence with NotificationRouter: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Optical-train baseline capture -------------------------------
    try {
      final baseline = _captureOpticalTrainBaseline();
      if (baseline == null) {
        _logger.info(
          'Optical-train diagnostics unavailable at session start '
          '(no PSF tiles or solved frames yet); baseline will be '
          'captured at session end instead.',
          source: 'SequenceExecutor',
        );
      } else {
        _sessionStartBaseline = baseline;
        // Push to both the baseline provider (pre-flight comparison
        // source) and the current-snapshot provider (so the live
        // dashboard reflects the start-of-run state until a fresh
        // snapshot supersedes it mid-run).
        _ref.read(opticalTrainBaselineProvider.notifier).state = baseline;
        _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
            baseline;
        _logger.debug(
          'Captured optical-train baseline at session start: '
          'tilt=${baseline.tiltScore.toStringAsFixed(1)}, '
          'collimation=${baseline.collimationScore.toStringAsFixed(1)}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to capture optical-train baseline at session start: $e\n$st',
        source: 'SequenceExecutor',
      );
    }
  }

  /// Finalize post-session diagnostics + clear the notification router
  /// override at session end.
  ///
  /// Called exactly once per run via `_finalizeRun`. Safe to call when
  /// session hooks never fired (e.g. start failed mid-way): the
  /// `_activeSequenceId` guard short-circuits cleanly.
  void _captureSessionEndHooks() {
    final sequenceId = _activeSequenceId;
    final sessionStart = _sessionStartedAt;

    if (sequenceId == null) {
      // start() never finished its hooks (the run aborted before the
      // session-start phase). Nothing to tear down.
      _logger.debug(
        'Skipping session-end hooks: no active sequence id recorded',
        source: 'SequenceExecutor',
      );
      return;
    }

    // --- Notification router clear --------------------------------------
    try {
      final router = _ref.read(notificationRouterProvider);
      router.setActiveSequence(null);
      _logger.debug(
        'NotificationRouter.setActiveSequence(null) at session end '
        '(was: $sequenceId)',
        source: 'SequenceExecutor',
      );
    } catch (e) {
      _logger.warning(
        'Failed to clear active sequence on NotificationRouter: $e',
        source: 'SequenceExecutor',
      );
    }

    // --- Optical-train post-session snapshot + drift ------------------
    OpticalTrainBaseline? postSnapshot;
    try {
      postSnapshot = _captureOpticalTrainBaseline();
      if (postSnapshot != null) {
        _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
            postSnapshot;
        // Promote the post-session snapshot to the new baseline for
        // the NEXT session's pre-flight comparison. Without this the
        // baseline would keep pointing at the start of the just-
        // finished run, so the second session would see no drift.
        _ref.read(opticalTrainBaselineProvider.notifier).state = postSnapshot;
        if (_sessionStartBaseline != null) {
          final drift =
              _sessionStartBaseline!.driftAgainst(OpticalTrainDiagnostics(
            tiltScore: postSnapshot.tiltScore,
            collimationScore: postSnapshot.collimationScore,
            dominantTiltDirection: 'unknown',
            issues: const [],
          ));
          _logger.info(
            'Optical-train drift vs. session-start baseline: '
            '${drift.toStringAsFixed(2)} (tilt '
            '${_sessionStartBaseline!.tiltScore.toStringAsFixed(1)} → '
            '${postSnapshot.tiltScore.toStringAsFixed(1)}, '
            'collimation '
            '${_sessionStartBaseline!.collimationScore.toStringAsFixed(1)} → '
            '${postSnapshot.collimationScore.toStringAsFixed(1)})',
            source: 'SequenceExecutor',
          );
        }
        _logger.debug(
          'Captured optical-train post-session snapshot: '
          'tilt=${postSnapshot.tiltScore.toStringAsFixed(1)}, '
          'collimation=${postSnapshot.collimationScore.toStringAsFixed(1)}',
          source: 'SequenceExecutor',
        );
      } else {
        // No live PSF/residual data at session end — fall back to the
        // start-of-session baseline (if we captured one) so the
        // dashboard's current snapshot at least shows the entry
        // state instead of stale data from a previous run.
        if (_sessionStartBaseline != null) {
          _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
              _sessionStartBaseline;
        }
        _logger.info(
          'Optical-train diagnostics unavailable at session end; '
          'post-session diagnostics will omit drift comparison.',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to capture optical-train post-session snapshot: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Post-session health summary ---------------------------------
    try {
      final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
      if (dbSessionId == null) {
        _logger.info(
          'No active database session id at end of run; '
          'post-session diagnostics summary will not be published.',
          source: 'SequenceExecutor',
        );
      } else {
        final summary = _buildPostSessionHealthSummary(
          sessionStartedAt: sessionStart,
        );
        _ref
            .read(postSessionHealthSummaryProvider(dbSessionId).notifier)
            .state = summary;
        _logger.debug(
          'Published post-session diagnostics for session $dbSessionId: '
          'disconnects=${summary.disconnectsDuringSession}, '
          'focuserMoves=${summary.focuserMoves}, '
          'noticedConcerns=${summary.noticedConcerns.length}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to publish post-session diagnostics: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Smart Night guide-RMS history --------------------------------
    try {
      final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
      if (dbSessionId != null) {
        final mountState = _ref.read(mountStateProvider);
        final profileMountId =
            _ref.read(activeEquipmentProfileProvider)?.mountId;
        final mountId =
            mountState.connectionState == DeviceConnectionState.connected
                ? mountState.deviceId
                : profileMountId;
        final collector = GuideRmsCollector(
          imagesDao: _ref.read(imagesDaoProvider),
          guideRmsHistoryDao: _ref.read(guideRmsHistoryDaoProvider),
        );
        unawaited(
          collector
              .collectSession(
            sessionId: dbSessionId,
            mountId: mountId,
            recordedAt: DateTime.now(),
          )
              .catchError((Object e, StackTrace st) {
            _logger.warning(
              'Failed to collect Smart Night guide-RMS history: $e\n$st',
              source: 'SequenceExecutor',
            );
            return null;
          }),
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to schedule Smart Night guide-RMS collection: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // Reset for the next run. Don't clear `_sessionStartBaseline`
    // until here so the post-session hook above could reference it.
    _activeSequenceId = null;
    _sessionStartedAt = null;
    _sessionStartBaseline = null;
  }

  /// Snapshot the live optical-train diagnostics for the active session
  /// and convert to an [OpticalTrainBaseline]. Returns `null` when no
  /// diagnostics data is available (no solved frames yet, no PSF
  /// tiles, no live session).
  ///
  /// Uses the same data path as the analytics tab so the values shown
  /// in the History dialog match the live dashboard — pulled directly
  /// from the PSF / residual provider streams rather than re-running
  /// the analysis on raw FITS files.
  OpticalTrainBaseline? _captureOpticalTrainBaseline() {
    final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
    if (dbSessionId == null) return null;
    final psfTiles =
        _ref.read(sessionPsfTilesProvider(dbSessionId)).valueOrNull ?? const [];
    final residuals =
        _ref.read(sessionResidualVectorsProvider(dbSessionId)).valueOrNull ??
            const [];
    if (psfTiles.isEmpty) {
      // Nothing solved yet — calling analyze() would emit the
      // "No diagnostics data" placeholder, which has tilt=0 and
      // collimation=0 and would look like a "zero drift" baseline.
      // Returning null preserves the honest "no data" signal.
      return null;
    }
    final service = _ref.read(opticalTrainDiagnosticsServiceProvider);
    final diagnostics = service.analyze(
      psfTiles: psfTiles,
      residualVectors: residuals,
    );
    return OpticalTrainBaseline.fromDiagnostics(diagnostics);
  }

  /// Build the post-session diagnostics summary from the run stats +
  /// USB disconnect log.
  ///
  /// The summary surfaces:
  ///   * USB disconnects that occurred during this run (not the rolling
  ///     24 h window — the user already saw earlier flakes the last time
  ///     they opened the report).
  ///   * Total focuser moves recorded across the run (sourced from
  ///     `liveSequenceStatsProvider.autofocusRuns` — an autofocus run
  ///     equals N moves of the focuser).
  ///   * Verbatim warning messages collected by `SequenceRunStats`
  ///     during the run, including filter-lookup fallbacks and any
  ///     other "noticed but did not fire" concerns the executor saw.
  ///
  ///   * Cooler temperature samples outside the setpoint band.
  ///   * Sky-brightness min / max / median from the adaptive-exposure
  ///     tracker's calibrated mag/arcsec² samples.
  PostSessionHealthSummary _buildPostSessionHealthSummary({
    DateTime? sessionStartedAt,
  }) {
    final stats = _ref.read(liveSequenceStatsProvider);
    final disconnectLog = _ref.read(usbDisconnectLogProvider);

    final disconnectsDuringSession = sessionStartedAt == null
        ? disconnectLog.totalLast24h()
        : disconnectLog.countSince(sessionStartedAt);

    final focuserMoves = stats?.autofocusRuns ?? 0;

    final noticedConcerns = <String>[];
    if (stats != null) {
      // Warnings collected via SequenceRunStats.recordWarning are
      // already deduplicated against consecutive identical messages,
      // so we surface them as-is.
      noticedConcerns.addAll(stats.warningMessages);
    }

    final skyStats = _skyBrightnessSummarySince(sessionStartedAt);

    return PostSessionHealthSummary(
      disconnectsDuringSession: disconnectsDuringSession,
      coolerOutOfBandSamples: _coolerOutOfBandSamplesSince(sessionStartedAt),
      focuserMoves: focuserMoves,
      skyBrightnessMin: skyStats?.min,
      skyBrightnessMax: skyStats?.max,
      skyBrightnessMedian: skyStats?.median,
      noticedConcerns: noticedConcerns,
    );
  }

  int _coolerOutOfBandSamplesSince(DateTime? sessionStartedAt) {
    final history = _ref.read(temperatureHistoryProvider);
    var count = 0;
    for (final point in history) {
      if (sessionStartedAt != null && point.time.isBefore(sessionStartedAt)) {
        continue;
      }
      final target = point.targetTemp;
      if (target == null) continue;
      if ((point.temperature - target).abs() > kCoolerSetpointBandDegC) {
        count++;
      }
    }
    return count;
  }

  ({double min, double max, double median})? _skyBrightnessSummarySince(
    DateTime? sessionStartedAt,
  ) {
    final samples = _ref
        .read(skyBrightnessTrackerProvider)
        .magSamplesSince(sessionStartedAt)
        .where((value) => value.isFinite)
        .toList()
      ..sort();
    if (samples.isEmpty) return null;

    final mid = samples.length ~/ 2;
    final median = samples.length.isOdd
        ? samples[mid]
        : (samples[mid - 1] + samples[mid]) / 2.0;
    return (
      min: samples.first,
      max: samples.last,
      median: median,
    );
  }

  /// Fetch the last captured image and update the UI providers so the Imaging
  /// tab and Dashboard show sequence frames as they complete.
  void _fetchAndDisplaySequenceImage(double durationSecs) {
    // Fire-and-forget; image display is non-critical for sequence correctness.
    Future(() async {
      try {
        final cameraState = _ref.read(cameraStateProvider);
        final cameraDeviceId = cameraState.deviceId;
        if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
          _logger.debug('No camera device ID available, skipping image fetch',
              source: 'SequenceExecutor');
          return;
        }
        final backend = _ref.read(backendProvider);
        final capturedImage = await backend.cameraGetLastImage(cameraDeviceId);
        if (capturedImage == null) {
          _logger.debug('No image data available from camera',
              source: 'SequenceExecutor');
          return;
        }

        final imageData = capturedImageDataFromResult(
          capturedImage: capturedImage,
          capturedAt: DateTime.now(),
          settings: ExposureSettings(
            exposureTime: durationSecs,
            gain: 0, // Not available from sequence event
            offset: 0,
            binningX: 1,
            binningY: 1,
            frameType: FrameType.light,
          ),
        );

        _ref.read(capturePreviewPublisherProvider).publish(
              _ref,
              imageData,
              cameraDeviceId,
            );
      } catch (e) {
        // Image display is non-critical; log only.
        _logger.warning('Failed to fetch sequence image for display: $e',
            source: 'SequenceExecutor');
      }
    });
  }

  bool _pauseResumeInProgress = false;

  /// Wait for state change with timeout
  Future<bool> _awaitStateChange(SequenceExecutionState expectedState,
      {Duration timeout = const Duration(seconds: 5)}) async {
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
      _logger.warning('Failed to clear checkpoint on stop: $e',
          source: 'SequenceExecutor');
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
      _logger.warning('Error resetting native sequencer: $e',
          source: 'SequenceExecutor');
      // The Dart-side reset above is the authoritative source of truth.
    }

    try {
      await backend.discardCheckpoint();
    } catch (e) {
      _logger.warning('Error clearing checkpoint on reset: $e',
          source: 'SequenceExecutor');
    }

    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;

    _logger.info('Sequence reset - ready to run from beginning',
        source: 'SequenceExecutor');
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
  Future<void> resumeFromCheckpoint() async {
    final backend = _ref.read(backendProvider);

    final info = await backend.getCheckpointInfo();
    if (info == null || !info.canResume) {
      throw Exception('No valid checkpoint to resume from');
    }

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    progressNotifier.updateState(SequenceExecutionState.running);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    progressNotifier.updateProgress(
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      message: 'Resuming from checkpoint...',
    );

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
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
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

    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
    );

    await backend.resumeFromCheckpoint();
  }

  /// Discard the current checkpoint
  Future<void> discardCheckpoint() async {
    final backend = _ref.read(backendProvider);
    await backend.discardCheckpoint();
  }

  /// Start periodic checkpoint saves (every 30 seconds while running).
  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_ref.read(sequenceExecutionStateProvider) ==
          SequenceExecutionState.running) {
        try {
          final backend = _ref.read(backendProvider);
          await backend.saveCheckpoint();
        } catch (e) {
          // Checkpoint write failure must not interrupt the running sequence;
          // the next tick will retry.
          _logger.warning('Failed to save checkpoint: $e',
              source: 'SequenceExecutor');
        }
      }
    });
  }

  /// Start the disk-space watchdog for the duration of this run.
  ///
  /// Watches the capture directory and:
  ///  - logs a warning event when free space drops below the configured
  ///    warning threshold (default 10 GB);
  ///  - pauses the running sequence when free space drops below the configured
  ///    abort threshold (default 2 GB), so the in-flight frame finishes
  ///    cleanly rather than the OS killing the writer mid-stream.
  ///
  /// Skipped silently when no capture path is configured — the pre-flight
  /// dialog already warns about that and there's nothing useful to monitor.
  void _startDiskSpaceWatchdog() {
    _diskWatchdogSubscription?.cancel();
    _diskWatchdogSubscription = null;

    final settings = _ref.read(appSettingsProvider).valueOrNull;
    final capturePath = settings?.imageOutputPath ?? '';
    if (capturePath.isEmpty) {
      _logger.warning(
        'Disk-space watchdog not started: no capture path configured',
        source: 'SequenceExecutor',
      );
      return;
    }

    final guard = _ref.read(diskSpaceGuardProvider);
    guard.start(capturePath: capturePath);
    _diskWatchdogSubscription = guard.events.listen((event) async {
      _logger.warning(
        '[disk-watchdog] ${event.message}',
        source: 'SequenceExecutor',
      );
      if (event.severity == DiskSpaceSeverity.blocking) {
        // Critical: pause the run so the user can intervene. We do NOT
        // fully stop because that would lose the checkpoint; pause keeps
        // state preserved.
        try {
          await pause();
        } catch (e, stack) {
          _logger.error(
            'Failed to pause sequence on disk-space abort: $e\n$stack',
            source: 'SequenceExecutor',
          );
        }
      }
    });
  }

  void _stopDiskSpaceWatchdog() {
    _diskWatchdogSubscription?.cancel();
    _diskWatchdogSubscription = null;
    try {
      _ref.read(diskSpaceGuardProvider).stop();
    } catch (_) {
      // Disposed provider — ignore.
    }
  }

  /// Cancel all owned timers and subscriptions.
  ///
  /// Wired into the owning Provider's `ref.onDispose`. Safe to call even when
  /// no sequence is running — all cancels are null-tolerant. Distinct from
  /// `stop()`, which also mutates execution state and ends the session.
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
