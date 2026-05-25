import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/planetarium_handle.dart';

/// Flutter texture-registry engine id passed to [planetariumCreate].
///
/// Defaults to `0` for widget tests without Irondash. Host apps override this
/// with the live engine handle before mounting planetarium v2 widgets.
final planetariumEngineHandleProvider = Provider<int>((ref) => 0);

/// Lazily creates the singleton [Planetarium] Rust handle when first watched.
///
/// After the first successful build, [Ref.keepAlive] retains the native handle
/// until the root [ProviderContainer] is disposed (see [Ref.onDispose]).
final planetariumHandleProvider = FutureProvider<Planetarium>((ref) async {
  final engineHandle = ref.watch(planetariumEngineHandleProvider);
  final planetarium = Planetarium.create(engineHandle: engineHandle);
  ref.onDispose(planetarium.dispose);
  ref.keepAlive();
  return planetarium;
});
