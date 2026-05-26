import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/nightshade_backend.dart';
import '../backend/ffi_backend.dart';
import '../backend/disconnected_backend.dart';
import '../backend/network_backend.dart';
import 'database_provider.dart';
import 'equipment/equipment_state_reset.dart';
import '../services/device_service_lifecycle.dart';

/// Notifier for the backend implementation
class BackendNotifier extends StateNotifier<NightshadeBackend> {
  final Ref _ref;

  BackendNotifier(this._ref) : super(DisconnectedBackend());

  /// Connect to a remote server and wait for the WebSocket event stream.
  ///
  /// P2-2: when `collaborationViewerId` and `collaborationDisplayName` are
  /// supplied, the backend will emit a `collaboration.join` frame after
  /// the WS upgrade completes so the server can populate its viewer slot
  /// list. The server overrides the viewerId with the authenticated
  /// principal's digest (P2-15) when auth is enabled; supplying it from
  /// the client is still useful for (a) unauthenticated deployments and
  /// (b) keeping the wire shape consistent.
  Future<void> connect(
    String host,
    int port, {
    String? authToken,
    String? collaborationViewerId,
    String? collaborationDeviceName,
    String? collaborationDisplayName,
  }) async {
    final backend = NetworkBackend(
      serverHost: host,
      serverPort: port,
      webSocketPort: port,
      authToken: authToken,
      autoConnectWebSocket: false,
    );
    if (collaborationViewerId != null && collaborationDisplayName != null) {
      backend.setCollaborationIdentity(
        viewerId: collaborationViewerId,
        deviceName: collaborationDeviceName ?? collaborationDisplayName,
        displayName: collaborationDisplayName,
      );
    }
    await _swapBackend(backend);
    try {
      await backend.connect();
      developer.log(
        '[BackendNotifier] NetworkBackend connected to $host:$port '
        '(auth=${authToken != null && authToken.isNotEmpty})',
        name: 'BackendNotifier',
        level: 800,
      );
    } catch (e, stackTrace) {
      developer.log(
        '[BackendNotifier] NetworkBackend connect failed for $host:$port: $e',
        name: 'BackendNotifier',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Disconnect from server and quiesce in-flight device operations first.
  Future<void> disconnect() async {
    await _swapBackend(DisconnectedBackend());
  }

  /// Use local FFI backend (for Desktop/Headless)
  Future<void> useLocalBackend() async {
    final database = _ref.read(databaseProvider);
    await _swapBackend(FfiBackend(database: database));
  }

  /// Quiesce the outgoing [DeviceService], reset equipment notifiers, then
  /// dispose the old backend. Fail-closed: quiesce timeout propagates so
  /// callers know the swap did not complete cleanly (DV-P0-2).
  Future<void> _swapBackend(NightshadeBackend newBackend) async {
    final oldBackend = state;
    if (identical(oldBackend, newBackend)) {
      return;
    }

    try {
      await DeviceServiceLifecycle.prepareForBackendSwap();
    } on Object catch (e, stackTrace) {
      developer.log(
        '[BackendNotifier] DeviceService quiesce failed during backend swap: $e',
        name: 'BackendNotifier',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    resetAllEquipmentStateNotifiers(_ref);

    oldBackend.dispose();
    state = newBackend;
  }

  @override
  void dispose() {
    // Dispose current backend when provider is disposed
    state.dispose();
    super.dispose();
  }
}

/// Provider for the backend implementation
///
/// This is now a dynamic provider that can switch between:
/// - DisconnectedBackend (default for mobile)
/// - NetworkBackend (when mobile connects to server)
/// - FfiBackend (default for desktop/headless)
final backendProvider =
    StateNotifierProvider<BackendNotifier, NightshadeBackend>((ref) {
  return BackendNotifier(ref);
});

/// Provider to check if we're in remote (network) mode
/// When true, file paths refer to the server filesystem, not local
final isRemoteModeProvider = Provider<bool>((ref) {
  final backend = ref.watch(backendProvider);
  return backend is NetworkBackend;
});

/// P2-13: surface the WebSocket-level connection state of the current
/// [NetworkBackend] as a Riverpod stream. Distinct from OS-level WiFi
/// state (NetworkService) so the chip in the mobile UI can render the
/// two signals separately and stop conflating "WiFi up" with "WebSocket
/// alive".
///
/// Emits [BackendConnectionState.disconnected] when the active backend
/// is not a [NetworkBackend] (local FFI mode, or no session). Always
/// seeded with the current value so the indicator doesn't flash empty
/// on first build.
final networkBackendConnectionStateProvider =
    StreamProvider<BackendConnectionState>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is! NetworkBackend) {
    return Stream<BackendConnectionState>.value(
      BackendConnectionState.disconnected,
    );
  }
  // Prepend the current value so subscribers see the seed immediately
  // rather than waiting for the next transition.
  final controller = StreamController<BackendConnectionState>();
  controller.add(backend.connectionState);
  final sub = backend.connectionStateStream.listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
