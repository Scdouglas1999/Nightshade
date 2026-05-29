import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:path/path.dart' as p;

import '../bridge/planetarium_driver.dart';
import '../bridge/planetarium_handle.dart';

/// Flutter texture-registry engine id passed to [planetariumCreate].
///
/// Defaults to `0` for widget tests without Irondash. Host apps override this
/// with the live engine handle before mounting planetarium v2 widgets.
final planetariumEngineHandleProvider = Provider<int>((ref) => 0);

/// Bundled-asset catalog packs the host should auto-load into the v2
/// planetarium when the [Planetarium] handle is created. Subdirectory names
/// under `apps/desktop/assets/planetarium/catalogs/` (also packaged into the
/// Flutter asset bundle), in load order. Without these, the renderer still
/// runs but draws no stars or deep-sky objects — the user sees only
/// constellation/grid line geometry, which is what we observed at first
/// launch.
const List<String> _defaultPackSubdirs = <String>[
  'core',
  'stars-hyg-v1',
];

/// Host override for the bundled-asset packs to load. Useful for tests that
/// want to skip catalog loading entirely (pass an empty list).
final planetariumBundledPacksProvider =
    Provider<List<String>>((ref) => _defaultPackSubdirs);

/// Lazily creates the singleton [Planetarium] Rust handle when first watched.
///
/// After the first successful build, [Ref.keepAlive] retains the native handle
/// until the root [ProviderContainer] is disposed (see [Ref.onDispose]).
final planetariumHandleProvider = FutureProvider<PlanetariumDriver>((ref) async {
  final engineHandle = ref.watch(planetariumEngineHandleProvider);
  final planetarium = Planetarium.create(engineHandle: engineHandle);
  ref.onDispose(planetarium.dispose);
  ref.keepAlive();

  // Auto-load bundled catalog packs from the Flutter assets directory laid
  // down next to the executable. Skipped on platforms where we don't have a
  // resolvable path (web/tests) or when the override list is empty.
  final packs = ref.read(planetariumBundledPacksProvider);
  if (packs.isNotEmpty && !kIsWeb) {
    final assetsRoot = _flutterAssetsRoot();
    if (assetsRoot != null) {
      for (final sub in packs) {
        final packDir = p.join(
          assetsRoot,
          'assets',
          'planetarium',
          'catalogs',
          sub,
        );
        if (Directory(packDir).existsSync()) {
          try {
            planetariumLoadPack(handle: planetarium.nativeHandle, path: packDir);
          } catch (err, stack) {
            debugPrint('planetarium v2 failed to load pack "$sub": $err');
            debugPrint('$stack');
          }
        } else {
          debugPrint('planetarium v2 pack "$sub" not present at $packDir');
        }
      }
    }
  }

  return planetarium;
});

/// Resolves the `flutter_assets/` directory laid down next to the executable
/// on desktop. Returns `null` on platforms where the layout doesn't apply or
/// when the executable path can't be queried.
String? _flutterAssetsRoot() {
  try {
    if (Platform.isWindows || Platform.isLinux) {
      // Windows + Linux release layout: <exe_dir>/data/flutter_assets/
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.join(exeDir, 'data', 'flutter_assets');
      if (Directory(candidate).existsSync()) {
        return candidate;
      }
    } else if (Platform.isMacOS) {
      // macOS .app bundle: <exe>/../../Frameworks/App.framework/Resources/flutter_assets/
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidate = p.normalize(p.join(
        exeDir,
        '..',
        'Frameworks',
        'App.framework',
        'Resources',
        'flutter_assets',
      ));
      if (Directory(candidate).existsSync()) {
        return candidate;
      }
    }
  } catch (_) {
    // Fall through to null — caller logs and continues without packs.
  }
  return null;
}
