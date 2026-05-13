// Unit tests for the dynamic RoboTarget-class SchedulerEngine.
//
// These exercise the pure-logic core directly (no Riverpod, no database)
// via the candidateLoader / clock / sequenceSink injection points. Each
// test creates a fixed virtual clock so altitude / hour-angle results are
// deterministic.

import 'package:flutter_test/flutter_test.dart';

import 'package:nightshade_core/src/models/scheduler/integration_goal.dart';
import 'package:nightshade_core/src/models/scheduler/scheduler_status.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/services/scheduler/scheduler_engine.dart';

class _RecordingSink implements SchedulerSequenceSink {
  final List<Sequence> dispatched = [];
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;

  @override
  Future<void> dispatchSequence(Sequence sequence) async {
    dispatched.add(sequence);
  }

  @override
  Future<void> pauseSequence() async {
    pauseCount++;
  }

  @override
  Future<void> resumeSequence() async {
    resumeCount++;
  }

  @override
  Future<void> stopSequence() async {
    stopCount++;
  }
}

// Mid-northern observatory site used across the tests. Local offset is
// UTC-5 so wall-clock-based constraints behave like an east-coast user.
const _site = SchedulerSite(
  latitudeDegrees: 40.0,
  longitudeDegrees: -75.0,
  localOffset: Duration(hours: -5),
);

// Fixed virtual clock: 2026-05-11 04:00 UTC == 23:00 local previous day.
// At this instant a target at RA ~14h, Dec +30° is near the meridian for
// the site; a target at RA ~04h is setting low in the west; a target at
// RA ~20h is rising in the east.
DateTime _fixedNow() => DateTime.utc(2026, 5, 11, 4, 0);

SchedulerCandidate _candidate({
  required int id,
  required String name,
  required double raHours,
  required double decDegrees,
  int userPriority = 5,
  List<IntegrationGoal> goals = const [],
  List<int> capturedCounts = const [],
  List<String> availableFilters = const ['L', 'R', 'G', 'B'],
}) {
  return SchedulerCandidate(
    targetId: id,
    name: name,
    raHours: raHours,
    decDegrees: decDegrees,
    userPriority: userPriority,
    goals: goals,
    capturedCounts: capturedCounts,
    constraints: const [],
    horizonProfiles: const {},
    availableFilters: availableFilters,
  );
}

