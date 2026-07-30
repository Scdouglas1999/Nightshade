// Regression test for tap-to-select identity.
//
// Tapping a star glyph used to hand the caller the coordinate reconstructed
// from the tap pixel, not the catalogue coordinate of the object that was hit.
// Every downstream action (popup readout, Slew, Framing, Sequencer, Add to
// List) consumed that coordinate, so a named object could be slewed to a
// position degrees away from where it actually is.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/src/celestial_object.dart';
import 'package:nightshade_planetarium/src/coordinate_system.dart';
import 'package:nightshade_planetarium/src/providers/deep_star_providers.dart';
import 'package:nightshade_planetarium/src/providers/planetarium_providers.dart';
import 'package:nightshade_planetarium/src/widgets/interactive_sky_view.dart';

const _capella = Star(
  id: 'HIP24608',
  name: 'Capella',
  coordinates: CelestialCoordinate(ra: 5.2782, dec: 45.998),
  magnitude: 0.08,
  spectralType: 'G8III',
  constellation: 'AUR',
);

void main() {
  testWidgets('tapping a star reports the catalogue coordinate', (
    tester,
  ) async {
    CelestialObject? tappedObject;
    CelestialCoordinate? tappedCoordinate;

    final container = ProviderContainer(
      overrides: [
        combinedStarsProvider.overrideWithValue(
          const AsyncValue.data([_capella]),
        ),
        fovFilteredDsosProvider.overrideWithValue(
          const AsyncValue.data(<DeepSkyObject>[]),
        ),
      ],
    );
    container
        .read(skyViewStateProvider.notifier)
        .setCenter(_capella.coordinates.ra, _capella.coordinates.dec);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: InteractiveSkyView(
              onObjectTapped: (object, coordinates, _) {
                tappedObject = object;
                tappedCoordinate = coordinates;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap a few pixels off the glyph centre — still inside the hit radius, but
    // a different sky coordinate than the star itself.
    final centre = tester.getCenter(find.byType(InteractiveSkyView));
    await tester.tapAt(centre + const Offset(4, 3));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tappedObject?.name, 'Capella');
    expect(
      tappedCoordinate!.ra,
      closeTo(_capella.coordinates.ra, 1e-9),
      reason: 'popup/slew RA must come from the catalogue, not the tap pixel',
    );
    expect(
      tappedCoordinate!.dec,
      closeTo(_capella.coordinates.dec, 1e-9),
      reason: 'popup/slew Dec must come from the catalogue, not the tap pixel',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
