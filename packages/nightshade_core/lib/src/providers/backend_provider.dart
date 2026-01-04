import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/nightshade_backend.dart';
import '../backend/ffi_backend.dart';
import '../backend/disconnected_backend.dart';
import '../backend/network_backend.dart';
import 'database_provider.dart';

/// Notifier for the backend implementation
class BackendNotifier extends StateNotifier<NightshadeBackend> {
  final Ref _ref;

  BackendNotifier(this._ref) : super(DisconnectedBackend());

  /// Connect to a remote server
  void connect(String host, int port) {
    // Dispose old backend before switching
    state.dispose();
    state = NetworkBackend(serverHost: host, serverPort: port);
  }

  /// Disconnect from server
  void disconnect() {
    // Dispose old backend before switching
    state.dispose();
    state = DisconnectedBackend();
  }

  /// Use local FFI backend (for Desktop/Headless)
  void useLocalBackend() {
    // Dispose old backend before switching
    state.dispose();
    // Get database instance from provider
    final database = _ref.read(databaseProvider);
    state = FfiBackend(database: database);
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
final backendProvider = StateNotifierProvider<BackendNotifier, NightshadeBackend>((ref) {
  return BackendNotifier(ref);
});

/// Provider to check if we're in remote (network) mode
/// When true, file paths refer to the server filesystem, not local
final isRemoteModeProvider = Provider<bool>((ref) {
  final backend = ref.watch(backendProvider);
  return backend is NetworkBackend;
});
