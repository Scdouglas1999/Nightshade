import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import '../services/device_service.dart';
import '../models/backend/autofocus_result.dart';
import '../models/equipment/equipment_models.dart';
import 'profiles_provider.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Default retry configuration for device operations
const int _defaultMaxRetries = 3;
const Duration _defaultRetryDelay = Duration(seconds: 1);

/// Camera state provider
final cameraStateProvider =
    StateNotifierProvider<CameraStateNotifier, CameraState>((ref) {
  return CameraStateNotifier(ref);
});

class CameraStateNotifier extends StateNotifier<CameraState> {
  final Ref _ref;
  int _retryAttempts = 0;

  CameraStateNotifier(this._ref) : super(const CameraState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectCamera(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final mountStateProvider =
    StateNotifierProvider<MountStateNotifier, MountState>((ref) {
  return MountStateNotifier(ref);
});

class MountStateNotifier extends StateNotifier<MountState> {
  final Ref _ref;
  int _retryAttempts = 0;

  MountStateNotifier(this._ref) : super(const MountState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectMount(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final focuserStateProvider =
    StateNotifierProvider<FocuserStateNotifier, FocuserState>((ref) {
  return FocuserStateNotifier(ref);
});

class FocuserStateNotifier extends StateNotifier<FocuserState> {
  final Ref _ref;
  int _retryAttempts = 0;

  FocuserStateNotifier(this._ref) : super(const FocuserState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectFocuser(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
      await deviceService.disconnectFocuser();
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

  void setConnected({
    int? maxPosition,
    double? stepSize,
    bool? isAbsolute,
    bool? hasTemperature,
  }) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      maxPosition: maxPosition,
      stepSize: stepSize,
      isAbsolute: isAbsolute,
      hasTemperature: hasTemperature,
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
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Focus position history provider - tracks the last N focus positions for sparkline display.
/// This allows the dashboard to show a visual history of focus position changes.
final focusPositionHistoryProvider =
    StateNotifierProvider<FocusPositionHistoryNotifier, List<int>>((ref) {
  return FocusPositionHistoryNotifier(ref);
});

/// Notifier that maintains a rolling history of focus positions.
class FocusPositionHistoryNotifier extends StateNotifier<List<int>> {
  final Ref _ref;
  static const int _maxHistoryLength = 10;
  int? _lastRecordedPosition;

  FocusPositionHistoryNotifier(this._ref) : super([]) {
    // Listen to focuser state changes and record position updates
    _ref.listen<FocuserState>(focuserStateProvider, (previous, next) {
      if (next.position != null && next.position != _lastRecordedPosition) {
        _lastRecordedPosition = next.position;
        _addPosition(next.position!);
      }
    });
  }

  void _addPosition(int position) {
    final newHistory = [...state, position];
    if (newHistory.length > _maxHistoryLength) {
      state = newHistory.sublist(newHistory.length - _maxHistoryLength);
    } else {
      state = newHistory;
    }
  }

  /// Manually add a position to the history (e.g., after autofocus)
  void recordPosition(int position) {
    _lastRecordedPosition = position;
    _addPosition(position);
  }

  /// Clear the history (e.g., when switching focusers)
  void clear() {
    _lastRecordedPosition = null;
    state = [];
  }
}

/// Filter wheel state provider
final filterWheelStateProvider =
    StateNotifierProvider<FilterWheelStateNotifier, FilterWheelState>((ref) {
  return FilterWheelStateNotifier(ref);
});

class FilterWheelStateNotifier extends StateNotifier<FilterWheelState> {
  final Ref _ref;
  int _retryAttempts = 0;

  FilterWheelStateNotifier(this._ref) : super(const FilterWheelState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectFilterWheel(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();

      // After connection, sync profile filter names to the native driver
      // This ensures user-defined filter names (Ha, OIII, SII) work in sequences
      await _syncProfileFilterNamesToDriver(deviceId);
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  /// Sync filter names to the native driver on connection.
  ///
  /// Filter names are resolved in this priority order:
  /// 1. Active profile filter names (if profile exists and has filter names configured)
  /// 2. Session filter names (if set via sessionFilterNamesProvider)
  /// 3. Driver-reported names (from the backend/hardware) - no sync needed
  ///
  /// This allows users to set filter names without creating an equipment profile.
  Future<void> _syncProfileFilterNamesToDriver(String deviceId) async {
    try {
      // Priority 1: Check active profile filter names
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile != null && activeProfile.filterNames.isNotEmpty) {
        final profileFilterNames = activeProfile.filterNames;
        final driverNames = state.filterNames;
        debugPrint(
            'FilterWheelStateNotifier: Profile has ${profileFilterNames.length} names, driver has ${driverNames.length} slots');

        // Pad profile names to match the wheel's actual slot count so no slots are lost
        final List<String> syncedNames;
        if (profileFilterNames.length < driverNames.length) {
          syncedNames = [
            ...profileFilterNames,
            ...driverNames.sublist(profileFilterNames.length),
          ];
          debugPrint(
              'FilterWheelStateNotifier: Padded profile names to ${syncedNames.length}: $syncedNames');
        } else {
          syncedNames = profileFilterNames.length > driverNames.length
              ? profileFilterNames.sublist(0, driverNames.length)
              : profileFilterNames;
        }

        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: deviceId,
          names: syncedNames,
        );

        state = state.copyWith(filterNames: syncedNames);
        debugPrint(
            'FilterWheelStateNotifier: Profile filter names synced successfully');
        return;
      }

      // Priority 2: Check session filter names
      final sessionFilterNames = _ref.read(sessionFilterNamesProvider);
      if (sessionFilterNames != null && sessionFilterNames.isNotEmpty) {
        final driverNames = state.filterNames;
        debugPrint(
            'FilterWheelStateNotifier: Session has ${sessionFilterNames.length} names, driver has ${driverNames.length} slots');

        // Pad session names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (sessionFilterNames.length < driverNames.length) {
          syncedNames = [
            ...sessionFilterNames,
            ...driverNames.sublist(sessionFilterNames.length),
          ];
        } else {
          syncedNames = sessionFilterNames.length > driverNames.length
              ? sessionFilterNames.sublist(0, driverNames.length)
              : sessionFilterNames;
        }

        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: deviceId,
          names: syncedNames,
        );

        state = state.copyWith(filterNames: syncedNames);
        debugPrint(
            'FilterWheelStateNotifier: Session filter names synced successfully');
        return;
      }

      // Priority 3: Use driver-reported names (no sync needed, they're already there)
      debugPrint(
          'FilterWheelStateNotifier: No profile or session filter names - using driver-reported names');
    } catch (e) {
      // Don't fail connection if filter name sync fails - log and continue
      debugPrint('FilterWheelStateNotifier: Failed to sync filter names: $e');
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
      await deviceService.disconnectFilterWheel();
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

  void setConnected({List<String>? filterNames}) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      filterNames: filterNames,
      clearError: true,
    );
  }

  void setDeviceName(String deviceName) {
    state = state.copyWith(deviceName: deviceName);
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
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }

  /// Set session-level filter names (without requiring an equipment profile).
  ///
  /// This allows users to name their filters for the current session without
  /// creating or modifying an equipment profile. The names are stored in
  /// [sessionFilterNamesProvider] and will be used when:
  /// - No equipment profile is active, OR
  /// - The active equipment profile has no filter names configured
  ///
  /// If [syncToDriver] is true and a filter wheel is connected, the names
  /// will be immediately synced to the native driver.
  Future<void> setSessionFilterNames(
    List<String> names, {
    bool syncToDriver = true,
  }) async {
    // Store in the session provider
    _ref.read(sessionFilterNamesProvider.notifier).state = names;

    // Update local state
    state = state.copyWith(filterNames: names);

    // Optionally sync to driver if connected
    if (syncToDriver &&
        state.connectionState == DeviceConnectionState.connected &&
        state.deviceId != null) {
      try {
        debugPrint(
            'FilterWheelStateNotifier: Syncing session filter names to driver: $names');
        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: state.deviceId!,
          names: names,
        );
        debugPrint(
            'FilterWheelStateNotifier: Session filter names synced to driver');
      } catch (e) {
        debugPrint(
            'FilterWheelStateNotifier: Failed to sync session filter names to driver: $e');
        // Don't throw - the names are still stored locally
      }
    }
  }

  /// Clear session-level filter names.
  ///
  /// This will cause the filter wheel to fall back to profile names (if available)
  /// or driver-reported names on the next connection.
  void clearSessionFilterNames() {
    _ref.read(sessionFilterNamesProvider.notifier).state = null;
  }
}

/// Guider state provider
final guiderStateProvider =
    StateNotifierProvider<GuiderStateNotifier, GuiderState>((ref) {
  return GuiderStateNotifier(ref);
});

class GuiderStateNotifier extends StateNotifier<GuiderState> {
  final Ref _ref;
  int _retryAttempts = 0;

  GuiderStateNotifier(this._ref) : super(const GuiderState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectGuider(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectGuider();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
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
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}

/// Rotator state provider
final rotatorStateProvider =
    StateNotifierProvider<RotatorStateNotifier, RotatorState>((ref) {
  return RotatorStateNotifier(ref);
});

class RotatorStateNotifier extends StateNotifier<RotatorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  RotatorStateNotifier(this._ref) : super(const RotatorState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectRotator(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final domeStateProvider =
    StateNotifierProvider<DomeStateNotifier, DomeState>((ref) {
  return DomeStateNotifier(ref);
});

class DomeStateNotifier extends StateNotifier<DomeState> {
  final Ref _ref;
  int _retryAttempts = 0;

  DomeStateNotifier(this._ref) : super(const DomeState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectDome(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final weatherStateProvider =
    StateNotifierProvider<WeatherStateNotifier, WeatherState>((ref) {
  return WeatherStateNotifier(ref);
});

class WeatherStateNotifier extends StateNotifier<WeatherState> {
  final Ref _ref;
  int _retryAttempts = 0;

  WeatherStateNotifier(this._ref) : super(const WeatherState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectWeather(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final safetyMonitorStateProvider =
    StateNotifierProvider<SafetyMonitorStateNotifier, SafetyMonitorState>(
        (ref) {
  return SafetyMonitorStateNotifier(ref);
});

class SafetyMonitorStateNotifier extends StateNotifier<SafetyMonitorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  SafetyMonitorStateNotifier(this._ref) : super(const SafetyMonitorState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectSafetyMonitor(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final coverCalibratorStateProvider =
    StateNotifierProvider<CoverCalibratorStateNotifier, CoverCalibratorState>(
        (ref) {
  return CoverCalibratorStateNotifier(ref);
});

class CoverCalibratorStateNotifier extends StateNotifier<CoverCalibratorState> {
  final Ref _ref;
  int _retryAttempts = 0;

  CoverCalibratorStateNotifier(this._ref) : super(const CoverCalibratorState());

  Future<void> connect(String deviceId,
      {int maxRetries = _defaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId, deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.connectCoverCalibrator(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
      setConnected();
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(_defaultRetryDelay * _retryAttempts);
        if (!mounted) return;
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
final autofocusResultProvider = StateProvider<AutofocusResult?>((ref) => null);

// =============================================================================
// Session Filter Names Provider
// =============================================================================

/// Session-only filter names (no profile required).
///
/// These are used when no equipment profile is active but user wants to name filters.
/// When a filter wheel connects, filter names are resolved in this priority order:
/// 1. Active profile filter names (if profile exists and has filter names configured)
/// 2. Session filter names (if set via this provider)
/// 3. Driver-reported names (from the backend/hardware)
///
/// This allows users to set filter names without creating an equipment profile,
/// which is useful for quick sessions or testing.
final sessionFilterNamesProvider = StateProvider<List<String>?>((ref) => null);
