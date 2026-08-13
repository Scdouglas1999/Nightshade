// Regression: Glance mode looked like a dead toggle.
//
// Driven live on an idle dashboard: the button lights up blue, its icon flips
// to an open eye, the tree flips `button: Glance mode [off]` -> `[ON]` — and
// nothing else on the page changes at all. The two screenshots differ only in
// the button and the clock, and the state survives navigation still with no
// visible effect. It does have one: it re-sizes the LIVE session readouts,
// which are not on an idle dashboard. A control has to say what it did.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/glance_mode_toggle.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  testWidgets('toggling acknowledges what changed', (tester) async {
    await pumpAppScreen(
      tester,
      Builder(
        builder: (context) =>
            GlanceModeToggle(colors: NightshadeColors.of(context)),
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(GlanceModeToggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Glance mode on — session readouts use the large type.'),
      findsOneWidget,
      reason: 'nothing else on an idle dashboard changes, so the toggle has to '
          'say so itself',
    );
  });

  testWidgets('the tooltip names the effect, not the button state',
      (tester) async {
    await pumpAppScreen(
      tester,
      Builder(
        builder: (context) =>
            GlanceModeToggle(colors: NightshadeColors.of(context)),
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byTooltip(
        'Glance mode — enlarge the session readouts to read across a room',
      ),
      findsOneWidget,
    );
  });
}
