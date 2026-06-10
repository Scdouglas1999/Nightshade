import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;
import '../providers/equipment_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/backend_provider.dart';
import '../providers/sequence_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_notification_provider.dart';
import '../providers/operation_progress_provider.dart';
import '../providers/filter_offset_provider.dart';
import '../providers/current_screen_provider.dart';
import '../providers/unified_discovery_provider.dart';
import 'smart_notification_service.dart';
import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart' hide TrackingRate;
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart' show AutofocusSettings;
import '../utils/device_id.dart';
import 'camera_temperature_poller.dart';
import 'camera_warmup_controller.dart';
import 'device_heartbeat_router.dart';
import 'device_reconnect_coordinator.dart';
import 'device_exceptions.dart';
import 'logging_service.dart';
import 'error_service.dart';
import 'phd2_launcher.dart';
import 'phd2_status_poll.dart';
import 'predictive_af_service.dart';
import 'switch_channel_service.dart';
import 'device_service_lifecycle.dart';

// Re-export backend types for backward compatibility
// These were previously defined locally but are now consolidated in backend_types
export '../models/backend/device_types.dart' show DeviceType, DriverType;
export '../models/backend/device_info.dart' show DeviceInfo;

part 'device_service/event_handling.dart';
part 'device_service/control_helpers.dart';
part 'device_service/connections.dart';
part 'device_service/profile_connections.dart';
part 'device_service/mount_controls.dart';
part 'device_service/focuser_rotator_controls.dart';
part 'device_service/autofocus_controls.dart';
part 'device_service/filter_wheel_controls.dart';
part 'device_service/guiding_sequencer_controls.dart';

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

/// Service for managing device discovery and connections
///
/// This service uses the NightshadeBackend abstraction to communicate
/// with devices via different backends (FFI for desktop, Network for mobile).
class DeviceService {
  final Ref _ref;
  final NightshadeBackend _backend;

  // Per-channel switch refresh + write logic lives on [SwitchChannelService]
  // (DEV-P2-1 follow-up, A-10 god-class split). The four `switchBridge*`
  // static hooks and the `switchBridgeBypassBackendCheck` flag now live
  // on that class; tests bind directly via
  // `SwitchChannelService.switchBridge* = ...` and reset with
  // `SwitchChannelService.resetHooks()` in `tearDown`.
  StreamSubscription? _eventSubscription;
  late final CameraTemperaturePoller _temperaturePoller;
  late final CameraWarmupController _warmupController;
  late final Phd2Launcher _phd2Launcher;
  late final DeviceReconnectCoordinator _reconnectCoordinator;
  late final DeviceHeartbeatRouter _heartbeat;
  late final SwitchChannelService _switchChannels;

  static const Duration _filterWheelVerifyTimeout = Duration(seconds: 60);
  static const Duration _filterWheelVerifyPollInterval =
      Duration(milliseconds: 250);

  static const Duration _focuserMoveTimeout = Duration(seconds: 300);
  static const Duration _focuserMovePollInterval = Duration(milliseconds: 500);

  int _focuserVerifyGeneration = 0;
  int _rotatorVerifyGeneration = 0;
  int _filterWheelVerifyGeneration = 0;

  /// Tracks the last applied filter focus offset per filter wheel so that
  /// multiple wheels do not clobber each other's delta calculations.
  final Map<String, int> _lastAppliedFilterOffsetByWheel = {};

  /// In-flight guarded operations — backend swap waits for zero (DV-P0-2).
  int _inFlightOperations = 0;
  final List<Completer<void>> _quiesceWaiters = [];

  bool _disposed = false;

  static const Duration _connectProfileDeviceTimeout = Duration(seconds: 60);
  static const Duration _quiesceTimeout = Duration(seconds: 30);

  /// Guard against concurrent autofocus runs. Only one AF can run at a time
  /// since the focuser and camera are shared hardware resources.
  bool _isAutofocusRunning = false;

  bool get isAutofocusRunning => _isAutofocusRunning;

