import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/nightshade_backend.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/imaging/imaging_models.dart';
import '../../models/sequence/sequence_models.dart';
import '../../models/settings/app_settings.dart'
    show ObserverLocation, SafetyFailMode;
import '../../services/disk_space_guard.dart';
import '../../services/imaging_service.dart';
import '../../services/logging_service.dart';
import '../backend_provider.dart';
import '../disk_space_provider.dart';
import '../equipment_provider.dart';
import '../imaging_provider.dart';
import '../meridian_flip_provider.dart';
import '../profiles_provider.dart';
import '../sequence_provider.dart'
    show
        currentSequenceProvider,
        sequenceExecutionStateProvider,
        sequenceProgressProvider;
import '../sequence_stats_provider.dart';
import '../session_provider.dart';
import '../settings_provider.dart';
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
        return {
          'type': 'Conditional',
          'condition': {
            'type': _conditionalTypeToString(n.conditionType),
            'value': conditionValue,
          },
        };
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

    final triggerMethod =
        useGlobal ? global.triggerMethod : node.triggerMethod;
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
    final settleTime =
        useGlobal ? global.settleTimeSeconds : node.settleTime;
    final resumeGuiding =
        useGlobal ? global.resumeGuidingAfterFlip : node.resumeGuiding;
    final maxRetries = useGlobal ? global.maxRetries : node.maxRetries;
    final failureAction =
        useGlobal ? global.failureAction : node.failureAction;

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
    }
  }

  /// Validate the sequence about to run. Delegates to the top-level
  /// [validation.validateSequence] in `sequence_validation.dart`; kept as an
  /// instance method to preserve the historical call site.
  List<validation.ValidationIssue> validateSequence(Sequence sequence) =>
      validation.validateSequence(sequence);

  Future<void> start() async {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) {
      throw Exception('No sequence loaded');
    }

    final issues = validateSequence(sequence);
    final errors = issues
        .where((i) => i.severity == validation.ValidationSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      throw Exception('Cannot start sequence: ${errors.first.title}');
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
    await sessionNotifier.startSession(
      targetName: sequence.name,
      targetRa: sequence.targetHeaders.isNotEmpty
          ? sequence.targetHeaders.first.raHours
          : null,
      targetDec: sequence.targetHeaders.isNotEmpty
          ? sequence.targetHeaders.first.decDegrees
          : null,
    );
    sessionNotifier.setTotalExposures(sequence.totalExposures);
    final runId = await _ref.read(sequenceRunsDaoProvider).startRun(
          sequenceId: sequence.databaseId,
          sequenceName: sequence.name,
        );
    _ref.read(currentRunIdProvider.notifier).state = runId;
    _ref.read(liveSequenceStatsProvider.notifier).state = SequenceRunStats();
    _runFinalized = false;

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
      final modeString = switch (settings.safetyFailMode) {
        SafetyFailMode.failOpen => 'fail_open',
        SafetyFailMode.warnOnly => 'warn_only',
        SafetyFailMode.failClosed => 'fail_closed',
      };
      await backend.sequencerSetSafetyFailMode(modeString);
      _logger.debug('Safety fail mode set to: $modeString',
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

  /// Start watching for settings changes that should be propagated to the
  /// backend executor during sequence execution (dither config, location,
  /// filter offsets).
  void _startSettingsWatchers(NightshadeBackend backend) {
    _stopSettingsWatchers();

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
      }),
    );

    _settingsSubscriptions.add(
      _ref.listen(activeEquipmentProfileProvider, (previous, next) {
        if (previous == null || next == null) return;
        final prevRaw = previous.filterFocusOffsets;
        final nextRaw = next.filterFocusOffsets;
        if (prevRaw != nextRaw) {
          _logger.debug(
            'Filter focus offsets changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          // filterFocusOffsets is a JSON-encoded string; decode to Map<String, int>
          Map<String, int> offsets = {};
          if (nextRaw != null && nextRaw.isNotEmpty) {
            try {
              final decoded = json.decode(nextRaw) as Map<String, dynamic>;
              offsets = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
            } catch (e) {
              _logger.error(
                'Failed to decode filter focus offsets: $e',
                source: 'SequenceExecutor',
              );
              return;
            }
          }
          backend.sequencerUpdateFilterOffsets(offsets);
        }
      }),
    );
  }

  void _stopSettingsWatchers() {
    for (final sub in _settingsSubscriptions) {
      sub.close();
    }
    _settingsSubscriptions.clear();
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
    }
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

        final imageData = CapturedImageData(
          width: capturedImage.width,
          height: capturedImage.height,
          displayData: Uint8List.fromList(capturedImage.displayData),
          histogram: capturedImage.histogram,
          stats: ImageStats(
            min: capturedImage.stats.min,
            max: capturedImage.stats.max,
            mean: capturedImage.stats.mean,
            median: capturedImage.stats.median,
            stdDev: capturedImage.stats.stdDev,
            hfr: capturedImage.stats.hfr ?? 0.0,
            // FWHM ≈ 2.35 * HFR
            fwhm: (capturedImage.stats.hfr ?? 0.0) * 2.35,
            starCount: capturedImage.stats.starCount,
            background: capturedImage.stats.mean - capturedImage.stats.stdDev,
            noise: capturedImage.stats.stdDev,
            snr: capturedImage.stats.stdDev > 0
                ? capturedImage.stats.mean / capturedImage.stats.stdDev
                : 0.0,
          ),
          capturedAt: DateTime.now(),
          settings: ExposureSettings(
            exposureTime: durationSecs,
            gain: 0, // Not available from sequence event
            offset: 0,
            binningX: 1,
            binningY: 1,
            frameType: FrameType.light,
          ),
          isColor: capturedImage.isColor,
        );

        _ref.read(currentImageProvider.notifier).state = imageData;
        _ref.read(lastImageStatsProvider.notifier).state = imageData.stats;
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

  Future<void> stop() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;
    _stopDiskSpaceWatchdog();
    _stopSettingsWatchers();
    _startTime = null;
    _isPaused = false;
    _ref
        .read(sequenceProgressProvider.notifier)
        .updateState(SequenceExecutionState.idle);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;
    _finalizeRun('stopped');

    _ref.read(sessionStateProvider.notifier).endSession(status: 'stopped');

    final backend = _ref.read(backendProvider);
    await backend.sequencerStop();

    // Clear checkpoint when stopped gracefully
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
