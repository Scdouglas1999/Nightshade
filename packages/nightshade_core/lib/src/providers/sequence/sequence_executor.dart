import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/nightshade_backend.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/imaging/imaging_models.dart';
import '../../models/sequence/sequence_models.dart';
import '../../models/settings/app_settings.dart' show ObserverLocation;
import '../../services/imaging_service.dart';
import '../../services/logging_service.dart';
import '../backend_provider.dart';
import '../equipment_provider.dart';
import '../imaging_provider.dart';
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
  Timer? _checkpointTimer;
  bool _runFinalized = false;

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

  /// Convert Dart sequence to JSON for native executor
  String _sequenceToJson(Sequence sequence) {
    final nodeDefinitions = <Map<String, dynamic>>[];

    void processNode(SequenceNode node) {
      final Map<String, dynamic> nodeType = _nodeToConfig(node);

      nodeDefinitions.add({
        'id': node.id,
        'name': node.name,
        'node_type': nodeType,
        'enabled': node.isEnabled,
        'children': node.childIds,
      });

      for (final childId in node.childIds) {
        final child = sequence.nodes[childId];
        if (child != null) {
          processNode(child);
        }
      }
    }

    if (sequence.rootNode != null) {
      processNode(sequence.rootNode!);
    }

    return jsonEncode({
      'id': sequence.id,
      'name': sequence.name,
      'description': sequence.description,
      'nodes': nodeDefinitions,
      'root_node_id': sequence.rootNodeId,
      'metadata': {},
    });
  }

  /// Look up filter index from profile by name (case-insensitive)
  int? _lookupFilterIndex(String? filterName) {
    if (filterName == null || filterName.isEmpty) return null;
    final profile = _ref.read(activeEquipmentProfileProvider);
    if (profile == null) return null;
    final filterNames = profile.filterNames;
    for (int i = 0; i < filterNames.length; i++) {
      if (filterNames[i].toLowerCase() == filterName.toLowerCase()) {
        return i;
      }
    }
    return null;
  }

  /// Convert a Dart node to native config format
  Map<String, dynamic> _nodeToConfig(SequenceNode node) {
    if (node is ExposureNode) {
      final defaults = _ref.read(sequencerDefaultsProvider);
      // Auto-populate filter_index from profile if not set
      final filterIndex = node.filterIndex ?? _lookupFilterIndex(node.filter);
      return {
        'type': 'TakeExposure',
        'duration_secs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'filter_index': filterIndex,
        'gain': node.gain,
        'offset': node.offset,
        'binning': _binningToString(node.binning),
        'dither_every': node.ditherEvery,
        'dither_pixels': defaults.ditherPixels,
        'dither_settle_pixels': defaults.ditherSettlePixels,
        'dither_settle_time': defaults.ditherSettleTime,
        'dither_settle_timeout': defaults.ditherSettleTimeout,
        'dither_ra_only': defaults.ditherRaOnly,
        'save_to': null,
      };
    } else if (node is SlewNode) {
      return {
        'type': 'SlewToTarget',
        'use_target_coords': node.useTargetCoords,
        'custom_ra': node.customRa,
        'custom_dec': node.customDec,
      };
    } else if (node is CenterNode) {
      return {
        'type': 'CenterTarget',
        'use_target_coords': node.useTargetCoords,
        'accuracy_arcsec': node.accuracyArcsec,
        'max_attempts': node.maxAttempts,
        'exposure_duration': 3.0, // Default exposure for centering
        'filter': null,
      };
    } else if (node is AutofocusNode) {
      return {
        'type': 'Autofocus',
        'method': _autofocusMethodToString(node.method),
        'step_size': node.stepSize,
        'steps_out': node.stepsOut,
        'exposure_duration': node.exposureDuration,
        'filter': null,
        'binning': 'One',
      };
    } else if (node is DitherNode) {
      return {
        'type': 'Dither',
        'pixels': node.pixels,
        'settle_pixels': node.settlePixels,
        'settle_time': node.settleTime,
        'settle_timeout': node.settleTimeout,
        'ra_only': node.raOnly,
      };
    } else if (node is StartGuidingNode) {
      return {
        'type': 'StartGuiding',
        'settle_pixels': node.settlePixels,
        'settle_time': node.settleTime,
        'settle_timeout': node.settleTimeout,
        'auto_select_star': node.autoSelectStar,
      };
    } else if (node is StopGuidingNode) {
      return {'type': 'StopGuiding'};
    } else if (node is FilterChangeNode) {
      // Auto-populate filter_index from profile if not set
      final filterIndex =
          node.filterPosition ?? _lookupFilterIndex(node.filterName);
      return {
        'type': 'ChangeFilter',
        'filter_name': node.filterName,
        'filter_index': filterIndex,
      };
    } else if (node is CoolCameraNode) {
      return {
        'type': 'CoolCamera',
        'target_temp': node.targetTemp,
        'duration_mins': node.durationMins,
      };
    } else if (node is WarmCameraNode) {
      return {
        'type': 'WarmCamera',
        'rate_per_min': node.ratePerMin,
        'target_temp': node.targetTemp,
      };
    } else if (node is RotatorNode) {
      return {
        'type': 'MoveRotator',
        'target_angle': node.targetAngle,
        'relative': node.relative,
      };
    } else if (node is ParkNode) {
      return {'type': 'Park'};
    } else if (node is UnparkNode) {
      return {'type': 'Unpark'};
    } else if (node is WaitTimeNode) {
      return {
        'type': 'WaitForTime',
        'wait_until': node.waitUntil?.millisecondsSinceEpoch,
        'wait_for_twilight': node.waitForTwilight != null
            ? _twilightToString(node.waitForTwilight!)
            : null,
      };
    } else if (node is DelayNode) {
      return {
        'type': 'Delay',
        'seconds': node.seconds,
      };
    } else if (node is NotificationNode) {
      return {
        'type': 'Notification',
        'title': node.title,
        'message': node.message,
        'level': _notificationLevelToString(node.level),
      };
    } else if (node is ScriptNode) {
      return {
        'type': 'RunScript',
        'script_path': node.scriptPath,
        'arguments': node.arguments,
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is TargetHeaderNode) {
      return {
        'type': 'TargetHeader',
        'target_name': node.targetName,
        'ra_hours': node.raHours,
        'dec_degrees': node.decDegrees,
        'rotation': node.rotation,
        'min_altitude': node.minAltitude,
        'max_altitude': node.maxAltitude,
        'priority': node.priority,
        'start_after': node.startAfter?.millisecondsSinceEpoch,
        'end_before': node.endBefore?.millisecondsSinceEpoch,
        'mosaic_panel': node.mosaicPanel?.toJson(),
      };
    } else if (node is InstructionSetNode) {
      // InstructionSet maps to a Loop with count=1 on the backend
      return {
        'type': 'Loop',
        'iterations': 1,
        'condition': 'Count',
        'condition_value': 1,
      };
    } else if (node is LoopNode) {
      dynamic conditionValue;
      switch (node.conditionType) {
        case LoopConditionType.count:
          conditionValue = node.repeatCount;
          break;
        case LoopConditionType.untilTime:
          conditionValue = node.repeatUntil?.millisecondsSinceEpoch;
          break;
        case LoopConditionType.untilAltitude:
        case LoopConditionType.altitudeAbove:
          conditionValue = node.repeatUntilAltitude;
          break;
        case LoopConditionType.integrationTime:
          conditionValue = node.repeatCount;
          break;
        case LoopConditionType.forever:
        case LoopConditionType.whileDark:
          conditionValue = null;
          break;
      }
      return {
        'type': 'Loop',
        'iterations': node.repeatCount,
        'condition': _loopConditionToString(node.conditionType),
        'condition_value': conditionValue,
      };
    } else if (node is ParallelNode) {
      return {
        'type': 'Parallel',
        'required_successes': node.requiredSuccesses,
      };
    } else if (node is ConditionalNode) {
      dynamic conditionValue;
      switch (node.conditionType) {
        case ConditionalType.always:
        case ConditionalType.weatherSafe:
        case ConditionalType.safetyMonitorSafe:
          conditionValue = null;
          break;
        case ConditionalType.altitudeAbove:
        case ConditionalType.guidingRmsBelow:
        case ConditionalType.hfrBelow:
        case ConditionalType.moonSeparationAbove:
          conditionValue = node.thresholdValue;
          break;
        case ConditionalType.timeAfter:
          conditionValue = node.thresholdTime?.millisecondsSinceEpoch;
          break;
      }
      return {
        'type': 'Conditional',
        'condition': {
          'type': _conditionalTypeToString(node.conditionType),
          'value': conditionValue,
        },
      };
    } else if (node is RecoveryNode) {
      return {
        'type': 'Recovery',
        'trigger': null,
        'recovery_action': _recoveryActionToString(node.recoveryAction),
        'max_retries': node.maxRetries,
      };
    } else if (node is MeridianFlipNode) {
      return {
        'type': 'MeridianFlip',
        'minutes_past_meridian': node.minutesPastMeridian,
        'pause_guiding': node.pauseGuiding,
        'auto_center': node.autoCenter,
        'settle_time': node.settleTime,
      };
    } else if (node is OpenDomeNode) {
      return {
        'type': 'OpenDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is CloseDomeNode) {
      return {
        'type': 'CloseDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is ParkDomeNode) {
      return {
        'type': 'ParkDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is PolarAlignmentNode) {
      return {
        'type': 'PolarAlignment',
        'step_size': node.rotationStep,
        'exposure_time': node.exposureDuration,
        'solve_timeout': 60.0, // Default timeout
        'manual_rotation': node.manualSlew,
        'rotate_east': node.isNorth, // Use isNorth as direction hint
        'gain': node.gain,
        'offset': node.offset,
        'binning': node.binning,
      };
    } else if (node is OpenCoverNode) {
      return {
        'type': 'OpenCover',
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CloseCoverNode) {
      return {
        'type': 'CloseCover',
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CalibratorOnNode) {
      return {
        'type': 'CalibratorOn',
        'brightness': node.brightness,
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CalibratorOffNode) {
      return {
        'type': 'CalibratorOff',
        'timeout_secs': node.timeoutSecs,
      };
    }

    throw StateError(
      'Unrecognized sequence node type "${node.runtimeType}" (name="${node.name}", id="${node.id}"). '
      'This node cannot be converted to a native executor config. '
      'Ensure all node types are handled in _nodeToConfig().',
    );
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
  List<validation.SequenceValidationIssue> validateSequence(Sequence sequence) =>
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
      throw Exception('Cannot start sequence: ${errors.first.message}');
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

    // Start progress timer with ETA computation
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final completedFrames = progress.completedExposures;
        final totalFrames = progress.totalExposures;
        double? eta;
        if (completedFrames > 0 && totalFrames > 0) {
          final remainingFrames = totalFrames - completedFrames;
          if (remainingFrames > 0) {
            // Wall-clock elapsed includes overhead (download, dither, slew, etc.)
            final avgSecsPerFrame = elapsed / completedFrames;
            eta = avgSecsPerFrame * remainingFrames;
          } else {
            eta = 0.0;
          }
        }
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    _startCheckpointTimer();

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
      // Strict fail-closed behavior is enforced at runtime.
      final modeString = 'fail_closed';
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
        _logger.info(
            'Trigger fired: $triggerName -> $action',
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

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final completedFrames = progress.completedExposures;
        final totalFrames = progress.totalExposures;
        double? eta;
        if (completedFrames > 0 && totalFrames > 0) {
          final remainingFrames = totalFrames - completedFrames;
          if (remainingFrames > 0) {
            final avgSecsPerFrame = elapsed / completedFrames;
            eta = avgSecsPerFrame * remainingFrames;
          } else {
            eta = 0.0;
          }
        }
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    _startCheckpointTimer();

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
  }
}
