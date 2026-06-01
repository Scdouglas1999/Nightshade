import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

const _tabs = [
  AdaptiveTab(label: 'Session', icon: Icons.bar_chart),
  AdaptiveTab(label: 'History', icon: Icons.history),
  AdaptiveTab(label: 'Projects', icon: Icons.folder),
  AdaptiveTab(label: 'Equipment', icon: Icons.settings),
  AdaptiveTab(label: 'Science', icon: Icons.science),
  AdaptiveTab(label: 'Diagnostics', icon: Icons.bug_report),
  AdaptiveTab(label: 'Telemetry', icon: Icons.timeline),
  AdaptiveTab(label: 'Calibration', icon: Icons.tune),
];

Widget _host({int selected = 0, ValueChanged<int>? onSelected}) {
  return MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(
      body: SizedBox(
        height: 48,
        child: AdaptiveTabBar(
          tabs: _tabs,
          selectedIndex: selected,
          onSelected: onSelected ?? (_) {},
        ),
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
  final sizes = <String, Size>{
    '360x640 portrait': const Size(360, 640),
    '640x360 landscape': const Size(640, 360),
    '390x844 portrait': const Size(390, 844),
    '844x390 landscape': const Size(844, 390),
  };

  for (final entry in sizes.entries) {
    testWidgets('no overflow and scrolls at ${entry.key}', (tester) async {
      await _pumpAt(tester, entry.value, _host());

      // No RenderFlex overflow thrown.
      expect(tester.takeException(), isNull);

      // The bar is horizontally scrollable when tabs do not fit.
      final scrollable = find.descendant(
        of: find.byType(AdaptiveTabBar),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollable, findsOneWidget);

      // Every tab is built (icons always present even when labels collapse).
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);

      // Dragging the bar does not throw.
      await tester.drag(scrollable, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping a tab reports its index', (tester) async {
    int? tapped;
    // Wide viewport so labels are shown (not collapsed).
    await _pumpAt(
      tester,
      const Size(1000, 800),
      _host(onSelected: (i) => tapped = i),
    );
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('tapping by icon works on a compact phone', (tester) async {
    int? tapped;
    await _pumpAt(
      tester,
      const Size(360, 640),
      _host(onSelected: (i) => tapped = i),
    );
    // Labels collapse on compact phones; the icon is still tappable.
    expect(find.text('History'), findsNothing);
    await tester.tap(find.byIcon(Icons.history));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('selecting later tab keeps it built', (tester) async {
    await _pumpAt(tester, const Size(360, 640), _host(selected: 7));
    expect(tester.takeException(), isNull);
    // The selected far tab is in the tree even when scrolled out of view.
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

  testWidgets('labels show, not collapse, on a wide viewport', (tester) async {
    await _pumpAt(tester, const Size(1200, 800), _host());
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
  });
}
