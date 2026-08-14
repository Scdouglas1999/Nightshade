// Regression (SKY-16): the planetarium command bar must not tell a desktop
// user to "tap".
//
// Live evidence from the desktop build, driven with a mouse: the coordinate
// mode toggle's tooltip read `Equatorial view — tap for Alt/Az`. Every other
// control in the app either says "click" or names the action; this one named a
// gesture the platform it was rendered on does not have. The fix names the
// action instead of any gesture, which is also the only wording that is true
// for a screen-reader user driving the bar from the keyboard.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/widgets/redesign/command_bar.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  testWidgets('no command-bar tooltip names a touch gesture', (tester) async {
    await pumpAppScreen(
      tester,
      PlanetariumCommandBar(
        compact: false,
        layersOpen: false,
        panelOpen: false,
        showFov: false,
        onToggleLayers: () {},
        onTogglePanel: () {},
        onOpenSearch: () {},
        onToggleFov: () {},
        onResetView: () {},
        onExportChart: () {},
      ),
      size: const Size(1400, 200),
      settle: false,
    );
    await tester.pump();

    final tooltips = tester
        .widgetList<NightshadeTooltip>(find.byType(NightshadeTooltip))
        .map((t) => t.message)
        .toList();

    expect(tooltips, isNotEmpty);
    expect(
      tooltips.where((m) => m.toLowerCase().contains('tap')),
      isEmpty,
      reason: 'this bar is driven with a mouse, a finger and the keyboard',
    );
    // The coordinate toggle still says what pressing it does.
    expect(
      tooltips.where((m) => m.contains('switch to Alt/Az')),
      isNotEmpty,
    );
  });
}
