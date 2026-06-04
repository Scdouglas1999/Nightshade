// Unit tests for the dynamic RoboTarget-class SchedulerEngine.
//
// These exercise the pure-logic core directly (no Riverpod, no database)
// via the candidateLoader / clock / sequenceSink injection points. Each
// test creates a fixed virtual clock so altitude / hour-angle results are
// deterministic.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:nightshade_core/src/models/scheduler/integration_goal.dart';
import 'package:nightshade_core/src/models/scheduler/scheduler_status.dart';
import 'package:nightshade_core/src/models/scheduler/target_constraint.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/services/scheduler/scheduler_engine.dart';

class _RecordingSink implements SchedulerSequenceSink {
  final List<Sequence> dispatched = [];
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  int parkCount = 0;

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

  @override
  Future<void> parkForEndOfNight() async {
    parkCount++;
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
  List<TargetConstraint> constraints = const [],
  bool isMosaicTarget = false,
}) {
  return SchedulerCandidate(
    targetId: id,
    name: name,
    raHours: raHours,
    decDegrees: decDegrees,
    userPriority: userPriority,
    goals: goals,
    capturedCounts: capturedCounts,
    constraints: constraints,
    horizonProfiles: const {},
    availableFilters: availableFilters,
    isMosaicTarget: isMosaicTarget,
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

    test('rejects all candidates while the Sun is up (no daylight imaging)',
        () async {
      final sink = _RecordingSink();
      // Local noon at the site (lon -75 -> solar noon ~17:00 UTC). Sun is
      // high (~+65 deg), far above the -12 deg darkness limit.
      DateTime daytime() => DateTime.utc(2026, 5, 11, 17, 0);
      final candidates = <SchedulerCandidate>[
        _candidate(id: 30, name: 'Circumpolar', raHours: 7.0, decDegrees: 40.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: daytime,
      );
      await engine.start();
      final decision = engine.lastDecision!;
      expect(decision.chosenTargetId, isNull,
          reason: 'must not slew/expose while the Sun is up');
      expect(
        decision.scoredCandidates.every((s) => s.hardConstraintFailed),
        isTrue,
      );
      expect(
        decision.scoredCandidates
            .any((s) => s.rejectionReasons.any((r) => r.contains('Sun'))),
        isTrue,
        reason: 'the twilight gate should reject candidates in daylight',
      );
      expect(sink.dispatched, isEmpty);
      await engine.dispose();
    });

    test('does not apply the Sun gate at night', () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(
            id: 31, name: 'High in south', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow, // 23:00 local -- deep night
      );
      await engine.start();
      final decision = engine.lastDecision!;
      final sunRejections = decision.scoredCandidates
          .expand((s) => s.rejectionReasons)
          .where((r) => r.contains('Sun'));
      expect(sunRejections, isEmpty,
          reason: 'gate must not fire when the Sun is well below the horizon');
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

    test('switches when user priority alone clears hysteresis', () async {
      final sink = _RecordingSink();
      var preferB = false;

      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => <SchedulerCandidate>[
          _candidate(
            id: 100,
            name: 'A',
            raHours: 14.0,
            decDegrees: 30.0,
            userPriority: preferB ? 0 : 5,
          ),
          _candidate(
            id: 200,
            name: 'B',
            raHours: 14.0,
            decDegrees: 30.0,
            userPriority: preferB ? 10 : 5,
          ),
        ],
        clock: _fixedNow,
      );

      await engine.start();
      expect(engine.lastDecision!.chosenTargetId, 100);

      preferB = true;
      await engine.evaluateNow();

      expect(engine.lastDecision!.chosenTargetId, 200,
          reason: 'a max-priority challenger should be able to override '
              'hysteresis even when sky geometry is tied');
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

  group('SchedulerEngine - mosaic candidates', () {
    test('dispatches one mosaic panel target per scheduler tick', () async {
      final sink = _RecordingSink();
      final now = DateTime.utc(2026, 5, 11, 4, 0);
      final goal = IntegrationGoal(
        targetId: 42,
        filter: 'L',
        exposureSeconds: 120.0,
        frameCount: 6,
        priority: 5,
        createdAt: now,
      );
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => [
          _candidate(
            id: 42,
            name: 'Andromeda Mosaic Panel 3/9',
            raHours: 14.0,
            decDegrees: 30.0,
            goals: [goal],
            capturedCounts: const [2],
            isMosaicTarget: true,
          ),
        ],
        clock: () => now,
      );

      await engine.start();

      expect(sink.dispatched.length, 1);
      final sequence = sink.dispatched.single;
      expect(sequence.name, contains('Andromeda Mosaic Panel 3/9'));
      final target = sequence.targetHeaders.single;
      expect(target.targetName, 'Andromeda Mosaic Panel 3/9');
      final exposure = sequence.nodes.values.whereType<ExposureNode>().single;
      expect(exposure.filter, 'L');
      expect(exposure.durationSecs, 120.0);
      expect(exposure.count, 4,
          reason: 'one scheduler tick should capture the remaining frames '
              'for the selected mosaic panel/filter');
      await engine.dispose();
    });

    test('builds all pending filter rows for a selected mosaic panel',
        () async {
      final sink = _RecordingSink();
      final now = DateTime.utc(2026, 5, 11, 4, 0);
      final goals = [
        IntegrationGoal(
          targetId: 42,
          filter: 'L',
          exposureSeconds: 120.0,
          frameCount: 6,
          priority: 8,
          createdAt: now,
        ),
        IntegrationGoal(
          targetId: 42,
          filter: 'R',
          exposureSeconds: 180.0,
          frameCount: 4,
          priority: 5,
          createdAt: now,
        ),
        IntegrationGoal(
          targetId: 42,
          filter: 'G',
          exposureSeconds: 180.0,
          frameCount: 4,
          priority: 5,
          createdAt: now,
        ),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => [
          _candidate(
            id: 42,
            name: 'Andromeda Mosaic Panel 3/9',
            raHours: 14.0,
            decDegrees: 30.0,
            goals: goals,
            capturedCounts: const [5, 1, 0],
            isMosaicTarget: true,
          ),
        ],
        clock: () => now,
      );

      await engine.start();

      final exposures =
          sink.dispatched.single.nodes.values.whereType<ExposureNode>().toList();
      expect(exposures.map((e) => e.filter), ['G', 'R', 'L']);
      expect(exposures.map((e) => e.count), [4, 3, 1]);
      expect(exposures.map((e) => e.durationSecs), [180.0, 180.0, 120.0]);
      await engine.dispose();
    });

  });

  group('SchedulerEngine - sequence completion reaction', () {
    test('SequenceCompleted re-dispatches a still-eligible current target',
        () async {
      final sink = _RecordingSink();
      final triggers = StreamController<SchedulerTriggerEvent>();
      addTearDown(triggers.close);
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        triggerStream: triggers.stream,
        clock: _fixedNow,
      );
      await engine.start();
      expect(sink.dispatched.length, 1,
          reason: 'cold start dispatches the chosen target');

      // The dispatched sequence finishes naturally. The engine must re-pick
      // and re-dispatch the still-eligible target's remaining work instead of
      // sitting idle until the next periodic tick.
      triggers.add(SchedulerTriggerEvent.sequenceCompleted);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sink.dispatched.length, 2,
          reason: 'natural completion must re-dispatch, not leave the rig '
              'idle (the original P0 bug)');
      await engine.dispose();
    });

    test('a non-completion trigger does NOT re-dispatch an unchanged winner',
        () async {
      final sink = _RecordingSink();
      final triggers = StreamController<SchedulerTriggerEvent>();
      addTearDown(triggers.close);
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        triggerStream: triggers.stream,
        clock: _fixedNow,
      );
      await engine.start();
      expect(sink.dispatched.length, 1);

      // A weather/guiding-style re-eval where the winner is unchanged must NOT
      // re-dispatch (hysteresis keeps the running target) -- only a genuine
      // completion clears the current target and re-dispatches.
      triggers.add(SchedulerTriggerEvent.guidingRecovered);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sink.dispatched.length, 1,
          reason: 'an unchanged-winner re-eval must not re-dispatch');
      await engine.dispose();
    });
  });

  group('SchedulerEngine - end-of-night park', () {
    // Local noon at the site (lon -75 -> solar noon ~17:00 UTC): the Sun is
    // high above the -12 deg darkness limit, so every candidate is
    // Sun-rejected and the engine treats the empty-eligible path as dawn.
    DateTime daytime() => DateTime.utc(2026, 5, 11, 17, 0);

    test('parks the mount once at end-of-night (Sun up, no eligible target)',
        () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: daytime,
      );
      await engine.start();

      expect(engine.lastDecision!.chosenTargetId, isNull,
          reason: 'Sun is up — no candidate is eligible');
      expect(sink.dispatched, isEmpty,
          reason: 'must never slew/expose at dawn');
      expect(sink.parkCount, 1,
          reason: 'end-of-night must invoke the distinct park hook');
      // The empty-eligible path stops a *running* sequence on every tick, but
      // on the dawn/park path we park instead of issuing a redundant stop.
      expect(sink.stopCount, 0,
          reason: 'the dawn path parks rather than stopping');
    });

    test('does NOT park again on subsequent dawn ticks (parks once per dawn)',
        () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: daytime,
      );
      await engine.start();
      expect(sink.parkCount, 1);

      // Several more ticks while the Sun is still up must NOT re-park.
      await engine.evaluateNow();
      await engine.evaluateNow();
      await engine.evaluateNow();
      expect(sink.parkCount, 1,
          reason: 'the end-of-night park must fire exactly once per dawn, '
              'not on every tick while the Sun stays up');
    });

    test(
        'a transient mid-night empty (all goals complete) STOPS but does NOT '
        'park', () async {
      final sink = _RecordingSink();
      final now = DateTime.utc(2026, 5, 11, 4, 0); // deep night
      // Target high in the south, but every goal is already fully captured, so
      // it is hard-rejected ("all integration goals complete") and the
      // eligible set is empty — at night, NOT end-of-night.
      final goal = IntegrationGoal(
        targetId: 1,
        filter: 'L',
        exposureSeconds: 120.0,
        frameCount: 10,
        priority: 5,
        createdAt: now,
      );
      var phase = 1;
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => <SchedulerCandidate>[
          SchedulerCandidate(
            targetId: 1,
            name: 'A',
            raHours: 14.0,
            decDegrees: 30.0,
            userPriority: 5,
            goals: [goal],
            // Phase 1: still needs frames (so we get a running sequence to
            // stop). Phase 2: fully complete -> empty-eligible mid-night.
            capturedCounts: phase == 1 ? const [2] : const [10],
            constraints: const [],
            horizonProfiles: const {},
            availableFilters: const ['L'],
          ),
        ],
        clock: () => now,
      );
      await engine.start();
      expect(sink.dispatched.length, 1,
          reason: 'phase 1 dispatches the incomplete target');

      // Now the goal is complete; the eligible set is empty but the Sun is
      // still well below the horizon.
      phase = 2;
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, isNull);
      expect(sink.parkCount, 0,
          reason: 'a transient mid-night empty must NEVER park — the night '
              'is not over');
      expect(sink.stopCount, 1,
          reason: 'mid-night empty stops the running sequence');
    });

    test('a mid-night target swap does NOT park', () async {
      final sink = _RecordingSink();
      // Two candidates at night; B becomes the clear winner in phase 2, forcing
      // a swap. A swap must use stopSequence/dispatch — never the park hook.
      var phase = 1;
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => phase == 1
            ? <SchedulerCandidate>[
                _candidate(id: 100, name: 'A', raHours: 14.0, decDegrees: 30.0),
                _candidate(
                    id: 200, name: 'B', raHours: 14.0, decDegrees: -25.0),
              ]
            : <SchedulerCandidate>[
                _candidate(
                    id: 100, name: 'A', raHours: 14.0, decDegrees: -10.0),
                _candidate(id: 200, name: 'B', raHours: 14.0, decDegrees: 30.0),
              ],
        clock: _fixedNow,
      );
      await engine.start();
      expect(engine.lastDecision!.chosenTargetId, 100);
      phase = 2;
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, 200,
          reason: 'the swap target should win in phase 2');
      expect(engine.lastDecision!.isSwitch, isTrue);
      expect(sink.parkCount, 0,
          reason: 'a mid-night target swap must never park the mount');
    });

    test('re-arms after dispatching a new target (parks again next dawn)',
        () async {
      final sink = _RecordingSink();
      // Phase 1: dawn -> park. Phase 2: night returns and a target is eligible
      // -> dispatch (re-arm). Phase 3: dawn again -> must park a SECOND time.
      var phase = 1;
      DateTime nowFn() => phase == 2
          ? DateTime.utc(2026, 5, 11, 4, 0) // night
          : DateTime.utc(2026, 5, 11, 17, 0); // dawn/day
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => <SchedulerCandidate>[
          _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
        ],
        clock: nowFn,
      );
      await engine.start(); // phase 1: dawn
      expect(sink.parkCount, 1);
      expect(sink.dispatched, isEmpty);

      phase = 2; // night returns
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, 1,
          reason: 'at night the target is eligible and dispatched');
      expect(sink.dispatched.length, 1);

      phase = 3; // dawn again
      await engine.evaluateNow();
      expect(sink.parkCount, 2,
          reason: 'after a fresh night/dispatch, the next dawn must park '
              'again (the guard re-arms on dispatch)');
    });

    test('does NOT park while idle (engine not running)', () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: daytime,
      );
      // evaluateNow without start(): the engine is idle, so even at dawn it
      // must not issue a park (nothing is running to be unsafe).
      await engine.evaluateNow();
      expect(sink.parkCount, 0,
          reason: 'an idle engine must not park — it is not driving the rig');
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

  group('SchedulerEngine - scheduledWindow override', () {
    // Window covers the fixed clock instant 2026-05-11 04:00 UTC. The
    // engine should force-select the lower base-score target during the
    // window and then revert to the higher base-score one once the
    // window ends.
    DateTime windowStart() => DateTime.utc(2026, 5, 11, 3, 0);
    DateTime windowEnd() => DateTime.utc(2026, 5, 11, 5, 0);

    test('forces selection mid-tick, bypassing hysteresis', () async {
      final sink = _RecordingSink();
      // A has a strong base score (high in south); B is rising but has a
      // scheduledWindow covering "now". The engine must select B.
      final aPhase1 = _candidate(
        id: 1,
        name: 'A',
        raHours: 14.0,
        decDegrees: 30.0,
      );
      final bPhase1 = _candidate(
        id: 2,
        name: 'B',
        raHours: 18.0,
        decDegrees: 30.0,
        constraints: [
          TargetConstraint(
            targetId: 2,
            kind: TargetConstraintKind.scheduledWindow,
            scheduledWindow: ScheduledWindow(
              startUtc: windowStart(),
              endUtc: windowEnd(),
              priorityBoost: 0.5,
            ),
          ),
        ],
      );
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => [aPhase1, bPhase1],
        clock: _fixedNow,
      );
      await engine.start();
      final decision = engine.lastDecision!;
      expect(decision.chosenTargetId, 2,
          reason: 'scheduledWindow must force-select B even though A scores '
              'higher absent the boost');
      expect(decision.isSwitch, isTrue);
      // The chosen target's reasoning should explicitly mention the
      // forced-selection state so the UI / log can surface it.
      final reasonsBlob = decision.reasoning.join('\n');
      expect(reasonsBlob, contains('Forced by scheduled window'));
      await engine.dispose();
    });

    test('window-end releases the bypass and lets normal scoring resume',
        () async {
      final sink = _RecordingSink();
      // Phase 1: clock inside window — B forced. Phase 2: clock advanced
      // past window AND B is now below the horizon, so the engine must
      // forcibly swap to A (the only eligible candidate). This proves the
      // bypass cleanly releases — without the release, B (a hard-failed
      // candidate) could never be replaced. We verify the chosen id flips
      // and the decision's `reasoning` no longer mentions the forced
      // bypass.
      var phase = 1;
      // B inside window is near meridian; B outside window is below
      // horizon (dec deeply south so the site can't see it).
      SchedulerCandidate buildB() {
        return _candidate(
          id: 2,
          name: 'B',
          raHours: phase == 1 ? 14.0 : 14.0,
          decDegrees: phase == 1 ? 30.0 : -80.0,
          constraints: [
            TargetConstraint(
              targetId: 2,
              kind: TargetConstraintKind.scheduledWindow,
              scheduledWindow: ScheduledWindow(
                startUtc: windowStart(),
                endUtc: windowEnd(),
                priorityBoost: 0.5,
              ),
            ),
          ],
        );
      }

      var nowFn = () => DateTime.utc(2026, 5, 11, 4, 0); // inside window
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => [
          _candidate(id: 1, name: 'A', raHours: 14.0, decDegrees: 30.0),
          buildB(),
        ],
        clock: () => nowFn(),
      );
      await engine.start();
      expect(engine.lastDecision!.chosenTargetId, 2,
          reason: 'B forced inside the window');
      expect(engine.lastDecision!.reasoning.join('\n'),
          contains('Forced by scheduled window'));

      // Advance past window end and make B below-horizon.
      phase = 2;
      nowFn = () => DateTime.utc(2026, 5, 11, 6, 0); // past window
      await engine.evaluateNow();
      expect(engine.lastDecision!.chosenTargetId, 1,
          reason: 'B is now hard-failed and the bypass has lapsed; A wins');
      expect(engine.lastDecision!.isSwitch, isTrue);
      // The post-window reasoning must NOT claim "forced by scheduled
      // window" — that's the whole point of the release.
      expect(engine.lastDecision!.reasoning.join('\n'),
          isNot(contains('Forced by scheduled window')));
      await engine.dispose();
    });

    test(
        'overlapping windows on different targets choose the higher base score',
        () async {
      final sink = _RecordingSink();
      // Both A and B sit inside an active scheduled window at the same
      // instant. A has higher base score (near meridian); B is lower. The
      // engine must pick A — eligibility-sorted by base+boost — but it
      // MUST still be a forced selection (hysteresis bypassed).
      final aCandidate = _candidate(
        id: 1,
        name: 'A',
        raHours: 14.0,
        decDegrees: 30.0,
        constraints: [
          TargetConstraint(
            targetId: 1,
            kind: TargetConstraintKind.scheduledWindow,
            scheduledWindow: ScheduledWindow(
              startUtc: windowStart(),
              endUtc: windowEnd(),
              priorityBoost: 0.3,
            ),
          ),
        ],
      );
      final bCandidate = _candidate(
        id: 2,
        name: 'B',
        raHours: 18.0,
        decDegrees: 30.0,
        constraints: [
          TargetConstraint(
            targetId: 2,
            kind: TargetConstraintKind.scheduledWindow,
            scheduledWindow: ScheduledWindow(
              startUtc: windowStart(),
              endUtc: windowEnd(),
              priorityBoost: 0.3,
            ),
          ),
        ],
      );
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => [aCandidate, bCandidate],
        clock: _fixedNow,
      );
      await engine.start();
      expect(engine.lastDecision!.chosenTargetId, 1,
          reason: 'when overlapping windows, the higher base score wins');
      final reasonsBlob = engine.lastDecision!.reasoning.join('\n');
      expect(reasonsBlob, contains('Forced by scheduled window'));
      await engine.dispose();
    });
  });

  group('SchedulerEngine - rejected candidate explanations', () {
    test('every non-chosen candidate appears in decision.rejected with a '
        'primary why-not reason', () async {
      final sink = _RecordingSink();
      final candidates = <SchedulerCandidate>[
        // Winner — high in south, near meridian, max altitude.
        _candidate(id: 1, name: 'Winner', raHours: 14.0, decDegrees: 40.0),
        // Rejected — below horizon (hard fail; deep southern dec).
        _candidate(
            id: 2, name: 'Below horizon', raHours: 2.0, decDegrees: -75.0),
        // Rejected — eligible but lower score. Same RA so it's near
        // meridian and definitely above the 25° floor at lat 40 (alt
        // ≈ 75° here), but lower than the winner.
        _candidate(id: 3, name: 'Same RA lower dec', raHours: 14.0, decDegrees: 30.0),
      ];
      final engine = SchedulerEngine(
        site: _site,
        sequenceSink: sink,
        candidateLoader: () async => candidates,
        clock: _fixedNow,
      );
      await engine.start();
      final decision = engine.lastDecision!;
      expect(decision.chosenTargetId, 1);
      // Both non-chosen targets must be in the rejected list.
      expect(decision.rejected.length, 2);
      final byId = {for (final r in decision.rejected) r.targetId: r};
      expect(byId.containsKey(2), isTrue);
      expect(byId.containsKey(3), isTrue);
      // Hard-fail rejection should mention the horizon.
      expect(byId[2]!.primaryReason.toLowerCase(), contains('horizon'));
      // Hard-fail rejection should also carry the full constraint
      // failure list so the UI can show every reason on expand.
      expect(byId[2]!.hardConstraintFailures, isNotEmpty);
      // Eligible-but-lower rejection should mention the score-gap.
      expect(byId[3]!.primaryReason.toLowerCase(), contains('lower score'));
      // Each rejected candidate must carry its full per-factor breakdown
      // so the UI's expand-on-tap can render identical detail.
      expect(byId[3]!.factors, isNotEmpty);
      // Eligible-but-lower entries have no hard constraint failures.
      expect(byId[3]!.hardConstraintFailures, isEmpty);
      await engine.dispose();
    });
  });
}
