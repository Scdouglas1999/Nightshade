import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/nightshade_backend.dart';
import '../backend/ffi_backend.dart';
import '../backend/disconnected_backend.dart';
import '../backend/network_backend.dart';
import 'database_provider.dart';
import 'equipment/equipment_state_reset.dart';

Future<void> Function()? _activeBackendSwapQuiescer;

void registerBackendSwapQuiescer(Future<void> Function() quiescer) {
  _activeBackendSwapQuiescer = quiescer;
}

void unregisterBackendSwapQuiescer(Future<void> Function() quiescer) {
  if (identical(_activeBackendSwapQuiescer, quiescer)) {
    _activeBackendSwapQuiescer = null;
  }
}

/// Notifier for the backend implementation
class BackendNotifier extends StateNotifier<NightshadeBackend> {
  final Ref _ref;

  BackendNotifier(this._ref) : super(DisconnectedBackend());

  /// Connect to a remote server
  Future<void> connect(
    String host,
    int port, {
    String? authToken,
  }) async {
    await _swapBackend(
      NetworkBackend(
        serverHost: host,
        serverPort: port,
        authToken: authToken,
      ),
    );
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    await _swapBackend(DisconnectedBackend());
  }

  /// Use local FFI backend (for Desktop/Headless)
  Future<void> useLocalBackend() async {
    // Get database instance from provider
    final database = _ref.read(databaseProvider);
    await _swapBackend(FfiBackend(database: database));
  }

  Future<void> _swapBackend(NightshadeBackend nextBackend) async {
    final quiesce = _activeBackendSwapQuiescer;
    if (quiesce != null) {
      await quiesce();
    }

    final previous = state;
    previous.dispose();
    state = nextBackend;
    resetAllEquipmentStateNotifiers(_ref);
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
