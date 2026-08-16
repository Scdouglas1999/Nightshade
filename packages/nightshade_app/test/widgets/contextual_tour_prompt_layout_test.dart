// The first-run tour nudge is chrome. It floats.
//
// History, because this file replaces the opposite assertion: the nudge was
// once laid out IN FLOW, holding a band of the host's height clear, so that the
// card could never cover the content it described. Driven live on a fresh
// install that cost every screen ~16% of its height until each of the seven
// nudges was dismissed — the Sequencer workspace stopped 147px short with the
// node palette cut through a card, and in Settings the entire ADVANCED group
// was off-screen, reachable only by dismissing a coach mark that says nothing
// about settings. A dismissible suggestion may not take a sixth of the screen
// away from the thing it is suggesting you learn about.
//
// So: the host keeps every pixel, and the card floats in the corner it is
// anchored to. Both properties are pinned here.
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

Future<void> _pumpPrompt(
  WidgetTester tester, {
  required Size size,
  String screenId = 'tour-float-test',
}) async {
  await pumpAppScreen(
    tester,
    ContextualTourPrompt(
      screenId: screenId,
      tourCategory: TutorialCategory.dashboardTour,
      title: 'Dashboard Tour',
      description: 'Learn about the dashboard controls and status displays.',
      child: const SizedBox.expand(
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
        'the host keeps its full height with the nudge up at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _pumpPrompt(tester, size: size);
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
        reason: 'a coach mark must not come out of the screen it annotates',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the card floats inside the host, anchored bottom-right',
      (tester) async {
    await _pumpPrompt(tester, size: const Size(1000, 700));
    await _waitForPrompt(tester);

    final childRect = tester.getRect(find.byKey(_childKey));
    final cardRect = tester.getRect(find.byKey(contextualTourPromptCardKey));

    expect(childRect.overlaps(cardRect), isTrue);
    expect(cardRect.bottom, lessThanOrEqualTo(childRect.bottom + 1));
    expect(cardRect.right, lessThanOrEqualTo(childRect.right + 1));
  });

  // With no reserved band, content underneath stays operable even on a viewport
  // shorter than the card.
  testWidgets('content stays operable under the card on a short viewport',
      (tester) async {
    var taps = 0;
    await pumpAppScreen(
      tester,
      SizedBox(
        height: 64,
        child: ContextualTourPrompt(
          screenId: 'tour-float-squeezed-test',
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

    expect(find.byKey(contextualTourPromptCardKey), findsOneWidget);
    expect(tester.getRect(find.byKey(_childKey)).height, 64.0);

    await tester.tap(find.byKey(_childKey), warnIfMissed: false);
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing removes the card and leaves the host untouched',
      (tester) async {
    await _pumpPrompt(tester, size: const Size(800, 600));
    final full = tester.getRect(find.byKey(_childKey));

    await _waitForPrompt(tester);
    await tester.tap(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(find.byKey(contextualTourPromptCardKey), findsNothing);
    expect(tester.getRect(find.byKey(_childKey)), full);
  });

  // The cost side of the float. A host whose bottom-right corner
  // carries live controls (Equipment: the DISCOVERY header's Scan All /
  // Collapse, the mount card's Unpark / Track / Home / Flip row, the STATUS
  // rail's blockers block) opts into the band, and then the card must not
  // touch the host's content at all.
  testWidgets('a host that opts in keeps its content clear of the card',
      (tester) async {
    await pumpAppScreen(
      tester,
      ContextualTourPrompt(
        screenId: 'tour-reserve-test',
        tourCategory: TutorialCategory.equipmentTour,
        title: 'Equipment Tour',
        description: 'Learn about the equipment controls and status displays.',
        reserveSpaceForCard: true,
        child: const SizedBox.expand(
          child: ColoredBox(color: Color(0xFF102030), key: _childKey),
        ),
      ),
      size: const Size(1000, 800),
      settle: false,
    );
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);

    final childRect = tester.getRect(find.byKey(_childKey));
    final cardRect = tester.getRect(find.byKey(contextualTourPromptCardKey));
    expect(find.byKey(contextualTourPromptCardKey), findsOneWidget);
    expect(childRect.overlaps(cardRect), isFalse,
        reason: 'the reserved band exists so the card covers no control');
  });
}
