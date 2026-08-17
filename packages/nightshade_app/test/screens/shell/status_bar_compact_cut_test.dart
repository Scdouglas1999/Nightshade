// The phone status strip must not slice a chip in half and say nothing.
//
// At 430x900 the bottom strip renders `Idle | <rig> 4/4 | camera | mount |
// guider |` and then the next chip is bisected by the window edge. The strip
// does scroll — it has always been a horizontal SingleChildScrollView — but
// nothing on screen says so: no fade, no truncation mark, no control. A
// bisected focuser glyph reads as a rendering fault, and the readouts past it
// (Focus, the temperature chip, the clock) look absent rather than off-screen.
//
// The desktop bar solved exactly this and the phone bar was left out of the
// fix. So the contract asserted here is the desktop one, at phone width: while
// content is hidden past the right edge the cut carries a visible mark and a
// control that reaches it, and when nothing is hidden neither is drawn.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../harness/pump_app_screen.dart';

Finder _strip() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.byType(Scrollable),
    );

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_strip().first).position;

Finder _cutMarker() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.text('…'),
    );

Future<void> _pumpBar(WidgetTester tester, Size size) async {
  await pumpAppScreen(
    tester,
    const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [StatusBar(compact: true)],
    ),
    size: size,
    extraOverrides: [localSiderealTimeProvider.overrideWithValue(12.5)],
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _disposeBar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  // The refuter's exact window.
  testWidgets('at 430x900 the phone strip says where it is cut',
      (tester) async {
    await _pumpBar(tester, const Size(430, 900));

    expect(tester.takeException(), isNull);
    expect(
      _position(tester).maxScrollExtent,
      greaterThan(0),
      reason: 'the premise of the finding: the strip does not fit 430 px',
    );
    expect(
      _cutMarker(),
      findsOneWidget,
      reason: 'a chip sliced by the window edge must be marked as truncated',
    );
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
      reason: 'the edge fade is what says the slice is a cut, not a fault',
    );

    // Flush against the viewport's right edge, on the outside: inside, it
    // would scroll away with the very chip it describes.
    final strip = tester.getRect(_strip().first);
    final marker = tester.getRect(_cutMarker());
    expect(marker.left, greaterThanOrEqualTo(strip.right - 0.5));
    expect(marker.left, lessThan(strip.right + 12));

    await _disposeBar(tester);
  });

  testWidgets('the phone strip offers a control that reaches the rest',
      (tester) async {
    await _pumpBar(tester, const Size(430, 900));
    expect(_position(tester).maxScrollExtent, greaterThan(0));

    final affordance = find.bySemanticsLabel('More equipment status');
    expect(affordance, findsOneWidget, reason: 'a fade alone is not a control');

    final before = _position(tester).pixels;
    await tester.tap(affordance);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(before));

    await _disposeBar(tester);
  });

  testWidgets('the affordance is inside the window, not sliced in its turn',
      (tester) async {
    await _pumpBar(tester, const Size(430, 900));

    final barRect = tester.getRect(find.byType(StatusBar));
    final affordance =
        tester.getRect(find.bySemanticsLabel('More equipment status'));
    expect(affordance.right, lessThanOrEqualTo(barRect.right + 0.5));
    expect(affordance.left, greaterThanOrEqualTo(barRect.left - 0.5));

    await _disposeBar(tester);
  });

  testWidgets('scrolled to the end, neither the mark nor the fade is drawn',
      (tester) async {
    await _pumpBar(tester, const Size(430, 900));
    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(0));

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pump();

    expect(
      _cutMarker(),
      findsNothing,
      reason: 'nothing is cut off once the strip is scrolled to its end',
    );
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
      reason: 'a fade over complete content is a false affordance',
    );
    // The way back is still offered.
    expect(find.bySemanticsLabel('More equipment status'), findsOneWidget);

    await _disposeBar(tester);
  });

  testWidgets('a compact strip with room shows no mark and no control',
      (tester) async {
    await _pumpBar(tester, const Size(2600, 900));

    expect(_position(tester).maxScrollExtent, 0);
    expect(_cutMarker(), findsNothing);
    expect(find.bySemanticsLabel('More equipment status'), findsNothing);

    await _disposeBar(tester);
  });
}
