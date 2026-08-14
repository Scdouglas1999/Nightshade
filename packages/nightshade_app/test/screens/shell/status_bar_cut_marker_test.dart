// WE-EQ-N5 residual — the pill at the viewport cut is still mangled.
//
// The E-fix capped a dense pill's value at 88 px "so four device pills plus
// the sequence indicator, the equipment indicator and the save-path chip fit a
// 1000 px bar without the strip overflowing into the fade". Wave F drove
// exactly that: `resize 1000 800` with four devices connected. The premise is
// false on screen — the strip DOES overflow and scroll — and the item at the
// cut still read "Si", sliced mid-word, dissolving into the fade with no
// ellipsis (46-narrow.png, 4x crop 49-sb-zoom.png).
//
// So the contract asserted here is not "the strip fits". It is: while there is
// content past the right edge, the cut carries a VISIBLE truncation mark, the
// way an ellipsis inside a pill does — and when there is nothing past the edge,
// neither the mark nor the fade is drawn, because a truncation mark over
// complete content is the same lie in the other direction.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../harness/pump_app_screen.dart';

Finder _pillScroller() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.byType(Scrollable),
    );

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_pillScroller().first).position;

/// The truncation mark drawn at the viewport cut.
Finder _cutMarker() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.text('…'),
    );

Future<void> _pumpBar(WidgetTester tester, Size size) async {
  await pumpAppScreen(
    tester,
    const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [StatusBar()],
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
  testWidgets('at 1000x800 the strip still scrolls — and says where it is cut',
      (tester) async {
    await _pumpBar(tester, const Size(1000, 800));

    expect(
      _position(tester).maxScrollExtent,
      greaterThan(0),
      reason: 'the E-fix premise "the strip fits a 1000 px bar" is false',
    );
    expect(
      _cutMarker(),
      findsOneWidget,
      reason: 'a pill sliced by the viewport must be marked as truncated',
    );

    // It sits at the cut: flush against the scroll viewport's right edge, on
    // the outside, so it reads as the end of the sliced pill rather than as
    // another readout.
    final scroller = tester.getRect(_pillScroller().first);
    final marker = tester.getRect(_cutMarker());
    expect(marker.left, greaterThanOrEqualTo(scroller.right - 0.5));
    expect(marker.left, lessThan(scroller.right + 12));

    await _disposeBar(tester);
  });

  testWidgets('scrolled to the end, neither the mark nor the fade is drawn',
      (tester) async {
    await _pumpBar(tester, const Size(1000, 800));
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

  testWidgets('a bar with room shows no cut mark', (tester) async {
    await _pumpBar(tester, const Size(2600, 900));
    expect(_position(tester).maxScrollExtent, 0);
    expect(_cutMarker(), findsNothing);

    await _disposeBar(tester);
  });
}
