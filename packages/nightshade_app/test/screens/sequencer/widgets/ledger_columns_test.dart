// Unit tests for the ledger row's column semantics and the node -> start-time
// map the ETA column reads (spec §2).
//
// `ledgerColumnsFor` is pure: the rolled-up duration and the predicted start
// are passed in, so the cases below pin WHICH node type fills WHICH column
// and with what — without needing a running estimator or simulator.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree/ledger_columns.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Root -> container -> leaves, the smallest shape that exercises the
/// container branch of [ledgerColumnsFor].
({
  Sequence sequence,
  InstructionSetNode container,
  List<SequenceNode> children,
}) _containerOf(List<SequenceNode> children) {
  final container = InstructionSetNode(name: 'Set');
  final root = InstructionSetNode(name: 'Root');
  final placed = <SequenceNode>[
    for (var i = 0; i < children.length; i++)
      children[i].copyWith(parentId: container.id, orderIndex: i),
  ];
  final placedContainer = container.copyWith(
    parentId: root.id,
    childIds: [for (final child in placed) child.id],
  );
  return (
    sequence: Sequence.create(
      name: 'T',
      rootNodeId: root.id,
      nodes: {
        for (final child in placed) child.id: child,
        placedContainer.id: placedContainer,
        root.id: root.copyWith(childIds: [placedContainer.id]),
      },
    ),
    container: placedContainer,
    children: placed,
  );
}

PreSessionSimulationSegment _segment(
  String nodeId,
  DateTime start, {
  Duration duration = const Duration(minutes: 5),
}) {
  return PreSessionSimulationSegment(
    nodeId: nodeId,
    nodeName: nodeId,
    nodeType: 'Node',
    start: start,
    end: start.add(duration),
    duration: duration,
  );
}

