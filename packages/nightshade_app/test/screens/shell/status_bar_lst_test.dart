// The shell status bar must not state a local sidereal time for a site the
// operator never gave it.
//
// `localSiderealTimeProvider` reads the planetarium's observer, whose default is
// **Los Angeles** (`PlanetariumObserver`), and `locationSyncProvider` only pushes
// the real site once one is configured — its two paths also disagree about the
// documented 0/0 "not set" sentinel, so an unconfigured rig yields either LA's or
// Greenwich's sidereal time. The chip renders that as a crisp "LST 21:14" in the
// accent colour, indistinguishable from a real reading, and LST is precisely what
// an imager reads to decide what is transiting.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';
// `siteLocationIsSet` moved from this widget file to the settings model in
// nightshade_core: a not-set rule living inside a status-bar widget invited
// every other surface to re-derive its own copy, and those copies drifted.
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  group('siteLocationIsSet', () {
    test('0/0 is the not-set sentinel', () {
      expect(siteLocationIsSet(0.0, 0.0), isFalse);
    });

    test('any configured component counts as set', () {
      expect(siteLocationIsSet(40.7, 0.0), isTrue);
      expect(siteLocationIsSet(0.0, -74.0), isTrue);
      expect(siteLocationIsSet(-33.9, 151.2), isTrue);
    });
  });

  group('formatLstChip', () {
    test('an unknown LST is shown as unknown, not as a number', () {
      expect(formatLstChip(null), 'LST --:--');
    });

    test('a known LST is formatted hh:mm', () {
      expect(formatLstChip(12.5), 'LST 12:30');
      expect(formatLstChip(0.0), 'LST 00:00');
      expect(formatLstChip(23.99), 'LST 23:59');
    });

    test('an out-of-range value folds instead of rendering garbage', () {
      expect(formatLstChip(-1.5), 'LST 22:30');
      expect(formatLstChip(25.5), 'LST 01:30');
    });
  });

  testWidgets('with no observing site the bar shows LST --:--, not a number',
      (tester) async {
    await pumpAppScreen(
      tester,
      const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [StatusBar()],
      ),
      size: const Size(2600, 900),
      extraOverrides: [
        // A perfectly valid sidereal time is available — but it belongs to the
        // planetarium's default observer, not to this operator. The bar must
        // refuse to present it as theirs.
        localSiderealTimeProvider.overrideWithValue(12.5),
      ],
      // The bar ticks a 1-second clock; pumpAndSettle would never return.
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.text('LST --:--'),
      ),
      findsOneWidget,
      reason: 'an unconfigured site must read as unknown',
    );
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.text('LST 12:30'),
      ),
      findsNothing,
      reason: "the default observer's sidereal time must not be presented as "
          "the operator's",
    );
    expect(tester.takeException(), isNull);

    // Dispose so the clock timer is cancelled before the binding's timer check.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