  DeviceService(this._ref, this._backend) {
    _temperaturePoller = CameraTemperaturePoller(
      ref: _ref,
      backend: _backend,
    );
    _warmupController = CameraWarmupController(
      ref: _ref,
      backend: _backend,
    );
    _phd2Launcher = Phd2Launcher(ref: _ref);
    // Construct the heartbeat router first so the reconnect coordinator
    // can drive the "reconnecting" health indicator through it (the
    // native HeartbeatReconnecting event is never emitted, so the Dart
    // side surfaces that state from the reconnect signals it does see).
    _heartbeat = DeviceHeartbeatRouter(ref: _ref, backend: _backend);
    _reconnectCoordinator = DeviceReconnectCoordinator(
      ref: _ref,
      backend: _backend,
      resumeSequence: resumeSequence,
      pauseSequence: pauseSequence,
      surfaceReconnecting: (deviceId, {int attempt = 0, int maxAttempts = 0}) =>
          _heartbeat.surfaceReconnecting(
        deviceId: deviceId,
        attempt: attempt,
        maxAttempts: maxAttempts,
      ),
    );
    _switchChannels = SwitchChannelService(ref: _ref, backend: _backend);
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
    _reconnectCoordinator.prepareForBackendSwap();
    cancelWarmCamera();
    _temperaturePoller.stop();
    _focuserVerifyGeneration++;
    _rotatorVerifyGeneration++;
    _filterWheelVerifyGeneration++;
    _lastAppliedFilterOffsetByWheel.clear();
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

  void dispose() {
    _disposed = true;
    DeviceServiceLifecycle.unregister(this);
    _eventSubscription?.cancel();
    _temperaturePoller.dispose();
    _warmupController.dispose();
    _reconnectCoordinator.cancelAll();
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

  // Public device orchestration stays on DeviceService so existing callers,
  // mocks, and provider contracts keep the same surface.
  Future<void> connectCamera(String deviceId) => _connectCamera(deviceId);
  Future<CameraRecommendedSettings> queryRecommendedCameraSettings(
          String deviceId) =>
      _queryRecommendedCameraSettings(deviceId);
  Future<bool> applyRecommendedCameraSettings(CameraRecommendedSettings rec) =>
      _applyRecommendedCameraSettings(rec);
  Future<void> setCameraCooling({required bool enabled, double? targetTemp}) =>
      _setCameraCooling(enabled: enabled, targetTemp: targetTemp);
  Future<void> warmCamera({double ratePerMin = 2.0}) =>
      _warmCamera(ratePerMin: ratePerMin);
  void cancelWarmCamera() => _cancelWarmCamera();
  Future<void> disconnectCamera() => _disconnectCamera();
  Future<void> connectMount(String deviceId) => _connectMount(deviceId);
  Future<void> disconnectMount() => _disconnectMount();
  Future<void> connectFocuser(String deviceId) => _connectFocuser(deviceId);
  Future<void> disconnectFocuser() => _disconnectFocuser();
  Future<void> connectFilterWheel(String deviceId) =>
      _connectFilterWheel(deviceId);
  Future<void> disconnectFilterWheel() => _disconnectFilterWheel();
  Future<void> connectGuider(String deviceId) => _connectGuider(deviceId);
  Future<void> disconnectGuider() => _disconnectGuider();

  /// Whether [deviceId]'s most recent disconnect was user-initiated (within
  /// the coordinator's debounce window). Exposed so external watchers —
  /// e.g. the PHD2 controller's crash-relaunch path — can distinguish a
  /// deliberate disconnect from a process/link loss.
  bool isUserInitiatedDisconnect(String deviceId) =>
      _reconnectCoordinator.isUserInitiatedDisconnect(deviceId);

  Future<void> connectDome(String deviceId) => _connectDome(deviceId);
  Future<void> disconnectDome() => _disconnectDome();
  Future<void> connectWeather(String deviceId) => _connectWeather(deviceId);
  Future<void> disconnectWeather() => _disconnectWeather();
  Future<void> connectSafetyMonitor(String deviceId) =>
      _connectSafetyMonitor(deviceId);
  Future<void> disconnectSafetyMonitor() => _disconnectSafetyMonitor();
  Future<void> connectSwitch(String deviceId) => _connectSwitch(deviceId);
  Future<void> disconnectSwitch() => _disconnectSwitch();
  Future<void> refreshSwitchChannels() => _refreshSwitchChannels();
  Future<void> setSwitchChannel(int channelIndex, bool on) =>
      _setSwitchChannel(channelIndex, on);
  Future<void> connectRotator(String deviceId) => _connectRotator(deviceId);
  Future<void> disconnectRotator() => _disconnectRotator();
  Future<void> connectCoverCalibrator(String deviceId) =>
      _connectCoverCalibrator(deviceId);
  Future<void> disconnectCoverCalibrator() => _disconnectCoverCalibrator();

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
  }) =>
      _connectProfile(
        cameraId: cameraId,
        mountId: mountId,
        focuserId: focuserId,
        filterWheelId: filterWheelId,
        guiderId: guiderId,
        rotatorId: rotatorId,
        domeId: domeId,
        weatherId: weatherId,
        safetyMonitorId: safetyMonitorId,
        switchId: switchId,
        coverCalibratorId: coverCalibratorId,
        onProgress: onProgress,
      );
  Future<void> connectActiveProfile() => _connectActiveProfile();
  Stream<DeviceConnectProgress> connectAllFromProfile(
          EquipmentProfileModel profile) =>
      _connectAllFromProfile(profile);
  Future<void> disconnectAll() => _disconnectAll();

