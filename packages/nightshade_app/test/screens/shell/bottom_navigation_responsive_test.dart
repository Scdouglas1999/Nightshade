// Responsive widget tests for the shell bottom navigation.
//
// The bottom nav hosts 13 destinations. It must fit (by scrolling) without
// overflow at the three reference phone sizes in BOTH orientations, keep its
// tap targets at the touch-target floor, and honor SafeArea (the home
// indicator). In landscape — where vertical space is scarce — the bar shortens
// but still lays out cleanly.
//
// See docs/plans/2026-06-01-mobile-responsive-standard.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/nightshade_bottom_navigation.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

const _phoneSizes = <(String, Size)>[
  ('small 360x640', Size(360, 640)),
  ('modern 390x844', Size(390, 844)),
  ('large 430x932', Size(430, 932)),
];

Future<void> _pumpNav(
  WidgetTester tester, {
  required Size size,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: NightshadeTheme.dark,
      home: MediaQuery(
        // Simulate a home-indicator inset so SafeArea handling is exercised.
        data: MediaQueryData(
            size: size, viewPadding: viewPadding, padding: viewPadding),
        child: Scaffold(
          bottomNavigationBar: NightshadeBottomNavigation(
            currentRoute: '/dashboard',
            onRouteSelected: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, portrait) in _phoneSizes) {
    final landscape = Size(portrait.height, portrait.width);

    for (final entry in <(String, Size)>[
      ('portrait', portrait),
      ('landscape', landscape),
    ]) {
      final (orientation, size) = entry;

      testWidgets('bottom nav fits $name $orientation without overflow',
          (tester) async {
        await _pumpNav(
          tester,
          size: size,
          viewPadding: const EdgeInsets.only(bottom: 34),
        );

        expect(tester.takeException(), isNull);

        // The strip is horizontally scrollable, so all 13 destinations exist
        // in the list even when only a few are visible at once.
        expect(find.byType(NightshadeBottomNavigation), findsOneWidget);
        // The dashboard destination (first slot) is laid out.
        expect(find.text('Dashboard'), findsOneWidget);
      });

      testWidgets('bottom nav tap targets are adequate $name $orientation',
          (tester) async {
        await _pumpNav(tester, size: size);

        final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
        expect(inkWells, isNotEmpty);
        for (final inkWell in inkWells) {
          final context = tester.element(find.byWidget(inkWell));
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) continue;
          expect(
            box.size.height,
            greaterThanOrEqualTo(NightshadeTokens.minTouchTarget - 1),
            reason: 'Bottom nav tap target too short at $name $orientation',
          );
        }
      });
    }
  }
}
