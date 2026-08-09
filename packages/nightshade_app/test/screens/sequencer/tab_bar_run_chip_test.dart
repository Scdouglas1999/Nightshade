// The Sequencer tab strip's run chip must state the run's real state.
//
// With a run PAUSED (toolbar chip "Paused 75%", node badge PAUSED, Pause
// flipped to Resume, no further frames landing) the chip one row above still
// showed a green dot and the literal text "Sequence Running" — the app's most
// prominent run indicator contradicting the one beside it about whether the
// rig was exposing. It was driven by an `isRunning` bool that was true for
// running AND paused.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/sequencer_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/pump_app_screen.dart';

Sequence _seedSequence() {
  final exposure = ExposureNode(name: 'Lum', durationSecs: 120, count: 10);
  final root = InstructionSetNode(name: 'Root');
  final nodes = <String, SequenceNode>{
    exposure.id: exposure.copyWith(parentId: root.id),
    root.id: root.copyWith(childIds: [exposure.id]),
  };
  return Sequence.create(name: 'Test', nodes: nodes, rootNodeId: root.id);
}

List<Override> _overrides(SequenceExecutionState state) {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = _seedSequence();
  return [
    currentSequenceProvider.overrideWith((_) => notifier),
    sequenceExecutionStateProvider.overrideWith((ref) => state),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Desktop width: the chip is deliberately desktop/tablet-only (a phone
  // surfaces run state through the playback bar instead).
  const desktop = Size(1920, 1080);

  Future<void> pumpAt(WidgetTester tester, SequenceExecutionState state) async {
    await pumpAppScreen(
      tester,
      const SequencerScreen(),
      size: desktop,
      extraOverrides: _overrides(state),
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a running sequence shows the running chip', (tester) async {
    await pumpAt(tester, SequenceExecutionState.running);
    expect(find.text('Sequence Running'), findsOneWidget);
    expect(find.text('Sequence Paused'), findsNothing);
  });

  testWidgets('a PAUSED sequence does not claim it is running', (tester) async {
    await pumpAt(tester, SequenceExecutionState.paused);
    expect(
      find.text('Sequence Running'),
      findsNothing,
      reason: 'the rig is not exposing while the run is paused',
    );
    expect(find.text('Sequence Paused'), findsOneWidget);
  });

  testWidgets('an idle sequence shows no run chip at all', (tester) async {
    await pumpAt(tester, SequenceExecutionState.idle);
    expect(find.text('Sequence Running'), findsNothing);
    expect(find.text('Sequence Paused'), findsNothing);
  });
}
