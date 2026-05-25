import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('clampPanelWidth', () {
    test('clamps fraction of available space', () {
      expect(
        clampPanelWidth(1000, fraction: 0.25, min: 200, max: 400),
        250,
      );
    });

    test('respects minimum', () {
      expect(
        clampPanelWidth(400, fraction: 0.1, min: 200, max: 500),
        200,
      );
    });

    test('respects maximum', () {
      expect(
        clampPanelWidth(2000, fraction: 0.5, min: 100, max: 400),
        400,
      );
    });
  });

  group('dialogMaxWidth', () {
    testWidgets('returns design max when viewport is wide enough',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late double width;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              width = dialogMaxWidth(context, 900);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(width, 900);
    });

    testWidgets('caps design max at 92% of viewport', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late double width;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              width = dialogMaxWidth(context, 900);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(width, closeTo(736, 0.01));
    });
  });

  group('ShellChromeMetrics', () {
    test('shell layout breakpoint matches tablet token', () {
      expect(
        ShellChromeMetrics.shellLayoutBreakpoint,
        NightshadeTokens.breakpointTablet,
      );
    });

    test('bottom nav height is tokenized', () {
      expect(BottomNavMetrics.barHeight, 78.0);
    });

    test('bottom nav item metrics are tokenized', () {
      expect(BottomNavMetrics.itemIconSize, 18.0);
      expect(BottomNavMetrics.itemLabelFontSize, 10.0);
      expect(
        BottomNavMetrics.itemSelectionAnimationDuration,
        const Duration(milliseconds: 180),
      );
    });

    test('content stack bottom chrome sums status bar and nav', () {
      expect(
        ShellChromeMetrics.contentStackBottomChromeHeight(useBottomNav: false),
        ShellChromeMetrics.statusBarHeight,
      );
      expect(
        ShellChromeMetrics.contentStackBottomChromeHeight(useBottomNav: true),
        ShellChromeMetrics.statusBarHeightCompact +
            BottomNavMetrics.barHeight,
      );
    });
  });
}
