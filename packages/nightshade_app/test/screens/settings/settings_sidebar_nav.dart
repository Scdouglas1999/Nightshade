// Shared sidebar navigation for the SettingsScreen widget tests.
//
// Every settings test that opens a section has to drive the same grouped,
// collapsible, lazily-built sidebar, and several of them had grown their own
// copy of the helper — each carrying the same defect.
//
// THE DEFECT. `tester.scrollUntilVisible` finishes with an un-awaited
// `Scrollable.ensureVisible` and never pumps:
//
//   while (maxIteration > 0 && finder.evaluate().isEmpty) { drag; pump; }
//   await Scrollable.ensureVisible(finder.evaluate().single);   // <- no pump
//
// so on return the ScrollPosition has already jumped to its new offset while
// the render tree still holds the OLD one. `tester.tap` then reads the stale
// RenderBox centre. Measured on the real screen at 1280x800: the sidebar
// viewport was 110..597, the position had moved to its 186px maximum, but the
// "AUTOMATION & SAFETY" header still reported its unscrolled rect, centre
// (129.5, 606) — 9px below the viewport clip. The tap silently landed on the
// page background, the group never expanded, and the test failed later and
// somewhere else, looking like a layout regression.
//
// It only ever worked by luck. With 28px-tall buttons the same stale centre
// (606) happened to fall inside a 617-deep viewport; raising the shared button
// to the 48px touch-target floor moved the viewport bottom to 597 and the luck
// ran out. The row height is not the bug — reading geometry before pumping is.
//
// Also note the loop exits on `finder.evaluate().isEmpty`, i.e. as soon as the
// row EXISTS. A lazy ListView builds rows a little beyond the viewport, so
// "exists" does not mean "inside the clip"; the explicit ensureVisible below is
// what actually reveals it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/tutorial_keys/settings_keys.dart';

/// The sidebar's scrollable (the keyed grouped ListView). Targeting it
/// explicitly avoids grabbing a Scrollable inside the detail pane.
Finder get settingsSidebar => find.descendant(
      of: find.byKey(SettingsTutorialKeys.categories),
      matching: find.byType(Scrollable),
    );

/// Scrolls the sidebar until [target] is not merely built but fully inside the
/// viewport, and leaves the render tree in sync with the final scroll offset.
///
/// Safe to call at any row height and any surface size: nothing here assumes
/// the row is already on screen, or that the list is short enough to fit.
Future<void> revealInSettingsSidebar(
  WidgetTester tester,
  Finder target,
) async {
  await tester.scrollUntilVisible(target, 100, scrollable: settingsSidebar);
  // Flush the jump scrollUntilVisible performed but never pumped.
  await tester.pumpAndSettle();
  // ...then actually reveal it, since "built" != "inside the clip".
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

/// Reveals [target] in the sidebar and taps it.
///
/// A missed tap is made FATAL here rather than a console warning. These tests
/// exist to prove a user can reach a setting; a tap that sails past the row and
/// lands on the page background proves the opposite, and letting it pass
/// silently is how the stale-geometry defect above stayed hidden.
Future<void> tapInSettingsSidebar(
  WidgetTester tester,
  Finder target, {
  Duration settle = const Duration(milliseconds: 300),
}) async {
  await revealInSettingsSidebar(tester, target);
  WidgetController.hitTestWarningShouldBeFatal = true;
  await tester.tap(target);
  await tester.pumpAndSettle(settle);
}

/// Expands a collapsed sidebar group by its (upper-cased) header. Expanding an
/// earlier group lengthens the list, so a later group's header can start below
/// the fold — hence the reveal.
Future<void> expandSettingsGroup(
  WidgetTester tester,
  String groupTitle,
) async {
  await tapInSettingsSidebar(tester, find.text(groupTitle.toUpperCase()));
}

/// Selects a section row (its group must already be expanded).
Future<void> selectSettingsSection(
  WidgetTester tester,
  String sectionLabel,
) async {
  await tapInSettingsSidebar(
    tester,
    find.text(sectionLabel).first,
    settle: const Duration(seconds: 1),
  );
}
