import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The Tonight screen's primary action — "Image this target tonight" — renders
/// dimmed and does nothing when no target has been picked, which is correct
/// (`onPressed: (hasPick && !state.isBusy) ? onGo : null`). Driving the running
/// desktop app on 2026-08-10, the accessibility tree nonetheless listed it as a
/// plain enabled button, with no disabled marker of the kind the same tree
/// prints for other controls (`Sort: Score [DISABLED]`), and pressing it
/// produced no feedback at all.
///
/// This pins what the widget actually publishes, because an AT-SPI tree read is
/// good for finding candidates and bad for confirming them.
void main() {
  Future<void> pump(WidgetTester tester, {required bool disabled}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Center(
            child: NightshadeButton(
              label: 'Image this target tonight',
              variant: ButtonVariant.primary,
              size: ButtonSize.large,
              onPressed: disabled ? null : () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a disabled button publishes its disabled state', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, disabled: true);

    final node = tester.getSemantics(find.byType(NightshadeButton));

    expect(
      node.hasFlag(SemanticsFlag.hasEnabledState),
      isTrue,
      reason:
          'without hasEnabledState an assistive client cannot report '
          'enabled or disabled at all',
    );
    expect(
      node.hasFlag(SemanticsFlag.isEnabled),
      isFalse,
      reason:
          'the button does nothing when pressed, so it must not be '
          'announced as actionable',
    );

    handle.dispose();
  });

  testWidgets('an enabled button still reads as enabled', (tester) async {
    // The complement, so the test above cannot pass by the flag simply never
    // being set in either direction.
    final handle = tester.ensureSemantics();
    await pump(tester, disabled: false);

    final node = tester.getSemantics(find.byType(NightshadeButton));

    expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);

    handle.dispose();
  });
}
