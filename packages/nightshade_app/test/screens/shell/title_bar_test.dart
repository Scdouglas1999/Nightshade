// Regression: the window chrome must be reachable without sight of it.
//
// Observed live: `tree | grep -iE "notification|account|settings|minimi|close"`
// returned nothing from the title bar. None of the four icon buttons and none
// of the three window controls appeared in the accessibility tree at all — an
// InkWell contributes a tap action but no role and no name, and a Tooltip
// contributes a tooltip rather than a label. The Settings gear is the only
// route to Settings, so Settings was unreachable to assistive tech.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/title_bar.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

/// The real alert stream opens a 15-minute polling timer that outlives the
/// widget tree; the title bar only cares that it resolves.
final _quietAlerts = <Override>[
  activeTransientAlertsProvider.overrideWith(
    (ref) => Stream.value(const <TransientAlert>[]),
  ),
];

void main() {
  testWidgets('every title-bar control carries a name and a button role',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      const TitleBar(),
      settle: false,
      extraOverrides: _quietAlerts,
    );
    await tester.pump(const Duration(milliseconds: 200));

    for (final label in const ['Equipment Profiles', 'Settings']) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '"$label" is icon-only chrome and must name itself',
      );
    }
    expect(find.bySemanticsLabel('Transient alerts'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('window controls name themselves', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      Builder(
        builder: (context) =>
            WindowControls(colors: NightshadeColors.of(context)),
      ),
      settle: false,
    );
    await tester.pump();

    for (final label in const ['Minimize', 'Maximize', 'Close window']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }

    semantics.dispose();
  });
}
