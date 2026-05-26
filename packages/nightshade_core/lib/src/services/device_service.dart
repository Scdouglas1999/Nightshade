import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api_barrel.dart' as bridge_api;
import '../providers/equipment_provider.dart';
import '../providers/imaging_provider.dart' show temperatureHistoryProvider;
import '../providers/profiles_provider.dart';
import '../providers/backend_provider.dart';
import '../providers/sequence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_notification_provider.dart';
import '../providers/operation_progress_provider.dart';
import '../providers/filter_offset_provider.dart';
import '../providers/current_screen_provider.dart';
import '../providers/device_heartbeat_health_provider.dart';
import 'smart_notification_service.dart';
import '../backend/ffi_backend.dart';
import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart' hide TrackingRate;
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart' show AutofocusSettings;
import '../models/sequence/sequence_models.dart';
import '../utils/device_id_utils.dart';
import 'device_exceptions.dart';
import 'notification_service.dart';
import 'logging_service.dart';
import 'error_service.dart';
import 'phd2_status_poll.dart';
import 'device_service_lifecycle.dart';

// Re-export backend types for backward compatibility
// These were previously defined locally but are now consolidated in backend_types
export '../models/backend/device_types.dart' show DeviceType, DriverType;
export '../models/backend/device_info.dart' show DeviceInfo;

/// Extension methods for DeviceType display
extension DeviceTypeDisplayExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.camera:
        return 'Camera';
      case DeviceType.mount:
        return 'Mount';
      case DeviceType.focuser:
        return 'Focuser';
      case DeviceType.filterWheel:
        return 'Filter Wheel';
      case DeviceType.guider:
        return 'Guider';
      case DeviceType.rotator:
        return 'Rotator';
      case DeviceType.dome:
        return 'Dome';
      case DeviceType.weather:
        return 'Weather';
      case DeviceType.safetyMonitor:
        return 'Safety Monitor';
      case DeviceType.switch_:
        return 'Switch';
      case DeviceType.coverCalibrator:
        return 'Cover Calibrator';
    }
  }
}

/// Extension methods for DriverType display
extension DriverTypeDisplayExtension on DriverType {
  String get displayName {
    switch (this) {
      case DriverType.ascom:
        return 'ASCOM';
      case DriverType.alpaca:
        return 'Alpaca';
      case DriverType.indi:
        return 'INDI';
      case DriverType.native:
        return 'Native';
      case DriverType.simulator:
        return 'Simulator';
    }
  }
}

/// Type alias for the switch-bridge `apiSwitchGetMax` shim used by
/// [DeviceService.refreshSwitchChannels]. Tests override the static
/// hook below to avoid loading the native bridge.
typedef SwitchBridgeGetMaxFn = Future<int> Function(String deviceId);

/// Type alias for the switch-bridge name fetch.
typedef SwitchBridgeGetNameFn = Future<String> Function(
    String deviceId, int switchId);

/// Type alias for the switch-bridge boolean read.
typedef SwitchBridgeGetStateFn = Future<bool> Function(
    String deviceId, int switchId);

/// Type alias for the switch-bridge boolean write.
typedef SwitchBridgeSetStateFn = Future<void> Function(
    String deviceId, int switchId, bool state);

/// Service for managing device discovery and connections
///
/// This service uses the NightshadeBackend abstraction to communicate
/// with devices via different backends (FFI for desktop, Network for mobile).
class DeviceService {
  final Ref _ref;
  final NightshadeBackend _backend;

  // ---- Switch bridge hooks (testable seam) -----------------------------
  // DEV-P2-1 follow-up: the per-channel switch UI needs to call FFI even
  // when the test rig swaps in a MockBackend. The MockBackend can't
  // satisfy `_backend is FfiBackend`, so the actual `apiSwitch*` calls
  // would otherwise be skipped. Static function-pointer hooks let
  // tests swap in fakes for the bridge calls without touching the
  // backend type check. Production code calls
  // `switchBridge{GetMax,GetName,GetState,SetState}` instead of
  // `bridge_api.apiSwitch*` directly so the override is centralized.
  @visibleForTesting
  static SwitchBridgeGetMaxFn switchBridgeGetMax =
      (deviceId) => bridge_api.apiSwitchGetMax(deviceId: deviceId);
  @visibleForTesting
  static SwitchBridgeGetNameFn switchBridgeGetName = (deviceId, switchId) =>
      bridge_api.apiSwitchGetName(deviceId: deviceId, switchId: switchId);
  @visibleForTesting
  static SwitchBridgeGetStateFn switchBridgeGetState = (deviceId, switchId) =>
      bridge_api.apiSwitchGetState(deviceId: deviceId, switchId: switchId);
  @visibleForTesting
  static SwitchBridgeSetStateFn switchBridgeSetState =
      (deviceId, switchId, state) => bridge_api.apiSwitchSetState(
          deviceId: deviceId, switchId: switchId, state: state);

  /// When true, [refreshSwitchChannels] and [setSwitchChannel] will
  /// call the bridge hooks above unconditionally instead of gating on
  /// `_backend is FfiBackend`. Tests set this to true so MockBackend
  /// can stand in for FfiBackend without satisfying its type.
  /// MUST remain false in production builds.
  @visibleForTesting
  static bool switchBridgeBypassBackendCheck = false;

  /// Reset switch bridge hooks to their production implementations.
  /// Call from `tearDown` in any test that overrode them.
  @visibleForTesting
  static void resetSwitchBridgeHooks() {
    switchBridgeBypassBackendCheck = false;
    switchBridgeGetMax =
        (deviceId) => bridge_api.apiSwitchGetMax(deviceId: deviceId);
    switchBridgeGetName = (deviceId, switchId) =>
        bridge_api.apiSwitchGetName(deviceId: deviceId, switchId: switchId);
    switchBridgeGetState = (deviceId, switchId) =>
        bridge_api.apiSwitchGetState(deviceId: deviceId, switchId: switchId);
    switchBridgeSetState = (deviceId, switchId, state) =>
        bridge_api.apiSwitchSetState(
            deviceId: deviceId, switchId: switchId, state: state);
  }

  StreamSubscription? _eventSubscription;
  Timer? _temperaturePollingTimer;
  String? _connectedCameraId;
  int _temperaturePollingGeneration = 0;
  Timer? _warmingTimer;
  bool _warmingCancelled = false;

  static const Duration _filterWheelVerifyTimeout = Duration(seconds: 60);
  static const Duration _filterWheelVerifyPollInterval =
      Duration(milliseconds: 250);

  static const Duration _focuserMoveTimeout = Duration(seconds: 300);
  static const Duration _focuserMovePollInterval = Duration(milliseconds: 500);

  /// Tracks the last applied filter focus offset so that filter changes apply
  /// delta adjustments (remove old offset, apply new offset) rather than
  /// cumulative offsets.
  int _lastAppliedFilterOffset = 0;

  /// In-flight guarded operations — backend swap waits for zero (DV-P0-2).
  int _inFlightOperations = 0;
  final List<Completer<void>> _quiesceWaiters = [];

  /// User-initiated disconnects suppress auto-reconnect briefly (DV-P0-3).
  final Set<String> _userInitiatedDisconnects = {};
  Timer? _userDisconnectDebounceTimer;

  /// Set during backend swap so stray Disconnected events cannot reconnect.
  bool _suppressAutoReconnect = false;

  bool _disposed = false;

  static const Duration _connectProfileDeviceTimeout = Duration(seconds: 60);
  static const Duration _quiesceTimeout = Duration(seconds: 30);
  static const Duration _userDisconnectSuppressDuration = Duration(seconds: 10);

  /// Guard against concurrent autofocus runs. Only one AF can run at a time
  /// since the focuser and camera are shared hardware resources.
  bool _isAutofocusRunning = false;

  DeviceService(this._ref, this._backend) {
    DeviceServiceLifecycle.register(this);
    _initEventListening();
  }

  /// Emits a diagnostic line through the logging service, but never lets a
  /// logger-emission failure mask a higher-priority device fault. We deliberately
  /// catch every kind of error from the logger lookup (e.g. provider mid-disposal
  /// during shutdown) and demote to a stderr line — fail-closed for the calling
  /// device operation, soft for the diagnostics emission itself.
  void _safeLog(void Function(LoggingService logger) emit, String contextTag) {
    try {
      final logger = _ref.read(loggingServiceProvider);
      emit(logger);
    } on Object catch (loggerErr) {
      // ignore: avoid_print
      print('DeviceService[$contextTag]: logger emission failed: $loggerErr');
    }
  }

  /// Active equipment profile from [equipmentProfilesProvider] (host API or local DB).
  EquipmentProfileModel? get _activeProfile =>
      _ref.read(activeEquipmentProfileProvider);