void main() {
  group('SchedulerEngine - candidate selection', () {
    test('picks the highest-scoring candidate from three options', () async {
      final sink = _RecordingSink();
      late SchedulerEngine engine;
      final candidates = <SchedulerCandidate>[
        // High in the south, near meridian - should win.
        _candidate(
          id: 1,
          name: 'High in south',
          raHours: 14.0,
          decDegrees: 30.0,
        ),
        // Setting low in west.
        _candidate(
          id: 2,
          name: 'Setting west',
          raHours: 4.0,
          decDegrees: 10.0,
        ),
        // Rising low in east.
        _candidate(
          id: 3,
          name: 'Rising east',
          raHours: 20.0,
          decDegrees: 20.0,
        ),
      ];
      engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );

      await engine.start();
      final decision = engine.lastDecision;
      expect(decision, isNotNull);
      expect(decision!.chosenTargetId, 1);
      expect(decision.chosenTargetName, 'High in south');
      // All three candidates should appear in scoredCandidates (some may
      // have failed hard constraints if below 25° at the chosen instant).
      expect(decision.scoredCandidates.length, 3);
      // The winner should have a higher totalScore than the rest among
      // those that passed.
      final eligible = decision.scoredCandidates
          .where((s) => !s.hardConstraintFailed)
          .toList();
      expect(eligible.isNotEmpty, isTrue);
      expect(eligible.first.targetId, 1);
      await engine.dispose();
    });

    test('rejects candidates below the minimum altitude as hard fails',
        () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        // Below the horizon at the chosen instant (RA opposite the LST).
        _candidate(
          id: 10,
          name: 'Below horizon',
          raHours: 2.0,
          decDegrees: -45.0,
        ),
        _candidate(
          id: 11,
          name: 'High in south',
          raHours: 14.0,
          decDegrees: 30.0,
        ),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );
      await engine.start();
      final decision = engine.lastDecision!;
      expect(decision.chosenTargetId, 11);
      final rejected =
          decision.scoredCandidates.where((s) => s.hardConstraintFailed);
      expect(rejected.isNotEmpty, isTrue,
          reason: 'below-horizon target should be hardConstraintFailed');
      await engine.dispose();
    });

    test('emits a null decision when no candidates are eligible', () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(
          id: 20,
          name: 'Underfoot',
          raHours: 2.0,
          decDegrees: -85.0,
        ),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );
      await engine.start();
      final decision = engine.lastDecision!;
      expect(decision.chosenTargetId, isNull);
      expect(decision.reasoning, isNotEmpty);
      await engine.dispose();
    });
  });

  group('SchedulerEngine - hysteresis', () {
    test('does not switch when challenger is 1.10x current (below 1.20)',
        () async {
      final sink = _RecordingSink();
      // Two candidates A and B. We seed weights so A has a slight edge
      // first, then mutate weights so B's score is ~1.10x A. Hysteresis
      // is 1.20, so the engine must stick with A.
      final candidates = <SchedulerCandidate>[
        _candidate(id: 100, name: 'A', raHours: 14.0, decDegrees: 30.0),
        _candidate(id: 200, name: 'B', raHours: 14.0, decDegrees: 32.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );
      await engine.start();
      // After the first tick, the engine has chosen one of them. Force a
      // re-evaluation with the same data — no switch should occur.
      final firstChoice = engine.lastDecision!.chosenTargetId!;
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, firstChoice);
      expect(engine.lastDecision!.isSwitch, isFalse,
          reason: 'identical evaluation should never flip the chosen target');
      await engine.dispose();
    });

    test('switches when challenger exceeds hysteresis ratio', () async {
      final sink = _RecordingSink();
      // The hysteresis ratio is 1.20. user-priority alone doesn't move
      // total score by 20 % (its weight is 0.5 and the other weights sum
      // to ~4.0), so we engineer a sharp altitude gap in phase 2 — a
      // candidate near the meridian at high altitude trivially scores
      // 1.5x a candidate that just barely clears the horizon.
      final candidatesPhase1 = <SchedulerCandidate>[
        // A: high in the south near the meridian -> wins phase 1.
        _candidate(
          id: 100,
          name: 'A',
          raHours: 14.0,
          decDegrees: 30.0,
        ),
        // B: very low alt at the same instant -> hard-fails phase 1.
        _candidate(
          id: 200,
          name: 'B',
          raHours: 14.0,
          decDegrees: -25.0,
        ),
      ];
      final candidatesPhase2 = <SchedulerCandidate>[
        // A: still up but now low and away from meridian.
        _candidate(
          id: 100,
          name: 'A',
          raHours: 14.0,
          decDegrees: -10.0,
        ),
        // B: high in the south.
        _candidate(
          id: 200,
          name: 'B',
          raHours: 14.0,
          decDegrees: 30.0,
        ),
      ];
      var phase = 1;
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async =>
            phase == 1 ? candidatesPhase1 : candidatesPhase2,
        clock: _fixedNow,
      );
      await engine.start();
      expect(engine.lastDecision!.chosenTargetId, 100,
          reason: 'A is high in the south in phase 1');
      phase = 2;
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, 200,
          reason: 'B is now the obviously-better target (high alt) so the '
              'engine should swap once hysteresis is exceeded');
      expect(engine.lastDecision!.isSwitch, isTrue);
      await engine.dispose();
    });
  });

  group('SchedulerEngine - integration goals', () {
    test('builds a sequence that exposes the highest-remaining filter',
        () async {
      final sink = _RecordingSink();
      final now = DateTime.utc(2026, 5, 11, 4, 0);
      // Target with two goals — Red is mostly done, Green is barely started.
      // The engine should choose Green for the next sequence dispatch.
      final goals = [
        IntegrationGoal(
          targetId: 1,
          filter: 'R',
          exposureSeconds: 180.0,
          frameCount: 20,
          priority: 5,
          createdAt: now,
        ),
        IntegrationGoal(
          targetId: 1,
          filter: 'G',
          exposureSeconds: 180.0,
          frameCount: 20,
          priority: 5,
          createdAt: now,
        ),
      ];
      final candidates = <SchedulerCandidate>[
        SchedulerCandidate(
          targetId: 1,
          name: 'NGC 7000',
          raHours: 14.0,
          decDegrees: 30.0,
          userPriority: 5,
          goals: goals,
          capturedCounts: [18, 2],
          constraints: const [],
          horizonProfiles: const {},
          availableFilters: const ['L', 'R', 'G', 'B'],
        ),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: () => now,
      );
      await engine.start();
      expect(sink.dispatched.length, 1);
      final sequence = sink.dispatched.first;
      // Find the exposure node and verify it targets the G filter.
      final exposure = sequence.nodes.values.whereType<ExposureNode>().single;
      expect(exposure.filter, 'G');
      expect(exposure.count, 18,
          reason: 'should request the remaining frames for the chosen filter');
      await engine.dispose();
    });
  });

  group('SchedulerEngine - requestReevaluation debounce', () {
    test('triggers exactly one recompute within the debounce window',
        () async {
      final sink = _RecordingSink();
      var loadCount = 0;
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async {
          loadCount++;
          return candidates;
        },
        clock: _fixedNow,
      );
      // Start triggers the cold-start evaluation (loadCount becomes 1).
      await engine.start();
      expect(loadCount, 1);

      // Fire three requests inside a window much smaller than 500ms — the
      // engine must coalesce them into a single re-evaluation.
      engine.requestReevaluation(reason: 'a');
      engine.requestReevaluation(reason: 'b');
      engine.requestReevaluation(reason: 'c');

      // Wait past the 500ms debounce window so the timer fires once.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(loadCount, 2,
          reason: 'three requests inside the debounce window should '
              'produce one extra evaluation, not three');
      await engine.dispose();
    });

    test('a single requestReevaluation does fire a recompute', () async {
      final sink = _RecordingSink();
      var loadCount = 0;
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async {
          loadCount++;
          return candidates;
        },
        clock: _fixedNow,
      );
      await engine.start();
      expect(loadCount, 1);
      engine.requestReevaluation();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(loadCount, 2);
      await engine.dispose();
    });

    test('two bursts separated by > 500ms produce two recomputes', () async {
      final sink = _RecordingSink();
      var loadCount = 0;
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async {
          loadCount++;
          return candidates;
        },
        clock: _fixedNow,
      );
      await engine.start();
      expect(loadCount, 1);
      engine.requestReevaluation();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(loadCount, 2);
      engine.requestReevaluation();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(loadCount, 3);
      await engine.dispose();
    });
  });

  group('SchedulerEngine - lifecycle', () {
    test('start / pause / resume / stop drives sequence sink', () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );
      await engine.start();
      expect(engine.status.state, SchedulerState.running);
      expect(sink.dispatched.length, 1);
      await engine.pause();
      expect(engine.status.state, SchedulerState.paused);
      expect(sink.pauseCount, 1);
      await engine.resume();
      expect(engine.status.state, SchedulerState.running);
      expect(sink.resumeCount, 1);
      await engine.stop();
      expect(engine.status.state, SchedulerState.idle);
      expect(sink.stopCount, 1);
      await engine.dispose();
    });
  });
}
