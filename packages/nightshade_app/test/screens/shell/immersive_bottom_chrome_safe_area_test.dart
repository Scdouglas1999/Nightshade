// Regression: the collapsed "Menu" reveal handle must clear the system's
// bottom inset (gesture home indicator / software nav bar).
//
// Observed live on an Android 15 emulator (gesture navigation, 48px bottom
// inset): once the phone shell auto-hid its bottom chrome, the 28px "^ Menu"
// handle — which IS the only navigation affordance in that state — was drawn
// flush to the screen edge, *underneath* the gesture home indicator. The white
// indicator struck through the word "Menu" and the lower half of the handle sat
// inside the system gesture region, where swipes belong to the OS, not the app.
//
// Root cause: NightshadeBottomNavigation supplies the bottom inset via its own
// SafeArea. The hidden branch swaps that whole subtree for a zero-height box,
// so nothing consumed the inset any more.
//
// Both halves are pinned here: simply padding the handle would be a regression
// if it also stopped the surface colour reaching the screen edge (that would
// show page content bleeding through behind the gesture bar).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/immersive_bottom_chrome.dart';

import '../../harness/pump_app_screen.dart';

const double _kBottomInset = 48;
const Size _kPhone = Size(400, 800);

/// Pumps the chrome bottom-aligned under a phone-like bottom system inset.
Future<void> _pumpChrome(
  WidgetTester tester, {
  required bool visible,
  Widget child = const SizedBox(height: 120, width: double.infinity),
}) async {
  await pumpAppScreen(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewPadding: const EdgeInsets.only(bottom: _kBottomInset),
          padding: const EdgeInsets.only(bottom: _kBottomInset),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ImmersiveBottomChrome(
              visible: visible,
              onToggle: () {},
              child: child,
            ),
          ],
        ),
      ),
    ),
    size: _kPhone,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ImmersiveBottomChrome bottom inset', () {
    testWidgets('hidden: "Menu" label sits above the system gesture inset',
        (tester) async {
      await _pumpChrome(tester, visible: false);

      final chrome = tester.getRect(find.byType(ImmersiveBottomChrome));
      final label = tester.getRect(find.text('Menu'));

      expect(
        label.bottom,
        lessThanOrEqualTo(chrome.bottom - _kBottomInset),
        reason: 'the label must not intrude into the gesture-bar strip — '
            'the home indicator drew straight through it',
      );
    });

    testWidgets('hidden: chrome reserves the inset below the 28px handle',
        (tester) async {
      await _pumpChrome(tester, visible: false);

      final chrome = tester.getRect(find.byType(ImmersiveBottomChrome));
      expect(
        chrome.height,
        closeTo(28 + _kBottomInset, 0.5),
        reason: 'handle height plus the reserved system inset',
      );
    });

    testWidgets('hidden: surface still paints all the way to the screen edge',
        (tester) async {
      await _pumpChrome(tester, visible: false);

      // The coloured Container is the handle's background; it must span the
      // inset too, otherwise page content shows through behind the gesture bar.
      final painted = tester.getRect(
        find
            .descendant(
              of: find.byType(ImmersiveBottomChrome),
              matching: find.byType(Container),
            )
            .first,
      );
      final chrome = tester.getRect(find.byType(ImmersiveBottomChrome));
      expect(painted.bottom, closeTo(chrome.bottom, 0.5));
      expect(painted.height, closeTo(28 + _kBottomInset, 0.5));
    });

    testWidgets('visible: chrome still renders its child (nav owns the inset)',
        (tester) async {
      await _pumpChrome(
        tester,
        visible: true,
        child: const SizedBox(
          key: ValueKey('nav'),
          height: 120,
          width: double.infinity,
        ),
      );

      expect(find.byKey(const ValueKey('nav')), findsOneWidget);
      expect(find.text('Menu'), findsNothing,
          reason: 'the labelled reveal handle belongs to the hidden state only');
    });
  });
}
