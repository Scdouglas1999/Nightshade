import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import '../backend_provider.dart';
import 'equipment_retry_defaults.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Mount state provider
final mountStateProvider =
    StateNotifierProvider<MountStateNotifier, MountState>((ref) {
  return MountStateNotifier(ref);
});

class MountStateNotifier extends StateNotifier<MountState> {
  final Ref _ref;
  int _retryAttempts = 0;
  Timer? _positionPollTimer;
  bool _isPolling = false;

  /// Normal polling interval (tracking/idle)
  static const _normalPollInterval = Duration(seconds: 2);

  /// Fast polling interval (while slewing)
  static const _slewingPollInterval = Duration(milliseconds: 500);

  MountStateNotifier(this._ref) : super(const MountState());

  @override
  void dispose() {
    _stopPositionPolling();
    super.dispose();
  }

  Future<void> connect(String deviceId,
      {int maxRetries = kDefaultMaxRetries}) async {
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
    _stopPositionPolling();
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
    _stopPositionPolling();
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
    _startPositionPolling();
  }

  void setDisconnected() {
    _stopPositionPolling();
    state = const MountState();
  }

  void updatePosition(double ra, double dec, double alt, double az) {
    state = state.copyWith(ra: ra, dec: dec, altitude: alt, azimuth: az);
  }

  void setTracking(bool tracking) {
    state = state.copyWith(isTracking: tracking);
  }

  void setSlewing(bool slewing) {
    final wasSlewing = state.isSlewing;
    state = state.copyWith(isSlewing: slewing);
    // Adjust poll rate when slewing state changes
    if (wasSlewing != slewing &&
        state.connectionState == DeviceConnectionState.connected) {
      _restartPollingWithCurrentRate();
    }
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

  // ---------------------------------------------------------------------------
  // Position polling
  // ---------------------------------------------------------------------------

  void _startPositionPolling() {
    _stopPositionPolling();
    final interval =
        state.isSlewing ? _slewingPollInterval : _normalPollInterval;
    developer.log(
        '[Mount] Starting position polling (interval: ${interval.inMilliseconds}ms)',
        name: 'MountStateNotifier',
        level: 800);
    _positionPollTimer = Timer.periodic(interval, (_) => _pollPosition());
  }

  void _stopPositionPolling() {
    if (_positionPollTimer != null) {
      _positionPollTimer!.cancel();
      _positionPollTimer = null;
      developer.log('[Mount] Stopped position polling',
          name: 'MountStateNotifier', level: 800);
    }
  }

  void _restartPollingWithCurrentRate() {
    if (_positionPollTimer == null) return; // Not currently polling
    _startPositionPolling();
  }

  Future<void> _pollPosition() async {
    if (_isPolling) return; // Skip if previous poll is still in-flight
    if (!mounted) return;
    if (state.connectionState != DeviceConnectionState.connected) return;

    final deviceId = state.deviceId;
    if (deviceId == null) return;

    _isPolling = true;
    try {
      final backend = _ref.read(backendProvider);
      final status = await backend.getMountStatus(deviceId);
      if (!mounted) return;

      updatePosition(
        status.rightAscension,
        status.declination,
        status.altitude,
        status.azimuth,
      );

      // Also sync tracking/slewing/parked state from hardware
      final wasSlewing = state.isSlewing;
      state = state.copyWith(
        isTracking: status.tracking,
        isSlewing: status.slewing,
        isParked: status.parked,
      );

      // If slewing state changed, adjust poll rate
      if (wasSlewing != status.slewing) {
        _restartPollingWithCurrentRate();
      }
    } catch (e) {
      // Don't spam errors for transient failures during polling.
      // A persistent failure will eventually be caught by the heartbeat
      // monitor which handles reconnection.
      developer.log('[Mount] Position poll failed: $e',
          name: 'MountStateNotifier', level: 900, error: e);
    } finally {
      _isPolling = false;
    }
  }
}
