import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import '../services/device_service.dart';
import '../models/equipment/equipment_models.dart';
import 'profiles_provider.dart';

/// Default retry configuration for device operations
const int _defaultMaxRetries = 3;
const Duration _defaultRetryDelay = Duration(seconds: 1);

/// Camera state provider
final cameraStateProvider = StateNotifierProvider<CameraStateNotifier, CameraState>((ref) {
  return CameraStateNotifier(ref);
});

class CameraStateNotifier extends StateNotifier<CameraState> {
  final Ref _ref;
  int _retryAttempts = 0;

  CameraStateNotifier(this._ref) : super(const CameraState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectCamera(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  /// Retry the last failed connection
  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  /// Clear the current error state
  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectCamera();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const CameraState();
  }

  void updateTemperature(double temp, double power) {
    state = state.copyWith(
      temperature: temp,
      coolerPower: power,
      lastSuccessfulCommunication: DateTime.now(),
    );
  }

  /// Update target temperature setting (persists across navigation)
  void setTargetTemp(double temp) {
    state = state.copyWith(targetTemp: temp);
  }

  /// Update cooling state (on/off)
  void setCooling(bool isCooling) {
    state = state.copyWith(isCooling: isCooling);
  }

  void setExposing(bool isExposing, {double? progress}) {
    state = state.copyWith(
      isExposing: isExposing,
      exposureProgress: progress,
      lastSuccessfulCommunication: DateTime.now(),
    );
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }

  /// Update last successful communication timestamp
  void updateCommunication() {
    state = state.copyWith(lastSuccessfulCommunication: DateTime.now());
  }

  /// Enable or disable auto-reconnection
  void setAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnectEnabled: enabled);
  }
}

/// Mount state provider
final mountStateProvider = StateNotifierProvider<MountStateNotifier, MountState>((ref) {
  return MountStateNotifier(ref);
});

class MountStateNotifier extends StateNotifier<MountState> {
  final Ref _ref;
  int _retryAttempts = 0;

  MountStateNotifier(this._ref) : super(const MountState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectMount(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceName != null) {
      await connect(state.deviceName!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectMount();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const MountState();
  }

  void updatePosition(double ra, double dec, double alt, double az) {
    state = state.copyWith(ra: ra, dec: dec, altitude: alt, azimuth: az);
  }

  void setTracking(bool tracking) {
    state = state.copyWith(isTracking: tracking);
  }

  void setSlewing(bool slewing) {
    state = state.copyWith(isSlewing: slewing);
  }

  void setParked(bool parked) {
    state = state.copyWith(isParked: parked);
  }

  void setTrackingRate(TrackingRate rate) {
    state = state.copyWith(trackingRate: rate);
  }

  void setCanSetTrackingRate(bool canSet) {
    state = state.copyWith(canSetTrackingRate: canSet);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Focuser state provider
final focuserStateProvider = StateNotifierProvider<FocuserStateNotifier, FocuserState>((ref) {
  return FocuserStateNotifier(ref);
});

class FocuserStateNotifier extends StateNotifier<FocuserState> {
  final Ref _ref;
  int _retryAttempts = 0;

  FocuserStateNotifier(this._ref) : super(const FocuserState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectFocuser(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceName != null) {
      await connect(state.deviceName!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectFocuser();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceName),
      );
    }
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
      clearError: true,
    );
  }

  void setConnected({int? maxPosition}) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      maxPosition: maxPosition,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const FocuserState();
  }

  void updatePosition(int position) {
    state = state.copyWith(position: position);
  }

  void updateTemperature(double temp) {
    state = state.copyWith(temperature: temp);
  }

  void setMoving(bool moving) {
    state = state.copyWith(isMoving: moving);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceName),
    );
  }
}

/// Filter wheel state provider
final filterWheelStateProvider = StateNotifierProvider<FilterWheelStateNotifier, FilterWheelState>((ref) {
  return FilterWheelStateNotifier(ref);
});

