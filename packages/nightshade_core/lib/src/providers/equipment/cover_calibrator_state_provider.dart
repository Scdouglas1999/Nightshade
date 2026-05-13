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
