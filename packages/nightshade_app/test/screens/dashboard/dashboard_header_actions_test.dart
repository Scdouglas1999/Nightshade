// Regression: "Edit Dashboard" must not offer to arrange a dashboard the user
// cannot see.
//
// With zero devices connected the dashboard shows the standby briefing —
// TONIGHT'S BRIEFING, the twilight bar, Tonight's targets, Readiness, Last run,
// Moon. Pressing Edit Dashboard replaced all of it with a different set of six
// cockpit tiles (Target, Live frame, Guiding, Equipment, Safety, Recent events),
// none of which were on the page, and offered to arrange those. Pressing Done
// brought the briefing back. So in that state there was no way to configure any
// tile the dashboard actually showed.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/widgets/dashboard_header_actions.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

Future<void> _pumpActions(WidgetTester tester, {required bool standby}) async {
  await pumpAppScreen(
    tester,
    DashboardHeaderActions(
      isEditing: false,
      onToggleEdit: () {},
      onManageWidgets: () {},
      onResetLayout: () {},
    ),
    settle: false,
    extraOverrides: [
      dashboardStandbyProvider.overrideWithValue(standby),
    ],
  );
  await tester.pump(const Duration(milliseconds: 100));
}

bool _editIsEnabled(WidgetTester tester) =>
    tester.widget<NightshadeButton>(find.byType(NightshadeButton)).onPressed !=
    null;

void main() {
  testWidgets('editing is refused while the briefing is showing',
      (tester) async {
    await _pumpActions(tester, standby: true);

    expect(_editIsEnabled(tester), isFalse);
    expect(
      find.byTooltip(
        'Nothing to arrange yet — the briefing has no tiles. Connect a device '
        'or load a sequence to arrange the session dashboard.',
      ),
      findsOneWidget,
      reason: 'a control that refuses has to say why',
    );
  });

  testWidgets('editing is offered once the cockpit tiles are on screen',
      (tester) async {
    await _pumpActions(tester, standby: false);

    expect(_editIsEnabled(tester), isTrue);
  });
}
