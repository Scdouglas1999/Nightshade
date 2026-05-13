import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import 'equipment_retry_defaults.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

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
      {int maxRetries = kDefaultMaxRetries}) async {
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
