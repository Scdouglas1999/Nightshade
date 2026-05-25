import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

final _polaris = SelectedObjectDto(
  objectId: BigInt.from(11767),
  screenX: 0.5,
  screenY: 0.5,
  raRad: 0.1,
  decRad: 1.4,
  category: LabelCategoryDto.star,
  displayName: 'Polaris',
);

void main() {
  testWidgets('InteractiveSkyView tap hit-tests and syncs selection to Rust',
      (tester) async {
    final fake = FakePlanetariumDriver()..hitTestStub = _polaris;
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const SizedBox(
              width: 400,
              height: 300,
              child: InteractiveSkyView(),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(Texture)));
    await tester.pump();

    expect(fake.lastHitTestX, closeTo(0.5, 0.01));
    expect(fake.lastHitTestY, closeTo(0.5, 0.01));
    expect(container.read(selectionProvider), _polaris);
    expect(fake.lastSelection, _polaris);
    expect(
      fake.pushedGestures.any((e) => e.kind == GestureKindDto.tap),
      isTrue,
    );
  });

  testWidgets('InteractiveSkyView tap on empty sky clears selection',
      (tester) async {
    final fake = FakePlanetariumDriver();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const SizedBox(
              width: 400,
              height: 300,
              child: InteractiveSkyView(),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(Texture)));
    await tester.pump();

    expect(container.read(selectionProvider), isNull);
    expect(fake.lastSelection, isNull);
  });
}