  String? _activeProfileDeviceId(
    String? Function(EquipmentProfileModel profile) pick,
  ) {
    final profile = _activeProfile;
    if (profile == null) {
      return null;
    }
    final deviceId = pick(profile);
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }
    return deviceId;
  }

  Future<void> _applyFilterNamesToNotifier({
    required FilterWheelStateNotifier notifier,
    required String deviceId,
    required List<String> syncedNames,
  }) async {
    if (_backend is NetworkBackend) {
      notifier.setConnected(filterNames: syncedNames);
      return;
    }

    await bridge_api.apiFilterwheelSetFilterNames(
      deviceId: deviceId,
      names: syncedNames,
    );
    notifier.setConnected(filterNames: syncedNames);
  }

  /// Start polling camera temperature every 5 seconds
  void _startTemperaturePolling(String deviceId) {
    _connectedCameraId = deviceId;
    final generation = ++_temperaturePollingGeneration;
    _temperaturePollingTimer?.cancel();
    _temperaturePollingTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      await _pollCameraTemperature(deviceId, generation);
    });
    // Poll immediately on start
    unawaited(_pollCameraTemperature(deviceId, generation));
  }

  /// Stop temperature polling
  void _stopTemperaturePolling() {
    _temperaturePollingGeneration++;
    _temperaturePollingTimer?.cancel();
    _temperaturePollingTimer = null;
    _connectedCameraId = null;
  }

  /// Poll camera temperature and update providers
  Future<void> _pollCameraTemperature(String deviceId, int generation) async {
    if (_connectedCameraId != deviceId ||
        _temperaturePollingGeneration != generation) {
      return;
    }

    try {
      final status = await _backend.getCameraStatus(deviceId);
      if (_connectedCameraId != deviceId ||
          _temperaturePollingGeneration != generation) {
        return;
      }

      // Use typed CameraStatus accessors
      final temp = status.sensorTemp;
      final power = status.coolerPower;
      final targetTemp = status.targetTemp;

      // Log temperature readings for debugging
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.debug(
          'Camera temp: ${temp?.toStringAsFixed(1) ?? "null"}°C, power: ${power?.toStringAsFixed(0) ?? "null"}%, target: ${targetTemp?.toStringAsFixed(1) ?? "null"}°C',
          source: 'DeviceService',
        );
      } on Object catch (e) {
        // Why: logger lookup happens inside a temperature poll tick; if the
        // logging service itself is mid-disposal we must not propagate up the
        // poll loop. Diagnostic-only failure — emit to stderr so it isn't
        // fully silent.
        // ignore: avoid_print
        print('DeviceService: temp-log emission failed: $e');
      }

      if (temp != null) {
        // Update camera state
        _ref
            .read(cameraStateProvider.notifier)
            .updateTemperature(temp, power ?? 0.0);

        // Update temperature history for the graph
        _ref.read(temperatureHistoryProvider.notifier).addPoint(
              temp,
              targetTemp: targetTemp,
              coolerPower: power,
            );
      }
    } catch (e) {
      if (_connectedCameraId != deviceId ||
          _temperaturePollingGeneration != generation) {
        return;
      }
      // Log polling errors for debugging
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.warning('Temperature polling error: $e',
            source: 'DeviceService');
      } on Object catch (loggerErr) {
        // Why: nested catch around logger emission during the poll-loop's
        // error path. If the logging provider is itself disposing we must
        // not re-throw — that would mask the original temperature-polling
        // failure. Surface to stderr so it isn't fully silent.
        // ignore: avoid_print
        print('DeviceService: warn-log emission failed: $loggerErr '
            '(original temp-poll error: $e)');
      }
    }
  }

  void _initEventListening() {
    _eventSubscription?.cancel();
    _eventSubscription = _backend.eventStream.listen(
      (event) {
        if (event.category == EventCategory.equipment) {
          _handleEquipmentEvent(event);
        } else if (event.category == EventCategory.sequencer) {
          _handleSequencerEvent(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _safeLog(
          (logger) => logger.error(
            'DeviceService equipment event stream error: $error',
            source: 'DeviceService',
          ),
          'event-stream-error',
        );
        if (!_disposed) {
          _initEventListening();
        }
      },
      cancelOnError: false,
    );
  }

  /// Wait until all guarded in-flight operations complete (DV-P0-2).
  Future<void> quiesce({Duration? timeout}) async {
    if (_inFlightOperations == 0) {
      return;
    }
    final completer = Completer<void>();
    _quiesceWaiters.add(completer);
    await completer.future.timeout(
      timeout ?? _quiesceTimeout,
      onTimeout: () {
        throw TimeoutException(
          'Device operations did not complete within '
          '${(timeout ?? _quiesceTimeout).inSeconds}s',
        );
      },
    );
  }

  /// Cancel reconnect timers, suppress auto-reconnect, and quiesce before a
  /// backend swap disposes this service instance (DV-P0-2).
  Future<void> prepareForBackendSwap() async {
    _suppressAutoReconnect = true;
    _cancelAllReconnections();
    _userInitiatedDisconnects.clear();
    _userDisconnectDebounceTimer?.cancel();
    _userDisconnectDebounceTimer = null;
    cancelWarmCamera();
    _stopTemperaturePolling();
    _lastAppliedFilterOffset = 0;
    await quiesce();
  }

  Future<T> _trackInFlight<T>(Future<T> Function() operation) async {
    _inFlightOperations++;
    try {
      return await operation();
    } finally {
      _inFlightOperations--;
      if (_inFlightOperations == 0) {
        final waiters = List<Completer<void>>.from(_quiesceWaiters);
        _quiesceWaiters.clear();
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
      }
    }
  }

  void _markUserInitiatedDisconnect(String deviceId) {
    if (deviceId.isEmpty) {
      return;
    }
    _userInitiatedDisconnects.add(deviceId);
    _reconnectionTimers[deviceId]?.cancel();
    _reconnectionTimers.remove(deviceId);
    _reconnectionAttempts.remove(deviceId);
    _userDisconnectDebounceTimer?.cancel();
    _userDisconnectDebounceTimer = Timer(_userDisconnectSuppressDuration, () {
      _userInitiatedDisconnects.clear();
      _userDisconnectDebounceTimer = null;
    });
  }

  bool _isUserInitiatedDisconnect(String deviceId) {
    return _userInitiatedDisconnects.contains(deviceId);
  }

  /// Resolve a display name without running discovery. Falls back to
  /// [getConnectedDevices] when the backend already knows this device
  /// (DV-P0-4).
  Future<String> _resolveDeviceDisplayName(
    DeviceType type,
    String deviceId,
  ) async {
    try {
      final connected = await _backend.getConnectedDevices();
      for (final device in connected) {
        if (device.id == deviceId && device.deviceType == type) {
          if (device.name.isNotEmpty) {
            return device.name;
          }
        }
      }
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'getConnectedDevices lookup failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'resolve-device-name',
      );
    }
    return _friendlyNameFromId(deviceId);
  }

  void _handleEquipmentEvent(NightshadeEvent event) {
    final data = event.data;
    switch (event.eventType) {
      // Connection events
      case 'Connecting':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        if (deviceType != null && deviceId != null) {
          _applyDeviceConnecting(deviceType, deviceId);
        }
        break;

      case 'Connected':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        if (deviceType != null && deviceId != null) {
          _applyDeviceConnected(deviceType, deviceId);
        }
        break;

      case 'Disconnected':
        final deviceType = data['device_type'] as String?;
        final deviceId = data['device_id'] as String?;
        _handleDeviceDisconnected(deviceType, deviceId);
        break;

      // DEV-P0-5: surface driver errors published from Rust via
      // report_error / connect_device_internal / heartbeat. Previously
      // dropped on the floor — the user never saw the actual driver
      // message. Per CLAUDE.md "errors are a feature", we route the
      // payload through the structured errorService (which also pushes
      // to UI notifications) AND set the matching device state to
      // error so the equipment card subtitle renders it.
      case 'Error':
        _handleDeviceError(
          deviceType: data['device_type'] as String?,
          deviceId: data['device_id'] as String?,
          message: data['message'] as String?,
          errorCode:
              data['error_code']?.toString() ?? data['errorCode']?.toString(),
          severity: event.severity,
        );
        break;

      // Legacy camera temperature event (keep for backward compatibility)
      case 'CameraTemperatureChanged':
        final temp = (data['temperature'] as num).toDouble();
        final power = (data['coolerPower'] as num).toDouble();
        _ref.read(cameraStateProvider.notifier).updateTemperature(temp, power);
        break;

      // Legacy mount position event (keep for backward compatibility)
      case 'MountPositionChanged':
        final ra = (data['ra'] as num).toDouble();
        final dec = (data['dec'] as num).toDouble();
        final alt = (data['altitude'] as num?)?.toDouble() ?? 0.0;
        final az = (data['azimuth'] as num?)?.toDouble() ?? 0.0;
        _ref.read(mountStateProvider.notifier).updatePosition(ra, dec, alt, az);

        if (data['isSlewing'] != null) {
          _ref
              .read(mountStateProvider.notifier)
              .setSlewing(data['isSlewing'] as bool);
        }
        if (data['isTracking'] != null) {
          _ref
              .read(mountStateProvider.notifier)
              .setTracking(data['isTracking'] as bool);
        }
        if (data['isParked'] != null) {
          _ref
              .read(mountStateProvider.notifier)
              .setParked(data['isParked'] as bool);
        }
        break;

      // Mount Slew Events
      case 'MountSlewStarted':
        final ra = (data['ra'] as num?)?.toDouble();
        final dec = (data['dec'] as num?)?.toDouble();
        _ref.read(mountStateProvider.notifier).setSlewing(true);
        if (ra != null && dec != null) {
          // Optionally update target position
        }
        break;

      case 'MountSlewCompleted':
        final ra = (data['ra'] as num?)?.toDouble();
        final dec = (data['dec'] as num?)?.toDouble();
        _ref.read(mountStateProvider.notifier).setSlewing(false);
        if (ra != null && dec != null) {
          _ref
              .read(mountStateProvider.notifier)
              .updatePosition(ra, dec, 0.0, 0.0);
        }
        // Smart notification - only show if not on imaging/planetarium screens
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
              message: 'Slew completed',
              relevantScreens: [
                AppScreen.imaging,
                AppScreen.planetarium,
                AppScreen.sequencer
              ],
              title: 'Mount',
            );
        break;

      // Mount Tracking Events
      case 'MountTrackingStarted':
        _ref.read(mountStateProvider.notifier).setTracking(true);
        break;

      case 'MountTrackingStopped':
        _ref.read(mountStateProvider.notifier).setTracking(false);
        break;

      // Mount Park Events
      case 'MountParkStarted':
        _ref.read(mountStateProvider.notifier).setSlewing(true);
        break;

      case 'MountParkCompleted':
        _ref.read(mountStateProvider.notifier).setSlewing(false);
        _ref.read(mountStateProvider.notifier).setParked(true);
        _ref.read(mountStateProvider.notifier).setTracking(false);
        // Smart notification
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
              message: 'Mount parked',
              relevantScreens: [AppScreen.imaging, AppScreen.equipment],
              title: 'Mount',
            );
        break;

      case 'MountUnparked':
        _ref.read(mountStateProvider.notifier).setParked(false);
        // Smart notification
        _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
              message: 'Mount unparked',
              relevantScreens: [AppScreen.imaging, AppScreen.equipment],
              title: 'Mount',
            );
        break;

      // Legacy focuser position event (keep for backward compatibility)
      case 'FocuserPositionChanged':
        final pos = data['position'] as int;
        _ref.read(focuserStateProvider.notifier).updatePosition(pos);
        if (data['isMoving'] != null) {
          _ref
              .read(focuserStateProvider.notifier)
              .setMoving(data['isMoving'] as bool);
        }
        if (data['temperature'] != null) {
          _ref
              .read(focuserStateProvider.notifier)
              .updateTemperature((data['temperature'] as num).toDouble());
        }
        break;

      // Focuser Events
      case 'FocuserMoveStarted':
        _ref.read(focuserStateProvider.notifier).setMoving(true);
        break;

      case 'FocuserMoveCompleted':
        final position = data['position'] as int?;
        _ref.read(focuserStateProvider.notifier).setMoving(false);
        if (position != null) {
          _ref.read(focuserStateProvider.notifier).updatePosition(position);
        }
        break;

      case 'FocuserTemperatureChanged':
        final temperature = (data['temperature'] as num?)?.toDouble();
        if (temperature != null) {
          _ref
              .read(focuserStateProvider.notifier)
              .updateTemperature(temperature);
        }
        break;

      // Legacy filter wheel position event (keep for backward compatibility)
      case 'FilterWheelPositionChanged':
        final pos = data['position'] as int;
        _ref.read(filterWheelStateProvider.notifier).updatePosition(pos);
        if (data['isMoving'] != null) {
          _ref
              .read(filterWheelStateProvider.notifier)
              .setMoving(data['isMoving'] as bool);
        }
        break;

      // Filter Wheel Events
      case 'FilterChanging':
        _ref.read(filterWheelStateProvider.notifier).setMoving(true);
        break;

      case 'FilterChanged':
        final position = data['position'] as int?;
        _ref.read(filterWheelStateProvider.notifier).setMoving(false);
        if (position != null) {
          _ref.read(filterWheelStateProvider.notifier).updatePosition(position);
        }
        break;

      // Rotator Events
      case 'RotatorMoveStarted':
        _ref.read(rotatorStateProvider.notifier).setMoving(true);
        break;

      case 'RotatorMoveCompleted':
        final angle = (data['angle'] as num?)?.toDouble();
        _ref.read(rotatorStateProvider.notifier).setMoving(false);
        if (angle != null) {
          _ref.read(rotatorStateProvider.notifier).updatePosition(angle);
        }
        break;

      // Camera Cooling Events
      case 'CameraCoolingStarted':
        final targetTemp = (data['target_temp'] as num?)?.toDouble();
        _ref.read(cameraStateProvider.notifier).setCooling(true);
        if (targetTemp != null) {
          _ref.read(cameraStateProvider.notifier).setTargetTemp(targetTemp);
        }
        break;

      case 'CameraCoolingReached':
        final temp = (data['temperature'] as num?)?.toDouble();
        if (temp != null) {
          _ref.read(cameraStateProvider.notifier).updateTemperature(temp, 0.0);
        }
        break;

      case 'CameraWarmingStarted':
        _ref.read(cameraStateProvider.notifier).setCooling(false);
        break;

      case 'CameraWarmingCompleted':
        // Warming finished - no additional action needed
        break;

      // ---------------------------------------------------------------
      // DEV-P3-2: Heartbeat-health routing.
      //
      // The Rust heartbeat monitor publishes status changes via the
      // equipment EventBus. We forward them into the dedicated
      // `deviceHeartbeatHealthProvider` so per-device cards can render
      // a colored indicator without each card subscribing to the
      // entire equipment event stream itself. Connection-state
      // notifiers (DEV-P0-1) and the driver-error handler (DEV-P0-5)
      // are intentionally untouched here — heartbeat health is a
      // separate gradient layered on top of connection state.
      //
      // Each case wraps the dispatch in a try/catch because the
      // notifier provider may be unavailable mid-disposal (e.g. during
      // a backend swap) and we never want a heartbeat-routing failure
      // to mask the higher-priority connection events that share this
      // method.
      // ---------------------------------------------------------------
      case 'HeartbeatStarted':
        _routeHeartbeatStarted(data['device_id'] as String?);
        break;

      case 'HeartbeatStatusChanged':
        _routeHeartbeatStatusChanged(
          deviceId: data['device_id'] as String?,
          status: data['status'] as String?,
          consecutiveFailures: (data['consecutive_failures'] as num?)?.toInt(),
          lastRttMs: _coerceIntFromBigInt(data['last_rtt_ms']),
        );
        break;

      case 'HeartbeatReconnecting':
        _routeHeartbeatReconnecting(
          deviceId: data['device_id'] as String?,
          attempt: (data['attempt'] as num?)?.toInt(),
          maxAttempts: (data['max_attempts'] as num?)?.toInt(),
        );
        break;

      case 'HeartbeatReconnected':
        _routeHeartbeatReconnected(
          deviceId: data['device_id'] as String?,
          afterAttempts: (data['after_attempts'] as num?)?.toInt(),
        );
        break;

      case 'HeartbeatStopped':
        // Heartbeat monitoring intentionally stopped (e.g. user
        // disconnected the device through the UI). Clear the entry so
        // the indicator returns to the gray "unknown" baseline. The
        // matching `Disconnected` event handler also clears, but the
        // events are emitted independently and either may arrive
        // first.
        final stoppedId = data['device_id'] as String?;
        if (stoppedId != null && stoppedId.isNotEmpty) {
          _safeClearHeartbeatHealth(stoppedId);
        }
        break;
    }
  }

  /// DEV-P3-2: helper — `last_rtt_ms` arrives as a `BigInt` over FRB.
  /// Squeeze it down to a Dart `int` for the heartbeat provider, which
  /// only cares about display. Returns null when the input is null or
  /// not coercible.
  int? _coerceIntFromBigInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is BigInt) {
      // Guard against absurdly large values that would overflow when
      // converted to int. We're displaying milliseconds; anything above
      // 2^31 is meaningless for a tooltip and we clamp to int.maxFinite
      // equivalent via toInt() (Dart ints are 64-bit on native, so the
      // guard is effectively only for the JS path which we don't ship
      // on desktop, but kept here so the cast is total).
      return value.isValidInt ? value.toInt() : null;
    }
    if (value is num) return value.toInt();
    return null;
  }

  void _routeHeartbeatStarted(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return;
    _safeApplyHeartbeat(
      contextTag: 'heartbeat-started',
      apply: (notifier) => notifier.applyHeartbeatStarted(deviceId: deviceId),
    );
  }

  void _routeHeartbeatStatusChanged({
    required String? deviceId,
    required String? status,
    required int? consecutiveFailures,
    required int? lastRttMs,
  }) {
    if (deviceId == null || deviceId.isEmpty) return;
    if (status == null || status.isEmpty) {
      _safeLog(
        (logger) => logger.warning(
          'HeartbeatStatusChanged for $deviceId missing status field; '
          'dropping. Payload may be malformed.',
          source: 'DeviceService',
        ),
        'heartbeat-status-missing',
      );
      return;
    }
    _safeApplyHeartbeat(
      contextTag: 'heartbeat-status',
      apply: (notifier) => notifier.applyStatusEvent(
        deviceId: deviceId,
        status: status,
        consecutiveFailures: consecutiveFailures ?? 0,
        lastRttMs: lastRttMs,
      ),
    );
  }

  void _routeHeartbeatReconnecting({
    required String? deviceId,
    required int? attempt,
    required int? maxAttempts,
  }) {
    if (deviceId == null || deviceId.isEmpty) return;
    _safeApplyHeartbeat(
      contextTag: 'heartbeat-reconnecting',
      apply: (notifier) => notifier.applyReconnecting(
        deviceId: deviceId,
        attempt: attempt ?? 0,
        maxAttempts: maxAttempts ?? 0,
      ),
    );
  }

  void _routeHeartbeatReconnected({
    required String? deviceId,
    required int? afterAttempts,
  }) {
    if (deviceId == null || deviceId.isEmpty) return;
    _safeApplyHeartbeat(
      contextTag: 'heartbeat-reconnected',
      apply: (notifier) => notifier.applyReconnected(
        deviceId: deviceId,
        afterAttempts: afterAttempts ?? 0,
      ),
    );
  }

  void _safeApplyHeartbeat({
    required String contextTag,
    required void Function(DeviceHeartbeatHealthNotifier notifier) apply,
  }) {
    try {
      final notifier = _ref.read(deviceHeartbeatHealthProvider.notifier);
      apply(notifier);
    } on Object catch (e) {
      // Diagnostic-only failure — the heartbeat indicator going stale
      // is strictly less important than the surrounding connection /
      // error path, so we log and continue rather than rethrowing.
      _safeLog(
        (logger) => logger.warning(
          'Heartbeat provider dispatch failed ($contextTag): $e',
          source: 'DeviceService',
        ),
        contextTag,
      );
    }
  }

  void _safeClearHeartbeatHealth(String deviceId) {
    try {
      _ref.read(deviceHeartbeatHealthProvider.notifier).clearDevice(deviceId);
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'Heartbeat provider clear failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'heartbeat-clear',
      );
    }
  }

  /// Handle device connection event from the native EventBus.
  void _applyDeviceConnected(String deviceType, String deviceId) {
    switch (deviceType.toLowerCase()) {
      case 'camera':
        final notifier = _ref.read(cameraStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'mount':
        final notifier = _ref.read(mountStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'focuser':
        final notifier = _ref.read(focuserStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'filterwheel':
      case 'filter wheel':
        final notifier = _ref.read(filterWheelStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'guider':
        final notifier = _ref.read(guiderStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'rotator':
        final notifier = _ref.read(rotatorStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'dome':
        final notifier = _ref.read(domeStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'weather':
        final notifier = _ref.read(weatherStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'safetymonitor':
      case 'safety monitor':
        final notifier = _ref.read(safetyMonitorStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider.
        final notifier = _ref.read(switchStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        final notifier = _ref.read(coverCalibratorStateProvider.notifier);
        notifier.setConnecting(deviceId, deviceId);
        notifier.setConnected();
        break;
    }
  }

  void _applyDeviceConnecting(String deviceType, String deviceId) {
    switch (deviceType.toLowerCase()) {
      case 'camera':
        _ref
            .read(cameraStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'mount':
        _ref
            .read(mountStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'focuser':
        _ref
            .read(focuserStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'filterwheel':
      case 'filter wheel':
        _ref
            .read(filterWheelStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'guider':
        _ref
            .read(guiderStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'rotator':
        _ref
            .read(rotatorStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'dome':
        _ref.read(domeStateProvider.notifier).setConnecting(deviceId, deviceId);
        break;
      case 'weather':
        _ref
            .read(weatherStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'safetymonitor':
      case 'safety monitor':
        _ref
            .read(safetyMonitorStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider.
        _ref
            .read(switchStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        _ref
            .read(coverCalibratorStateProvider.notifier)
            .setConnecting(deviceId, deviceId);
        break;
    }
  }

  /// Handle device disconnection event
  void _handleDeviceDisconnected(String? deviceType, String? deviceId) {
    if (deviceType == null || deviceId == null) return;

    // DEV-P3-2: clear the heartbeat health entry so the per-card
    // indicator falls back to "unknown" (gray dot) rather than getting
    // stuck on the last-known value. Done unconditionally up-front so
    // a clear failure here cannot block the existing connection-state
    // teardown below (DEV-P0-1 / DEV-P0-5 paths).
    _safeClearHeartbeatHealth(deviceId);

    // Log the disconnection event with timestamp
    try {
      final logger = _ref.read(loggingServiceProvider);
      logger.warning(
        'Device disconnected: $deviceType ($deviceId) at ${DateTime.now().toIso8601String()}',
        source: 'DeviceService',
      );
    } catch (e) {
      // Logging service not available, continue without it
    }

    // Check if this is a critical device and sequence is running
    final isCriticalDevice = deviceType.toLowerCase() == 'camera' ||
        deviceType.toLowerCase() == 'mount';
    if (isCriticalDevice) {
      _handleCriticalDeviceDisconnect(deviceType, deviceId);
    }

    // Update connection state based on device type
    switch (deviceType.toLowerCase()) {
      case 'camera':
        // DEV-P1-4: only tear down camera-scoped polling state if the
        // disconnect event is for the camera we're actually tracking.
        // A stale event for a previously-disconnected camera must not
        // kill polling/IDs for the CURRENT camera. We still flip the
        // notifier and schedule reconnect — those operations are
        // device-id aware via _attemptReconnect/setDisconnected.
        if (_connectedCameraId != null && _connectedCameraId == deviceId) {
          _stopTemperaturePolling();
        } else if (_connectedCameraId != null) {
          _safeLog(
            (logger) => logger.warning(
              'Ignoring stale camera Disconnected for $deviceId; '
              'currently-tracked camera is $_connectedCameraId',
              source: 'DeviceService',
            ),
            'camera-disconnect-guard',
          );
        }
        _ref.read(cameraStateProvider.notifier).setDisconnected();
        // Attempt auto-reconnection for camera
        _attemptReconnect(DeviceType.camera, deviceId);
        break;

      case 'mount':
        _ref.read(mountStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.mount, deviceId);
        break;

      case 'focuser':
        _ref.read(focuserStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.focuser, deviceId);
        break;

      case 'filterwheel':
      case 'filter wheel':
        _ref.read(filterWheelStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.filterWheel, deviceId);
        break;

      case 'guider':
        _ref.read(guiderStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.guider, deviceId);
        break;

      case 'rotator':
        _ref.read(rotatorStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.rotator, deviceId);
        break;

      case 'dome':
        _ref.read(domeStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.dome, deviceId);
        break;

      case 'weather':
        _ref.read(weatherStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.weather, deviceId);
        break;

      case 'safetymonitor':
      case 'safety monitor':
        _ref.read(safetyMonitorStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.safetyMonitor, deviceId);
        break;

      // DEV-P0-1: cover calibrator + switch cases. Previously these
      // device types would never propagate a Disconnected event to the
      // UI — cards stayed "connected" until app restart. Cover
      // calibrator has a state provider; switch does not yet (DEV-P2-1)
      // so we log loudly and surface a UI notification so the user
      // knows the device is gone.
      case 'covercalibrator':
      case 'cover calibrator':
        _ref.read(coverCalibratorStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.coverCalibrator, deviceId);
        break;

      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider,
        // so disconnects route through `setDisconnected` and the
        // standard auto-reconnect path — same shape as safety monitor.
        _ref.read(switchStateProvider.notifier).setDisconnected();
        _attemptReconnect(DeviceType.switch_, deviceId);
        break;
    }
  }

  /// DEV-P0-5: Handle a driver/heartbeat error event published from Rust.
  ///
  /// Three responsibilities:
  ///   1. Always log (driver, device id, message, error code if any).
  ///   2. Update the matching device-type StateNotifier with the error
  ///      so equipment-card subtitles render it.
  ///   3. Surface to the user via the structured errorService (which
  ///      also pushes to the UI notification stream).
  ///
  /// Fail-loud: this method MUST NOT swallow the payload. Individual
  /// downstream emissions are wrapped so one channel failing (e.g.
  /// notification provider mid-disposal) cannot mask the others.
  void _handleDeviceError({
    required String? deviceType,
    required String? deviceId,
    required String? message,
    required String? errorCode,
    required EventSeverity severity,
  }) {
    // Compose a human-readable error string. Even if device_type or
    // device_id are missing we still want the message visible.
    final composedMessage = StringBuffer();
    if (message != null && message.isNotEmpty) {
      composedMessage.write(message);
    } else {
      composedMessage.write('Driver reported an error (no message provided)');
    }
    if (errorCode != null && errorCode.isNotEmpty) {
      composedMessage.write(' [code: $errorCode]');
    }
    final fullMessage = composedMessage.toString();

    // 1. Log loudly with full context.
    _safeLog(
      (logger) => logger.error(
        'Driver error: type=${deviceType ?? "unknown"} '
        'id=${deviceId ?? "unknown"} code=${errorCode ?? "none"} :: '
        '$fullMessage',
        source: 'DeviceService',
      ),
      'device-error-log',
    );

    // 2. Update the matching device-type state notifier so equipment
    //    cards display the error in their subtitle.
    final exception =
        Exception(fullMessage); // setError expects Object — wrap once.
    final typeKey = (deviceType ?? '').toLowerCase();
    switch (typeKey) {
      case 'camera':
        _ref.read(cameraStateProvider.notifier).setError(exception);
        break;
      case 'mount':
        _ref.read(mountStateProvider.notifier).setError(exception);
        break;
      case 'focuser':
        _ref.read(focuserStateProvider.notifier).setError(exception);
        break;
      case 'filterwheel':
      case 'filter wheel':
        _ref.read(filterWheelStateProvider.notifier).setError(exception);
        break;
      case 'guider':
        _ref.read(guiderStateProvider.notifier).setError(exception);
        break;
      case 'rotator':
        _ref.read(rotatorStateProvider.notifier).setError(exception);
        break;
      case 'dome':
        _ref.read(domeStateProvider.notifier).setError(exception);
        break;
      case 'weather':
        _ref.read(weatherStateProvider.notifier).setError(exception);
        break;
      case 'safetymonitor':
      case 'safety monitor':
        _ref.read(safetyMonitorStateProvider.notifier).setError(exception);
        break;
      case 'covercalibrator':
      case 'cover calibrator':
        _ref.read(coverCalibratorStateProvider.notifier).setError(exception);
        break;
      case 'switch':
      case 'switch_':
        // DEV-P2-1: switch device now has a first-class state provider,
        // so driver errors surface in the equipment card subtitle.
        _ref.read(switchStateProvider.notifier).setError(exception);
        break;
      default:
        _safeLog(
          (logger) => logger.warning(
            'Error event for unknown device type "$deviceType"; '
            'no state notifier updated. Message: $fullMessage',
            source: 'DeviceService',
          ),
          'device-error-unknown-type',
        );
    }

    // 3. Surface via the structured errorService. This routes through
    //    the error history (visible in diagnostics) AND pushes a UI
    //    notification toast (errorService internally calls
    //    uiNotificationProvider for error/critical severities).
    try {
      final errSvc = _ref.read(errorServiceProvider);
      final mappedSeverity = switch (severity) {
        EventSeverity.info => ErrorSeverity.info,
        EventSeverity.warning => ErrorSeverity.warning,
        EventSeverity.error => ErrorSeverity.error,
        EventSeverity.critical => ErrorSeverity.critical,
      };
      // Use deviceType for the structured entry's title. If absent we
      // still want the entry recorded, so default to "Device".
      errSvc.logDeviceError(
        operation: 'driver_error',
        message: fullMessage,
        deviceType: deviceType ?? 'Device',
        deviceId: deviceId,
        severity: mappedSeverity,
        context: errorCode == null ? null : {'error_code': errorCode},
      );
    } on Object catch (errSvcErr) {
      _safeLog(
        (logger) => logger.warning(
          'errorService emission for driver error failed: $errSvcErr '
          '(original: $fullMessage)',
          source: 'DeviceService',
        ),
        'device-error-errorservice',
      );
      // Fallback: try uiNotificationProvider directly so the user
      // still sees the message even if errorService is unavailable.
      try {
        _ref.read(uiNotificationProvider.notifier).showError(
              fullMessage,
              title: '${deviceType ?? "Device"} Error',
              duration: const Duration(seconds: 12),
            );
      } on Object catch (uiErr) {
        _safeLog(
          (logger) => logger.warning(
            'UI notification fallback also failed: $uiErr '
            '(original: $fullMessage)',
            source: 'DeviceService',
          ),
          'device-error-ui-fallback',
        );
      }
    }
  }

  /// Stored reconnection attempts for each device
  final Map<String, int> _reconnectionAttempts = {};

  /// Timers for reconnection delays
  final Map<String, Timer> _reconnectionTimers = {};

  /// Maximum number of reconnection attempts
  static const int _maxReconnectAttempts = 3;

  /// Reconnection delay backoff (5, 10, 20 seconds)
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  /// Attempt to reconnect to a device with exponential backoff
  /// Read the current `autoReconnectEnabled` value for a device type.
  ///
  /// DEV-P1-1: Previously only [DeviceType.camera] honored the
  /// user-controlled flag; every other type silently auto-reconnected
  /// regardless of preference. This switch makes the bridge explicit
  /// so each device type's state notifier owns the answer.
  ///
  /// Switch device has no state provider yet (tracked under DEV-P2-1);
  /// it follows the legacy default of `true`.
  bool _getAutoReconnectFor(DeviceType type) {
    return switch (type) {
      DeviceType.camera => _ref.read(cameraStateProvider).autoReconnectEnabled,
      DeviceType.mount => _ref.read(mountStateProvider).autoReconnectEnabled,
      DeviceType.focuser =>
        _ref.read(focuserStateProvider).autoReconnectEnabled,
      DeviceType.filterWheel =>
        _ref.read(filterWheelStateProvider).autoReconnectEnabled,
      DeviceType.guider => _ref.read(guiderStateProvider).autoReconnectEnabled,
      DeviceType.rotator =>
        _ref.read(rotatorStateProvider).autoReconnectEnabled,
      DeviceType.dome => _ref.read(domeStateProvider).autoReconnectEnabled,
      DeviceType.weather =>
        _ref.read(weatherStateProvider).autoReconnectEnabled,
      DeviceType.safetyMonitor =>
        _ref.read(safetyMonitorStateProvider).autoReconnectEnabled,
      DeviceType.coverCalibrator =>
        _ref.read(coverCalibratorStateProvider).autoReconnectEnabled,
      DeviceType.switch_ => _ref.read(switchStateProvider).autoReconnectEnabled,
    };
  }

  Future<void> _attemptReconnect(DeviceType type, String deviceId) async {
    if (_suppressAutoReconnect) {
      return;
    }

    if (_isUserInitiatedDisconnect(deviceId)) {
      _safeLog(
        (logger) => logger.info(
          'Skipping auto-reconnect for user-initiated disconnect of '
          '${type.displayName} ($deviceId)',
          source: 'DeviceService',
        ),
        'user-disconnect-reconnect-skip',
      );
      return;
    }

    // Check if auto-reconnect is enabled for this device.
    final autoReconnectEnabled = _getAutoReconnectFor(type);

    if (!autoReconnectEnabled) {
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.info(
          'Auto-reconnect disabled for ${type.displayName} ($deviceId)',
          source: 'DeviceService',
        );
      } catch (e) {
        // Logging service not available
      }
      return;
    }

    // Get current attempt count
    final attemptCount = _reconnectionAttempts[deviceId] ?? 0;

    if (attemptCount >= _maxReconnectAttempts) {
      // Max attempts reached - notify user
      try {
        final logger = _ref.read(loggingServiceProvider);
        logger.error(
          'Failed to reconnect ${type.displayName} ($deviceId) after $_maxReconnectAttempts attempts',
          source: 'DeviceService',
        );
      } catch (e) {
        // Logging service not available
      }
      _showReconnectionFailedNotification(type, deviceId);
      _reconnectionAttempts.remove(deviceId);
      return;
    }

    // Increment attempt count
    _reconnectionAttempts[deviceId] = attemptCount + 1;

    // Get delay for this attempt
    final delay = attemptCount < _reconnectDelays.length
        ? _reconnectDelays[attemptCount]
        : _reconnectDelays.last;

    // Log reconnection attempt
    try {
      final logger = _ref.read(loggingServiceProvider);
      logger.info(
        'Scheduling reconnection attempt ${attemptCount + 1}/$_maxReconnectAttempts for ${type.displayName} ($deviceId) in ${delay.inSeconds}s at ${DateTime.now().add(delay).toIso8601String()}',
        source: 'DeviceService',
      );
    } catch (e) {
      // Logging service not available
    }

    // Cancel any existing reconnection timer for this device
    _reconnectionTimers[deviceId]?.cancel();

    // Schedule reconnection attempt
    _reconnectionTimers[deviceId] = Timer(delay, () async {
      try {
        // Log the actual attempt
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Attempting reconnection ${attemptCount + 1}/$_maxReconnectAttempts for ${type.displayName} ($deviceId) at ${DateTime.now().toIso8601String()}',
            source: 'DeviceService',
          );
        } catch (e) {
          // Logging service not available
        }

        await _performReconnection(type, deviceId);

        // Success - reset attempt count
        _reconnectionAttempts.remove(deviceId);
        _reconnectionTimers.remove(deviceId);

        // Log success
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.info(
            'Successfully reconnected ${type.displayName} ($deviceId) at ${DateTime.now().toIso8601String()}',
            source: 'DeviceService',
          );
        } catch (e) {
          // Logging service not available
        }

        // Show success notification
        _showReconnectionSuccessNotification(type, deviceId);

        // If this was a critical device and sequence is paused, consider resuming
        await _considerSequenceResume(type);
      } catch (e) {
        // Log the failure
        try {
          final logger = _ref.read(loggingServiceProvider);
          logger.warning(
            'Reconnection attempt ${attemptCount + 1}/$_maxReconnectAttempts failed for ${type.displayName} ($deviceId): $e',
            source: 'DeviceService',
          );
        } catch (logError) {
          // Logging service not available
        }

        // Reconnection failed - try again
        await _attemptReconnect(type, deviceId);
      }
    });
  }

  /// Consider resuming the sequence if reconnection was successful
  Future<void> _considerSequenceResume(DeviceType type) async {
    // Only for critical devices
    if (type != DeviceType.camera && type != DeviceType.mount) {
      return;
    }

    // Check if sequence is paused
    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.paused) {
      return;
    }

    // Check if both critical devices are connected (if they're in the profile)
    final activeProfile = _activeProfile;
    if (activeProfile == null) {
      return;
    }

    bool allCriticalDevicesConnected = true;

    // Check camera if in profile
    if (activeProfile.cameraId != null && activeProfile.cameraId!.isNotEmpty) {
      final cameraState = _ref.read(cameraStateProvider);
      if (cameraState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    // Check mount if in profile
    if (activeProfile.mountId != null && activeProfile.mountId!.isNotEmpty) {
      final mountState = _ref.read(mountStateProvider);
      if (mountState.connectionState != DeviceConnectionState.connected) {
        allCriticalDevicesConnected = false;
      }
    }

    // Resume if all critical devices are connected
    if (allCriticalDevicesConnected) {
      try {
        await resumeSequence();
      } catch (e) {
        // Log error if available
      }
    }
  }

  /// Perform the actual reconnection based on device type
  Future<void> _performReconnection(DeviceType type, String deviceId) async {
    switch (type) {
      case DeviceType.camera:
        final notifier = _ref.read(cameraStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.mount:
        final notifier = _ref.read(mountStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.focuser:
        final notifier = _ref.read(focuserStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.filterWheel:
        final notifier = _ref.read(filterWheelStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.guider:
        final notifier = _ref.read(guiderStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.rotator:
        final notifier = _ref.read(rotatorStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.dome:
        final notifier = _ref.read(domeStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.weather:
        final notifier = _ref.read(weatherStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.safetyMonitor:
        final notifier = _ref.read(safetyMonitorStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.switch_:
        final notifier = _ref.read(switchStateProvider.notifier);
        await notifier.connect(deviceId, maxRetries: 1);
        break;

      case DeviceType.coverCalibrator:
        // Cover calibrator devices not yet supported for reconnection
        break;
    }
  }

  /// Show notification that reconnection failed after max attempts
  void _showReconnectionFailedNotification(DeviceType type, String deviceId) {
    // Show UI notification with detailed troubleshooting info
    try {
      final uiNotifier = _ref.read(uiNotificationProvider.notifier);
      uiNotifier.showError(
        'Failed to reconnect ${type.displayName} after $_maxReconnectAttempts attempts.\n\n'
        'Troubleshooting steps:\n'
        '• Check device power and USB/network connections\n'
        '• Verify device drivers are installed and up to date\n'
        '• Try unplugging and reconnecting the device\n'
        '• Restart the device software (ASCOM/INDI/etc.)\n'
        '• Check for device error messages or logs\n\n'
        'Please fix the issue and reconnect manually.',
        title: '${type.displayName} Reconnection Failed',
        duration: const Duration(seconds: 15),
      );
    } catch (e) {
      // Ignore errors if notification system is not available
    }

    // Also send external notifications (Discord/Pushover) with detailed info
    try {
      final notificationService = _ref.read(notificationServiceProvider);
      notificationService.notifyError(
        errorTitle: 'Device Reconnection Failed',
        errorMessage:
            '${type.displayName} ($deviceId) could not be reconnected after $_maxReconnectAttempts attempts.\n\n'
            'Auto-reconnection has stopped. Manual intervention required.\n'
            'Check device power, connections, and drivers.',
        source: 'Device Monitor',
      );
    } catch (e) {
      // Ignore errors if notification service is not available
    }
  }

  /// Show notification that reconnection succeeded
  void _showReconnectionSuccessNotification(DeviceType type, String deviceId) {
    // Show UI notification
    try {
      final uiNotifier = _ref.read(uiNotificationProvider.notifier);
      uiNotifier.showSuccess(
        '${type.displayName} has been reconnected successfully.',
        title: 'Device Reconnected',
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      // Ignore errors if notification system is not available
    }

    // Also send external notifications if this was a critical device
    if (type == DeviceType.camera || type == DeviceType.mount) {
      try {
        final notificationService = _ref.read(notificationServiceProvider);
        notificationService.notifyCustom(
          title: 'Device Reconnected',
          message:
              '${type.displayName} ($deviceId) has been reconnected successfully and is back online.',
          priority: NotificationPriority.normal,
        );
      } catch (e) {
        // Ignore errors if notification service is not available
      }
    }
  }

  /// Cancel all pending reconnection attempts
  void _cancelAllReconnections() {
    for (final timer in _reconnectionTimers.values) {
      timer.cancel();
    }
    _reconnectionTimers.clear();
    _reconnectionAttempts.clear();
  }

  /// Handle disconnection of critical devices (camera, mount) during sequence execution
  Future<void> _handleCriticalDeviceDisconnect(
      String deviceType, String deviceId) async {
    // Check if sequence is currently active. A paused sequence still needs a
    // fresh checkpoint on critical disconnect so a crash during recovery does
    // not roll back to the previous periodic checkpoint.
    final sequenceState = _ref.read(sequenceExecutionStateProvider);
    if (sequenceState != SequenceExecutionState.running &&
        sequenceState != SequenceExecutionState.paused) {
      return; // Not active, no action needed
    }

    try {
      await _backend.saveCheckpoint();
    } catch (e) {
      _safeLog(
        (logger) => logger.error(
          'Failed to save checkpoint after critical $deviceType disconnect '
          '($deviceId): $e',
          source: 'DeviceService',
        ),
        'critical-disconnect-checkpoint',
      );
      try {
        _ref.read(uiNotificationProvider.notifier).showError(
              'Failed to save a sequence checkpoint after $deviceType disconnected.',
              title: 'Checkpoint Failed',
              duration: const Duration(seconds: 12),
            );
      } on Object {
        // Notification failure must not mask the hardware-protection pause.
      }
    }

    if (sequenceState == SequenceExecutionState.paused) {
      return;
    }

    // Pause the sequence
    try {
      await pauseSequence();
    } catch (e) {
      // Log error if available
    }

    // The sequence will resume automatically if reconnection succeeds
    // The reconnection logic in _performReconnection will handle resuming
  }

  void _handleSequencerEvent(NightshadeEvent event) {
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    final data = event.data;

    switch (event.eventType) {
      case 'SequenceStarted':
        final sequenceName = data['sequence_name'] as String? ?? 'Unknown';
        progressNotifier.updateState(SequenceExecutionState.running);
        progressNotifier.updateProgress(
            message: 'Started sequence: $sequenceName');
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'SequencePaused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
        break;

      case 'SequenceResumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'SequenceStopped':
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.idle;
        break;

      case 'SequenceCompleted':
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.completed;
        break;

      case 'NodeStarted':
        final nodeId = data['node_id'] as String? ?? '';
        final nodeType = data['node_type'] as String? ?? '';
        progressNotifier.updateProgress(
          currentNodeId: nodeId,
          currentNodeName: nodeType,
          currentNodeStatus: NodeStatus.running,
        );
        progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
        break;

      case 'NodeCompleted':
        final nodeId = data['node_id'] as String? ?? '';
        final success = data['success'] as bool? ?? false;
        progressNotifier.updateNodeStatus(
          nodeId,
          success ? NodeStatus.success : NodeStatus.failure,
        );
        break;

      case 'Progress':
        final current = (data['current'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        progressNotifier.updateProgress(completedExposures: current);
        progressNotifier.setTotals(total, 0);
        break;

      case 'TargetChanged':
        final targetName = data['target_name'] as String? ?? '';
        progressNotifier.updateProgress(currentTarget: targetName);
        break;

      case 'TargetCompleted':
        final targetName = data['target_name'] as String? ?? '';
        progressNotifier.updateProgress(
            message: 'Completed target: $targetName');
        break;

      case 'ExposureStarted':
        final frame = (data['frame'] as num?)?.toInt() ?? 0;
        final total = (data['total'] as num?)?.toInt() ?? 0;
        final filter = data['filter'] as String?;
        final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        progressNotifier.updateProgress(
          currentFilter: filter,
          message:
              'Exposure $frame/$total - ${durationSecs}s${filter != null ? " ($filter)" : ""}',
        );
        break;

      case 'ExposureCompleted':
        final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        final currentCompleted =
            _ref.read(sequenceProgressProvider).completedExposures;
        final currentIntegration =
            _ref.read(sequenceProgressProvider).completedIntegrationSecs;
        progressNotifier.updateProgress(
          completedExposures: currentCompleted + 1,
          completedIntegrationSecs: currentIntegration + durationSecs,
        );
        break;

      case 'Error':
        final message = data['message'] as String? ?? 'Unknown error';
        progressNotifier.updateProgress(message: 'Error: $message');
        break;
    }
  }

  void dispose() {
    _disposed = true;
    DeviceServiceLifecycle.unregister(this);
    _eventSubscription?.cancel();
    _temperaturePollingTimer?.cancel();
    _warmingTimer?.cancel();
    _userDisconnectDebounceTimer?.cancel();
    _cancelAllReconnections();
  }

  /// Discover available devices of a specific type
  ///
  /// Returns a list of [DeviceInfo] objects representing available devices.
  /// The DeviceInfo type is now the canonical type for device information.
  Future<List<DeviceInfo>> discoverDevices(DeviceType type) async {
    // Backend now returns DeviceInfo directly - no conversion needed
    return await _backend.discoverDevices(type);
  }

  /// Discover INDI devices at a specific server address
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    // Backend returns DeviceInfo directly
    return await _backend.discoverIndiAtAddress(host, port);
  }

  /// Discover Alpaca devices at a specific server address
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(
      String host, int port) async {
    // Backend returns DeviceInfo directly
    return await _backend.discoverAlpacaAtAddress(host, port);
  }

  /// Connect to a camera
  Future<void> connectCamera(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(cameraStateProvider.notifier);

      // DEV-P1-7: skip the discovery precondition. We used to run a full
      // `discoverDevices(camera)` sweep and reject any unknown id with
      // "Camera not found: $id" — that made a reconnect of a known-good
      // device fail whenever a discovery transient (USB blip, backend
      // swap, ...) had blanked the cache. The backend's `connectDevice`
      // is the only honest source of truth for "is this actually
      // reachable?", so we keep the cheap structural format check here
      // and let the backend report the real outcome.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('camera', deviceId);
      }

      final deviceName =
          await _resolveDeviceDisplayName(DeviceType.camera, deviceId);
      notifier.setConnecting(deviceId, deviceName);

      try {
        // Connect via native bridge
        await _backend.connectDevice(DeviceType.camera, deviceId);

        notifier.setConnected();

        // Apply active profile's cooling target temperature if available
        // and auto-start cooling if coolOnConnect is enabled
        try {
          final activeProfile = _ref.read(activeEquipmentProfileProvider);
          if (activeProfile?.defaultCoolingTemp != null) {
            notifier.setTargetTemp(activeProfile!.defaultCoolingTemp!);

            if (activeProfile.coolOnConnect) {
              await _backend.cameraSetCooling(
                deviceId: deviceId,
                enabled: true,
                targetTemp: activeProfile.defaultCoolingTemp,
              );
              notifier.setCooling(true);
            }
          }
        } catch (e) {
          _safeLog(
            (l) => l.warning(
                'Cool-on-connect failed (profile lookup or cooling command): $e',
                source: 'DeviceService'),
            'cool-on-connect',
          );
        }

        // IMG-P3-2: auto-detect manufacturer-recommended gain/offset from the
        // camera SDK and populate the active equipment profile when the user
        // has NOT explicitly set those values. We never overwrite an existing
        // profile value — the SDK recommendation is a starting point, not an
        // override of the user's deliberate choice.
        //
        // Failures here are non-fatal: connection has already succeeded, and
        // a missing recommendation is the honest "the SDK didn't tell us"
        // answer (most ASCOM/Alpaca/INDI cameras, and several native vendors,
        // don't expose this). The user can still set values manually.
        await _autoApplyRecommendedCameraSettings(deviceId, deviceName);

        // Start temperature polling (this will immediately poll and update)
        _startTemperaturePolling(deviceId);

        // Start heartbeat monitoring (10 second interval)
        try {
          await _backend.startDeviceHeartbeat(
            deviceType: DeviceType.camera,
            deviceId: deviceId,
            intervalMs: 10000,
          );

          // Log successful heartbeat start
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.info(
              'Started heartbeat monitoring for Camera ($deviceId) with 10s interval',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        } catch (e) {
          // Heartbeat monitoring is optional - log but don't fail connection
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.warning(
              'Failed to start heartbeat monitoring for Camera ($deviceId): $e. Device will remain connected but automatic reconnection may not work if connection is lost.',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        }
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// connect and apply them to the active equipment profile ONLY when the
  /// profile has no explicit value set.
  ///
  /// Contract:
  /// - Query the camera SDK via [NightshadeBackend.cameraGetRecommendedSettings].
  /// - If unityGain is non-null AND the profile's defaultGain is null, write
  ///   the recommendation through and log it.
  /// - Same for defaultOffset.
  /// - Existing user-set values are never overwritten.
  /// - Any failure (query failed, no active profile, no profile id) is logged
  ///   and swallowed — the camera is already connected; auto-detect is a
  ///   convenience, not a precondition.
  Future<void> _autoApplyRecommendedCameraSettings(
      String deviceId, String deviceName) async {
    try {
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile == null || activeProfile.id == null) {
        // No profile to update. Honest no-op.
        return;
      }

      // If the profile already has BOTH values set, skip the SDK query
      // entirely — there's nothing we'd want to write anyway.
      if (activeProfile.defaultGain != null &&
          activeProfile.defaultOffset != null) {
        return;
      }

      final CameraRecommendedSettings rec;
      try {
        rec = await _backend.cameraGetRecommendedSettings(deviceId);
      } catch (e) {
        _safeLog(
          (l) => l.warning(
              'Auto-detect recommended camera settings failed for $deviceName ($deviceId): $e',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // No recommendation available (typical for ASCOM/Alpaca/INDI and
      // Touptek/Player One/Atik/FLI/Moravian). Honest no-op.
      if (rec.unityGain == null && rec.defaultOffset == null) {
        if (rec.notes.isNotEmpty) {
          _safeLog(
            (l) => l.info(
                'Camera $deviceName reported no SDK recommendation: ${rec.notes}',
                source: 'DeviceService'),
            'auto-detect-recommended-settings',
          );
        }
        return;
      }

      // Decide what to apply. Never overwrite user values.
      final int? newGain =
          (activeProfile.defaultGain == null) ? rec.unityGain : null;
      final int? newOffset =
          (activeProfile.defaultOffset == null) ? rec.defaultOffset : null;

      if (newGain == null && newOffset == null) {
        // Both already set by the user; surface the recommendation in logs
        // so they can compare manually if interested.
        _safeLog(
          (l) => l.info(
              'Camera $deviceName advertised recommendation but profile already populated. '
              'SDK reported: unity_gain=${rec.unityGain}, default_offset=${rec.defaultOffset}. '
              'Notes: ${rec.notes}',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // Persist the new values.
      final notifier = _ref.read(equipmentProfilesProvider.notifier);
      final updated = activeProfile.copyWith(
        defaultGain: newGain ?? activeProfile.defaultGain,
        defaultOffset: newOffset ?? activeProfile.defaultOffset,
      );
      try {
        await notifier.updateProfile(updated);
      } catch (e) {
        _safeLog(
          (l) => l.warning(
              'Failed to persist auto-detected camera settings to profile ${activeProfile.id}: $e',
              source: 'DeviceService'),
          'auto-detect-recommended-settings',
        );
        return;
      }

      // Log clearly per task spec: "Auto-applied recommended gain from
      // camera (X): unity gain at G=Y".
      final logged = <String>[];
      if (newGain != null) {
        logged.add('unity gain G=$newGain');
      }
      if (newOffset != null) {
        logged.add('offset O=$newOffset');
      }
      _safeLog(
        (l) => l.info(
            'Auto-applied recommended camera settings from $deviceName: '
            '${logged.join(", ")} (notes: ${rec.notes})',
            source: 'DeviceService'),
        'auto-detect-recommended-settings',
      );
    } catch (e) {
      // Belt-and-braces: any unexpected error here must not break the
      // connect flow.
      _safeLog(
        (l) => l.warning(
            'Unexpected error in auto-detect recommended settings for $deviceId: $e',
            source: 'DeviceService'),
        'auto-detect-recommended-settings',
      );
    }
  }

  /// Public re-entry point: re-query the SDK for the recommendation. Used by
  /// the equipment-screen "Auto-detect" button.
  ///
  /// Returns the raw [CameraRecommendedSettings] from the backend so the UI
  /// can present the values BEFORE deciding whether to apply them.
  Future<CameraRecommendedSettings> queryRecommendedCameraSettings(
      String deviceId) {
    return _backend.cameraGetRecommendedSettings(deviceId);
  }

  /// Public re-entry point: apply a recommendation to the active profile,
  /// overwriting whatever was there. Used by the equipment-screen
  /// "Auto-detect" UI when the user explicitly confirms the apply.
  ///
  /// Returns true if at least one field was updated.
  Future<bool> applyRecommendedCameraSettings(
      CameraRecommendedSettings rec) async {
    final activeProfile = _ref.read(activeEquipmentProfileProvider);
    if (activeProfile == null || activeProfile.id == null) {
      return false;
    }
    if (rec.unityGain == null && rec.defaultOffset == null) {
      return false;
    }

    final updated = activeProfile.copyWith(
      defaultGain: rec.unityGain ?? activeProfile.defaultGain,
      defaultOffset: rec.defaultOffset ?? activeProfile.defaultOffset,
    );
    final notifier = _ref.read(equipmentProfilesProvider.notifier);
    await notifier.updateProfile(updated);
    return true;
  }

  /// Set camera cooling
  Future<void> setCameraCooling({
    required bool enabled,
    double? targetTemp,
  }) async {
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw Exception('Camera not connected');
    }

    // Use the connected device's ID from state, not the profile
    final deviceId = cameraState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No camera device ID available');
    }

    await _backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: enabled,
      targetTemp: targetTemp,
    );
  }

  /// Gradually warm the camera by stepping the target temperature up
  /// until the cooler power drops to 0%, then disabling the cooler.
  ///
  /// This is deliberately NOT temperature-aware. We don't care what
  /// the sensor reads - we just keep raising the setpoint so the cooler
  /// has less and less work to do. On a cold night (e.g. -10°C ambient)
  /// the cooler power will hit 0% well before the sensor reaches 0°C,
  /// which is exactly what we want. A temperature-based stopping
  /// condition would stall or fail in cold ambient conditions.
  ///
  /// The mechanism: ASCOM/INDI cameras accept a target temperature and
  /// the cooler's PID loop adjusts power to reach it. By steadily
  /// raising the target, the cooler reduces power. We watch the
  /// reported cooler power and disable the cooler once it hits 0%.
  Future<void> warmCamera({double ratePerMin = 2.0}) async {
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw Exception('Camera not connected');
    }

    final deviceId = cameraState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No camera device ID available');
    }

    // Cancel any previous warming in progress
    cancelWarmCamera();

    final notifier = _ref.read(cameraStateProvider.notifier);
    notifier.setWarming(true);
    _warmingCancelled = false;

    // Determine the starting setpoint from current sensor temperature.
    // If sensor temp is unavailable, start from the current target temp.
    final currentTemp = cameraState.temperature ?? cameraState.targetTemp;

    // We ramp in steps. Tick every 10 seconds, adjusting the target by
    // ratePerMin / 6 each tick (since 60s / 10s = 6 ticks per minute).
    const tickInterval = Duration(seconds: 10);
    final stepPerTick = ratePerMin / 6.0;
    var currentSetpoint = currentTemp;

    // Safety timeout: if warming hasn't finished after 30 minutes,
    // just disable the cooler. Something is wrong.
    const maxWarmingDuration = Duration(minutes: 30);
    final warmingStartTime = DateTime.now();

    _safeLog(
      (l) => l.info(
        'Starting gradual warm-up from ${currentTemp.toStringAsFixed(1)}°C at ${ratePerMin.toStringAsFixed(1)}°C/min (power-based stopping)',
        source: 'DeviceService',
      ),
      'warm-up-start',
    );

    // Set initial target to current temp (keeps cooler tracking but doesn't shock)
    await _backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: true,
      targetTemp: currentSetpoint,
    );

    _warmingTimer = Timer.periodic(tickInterval, (timer) async {
      if (_warmingCancelled) {
        timer.cancel();
        notifier.setWarming(false);
        return;
      }

      // Check camera is still connected
      final state = _ref.read(cameraStateProvider);
      if (state.connectionState != DeviceConnectionState.connected) {
        timer.cancel();
        notifier.setWarming(false);
        return;
      }

      // Check if cooler power has dropped to 0% - we're done
      final coolerPower = state.coolerPower ?? 0.0;
      if (coolerPower <= 2.0) {
        timer.cancel();
        try {
          await _backend.cameraSetCooling(
            deviceId: deviceId,
            enabled: false,
          );
          _safeLog(
            (l) => l.info(
              'Warm-up complete. Cooler power reached ${coolerPower.toStringAsFixed(0)}%, cooler disabled. Sensor: ${state.temperature?.toStringAsFixed(1) ?? "?"}°C',
              source: 'DeviceService',
            ),
            'warm-up-complete',
          );
        } catch (e) {
          _safeLog(
            (l) => l.error(
              'Failed to disable cooler at end of warm-up: $e',
              source: 'DeviceService',
            ),
            'warm-up-disable-fail',
          );
        }
        notifier.setWarming(false);
        return;
      }

      // Safety timeout
      if (DateTime.now().difference(warmingStartTime) > maxWarmingDuration) {
        timer.cancel();
        try {
          await _backend.cameraSetCooling(
            deviceId: deviceId,
            enabled: false,
          );
          _safeLog(
            (l) => l.warning(
              'Warm-up safety timeout (30 min). Cooler disabled at power ${coolerPower.toStringAsFixed(0)}%, sensor ${state.temperature?.toStringAsFixed(1) ?? "?"}°C',
              source: 'DeviceService',
            ),
            'warm-up-safety-timeout',
          );
        } catch (e) {
          _safeLog(
            (l) => l.error(
              'Failed to disable cooler after warm-up timeout: $e',
              source: 'DeviceService',
            ),
            'warm-up-timeout-disable-fail',
          );
        }
        notifier.setWarming(false);
        return;
      }

      // Step the target temperature up
      currentSetpoint += stepPerTick;
      try {
        await _backend.cameraSetCooling(
          deviceId: deviceId,
          enabled: true,
          targetTemp: currentSetpoint,
        );
        // Update the UI target temp so the user sees it climbing
        notifier.setTargetTemp(currentSetpoint);
      } catch (e) {
        _safeLog(
          (l) => l.error(
            'Error during warm-up step (setpoint ${currentSetpoint.toStringAsFixed(1)}°C): $e',
            source: 'DeviceService',
          ),
          'warm-up-step-fail',
        );
        // Don't cancel on transient errors - try again next tick
      }
    });
  }

  /// Cancel an in-progress gradual warm-up.
  /// The cooler remains in whatever state it was in at the time of cancellation.
  void cancelWarmCamera() {
    _warmingCancelled = true;
    _warmingTimer?.cancel();
    _warmingTimer = null;
    final notifier = _ref.read(cameraStateProvider.notifier);
    notifier.setWarming(false);
  }

  /// Disconnect camera
  Future<void> disconnectCamera() {
    return _trackInFlight(() async {
      // Cancel any warming in progress
      cancelWarmCamera();
      // Stop temperature polling first
      _stopTemperaturePolling();

      final notifier = _ref.read(cameraStateProvider.notifier);
      final state = _ref.read(cameraStateProvider);

      // Audit DEV-P2-6: surface "nothing connected" as a typed precondition
      // instead of a silent no-op so the equipment screen's bulk-disconnect
      // sweep can distinguish "already disconnected" (skip cleanly) from
      // "real disconnect failure" (toast + log).
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('camera');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        // Stop heartbeat monitoring
        try {
          await _backend.stopDeviceHeartbeat(deviceId);

          // Log successful heartbeat stop
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.info(
              'Stopped heartbeat monitoring for Camera ($deviceId)',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        } catch (e) {
          // Ignore errors during cleanup but log them
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.warning(
              'Error stopping heartbeat monitoring for Camera ($deviceId): $e',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        }

        // Disconnect device
        await _backend.disconnectDevice(DeviceType.camera, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a mount
  Future<void> connectMount(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(mountStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('mount', deviceId);
      }

      final deviceName =
          await _resolveDeviceDisplayName(DeviceType.mount, deviceId);
      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.mount, deviceId);

        notifier.setConnected();

        // Fetch actual mount status from hardware instead of hardcoding defaults
        try {
          final status = await _backend.getMountStatus(deviceId);
          notifier.updatePosition(
            status.rightAscension,
            status.declination,
            status.altitude,
            status.azimuth,
          );
          notifier.setParked(status.parked);
          notifier.setTracking(status.tracking);
          notifier.setSlewing(status.slewing);
        } catch (e) {
          // If status query fails, log but don't fail the connection
          _safeLog(
            (l) => l.warning(
              'Failed to get initial mount status for ($deviceId): $e',
              source: 'DeviceService',
            ),
            'mount-initial-status-fail',
          );
        }

        // Start heartbeat monitoring (10 second interval) for critical device
        try {
          await _backend.startDeviceHeartbeat(
            deviceType: DeviceType.mount,
            deviceId: deviceId,
            intervalMs: 10000,
          );

          // Log successful heartbeat start
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.info(
              'Started heartbeat monitoring for Mount ($deviceId) with 10s interval',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        } catch (e) {
          // Heartbeat monitoring is optional - log but don't fail connection
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.warning(
              'Failed to start heartbeat monitoring for Mount ($deviceId): $e. Device will remain connected but automatic reconnection may not work if connection is lost.',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        }
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect mount
  Future<void> disconnectMount() {
    return _trackInFlight(() async {
      final notifier = _ref.read(mountStateProvider.notifier);
      final state = _ref.read(mountStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('mount');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        // Stop heartbeat monitoring
        try {
          await _backend.stopDeviceHeartbeat(deviceId);

          // Log successful heartbeat stop
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.info(
              'Stopped heartbeat monitoring for Mount ($deviceId)',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        } catch (e) {
          // Ignore errors during cleanup but log them
          try {
            final logger = _ref.read(loggingServiceProvider);
            logger.warning(
              'Error stopping heartbeat monitoring for Mount ($deviceId): $e',
              source: 'DeviceService',
            );
          } catch (logError) {
            // Logging service not available
          }
        }

        await _backend.disconnectDevice(
          DeviceType.mount,
          deviceId,
        );
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a focuser
  Future<void> connectFocuser(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(focuserStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('focuser', deviceId);
      }

      final deviceName =
          await _resolveDeviceDisplayName(DeviceType.focuser, deviceId);
      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.focuser, deviceId);

        // Get actual focuser status from the backend (now typed FocuserStatus)
        final status = await _backend.getFocuserStatus(deviceId);

        notifier.setConnected(
          maxPosition: status.maxPosition,
          stepSize: status.stepSize,
          isAbsolute: status.isAbsolute,
          hasTemperature: status.hasTemperature,
        );
        notifier.updatePosition(status.position);
        notifier.setMoving(status.moving);
        if (status.temperature != null) {
          notifier.updateTemperature(status.temperature!);
        }
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect focuser
  Future<void> disconnectFocuser() {
    return _trackInFlight(() async {
      final notifier = _ref.read(focuserStateProvider.notifier);
      final state = _ref.read(focuserStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('focuser');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(
          DeviceType.focuser,
          deviceId,
        );
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a filter wheel
  Future<void> connectFilterWheel(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(filterWheelStateProvider.notifier);
      final logger = _ref.read(loggingServiceProvider);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('filter wheel', deviceId);
      }

      // Derive a friendly name without running discovery.
      // Discovery opens/closes hardware (e.g. ZWO EFW via native SDK) which
      // can interfere with subsequent position reads.  The device manager will
      // register the full DeviceInfo during api_connect_device anyway.
      final deviceName =
          await _resolveDeviceDisplayName(DeviceType.filterWheel, deviceId);

      notifier.setConnecting(deviceId, deviceName);

      try {
        await _backend.connectDevice(DeviceType.filterWheel, deviceId);

        // Give the filter wheel firmware time to synchronise the actual
        // encoder position after the USB/COM connection is established.
        // Some SDKs (ZWO EFW, ASCOM wrappers) report position 0 or -1
        // immediately after opening before the firmware has read the encoder.
        // Poll up to 5 times over ~2.5 s to get a stable reading.
        FilterWheelStatus status;
        int pollAttempts = 0;
        const maxPolls = 5;
        const pollDelay = Duration(milliseconds: 500);

        status = await _backend.getFilterWheelStatus(deviceId);
        logger.debug(
          'Filter wheel poll #0: position=${status.position}, '
          'moving=${status.moving}',
          source: 'DeviceService',
        );

        // Keep polling while position is -1 (moving/initializing)
        while (status.position < 0 && pollAttempts < maxPolls) {
          pollAttempts++;
          await Future.delayed(pollDelay);
          status = await _backend.getFilterWheelStatus(deviceId);
          logger.debug(
            'Filter wheel poll #$pollAttempts: position=${status.position}, '
            'moving=${status.moving}',
            source: 'DeviceService',
          );
        }

        logger.debug(
          'Filter wheel final status: ${status.filterNames.length} filter '
          'names=${status.filterNames}, position=${status.position}',
          source: 'DeviceService',
        );

        notifier.setConnected(
          filterNames: status.filterNames,
        );
        notifier.setDeviceName(deviceName);
        notifier.updatePosition(status.position);
        notifier.setMoving(status.moving);

        // After connection, sync profile/session filter names to the native
        // driver so user-defined names (Ha, OIII, SII, etc.) are used in
        // sequences and UI instead of generic "Filter 1", "Filter 2".
        await _syncFilterNamesToDriver(deviceId, status.filterNames);
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Sync filter names from the active equipment profile or session to the
  /// native driver after a filter wheel connects.
  ///
  /// Filter names are resolved in this priority order:
  /// 1. Active profile filter names (if profile exists and has filter names)
  /// 2. Session filter names (if set via sessionFilterNamesProvider)
  /// 3. Driver-reported names (no sync needed, already set)
  Future<void> _syncFilterNamesToDriver(
      String deviceId, List<String> driverNames) async {
    final notifier = _ref.read(filterWheelStateProvider.notifier);
    final logger = _ref.read(loggingServiceProvider);

    try {
      // Priority 1: Check active profile filter names
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile != null && activeProfile.filterNames.isNotEmpty) {
        final profileFilterNames = activeProfile.filterNames;
        logger.debug(
          'Profile has ${profileFilterNames.length} filter names; '
          'driver has ${driverNames.length} slots',
          source: 'DeviceService',
        );

        // Pad or trim profile names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (profileFilterNames.length < driverNames.length) {
          syncedNames = [
            ...profileFilterNames,
            ...driverNames.sublist(profileFilterNames.length),
          ];
          logger.debug(
            'Padded profile filter names to ${syncedNames.length}: '
            '$syncedNames',
            source: 'DeviceService',
          );
        } else if (profileFilterNames.length > driverNames.length &&
            driverNames.isNotEmpty) {
          syncedNames = profileFilterNames.sublist(0, driverNames.length);
        } else {
          syncedNames = profileFilterNames;
        }

        await _applyFilterNamesToNotifier(
          notifier: notifier,
          deviceId: deviceId,
          syncedNames: syncedNames,
        );
        logger.debug(
          'Profile filter names synced: $syncedNames',
          source: 'DeviceService',
        );
        return;
      }

      // Priority 2: Check session filter names
      final sessionFilterNames = _ref.read(sessionFilterNamesProvider);
      if (sessionFilterNames != null && sessionFilterNames.isNotEmpty) {
        logger.debug(
          'Session has ${sessionFilterNames.length} filter names; '
          'driver has ${driverNames.length} slots',
          source: 'DeviceService',
        );

        // Pad or trim session names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (sessionFilterNames.length < driverNames.length) {
          syncedNames = [
            ...sessionFilterNames,
            ...driverNames.sublist(sessionFilterNames.length),
          ];
        } else if (sessionFilterNames.length > driverNames.length &&
            driverNames.isNotEmpty) {
          syncedNames = sessionFilterNames.sublist(0, driverNames.length);
        } else {
          syncedNames = sessionFilterNames;
        }

        await _applyFilterNamesToNotifier(
          notifier: notifier,
          deviceId: deviceId,
          syncedNames: syncedNames,
        );
        logger.debug(
          'Session filter names synced: $syncedNames',
          source: 'DeviceService',
        );
        return;
      }

      // Priority 3: Use driver-reported names (already set, no sync needed)
      logger.debug(
        'No profile or session filter names; using driver-reported names',
        source: 'DeviceService',
      );
    } catch (e) {
      // Don't fail connection if filter name sync fails - log the error
      logger.warning(
        'Failed to sync filter names: $e',
        source: 'DeviceService',
      );
    }
  }

  /// Derive a human-readable name from a device ID without running discovery.
  /// e.g. "native:zwo_efw:0" → "ZWO EFW 0"
  ///      "ascom:ASCOM.EFWmini.FilterWheel" → "EFWmini FilterWheel"
  String _friendlyNameFromId(String deviceId) {
    if (deviceId.startsWith('native:zwo_efw:')) {
      final hwId = deviceId.split(':').last;
      return 'ZWO EFW $hwId';
    }
    if (deviceId.startsWith('native:qhy_cfw:')) {
      final camId = deviceId.split(':').last;
      return 'QHY CFW ($camId)';
    }
    if (deviceId.startsWith('native:fli_fw:')) {
      return 'FLI Filter Wheel';
    }
    if (deviceId.startsWith('ascom:')) {
      // "ascom:ASCOM.Vendor.FilterWheel" → keep last two segments
      final progId = deviceId.substring(6); // strip "ascom:"
      final parts = progId.split('.');
      if (parts.length >= 2) {
        return parts.sublist(1).join(' ');
      }
      return progId;
    }
    if (deviceId.startsWith('alpaca:')) {
      return 'Alpaca Filter Wheel';
    }
    return deviceId;
  }

  /// Disconnect filter wheel
  Future<void> disconnectFilterWheel() {
    return _trackInFlight(() async {
      final notifier = _ref.read(filterWheelStateProvider.notifier);
      final state = _ref.read(filterWheelStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('filter wheel');
      }

      _markUserInitiatedDisconnect(deviceId);
      _lastAppliedFilterOffset = 0;

      try {
        await _backend.disconnectDevice(
          DeviceType.filterWheel,
          deviceId,
        );
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a guider
  Future<void> connectGuider(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(guiderStateProvider.notifier);
      final isPhd2 = deviceId == 'phd2_guider' ||
          deviceId == 'phd2' ||
          deviceId.startsWith('phd2:') ||
          deviceId.startsWith('phd2://');

      // Special handling for PHD2 guider - uses different connection method
      if (isPhd2) {
        notifier.setConnecting('phd2_guider', 'PHD2 Guiding');
        try {
          final settings = await _ref.read(appSettingsProvider.future);
          // Auto-launch PHD2 on the imaging host when the socket is local.
          // Remote companions (NetworkBackend) must not spawn processes here —
          // they delegate launch to the desktop via POST /api/phd2/connect.
          // For remote PHD2 hosts (host != localhost/127.0.0.1) we never spawn.
          final connectHost = resolvePhd2ConnectHost(settings.phd2Host);
          if (_backend is! NetworkBackend && _isLocalHost(settings.phd2Host)) {
            await _ensurePhd2Running(
              executablePath: settings.phd2Path,
              host: connectHost,
              port: settings.phd2Port,
            );
          }
          await _backend.phd2Connect(
            host: connectHost,
            port: settings.phd2Port,
          );
          await pollPhd2Connected(_backend);
          notifier.setConnected();
        } catch (e) {
          notifier.setDisconnected();
          try {
            await _backend.phd2Disconnect();
          } catch (_) {
            // Best-effort cleanup after a failed connect attempt.
          }
          rethrow;
        }
        return;
      }

      // Standard guider connection (ASCOM/Alpaca/INDI).
      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('guider', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.guider, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.guider, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect guider
  Future<void> disconnectGuider() {
    return _trackInFlight(() async {
      final notifier = _ref.read(guiderStateProvider.notifier);
      final state = _ref.read(guiderStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('guider');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        // Special handling for PHD2
        if (deviceId == 'phd2_guider' ||
            deviceId == 'phd2' ||
            deviceId.startsWith('phd2:') ||
            deviceId.startsWith('phd2://')) {
          await _backend.phd2Disconnect();
        } else {
          await _backend.disconnectDevice(
            DeviceType.guider,
            deviceId,
          );
        }
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a dome
  Future<void> connectDome(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(domeStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('dome', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.dome, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.dome, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect dome
  Future<void> disconnectDome() {
    return _trackInFlight(() async {
      final notifier = _ref.read(domeStateProvider.notifier);
      final state = _ref.read(domeStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('dome');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.dome, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a weather device
  Future<void> connectWeather(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(weatherStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('weather station', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.weather, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.weather, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect weather device
  Future<void> disconnectWeather() {
    return _trackInFlight(() async {
      final notifier = _ref.read(weatherStateProvider.notifier);
      final state = _ref.read(weatherStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('weather station');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.weather, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a safety monitor
  Future<void> connectSafetyMonitor(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('safety monitor', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.safetyMonitor, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.safetyMonitor, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect safety monitor
  Future<void> disconnectSafetyMonitor() {
    return _trackInFlight(() async {
      final notifier = _ref.read(safetyMonitorStateProvider.notifier);
      final state = _ref.read(safetyMonitorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('safety monitor');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.safetyMonitor, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a switch device.
  ///
  /// DEV-P2-1: switch is a first-class device type with its own state
  /// provider and equipment-profile column. The Rust bridge exposes
  /// per-channel get/set under `api_switch_*`; per-channel UI is future
  /// work (see [SwitchState] docs) but the connect/disconnect path is
  /// real and must succeed before the user can flip any channels.
  Future<void> connectSwitch(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('switch', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.switch_, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.switch_, deviceId);
        notifier.setConnected();
        // Best-effort: fetch the channel snapshot so the card can render
        // per-channel toggles. Only attempted when the active backend is
        // the local FfiBackend (NetworkBackend would need a separate REST
        // endpoint that does not exist yet — tracked as follow-up).
        // Failures here MUST NOT abort the connect (CLAUDE.md "errors
        // are a feature" — surface as a warning but keep the device
        // marked connected).
        await refreshSwitchChannels();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect switch device.
  Future<void> disconnectSwitch() {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);
      final state = _ref.read(switchStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('switch');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.switch_, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Refresh the cached channel snapshot for the currently-connected
  /// switch device.
  ///
  /// Polls `api_switch_get_max`, then `api_switch_get_name` +
  /// `api_switch_get_state` for each channel, and stores the result on
  /// the [switchStateProvider]. Per-channel name/state fetches that
  /// individually fail fall back to a generated "Channel N" label and
  /// `false` state so a single misbehaving channel never blocks the
  /// whole panel; the failure is logged via the LoggingService.
  ///
  /// No-op when there is no connected switch device. No-op (but logs a
  /// warning) when running against [NetworkBackend], because there is
  /// no remote REST endpoint for per-channel switch reads yet.
  ///
  /// Errors at the top-level (e.g. `apiSwitchGetMax` throws) are
  /// surfaced through [ErrorService] so the user sees a toast — silent
  /// fallbacks would hide a real driver fault for the whole session.
  Future<void> refreshSwitchChannels() async {
    final notifier = _ref.read(switchStateProvider.notifier);
    final state = _ref.read(switchStateProvider);
    final deviceId = state.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    if (state.connectionState != DeviceConnectionState.connected) return;

    if (_backend is! FfiBackend && !switchBridgeBypassBackendCheck) {
      _safeLog(
        (logger) => logger.warning(
          'refreshSwitchChannels skipped: NetworkBackend has no remote '
          'switch endpoint yet (device=$deviceId).',
          source: 'DeviceService',
        ),
        'switch-refresh-network-backend',
      );
      return;
    }

    try {
      final count = await switchBridgeGetMax(deviceId);
      final names = <String>[];
      final states = <bool>[];
      for (var i = 0; i < count; i++) {
        String name;
        try {
          name = await switchBridgeGetName(deviceId, i);
        } catch (e) {
          // Per-channel label fetch failed — fall back to a generated
          // label so the row still renders. The state below is the
          // load-bearing data; an opaque label is acceptable.
          _safeLog(
            (logger) => logger.warning(
              'Switch channel name fetch failed for $deviceId#$i: $e',
              source: 'DeviceService',
            ),
            'switch-channel-name-fetch',
          );
          name = '';
        }
        bool on;
        try {
          on = await switchBridgeGetState(deviceId, i);
        } catch (e) {
          _safeLog(
            (logger) => logger.warning(
              'Switch channel state fetch failed for $deviceId#$i: $e',
              source: 'DeviceService',
            ),
            'switch-channel-state-fetch',
          );
          on = false;
        }
        names.add(name);
        states.add(on);
      }
      notifier.setChannels(
        count: count,
        names: names,
        states: states,
        refreshedAt: DateTime.now(),
      );
    } catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'refreshSwitchChannels failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'switch-refresh',
      );
      try {
        final errSvc = _ref.read(errorServiceProvider);
        errSvc.logDeviceError(
          operation: 'switch_refresh',
          message: 'Failed to refresh switch channels: $e',
          deviceType: 'Switch',
          deviceId: deviceId,
          severity: ErrorSeverity.warning,
        );
      } on Object catch (errSvcErr) {
        _safeLog(
          (logger) => logger.warning(
            'errorService emission for switch_refresh failed: $errSvcErr',
            source: 'DeviceService',
          ),
          'switch-refresh-errsvc',
        );
      }
    }
  }

  /// Toggle a single switch channel on or off.
  ///
  /// Calls the bridge synchronously and only updates the cached state
  /// after the bridge confirms success — optimistic updates would lie
  /// to the user about hardware state when a relay fails to engage.
  ///
  /// Throws [DeviceNotConnectedException] when no switch is connected.
  /// Bridge errors are routed through [ErrorService] (toast + history)
  /// and then rethrown so callers can react (e.g. a UI that wants to
  /// revert a switch widget's visual state).
  Future<void> setSwitchChannel(int channelIndex, bool on) {
    return _trackInFlight(() async {
      final notifier = _ref.read(switchStateProvider.notifier);
      final state = _ref.read(switchStateProvider);
      final deviceId = state.deviceId;
      if (deviceId == null ||
          deviceId.isEmpty ||
          state.connectionState != DeviceConnectionState.connected) {
        throw const DeviceNotConnectedException('switch');
      }
      if (channelIndex < 0 || channelIndex >= state.channelCount) {
        throw ArgumentError.value(
          channelIndex,
          'channelIndex',
          'Out of range for channelCount=${state.channelCount}',
        );
      }

      if (_backend is! FfiBackend && !switchBridgeBypassBackendCheck) {
        throw UnsupportedError(
          'setSwitchChannel is not supported on the current backend '
          '(NetworkBackend has no remote switch write endpoint).',
        );
      }

      try {
        await switchBridgeSetState(deviceId, channelIndex, on);
        notifier.setChannelState(channelIndex, on);
      } catch (e) {
        _safeLog(
          (logger) => logger.warning(
            'setSwitchChannel failed for $deviceId#$channelIndex on=$on: $e',
            source: 'DeviceService',
          ),
          'switch-set-channel',
        );
        try {
          final errSvc = _ref.read(errorServiceProvider);
          errSvc.logDeviceError(
            operation: 'switch_set_state',
            message: 'Failed to set switch channel $channelIndex to '
                '${on ? "on" : "off"}: $e',
            deviceType: 'Switch',
            deviceId: deviceId,
            severity: ErrorSeverity.error,
          );
        } on Object catch (errSvcErr) {
          _safeLog(
            (logger) => logger.warning(
              'errorService emission for switch_set_state failed: '
              '$errSvcErr',
              source: 'DeviceService',
            ),
            'switch-set-channel-errsvc',
          );
        }
        rethrow;
      }
    });
  }

  /// Connect to a rotator
  Future<void> connectRotator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(rotatorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('rotator', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.rotator, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.rotator, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect rotator
  Future<void> disconnectRotator() {
    return _trackInFlight(() async {
      final notifier = _ref.read(rotatorStateProvider.notifier);
      final state = _ref.read(rotatorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('rotator');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.rotator, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect to a cover calibrator (flat panel)
  Future<void> connectCoverCalibrator(String deviceId) {
    return _trackInFlight(() async {
      final notifier = _ref.read(coverCalibratorStateProvider.notifier);

      // DEV-P1-7: format check only; backend is the source of truth for
      // reachability. See [connectCamera] for the full rationale.
      if (!isValidDeviceIdFormat(deviceId)) {
        throw InvalidDeviceIdException('cover calibrator', deviceId);
      }

      notifier.setConnecting(
        deviceId,
        await _resolveDeviceDisplayName(DeviceType.coverCalibrator, deviceId),
      );

      try {
        await _backend.connectDevice(DeviceType.coverCalibrator, deviceId);
        notifier.setConnected();
      } catch (e) {
        notifier.setDisconnected();
        rethrow;
      }
    });
  }

  /// Disconnect cover calibrator
  Future<void> disconnectCoverCalibrator() {
    return _trackInFlight(() async {
      final notifier = _ref.read(coverCalibratorStateProvider.notifier);
      final state = _ref.read(coverCalibratorStateProvider);

      // Audit DEV-P2-6: see [disconnectCamera] for the rationale.
      final deviceId = state.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw const DeviceNotConnectedException('cover calibrator');
      }

      _markUserInitiatedDisconnect(deviceId);

      try {
        await _backend.disconnectDevice(DeviceType.coverCalibrator, deviceId);
      } finally {
        notifier.setDisconnected();
      }
    });
  }

  /// Connect all devices from a profile sequentially with per-device timeout
  /// and early abort on failure (DV-P0-5).
  ///
  /// Imaging-chain devices (camera → mount → focuser → filter wheel) abort
  /// the remainder when any link fails because they often share USB hubs.
  /// Optional peripherals (dome, weather, etc.) still run after imaging
  /// failures when invoked through [connectAllFromProfile] instead.
  Future<void> connectProfile({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
    String? rotatorId,
    String? domeId,
    String? weatherId,
    String? safetyMonitorId,
    String? switchId,
    String? coverCalibratorId,
    void Function(DeviceConnectProgress progress)? onProgress,
  }) {
    return _trackInFlight(() async {
      final entries = <(String, String, Future<void> Function(String))>[
        if (cameraId != null && cameraId.isNotEmpty)
          ('camera', cameraId, connectCamera),
        if (mountId != null && mountId.isNotEmpty)
          ('mount', mountId, connectMount),
        if (focuserId != null && focuserId.isNotEmpty)
          ('focuser', focuserId, connectFocuser),
        if (filterWheelId != null && filterWheelId.isNotEmpty)
          ('filter wheel', filterWheelId, connectFilterWheel),
        if (guiderId != null && guiderId.isNotEmpty)
          ('guider', guiderId, connectGuider),
        if (rotatorId != null && rotatorId.isNotEmpty)
          ('rotator', rotatorId, connectRotator),
        if (domeId != null && domeId.isNotEmpty) ('dome', domeId, connectDome),
        if (weatherId != null && weatherId.isNotEmpty)
          ('weather station', weatherId, connectWeather),
        if (safetyMonitorId != null && safetyMonitorId.isNotEmpty)
          ('safety monitor', safetyMonitorId, connectSafetyMonitor),
        if (switchId != null && switchId.isNotEmpty)
          ('switch', switchId, connectSwitch),
        if (coverCalibratorId != null && coverCalibratorId.isNotEmpty)
          ('cover calibrator', coverCalibratorId, connectCoverCalibrator),
      ];

      for (final (deviceType, id, connect) in entries) {
        onProgress?.call(DeviceConnectProgress(
          deviceType: deviceType,
          deviceId: id,
          status: DeviceConnectProgressStatus.connecting,
        ));

        try {
          await connect(id).timeout(_connectProfileDeviceTimeout);
          onProgress?.call(DeviceConnectProgress(
            deviceType: deviceType,
            deviceId: id,
            status: DeviceConnectProgressStatus.connected,
          ));
        } catch (e) {
          onProgress?.call(DeviceConnectProgress(
            deviceType: deviceType,
            deviceId: id,
            status: DeviceConnectProgressStatus.failed,
            error: e,
            errorMessage: e.toString(),
          ));
          throw Exception('Profile connect aborted at $deviceType: $e');
        }
      }
    });
  }

  /// Connect all devices from the active equipment profile
  Future<void> connectActiveProfile() async {
    final profilesState = await _ref.read(equipmentProfilesProvider.future);
    final activeProfile = profilesState.activeProfile;

    if (activeProfile == null) {
      throw Exception('No active equipment profile selected');
    }

    await connectProfile(
      cameraId: activeProfile.cameraId,
      mountId: activeProfile.mountId,
      focuserId: activeProfile.focuserId,
      filterWheelId: activeProfile.filterWheelId,
      guiderId: activeProfile.guiderId,
      rotatorId: activeProfile.rotatorId,
      domeId: activeProfile.domeId,
      weatherId: activeProfile.weatherId,
      safetyMonitorId: activeProfile.safetyMonitorId,
      switchId: activeProfile.switchId,
      coverCalibratorId: activeProfile.coverCalibratorId,
    );
  }

  /// DEV-P1-5: parallel "Connect All" with per-device progress.
  ///
  /// Returns a [Stream] of [DeviceConnectProgress] events that the caller
  /// (typically the equipment screen) can subscribe to so each device card
  /// can render its own live status: idle → connecting → connected/failed.
  ///
  /// Why this exists: the equipment screen's previous "Connect All" button
  /// iterated devices sequentially with `await`. Ten devices × 3-5 s each
  /// meant 30-50 s of wall-clock time with no feedback per device. A user
  /// staring at a single spinner has no idea whether the focuser is the
  /// one taking forever or whether the dome failed and the mount succeeded.
  ///
  /// Contract:
  ///
  /// * Every configured device-type from [profile] is connected in parallel
  ///   with `Future.wait`. Device connects do not interact with each other
  ///   during the connect phase (mount/camera/focuser/etc. each go to a
  ///   different driver) so parallelism is safe.
  /// * For each device, the stream emits:
  ///     1. `connecting` immediately as the call is dispatched, and
  ///     2. `connected` if the underlying `connectX` completes, or
  ///        `failed` carrying the raw error if it throws.
  /// * One device failing does NOT block any other device. Per-device
  ///   errors are reported as `failed` events; the stream itself never
  ///   errors and always closes cleanly once every device is settled.
  /// * Errors are a feature: the original backend error is preserved on
  ///   the `failed` event so the UI can show it (driver error, "device not
  ///   reachable", USB hub blip, etc.). We do NOT swallow or rewrite the
  ///   error.
  /// * If [profile] has no configured devices, the stream closes
  ///   immediately with no events.
  ///
  /// The returned stream is single-subscription so initial `connecting`
  /// events are buffered until the caller attaches its listener. UI
  /// surfaces that need to fan out to multiple widgets should feed the
  /// stream through [deviceConnectionProgressProvider]
  /// (see `record(event)`), which materializes the events into a
  /// `ref.watch`-able snapshot that any number of widgets can observe.
  Stream<DeviceConnectProgress> connectAllFromProfile(
      EquipmentProfileModel profile) {
    // (id, deviceType label, connector). Order is informational only —
    // every device is dispatched in parallel.
    final entries = <(String?, String, Future<void> Function(String))>[
      (profile.cameraId, 'camera', connectCamera),
      (profile.mountId, 'mount', connectMount),
      (profile.focuserId, 'focuser', connectFocuser),
      (profile.filterWheelId, 'filter wheel', connectFilterWheel),
      (profile.guiderId, 'guider', connectGuider),
      (profile.rotatorId, 'rotator', connectRotator),
      (profile.domeId, 'dome', connectDome),
      (profile.weatherId, 'weather station', connectWeather),
      (profile.safetyMonitorId, 'safety monitor', connectSafetyMonitor),
      (profile.switchId, 'switch', connectSwitch),
      (profile.coverCalibratorId, 'cover calibrator', connectCoverCalibrator),
    ];

    // Use a single-subscription StreamController so events are buffered
    // until the caller subscribes. A broadcast controller would drop the
    // initial `connecting` events because the caller hasn't yet attached
    // its `await for` listener at the moment we add them.
    final controller = StreamController<DeviceConnectProgress>();

    // Filter to only configured devices. An empty list still produces a
    // valid stream — the caller just sees no events before close.
    final active = entries
        .where((e) => e.$1 != null && e.$1!.isNotEmpty)
        .map((e) => (e.$1!, e.$2, e.$3))
        .toList(growable: false);

    if (active.isEmpty) {
      // No devices configured — close immediately so the caller's `await
      // for` exits cleanly.
      scheduleMicrotask(controller.close);
      return controller.stream;
    }

    // Defer dispatch one microtask so the caller (typically `await for`)
    // has time to attach its listener before any events fire. The
    // single-subscription controller buffers anyway, but emitting on the
    // next turn also keeps observable ordering deterministic in tests
    // that drive multiple sweeps in the same event-loop turn.
    scheduleMicrotask(() {
      // Dispatch every connect in parallel. Each future swallows its own
      // error and routes it onto the stream as a `failed` event so one
      // bad device cannot abort the sweep.
      final futures = <Future<void>>[];
      for (final (id, deviceType, connect) in active) {
        controller.add(DeviceConnectProgress(
          deviceType: deviceType,
          deviceId: id,
          status: DeviceConnectProgressStatus.connecting,
        ));

        futures.add(
          connect(id).then(
            (_) {
              if (!controller.isClosed) {
                controller.add(DeviceConnectProgress(
                  deviceType: deviceType,
                  deviceId: id,
                  status: DeviceConnectProgressStatus.connected,
                ));
              }
            },
          ).catchError((Object error, StackTrace stack) {
            if (!controller.isClosed) {
              controller.add(DeviceConnectProgress(
                deviceType: deviceType,
                deviceId: id,
                status: DeviceConnectProgressStatus.failed,
                error: error,
                errorMessage: error.toString(),
              ));
            }
          }),
        );
      }

      // Close the stream once every device has settled. We use
      // `Future.wait` without `eagerError` because we've already caught
      // every per-device error above — every future resolves
      // successfully here.
      Future.wait(futures).whenComplete(() {
        if (!controller.isClosed) {
          controller.close();
        }
      });
    });

    return controller.stream;
  }

  /// Disconnect all devices
  ///
  /// Each device-type disconnect now throws [DeviceNotConnectedException]
  /// when the matching state provider has no `deviceId` (DEV-P2-6). For a
  /// bulk-disconnect sweep that is the normal case (most equipment profiles
  /// list only a handful of devices), so we silence that specific exception
  /// and let every other failure (driver error, stale handle, timeout, …)
  /// propagate so the caller can surface it. We deliberately do not use
  /// `Future.wait`: a single failure there cancels reporting of the others.
  Future<void> disconnectAll() async {
    final disconnects = <(Future<void> Function(), String)>[
      (disconnectCamera, 'camera'),
      (disconnectMount, 'mount'),
      (disconnectFocuser, 'focuser'),
      (disconnectFilterWheel, 'filter wheel'),
      (disconnectGuider, 'guider'),
      (disconnectRotator, 'rotator'),
      (disconnectDome, 'dome'),
      (disconnectWeather, 'weather station'),
      (disconnectSafetyMonitor, 'safety monitor'),
      (disconnectSwitch, 'switch'),
      (disconnectCoverCalibrator, 'cover calibrator'),
    ];

    final errors = <String>[];
    for (final (disconnect, name) in disconnects) {
      try {
        await disconnect();
      } on DeviceNotConnectedException {
        // Expected — the matching device type is not currently connected.
        continue;
      } catch (e) {
        errors.add('$name: $e');
      }
    }

    if (errors.isNotEmpty) {
      throw Exception(
          'Some devices failed to disconnect:\n${errors.join('\n')}');
    }
  }

  // ===========================================================================
  // Mount Control
  // ===========================================================================

  /// Get the connected mount device ID from mount state (preferred) or active profile
  Future<String?> _getMountDeviceId() async {
    // First check if a mount is currently connected via state provider
    final mountState = _ref.read(mountStateProvider);
    if (mountState.connectionState == DeviceConnectionState.connected &&
        mountState.deviceId != null &&
        mountState.deviceId!.isNotEmpty) {
      return mountState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.mountId);
  }

  /// Slew mount to coordinates
  Future<void> slewMountToCoordinates(double ra, double dec) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description: 'Slewing to RA ${_formatRA(ra)}, Dec ${_formatDec(dec)}',
      canCancel: true,
    );

    try {
      await _backend.mountSlewToCoordinates(deviceId, ra, dec);
      mountNotifier.updatePosition(ra, dec, 0.0, 0.0);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Format RA for display (hours:minutes)
  String _formatRA(double raHours) {
    final h = raHours.floor();
    final m = ((raHours - h) * 60).floor();
    return '${h}h ${m}m';
  }

  /// Format Dec for display (degrees)
  String _formatDec(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '';
    return '$sign${decDeg.toStringAsFixed(1)}°';
  }

  /// Sync mount to coordinates
  Future<void> syncMountToCoordinates(double ra, double dec) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSync(deviceId, ra, dec);

    // Update local state
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.updatePosition(ra, dec, 0.0, 0.0);
  }

  /// Park the mount
  Future<void> parkMount() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.parkMount,
      description: 'Parking mount',
    );

    try {
      await _backend.mountPark(deviceId);
      mountNotifier.setParked(true);
      mountNotifier.setTracking(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.parkMount);
    }
  }

  /// Unpark the mount
  Future<void> unparkMount() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.unparkMount,
      description: 'Unparking mount',
    );

    try {
      await _backend.mountUnpark(deviceId);
      final mountNotifier = _ref.read(mountStateProvider.notifier);
      mountNotifier.setParked(false);
    } finally {
      operationsNotifier.completeOperation(OperationType.unparkMount);
    }
  }

  /// Enable or disable mount tracking
  Future<void> setMountTracking(bool enabled) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSetTracking(deviceId, enabled);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setTracking(enabled);
  }

  /// Set mount tracking rate
  Future<void> setMountTrackingRate(int rate) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountSetTrackingRate(deviceId, rate);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    // Update the state with the new tracking rate
    mountNotifier.setTrackingRate(TrackingRate.values[rate]);
  }

  /// Abort mount slew (emergency stop)
  Future<void> abortMountSlew() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    await _backend.mountAbort(deviceId);
    final mountNotifier = _ref.read(mountStateProvider.notifier);
    mountNotifier.setSlewing(false);
  }

  /// Slew mount to horizontal (alt/az) coordinates
  Future<void> slewMountToAltAz(double altitude, double azimuth) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description:
          'Slewing to Alt ${altitude.toStringAsFixed(1)}, Az ${azimuth.toStringAsFixed(1)}',
      canCancel: true,
    );

    try {
      await _backend.mountSlewAltAz(deviceId, altitude, azimuth);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Find mount home position
  Future<void> findMountHome() async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No mount connected');
    }

    final mountNotifier = _ref.read(mountStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    mountNotifier.setSlewing(true);
    operationsNotifier.startOperation(
      type: OperationType.slewToTarget,
      description: 'Finding mount home position',
    );

    try {
      await _backend.mountFindHome(deviceId);
      mountNotifier.setParked(false);
    } finally {
      mountNotifier.setSlewing(false);
      operationsNotifier.completeOperation(OperationType.slewToTarget);
    }
  }

  /// Pulse guide the mount in a given direction for a duration
  Future<void> pulseGuidMount({
    required String direction,
    required int durationMs,
  }) async {
    final deviceId = await _getMountDeviceId();
    if (deviceId == null) {
      throw Exception('No mount connected');
    }

    await _backend.mountPulseGuide(
      deviceId: deviceId,
      direction: direction,
      durationMs: durationMs,
    );
  }

  // ===========================================================================
  // Device ID Helpers
  // ===========================================================================

  /// Get the connected camera device ID
  /// First checks the currently connected camera state, then falls back to active profile
  Future<String?> _getCameraDeviceId() async {
    // First check if we have a currently connected camera
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState == DeviceConnectionState.connected &&
        cameraState.deviceId != null &&
        cameraState.deviceId!.isNotEmpty) {
      return cameraState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.cameraId);
  }

  // ===========================================================================
  // Focuser Control
  // ===========================================================================

  /// Get the connected focuser device ID
  /// First checks the currently connected focuser state, then falls back to active profile
  Future<String?> _getFocuserDeviceId() async {
    // First check if we have a currently connected focuser
    final focuserState = _ref.read(focuserStateProvider);
    if (focuserState.connectionState == DeviceConnectionState.connected &&
        focuserState.deviceId != null &&
        focuserState.deviceId!.isNotEmpty) {
      return focuserState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.focuserId);
  }

  /// Move focuser to absolute position
  Future<void> moveFocuserTo(int position) async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.focuserMove,
      description: 'Moving focuser to $position',
    );

    try {
      await _backend.focuserMoveTo(deviceId, position);
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: position,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Move focuser by relative amount
  /// Uses the backend's native relative move which queries actual device position
  Future<void> moveFocuserRelative(int delta) async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    final direction = delta > 0 ? 'out' : 'in';
    operationsNotifier.startOperation(
      type: OperationType.focuserMove,
      description: 'Moving focuser ${delta.abs()} steps $direction',
    );

    try {
      // Get current position to compute target
      final currentStatus = await _backend.getFocuserStatus(deviceId);
      final targetPosition = currentStatus.position + delta;

      // Use backend's native relative move which queries actual device position
      await _backend.focuserMoveRelative(deviceId, delta);
      await _verifyFocuserPosition(
        deviceId: deviceId,
        targetPosition: targetPosition,
      );
    } finally {
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.focuserMove);
    }
  }

  /// Halt focuser movement
  Future<void> haltFocuser() async {
    final deviceId = await _getFocuserDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);

    try {
      await _backend.focuserHalt(deviceId);
      // Query actual position from device after halt
      final status = await _backend.getFocuserStatus(deviceId);
      focuserNotifier.updatePosition(status.position);
    } finally {
      focuserNotifier.setMoving(false);
    }
  }

  /// Verify focuser reached target position with polling and timeout.
  ///
  /// Polls the focuser position every 500ms until it reaches the target
  /// (within 1 step tolerance). Times out after 300 seconds.
  Future<void> _verifyFocuserPosition({
    required String deviceId,
    required int targetPosition,
  }) async {
    final deadline = DateTime.now().add(_focuserMoveTimeout);
    final focuserNotifier = _ref.read(focuserStateProvider.notifier);

    while (true) {
      final status = await _backend.getFocuserStatus(deviceId);
      focuserNotifier.updatePosition(status.position);
      focuserNotifier.setMoving(status.moving);
      if (status.temperature != null) {
        focuserNotifier.updateTemperature(status.temperature!);
      }

      // Check if we've reached the target (within 1 step tolerance)
      if ((status.position - targetPosition).abs() <= 1) {
        focuserNotifier.setMoving(false);
        return;
      }

      // Check if focuser stopped moving but hasn't reached target (stall)
      if (!status.moving && (status.position - targetPosition).abs() > 1) {
        throw Exception(
          'Focuser stalled at position ${status.position}, '
          'target was $targetPosition.',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Focuser did not reach position $targetPosition within '
          '${_focuserMoveTimeout.inSeconds}s '
          '(last reported position: ${status.position}).',
        );
      }

      await Future.delayed(_focuserMovePollInterval);
    }
  }

  // ===========================================================================
  // Rotator Control
  // ===========================================================================

  /// Get the connected rotator device ID.
  /// First checks the currently connected rotator state, then falls back to active profile.
  Future<String?> _getRotatorDeviceId() async {
    final rotatorState = _ref.read(rotatorStateProvider);
    if (rotatorState.connectionState == DeviceConnectionState.connected &&
        rotatorState.deviceId != null &&
        rotatorState.deviceId!.isNotEmpty) {
      return rotatorState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.rotatorId);
  }

  /// Move rotator to an absolute angle (0-360 degrees).
  Future<void> moveRotatorTo(double angle) async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    rotatorNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.rotatorMove,
      description: 'Moving rotator to ${angle.toStringAsFixed(1)}°',
    );

    try {
      await _backend.rotatorMoveTo(deviceId, angle);
      // Poll until movement completes
      await _verifyRotatorPosition(deviceId: deviceId, targetAngle: angle);
    } finally {
      rotatorNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.rotatorMove);
    }
  }

  /// Move rotator by a relative angle (degrees).
  Future<void> moveRotatorRelative(double delta) async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    final direction = delta > 0 ? 'CW' : 'CCW';
    rotatorNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.rotatorMove,
      description: 'Rotating ${delta.abs().toStringAsFixed(1)}° $direction',
    );

    try {
      // Get current angle to compute target for verification
      final currentAngle = await _backend.rotatorGetAngle(deviceId);
      final targetAngle = (currentAngle + delta) % 360.0;

      await _backend.rotatorMoveRelative(deviceId, delta);
      await _verifyRotatorPosition(
          deviceId: deviceId, targetAngle: targetAngle);
    } finally {
      rotatorNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.rotatorMove);
    }
  }

  /// Halt rotator movement.
  Future<void> haltRotator() async {
    final deviceId = await _getRotatorDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No rotator connected');
    }

    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);

    try {
      await _backend.rotatorHalt(deviceId);
      // Query actual angle from device after halt
      final angle = await _backend.rotatorGetAngle(deviceId);
      rotatorNotifier.updatePosition(angle);
    } finally {
      rotatorNotifier.setMoving(false);
    }
  }

  /// Verify rotator reached target angle with polling and timeout.
  ///
  /// Polls the rotator angle every 500ms until it reaches the target
  /// (within 0.5 degree tolerance). Times out after 120 seconds.
  static const Duration _rotatorMoveTimeout = Duration(seconds: 120);
  static const Duration _rotatorMovePollInterval = Duration(milliseconds: 500);

  Future<void> _verifyRotatorPosition({
    required String deviceId,
    required double targetAngle,
  }) async {
    final deadline = DateTime.now().add(_rotatorMoveTimeout);
    final rotatorNotifier = _ref.read(rotatorStateProvider.notifier);

    while (true) {
      final status = await _backend.getRotatorStatus(deviceId);
      rotatorNotifier.updatePosition(status.position,
          mechanicalPosition: status.mechanicalPosition);
      rotatorNotifier.setMoving(status.moving);

      // Check if we're within tolerance (handle wraparound at 0/360)
      final diff = (status.position - targetAngle).abs();
      final wrappedDiff = (360.0 - diff).abs();
      final effectiveDiff = diff < wrappedDiff ? diff : wrappedDiff;

      if (effectiveDiff < 0.5) {
        rotatorNotifier.setMoving(false);
        return;
      }

      // Check if rotator stopped moving but hasn't reached target (stall)
      if (!status.moving && effectiveDiff >= 0.5) {
        throw Exception(
          'Rotator stalled at ${status.position.toStringAsFixed(1)}°, '
          'target was ${targetAngle.toStringAsFixed(1)}° '
          '(diff: ${effectiveDiff.toStringAsFixed(1)}°).',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Rotator did not reach ${targetAngle.toStringAsFixed(1)}° within '
          '${_rotatorMoveTimeout.inSeconds}s '
          '(last reported angle: ${status.position.toStringAsFixed(1)}°).',
        );
      }

      await Future.delayed(_rotatorMovePollInterval);
    }
  }

  /// Run autofocus routine
  ///
  /// When [useSettingsDefaults] is true (the default), the persisted autofocus
  /// settings from [appSettingsProvider] are used. The explicit parameters serve
  /// as overrides only when [useSettingsDefaults] is false.
  ///
  /// If `afDisableGuidingDuringAf` is enabled in settings, guiding is
  /// paused before the AF run and resumed afterwards.
  Future<AutofocusResult> runAutofocus({
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    bool useSettingsDefaults = true,
  }) async {
    if (_isAutofocusRunning) {
      throw Exception(
          'Autofocus is already running. Wait for it to complete before starting another.');
    }
    _isAutofocusRunning = true;

    final focuserDeviceId = await _getFocuserDeviceId();
    if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
      throw Exception('No focuser connected');
    }

    // Use the connected camera's device ID
    final cameraDeviceId = await _getCameraDeviceId();
    if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
      throw Exception('No camera connected');
    }

    // Resolve effective AF parameters from settings or explicit values
    final appSettings = _ref.read(appSettingsProvider).valueOrNull;

    final double effectiveExposureTime;
    final int effectiveStepSize;
    final int effectiveStepsOut;
    final String effectiveMethod;
    final int effectiveBinning;
    final String effectiveCurveFitting;
    final int effectiveNumberOfAttempts;
    final int effectiveExposuresPerPoint;
    final double effectiveRSquaredThreshold;
    final double effectiveOuterCropRatio;
    final double effectiveInnerCropRatio;
    final int effectiveUseBrightestNStars;
    final int effectiveFocuserSettleTimeMs;
    final String effectiveBacklashCompMethod;
    final int effectiveBacklashIn;
    final int effectiveBacklashOut;
    final bool disableGuidingDuringAf;

    if (useSettingsDefaults && appSettings == null) {
      // Settings not yet loaded from DB — don't silently fall back to hardcoded
      // defaults because the user's persisted configuration would be ignored.
      throw Exception(
          'Cannot run autofocus with settings defaults: AppSettings not yet loaded. '
          'Wait for the app to finish initializing before running autofocus.');
    }

    if (useSettingsDefaults && appSettings != null) {
      effectiveExposureTime = appSettings.afExposureTime;
      effectiveStepSize = appSettings.afStepSize;
      effectiveStepsOut = appSettings.afInitialOffsetSteps;
      effectiveMethod = appSettings.afMethod;
      effectiveBinning = appSettings.afBinning;
      effectiveCurveFitting = appSettings.afCurveFitting;
      effectiveNumberOfAttempts = appSettings.afNumberOfAttempts;
      effectiveExposuresPerPoint = appSettings.afExposuresPerPoint;
      effectiveRSquaredThreshold = appSettings.afRSquaredThreshold;
      effectiveOuterCropRatio = appSettings.afOuterCropRatio;
      effectiveInnerCropRatio = appSettings.afInnerCropRatio;
      effectiveUseBrightestNStars = appSettings.afUseBrightestNStars;
      effectiveFocuserSettleTimeMs = appSettings.afFocuserSettleTimeMs;
      effectiveBacklashCompMethod = appSettings.afBacklashCompMethod;
      effectiveBacklashIn = appSettings.afBacklashIn;
      effectiveBacklashOut = appSettings.afBacklashOut;
      disableGuidingDuringAf = appSettings.afDisableGuidingDuringAf;
    } else {
      effectiveExposureTime = exposureTime;
      effectiveStepSize = stepSize;
      effectiveStepsOut = stepsOut;
      effectiveMethod = method;
      effectiveBinning = binning;
      effectiveCurveFitting = 'Hyperbolic';
      effectiveNumberOfAttempts = 1;
      effectiveExposuresPerPoint = 1;
      effectiveRSquaredThreshold = 0.7;
      effectiveOuterCropRatio = 1.0;
      effectiveInnerCropRatio = 0.0;
      effectiveUseBrightestNStars = 0;
      effectiveFocuserSettleTimeMs = 500;
      effectiveBacklashCompMethod = 'Overshoot';
      effectiveBacklashIn = 350;
      effectiveBacklashOut = 0;
      disableGuidingDuringAf = false;
    }

    final focuserNotifier = _ref.read(focuserStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    focuserNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.autofocus,
      description: 'Running autofocus ($effectiveMethod)',
      currentStep: 'Initializing...',
      canCancel: true,
    );

    // Pause guiding if configured and guiding is active
    final guiderState = _ref.read(guiderStateProvider);
    final wasGuiding = disableGuidingDuringAf && guiderState.isGuiding;
    if (wasGuiding) {
      try {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.info(
          'Pausing guiding for autofocus run',
          source: 'DeviceService',
        );
        await stopGuiding();
      } catch (e) {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.warning(
          'Failed to pause guiding before autofocus: $e',
          source: 'DeviceService',
        );
      }
    }

    try {
      final result = await _backend.autofocusStart(
        deviceId: focuserDeviceId,
        cameraId: cameraDeviceId,
        exposureTime: effectiveExposureTime,
        stepSize: effectiveStepSize,
        stepsOut: effectiveStepsOut,
        method: effectiveMethod,
        binning: effectiveBinning,
        curveFitting: effectiveCurveFitting,
        numberOfAttempts: effectiveNumberOfAttempts,
        exposuresPerPoint: effectiveExposuresPerPoint,
        rSquaredThreshold: effectiveRSquaredThreshold,
        outerCropRatio: effectiveOuterCropRatio,
        innerCropRatio: effectiveInnerCropRatio,
        useBrightestNStars: effectiveUseBrightestNStars,
        focuserSettleTimeMs: effectiveFocuserSettleTimeMs,
        backlashCompMethod: effectiveBacklashCompMethod,
        backlashIn: effectiveBacklashIn,
        backlashOut: effectiveBacklashOut,
      );

      // Smart notification for autofocus completion
      final hfrText = result.bestHfr.toStringAsFixed(2);
      _ref.read(smartNotificationServiceProvider).showSuccessIfNotOnScreens(
            message: 'Autofocus complete (HFR: $hfrText)',
            relevantScreens: [
              AppScreen.imaging,
              AppScreen.equipment,
              AppScreen.sequencer
            ],
            title: 'Autofocus',
          );

      return result;
    } finally {
      _isAutofocusRunning = false;
      focuserNotifier.setMoving(false);
      operationsNotifier.completeOperation(OperationType.autofocus);

      // Resume guiding if it was paused
      if (wasGuiding) {
        try {
          final loggingService = _ref.read(loggingServiceProvider);
          loggingService.info(
            'Resuming guiding after autofocus run',
            source: 'DeviceService',
          );
          await startGuiding();
        } catch (e) {
          final loggingService = _ref.read(loggingServiceProvider);
          loggingService.warning(
            'Failed to resume guiding after autofocus: $e',
            source: 'DeviceService',
          );
        }
      }
    }
  }

  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  /// Get the connected filter wheel device ID
  /// First checks the currently connected filter wheel state, then falls back to active profile
  Future<String?> _getFilterWheelDeviceId() async {
    // First check if we have a currently connected filter wheel
    final filterWheelState = _ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState == DeviceConnectionState.connected &&
        filterWheelState.deviceId != null &&
        filterWheelState.deviceId!.isNotEmpty) {
      return filterWheelState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.filterWheelId);
  }

  /// Set filter wheel position
  ///
  /// Changes the filter wheel to the specified position and automatically
  /// applies focus offset if configured for the selected filter.
  Future<void> setFilterWheelPosition(int position) async {
    final deviceId = await _getFilterWheelDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No filter wheel connected');
    }

    final filterWheelNotifier = _ref.read(filterWheelStateProvider.notifier);
    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);

    // Get filter name for display
    final filterWheelState = _ref.read(filterWheelStateProvider);
    final filterNames = filterWheelState.filterNames;
    final filterName = position >= 0 && position < filterNames.length
        ? filterNames[position]
        : 'Position $position';

    filterWheelNotifier.setMoving(true);
    operationsNotifier.startOperation(
      type: OperationType.filterChange,
      description: 'Changing filter to $filterName',
    );

    var hardwareStillMoving = false;
    try {
      // Move the filter wheel
      _ref.read(loggingServiceProvider).debug(
            'Changing filter wheel $deviceId to $filterName '
            '(position $position)',
            source: 'DeviceService',
          );
      await _backend.filterWheelSetPosition(deviceId, position);

      await _verifyFilterWheelPosition(
        deviceId: deviceId,
        expectedPosition: position,
        filterNames: filterNames,
      );

      // Apply focus offset only after position is verified (DV-P0-6).
      if (position >= 0 && position < filterNames.length) {
        await _applyFilterFocusOffset(filterNames[position]);
      }
    } catch (e) {
      hardwareStillMoving =
          await _recoverFilterWheelMovingState(deviceId, filterWheelNotifier);
      rethrow;
    } finally {
      if (!hardwareStillMoving) {
        filterWheelNotifier.setMoving(false);
      }
      operationsNotifier.completeOperation(OperationType.filterChange);
    }
  }

  /// After a failed verify, sync position/moving from hardware instead of
  /// blindly clearing moving state while the wheel is still rotating.
  Future<bool> _recoverFilterWheelMovingState(
    String deviceId,
    FilterWheelStateNotifier filterWheelNotifier,
  ) async {
    try {
      final status = await _backend.getFilterWheelStatus(deviceId);
      filterWheelNotifier.updatePosition(status.position);
      final stillMoving = status.moving || status.position < 0;
      filterWheelNotifier.setMoving(stillMoving);
      return stillMoving;
    } on Object catch (e) {
      _safeLog(
        (logger) => logger.warning(
          'Filter wheel moving-state recovery failed for $deviceId: $e',
          source: 'DeviceService',
        ),
        'filter-wheel-recover-moving',
      );
      return false;
    }
  }

  Future<void> _verifyFilterWheelPosition({
    required String deviceId,
    required int expectedPosition,
    required List<String> filterNames,
  }) async {
    final deadline = DateTime.now().add(_filterWheelVerifyTimeout);
    final filterWheelNotifier = _ref.read(filterWheelStateProvider.notifier);

    while (true) {
      final status = await _backend.getFilterWheelStatus(deviceId);
      final isMoving = status.moving || status.position < 0;

      filterWheelNotifier.updatePosition(status.position);
      filterWheelNotifier.setMoving(isMoving);

      if (!isMoving && status.position == expectedPosition) {
        return;
      }

      if (!isMoving && status.position != expectedPosition) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final actualName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel reported "$actualName" after change, expected "$expectedName".',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        final expectedName = _formatFilterName(filterNames, expectedPosition);
        final lastName = _formatFilterName(filterNames, status.position);
        throw Exception(
          'Filter wheel did not reach "$expectedName" within ${_filterWheelVerifyTimeout.inSeconds}s '
          '(last reported "$lastName").',
        );
      }

      await Future.delayed(_filterWheelVerifyPollInterval);
    }
  }

  String _formatFilterName(List<String> filterNames, int position) {
    if (position >= 0 && position < filterNames.length) {
      return filterNames[position];
    }
    return 'Position $position';
  }

  /// Apply focus offset for a given filter
  ///
  /// Checks if there's a configured offset for this filter and moves
  /// the focuser accordingly. This is called automatically by setFilterWheelPosition.
  /// Respects the `useFilterFocusOffsets` toggle from AppSettings.
  ///
  /// Uses delta-based offset application: when switching from filter A to
  /// filter B, the focuser is moved by (B_offset - A_offset) rather than
  /// cumulative addition, preventing drift over multiple filter changes.
  ///
  /// Per-filter autofocus config `focusOffset` values from AppSettings take
  /// precedence over the general filter offset provider values.
  Future<void> _applyFilterFocusOffset(String filterName) async {
    try {
      // Check if filter focus offsets are enabled in settings.
      // If settings haven't loaded yet, skip offsets (fail closed) rather than
      // applying offsets the user may have disabled.
      final appSettings = _ref.read(appSettingsProvider).valueOrNull;
      if (appSettings == null || !appSettings.useFilterFocusOffsets) {
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.debug(
          appSettings == null
              ? 'Filter focus offsets skipped: settings not yet loaded for "$filterName"'
              : 'Filter focus offsets disabled in settings, skipping offset for "$filterName"',
          source: 'DeviceService',
        );
        return;
      }

      // Check if focuser is connected
      final focuserDeviceId = await _getFocuserDeviceId();
      if (focuserDeviceId == null || focuserDeviceId.isEmpty) {
        return;
      }

      // Check if focuser is ready
      final focuserState = _ref.read(focuserStateProvider);
      if (focuserState.connectionState != DeviceConnectionState.connected) {
        return;
      }

      // Resolve the effective offset for this filter.
      // Per-filter AF config focusOffset takes precedence if set.
      int newOffset = 0;

      final afFilterSettings = AutofocusSettings.parseFilterSettingsJson(
          appSettings.afFilterSettingsJson);
      final perFilterConfig = afFilterSettings[filterName];
      if (perFilterConfig != null && perFilterConfig.focusOffset != 0) {
        newOffset = perFilterConfig.focusOffset;
      } else {
        final filterOffsetState = _ref.read(filterOffsetProvider);
        newOffset = filterOffsetState.offsets[filterName] ?? 0;
      }

      // Calculate delta from last applied offset
      final delta = newOffset - _lastAppliedFilterOffset;

      if (delta == 0) {
        // No movement needed
        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.debug(
          'Filter "$filterName" offset ($newOffset) same as previous, no focuser move needed',
          source: 'DeviceService',
        );
        return;
      }

      // Move focuser by the delta amount
      final currentPosition = focuserState.position ?? 0;
      final targetPosition = currentPosition + delta;

      final focuserNotifier = _ref.read(focuserStateProvider.notifier);
      focuserNotifier.setMoving(true);

      try {
        await _backend.focuserMoveTo(focuserDeviceId, targetPosition);
        focuserNotifier.updatePosition(targetPosition);
        _lastAppliedFilterOffset = newOffset;

        final loggingService = _ref.read(loggingServiceProvider);
        loggingService.info(
          'Applied focus offset for filter "$filterName": delta=$delta steps '
          '(offset=$newOffset, moved to position $targetPosition)',
          source: 'DeviceService',
        );
      } finally {
        focuserNotifier.setMoving(false);
      }
    } catch (e) {
      // Don't fail filter change if focus offset fails
      final loggingService = _ref.read(loggingServiceProvider);
      loggingService.error(
        'Failed to apply focus offset for filter "$filterName": $e',
        source: 'DeviceService',
      );
    }
  }

  // ===========================================================================
  // Guiding Control
  // ===========================================================================

  /// Get the connected guider device ID
  /// First checks the currently connected guider state, then falls back to active profile
  Future<String?> _getGuiderDeviceId() async {
    // First check if we have a currently connected guider
    final guiderState = _ref.read(guiderStateProvider);
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.deviceId != null &&
        guiderState.deviceId!.isNotEmpty) {
      return guiderState.deviceId;
    }

    return _activeProfileDeviceId((profile) => profile.guiderId);
  }

  /// Start guiding
  Future<void> startGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.guideSettle,
      description: 'Starting guiding and settling',
      currentStep: 'Calibrating...',
    );

    try {
      await _backend.guiderStartGuiding(
        deviceId: deviceId,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      final guiderNotifier = _ref.read(guiderStateProvider.notifier);
      guiderNotifier.setGuiding(true);
    } finally {
      operationsNotifier.completeOperation(OperationType.guideSettle);
    }
  }

  /// Stop guiding
  Future<void> stopGuiding() async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }

    await _backend.guiderStopGuiding(deviceId: deviceId);

    final guiderNotifier = _ref.read(guiderStateProvider.notifier);
    guiderNotifier.setGuiding(false);
  }

  /// Dither
  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final deviceId = await _getGuiderDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('No guider connected');
    }

    final operationsNotifier = _ref.read(activeOperationsProvider.notifier);
    operationsNotifier.startOperation(
      type: OperationType.dither,
      description: 'Dithering ${amount.toStringAsFixed(1)} px',
      currentStep: 'Moving...',
    );

    try {
      await _backend.guiderDither(
        deviceId: deviceId,
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
    } finally {
      operationsNotifier.completeOperation(OperationType.dither);
    }
  }

  // ===========================================================================
  // Sequencer Control
  // ===========================================================================

  Future<void> startSequence() async {
    await _backend.sequencerStart();
  }

  Future<void> stopSequence() async {
    await _backend.sequencerStop();
  }

  Future<void> pauseSequence() async {
    await _backend.sequencerPause();
  }

  Future<void> resumeSequence() async {
    await _backend.sequencerResume();
  }

  Future<void> loadSequence(String json) async {
    await _backend.sequencerLoadJson(json);
  }

  Future<SequencerStatus> getSequencerStatus() async {
    return await _backend.sequencerGetStatus();
  }

  // ---------------------------------------------------------------------------
  // PHD2 auto-launch
  //
  // Why: PHD2 is an external program. Users routinely configure a path to
  // its executable in Settings → PHD2 expecting "Connect" to start the
  // process when it is not already running. The previous behaviour required
  // the user to launch PHD2 separately before pressing Connect, which made
  // the path field misleading.
  //
  // Audit-handoff §2.1 WIRE-UP item #1.
  // ---------------------------------------------------------------------------

  /// Maximum wait for the PHD2 socket to come up after spawning the process.
  static const Duration _phd2LaunchTimeout = Duration(seconds: 10);
  static const Duration _phd2PollInterval = Duration(milliseconds: 250);

  /// True when the configured host is the same machine (i.e. we should
  /// auto-spawn PHD2 ourselves rather than expecting it to be remote).
  bool _isLocalHost(String host) {
    if (kIsWeb) return false;
    final normalized = host.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  /// Ensure PHD2 is running on [host]:[port]. If a socket is already
  /// accepting connections we return immediately; otherwise we spawn the
  /// configured executable and wait up to [_phd2LaunchTimeout] for the port
  /// to open.
  Future<void> _ensurePhd2Running({
    required String executablePath,
    required String host,
    required int port,
  }) async {
    if (await _isPortOpen(host, port)) {
      // Already running — nothing to do.
      return;
    }

    final notifications = _ref.read(uiNotificationProvider.notifier);
    final configuredPath = executablePath.trim();
    if (configuredPath.isNotEmpty) {
      final exe = File(configuredPath);
      if (!await exe.exists()) {
        throw FileSystemException(
          'PHD2 executable not found. Update Settings → PHD2 Guiding → '
          'PHD2 executable path or clear it to use automatic discovery.',
          configuredPath,
        );
      }

      notifications.showInfo(
        'PHD2 not running — launching $configuredPath...',
        title: 'PHD2',
        duration: const Duration(seconds: 5),
      );

      try {
        await Process.start(
          configuredPath,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      } on ProcessException catch (e) {
        throw ProcessException(
          configuredPath,
          const <String>[],
          'Failed to launch PHD2 (${e.message}). Check the configured '
          'PHD2 executable path.',
          e.errorCode,
        );
      }
    } else {
      notifications.showInfo(
        'PHD2 not running — searching for installed PHD2...',
        title: 'PHD2',
        duration: const Duration(seconds: 5),
      );

      try {
        await bridge_api.apiLaunchPhd2();
      } catch (e) {
        throw StateError(
          'PHD2 is not running and could not be launched automatically. '
          'Install PHD2 or set Settings → PHD2 Guiding → PHD2 executable path. '
          '($e)',
        );
      }
    }

    // Poll for the socket to open. PHD2 typically takes 2-5s to begin
    // accepting connections on cold start.
    final deadline = DateTime.now().add(_phd2LaunchTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isPortOpen(host, port)) {
        return;
      }
      await Future.delayed(_phd2PollInterval);
    }

    throw TimeoutException(
      'PHD2 launched but did not open port $port on $host within '
      '${_phd2LaunchTimeout.inSeconds} seconds. Verify PHD2 is configured '
      'to expose its server interface.',
      _phd2LaunchTimeout,
    );
  }

  /// Check whether [host]:[port] is accepting TCP connections.
  Future<bool> _isPortOpen(String host, int port) async {
    final connectHost = resolvePhd2ConnectHost(host);
    try {
      final socket = await Socket.connect(
        connectHost,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Provider for the device service
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final backend = ref.watch(backendProvider);
  final service = DeviceService(ref, backend);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for available cameras
final availableCamerasProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.camera);
});

/// Provider for available mounts
final availableMountsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.mount);
});

/// Provider for available focusers
final availableFocusersProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.focuser);
});

/// Provider for available filter wheels
final availableFilterWheelsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref
      .watch(deviceServiceProvider)
      .discoverDevices(DeviceType.filterWheel);
});

/// Provider for available guiders
final availableGuidersProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.guider);
});

/// Provider for available rotators
final availableRotatorsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.rotator);
});

/// Provider for available domes
final availableDomesProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.dome);
});

/// Provider for available weather devices
final availableWeatherProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.weather);
});

/// Provider for available safety monitors
final availableSafetyMonitorsProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref
      .watch(deviceServiceProvider)
      .discoverDevices(DeviceType.safetyMonitor);
});

/// Provider for available switch devices (DEV-P2-1).
final availableSwitchesProvider = FutureProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).discoverDevices(DeviceType.switch_);
});
