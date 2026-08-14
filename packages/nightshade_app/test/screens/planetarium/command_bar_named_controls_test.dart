// D-2 (final) + WF-SS-N3: two controls of the planetarium command bar were
// still anonymous to assistive tech, and one of them was the last remaining
// tooltip leak.
//
// Live evidence, `tree --all` on the running desktop app: between
// `button: Equatorial view - switch to Alt/Az` and `button: Layers` sat a bare
// `button: ` (the projection cycler, root x=536), and a second bare `button: `
// (Tools, root x=636). D-3 had named `CommandBarIconButton` from its tooltip;
// these two are `PopupMenuButton`s and were never touched.
//
// The projection one also leaked: hovering it published
// `panel: Projection: Stereographic` under the bare button and that node stayed
// in the tree for the rest of the session — 35 s later, with the command bar
// visibly clean in a screenshot taken at the same instant. That node is
// Material's own `Tooltip`, which the D-2 fix in `nightshade_tooltip.dart`
// could not reach because this control never used `NightshadeTooltip`.
//
// So the bar is pinned on two rules at once: every button in it announces a
// name, and no Material `Tooltip` is mounted inside it.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/widgets/redesign/command_bar.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  testWidgets('every command-bar button announces a name', (tester) async {
    final handle = tester.ensureSemantics();
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

    final labels = <String>[];
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.hasFlag(SemanticsFlag.isButton)) {
        labels.add(data.label);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    // ignore: deprecated_member_use
    visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

    expect(labels, isNotEmpty, reason: 'the bar is made of buttons');
    expect(
      labels.where((label) => label.trim().isEmpty).length,
      0,
      reason: 'a bare `button: ` cannot be identified by anyone using the '
          'keyboard or a screen reader — found ${labels.length} buttons: '
          '$labels',
    );
    expect(
      labels.any((label) => label.startsWith('Projection: ')),
      isTrue,
      reason: 'the projection cycler names the projection it is on',
    );
    expect(
      labels.any((label) => label.trim() == 'Tools'),
      isTrue,
      reason: 'the Tools overflow names itself',
    );

    handle.dispose();
  });

  testWidgets('the command bar mounts no Material tooltip', (tester) async {
    // The D-2 leak's owner: a Material `Tooltip` publishes its message as a
    // semantics node of its own, and the live tree kept that node after the
    // pointer had left. Every message in this bar belongs to `NightshadeTooltip`
    // (which carries it on the trigger) instead.
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

    // Material's `Tooltip` builds its child untouched when the message is
    // empty — no overlay, and no `tooltip` semantics node to strand. A
    // NON-empty one is the leak.
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .where((m) => m.isNotEmpty)
        .toList();
    expect(messages, isEmpty);
  });
}