void main() {
  group('ledgerColumnsFor', () {
    test('exposure: filter/exp, frame count, rollup duration, ETA', () {
      final exposure = ExposureNode(
        name: 'Ha',
        filter: 'Ha',
        durationSecs: 300,
        count: 12,
      );
      final sequence = Sequence.create(
        name: 'T',
        nodes: {exposure.id: exposure},
        rootNodeId: exposure.id,
      );

      final columns = ledgerColumnsFor(
        exposure,
        sequence,
        rollup: const Duration(hours: 1, minutes: 4),
        eta: DateTime(2026, 9, 13, 23, 12),
      );

      expect(columns.filterExp, 'Ha 300s');
      expect(columns.count, '12');
      expect(columns.duration, '~1h 4m');
      expect(columns.eta, '23:12');
    });

    test('exposure without a filter prints the seconds alone', () {
      final exposure = ExposureNode(durationSecs: 300, count: 5);
      final sequence = Sequence.create(
        name: 'T',
        nodes: {exposure.id: exposure},
        rootNodeId: exposure.id,
      );

      final columns = ledgerColumnsFor(
        exposure,
        sequence,
        rollup: const Duration(minutes: 25),
      );

      expect(columns.filterExp, '300s');
      expect(columns.count, '5');
    });

    test('fractional exposure keeps one decimal', () {
      final exposure = ExposureNode(
        filter: 'L',
        durationSecs: 1.5,
        count: 60,
      );
      final sequence = Sequence.create(
        name: 'T',
        nodes: {exposure.id: exposure},
        rootNodeId: exposure.id,
      );

      expect(
        ledgerColumnsFor(exposure, sequence, rollup: Duration.zero).filterExp,
        'L 1.5s',
      );
    });

    test('smart exposure: plan filters joined, total frames counted', () {
      final smart = SmartExposureNode(
        name: 'LRGB',
        plans: const [
          FilterPlan(filterName: 'L', count: 20, durationSecs: 60),
          FilterPlan(filterName: 'R', count: 10, durationSecs: 60),
          FilterPlan(filterName: 'G', count: 10, durationSecs: 60),
          FilterPlan(filterName: 'B', count: 10, durationSecs: 60),
        ],
      );
      final sequence = Sequence.create(
        name: 'T',
        nodes: {smart.id: smart},
        rootNodeId: smart.id,
      );

      final columns = ledgerColumnsFor(
        smart,
        sequence,
        rollup: const Duration(minutes: 50),
      );

      expect(columns.filterExp, 'L R G B');
      expect(columns.count, '50');
    });

    test('unnamed smart plans fall back to wheel position', () {
      final smart = SmartExposureNode(
        plans: const [
          FilterPlan(filterIndex: 0, count: 5),
          FilterPlan(filterIndex: 3, count: 5),
        ],
      );
      final sequence = Sequence.create(
        name: 'T',
        nodes: {smart.id: smart},
        rootNodeId: smart.id,
      );

      expect(
        ledgerColumnsFor(smart, sequence, rollup: Duration.zero).filterExp,
        '#1 #4',
      );
    });

    test('open-ended smart exposure prints an em dash, not an invented count',
        () {
      final smart = SmartExposureNode(
        loopUntilStopped: true,
        integrationBudgetSecs: 3600,
        plans: const [
          FilterPlan(filterName: 'L', count: 99, durationSecs: 60),
        ],
      );
      final sequence = Sequence.create(
        name: 'T',
        nodes: {smart.id: smart},
        rootNodeId: smart.id,
      );

      // The executor ignores per-plan counts in this mode, so "99" would be
      // a lie and "0" worse. The column says it cannot be numbered.
      expect(
        ledgerColumnsFor(smart, sequence, rollup: Duration.zero).count,
        '—',
      );
    });

    test('container: blank filter, subtree frame total, rollup, ETA', () {
      final built = _containerOf([
        ExposureNode(name: 'Ha', filter: 'Ha', durationSecs: 300, count: 4),
        ExposureNode(name: 'OIII', filter: 'OIII', durationSecs: 300, count: 6),
      ]);
      final loop = LoopNode(
        name: 'Loop x3',
        conditionType: LoopConditionType.count,
        repeatCount: 3,
      );
      // Re-parent the set under a count loop so the multiplier is exercised.
      final root = InstructionSetNode(name: 'Root');
      final setWithParent = built.container.copyWith(parentId: loop.id);
      final loopPlaced = loop.copyWith(
        parentId: root.id,
        childIds: [setWithParent.id],
      );
      final sequence = Sequence.create(
        name: 'T',
        rootNodeId: root.id,
        nodes: {
          for (final child in built.children)
            child.id: child.copyWith(parentId: setWithParent.id),
          setWithParent.id: setWithParent,
          loopPlaced.id: loopPlaced,
          root.id: root.copyWith(childIds: [loopPlaced.id]),
        },
      );

      final columns = ledgerColumnsFor(
        loopPlaced,
        sequence,
        rollup: const Duration(hours: 2, minutes: 30),
        eta: DateTime(2026, 9, 13, 22, 5),
      );

      expect(columns.filterExp, isEmpty);
      // (4 + 6) frames per pass × 3 passes.
      expect(columns.count, '30');
      expect(columns.duration, '~2h 30m');
      expect(columns.eta, '22:05');
    });

    test('unbounded loop marks the frame total as a floor', () {
      final exposure = ExposureNode(
        name: 'L',
        filter: 'L',
        durationSecs: 60,
        count: 10,
      );
      final loop = LoopNode(
        name: 'Until dawn',
        conditionType: LoopConditionType.whileDark,
      );
      final root = InstructionSetNode(name: 'Root');
      final sequence = Sequence.create(
        name: 'T',
        rootNodeId: root.id,
        nodes: {
          exposure.id: exposure.copyWith(parentId: loop.id),
          loop.id: loop.copyWith(parentId: root.id, childIds: [exposure.id]),
          root.id: root.copyWith(childIds: [loop.id]),
        },
      );

      // One pass is counted; the `+` says the plan runs it more than once.
      expect(
        ledgerColumnsFor(sequence.nodes[loop.id]!, sequence,
                rollup: Duration.zero)
            .count,
        '10+',
      );
    });

    test('delay: duration and ETA only', () {
      final delay = DelayNode(name: 'Settle', seconds: 30);
      final sequence = Sequence.create(
        name: 'T',
        nodes: {delay.id: delay},
        rootNodeId: delay.id,
      );

      final columns = ledgerColumnsFor(
        delay,
        sequence,
        rollup: const Duration(seconds: 30),
        eta: DateTime(2026, 9, 13, 21, 0),
      );

      expect(columns.filterExp, isEmpty);
      expect(columns.count, isEmpty);
      expect(columns.duration, '~30s');
      expect(columns.eta, '21:00');
    });

    test('a node with no duration leaves the column blank rather than "<1s"',
        () {
      final delay = DelayNode(seconds: 0);
      final sequence = Sequence.create(
        name: 'T',
        nodes: {delay.id: delay},
        rootNodeId: delay.id,
      );

      final columns = ledgerColumnsFor(delay, sequence, rollup: Duration.zero);

      expect(columns.duration, isEmpty);
      expect(columns.values, everyElement(isEmpty));
    });

    test('ETA stays blank when the simulation has no entry', () {
      final delay = DelayNode(seconds: 30);
      final sequence = Sequence.create(
        name: 'T',
        nodes: {delay.id: delay},
        rootNodeId: delay.id,
      );

      expect(
        ledgerColumnsFor(delay, sequence,
                rollup: const Duration(seconds: 30), eta: null)
            .eta,
        isEmpty,
      );
    });
  });

  group('formatLedgerClock', () {
    test('local HH:mm, zero-padded', () {
      final time = DateTime(2026, 9, 13, 7, 5);
      expect(formatLedgerClock(time), '07:05');
    });
  });

  group('ledgerNodeStarts', () {
    test('empty without a simulation', () {
      final built = _containerOf([DelayNode(name: 'd', seconds: 1)]);
      expect(ledgerNodeStarts(built.sequence, null), isEmpty);
    });

    test('container takes the earliest start inside its subtree', () {
      final built = _containerOf([
        DelayNode(name: 'first', seconds: 60),
        DelayNode(name: 'second', seconds: 30),
      ]);
      final t0 = DateTime(2026, 9, 13, 22, 0);
      final simulation = PreSessionSimulationResult(
        start: t0,
        end: t0.add(const Duration(minutes: 30)),
        duration: const Duration(minutes: 30),
        segments: [
          _segment(built.children[0].id, t0),
          _segment(
            built.children[1].id,
            t0.add(const Duration(minutes: 5)),
          ),
        ],
        targetWindows: const {},
        issues: const [],
      );

      final starts = ledgerNodeStarts(built.sequence, simulation);

      // The set itself has no segment — it inherits its first child's start.
      expect(starts[built.container.id], t0);
      expect(starts[built.children[0].id], t0);
      expect(starts[built.children[1].id], t0.add(const Duration(minutes: 5)));
      // The root has no billed duration either; it still starts at t0.
      expect(starts[built.sequence.rootNodeId], t0);
    });

    test('a node the simulation cannot place has no entry', () {
      final built = _containerOf([DelayNode(name: 'd', seconds: 1)]);
      final t0 = DateTime(2026, 9, 13, 22, 0);
      final simulation = PreSessionSimulationResult(
        start: t0,
        end: t0,
        duration: Duration.zero,
        // A segment for a DIFFERENT node id — nothing under this sequence.
        segments: [_segment('elsewhere', t0)],
        targetWindows: const {},
        issues: const [],
      );

      final starts = ledgerNodeStarts(built.sequence, simulation);

      expect(starts.containsKey(built.children[0].id), isFalse);
      expect(starts.containsKey(built.container.id), isFalse);
    });

    test('a repeated node keeps its earliest segment start', () {
      final delay = DelayNode(name: 'd', seconds: 60);
      final sequence = Sequence.create(
        name: 'T',
        nodes: {delay.id: delay},
        rootNodeId: delay.id,
      );
      final t0 = DateTime(2026, 9, 13, 22, 0);
      final simulation = PreSessionSimulationResult(
        start: t0,
        end: t0.add(const Duration(hours: 1)),
        duration: const Duration(hours: 1),
        segments: [
          _segment(delay.id, t0.add(const Duration(minutes: 40))),
          _segment(delay.id, t0.add(const Duration(minutes: 10))),
        ],
        targetWindows: const {},
        issues: const [],
      );

      expect(
        ledgerNodeStarts(sequence, simulation)[delay.id],
        t0.add(const Duration(minutes: 10)),
      );
    });
  });

  group('ledgerEtasFor', () {
    final t0 = DateTime(2026, 9, 13, 22, 0);

    PreSessionSimulationResult simFor(
      ({
        Sequence sequence,
        InstructionSetNode container,
        List<SequenceNode> children
      }) built, {
      List<Duration>? offsets,
    }) {
      final starts = offsets ??
          List<Duration>.generate(
              built.children.length, (i) => Duration(minutes: 5 * i));
      return PreSessionSimulationResult(
        start: t0,
        end: t0.add(const Duration(hours: 1)),
        duration: const Duration(hours: 1),
        segments: [
          for (var i = 0; i < built.children.length; i++)
            _segment(built.children[i].id, t0.add(starts[i])),
        ],
        targetWindows: const {},
        issues: const [],
      );
    }

    test('before a run the whole plan re-anchors at now', () {
      final built = _containerOf([
        DelayNode(name: 'a', seconds: 60),
        DelayNode(name: 'b', seconds: 60),
      ]);
      final simulation = simFor(built);

      final etas = ledgerEtasFor(
        built.sequence,
        simulation,
        // The simulation was built at 22:00; the wall clock is now 23:00.
        now: t0.add(const Duration(hours: 1)),
        runActive: false,
      );

      expect(etas[built.children[0].id],
          LedgerEta(t0.add(const Duration(hours: 1)), isActual: false));
      expect(
          etas[built.children[1].id],
          LedgerEta(t0.add(const Duration(hours: 1, minutes: 5)),
              isActual: false));
      // The container folds the earliest shifted start.
      expect(etas[built.container.id],
          LedgerEta(t0.add(const Duration(hours: 1)), isActual: false));
    });

    test('during a run the remaining plan anchors at the recorded start', () {
      final built = _containerOf([DelayNode(name: 'a', seconds: 60)]);
      final simulation = simFor(built);
      final runStart = DateTime(2026, 9, 13, 23, 30);

      final etas = ledgerEtasFor(
        built.sequence,
        simulation,
        // `now` is deliberately far from both anchors: if it leaked into the
        // anchor the assertion would catch it.
        now: DateTime(2026, 9, 14, 4, 0),
        runActive: true,
        runStart: runStart,
      );

      // The plan is projected from the run's recorded start, not `now` and
      // not the simulation's own anchor.
      expect(etas[built.children[0].id], LedgerEta(runStart, isActual: false));
    });

    test('a run with no recorded start yet keeps the simulation anchor', () {
      final built = _containerOf([DelayNode(name: 'a', seconds: 60)]);
      final simulation = simFor(built);

      final etas = ledgerEtasFor(
        built.sequence,
        simulation,
        now: DateTime(2026, 9, 14, 4, 0),
        runActive: true,
      );

      expect(etas[built.children[0].id], LedgerEta(t0, isActual: false));
    });

    test('an observed start beats the prediction and folds into the parent',
        () {
      final built = _containerOf([
        DelayNode(name: 'a', seconds: 60),
        DelayNode(name: 'b', seconds: 60),
      ]);
      final simulation = simFor(built);
      // The first child really began 2 minutes after the run's plan said —
      // an observed time replaces the projection rather than averaging it.
      final observed = t0.add(const Duration(minutes: 32));

      final etas = ledgerEtasFor(
        built.sequence,
        simulation,
        now: DateTime(2026, 9, 14, 4, 0),
        runActive: true,
        runStart: DateTime(2026, 9, 13, 23, 0),
        actualStarts: {built.children[0].id: observed},
      );

      expect(etas[built.children[0].id], LedgerEta(observed, isActual: true));
      // The container's subtree start is the earliest thing under it — the
      // observed start, not the earlier (wrong) prediction.
      expect(etas[built.container.id], LedgerEta(observed, isActual: true));
      // The sibling still projects.
      expect(etas[built.children[1].id]!.isActual, isFalse);
    });

    test('actual starts alone still produce a map when there is no simulation',
        () {
      final built = _containerOf([DelayNode(name: 'a', seconds: 60)]);
      final observed = DateTime(2026, 9, 13, 23, 41);

      final etas = ledgerEtasFor(
        built.sequence,
        null,
        now: t0,
        runActive: true,
        runStart: t0,
        actualStarts: {built.children[0].id: observed},
      );

      expect(etas[built.children[0].id], LedgerEta(observed, isActual: true));
      expect(etas[built.container.id], LedgerEta(observed, isActual: true));
    });

    test('empty when nothing can be placed', () {
      final built = _containerOf([DelayNode(name: 'a', seconds: 60)]);
      expect(
        ledgerEtasFor(built.sequence, null, now: t0, runActive: false),
        isEmpty,
      );
    });

    // Anchoring the whole remaining plan on the run's START is what made a
    // night that was running late report the same ETAs it reported at
    // sunset — all of them, all night. The pending tail hangs off the
    // executing node's predicted start OR the clock, whichever is later.
    group('a run behind schedule', () {
      /// a (22:00) -> b (22:05) -> c (22:10), run started exactly on plan,
      /// `b` executing.
      ({
        Sequence sequence,
        InstructionSetNode container,
        List<SequenceNode> children
      }) late() {
        return _containerOf([
          DelayNode(name: 'a', seconds: 60),
          DelayNode(name: 'b', seconds: 60),
          DelayNode(name: 'c', seconds: 60),
        ]);
      }

      test('pushes the pending tail by how late the executing node is', () {
        final built = late();
        final simulation = simFor(built);
        // `b` was predicted to start at 22:05 and the run started on plan, so
        // the clock at 22:45 says the night is 40 minutes behind.
        final etas = ledgerEtasFor(
          built.sequence,
          simulation,
          now: t0.add(const Duration(minutes: 45)),
          runActive: true,
          runStart: t0,
          currentNodeId: built.children[1].id,
          actualStarts: {
            built.children[1].id: t0.add(const Duration(minutes: 7))
          },
        );

        // The executing node keeps its OBSERVED start — it really began then.
        expect(
          etas[built.children[1].id],
          LedgerEta(t0.add(const Duration(minutes: 7)), isActual: true),
        );
        // The step after it was predicted for 22:10 and is now 22:50: the
        // 40 minutes the run is behind, added to the plan's own spacing.
        expect(
          etas[built.children[2].id],
          LedgerEta(t0.add(const Duration(minutes: 50)), isActual: false),
        );
      });

      test('leaves a run that is ON plan exactly where the plan put it', () {
        final built = late();
        final simulation = simFor(built);
        final etas = ledgerEtasFor(
          built.sequence,
          simulation,
          // `b` was predicted for 22:05 and it is 22:05: nothing to push.
          now: t0.add(const Duration(minutes: 5)),
          runActive: true,
          runStart: t0,
          currentNodeId: built.children[1].id,
        );

        expect(
          etas[built.children[2].id],
          LedgerEta(t0.add(const Duration(minutes: 10)), isActual: false),
        );
      });

      test('never talks a run that is AHEAD of plan back down to it', () {
        final built = late();
        final simulation = simFor(built);
        final etas = ledgerEtasFor(
          built.sequence,
          simulation,
          // The run reached `b` three minutes early.
          now: t0.add(const Duration(minutes: 2)),
          runActive: true,
          runStart: t0,
          currentNodeId: built.children[1].id,
        );

        expect(
          etas[built.children[2].id],
          LedgerEta(t0.add(const Duration(minutes: 10)), isActual: false),
          reason: 'the estimator, not the clock, says how long the rest takes',
        );
      });

      test('an unbilled executing node leaves the tail on the run anchor', () {
        final built = late();
        final simulation = simFor(built);
        // Containers carry no segment of their own, so there is no predicted
        // start to measure lateness against; the honest answer is to leave the
        // plan where the run's start put it rather than invent a delay.
        final etas = ledgerEtasFor(
          built.sequence,
          simulation,
          now: t0.add(const Duration(hours: 6)),
          runActive: true,
          runStart: t0,
          currentNodeId: 'a-node-the-estimator-never-billed',
        );

        expect(
          etas[built.children[2].id],
          LedgerEta(t0.add(const Duration(minutes: 10)), isActual: false),
        );
      });

      test('does not apply before a run, where `now` is already the anchor',
          () {
        final built = late();
        final simulation = simFor(built);
        final etas = ledgerEtasFor(
          built.sequence,
          simulation,
          now: t0.add(const Duration(hours: 1)),
          runActive: false,
          currentNodeId: built.children[1].id,
        );

        expect(
          etas[built.children[0].id],
          LedgerEta(t0.add(const Duration(hours: 1)), isActual: false),
        );
      });
    });
  });
}
