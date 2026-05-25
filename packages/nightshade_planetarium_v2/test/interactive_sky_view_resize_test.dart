import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

/// Hosts [InteractiveSkyView] inside a tight box of the requested size.
///
/// `tester.pumpWidget` gives the root tight constraints equal to the test
/// surface (800×600 by default). A bare `SizedBox` cannot shrink under tight
/// parent constraints, so we wrap in `Center` to relax them before sizing.
Widget _harness({
  required Widget child,
  required double width,
  required double height,
  required PlanetariumDriver driver,
}) {
  return ProviderScope(
    overrides: [
      planetariumHandleProvider.overrideWith((ref) async => driver),
    ],
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('InteractiveSkyView resizes when layout constraints change',
      (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      _harness(
        driver: fake,
        width: 640,
        height: 480,
        child: const InteractiveSkyView(),
      ),
    );

    await tester.pumpAndSettle();
    expect(fake.lastResizeWidth, 640);
    expect(fake.lastResizeHeight, 480);

    await tester.pumpWidget(
      _harness(
        driver: fake,
        width: 320,
        height: 240,
        child: const InteractiveSkyView(),
      ),
    );

    await tester.pumpAndSettle();
    expect(fake.lastResizeWidth, 320);
    expect(fake.lastResizeHeight, 240);
  });

  testWidgets('InteractiveSkyView debounces no-op layouts', (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      _harness(
        driver: fake,
        width: 640,
        height: 480,
        child: const InteractiveSkyView(),
      ),
    );

    await tester.pumpAndSettle();
    expect(fake.lastResizeWidth, 640);

    // Re-pump same widget with same dimensions — must not re-issue resize.
    fake.lastResizeWidth = null;
    fake.lastResizeHeight = null;
    await tester.pumpWidget(
      _harness(
        driver: fake,
        width: 640,
        height: 480,
        child: const InteractiveSkyView(),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.lastResizeWidth, isNull);
    expect(fake.lastResizeHeight, isNull);
  });
}
