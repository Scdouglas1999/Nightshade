// Planetarium v2 Dart bridge handle smoke test.
// Verifies create → dispose with engine handle 0 when native bridge is loaded.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:nightshade_bridge/src/frb_generated.dart';
import 'package:nightshade_planetarium_v2/src/bridge/planetarium_handle.dart';

final _nativeLibCandidates = [
  '../../../native/nightshade_native/target/debug/nightshade_bridge.dll',
  '../../../native/nightshade_native/target/release/nightshade_bridge.dll',
];

Future<bool> _tryInitRustLib() async {
  for (final relative in _nativeLibCandidates) {
    final path = File(relative);
    if (!path.existsSync()) continue;
    try {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(path.absolute.path),
      );
      return true;
    } catch (_) {
      continue;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final bool rustReady;

  setUpAll(() async {
    rustReady = await _tryInitRustLib();
  });

  testWidgets('Planetarium create and dispose round-trip', (tester) async {
    if (!Platform.isWindows) {
      return;
    }
    if (!rustReady) {
      return;
    }

    final planetarium = Planetarium.create(engineHandle: 0);
    addTearDown(planetarium.dispose);

    expect(planetarium.nativeHandle, greaterThan(0));
    expect(planetarium.textureId, 0);

    planetarium.dispose();
    planetarium.dispose();
  });
}
