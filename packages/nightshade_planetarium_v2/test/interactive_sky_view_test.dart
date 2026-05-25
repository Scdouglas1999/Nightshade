import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('InteractiveSkyView hosts Texture from handle', (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const SizedBox(
          width: 640,
          height: 480,
          child: InteractiveSkyView(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Texture), findsOneWidget);
  });
}
