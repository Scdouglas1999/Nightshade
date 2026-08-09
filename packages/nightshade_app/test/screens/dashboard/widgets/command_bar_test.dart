// Unit tests for the DashboardCommandBar's pure helper logic.
//
// These cover the two pieces of decision logic that drive the command bar's
// new behavior and are cheap to test in isolation (no widget tree, no
// provider container, no leaking planetarium timers):
//
//   * resolveNightContext(twilight, now, clock: const SystemClock()) — picks the single most relevant
//     darkness fact for the night-context chip:
//       before astro dusk  → "Dark in {countdown}"   (key darkIn)
//       during astro night → "Dark {countdown} left" (key darkLeft)
//       after dawn / day    → "Sunset {HH:MM}"        (key sunsetAt)
//     and returns null when there's no twilight data (no location) so the
//     chip self-hides.
//
//   * gradeRms(arcsec) — the guiding-quality color grade thresholds:
//       < 1.0"  → good, 1.0–2.0" → fair, > 2.0" → poor, null → null.
//
// We import command_bar.dart directly to reach the top-level helpers and
// the NightContextKind / RmsGrade enums.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/command_bar.dart';
import 'package:nightshade_core/nightshade_core.dart' hide TwilightTimes;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  group('resolveNightContext', () {
    // A fixed local reference instant so countdowns are deterministic.
    final now = DateTime(2026, 6, 10, 21, 0); // 21:00

    test('before astronomical dusk → "Dark in" countdown', () {
      final twilight = TwilightTimes(
        sunset: DateTime(2026, 6, 10, 20, 30),
        astronomicalDusk: now.add(const Duration(hours: 1, minutes: 23)),
        astronomicalDawn: DateTime(2026, 6, 11, 4, 0),
      );

      final fact =
          resolveNightContext(twilight, now, clock: const SystemClock());

      expect(fact, isNotNull);
      expect(fact!.kind, NightContextKind.beforeDark);
      expect(fact.l10nKey, 'darkIn');
      expect(fact.time, '1h 23m');
    });

    test('during astronomical darkness → "Dark ... left" until dawn', () {
      final twilight = TwilightTimes(
        sunset: DateTime(2026, 6, 10, 20, 30),
        // Dusk already passed (one hour ago), dawn is 4h12m out.
        astronomicalDusk: now.subtract(const Duration(hours: 1)),
        astronomicalDawn: now.add(const Duration(hours: 4, minutes: 12)),
      );

      final fact =
          resolveNightContext(twilight, now, clock: const SystemClock());

      expect(fact, isNotNull);
      expect(fact!.kind, NightContextKind.duringDark);
      expect(fact.l10nKey, 'darkLeft');
      expect(fact.time, '4h 12m');
    });

    test('after dawn / daytime → next sunset clock time', () {
      final twilight = TwilightTimes(
        sunset: DateTime(2026, 6, 10, 20, 14),
        // Both dusk and dawn are in the past relative to `now`.
        astronomicalDusk: now.subtract(const Duration(hours: 10)),
        astronomicalDawn: now.subtract(const Duration(hours: 5)),
      );

      final fact =
          resolveNightContext(twilight, now, clock: const SystemClock());

      expect(fact, isNotNull);
      expect(fact!.kind, NightContextKind.afterDark);
      expect(fact.l10nKey, 'sunsetAt');
      expect(fact.time, '20:14');
    });

    // The only clock FACE on this chip. It formatted the raw DateTime, so it
    // stayed on the host's zone while the status bar, the dashboard header
    // clock and the night timeline directly beside it all honoured
    // Settings -> Location -> Timezone: the same screen showing two zones.
    test('the sunset face follows the chosen site timezone', () {
      final twilight = TwilightTimes(
        // 20:14 UTC.
        sunset: DateTime.utc(2026, 6, 10, 20, 14),
        astronomicalDusk: now.subtract(const Duration(hours: 10)),
        astronomicalDawn: now.subtract(const Duration(hours: 5)),
      );

      final tokyo = resolveNightContext(
        twilight,
        now,
        clock: const FixedOffsetClock(
          utcOffset: Duration(hours: 9),
          label: 'UTC+09:00',
        ),
      );
      expect(tokyo!.time, '05:14');

      final utc = resolveNightContext(
        twilight,
        now,
        clock: const FixedOffsetClock(utcOffset: Duration.zero, label: 'UTC'),
      );
      expect(utc!.time, '20:14');
    });

    test('sub-hour countdown drops the hours component', () {
      final twilight = TwilightTimes(
        astronomicalDusk: now.add(const Duration(minutes: 7)),
        astronomicalDawn: DateTime(2026, 6, 11, 4, 0),
      );

      final fact =
          resolveNightContext(twilight, now, clock: const SystemClock());

      expect(fact!.kind, NightContextKind.beforeDark);
      expect(fact.time, '7m');
    });

    test('no twilight data (no location) → null so the chip self-hides', () {
      const twilight = TwilightTimes(); // all fields null

      expect(resolveNightContext(twilight, now, clock: const SystemClock()),
          isNull);
    });

    test('after dark with no sunset value → null (nothing to show)', () {
      final twilight = TwilightTimes(
        astronomicalDusk: now.subtract(const Duration(hours: 10)),
        astronomicalDawn: now.subtract(const Duration(hours: 5)),
        // sunset intentionally null
      );

      expect(resolveNightContext(twilight, now, clock: const SystemClock()),
          isNull);
    });

    test('exactly at dusk counts as during-darkness, not before', () {
      final twilight = TwilightTimes(
        astronomicalDusk: now, // dusk == now (not "after now")
        astronomicalDawn: now.add(const Duration(hours: 5)),
      );

      final fact =
          resolveNightContext(twilight, now, clock: const SystemClock());

      expect(fact!.kind, NightContextKind.duringDark);
      expect(fact.l10nKey, 'darkLeft');
      expect(fact.time, '5h 0m');
    });
  });

  group('gradeRms thresholds', () {
    test('null RMS (not guiding) → null grade', () {
      expect(gradeRms(null), isNull);
    });

    test('sub-arcsecond is good', () {
      expect(gradeRms(0.0), RmsGrade.good);
      expect(gradeRms(0.5), RmsGrade.good);
      expect(gradeRms(0.99), RmsGrade.good);
    });

    test('1.0"–2.0" inclusive is fair', () {
      expect(gradeRms(1.0), RmsGrade.fair);
      expect(gradeRms(1.5), RmsGrade.fair);
      expect(gradeRms(2.0), RmsGrade.fair);
    });

    test('above 2.0" is poor', () {
      expect(gradeRms(2.01), RmsGrade.poor);
      expect(gradeRms(5.0), RmsGrade.poor);
    });
  });
}
