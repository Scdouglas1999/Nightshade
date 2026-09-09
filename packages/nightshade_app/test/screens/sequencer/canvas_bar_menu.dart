// Test helpers for the Sequencer canvas bar's "more" menu.
//
// Wave 3 replaced the 20-icon toolbar with a 44 px canvas bar whose secondary
// actions live behind one overflow menu (06 §Sequencer: "file actions → canvas
// bar `more`"). Tests that used to reach an action with
// `find.byTooltip('Plan Mosaic')` now open the menu first and pick the entry by
// the words it shows.
//
// The anchor is a `NightshadeIconButton`, which renders `NightshadeTooltip`
// rather than Material's `Tooltip`, so `find.byTooltip` does not reach it
// either — match the widget instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The canvas bar's "more actions" button.
///
/// Two shapes, one control: NightshadeIconButton on a pointer platform, and
/// AccessibleIconButton on touch, where the Observatory button's fixed 28 dp
/// box is under Android's 48 dp rule (see the notes' "owed to wave 4").
Finder canvasBarMoreButton() => find.byWidgetPredicate(
      (widget) =>
          (widget is NightshadeIconButton &&
              widget.tooltip == 'More actions') ||
          (widget is AccessibleIconButton && widget.label == 'More actions'),
      description: 'the canvas bar\'s "More actions" button',
    );

/// Opens the canvas bar's overflow menu and settles the popup animation.
Future<void> openCanvasBarMenu(WidgetTester tester) async {
  await tester.tap(canvasBarMoreButton());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// A menu entry by its label. Works whether the menu is open or not — an empty
/// result from a closed menu is the caller forgetting [openCanvasBarMenu].
Finder canvasBarAction(String label) => find.descendant(
      of: find.byType(PopupMenuItem<int>),
      matching: find.text(label),
    );

/// Whether the entry labelled [label] is enabled.
bool canvasBarActionEnabled(WidgetTester tester, String label) {
  final item = tester.widget<PopupMenuItem<int>>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(PopupMenuItem<int>),
    ),
  );
  return item.enabled;
}

/// Opens the menu and taps the entry labelled [label].
Future<void> tapCanvasBarAction(WidgetTester tester, String label) async {
  await openCanvasBarMenu(tester);
  await tester.tap(canvasBarAction(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
