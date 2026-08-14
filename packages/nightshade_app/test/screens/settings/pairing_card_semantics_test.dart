// WE-SP-3 / WE-SP-4, from the live pairing walk.
//
// WE-SP-3: with no paired devices the instruction "Start pairing mode to
// connect a device" was painted in `colorScheme.outline` — a border colour. On
// the captured frame its brightest glyph pixel measured rgb(43,49,59) against a
// rgb(24,28,34) card: 1.31:1, where AA body text needs 4.5:1.
//
// WE-SP-4: while pairing mode ran, the whole card collapsed into ONE semantics
// node with role button, named by four unrelated strings —
// "Pair New Device / Enter this code on your device: / Expires in 04:53 /
// Cancel Pairing" — and the copy-the-code control had no accessible node, no
// name, and produced no visible change when clicked.
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/pairing_screen.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

Future<void> _pumpPairing(
  WidgetTester tester,
  PairingNotifier notifier,
) async {
  await pumpAppScreen(
    tester,
    const PairingScreen(),
    size: const Size(1200, 1600),
    extraOverrides: [
      pairingProvider.overrideWith((ref) => notifier),
    ],
  );
}

List<SemanticsData> _tree(WidgetTester tester) {
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final out = <SemanticsData>[];
  void visit(SemanticsNode node) {
    out.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  double channel(double c) {
    final s = c / 255.0;
    return s <= 0.03928 ? s / 12.92 : _pow((s + 0.055) / 1.055, 2.4);
  }

  double luminance(Color c) =>
      0.2126 * channel((c.r * 255).roundToDouble()) +
      0.7152 * channel((c.g * 255).roundToDouble()) +
      0.0722 * channel((c.b * 255).roundToDouble());

  final la = luminance(a);
  final lb = luminance(b);
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

double _pow(double x, double exp) => x <= 0 ? 0 : math.pow(x, exp).toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the empty-state instruction is readable', (tester) async {
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final notifier = PairingNotifier.withDatabase(database);
    await notifier.loadPairedDevices();

    await _pumpPairing(tester, notifier);
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(
      find.text('Start pairing mode to connect a device'),
    );
    final context = tester.element(
      find.text('Start pairing mode to connect a device'),
    );
    final colors = NightshadeColors.of(context);
    final colour = text.style!.color!;

    expect(
      colour,
      isNot(Theme.of(context).colorScheme.outline),
      reason: 'outline is a border colour, not a text colour',
    );
    expect(
      _contrast(colour, colors.surface),
      greaterThanOrEqualTo(4.5),
      reason: 'it measured 1.31:1 on the live frame',
    );
  });

  testWidgets('the live pairing card does not collapse into one button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final notifier = PairingNotifier.withDatabase(database);
    expect(await notifier.startPairing(), isTrue);

    await _pumpPairing(tester, notifier);
    await tester.pumpAndSettle();

    final tree = _tree(tester);

    // No single node may be BOTH a button and the carrier of the card's prose.
    final collapsed = tree.where((d) =>
        d.hasFlag(SemanticsFlag.isButton) &&
        d.label.contains('Enter this code on your device'));
    expect(
      collapsed,
      isEmpty,
      reason: 'one "button" named by four unrelated sentences is not a control',
    );

    // The copy control is a named button of its own.
    expect(
      tree.any((d) =>
          d.hasFlag(SemanticsFlag.isButton) && d.label.contains('Copy code')),
      isTrue,
      reason: 'it had no accessible node at all',
    );

    // ...and pressing it changes something the operator can see.
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pairing code copied to clipboard'),
      findsWidgets,
      reason: 'two screenshots either side of the click were identical',
    );

    // Let the in-place confirmation expire, then tear the tree down so the
    // binding's pending-timer invariant sees a clean slate.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Copy code'), findsOneWidget);

    // The live code runs a one-second expiry ticker; end it before the
    // binding's pending-timer invariant runs.
    await notifier.cancelPairing();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    handle.dispose();
  });

  // WF-SS-N1: the button WE-SP-4 introduced was painted worse than the
  // empty-state WE-SP-3 fixed. `ButtonVariant.ghost` draws its label in
  // `textSecondary` rgb(154,163,173) and paints no fill until hover, so the
  // only copy affordance sat directly on the card's `primaryContainer` fill
  // rgb(91,158,196) at 1.15:1 — a legible confirmation chip AFTER the click,
  // and a disabled-looking ghost before it.
  testWidgets('the copy-code label is readable where it sits', (tester) async {
    final database = PairingDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final notifier = PairingNotifier.withDatabase(database);
    expect(await notifier.startPairing(), isTrue);

    await _pumpPairing(tester, notifier);
    await tester.pumpAndSettle();

    final labelFinder = find.text('Copy code');
    final context = tester.element(labelFinder);
    final ink = tester.widget<Text>(labelFinder).style!.color!;

    // Whatever is actually behind the glyphs: the button's own fill when it
    // paints one, otherwise the card it sits on.
    final buttonFill = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.ancestor(
              of: labelFinder,
              matching: find.byType(NightshadeButton),
            ),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .firstWhere((c) => c != null && c.a > 0.99, orElse: () => null);
    final behind = buttonFill ?? Theme.of(context).colorScheme.primaryContainer;

    expect(
      _contrast(ink, behind),
      greaterThanOrEqualTo(4.5),
      reason: 'it measured 1.15:1 on the live frame, idle state',
    );

    await notifier.cancelPairing();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
