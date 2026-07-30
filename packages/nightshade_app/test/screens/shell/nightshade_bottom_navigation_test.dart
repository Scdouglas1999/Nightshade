import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/nightshade_bottom_navigation.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Pump the bar at [route] and return the labels of the selected slots.
///
/// Selection is drawn by [NightshadeDecorations.navSelected] on the item's
/// `AnimatedContainer`; an unselected slot has no decoration at all.
Future<List<String>> _selectedLabels(
  WidgetTester tester,
  String route,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        bottomNavigationBar: NightshadeBottomNavigation(
          currentRoute: route,
          onRouteSelected: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final selected = <String>[];
  for (final element in find.byType(AnimatedContainer).evaluate()) {
    final container = element.widget as AnimatedContainer;
    if (container.decoration == null) continue;
    final text = find
        .descendant(
          of: find.byWidget(container),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>();
    selected.addAll(text);
  }
  return selected;
}

void main() {
  // The bar's selection is a statement about where the operator is. Exact route
  // matching left it blank on legitimate sub-routes (the image-ready deep link
  // /imaging/preview/:id renders the Imaging screen), so the phone showed a
  // screen with nothing in the bar claiming it.
  testWidgets('a sub-route lights the slot that hosts it', (tester) async {
    expect(await _selectedLabels(tester, '/imaging'), isNotEmpty);
    expect(
      await _selectedLabels(tester, '/imaging/preview/42'),
      await _selectedLabels(tester, '/imaging'),
    );
  });

  testWidgets('a route no slot owns lights nothing', (tester) async {
    // Settings is the app-bar gear, not a bar slot; the Flat Wizard is a pushed
    // screen. Neither may borrow another slot's highlight.
    expect(await _selectedLabels(tester, '/settings'), isEmpty);
    expect(await _selectedLabels(tester, '/settings/plate-solving'), isEmpty);
    expect(await _selectedLabels(tester, '/flat-wizard'), isEmpty);
  });

  testWidgets('bottom nav items meet minimum touch target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          bottomNavigationBar: NightshadeBottomNavigation(
            currentRoute: '/dashboard',
            onRouteSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
    for (final inkWell in inkWells) {
      final context = tester.element(find.byWidget(inkWell));
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      expect(
        box.size.height,
        greaterThanOrEqualTo(NightshadeTokens.minTouchTarget - 1),
        reason:
            'Bottom nav tap target height below ${NightshadeTokens.minTouchTarget}pt',
      );
    }
  });
}
