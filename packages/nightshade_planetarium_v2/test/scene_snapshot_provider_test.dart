import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

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
    );

    await tester.pump();
    await tester.pump();

    expect(container.read(sceneSnapshotProvider).frameId, BigInt.from(42));
    expect(fake.snapshotCallCount, greaterThan(readsAfterSettle));
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