  Future<void> slewMountToCoordinates(double ra, double dec) =>
      _slewMountToCoordinates(ra, dec);
  Future<void> syncMountToCoordinates(double ra, double dec) =>
      _syncMountToCoordinates(ra, dec);
  Future<void> parkMount() => _parkMount();
  Future<void> unparkMount() => _unparkMount();
  Future<void> setMountTracking(bool enabled) => _setMountTracking(enabled);
  Future<void> setMountTrackingRate(int rate) => _setMountTrackingRate(rate);
  Future<void> abortMountSlew() => _abortMountSlew();
  Future<void> slewMountToAltAz(double altitude, double azimuth) =>
      _slewMountToAltAz(altitude, azimuth);
  Future<void> findMountHome() => _findMountHome();
  Future<void> pulseGuidMount(
          {required String direction, required int durationMs}) =>
      _pulseGuidMount(direction: direction, durationMs: durationMs);

  Future<void> moveFocuserTo(int position) => _moveFocuserTo(position);
  Future<void> moveFocuserRelative(int delta) => _moveFocuserRelative(delta);
  Future<void> haltFocuser() => _haltFocuser();
  Future<void> moveRotatorTo(double angle) => _moveRotatorTo(angle);
  Future<void> moveRotatorRelative(double delta) => _moveRotatorRelative(delta);
  Future<void> haltRotator() => _haltRotator();
  Future<AutofocusResult> runAutofocus({
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    bool useSettingsDefaults = true,
  }) =>
      _runAutofocus(
        exposureTime: exposureTime,
        stepSize: stepSize,
        stepsOut: stepsOut,
        method: method,
        binning: binning,
        useSettingsDefaults: useSettingsDefaults,
      );
  Future<void> setFilterWheelPosition(int position) =>
      _setFilterWheelPosition(position);

  Future<void> startGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) =>
      _startGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
  Future<void> stopGuiding() => _stopGuiding();
  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) =>
      _dither(
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
  Future<void> startSequence() => _startSequence();
  Future<void> stopSequence() => _stopSequence();
  Future<void> pauseSequence() => _pauseSequence();
  Future<void> resumeSequence() => _resumeSequence();
  Future<void> loadSequence(String json) => _loadSequence(json);
  Future<SequencerStatus> getSequencerStatus() => _getSequencerStatus();
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
