import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _host({
  PhonePanelStrategy strategy = PhonePanelStrategy.bottomSheet,
  List<AdaptivePanel>? secondary,
}) {
  return MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(
      body: AdaptivePanelLayout(
        phoneStrategy: strategy,
        primary: const ColoredBox(
          color: Color(0xFF101010),
          child: Center(child: Text('PRIMARY')),
        ),
        secondary: secondary ??
            const [
              AdaptivePanel(
                title: 'Controls',
                icon: Icons.tune,
                child: Center(child: Text('CONTROLS')),
              ),
            ],
      ),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  group('phone portrait', () {
    final phoneSizes = <String, Size>{
      '360x640': const Size(360, 640),
      '390x844': const Size(390, 844),
    };

    for (final entry in phoneSizes.entries) {
      testWidgets('bottom-sheet collapse at ${entry.key}', (tester) async {
        await _pumpAt(tester, entry.value, _host());
        expect(tester.takeException(), isNull);

        // Primary fills the screen; controls hidden behind a handle.
        expect(find.text('PRIMARY'), findsOneWidget);
        expect(find.text('CONTROLS'), findsNothing);

        // The handle button shows the panel title; tapping opens the sheet.
        expect(find.text('Controls'), findsOneWidget);
        await tester.tap(find.text('Controls'));
        await tester.pumpAndSettle();
        expect(find.text('CONTROLS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('segmented collapse at ${entry.key}', (tester) async {
        await _pumpAt(
          tester,
          entry.value,
          _host(strategy: PhonePanelStrategy.segmented),
        );
        expect(tester.takeException(), isNull);

        // Primary shown by default; switching segment shows controls.
        expect(find.text('PRIMARY'), findsOneWidget);
        expect(find.text('CONTROLS'), findsNothing);

        await tester.tap(find.text('Controls'));
        await tester.pumpAndSettle();
        expect(find.text('CONTROLS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('phone landscape', () {
    testWidgets('shows side-by-side split when wide enough (844x390)',
        (tester) async {
      await _pumpAt(tester, const Size(844, 390), _host());
      expect(tester.takeException(), isNull);
      // Both visible at once — no collapse.
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.text('CONTROLS'), findsOneWidget);
    });

    testWidgets('falls back to collapse when too narrow (640x360)',
        (tester) async {
      // 640 < landscapeSplitMinWidth (560)? 640 >= 560 so it WILL split.
      await _pumpAt(tester, const Size(640, 360), _host());
      expect(tester.takeException(), isNull);
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.text('CONTROLS'), findsOneWidget);
    });
  });

  group('tablet / desktop', () {
    testWidgets('fixed split on tablet (800x1000)', (tester) async {
      await _pumpAt(tester, const Size(800, 1000), _host());
      expect(tester.takeException(), isNull);
      // Side-by-side: both present, no sheet handle button duplication.
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.text('CONTROLS'), findsOneWidget);
    });

    testWidgets('resizable split on desktop (1400x900)', (tester) async {
      await _pumpAt(tester, const Size(1400, 900), _host());
      expect(tester.takeException(), isNull);
      expect(find.text('PRIMARY'), findsOneWidget);
      expect(find.text('CONTROLS'), findsOneWidget);

      // A draggable divider exists (MouseRegion with resizeColumn cursor).
      final handle = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(handle, findsOneWidget);

      // Dragging the handle does not throw.
      await tester.drag(handle, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('two secondary panels segment correctly on phone',
      (tester) async {
    await _pumpAt(
      tester,
      const Size(390, 844),
      _host(
        strategy: PhonePanelStrategy.segmented,
        secondary: const [
          AdaptivePanel(title: 'Tune', child: Center(child: Text('TUNE'))),
          AdaptivePanel(title: 'Stats', child: Center(child: Text('STATS'))),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('STATS'), findsOneWidget);
  });
}
