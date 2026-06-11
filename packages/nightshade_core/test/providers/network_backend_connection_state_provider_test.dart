import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Regression test for the
/// [networkBackendConnectionStateProvider] introduced to separate the
/// WebSocket-level connection state from the OS-level network state in
/// the mobile chip. The provider must emit `disconnected` whenever the
/// active backend is not a [NetworkBackend] so that the chip falls back
/// to a sane "not connected" rendering for the desktop/local-FFI and
/// "explicitly disconnected" code paths.
///
/// The companion case (`NetworkBackend` produces a live state stream) is
/// exercised by `network_backend_websocket_test.dart::first
/// attempt emits 'connecting'...` which drives a real backend against
/// a loopback HTTP server. Combining both gives us full coverage of the
/// public API without having to mock the WS layer twice.
void main() {
  test('networkBackendConnectionStateProvider: emits disconnected when the '
      'active backend is the default DisconnectedBackend', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // BackendNotifier seeds with DisconnectedBackend so the provider
    // should immediately resolve to `disconnected` without any WS
    // activity. This is the OS-online + WS-not-live case the chip
    // collapses into "Server unreachable" or "Not connected" on the
    // mobile UI side.
    final asyncValue = container.read(networkBackendConnectionStateProvider);
    // The provider is a StreamProvider with a synchronous seed; the
    // first read returns the synchronous AsyncValue with the seed in
    // either `.data` or as the first frame after a pump.
    // Wait one microtask for the controller to dispatch the seed.
    await Future<void>.value();
    final settled = container.read(networkBackendConnectionStateProvider);
    expect(
      settled.value ?? asyncValue.value,
      BackendConnectionState.disconnected,
      reason:
          'with no NetworkBackend, the provider must report '
          'disconnected so the chip renders "Server unreachable" / '
          '"Not connected" instead of guessing connectivity from the '
          'OS link.',
    );
  });
}
