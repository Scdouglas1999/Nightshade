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

/// Pulls the first `AnimationController` driving an `AnimatedBuilder` in the
/// subtree. The bar wraps its contents in a single top-level `AnimatedBuilder`
/// bound to the pulse controller, so the first match is the one we want.
AnimationController _pulseControllerOf(WidgetTester tester) {
  final builder = tester.widget<AnimatedBuilder>(find.byType(AnimatedBuilder).first);
  return builder.animation as AnimationController;
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
        await tester.pumpWidget(
          _harness(execState: SequenceExecutionState.running),
        );
        // Let the pulse start.
        await tester.pump(const Duration(milliseconds: 16));

        final runningController = _pulseControllerOf(tester);
        expect(runningController.isAnimating, isTrue,
            reason: 'pulse should be running while the sequence is running');

        // Flip to paused by rebuilding the harness with a new override.
        await tester.pumpWidget(
          _harness(execState: SequenceExecutionState.paused),
        );
        await tester.pump(const Duration(milliseconds: 16));

        final pausedController = _pulseControllerOf(tester);
        expect(pausedController.isAnimating, isFalse,
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
        expect(_pulseControllerOf(tester).isAnimating, isFalse);

        await tester.pumpWidget(
          _harness(execState: SequenceExecutionState.running),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(_pulseControllerOf(tester).isAnimating, isTrue,
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