class FilterWheelStateNotifier extends StateNotifier<FilterWheelState> {
  final Ref _ref;
  int _retryAttempts = 0;

  FilterWheelStateNotifier(this._ref) : super(const FilterWheelState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectFilterWheel(deviceId);
      _retryAttempts = 0;
      setConnected();

      // After connection, sync profile filter names to the native driver
      // This ensures user-defined filter names (Ha, OIII, SII) work in sequences
      await _syncProfileFilterNamesToDriver(deviceId);
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  /// Sync filter names from the active equipment profile to the native driver.
  /// This is called after filter wheel connection to ensure user-defined names work.
  Future<void> _syncProfileFilterNamesToDriver(String deviceId) async {
    try {
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile == null) {
        debugPrint('FilterWheelStateNotifier: No active profile - skipping filter name sync');
        return;
      }

      final profileFilterNames = activeProfile.filterNames;
      if (profileFilterNames.isEmpty) {
        debugPrint('FilterWheelStateNotifier: Profile has no filter names - skipping sync');
        return;
      }

      debugPrint('FilterWheelStateNotifier: Syncing ${profileFilterNames.length} filter names to driver: $profileFilterNames');

      // Push filter names to the native driver
      await bridge_api.apiFilterwheelSetFilterNames(
        deviceId: deviceId,
        names: profileFilterNames,
      );

      // Update our local state with the synced filter names
      state = state.copyWith(filterNames: profileFilterNames);

      debugPrint('FilterWheelStateNotifier: Filter names synced successfully');
    } catch (e) {
      // Don't fail connection if filter name sync fails - log and continue
      debugPrint('FilterWheelStateNotifier: Failed to sync filter names: $e');
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceName != null) {
      await connect(state.deviceName!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectFilterWheel();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceName),
      );
    }
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
      clearError: true,
    );
  }

  void setConnected({List<String>? filterNames}) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      filterNames: filterNames,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const FilterWheelState();
  }

  void updatePosition(int position) {
    state = state.copyWith(currentPosition: position);
  }

  void setMoving(bool moving) {
    state = state.copyWith(isMoving: moving);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceName),
    );
  }
}

/// Guider state provider
final guiderStateProvider = StateNotifierProvider<GuiderStateNotifier, GuiderState>((ref) {
  return GuiderStateNotifier(ref);
});

class GuiderStateNotifier extends StateNotifier<GuiderState> {
  final Ref _ref;
  int _retryAttempts = 0;

  GuiderStateNotifier(this._ref) : super(const GuiderState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectGuider(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceName != null) {
      await connect(state.deviceName!);
    }
  }

  Future<void> disconnect() async {
    if (state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectGuider();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceName),
      );
    }
  }

  void clearError() {
    state = state.clearError();
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const GuiderState();
  }

  void setGuiding(bool guiding) {
    state = state.copyWith(isGuiding: guiding);
  }

  void updateRms(double ra, double dec, double total) {
    state = state.copyWith(rmsRa: ra, rmsDec: dec, rmsTotal: total);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceName),
    );
  }
}

/// Rotator state provider
final rotatorStateProvider = StateNotifierProvider<RotatorStateNotifier, RotatorState>((ref) {
  return RotatorStateNotifier(ref);
});

