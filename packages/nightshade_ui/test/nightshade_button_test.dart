import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

/// Walks the rendered tree under [finder] and returns the
/// [BoxDecoration] of the AnimatedContainer with a non-null gradient or
/// non-null color. Used to assert filled-button visuals.
BoxDecoration _decorationOf(WidgetTester tester, Finder finder) {
  final container =
      tester.widget<AnimatedContainer>(find.descendant(
    of: finder,
    matching: find.byType(AnimatedContainer),
  ));
  return container.decoration as BoxDecoration;
}

void main() {
  testWidgets('primary button uses gradient fill (not flat translucent)',
      (tester) async {
    await tester.pumpWidget(_wrap(NightshadeButton(
      label: 'Save',
      onPressed: () {},
    )));
    await tester.pump();

    final deco = _decorationOf(tester, find.byType(NightshadeButton));
    expect(deco.gradient, isA<LinearGradient>(),
        reason: 'design doc requires LinearGradient on primary buttons');
    final lg = deco.gradient! as LinearGradient;
    expect(lg.begin, Alignment.topCenter);
    expect(lg.end, Alignment.bottomCenter);
    expect(lg.colors.length, 2);
    // Top color must be lighter than bottom (lighten(5) → primary).
    final topL = HSLColor.fromColor(lg.colors[0]).lightness;
    final bottomL = HSLColor.fromColor(lg.colors[1]).lightness;
    expect(topL, greaterThan(bottomL));
  });

  testWidgets('disabled primary button has no gradient', (tester) async {
    await tester.pumpWidget(_wrap(const NightshadeButton(
      label: 'Save',
      onPressed: null,
    )));
    await tester.pump();
    final deco = _decorationOf(tester, find.byType(NightshadeButton));
    expect(deco.gradient, isNull);
    expect(deco.color, isNotNull);
  });

  testWidgets('hover state changes synchronously and adds glow shadow',
      (tester) async {
    await tester.pumpWidget(_wrap(NightshadeButton(
      label: 'Hover me',
      onPressed: () {},
    )));
    await tester.pump();

    // Pre-hover: no glow.
    var deco = _decorationOf(tester, find.byType(NightshadeButton));
    expect(deco.boxShadow, anyOf(isNull, isEmpty));

    // Simulate hover via the mouse-region gesture.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(NightshadeButton)));
    await tester.pump();

    deco = _decorationOf(tester, find.byType(NightshadeButton));
    expect(deco.boxShadow, isNotNull);
    expect(deco.boxShadow!, isNotEmpty,
        reason: 'hover should add the soft accent glow');
  });

  testWidgets('onPressed fires on tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(NightshadeButton(
      label: 'Click',
      onPressed: () => taps++,
    )));
    await tester.tap(find.byType(NightshadeButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('isLoading suppresses onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(NightshadeButton(
      label: 'Loading',
      isLoading: true,
      onPressed: () => taps++,
    )));
    await tester.tap(find.byType(NightshadeButton));
    // Don't pumpAndSettle — the indeterminate progress indicator never settles.
    await tester.pump();
    expect(taps, 0);
    // Loading indicator visible.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('outline variant renders a non-transparent border on hover',
      (tester) async {
    await tester.pumpWidget(_wrap(NightshadeButton(
      label: 'Outline',
      variant: ButtonVariant.outline,
      onPressed: () {},
    )));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(NightshadeButton)));
    await tester.pump();

    final deco = _decorationOf(tester, find.byType(NightshadeButton));
    final border = deco.border! as Border;
    expect(border.top.color.a, greaterThan(0));
  });

  testWidgets('semantics: button + enabled flag tracks onPressed',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_wrap(const NightshadeButton(
        label: 'DisabledLbl',
        onPressed: null,
      )));
      await tester.pump();
      final semantics = tester.getSemantics(
        find.descendant(
          of: find.byType(NightshadeButton),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'DisabledLbl',
          ),
        ),
      );
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isEnabled, isFalse);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('semantics: enabled when onPressed is set', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_wrap(NightshadeButton(
        label: 'ActiveLbl',
        onPressed: () {},
      )));
      await tester.pump();
      final semantics = tester.getSemantics(
        find.descendant(
          of: find.byType(NightshadeButton),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'ActiveLbl',
          ),
        ),
      );
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isEnabled, isTrue);
    } finally {
      handle.dispose();
    }
  });
}
