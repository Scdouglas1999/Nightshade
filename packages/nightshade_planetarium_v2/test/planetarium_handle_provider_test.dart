// Widget tests for lazy planetarium handle provider + keepalive semantics.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_bridge/src/frb_generated.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

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

  testWidgets('planetariumHandleProvider resolves lazily in widget tree',
      (tester) async {
    if (!Platform.isWindows || !rustReady) {
      return;
    }

    await tester.pumpWidget(
      const ProviderScope(
        child: _PlanetariumHandleProbe(),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('handle:'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('planetariumHandleProvider keepalives after first success',
      (tester) async {
    if (!Platform.isWindows || !rustReady) {
      return;
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = await container.read(planetariumHandleProvider.future);
    expect(first.nativeHandle, greaterThan(0));

    final subscription = container.listen(
      planetariumHandleProvider,
      (_, __) {},
    );
    subscription.close();

    final second = await container.read(planetariumHandleProvider.future);
    expect(identical(first, second), isTrue);

    container.dispose();
    expect(
      () => first.setPose(
        const ViewPoseDto(
          raRad: 0,
          decRad: 0,
          fovRad: 1,
          rollRad: 0,
          projection: SkyProjectionDto.stereographic,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _PlanetariumHandleProbe extends ConsumerWidget {
  const _PlanetariumHandleProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHandle = ref.watch(planetariumHandleProvider);
    return asyncHandle.when(
      data: (planetarium) => Text('handle:${planetarium.nativeHandle}'),
      loading: () => const Text('loading'),
      error: (error, _) => Text('error:$error'),
    );
  }
}
