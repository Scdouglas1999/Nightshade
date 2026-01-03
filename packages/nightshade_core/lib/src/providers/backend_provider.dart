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
    state = NetworkBackend(serverHost: host, serverPort: port);
  }

  /// Disconnect from server
  void disconnect() {
    state = DisconnectedBackend();
  }

  /// Use local FFI backend (for Desktop/Headless)
  void useLocalBackend() {
    // Get database instance from provider
    final database = _ref.read(databaseProvider);
    state = FfiBackend(database: database);
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
