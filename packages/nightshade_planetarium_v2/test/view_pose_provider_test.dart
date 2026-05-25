import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('viewPoseProvider pushes pose to planetariumSetPose', (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _ViewPoseSyncProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_ViewPoseSyncProbe)),
    );
    container.read(viewPoseProvider.notifier).setCenter(6, 30);
    container.read(viewPoseProvider.notifier).setFieldOfView(45);
    container.read(viewPoseProvider.notifier).setRotation(15);
    container
        .read(viewPoseProvider.notifier)
        .setProjection(PlanetariumSkyProjection.orthographic);

    await tester.pump();

    expect(fake.lastPose, isNotNull);
    expect(fake.lastPose!.raRad, closeTo(6 * 3.141592653589793 / 12, 1e-9));
    expect(fake.lastPose!.decRad, closeTo(30 * 3.141592653589793 / 180, 1e-9));
    expect(fake.lastPose!.fovRad, closeTo(45 * 3.141592653589793 / 180, 1e-9));
    expect(fake.lastPose!.rollRad, closeTo(15 * 3.141592653589793 / 180, 1e-9));
    expect(fake.lastPose!.projection, SkyProjectionDto.orthographic);
  });
}

class _ViewPoseSyncProbe extends ConsumerWidget {
  const _ViewPoseSyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planetariumViewPoseSyncProvider);
    return const SizedBox.shrink();
  }
}
