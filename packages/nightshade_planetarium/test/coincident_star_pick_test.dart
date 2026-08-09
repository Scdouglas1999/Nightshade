// Regression: tapping a star must hand out the star the chart LABELLED.
//
// Found live: the sky draws "Capella"; clicking it opened the object panel
// headed "HYG118360" at "mag 1.0". HYG lists the Capella system as two rows
// 9 arcsec apart — Aa (mag 0.08, "Capella") and Ab (mag 0.96, the unnamed
// component). At any field wider than a fraction of a degree that separation is
// well under one pixel, so the renderer draws ONE glyph with ONE label while the
// hit test took the strictly nearest row — making the pick a coin flip between
// a star and its own companion, and the reported magnitude a magnitude too
// faint.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Capella Aa — what the chart labels.
const _capellaAa = Star(
  id: 'HIP24608',
  name: 'Capella',
  coordinates: CelestialCoordinate(ra: 5.27815, dec: 45.997991),
  magnitude: 0.08,
);

/// Capella Ab — 9 arcsec away, a magnitude fainter.
const _capellaAb = Star(
  id: 'HYG118360',
  name: 'Capella B',
  coordinates: CelestialCoordinate(ra: 5.277926, dec: 46.000842),
  magnitude: 0.96,
);

Future<Star?> _tapCentreAt(WidgetTester tester, double fovDegrees) async {
  CelestialObject? tapped;
  final container = ProviderContainer(
    overrides: [
      combinedStarsProvider.overrideWithValue(
        const AsyncValue.data(<Star>[_capellaAb, _capellaAa]),
      ),
      fovFilteredDsosProvider.overrideWithValue(
        const AsyncValue.data(<DeepSkyObject>[]),
      ),
      planetPositionsProvider.overrideWithValue(const []),
    ],
  );
  // Aim exactly at the FAINT companion, so the nearest-row rule would pick it.
  container
      .read(skyViewStateProvider.notifier)
      .setCenter(_capellaAb.coordinates.ra, _capellaAb.coordinates.dec);
  container.read(skyViewStateProvider.notifier).setFieldOfView(fovDegrees);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: InteractiveSkyView(
            onObjectTapped: (object, _, __) => tapped = object,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tapAt(tester.getCenter(find.byType(InteractiveSkyView)));
  await tester.pump(const Duration(milliseconds: 500));

  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  return tapped as Star?;
}

void main() {
  testWidgets('a tap inside one drawn glyph returns the labelled star', (
    tester,
  ) async {
    // The audited framing: a 2-degree imaging field, where 9 arcsec is ~1 px.
    final tapped = await _tapCentreAt(tester, 2.0);

    expect(tapped, isNotNull);
    expect(tapped!.name, 'Capella');
    expect(
      tapped.magnitude,
      closeTo(0.08, 1e-9),
      reason: 'reporting the companion\'s 0.96 is the original bug',
    );
  });

  testWidgets('at a wide field the same tap still returns the labelled star', (
    tester,
  ) async {
    final tapped = await _tapCentreAt(tester, 60.0);
    expect(tapped!.name, 'Capella');
  });

  testWidgets('once the pair is genuinely resolved both stay selectable', (
    tester,
  ) async {
    // At a 0.05-degree field the 9-arcsec pair is ~50 px apart on screen, so a
    // tap really can address one component rather than the other and the merge
    // must not fire.
    final tapped = await _tapCentreAt(tester, 0.05);
    expect(tapped!.name, 'Capella B');
  });
}
