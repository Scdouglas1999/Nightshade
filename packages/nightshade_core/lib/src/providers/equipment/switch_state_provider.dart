import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import 'equipment_retry_defaults.dart';

// Switch device state provider, mirroring the safety-monitor
// shape (Audit C1). The notifier owns the connect-with-retry loop and the
// `autoReconnectEnabled` flag that `DeviceService._getAutoReconnectFor`
// consults when a Disconnected event arrives.
//
// Per-channel state mutation is driven by [DeviceService.setSwitchChannel],
// which calls the Rust bridge (`api_switch_set_state`) and then calls
// [setChannelState] here to reconcile the cached snapshot. The
// [setChannels] helper is used by [DeviceService.refreshSwitchChannels]
// to populate the channel snapshot on connect and on manual refresh.
//
// Note: All async callbacks and stream listeners check `mounted` before
// updating state to prevent updates after disposal.

/// Switch device state provider.
final switchStateProvider =
    StateNotifierProvider<SwitchStateNotifier, SwitchState>((ref) {
      return SwitchStateNotifier(ref);
    });

class SwitchStateNotifier extends StateNotifier<SwitchState> {
  final Ref _ref;
  int _retryAttempts = 0;

  SwitchStateNotifier(this._ref) : super(const SwitchState());

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
      await deviceService.connectSwitch(deviceId);
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
      await deviceService.disconnectSwitch();
    } catch (_) {
      // DeviceService logs; notifier always clears connection state.
    } finally {
      setDisconnected();
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
    final preservedAutoReconnect = state.autoReconnectEnabled;
    state = SwitchState(autoReconnectEnabled: preservedAutoReconnect);
  }

  /// Enable or disable auto-reconnection for the switch device.
  void setAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnectEnabled: enabled);
  }

  /// Update the cached channel snapshot. The Rust bridge does not push
  /// these on a stream yet; DeviceService polls explicitly on connect
  /// and after any `setSwitchChannel` write.
  ///
  /// When [refreshedAt] is provided it is recorded as the last-poll
  /// timestamp the UI uses for the "Refresh" affordance; pass null when
  /// only updating the count without re-polling labels/states.
  void setChannels({
    required int count,
    List<String>? names,
    List<bool>? states,
    DateTime? refreshedAt,
  }) {
    state = state.copyWith(
      channelCount: count,
      channelNames: names ?? state.channelNames,
      channelStates: states ?? state.channelStates,
      lastChannelRefresh: refreshedAt,
    );
  }

  /// Update a single channel's boolean state after a successful bridge
  /// write. The index is bounds-checked against the cached
  /// [SwitchState.channelStates] list; out-of-range indices are
  /// silently ignored because the UI cannot have rendered a row for a
  /// channel that does not exist in the snapshot. This is the only
  /// mutation path the UI is allowed to use — direct optimistic writes
  /// would lie to the user about hardware state.
  void setChannelState(int index, bool on) {
    final current = state.channelStates;
    if (index < 0 || index >= current.length) return;
    final next = List<bool>.from(current);
    next[index] = on;
    state = state.copyWith(channelStates: next);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }
}
