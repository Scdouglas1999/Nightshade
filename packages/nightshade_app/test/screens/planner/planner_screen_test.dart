// Tests for the Plan Tonight screen tab structure after Scheduler was
// merged in as a tab (W8-SCHED-MERGE). The full Riverpod graph requires a
// real drift database and FFI backend, so we override the providers each
// tab actually reads with deterministic test doubles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../scheduler/scheduler_test_doubles.dart';

List<Override> _commonOverrides() {
  return [
    // Recommendation tab dependencies — empty pool so the loading state
    // resolves quickly into the "no candidates" empty state without
    // touching the database.
    tonightSuggestionsProvider.overrideWith((ref) async => const []),
    appSettingsProvider.overrideWith(() => _StubAppSettingsNotifier()),
    // Progress tab dependency.
    allTargetProgressProvider.overrideWith(
      (ref) async => <int, TargetProgress>{},
    ),
    // Scheduler tab dependencies (mirror the scheduler_screen tests).
    schedulerEngineProvider.overrideWithValue(buildTestSchedulerEngine()),
    schedulerStatusProvider.overrideWith(
      (ref) => FakeSchedulerStatusNotifier(
        const SchedulerStatus(state: SchedulerState.idle),
      ),
    ),
    currentSchedulerDecisionProvider.overrideWith(
      (ref) => FakeCurrentSchedulerDecisionNotifier(null),
    ),
    allIntegrationGoalsProvider.overrideWith((ref) async => <IntegrationGoal>[]),
    integrationGoalProgressProvider
        .overrideWith((ref, _) async => <IntegrationGoalProgress>[]),
  ];
}

/// Stub AppSettingsNotifier that immediately provides a known-good config
/// so the planner's location-check guard short-circuits without hitting
/// the DB. We give it a real lat/lon so the screen does not surface the
/// "set your location" error state and confuse the tab-structure assertions.
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async {
    return const AppSettingsState(
      latitude: 40.0,
      longitude: -75.0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('plannerTabFromQuery', () {
    test('returns null for null input', () {
      expect(plannerTabFromQuery(null), isNull);
    });

    test('returns null for an unrecognised value', () {
      expect(plannerTabFromQuery('made-up-tab'), isNull);
    });

    test('maps canonical tab names', () {
      expect(plannerTabFromQuery('recommendation'),
          PlannerTab.recommendation);
      expect(plannerTabFromQuery('scheduler'), PlannerTab.scheduler);
      expect(plannerTabFromQuery('progress'), PlannerTab.progress);
    });

    test('accepts case-insensitive aliases', () {
      expect(plannerTabFromQuery('Scheduler'), PlannerTab.scheduler);
      expect(plannerTabFromQuery('queue'), PlannerTab.scheduler);
      expect(plannerTabFromQuery('target-queue'), PlannerTab.scheduler);
      expect(plannerTabFromQuery('history'), PlannerTab.progress);
      expect(plannerTabFromQuery('recommend'), PlannerTab.recommendation);
    });

    test('Recommendation is the first enum entry', () {
      expect(
        PlannerTab.values.first,
        PlannerTab.recommendation,
        reason:
            'UX consolidation places Recommendation as the default leftmost '
            'tab so the previous Plan Tonight body remains the landing page.',
      );
    });
  });

  testWidgets('renders all three sub-tabs (Recommendation, Target Queue, Progress)',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: PlannerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.widgetWithText(SubTabButton, 'Recommendation'), findsOneWidget);
    expect(find.widgetWithText(SubTabButton, 'Target Queue'), findsOneWidget);
    expect(find.widgetWithText(SubTabButton, 'Progress'), findsOneWidget);
  });

  testWidgets('defaults to Recommendation when no query param is supplied',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: PlannerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final selectedRec = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Recommendation' &&
          widget.isSelected,
    );
    expect(selectedRec, findsOneWidget);
  });

  testWidgets('?tab=scheduler selects the Target Queue tab on initial render',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: PlannerScreen(initialTabQuery: 'scheduler'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final selectedQueue = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Target Queue' &&
          widget.isSelected,
    );
    expect(selectedQueue, findsOneWidget);

    final selectedRec = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Recommendation' &&
          widget.isSelected,
    );
    expect(selectedRec, findsNothing);
  });

  testWidgets('?tab=progress selects the Progress tab on initial render',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: PlannerScreen(initialTabQuery: 'progress'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final selectedProgress = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Progress' &&
          widget.isSelected,
    );
    expect(selectedProgress, findsOneWidget);
  });
}
