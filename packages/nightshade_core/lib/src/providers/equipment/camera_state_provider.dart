import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import 'equipment_retry_defaults.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Camera state provider
final cameraStateProvider =
    StateNotifierProvider<CameraStateNotifier, CameraStateSnapshot>((ref) {
      return CameraStateNotifier(ref);
    });

class CameraStateNotifier extends StateNotifier<CameraStateSnapshot> {
  final Ref _ref;
  int _retryAttempts = 0;

  CameraStateNotifier(this._ref) : super(const CameraStateSnapshot());

  Future<void> connect(
    String deviceId, {
    int maxRetries = kDefaultMaxRetries,
  }) async {
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
        await Future.delayed(kDefaultRetryDelay * _retryAttempts);
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
    if (state.deviceId == null && state.deviceName == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectCamera();
    } catch (e) {
      _safeLogDisconnectError('camera', e);
    } finally {
      setDisconnected();
    }
  }

  void _safeLogDisconnectError(String deviceType, Object error) {
    // Disconnect errors are logged but must not leave the UI showing
    // "connected with error" — setDisconnected runs in finally (DV-P0-7).
    try {
      // ignore: avoid_print
      print('CameraStateNotifier: disconnect $deviceType failed: $error');
    } on Object {
      // No-op — logging must not mask disconnect cleanup.
    }
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    // DEV-P3-4: preserve `lastError` across the Connecting transition so
    // the equipment card can keep showing the most recent driver error
    // while the reconnect is in flight. It is cleared only when the
    // device actually reaches Connected (see [setConnected]), or when
    // the user explicitly calls [clearError].
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    // Preserve the user's auto-reconnect preference across disconnects.
    // Resetting to a fresh CameraStateSnapshot would flip it back to the
    // `true` default, which would silently undo the user's choice the
    // moment the device disconnected.
    final preservedAutoReconnect = state.autoReconnectEnabled;
    state = CameraStateSnapshot(autoReconnectEnabled: preservedAutoReconnect);
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

  /// Update warming state (gradual warm-up in progress)
  void setWarming(bool isWarming) {
    state = state.copyWith(isWarming: isWarming);
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
