// Regression: NightshadeButton must be operable from the keyboard.
//
// The defect: the button was `Semantics > MouseRegion > GestureDetector`. A
// GestureDetector owns no focus node, so the design system's primary button —
// used on essentially every screen — was invisible to Tab traversal and could
// not be activated by Enter or Space.
//
// Observed live in the 13-step first-run wizard at 1400x900: the only control
// Tab could reach was the header's "Skip onboarding" TextButton. Three
// consecutive Tab presses produced a pixel-identical frame (0 differing pixels)
// and pressing Return abandoned setup rather than advancing, so the wizard could
// not be completed without a mouse.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _host(List<Widget> children) => MaterialApp(
  theme: NightshadeTheme.dark,
  home: Scaffold(body: Column(mainAxisSize: MainAxisSize.min, children: children)),
);

void main() {
  testWidgets('Tab reaches the button and Enter activates it', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host([
        NightshadeButton(label: 'Next', onPressed: () => pressed++),
      ]),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(
      Focus.of(tester.element(find.text('Next')), scopeOk: true).hasFocus,
      isTrue,
      reason: 'Tab must be able to land on the button at all',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pressed, 1, reason: 'Enter must activate the focused button');
  });

  testWidgets('Space activates the focused button', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host([
        NightshadeButton(label: 'Save', onPressed: () => pressed++),
      ]),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(pressed, 1);
  });

  testWidgets('Tab walks through every button in order', (tester) async {
    final order = <String>[];
    await tester.pumpWidget(
      _host([
        NightshadeButton(label: 'Back', onPressed: () => order.add('Back')),
        NightshadeButton(label: 'Skip', onPressed: () => order.add('Skip')),
        NightshadeButton(label: 'Next', onPressed: () => order.add('Next')),
      ]),
    );

    // Three tabs, activating each stop, must visit all three buttons — the
    // property the wizard needed and did not have.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    expect(order, ['Back', 'Skip', 'Next']);
  });

  testWidgets('a disabled button is skipped by Tab', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host([
        const NightshadeButton(label: 'Disabled', onPressed: null),
        NightshadeButton(label: 'Enabled', onPressed: () => pressed++),
      ]),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      pressed,
      1,
      reason: 'the first Tab stop must be the enabled button, not the '
          'disabled one, and a disabled button must never fire',
    );
  });
}
