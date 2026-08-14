// Regression (D-1): the planetarium's time transport must not redefine the
// sidereal time the rest of the app states as fact.
//
// Live evidence, reproduced three times on the desktop build with the site set
// to 40.7128 N / -74.0060 W: stepping the planetarium forward six hours left
// the shell's bottom-right status strip showing a real wall clock beside a
// SIMULATED sidereal time, ~15 px apart, with nothing marking the difference:
//
//   wall 18:39:24 -> status bar `18:39:23` / `LST 11:15`  (true LST 15:12)
//   wall 18:40:11 -> status bar `18:40:10` / `LST 21:14`  (true LST 15:14)
//   wall 18:49:43 -> status bar `18:49:43` / `LST 21:24`  (true LST 15:22)
//
// The status bar and the dashboard header read `localSiderealTimeProvider`;
// that provider used to be keyed on the observation clock, so a preview control
// on one screen silently rewrote a number an imager plans by. Worse, a held
// clock stops publishing at all, which is why the wrong value then froze.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/src/astronomy/astronomy_calculations.dart';
import 'package:nightshade_planetarium/src/providers/planetarium_providers.dart';

const double _longitude = -74.0060;
const double _latitude = 40.7128;

/// Sidereal hours between two LST readings, folded across the 0/24 seam.
double _siderealGap(double a, double b) {
  var d = (a - b).abs() % 24;
  if (d > 12) d = 24 - d;
  return d;
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container
        .read(observerLocationProvider.notifier)
        .setLocation(latitude: _latitude, longitude: _longitude);
  });

  tearDown(() => container.dispose());

  test('scrubbing the planetarium forward does not move the real LST', () {
    final truth = AstronomyCalculations.localSiderealTime(
      DateTime.now(),
      _longitude,
    );
    expect(
      container.read(localSiderealTimeProvider),
      closeTo(truth, 0.01),
      reason: 'baseline: the chip agrees with now',
    );

    // The exact drive: six presses of step-forward, +1 h each.
    final notifier = container.read(observationTimeProvider.notifier);
    for (var i = 0; i < 6; i++) {
      notifier.fastForward(const Duration(hours: 1));
    }

    final scrubbed = container.read(observationSiderealTimeProvider);
    expect(
      _siderealGap(scrubbed, truth),
      greaterThan(5.5),
      reason: 'the planetarium\'s own readout must follow the scrub',
    );

    expect(
      container.read(localSiderealTimeProvider),
      closeTo(truth, 0.01),
      reason: 'the shell status bar states a fact about now, not a preview',
    );
  });

  test('pausing the sky does not freeze the real LST at a fiction', () {
    final notifier = container.read(observationTimeProvider.notifier);
    notifier.setTime(DateTime.now().add(const Duration(hours: 9)));
    notifier.pause();
    expect(container.read(observationTimeProvider).isPaused, isTrue);

    final truth = AstronomyCalculations.localSiderealTime(
      DateTime.now(),
      _longitude,
    );
    expect(container.read(localSiderealTimeProvider), closeTo(truth, 0.01));
  });

  test('the real LST tracks the site, not the observation clock', () {
    container
        .read(observationTimeProvider.notifier)
        .fastForward(const Duration(hours: 3));

    final east = container.read(localSiderealTimeProvider);
    container
        .read(observerLocationProvider.notifier)
        .setLocation(
          latitude: _latitude,
          longitude: _longitude + 15.0, // one hour of longitude
        );
    final west = container.read(localSiderealTimeProvider);

    expect(_siderealGap(east, west), closeTo(1.0, 0.02));
  });
}
