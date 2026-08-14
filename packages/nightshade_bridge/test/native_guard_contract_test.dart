/// Contract tests for the `_nativeAvailable` guards on the bridge stub.
///
/// `_nativeBridgeRequired` throws "requires the native bridge", so it is only
/// ever truthful under `if (!_nativeAvailable)`. A single inverted guard makes a
/// method fail on exactly the builds where it should work, and blames the wrong
/// thing while doing it — the cry-wolf shape this pass exists to remove.
///
/// The branch itself cannot be driven from a unit test: it needs
/// `_nativeAvailable == true`, which needs a `libnightshade_bridge` whose
/// content hash matches the checked-in `frb_generated.dart`, and `flutter test`
/// has no such library on its loader path. So the polarity of every guard is
/// pinned by reading the source, and the reachable half of the contract is
/// pinned by driving the fallback path.

library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// How far back from a `_nativeBridgeRequired` call the guard may sit.
const _guardLookbehind = 3;

void main() {
  group('native-availability guard polarity', () {
    test('every _nativeBridgeRequired sits under a negated guard', () {
      final stubDir = Directory('lib/src/bridge_stub');
      final sources = stubDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty, reason: 'run from the package root');

      final inverted = <String>[];
      for (final source in sources) {
        final lines = source.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('_nativeBridgeRequired(')) continue;
          final start = (i - _guardLookbehind).clamp(0, i);
          for (var j = i; j >= start; j--) {
            final line = lines[j];
            if (!line.contains('if (') || !line.contains('_nativeAvailable')) {
              continue;
            }
            if (!line.contains('!_nativeAvailable')) {
              inverted.add('${source.path}:${j + 1}: ${line.trim()}');
            }
            break;
          }
        }
      }

      expect(
        inverted,
        isEmpty,
        reason:
            'these guards throw "requires the native bridge" on the builds '
            'where the native bridge IS available',
      );
    });
  });

  group('no PHD2 call is stranded on the Dart client in native mode', () {
    // `phd2Connect`'s native branch NULLS `_phd2Client` and returns before the
    // only line that ever assigns it, and `phd2Disconnect` nulls it again. So
    // on every build where the native library loads — the shipped desktop and
    // headless configuration — `_phd2Client` is unconditionally null. A method
    // that reaches for it without a `_nativeAvailable` branch first therefore
    // cannot work on the builds users run, and it refuses with "PHD2 not
    // connected" on a rig whose PHD2 IS connected through the Rust client:
    // the same cry-wolf shape as the "requires the native bridge" refusal it
    // replaced. `phd2AutoSelectStar` was that method; the RPC it sends
    // (`find_star`) is exactly `api_phd2_find_star`.
    test('every _phd2Client user has a native branch', () {
      final source = File('lib/src/bridge_stub/guiding_operations.dart');
      expect(source.existsSync(), isTrue, reason: 'run from the package root');
      final lines = source.readAsLinesSync();

      // Method declarations sit at exactly two spaces of indent inside the
      // extension, so they bound each other.
      final starts = <int>[];
      final decl = RegExp(r'^  (?:Future|Stream)<');
      for (var i = 0; i < lines.length; i++) {
        if (decl.hasMatch(lines[i])) starts.add(i);
      }
      expect(starts, isNotEmpty, reason: 'the method scan found nothing');

      final stranded = <String>[];
      for (var m = 0; m < starts.length; m++) {
        final end = m + 1 < starts.length ? starts[m + 1] : lines.length;
        final body = lines.sublist(starts[m], end);
        if (!body.any((l) => l.contains('_phd2Client'))) continue;
        if (body.any((l) => l.contains('if (_nativeAvailable)'))) continue;
        stranded.add('${source.path}:${starts[m] + 1}: ${body.first.trim()}');
      }

      expect(
        stranded,
        isEmpty,
        reason:
            '_phd2Client is always null when the native library loads, so '
            'these methods refuse "PHD2 not connected" on exactly the builds '
            'where PHD2 is connected via Rust',
      );
    });
  });

  group('phd2AutoSelectStar', () {
    setUpAll(() async {
      await NativeBridge.init();
    });

    test('reports PHD2 connectivity, never a missing bridge', () async {
      // The fallback (no native library, which is what `flutter test` gets)
      // has no PHD2 client connected, so the only truthful failure is that
      // PHD2 is not connected. The native half is pinned by the source
      // contract above.
      await expectLater(
        NativeBridge.phd2AutoSelectStar(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('PHD2 not connected'),
              isNot(contains('requires the native bridge')),
            ),
          ),
        ),
      );
    });
  });
}
