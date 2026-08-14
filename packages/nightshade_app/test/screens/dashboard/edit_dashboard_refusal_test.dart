// WD-EQ-4: "Edit Dashboard" is silently inert in the standby briefing.
//
// Live evidence (waveD-equipment-shell.md): 0 devices connected, Dashboard
// showing TONIGHT'S BRIEFING, click Edit Dashboard — the page does not change
// and nothing explains why. The only disclosure was a Tooltip, which a
// keyboard or screen-reader user never receives, so the control announced
// itself as an ordinary live button that does nothing.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/widgets/dashboard_header_actions.dart';

import '../../harness/pump_app_screen.dart';

Future<SemanticsNode> _pumpEditButton(
  WidgetTester tester, {
  required bool standby,
}) async {
  await pumpAppScreen(
    tester,
    DashboardHeaderActions(
      isEditing: false,
      onToggleEdit: () {},
      onManageWidgets: () {},
      onResetLayout: () {},
    ),
    settle: false,
    extraOverrides: [dashboardStandbyProvider.overrideWithValue(standby)],
  );
  await tester.pump(const Duration(milliseconds: 200));
  return tester.getSemantics(find.text('Edit Dashboard'));
}

void main() {
  testWidgets('in standby the control is disabled and says why',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final node = await _pumpEditButton(tester, standby: true);

    expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse,
        reason: 'a control that refuses every click must say it is disabled');
    expect(node.hint, contains('Nothing to arrange yet'),
        reason: 'the reason must reach someone who cannot hover');
    expect(standbyEditRefusalReason, contains('Connect a device'));

    semantics.dispose();
  });

  testWidgets('with a live dashboard it is an ordinary enabled button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var toggles = 0;
    await pumpAppScreen(
      tester,
      DashboardHeaderActions(
        isEditing: false,
        onToggleEdit: () => toggles++,
        onManageWidgets: () {},
        onResetLayout: () {},
      ),
      settle: false,
      extraOverrides: [dashboardStandbyProvider.overrideWithValue(false)],
    );
    await tester.pump(const Duration(milliseconds: 200));

    final node = tester.getSemantics(find.text('Edit Dashboard'));
    expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(node.hint, isEmpty);

    await tester.tap(find.text('Edit Dashboard'));
    await tester.pump();
    expect(toggles, 1);

    semantics.dispose();
  });
}
