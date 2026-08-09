// Regression: rise / transit / set must describe ONE up-period.
//
// `calculateObjectVisibility` scans local noon to local noon. For every object
// that is already above the horizon when that window opens — the whole
// early-evening half of the sky — the first crossing found is a SET and the
// next RISE belongs to the following day. The solver used to keep that late
// rise and then hunt forward for a set to match it, so both ends landed ~24 h
// after the events they described while the transit stayed on the right day:
//
//   Denver, night of 2024-01-15, RA 22h Dec +20
//     rise 2024-01-16 07:03   transit 2024-01-15 14:20   set 2024-01-16 21:30
//
// The target actually rose at 07:07 and set at 21:33 on the 15th. Three
// separate consumers had grown workarounds for this: the Smart Night emitter
// shifts crossings by whole sidereal days to find the period that overlaps the
// dark window, `TargetWindow.isVisibleAt` short-circuits to a live altitude
// solve ("a target at the zenith came back as 'rises at 03:41' tomorrow"), and
// the night scorer stopped gating its "rises late" warning on riseTime at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  test('an evening target sets on the night it was asked about', () {
    // Deliberately timezone-independent: the assertions are about which
    // up-period the three timestamps belong to, not about absolute instants.
    final v = AstronomyCalculations.calculateObjectVisibility(
      raDeg: 22 * 15.0,
      decDeg: 20,
      date: DateTime(2024, 1, 15),
      latitudeDeg: 40,
      longitudeDeg: -105,
    );

    expect(v.riseTime, isNotNull);
    expect(v.setTime, isNotNull);
    expect(v.transitTime, isNotNull);
    expect(
      v.riseTime!.isBefore(v.transitTime!),
      isTrue,
      reason: 'rise ${v.riseTime} is not before transit ${v.transitTime}',
    );
    expect(
      v.setTime!.isAfter(v.transitTime!),
      isTrue,
      reason: 'set ${v.setTime} is not after transit ${v.transitTime}',
    );
    // The whole up-period is one pass of the sky, so it cannot span a day.
    expect(
      v.setTime!.difference(v.riseTime!).inHours,
      lessThan(24),
      reason: 'rise and set must bound a single pass, not two',
    );
  });

  test('rise and set bracket the transit everywhere they all exist', () {
    // A wide sweep, because which objects open the window already up depends on
    // longitude, latitude, declination and the season.
    var checked = 0;
    for (final lat in [-45.0, -20.0, 0.0, 25.0, 40.0, 58.0]) {
      for (final lon in [-105.0, 0.0, 140.0]) {
        for (final month in [1, 4, 7, 10]) {
          for (var raHours = 0.0; raHours < 24.0; raHours += 1.0) {
            for (final dec in [-55.0, -15.0, 5.0, 35.0, 65.0]) {
              final v = AstronomyCalculations.calculateObjectVisibility(
                raDeg: raHours * 15.0,
                decDeg: dec,
                date: DateTime(2025, month, 12),
                latitudeDeg: lat,
                longitudeDeg: lon,
              );
              final rise = v.riseTime;
              final set = v.setTime;
              final transit = v.transitTime;
              if (rise == null || set == null || transit == null) continue;
              checked++;
              final label =
                  'lat=$lat lon=$lon month=$month ra=${raHours}h dec=$dec: '
                  'rise=$rise transit=$transit set=$set';
              expect(rise.isBefore(transit), isTrue, reason: label);
              expect(set.isAfter(transit), isTrue, reason: label);
              expect(set.difference(rise).inHours, lessThan(24), reason: label);
            }
          }
        }
      }
    }
    expect(checked, greaterThan(500), reason: 'the sweep must actually solve');
  });
}
