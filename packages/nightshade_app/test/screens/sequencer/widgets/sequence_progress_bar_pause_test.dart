// Widget test for SequenceProgressBar pause behaviour.
//
// Verifies that:
//   * The background-pulse `AnimationController` runs while the sequence is
//     executing (or idle) and stops when the execution state flips to
//     `SequenceExecutionState.paused`.
//   * When paused with no current node, the fallback label renders the
//     paused-aware copy instead of the misleading "Starting..." string.
//
// Implementation notes:
//   * We dig the `AnimationController` out of the State via a global key on
//     the widget under test. The state class is private to the library, so
//     we look up the `Ticker` and assert via `isAnimating` reachable through
//     `AnimatedBuilder`'s listenable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_progress_bar.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Pulls the `AnimationController` driving the SequenceProgressBar's
/// background-pulse `AnimatedBuilder`.
///
/// `find.byType(AnimatedBuilder).first` is no longer reliable: framework
/// wrappers (MaterialApp/Title/etc.) now insert AnimatedBuilders whose
/// `animation` is a `ValueNotifier`, which yielded
///   "type 'ValueNotifier<String?>' is not a subtype of type
///    'AnimationController' in type cast"
/// after the stash@{1} merge bumped the wrapper tree. Filter to the first
/// builder whose animation actually IS an AnimationController so we lock
/// onto SequenceProgressBar's own pulse, not the framework's plumbing.
/// Locate the SequenceProgressBar's background-pulse `AnimationController`.
///
/// `find.byType(AnimatedBuilder).first` is no longer reliable: framework
/// wrappers (MaterialApp/Title/etc.) insert AnimatedBuilders whose
/// `animation` is a `ValueNotifier`, which yielded
///   "type 'ValueNotifier<String?>' is not a subtype of type
///    'AnimationController' in type cast"
/// after the stash@{1} merge bumped the wrapper tree. SequenceProgressBar
/// also nests a second AnimatedBuilder (`_PulsingIndicator`'s breathing
/// dot) when `!isPaused`. We use the public widget's debug accessor
/// `debugPulseControllerForTesting` (added with @visibleForTesting on the
/// State class) to lock onto the right controller without subtree
/// guesswork.
AnimationController _pulseControllerOf(WidgetTester tester) {
  final state = tester.state<SequenceProgressBarState>(
    find.byType(SequenceProgressBar),
  );
  return state.debugPulseControllerForTesting;
}

Widget _harness({
  required SequenceExecutionState execState,
  SequenceProgress? progress,
}) {
  return ProviderScope(
    overrides: [
      sequenceExecutionStateProvider.overrideWith((ref) => execState),
      if (progress != null)
        sequenceProgressProvider.overrideWith(
          (ref) => _FixedProgressNotifier(progress),
        ),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Builder(
        builder: (ctx) {
          final colors = NightshadeColors.of(ctx);
          return Scaffold(
            body: SequenceProgressBar(colors: colors),
          );
        },
      ),
    ),
  );
}

class _FixedProgressNotifier extends SequenceProgressNotifier {
  _FixedProgressNotifier(SequenceProgress initial) {
    state = initial;
  }
}

void main() {
  group('SequenceProgressBar pause animation', () {
    testWidgets(
      'pulse controller stops when execution state flips to paused',
      (tester) async {
        // We mutate the override target THROUGH the provider rather than
        // calling pumpWidget twice with different overrides. pumpWidget on
        // the same widget type reuses the existing State (and the existing
        // ProviderScope's ProviderContainer), so the second override never
        // takes effect — `_syncPulse` would never see isPaused flip.
        // Driving the StateProvider directly via the ProviderContainer
        // makes the watch fire correctly and is closer to how the real app
        // toggles paused state at runtime.
        await tester.pumpWidget(
          _harness(execState: SequenceExecutionState.running),
        );
        await tester.pump(const Duration(milliseconds: 16));

        final runningController = _pulseControllerOf(tester);
        expect(runningController.isAnimating, isTrue,
            reason: 'pulse should be running while the sequence is running');

        // Flip to paused via the live ProviderContainer.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SequenceProgressBar)),
        );
        container.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
        await tester.pump(const Duration(milliseconds: 16));

        expect(runningController.isAnimating, isFalse,
            reason: 'pulse should freeze while the sequence is paused');
      },
    );

    testWidgets(
      'pulse controller resumes when execution leaves paused',
      (tester) async {
        await tester.pumpWidget(
          _harness(execState: SequenceExecutionState.paused),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final controller = _pulseControllerOf(tester);
        expect(controller.isAnimating, isFalse);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SequenceProgressBar)),
        );
        container.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        await tester.pump(const Duration(milliseconds: 16));

        expect(controller.isAnimating, isTrue,
            reason: 'pulse should resume once the sequence is running again');
      },
    );

    testWidgets(
      'paused + null currentNodeName shows the paused-aware fallback',
      (tester) async {
        await tester.pumpWidget(_harness(
          execState: SequenceExecutionState.paused,
          progress: const SequenceProgress(),
        ));
        await tester.pump();

        expect(find.text('Starting...'), findsNothing,
            reason: 'must not say "Starting..." while paused');
        expect(find.text('Paused — no active node'), findsOneWidget);
      },
    );

    testWidgets(
      'running + null currentNodeName still shows "Starting..."',
      (tester) async {
        await tester.pumpWidget(_harness(
          execState: SequenceExecutionState.running,
          progress: const SequenceProgress(),
        ));
        await tester.pump();

        expect(find.text('Starting...'), findsOneWidget);
      },
    );
  });
}
