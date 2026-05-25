import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/nightshade_bottom_navigation.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
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
        reason: 'Bottom nav tap target height below ${NightshadeTokens.minTouchTarget}pt',
      );
    }
  });
}
