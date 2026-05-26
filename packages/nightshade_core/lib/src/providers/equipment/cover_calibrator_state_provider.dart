import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import 'equipment_retry_defaults.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

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
      {int maxRetries = kDefaultMaxRetries}) async {
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
    } catch (_) {
      // DeviceService logs; notifier always clears connection state (DV-P0-7).
    } finally {
      setDisconnected();
    }
  }

  void setConnecting(String deviceId, String deviceName) {
    // DEV-P3-4: preserve `lastError` across Connecting; see camera
    // provider for the full rationale.
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  void setConnected() {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      clearError: true,
    );
  }

  void setDisconnected() {
    final preservedAutoReconnect = state.autoReconnectEnabled;
    state = CoverCalibratorState(autoReconnectEnabled: preservedAutoReconnect);
  }

  /// Enable or disable auto-reconnection for the cover calibrator.
  void setAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnectEnabled: enabled);
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
