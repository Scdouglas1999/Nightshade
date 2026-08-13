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

  group('phd2AutoSelectStar', () {
    setUpAll(() async {
      await NativeBridge.init();
    });

    test('reports PHD2 connectivity, never a missing bridge', () async {
      // No PHD2 client has been connected, so the only truthful failure is
      // that PHD2 is not connected. There is no `apiPhd2AutoSelectStar` in the
      // generated API, so the Dart client is the sole implementation in either
      // native mode and this contract holds in both.
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
