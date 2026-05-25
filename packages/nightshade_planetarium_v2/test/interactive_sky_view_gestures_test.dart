import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('InteractiveSkyView pan pushes planetariumPushGesture events',
      (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const SizedBox(
          width: 400,
          height: 300,
          child: InteractiveSkyView(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(Texture));
    await tester.dragFrom(center, const Offset(40, 0));
    await tester.pump();

    expect(fake.pushedGestures, isNotEmpty);
    expect(
      fake.pushedGestures.any((e) => e.kind == GestureKindDto.panStart),
      isTrue,
    );
    expect(
      fake.pushedGestures.any((e) => e.kind == GestureKindDto.panUpdate),
      isTrue,
    );
  });
}