class RotatorStateNotifier extends StateNotifier<RotatorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  RotatorStateNotifier(this._ref) : super(const RotatorState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectRotator(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectRotator();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const RotatorState();
  }

  void updatePosition(double position, {double? mechanicalPosition}) {
    state = state.copyWith(
      position: position,
      mechanicalPosition: mechanicalPosition,
    );
  }

  void setMoving(bool moving) {
    state = state.copyWith(isMoving: moving);
  }

  void setReversed(bool reversed) {
    state = state.copyWith(isReversed: reversed);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Dome state provider
final domeStateProvider = StateNotifierProvider<DomeStateNotifier, DomeState>((ref) {
  return DomeStateNotifier(ref);
});

class DomeStateNotifier extends StateNotifier<DomeState> {
  final Ref _ref;
  int _retryAttempts = 0;

  DomeStateNotifier(this._ref) : super(const DomeState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectDome(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectDome();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const DomeState();
  }

  void updateAzimuth(double azimuth) {
    state = state.copyWith(azimuth: azimuth);
  }

  void updateShutterStatus(ShutterStatus status) {
    state = state.copyWith(shutterStatus: status);
  }

  void setSlewing(bool slewing) {
    state = state.copyWith(isSlewing: slewing);
  }

  void setParked(bool parked) {
    state = state.copyWith(isParked: parked);
  }

  void setSlaved(bool slaved) {
    state = state.copyWith(isSlaved: slaved);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Weather state provider
final weatherStateProvider = StateNotifierProvider<WeatherStateNotifier, WeatherState>((ref) {
  return WeatherStateNotifier(ref);
});

class WeatherStateNotifier extends StateNotifier<WeatherState> {
  final Ref _ref;
  int _retryAttempts = 0;

  WeatherStateNotifier(this._ref) : super(const WeatherState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectWeather(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectWeather();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const WeatherState();
  }

  void updateConditions({
    double? temperature,
    double? humidity,
    double? pressure,
    double? cloudCover,
    double? dewPoint,
    double? windSpeed,
    double? windDirection,
    double? skyQuality,
    double? skyTemperature,
    double? rainRate,
  }) {
    state = state.copyWith(
      temperature: temperature,
      humidity: humidity,
      pressure: pressure,
      cloudCover: cloudCover,
      dewPoint: dewPoint,
      windSpeed: windSpeed,
      windDirection: windDirection,
      skyQuality: skyQuality,
      skyTemperature: skyTemperature,
      rainRate: rainRate,
      lastUpdated: DateTime.now(),
    );
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Safety monitor state provider
final safetyMonitorStateProvider = StateNotifierProvider<SafetyMonitorStateNotifier, SafetyMonitorState>((ref) {
  return SafetyMonitorStateNotifier(ref);
});

class SafetyMonitorStateNotifier extends StateNotifier<SafetyMonitorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  SafetyMonitorStateNotifier(this._ref) : super(const SafetyMonitorState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectSafetyMonitor(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectSafetyMonitor();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const SafetyMonitorState();
  }

  void updateSafetyStatus(bool isSafe) {
    state = state.copyWith(
      isSafe: isSafe,
      lastChecked: DateTime.now(),
    );
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

// =============================================================================
// Cover Calibrator (Flat Panel) Provider
// =============================================================================

/// Cover calibrator state provider
final coverCalibratorStateProvider = StateNotifierProvider<CoverCalibratorStateNotifier, CoverCalibratorState>((ref) {
  return CoverCalibratorStateNotifier(ref);
});

class CoverCalibratorStateNotifier extends StateNotifier<CoverCalibratorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  CoverCalibratorStateNotifier(this._ref) : super(const CoverCalibratorState());

  Future<void> connect(String deviceId, {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectCoverCalibrator(deviceId);
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectCoverCalibrator();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
      clearError: true,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    state = const CoverCalibratorState();
  }

  void updateCoverStatus(CoverStatus status) {
    state = state.copyWith(coverStatus: status);
  }

  void updateCalibratorStatus(CalibratorStatus status) {
    state = state.copyWith(calibratorStatus: status);
  }

  void updateBrightness(int brightness) {
    state = state.copyWith(brightness: brightness);
  }

  void updateMaxBrightness(int maxBrightness) {
    state = state.copyWith(maxBrightness: maxBrightness);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

// =============================================================================
// Autofocus Result Provider
// =============================================================================

/// Provider for the last autofocus result
/// This stores the most recent autofocus run result for display in the UI
final autofocusResultProvider = StateProvider<bridge_api.AutofocusResultApi?>((ref) => null);
