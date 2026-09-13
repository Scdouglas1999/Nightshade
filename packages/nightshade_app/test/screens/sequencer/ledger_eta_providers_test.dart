// The two providers behind the ledger's ETA column, and the lifetimes their
// correctness depends on (spec §2).
//
// `ledger_columns_test.dart` covers the arithmetic. This covers the parts the
// arithmetic cannot see: whether the minute clock really reaches the map while
// a run is in flight (a run falling behind only shows when the clock moves),
// and whether the observed-start fold lets go of the typed event stream when
// there is no run to observe.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree/ledger_columns.dart';
import 'package:nightshade_app/screens/sequencer/widgets/visual_timeline.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';

/// 22:00, the anchor every simulation below is built at.
final DateTime _t0 = DateTime(2026, 9, 13, 22, 0);

/// Root -> [a, b, c], each billed five minutes apart.
({Sequence sequence, List<SequenceNode> steps}) _threeSteps() {
  final steps = <DelayNode>[
    DelayNode(name: 'a', seconds: 60),
    DelayNode(name: 'b', seconds: 60),
    DelayNode(name: 'c', seconds: 60),
  ];
  final root = InstructionSetNode(name: 'Root');
  final placed = <SequenceNode>[
    for (var i = 0; i < steps.length; i++)
      steps[i].copyWith(parentId: root.id, orderIndex: i),
  ];
  return (
    sequence: Sequence.create(
      name: 'T',
      rootNodeId: root.id,
      nodes: {
        for (final step in placed) step.id: step,
        root.id: root.copyWith(childIds: [for (final s in placed) s.id]),
      },
    ),
    steps: placed,
  );
}

PreSessionSimulationResult _simulation(List<SequenceNode> steps) {
  return PreSessionSimulationResult(
    start: _t0,
    end: _t0.add(const Duration(minutes: 15)),
    duration: const Duration(minutes: 15),
    segments: [
      for (var i = 0; i < steps.length; i++)
        PreSessionSimulationSegment(
          nodeId: steps[i].id,
          nodeName: steps[i].name,
          nodeType: 'Delay',
          start: _t0.add(Duration(minutes: 5 * i)),
          end: _t0.add(Duration(minutes: 5 * i + 1)),
          duration: const Duration(minutes: 1),
        ),
    ],
    targetWindows: const {},
    issues: const [],
  );
}

bridge.NightshadeEvent _nodeStarted(String nodeId, DateTime at) {
  return bridge.NightshadeEvent(
    eventId: BigInt.from(1),
    timestamp: at.millisecondsSinceEpoch,
    severity: bridge.EventSeverity.info,
    category: bridge.EventCategory.sequencer,
    payload: bridge.EventPayload.sequencer(
      bridge.SequencerEvent.nodeStarted(nodeId: nodeId, nodeType: 'Delay'),
    ),
  );
}

/// Let Riverpod's auto-dispose pass, and the stream cancellation it triggers.
/// Neither is synchronous: the dispose is scheduled after the last listener
/// goes, and the subscription's own `cancel()` completes a turn later again.
Future<void> _settleDisposal() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// Deliberately NO `TestWidgetsFlutterBinding.ensureInitialized()`. With the
// widget binding installed, Riverpod schedules auto-disposal against the
// scheduler's frames — and a plain `test` never pumps one, so nothing is ever
// disposed and the two lifetime assertions below would pass vacuously.
void main() {
  group('ledgerClockProvider', () {
    test('feeds the ETA map while a run is in flight', () async {
      final built = _threeSteps();
      final clock = StreamController<DateTime>.broadcast();
      addTearDown(clock.close);
      final sequence = CurrentSequenceNotifier();
      // ignore: invalid_use_of_protected_member
      sequence.state = built.sequence;

      final container = ProviderContainer(overrides: [
        currentSequenceProvider.overrideWith((_) => sequence),
        sequenceTimelineProvider.overrideWithValue(_simulation(built.steps)),
        ledgerClockProvider.overrideWith((ref) => clock.stream),
      ]);
      addTearDown(container.dispose);

      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      container
          .read(sequenceProgressProvider.notifier)
          .updateProgress(currentNodeId: built.steps[1].id);
      container.listen(ledgerEtaProvider, (_, __) {});

      // 22:05: `b` is executing exactly when the plan said, so `c` keeps its
      // planned 22:10.
      clock.add(_t0.add(const Duration(minutes: 5)));
      await _settleDisposal();
      expect(
        container.read(ledgerEtaProvider)[built.steps[2].id]!.start,
        _t0.add(const Duration(minutes: 10)),
      );

      // 22:45, still on `b`: the night is forty minutes behind and the column
      // has to say so. Before this provider ticked during a run, it did not.
      clock.add(_t0.add(const Duration(minutes: 45)));
      await _settleDisposal();
      expect(
        container.read(ledgerEtaProvider)[built.steps[2].id]!.start,
        _t0.add(const Duration(minutes: 50)),
        reason: 'a run 40 minutes behind must not quote its sunset ETAs',
      );
    });

    test('its subscription ends with its last listener', () async {
      // The clock now ticks THROUGH a run, so the thing that stops its timer
      // is auto-disposal and nothing else. A fresh subscription on the way back
      // in is the observable proof that the previous one was let go: the
      // provider body runs exactly once per live subscription.
      var subscriptions = 0;
      final container = ProviderContainer(overrides: [
        ledgerClockProvider.overrideWith((ref) {
          subscriptions += 1;
          return const Stream<DateTime>.empty();
        }),
      ]);
      addTearDown(container.dispose);

      final first = container.listen(ledgerClockProvider, (_, __) {});
      expect(subscriptions, 1);

      first.close();
      await _settleDisposal();
      container.listen(ledgerClockProvider, (_, __) {});
      expect(
        subscriptions,
        2,
        reason: 'a minute timer must not outlive the tree that wanted it',
      );
    });
  });

  group('ledgerActualStartsProvider', () {
    late StreamController<bridge.NightshadeEvent> events;
    late ProviderContainer container;

    setUp(() {
      events = StreamController<bridge.NightshadeEvent>.broadcast();
      container = ProviderContainer(overrides: [
        nightshadeEventsProvider.overrideWith((ref) => events.stream),
      ]);
    });

    tearDown(() {
      container.dispose();
      events.close();
    });

    test('survives the sequencer closing while a run is still going', () async {
      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      final subscription =
          container.listen(ledgerActualStartsProvider, (_, __) {});

      final at = _t0.add(const Duration(minutes: 7));
      events.add(_nodeStarted('node-b', at));
      await _settleDisposal();
      expect(container.read(ledgerActualStartsProvider)['node-b'], at);

      // The operator leaves the sequencer screen. The run is still going, so
      // the times it has already observed are still the truth about it.
      subscription.close();
      await _settleDisposal();
      expect(
        container.read(ledgerActualStartsProvider)['node-b'],
        at,
        reason: 'the run has not ended, so its observed starts have not either',
      );
    });

    test('lets go once the run settles', () async {
      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      final subscription =
          container.listen(ledgerActualStartsProvider, (_, __) {});

      events.add(_nodeStarted('node-b', _t0));
      await _settleDisposal();
      expect(container.read(ledgerActualStartsProvider), isNotEmpty);

      subscription.close();
      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.completed;
      await _settleDisposal();

      // Read again: the fold was disposed with the run, so this is a fresh
      // notifier with nothing in it — and, the point of the exercise, nothing
      // is still subscribed to the typed event stream.
      expect(container.read(ledgerActualStartsProvider), isEmpty);
    });
  });
}
