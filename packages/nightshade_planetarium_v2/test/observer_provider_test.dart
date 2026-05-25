import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('observerProvider pushes site to planetariumSetObserver',
      (tester) async {
    final fake = FakePlanetariumDriver();
    const site = LocationSettings(
      latitude: 40.015,
      longitude: -105.2705,
      elevation: 1655,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
          appObserverLocationProvider.overrideWith((ref) => site),
        ],
        child: const _ObserverSyncProbe(),
      ),
    );

    await tester.pump();

    expect(fake.lastObserver, isNotNull);
    expect(
      fake.lastObserver!.latitudeRad,
      closeTo(40.015 * 3.141592653589793 / 180, 1e-9),
    );
    expect(
      fake.lastObserver!.longitudeRad,
      closeTo(-105.2705 * 3.141592653589793 / 180, 1e-9),
    );
    expect(fake.lastObserver!.elevationM, closeTo(1655, 1e-9));
    expect(fake.lastObserver!.pressureHpa, kDefaultObserverPressureHpa);
    expect(fake.lastObserver!.temperatureC, kDefaultObserverTemperatureC);
  });

  test('observerProvider fails loud when location is unset', () {
    final container = ProviderContainer(
      overrides: [
        appObserverLocationProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    expect(() => container.read(observerProvider), throwsA(isA<StateError>()));
  });
}

class _ObserverSyncProbe extends ConsumerWidget {
  const _ObserverSyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planetariumObserverSyncProvider);
    ref.watch(observerProvider);
    return const SizedBox.shrink();
  }
}
