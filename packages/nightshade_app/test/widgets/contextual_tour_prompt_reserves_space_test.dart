// Regression: the contextual tour prompt must not cover the content it is
// describing.
//
// Observed live on a virgin install at 800x600: the "Dashboard Tour" card sat on
// top of the dashboard, covering the right half of the "Last run" card and
// clipping the Readiness chip row mid-word. At 1000x700 it covered the Readiness
// card's right side. The card was a free-floating Positioned child of a Stack
// wrapping the whole screen, so its footprint always came out of live content.
//
// The fix reserves the band the card occupies. This test pins the geometric
// invariant — card and child never intersect — plus the two properties that make
// the reservation honest: it costs nothing before the card appears, and nothing
// after it is dismissed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/contextual_tour_prompt.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../harness/pump_app_screen.dart';

const _childKey = Key('tour.test.child');

/// The prompt waits 500 ms after its post-frame check before fading in.
Future<void> _waitForPrompt(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _pumpPrompt(WidgetTester tester, {required Size size}) async {
  await pumpAppScreen(
    tester,
    const ContextualTourPrompt(
      screenId: 'tour-reservation-test',
      tourCategory: TutorialCategory.dashboardTour,
      title: 'Dashboard Tour',
      description: 'Learn about the dashboard controls and status displays.',
      child: SizedBox.expand(
        child: ColoredBox(color: Color(0xFF102030), key: _childKey),
      ),
    ),
    size: size,
    settle: false,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(800, 600),
    Size(1000, 700),
    Size(1400, 900),
  ]) {
    testWidgets(
        'prompt card never overlaps its child at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _pumpPrompt(tester, size: size);

      final fullHeight = tester.getRect(find.byKey(_childKey)).height;

      await _waitForPrompt(tester);
      expect(
        find.byKey(contextualTourPromptCardKey),
        findsOneWidget,
        reason: 'the prompt did not appear, so the test proves nothing',
      );

      final childRect = tester.getRect(find.byKey(_childKey));
      final cardRect = tester.getRect(find.byKey(contextualTourPromptCardKey));

      expect(
        childRect.overlaps(cardRect),
        isFalse,
        reason: 'tour card $cardRect covers content $childRect',
      );
      // The band came out of the child, not out of the window.
      expect(childRect.height, lessThan(fullHeight));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the child keeps the full area until the prompt appears',
      (tester) async {
    await _pumpPrompt(tester, size: const Size(800, 600));

    // Before the 500 ms delay elapses there is no card, so nothing is reserved.
    final before = tester.getRect(find.byKey(_childKey));
    expect(find.byKey(contextualTourPromptCardKey), findsNothing);

    await _waitForPrompt(tester);
    expect(
        tester.getRect(find.byKey(_childKey)).height, lessThan(before.height));
  });

  // Regression: the band is an ENHANCEMENT and must never be able to take the
  // screen away.
  //
  // The reservation was whatever the card measured, and the card's height is
  // driven by how far its copy wraps — so on a short viewport it could exceed
  // the viewport. It did: squeezed into 64px (a landscape phone whose shell has
  // handed most of the height to the keyboard) the card measured 203px, the
  // child was laid out at zero height, and every control underneath — including
  // the settings search field — silently stopped hit-testing.
  testWidgets('a viewport too short for the band keeps all of its content',
      (tester) async {
    var taps = 0;
    await pumpAppScreen(
      tester,
      SizedBox(
        height: 64,
        child: ContextualTourPrompt(
          screenId: 'tour-reservation-squeezed-test',
          tourCategory: TutorialCategory.dashboardTour,
          title: 'Dashboard Tour',
          description:
              'Learn about the dashboard controls and status displays.',
          child: GestureDetector(
            key: _childKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      size: const Size(932, 430),
      settle: false,
    );
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);

    expect(
      find.byKey(contextualTourPromptCardKey),
      findsOneWidget,
      reason: 'the prompt did not appear, so the test proves nothing',
    );
    expect(
      tester.getRect(find.byKey(_childKey)).height,
      64.0,
      reason: 'a card that cannot fit must reserve nothing and float over the '
          'content instead of squeezing it to zero',
    );

    // The property that actually broke: content underneath stays operable.
    await tester.tap(find.byKey(_childKey), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1,
        reason: 'content under an over-sized prompt must still receive taps');
    expect(tester.takeException(), isNull);
  });

  // Regression: reserving the band is right for a page of cards and WRONG for a
  // full-bleed canvas.
  //
  // On first entry to the Planetarium the sky canvas stopped ~150px short of its
  // container and the strip below it was flat page background with the tour card
  // floating in it — measured at a constant ~150px across 1600x900, 1400x1300,
  // 1920x1200 and 5120x1400, i.e. ~25% of the viewport on a 1366x768 laptop. It
  // snapped back to full height the moment the card was dismissed. The card
  // already sits in the sky's empty bottom-right corner, so on such a screen it
  // must float instead.
  testWidgets('a full-bleed host can opt out and keep all of its height',
      (tester) async {
    await pumpAppScreen(
      tester,
      const ContextualTourPrompt(
        screenId: 'tour-no-reservation-test',
        tourCategory: TutorialCategory.planetariumTour,
        title: 'Planetarium Tour',
        description: 'Learn how to navigate the sky and find targets.',
        reserveSpaceForCard: false,
        child: SizedBox.expand(
          child: ColoredBox(color: Color(0xFF102030), key: _childKey),
        ),
      ),
      size: const Size(1600, 900),
      settle: false,
    );
    await tester.pumpAndSettle();

    final before = tester.getRect(find.byKey(_childKey));
    await _waitForPrompt(tester);

    expect(
      find.byKey(contextualTourPromptCardKey),
      findsOneWidget,
      reason: 'the prompt did not appear, so the test proves nothing',
    );
    expect(
      tester.getRect(find.byKey(_childKey)),
      before,
      reason: 'an opted-out host must not lose a pixel of its canvas to the '
          'nudge; on the planetarium that band was ~150px of dead black',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opting out still floats the card inside the host',
      (tester) async {
    await pumpAppScreen(
      tester,
      const ContextualTourPrompt(
        screenId: 'tour-no-reservation-overlap-test',
        tourCategory: TutorialCategory.planetariumTour,
        title: 'Planetarium Tour',
        description: 'Learn how to navigate the sky and find targets.',
        reserveSpaceForCard: false,
        child: SizedBox.expand(
          child: ColoredBox(color: Color(0xFF102030), key: _childKey),
        ),
      ),
      size: const Size(1600, 900),
      settle: false,
    );
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);

    final childRect = tester.getRect(find.byKey(_childKey));
    final cardRect = tester.getRect(find.byKey(contextualTourPromptCardKey));

    // Deliberately the inverse of the reserved-band assertion: here the card is
    // SUPPOSED to sit over the canvas, in the corner that holds only sky.
    expect(childRect.overlaps(cardRect), isTrue);
    expect(cardRect.bottom, lessThanOrEqualTo(childRect.bottom + 1));
    expect(cardRect.right, lessThanOrEqualTo(childRect.right + 1));
  });

  testWidgets('dismissing returns the reserved band to the content',
      (tester) async {
    await _pumpPrompt(tester, size: const Size(800, 600));
    final full = tester.getRect(find.byKey(_childKey));

    await _waitForPrompt(tester);
    expect(tester.getRect(find.byKey(_childKey)).height, lessThan(full.height));

    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(find.byKey(contextualTourPromptCardKey), findsNothing);
    expect(
      tester.getRect(find.byKey(_childKey)),
      full,
      reason: 'the reserved band must be given back on dismiss',
    );
  });
}
