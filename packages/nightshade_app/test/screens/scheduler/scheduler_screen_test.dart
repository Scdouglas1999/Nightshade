// Widget tests for the Scheduler screen.
//
// We don't spin up the full Riverpod graph (which would require a real
// drift database, an Ffi backend, and the full event bus). Instead we
// override the three providers the screen actually reads
// (schedulerEngineProvider, schedulerStatusProvider,
// currentSchedulerDecisionProvider, plus the integration goals + active
// equipment profile providers) with deterministic test doubles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/scheduler/scheduler_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _FakeSink implements SchedulerSequenceSink {
  @override
  Future<void> dispatchSequence(Sequence sequence) async {}
  @override
  Future<void> pauseSequence() async {}
  @override
  Future<void> resumeSequence() async {}
  @override
  Future<void> stopSequence() async {}
}

SchedulerEngine _buildTestEngine() {
  return SchedulerEngine(
    site: const SchedulerSite(
      latitudeDegrees: 40.0,
      longitudeDegrees: -75.0,
      localOffset: Duration(hours: -5),
    ),
    sequenceSink: _FakeSink(),
    candidateLoader: () async => const <SchedulerCandidate>[],
    clock: () => DateTime.utc(2026, 5, 11, 4, 0),
  );
}

TargetScore _score({
  required int id,
  required String name,
  required double total,
  bool hardFail = false,
  List<String> rejections = const [],
}) {
  return TargetScore(
    targetId: id,
    targetName: name,
    totalScore: total,
    factors: const [
      ScoreFactor(
          name: 'altitude', value: 0.7, weight: 1.0, weighted: 0.7),
      ScoreFactor(
          name: 'meridian', value: 0.5, weight: 1.0, weighted: 0.5),
    ],
    hardConstraintFailed: hardFail,
    rejectionReasons: rejections,
  );
}

SchedulerDecision _decisionWith({
  required int? chosenId,
  required String? chosenName,
  required List<TargetScore> scored,
}) {
  return SchedulerDecision(
    chosenTargetId: chosenId,
    chosenTargetName: chosenName,
    score: chosenId != null ? scored.first.totalScore : 0.0,
    reasoning: [
      if (chosenName != null)
        'Chose $chosenName at 2026-05-11T04:00:00Z (manual)'
      else
        'No eligible candidates',
    ],
    scoredCandidates: scored,
    evaluatedAt: DateTime.utc(2026, 5, 11, 4, 0),
    isSwitch: chosenId != null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders queue, decision panel, and control buttons',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = _buildTestEngine();
    final decision = _decisionWith(
      chosenId: 1,
      chosenName: 'NGC 7000',
      scored: [
        _score(id: 1, name: 'NGC 7000', total: 2.4),
        _score(id: 2, name: 'M31', total: 1.8),
        _score(
          id: 3,
          name: 'Setting Object',
          total: 0.3,
          hardFail: true,
          rejections: ['altitude 12.3° below site minimum 25.0°'],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schedulerEngineProvider.overrideWithValue(engine),
          schedulerStatusProvider.overrideWith((ref) {
            return _FakeStatusNotifier(const SchedulerStatus(
              state: SchedulerState.idle,
            ));
          }),
          currentSchedulerDecisionProvider.overrideWith((ref) {
            return _FakeDecisionNotifier(decision);
          }),
          allIntegrationGoalsProvider.overrideWith(
            (ref) async => <IntegrationGoal>[],
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: SchedulerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Header and state badge.
    expect(find.text('Scheduler'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);

    // Three control buttons should be present in idle state: Start +
    // Re-evaluate (Pause/Resume/Stop hidden while idle).
    expect(find.widgetWithText(NightshadeButton, 'Start'), findsOneWidget);
    expect(find.widgetWithText(NightshadeButton, 'Re-evaluate'),
        findsOneWidget);

    // Active target name appears in the decision panel.
    expect(find.text('NGC 7000'), findsAtLeastNWidgets(1));
    // The queue table heading.
    expect(find.text('Target queue'), findsOneWidget);
    // All three candidate names render in the queue.
    expect(find.text('M31'), findsOneWidget);
    expect(find.text('Setting Object'), findsOneWidget);
  });

  testWidgets('running state shows Pause and Stop buttons', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = _buildTestEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schedulerEngineProvider.overrideWithValue(engine),
          schedulerStatusProvider.overrideWith((ref) {
            return _FakeStatusNotifier(SchedulerStatus(
              state: SchedulerState.running,
              currentTargetId: 1,
              currentTargetName: 'NGC 7000',
              nextEvaluationAt:
                  DateTime.now().add(const Duration(seconds: 45)),
            ));
          }),
          currentSchedulerDecisionProvider.overrideWith((ref) {
            return _FakeDecisionNotifier(_decisionWith(
              chosenId: 1,
              chosenName: 'NGC 7000',
              scored: [_score(id: 1, name: 'NGC 7000', total: 2.4)],
            ));
          }),
          allIntegrationGoalsProvider.overrideWith(
            (ref) async => <IntegrationGoal>[],
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: SchedulerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Running'), findsOneWidget);
    expect(find.widgetWithText(NightshadeButton, 'Pause'), findsOneWidget);
    expect(find.widgetWithText(NightshadeButton, 'Stop'), findsOneWidget);
    expect(find.widgetWithText(NightshadeButton, 'Start'), findsNothing);
  });
}

class _FakeStatusNotifier extends SchedulerStatusNotifier {
  _FakeStatusNotifier(SchedulerStatus initial) : super(_DummyEngine()) {
    // ignore: invalid_use_of_protected_member
    state = initial;
  }
}

class _FakeDecisionNotifier extends CurrentSchedulerDecisionNotifier {
  _FakeDecisionNotifier(SchedulerDecision? initial) : super(_DummyEngine()) {
    // ignore: invalid_use_of_protected_member
    state = initial;
  }
}

/// Bare-bones SchedulerEngine that satisfies the notifier constructor
/// signature without doing any real work — the fake notifiers above only
/// pass their initial state up to the StateNotifier base class and never
/// listen to the engine's streams (the streams are still live, but they
/// emit nothing so the fake state stays put).
class _DummyEngine extends SchedulerEngine {
  _DummyEngine()
      : super(
          site: const SchedulerSite(
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            localOffset: Duration.zero,
          ),
          sequenceSink: _FakeSink(),
          candidateLoader: () async => const <SchedulerCandidate>[],
        );
}
