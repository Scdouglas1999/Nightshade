// Verifies that the scheduler queue / decision panel / editors still
// work when mounted inside the new Plan Tonight → Target Queue tab
// (W8-SCHED-MERGE). The widget under test is the extracted
// [SchedulerTabContent] — the same widget the standalone
// /scheduler shell now embeds.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/planner/widgets/scheduler_tab_content.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as ndb;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../scheduler/scheduler_test_doubles.dart';

List<Override> _commonOverrides({
  IntegrationGoalService? goalService,
  TargetConstraintService? constraintService,
}) {
  return [
    allDbTargetsProvider.overrideWith(
      (ref) => const Stream<List<ndb.Target>>.empty(),
    ),
    integrationGoalsStreamProvider.overrideWith(
      (ref) => const Stream<List<IntegrationGoal>>.empty(),
    ),
    targetConstraintsStreamProvider.overrideWith(
      (ref) => const Stream<List<TargetConstraint>>.empty(),
    ),
    integrationGoalProgressProvider.overrideWith(
      (ref, _) async => <IntegrationGoalProgress>[],
    ),
    if (goalService != null)
      integrationGoalServiceProvider.overrideWithValue(goalService),
    if (constraintService != null)
      targetConstraintServiceProvider.overrideWithValue(constraintService),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'per-row delete icon opens confirmation dialog and on confirm wipes '
      'goals and constraints for that target even when embedded as a Plan '
      'Tonight tab', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = buildTestSchedulerEngine();
    final goalSvc = FakeIntegrationGoalService();
    final constraintSvc = FakeTargetConstraintService();
    final decision = decisionWith(
      chosenId: 1,
      chosenName: 'NGC 7000',
      scored: [
        scoreFor(id: 1, name: 'NGC 7000', total: 2.4),
        scoreFor(id: 2, name: 'M31', total: 1.8),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(
            goalService: goalSvc,
            constraintService: constraintSvc,
          ),
          schedulerEngineProvider.overrideWithValue(engine),
          schedulerStatusProvider.overrideWith((ref) {
            return FakeSchedulerStatusNotifier(const SchedulerStatus(
              state: SchedulerState.idle,
            ));
          }),
          currentSchedulerDecisionProvider.overrideWith((ref) {
            return FakeCurrentSchedulerDecisionNotifier(decision);
          }),
          allIntegrationGoalsProvider.overrideWith(
            (ref) async => <IntegrationGoal>[],
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: SchedulerTabContent()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Tap the delete icon on the second row (target id=2, M31).
    final deleteButton =
        find.byKey(const ValueKey('scheduler-delete-row-2'));
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Remove from scheduler?'), findsOneWidget);
    expect(find.textContaining('Remove M31'), findsOneWidget);

    // Confirm.
    await tester.tap(find.widgetWithText(NightshadeButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(goalSvc.deletedForTarget, [2]);
    expect(constraintSvc.deletedForTarget, [2]);
  });

  testWidgets(
      '"Clear all" button works when SchedulerTabContent is embedded',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = buildTestSchedulerEngine();
    final goalSvc = FakeIntegrationGoalService();
    final constraintSvc = FakeTargetConstraintService();
    final decision = decisionWith(
      chosenId: 1,
      chosenName: 'NGC 7000',
      scored: [
        scoreFor(id: 1, name: 'NGC 7000', total: 2.4),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(
            goalService: goalSvc,
            constraintService: constraintSvc,
          ),
          schedulerEngineProvider.overrideWithValue(engine),
          schedulerStatusProvider.overrideWith((ref) {
            return FakeSchedulerStatusNotifier(const SchedulerStatus(
              state: SchedulerState.idle,
            ));
          }),
          currentSchedulerDecisionProvider.overrideWith((ref) {
            return FakeCurrentSchedulerDecisionNotifier(decision);
          }),
          allIntegrationGoalsProvider.overrideWith(
            (ref) async => <IntegrationGoal>[],
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: SchedulerTabContent()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final clearAll = find.byKey(const ValueKey('scheduler-clear-all'));
    expect(clearAll, findsOneWidget);
    await tester.tap(clearAll);
    await tester.pumpAndSettle();

    expect(find.text('Clear scheduler queue?'), findsOneWidget);
    await tester.tap(find.widgetWithText(NightshadeButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(goalSvc.deleteAllCalls, 1);
    expect(constraintSvc.deleteAllCalls, 1);
  });

  testWidgets('queue header, decision panel, and Target queue render',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = buildTestSchedulerEngine();
    final decision = decisionWith(
      chosenId: 1,
      chosenName: 'NGC 7000',
      scored: [scoreFor(id: 1, name: 'NGC 7000', total: 2.4)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(),
          schedulerEngineProvider.overrideWithValue(engine),
          schedulerStatusProvider.overrideWith((ref) {
            return FakeSchedulerStatusNotifier(const SchedulerStatus(
              state: SchedulerState.idle,
            ));
          }),
          currentSchedulerDecisionProvider.overrideWith((ref) {
            return FakeCurrentSchedulerDecisionNotifier(decision);
          }),
          allIntegrationGoalsProvider.overrideWith(
            (ref) async => <IntegrationGoal>[],
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: SchedulerTabContent()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Scheduler'), findsOneWidget);
    expect(find.text('Target queue'), findsOneWidget);
    expect(find.text('NGC 7000'), findsAtLeastNWidgets(1));
  });
}
