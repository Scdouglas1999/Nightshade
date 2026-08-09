// One guided flow at a time.
//
// Live finding: finishing the 13-step onboarding wizard and choosing "Take the
// first-night walkthrough" opens a 7-step modal. Its "Show me on the Sequencer
// screen" deep-link pops the modal and navigates — and the Sequencer then
// raised its own bottom-right nudge, "Sequencer Tour — learn how to create and
// run automated imaging sequences", offering a tour of the screen the
// walkthrough step had just explained. Following the first tour's own
// instructions was rewarded with a second tour.
//
// The walkthrough parks rather than ends when it deep-links, so the gate is a
// session flag it holds until the user actually finishes, skips or closes it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/contextual_tour_prompt.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../harness/pump_app_screen.dart';

/// The prompt waits 500 ms after its post-frame check before fading in.
Future<void> _waitForPrompt(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<HarnessHandle> _pump(
  WidgetTester tester, {
  required bool guidedFlowActive,
}) {
  return pumpAppScreen(
    tester,
    const ContextualTourPrompt(
      screenId: 'guided-flow-test',
      tourCategory: TutorialCategory.sequencerTour,
      title: 'Sequencer Tour',
      description: 'Learn how to create and run automated imaging sequences.',
      child: SizedBox.expand(child: ColoredBox(color: Color(0xFF102030))),
    ),
    size: const Size(1200, 800),
    settle: false,
    extraOverrides: [
      guidedFlowActiveProvider.overrideWith((ref) => guidedFlowActive),
    ],
  );
}

void main() {
  testWidgets('with no walkthrough running the nudge still appears',
      (tester) async {
    // Control case: without this the suppression test proves nothing.
    await _pump(tester, guidedFlowActive: false);
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);

    expect(find.byKey(contextualTourPromptCardKey), findsOneWidget);
  });

  testWidgets('the nudge stands down while the walkthrough is running',
      (tester) async {
    await _pump(tester, guidedFlowActive: true);
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);

    expect(find.byKey(contextualTourPromptCardKey), findsNothing);
    expect(find.text('Start Tour'), findsNothing);
  });

  testWidgets('a walkthrough started later takes the nudge off screen',
      (tester) async {
    // The walkthrough is reachable from Settings while a nudge is already up.
    final harness = await _pump(tester, guidedFlowActive: false);
    await tester.pumpAndSettle();
    await _waitForPrompt(tester);
    expect(find.byKey(contextualTourPromptCardKey), findsOneWidget);

    harness.container.read(guidedFlowActiveProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(find.byKey(contextualTourPromptCardKey), findsNothing);
    // Taken off screen, NOT spent: the user declined nothing, so the offer
    // must survive to the next visit.
    expect(
      harness.container.read(dismissedTourPromptsProvider),
      isNot(contains('guided-flow-test')),
    );
  });
}
