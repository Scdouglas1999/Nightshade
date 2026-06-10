import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capture support for the key-surface design goldens.
///
/// Mirrors the nightshade_ui golden harness: it loads the real bundled fonts so
/// rasterised PNGs render the shipped typefaces (not Ahem boxes), then captures
/// a `RepaintBoundary` of a fully-built surface to a PNG written into
/// `docs/design/goldens/`. These are review artifacts for the lead engineer, not
/// pixel-diff guards — the test bodies assert only that a real, non-empty image
/// was produced.
abstract final class SurfaceGoldenHarness {
  SurfaceGoldenHarness._();

  static bool _fontsLoaded = false;

  static Future<void> ensureFonts() async {
    if (_fontsLoaded) return;
    final fontsDir = '${repoRoot().path}/packages/nightshade_ui/assets/fonts';
    await _loadFont('HankenGrotesk', '$fontsDir/HankenGrotesk-VF.ttf');
    await _loadFont('SplineSansMono', '$fontsDir/SplineSansMono-VF.ttf');
    // Lucide glyph font (family "Lucide", package "lucide_icons") so icons in
    // captured surfaces render as real glyphs, not tofu boxes.
    await _loadFont('packages/lucide_icons/Lucide', resolveLucideTtf());
    _fontsLoaded = true;
  }

  /// Resolves the absolute path to the bundled Lucide icon font via the test
  /// package's `.dart_tool/package_config.json`. Fails loud if unresolvable.
  static String resolveLucideTtf() {
    final config =
        File('${Directory.current.path}/.dart_tool/package_config.json');
    if (!config.existsSync()) {
      throw StateError('package_config.json not found: ${config.path}');
    }
    final decoded =
        jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final packages = (decoded['packages'] as List).cast<Map<String, dynamic>>();
    final lucide = packages.firstWhere(
      (p) => p['name'] == 'lucide_icons',
      orElse: () =>
          throw StateError('lucide_icons missing from package_config.json'),
    );
    var rootUri = Uri.parse(lucide['rootUri'] as String);
    if (!rootUri.isAbsolute) {
      rootUri = Uri.directory('${config.parent.path}/').resolveUri(rootUri);
    }
    final rootDir = rootUri.path.endsWith('/')
        ? rootUri
        : rootUri.replace(path: '${rootUri.path}/');
    final ttf = File.fromUri(rootDir.resolve('assets/lucide.ttf'));
    if (!ttf.existsSync()) {
      throw StateError('Lucide font asset not found: ${ttf.path}');
    }
    return ttf.path;
  }

  static Future<void> _loadFont(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Missing bundled font for golden capture: $path');
    }
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  static Directory repoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 10; i++) {
      if (File('${dir.path}/version.yaml').existsSync() ||
          Directory('${dir.path}/.git').existsSync()) {
        return dir;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current;
  }

  static Directory goldensDir() {
    final dir = Directory('${repoRoot().path}/docs/design/goldens');
    dir.createSync(recursive: true);
    return dir;
  }

  /// Captures whatever is currently mounted under [boundaryKey] to
  /// `docs/design/goldens/<fileName>` and returns the written file.
  ///
  /// `RenderRepaintBoundary.toImage` and `Image.toByteData` are real
  /// (non-fake) async GPU/IO operations. Under the automated test binding's
  /// fake-async zone they never resolve — so the capture MUST run inside
  /// [WidgetTester.runAsync], otherwise the awaiting test hangs until the
  /// per-test timeout. (The PNG still gets written by the worker, which is why
  /// earlier runs produced images yet each test then timed out.)
  static Future<File> captureBoundary(
    WidgetTester tester,
    GlobalKey boundaryKey, {
    required String fileName,
    double pixelRatio = 2.0,
  }) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final file = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw StateError('PNG encode failed for golden capture: $fileName');
        }
        final out = File('${goldensDir().path}/$fileName');
        out.writeAsBytesSync(bytes.buffer.asUint8List());
        // ignore: avoid_print
        print('Golden written: ${out.absolute.path} '
            '(${out.lengthSync()} bytes)');
        return out;
      } finally {
        image.dispose();
      }
    });
    if (file == null) {
      throw StateError('Golden capture returned no file for: $fileName');
    }
    return file;
  }
}
