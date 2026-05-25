import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/planetarium/adaptive_interactive_sky_view.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart' as planetarium_v1;
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart' as planetarium_v2;

import 'fake_planetarium_driver.dart';

void main() {
  testWidgets('AdaptiveInteractiveSkyView uses v1 InteractiveSkyView by default',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AdaptiveInteractiveSkyView(),
          ),
        ),
      ),
    );

    expect(find.byType(planetarium_v1.InteractiveSkyView), findsOneWidget);
    expect(find.byType(planetarium_v2.InteractiveSkyView), findsNothing);
  });

  testWidgets('AdaptiveInteractiveSkyView stacks v2 sky and overlay layers when v2',
      (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          usePlanetariumV2Provider.overrideWith((ref) => true),
          appObserverLocationProvider.overrideWith(
            (ref) => const LocationSettings(
              latitude: 40.0,
              longitude: -105.0,
              elevation: 1600,
            ),
          ),
          planetarium_v2.planetariumHandleProvider
              .overrideWith((ref) async => fake),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AdaptiveInteractiveSkyView(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(planetarium_v1.InteractiveSkyView), findsNothing);
    expect(find.byType(planetarium_v2.InteractiveSkyView), findsOneWidget);
    expect(find.byType(planetarium_v2.LabelLayer), findsOneWidget);
    expect(find.byType(planetarium_v2.ConstellationArtLayer), findsOneWidget);
  });
}
