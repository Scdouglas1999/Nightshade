// Regression: the Dashboard header clock chip must not state a local sidereal
// time for a site the operator never gave it.
//
// This is the SECOND surface named by the same finding that produced
// `screens/shell/status_bar_lst_test.dart`. The evidence recorded both — "the
// header clock chip read 'LST 12:16:27' and the status bar read 'LST 12:16'" —
// while the widgets beside them correctly said "Set an observing location" and
// rendered moonrise/moonset as "--:--". Only the status bar was fixed at the
// time, so the header kept asserting Greenwich's sidereal time as fact.
//
// `localSiderealTimeProvider` reads the planetarium's observer, whose default is
// not the operator's site, so an unconfigured rig produced a perfectly
// well-formed number that belonged to somebody else. LST is exactly what an
// imager reads to decide what is transiting, which is why a confident wrong
// value is worse here than a dash.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/dashboard_header_actions.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

/// A perfectly valid sidereal time that belongs to the planetarium's DEFAULT
/// observer rather than to this operator. The chip must refuse to present it as
/// theirs.
List<Override> _overrides() => [
      localSiderealTimeProvider.overrideWithValue(12.5),
    ];

/// Tear down the widget tree AND the container.
///
/// [ObservationTimeNotifier] starts a 1-second periodic timer in its constructor
/// and cancels it only in `dispose`. That timer belongs to the PROVIDER, not to
/// the widget, so unmounting the tree alone leaves it pending and trips the
/// binding's `!timersPending` invariant. (The sibling status-bar test needs none
/// of this because `StatusBar` receives `now` as a parameter and never reads the
/// provider.)
Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  container.dispose();
}

void main() {
  /// The default test settings carry the documented 0/0 "not set" sentinel, so
  /// no override is needed to model an unconfigured rig — that is the state a
  /// fresh install is actually in.
  testWidgets(
    'with no observing site the header clock shows LST --:--:--, not a number',
    (tester) async {
      final handle = await pumpAppScreen(
        tester,
        Builder(
          builder: (context) => DashboardClockWidget(
            colors: NightshadeColors.of(context),
          ),
        ),
        size: const Size(1600, 900),
        extraOverrides: _overrides(),
        // The chip ticks a 1-second clock; pumpAndSettle would never return.
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('LST --:--:--'),
        findsOneWidget,
        reason: 'an unconfigured site must read as unknown',
      );
      expect(
        find.text('LST 12:30:00'),
        findsNothing,
        reason: "the default observer's sidereal time must not be presented as "
            "the operator's",
      );
      expect(tester.takeException(), isNull);

      await _teardown(tester, handle.container);
    },
  );

  testWidgets(
      'a dash explains itself in the tooltip rather than looking broken',
      (tester) async {
    final handle = await pumpAppScreen(
      tester,
      Builder(
        builder: (context) => DashboardClockWidget(
          colors: NightshadeColors.of(context),
        ),
      ),
      size: const Size(1600, 900),
      extraOverrides: _overrides(),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 50));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      contains('No observing site set'),
      reason: 'a bare "--:--:--" reads as a bug unless it says why',
    );
    expect(
      tooltip.message,
      contains('Settings'),
      reason: 'the empty state has to name the fix, not just the problem',
    );

    await _teardown(tester, handle.container);
  });
}
