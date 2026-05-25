import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  test('PlanetariumAstroTime.fromDateTime matches J2000 noon UTC', () {
    final astro = PlanetariumAstroTime.fromDateTime(
      DateTime.utc(2000, 1, 1, 12, 0, 0),
    );
    expect(astro.jdUtc, closeTo(2451545.0, 1e-6));
    expect(astro.jdUt1, closeTo(2451545.0, 1e-6));
    expect(astro.jdTt, greaterThan(astro.jdUtc));
  });

  testWidgets('observationTimeProvider pushes time to planetariumSetTime',
      (tester) async {
    final fake = FakePlanetariumDriver();
    final sample = DateTime.utc(2020, 6, 21, 19, 0, 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
          coreObservationTimeProvider.overrideWith((ref) => sample),
        ],
        child: const _ObservationTimeSyncProbe(),
      ),
    );

    await tester.pump();

    final expected = PlanetariumAstroTime.fromDateTime(sample);
    expect(fake.lastTime, isNotNull);
    expect(fake.lastTime!.jdUtc, closeTo(expected.jdUtc, 1e-9));
    expect(fake.lastTime!.jdUt1, closeTo(expected.jdUt1, 1e-9));
    expect(fake.lastTime!.jdTt, closeTo(expected.jdTt, 1e-9));
  });
}

class _ObservationTimeSyncProbe extends ConsumerWidget {
  const _ObservationTimeSyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planetariumObservationTimeSyncProvider);
    ref.watch(observationTimeProvider);
    return const SizedBox.shrink();
  }
}
