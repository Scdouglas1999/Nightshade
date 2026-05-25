import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

/// Drives one extra frame so the chained post-frame callback that
/// [SceneSnapshotNotifier] uses for polling actually fires.
///
/// The notifier deliberately does NOT call `scheduleFrame()` itself (that
/// would peg the engine and break `pumpAndSettle`). Production code drives
/// the loop via real frame triggers (gestures, animations, ticker rebuilds);
/// tests do the same by explicitly scheduling + pumping a frame.
Future<void> _pumpPoll(WidgetTester tester) async {
  SchedulerBinding.instance.scheduleFrame();
  await tester.pump();
}

void main() {
  testWidgets('sceneSnapshotProvider polls snapshot each Flutter frame',
      (tester) async {
    final fake = FakePlanetariumDriver();
    fake.snapshotResult = kEmptySceneSnapshot;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _SceneSnapshotProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_SceneSnapshotProbe)),
    );
    expect(container.read(sceneSnapshotProvider).frameId, BigInt.zero);
    final readsAfterSettle = fake.snapshotCallCount;
    expect(readsAfterSettle, greaterThan(0));

    fake.snapshotResult = SceneSnapshotDto(
      frameId: BigInt.from(42),
      viewPose: kEmptySceneSnapshot.viewPose,
      labels: const [],
      constellationArt: const [],
    );

    await _pumpPoll(tester);
    await _pumpPoll(tester);

    expect(container.read(sceneSnapshotProvider).frameId, BigInt.from(42));
    expect(fake.snapshotCallCount, greaterThan(readsAfterSettle));
  });

  testWidgets(
      'sceneSnapshotProvider skips state updates when frameId is unchanged',
      (tester) async {
    final fake = FakePlanetariumDriver();
    fake.snapshotResult = kEmptySceneSnapshot;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _SceneSnapshotProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_SceneSnapshotProbe)),
    );

    var rebuilds = 0;
    final sub = container.listen<SceneSnapshotDto>(
      sceneSnapshotProvider,
      (_, __) => rebuilds++,
    );
    addTearDown(sub.close);

    // Three pumps with the same frameId — provider must not push new state.
    await _pumpPoll(tester);
    await _pumpPoll(tester);
    await _pumpPoll(tester);

    expect(rebuilds, 0);
  });

  testWidgets('sceneSnapshotProvider stops polling when quiesced',
      (tester) async {
    final fake = FakePlanetariumDriver();
    fake.snapshotResult = kEmptySceneSnapshot;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _SceneSnapshotProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_SceneSnapshotProbe)),
    );
    container.read(planetariumQuiescedProvider.notifier).state = true;
    await tester.pump();

    final readsBefore = fake.snapshotCallCount;
    await _pumpPoll(tester);
    await _pumpPoll(tester);
    expect(fake.snapshotCallCount, readsBefore);
  });
}

class _SceneSnapshotProbe extends ConsumerWidget {
  const _SceneSnapshotProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sceneSnapshotProvider);
    return const SizedBox.shrink();
  }
}
