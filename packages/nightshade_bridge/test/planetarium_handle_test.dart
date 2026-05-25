/// Planetarium v2 FFI handle smoke test.
///
/// Full texture resize round-trip requires a loaded native bridge **and** a live
/// Flutter engine (`EngineContext`). In plain `flutter test` we verify the
/// create → set pose → snapshot → dispose path with engine handle `0` when the
/// native `nightshade_bridge` library is available (debug build).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:nightshade_bridge/src/api/planetarium.dart';
import 'package:nightshade_bridge/src/frb_generated.dart';

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

  test('planetarium handle round-trip without texture allocate', () {
    if (!Platform.isWindows) {
      return;
    }
    if (!rustReady) {
      // Mock-engine / CI: native dylib not on PATH; Rust bridge tests cover FFI.
      return;
    }

    final handle = planetariumCreate(engineHandle: 0);
    expect(handle, greaterThan(0));

      planetariumSetPose(
        handle: handle,
        pose: const ViewPoseDto(
          raRad: 1.0,
          decRad: 0.5,
          fovRad: 1.2,
          rollRad: 0.0,
          projection: SkyProjectionDto.stereographic,
        ),
      );

      final snap = planetariumSnapshot(handle: handle);
      expect(snap.frameId, greaterThan(0));
      expect(snap.viewPose.raRad, closeTo(1.0, 1e-9));

    planetariumDispose(handle: handle);
  });
}
