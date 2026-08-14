// CON-61: the shell chrome is absent from the accessibility tree.
//
// Live evidence (waveD-equipment-shell.md, waveD-consistency.md): on the
// running Linux bundle, `tree --all` on any screen contains ZERO title-bar
// nodes and ZERO nav-rail destinations — `grep -icE
// "minimize|maximize|close window|transient|settings"` returns 0 — while the
// dashboard's own content and the alert popup ARE exposed. Settings is
// therefore unreachable to assistive tech, which is what made it a P2.
//
// This file settles which layer is at fault by asserting on the COMPILED
// SemanticsNode tree (not on widget properties) for the exact arrangement the
// desktop shell builds: title bar on top, nav rail beside the content. If the
// labels are here, the Flutter side is doing its job and the loss is below it
// (the GTK/AT-SPI bridge in the engine), which is out of this repo's reach.
//
// It also pins the half that WAS missing in-widget: the rail's collapse
// button was a bare GestureDetector with no role and no name.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/side_navigation.dart';
import 'package:nightshade_app/screens/shell/widgets/title_bar.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/pump_app_screen.dart';

/// The real alert stream opens a 15-minute polling timer that outlives the
/// widget tree; the chrome only cares that it resolves.
final _quietAlerts = <Override>[
  activeTransientAlertsProvider.overrideWith(
    (ref) => Stream.value(const <TransientAlert>[]),
  ),
];

/// Every label in the compiled semantics tree, in traversal order.
List<String> _semanticsLabels(WidgetTester tester) {
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return const <String>[];
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return labels;
}

/// Flutter merges a labelled ancestor with the Text inside it into ONE node
/// whose label is both strings joined by a newline ("Collapse navigation\nCollapse").
/// Match on containment so a control that also renders its word on screen is
/// not reported missing.
Matcher _publishes(String label) => predicate<List<String>>(
      (labels) => labels.any((l) => l.contains(label)),
      'publishes a semantics label containing "$label"',
    );

void main() {
  testWidgets('the collapse button names itself and its action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      SideNavigation(
        currentIndex: 0,
        onTabSelected: (_) {},
        isExpanded: true,
        onToggleExpanded: () {},
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(_semanticsLabels(tester), _publishes('Collapse navigation'));

    semantics.dispose();
  });

  testWidgets('a collapsed rail still names the control that expands it',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      SideNavigation(
        currentIndex: 0,
        onTabSelected: (_) {},
        isExpanded: false,
        onToggleExpanded: () {},
      ),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Collapsed, the glyph has no text beside it at all — this label is the
    // only thing that names it.
    expect(_semanticsLabels(tester), _publishes('Expand navigation'));

    semantics.dispose();
  });

  testWidgets('the desktop chrome column publishes title bar and rail alike',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      Column(
        children: [
          const TitleBar(),
          Expanded(
            child: Row(
              children: [
                SideNavigation(
                  currentIndex: 0,
                  onTabSelected: (_) {},
                  isExpanded: true,
                  onToggleExpanded: () {},
                ),
                const Expanded(child: Center(child: Text('Routed content'))),
              ],
            ),
          ),
        ],
      ),
      settle: false,
      extraOverrides: _quietAlerts,
      size: const Size(1600, 900),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final labels = _semanticsLabels(tester);
    // The title-bar icons the live tree could not find.
    expect(labels, _publishes('Settings'));
    expect(labels, _publishes('Equipment Profiles'));
    // A nav destination and the rail's own control.
    expect(labels, _publishes('Dashboard'),
        reason: 'the rail must publish its destinations');
    expect(labels, _publishes('Collapse navigation'));
    // And the routed content, so the assertion above is not vacuous.
    expect(labels, _publishes('Routed content'));

    semantics.dispose();
  });

  testWidgets('window controls reach the compiled tree beside the rail',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      Column(
        children: [
          const TitleBar(),
          Expanded(
            child: SideNavigation(
              currentIndex: 0,
              onTabSelected: (_) {},
              isExpanded: true,
              onToggleExpanded: () {},
            ),
          ),
        ],
      ),
      settle: false,
      extraOverrides: _quietAlerts,
      size: const Size(1600, 900),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final labels = _semanticsLabels(tester);
    // WindowControls only render on a desktop window; on the test host
    // (Platform.isLinux) they do, and this is the exact string the live audit
    // grepped for and did not find.
    expect(labels, _publishes('Close window'));

    semantics.dispose();
  });
}
