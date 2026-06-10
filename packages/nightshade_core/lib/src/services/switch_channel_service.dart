import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;

import '../backend/ffi_backend.dart';
import '../backend/nightshade_backend.dart';
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../providers/equipment_provider.dart';
import 'device_exceptions.dart';
import 'error_service.dart';
import 'logging_service.dart';

/// Type alias for the switch-bridge `apiSwitchGetMax` shim used by
/// [SwitchChannelService.refreshChannels]. Tests override the static
/// hook below to avoid loading the native bridge.
typedef SwitchBridgeGetMaxFn = Future<int> Function(String deviceId);

/// Type alias for the switch-bridge name fetch.
typedef SwitchBridgeGetNameFn =
    Future<String> Function(String deviceId, int switchId);

/// Type alias for the switch-bridge boolean read.
typedef SwitchBridgeGetStateFn =
    Future<bool> Function(String deviceId, int switchId);

/// Type alias for the switch-bridge boolean write.
typedef SwitchBridgeSetStateFn =
    Future<void> Function(String deviceId, int switchId, bool state);

/// Owns the per-channel switch-device refresh + write paths that used to
/// live inline on `DeviceService`. Extracted as part of the A-10 god-
/// class split so the switch-bridge testable seam (4 static function
/// pointers + the backend-bypass flag) has a dedicated home instead of
/// being scattered across the 3,800-line facade.
///
/// `DeviceService` instantiates one of these per-instance and keeps thin
/// public delegators (`refreshSwitchChannels` / `setSwitchChannel`) so
/// the existing call sites (UI, generated MockDeviceService used by
/// `centering_service_test.mocks.dart`, sequencer triggers) keep working
/// without churn. The DeviceService delegator owns its `_trackInFlight`
/// quiesce accounting; this service does not touch that state.
///
/// ## Testable seam
///
/// The FFI branch is normally guarded by `_backend is FfiBackend`, which
/// `MockBackend` cannot satisfy. Tests set
/// [switchBridgeBypassBackendCheck] = true and override the four
/// function-pointer hooks so the bridge calls are intercepted without
/// changing the backend type-check used in production.
///
/// MUST call [resetHooks] in `tearDown` to avoid leaking state between
/// tests.
class SwitchChannelService {
  SwitchChannelService({required Ref ref, required NightshadeBackend backend})
    : _ref = ref,
      _backend = backend;

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
  static SwitchBridgeGetMaxFn switchBridgeGetMax = (deviceId) =>
      bridge_api.apiSwitchGetMax(deviceId: deviceId);
  @visibleForTesting
  static SwitchBridgeGetNameFn switchBridgeGetName = (deviceId, switchId) =>
      bridge_api.apiSwitchGetName(deviceId: deviceId, switchId: switchId);
  @visibleForTesting
  static SwitchBridgeGetStateFn switchBridgeGetState = (deviceId, switchId) =>
      bridge_api.apiSwitchGetState(deviceId: deviceId, switchId: switchId);
  @visibleForTesting
  static SwitchBridgeSetStateFn switchBridgeSetState =
      (deviceId, switchId, state) => bridge_api.apiSwitchSetState(
        deviceId: deviceId,
        switchId: switchId,
        state: state,
      );

  /// When true, [refreshChannels] and [setChannel] will call the bridge
  /// hooks above unconditionally instead of gating on
  /// `_backend is FfiBackend`. Tests set this to true so MockBackend
  /// can stand in for FfiBackend without satisfying its type.
  /// MUST remain false in production builds.
  @visibleForTesting
  static bool switchBridgeBypassBackendCheck = false;

  /// Reset switch bridge hooks to their production implementations.
  /// Call from `tearDown` in any test that overrode them.
  @visibleForTesting
  static void resetHooks() {
    switchBridgeBypassBackendCheck = false;
    switchBridgeGetMax = (deviceId) =>
        bridge_api.apiSwitchGetMax(deviceId: deviceId);
    switchBridgeGetName = (deviceId, switchId) =>
        bridge_api.apiSwitchGetName(deviceId: deviceId, switchId: switchId);
    switchBridgeGetState = (deviceId, switchId) =>
        bridge_api.apiSwitchGetState(deviceId: deviceId, switchId: switchId);
    switchBridgeSetState = (deviceId, switchId, state) =>
        bridge_api.apiSwitchSetState(
          deviceId: deviceId,
          switchId: switchId,
          state: state,
        );
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
  /// warning) when running against a non-Ffi backend, because there is
  /// no remote REST endpoint for per-channel switch reads yet.
  ///
  /// Errors at the top-level (e.g. `apiSwitchGetMax` throws) are
  /// surfaced through [ErrorService] so the user sees a toast — silent
  /// fallbacks would hide a real driver fault for the whole session.
  Future<void> refreshChannels() async {
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
          source: 'SwitchChannelService',
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
              source: 'SwitchChannelService',
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
              source: 'SwitchChannelService',
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
          source: 'SwitchChannelService',
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
            source: 'SwitchChannelService',
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
  ///
  /// Note: this method does NOT participate in `DeviceService._trackInFlight`
  /// accounting; the public `DeviceService.setSwitchChannel` delegator wraps
  /// it in the facade's quiesce-tracking helper.
  Future<void> setChannel(int channelIndex, bool on) async {
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
          source: 'SwitchChannelService',
        ),
        'switch-set-channel',
      );
      try {
        final errSvc = _ref.read(errorServiceProvider);
        errSvc.logDeviceError(
          operation: 'switch_set_state',
          message:
              'Failed to set switch channel $channelIndex to '
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
            source: 'SwitchChannelService',
          ),
          'switch-set-channel-errsvc',
        );
      }
      rethrow;
    }
  }

  /// Mirror of `DeviceService._safeLog` — emits a diagnostic line through
  /// the logging service, but never lets a logger-emission failure mask
  /// a higher-priority device fault. We deliberately catch every kind of
  /// error from the logger lookup (e.g. provider mid-disposal during
  /// shutdown) and demote to a stderr line — fail-closed for the calling
  /// device operation, soft for the diagnostics emission itself.
  void _safeLog(void Function(LoggingService logger) emit, String contextTag) {
    try {
      final logger = _ref.read(loggingServiceProvider);
      emit(logger);
    } on Object catch (loggerErr) {
      // ignore: avoid_print
      print(
        'SwitchChannelService[$contextTag]: logger emission failed: $loggerErr',
      );
    }
  }
}
