// Regression test for the planetarium's OPENING view.
//
// The reset action was fixed to home on the zenith, but the initial state was
// left at the constructor's RA 0h / Dec 0. Live at 40N / 105W that put first
// paint 25-45 deg BELOW the horizon: the bottom bar read "Center RA 0h 0m 0s
// Center Dec +0 0'" while the compass HUD read alt -45 — the map opened aimed
// into the ground.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/src/astronomy/astronomy_calculations.dart';
import 'package:nightshade_planetarium/src/providers/planetarium_providers.dart';

const _latitude = 40.0;
const _longitude = -105.0;

double _altitudeOfViewCentre(ProviderContainer container) {
  final view = container.read(skyViewStateProvider);
  final (alt, _) = AstronomyCalculations.objectAltAz(
    raDeg: view.centerRA * 15,
    decDeg: view.centerDec,
    dt: container.read(observationTimeProvider).time,
    latitudeDeg: _latitude,
    longitudeDeg: _longitude,
  );
  return alt;
}

void main() {
  test('first paint opens on sky that is up, not on RA 0h / Dec 0', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(observerLocationProvider.notifier)
        .setLocation(latitude: _latitude, longitude: _longitude);

    final (homeRa, homeDec) = container.read(skyViewHomeCenterProvider);
    final view = container.read(skyViewStateProvider);

    // Tolerance: the notifier homes off the wall clock, the provider off the
    // minute-truncated observation clock, so they can differ by up to a minute
    // of sidereal rotation (1/60 h of RA).
    expect(view.centerRA, closeTo(homeRa, 0.02));
    expect(view.centerDec, closeTo(homeDec, 1e-9));
    // The zenith, so within a minute of clock slop of straight up — and above
    // all the horizon is what actually matters.
    expect(
      _altitudeOfViewCentre(container),
      greaterThan(85.0),
      reason: 'the opening view must not be aimed below the horizon',
    );
  });

  test('a site that arrives after first build re-homes an untouched view', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Materialise the view BEFORE the site is known — this is the real order:
    // PlanetariumObserver starts on its Los Angeles default and the app's
    // settings sync pushes the user's site in later.
    container.read(skyViewStateProvider);
    container
        .read(observerLocationProvider.notifier)
        .setLocation(latitude: _latitude, longitude: _longitude);

    final (homeRa, homeDec) = container.read(skyViewHomeCenterProvider);
    final view = container.read(skyViewStateProvider);
    expect(view.centerRA, closeTo(homeRa, 0.02));
    expect(view.centerDec, closeTo(homeDec, 1e-9));
    expect(_altitudeOfViewCentre(container), greaterThan(85.0));
  });

  test('a late site never yanks the camera off a view the user aimed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(skyViewStateProvider.notifier).setCenter(5.5, 12.5);
    container
        .read(observerLocationProvider.notifier)
        .setLocation(latitude: _latitude, longitude: _longitude);

    final view = container.read(skyViewStateProvider);
    expect(view.centerRA, closeTo(5.5, 1e-9));
    expect(view.centerDec, closeTo(12.5, 1e-9));
  });
}
