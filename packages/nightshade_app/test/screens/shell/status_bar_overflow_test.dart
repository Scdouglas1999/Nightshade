// Regression: the desktop status bar must not silently cut off its trailing
// readouts in a small window.
//
// Observed live on a virgin install: the bar was a bare `Row` with a `Spacer`,
// so once the pills and readouts exceeded the window width the overflow was
// simply clipped at the right edge — no ellipsis, no scroll, no indication that
// anything was missing. At 1000x700 the clock and LST readouts were gone
// entirely; at 800x600 the save-path chip was cut mid-word ("No s").
//
// The fix gives the device-pill group the slack (and lets it scroll when there
// is none) while the readouts on the right stay pinned and whole. Both halves
// are pinned here: "make it scroll" would be a regression if it also lost the
// right-alignment on a wide window.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../harness/pump_app_screen.dart';

/// The pill group's scroll view — the only Scrollable the bar owns.
Finder _pillScroller() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.byType(Scrollable),
    );

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_pillScroller().first).position;

/// The right-most readout: the clock is always last in the trailing group.
Finder _lastReadout() => find.descendant(
      of: find.byType(StatusBar),
      matching: find.byType(Text),
    );

Future<void> _pumpBar(WidgetTester tester, Size size) async {
  await pumpAppScreen(
    tester,
    // Bottom-align it the way the shell does, so the bar takes its natural
    // height instead of being stretched by the test Scaffold.
    const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [StatusBar()],
    ),
    size: size,
    extraOverrides: [
      // The LST readout pulls in the planetarium's observation-time notifier,
      // whose own 1-second timer outlives the widget tree and trips the
      // binding's end-of-test timer check. The bar's layout does not care what
      // the number is.
      localSiderealTimeProvider.overrideWithValue(12.5),
    ],
    // The bar ticks a 1-second periodic timer for its clock; pumpAndSettle
    // would never return.
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Dispose the tree so the bar's periodic clock timer is cancelled before the
/// binding's end-of-test timer check runs.
Future<void> _disposeBar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('a narrow window scrolls the pills instead of clipping',
      (tester) async {
    await _pumpBar(tester, const Size(800, 600));

    expect(tester.takeException(), isNull);
    expect(_pillScroller(), findsWidgets);
    expect(
      _position(tester).maxScrollExtent,
      greaterThan(0),
      reason: 'pills wider than the slack must be reachable by scrolling, '
          'not cut off at the edge',
    );

    await _disposeBar(tester);
  });

  testWidgets('the trailing readouts stay whole and on-screen when narrow',
      (tester) async {
    await _pumpBar(tester, const Size(800, 600));

    // Every readout in the trailing group is laid out inside the window. This
    // is the property that failed before: the tail of the bar was outside it.
    final barRect = tester.getRect(find.byType(StatusBar));
    final texts = _lastReadout();
    var checked = 0;
    for (var i = 0; i < texts.evaluate().length; i++) {
      final rect = tester.getRect(texts.at(i));
      // Skip anything inside the scrollable pill group — that is allowed to
      // extend past the viewport, because it can be scrolled to.
      final inScroller = find
          .descendant(of: _pillScroller().first, matching: texts.at(i))
          .evaluate()
          .isNotEmpty;
      if (inScroller) continue;
      checked++;
      expect(
        rect.right,
        lessThanOrEqualTo(barRect.right + 0.5),
        reason:
            'trailing readout "${(texts.at(i).evaluate().single.widget as Text).data}" '
            'is cut off at the window edge',
      );
      expect(rect.left, greaterThanOrEqualTo(barRect.left - 0.5));
    }
    expect(checked, greaterThan(0),
        reason: 'no trailing readouts were checked');
    expect(tester.takeException(), isNull);

    await _disposeBar(tester);
  });

  // Scrolling alone was not enough. On a desktop mouse a horizontal scroll view
  // with no scrollbar and no fade is close to undiscoverable, and its viewport
  // edge sliced the pill label mid-word — live at 800x600 the bar read
  // "Mount Dis", which looks like a rendering fault rather than "there is more
  // over here". Below the desktop breakpoint the pills now shed their static
  // label word, which is what buys the room back. The value — the part that
  // actually changes — is never what gets dropped.
  testWidgets('a narrow bar drops pill labels but keeps their values',
      (tester) async {
    await _pumpBar(tester, const Size(800, 600));

    for (final label in ['Camera', 'Mount', 'Guider', 'Focus']) {
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text(label),
        ),
        findsNothing,
        reason: '"$label" is a constant word the icon already conveys; it must '
            'not be spending width in a bar this narrow',
      );
    }
    // The states are still readable.
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.text('Disconnected'),
      ),
      findsWidgets,
      reason: 'the changing value must survive the density change',
    );
    expect(tester.takeException(), isNull);

    await _disposeBar(tester);
  });

  // Shedding the labels is not always enough (a long profile name can still
  // push a pill past the edge). When the group really does overflow the bar
  // must SAY so: a silent cut made "mount pill scrolled out of view" look
  // identical to "no mount configured".
  testWidgets('an overflowing pill group is marked with a fade',
      (tester) async {
    await _pumpBar(tester, const Size(800, 600));
    expect(_position(tester).maxScrollExtent, greaterThan(0));

    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
      reason: 'an overflowing pill group must show an edge fade',
    );

    await _disposeBar(tester);
  });

  testWidgets('a bar with room shows no fade', (tester) async {
    await _pumpBar(tester, const Size(2600, 900));
    expect(_position(tester).maxScrollExtent, 0);

    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
      reason: 'a fade with nothing hidden behind it is a false affordance',
    );

    await _disposeBar(tester);
  });

  testWidgets('a wide bar keeps the pill labels', (tester) async {
    await _pumpBar(tester, const Size(2600, 900));

    for (final label in ['Camera', 'Mount', 'Guider', 'Focus']) {
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text(label),
        ),
        findsWidgets,
        reason: 'a wide bar has room for "$label" and must not be degraded',
      );
    }
    expect(tester.takeException(), isNull);

    await _disposeBar(tester);
  });

  testWidgets('a wide window keeps the trailing group right-aligned',
      (tester) async {
    // Deliberately far wider than any real window: widget tests render with a
    // fixed-width test font, so the same bar that fits 1400 real pixels needs
    // ~1630 test pixels. The point of the case is the has-slack branch, not the
    // specific threshold.
    await _pumpBar(tester, const Size(2600, 900));

    expect(tester.takeException(), isNull);
    expect(
      _position(tester).maxScrollExtent,
      0,
      reason: 'a wide bar must not become scrollable',
    );
    // The pill group absorbs the slack exactly as the Spacer used to, so the
    // readouts stay pinned to the right edge instead of drifting left.
    final barRect = tester.getRect(find.byType(StatusBar));
    final scrollerRect = tester.getRect(_pillScroller().first);
    expect(scrollerRect.left, closeTo(barRect.left, 0.5));

    var rightMost = barRect.left;
    final texts = _lastReadout();
    for (var i = 0; i < texts.evaluate().length; i++) {
      final rect = tester.getRect(texts.at(i));
      if (rect.right > rightMost) rightMost = rect.right;
    }
    expect(
      rightMost,
      greaterThan(barRect.right - 40),
      reason: 'the trailing group is no longer right-aligned '
          '(right-most readout ends at $rightMost, bar ends at ${barRect.right})',
    );

    await _disposeBar(tester);
  });
}
