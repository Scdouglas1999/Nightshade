// Tab-wiring tests for the multi-night planner (component C11).
//
// These complement `planner_screen_test.dart` (which covers the pre-existing
// Recommendation / Target Queue / Progress tabs) by asserting the *new* wiring:
// the Projects (C9) and This Week (C10) tabs, their `?tab=` deep-links, and the
// structural invariant that the rendered tab list and the IndexedStack child
// list stay in lockstep with the `PlannerTab` enum (the selected index is
// `PlannerTab.index`, so any drift mis-routes deep-links and taps).
//
// The planner body is an IndexedStack, which builds *every* child eagerly, so
// the leaf providers each tab reads must resolve without a real drift database
// or HTTP client. We override exactly those leaves with deterministic doubles,
// mirroring the override set in `planner_screen_test.dart` and the per-tab
// tests (`projects_tab_content_test.dart`, `week_forecast_strip_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_app/screens/planner/widgets/projects_tab_content.dart';
import 'package:nightshade_app/screens/planner/widgets/scheduler_tab_content.dart';
import 'package:nightshade_app/screens/planner/widgets/progress_tab_content.dart';
import 'package:nightshade_app/screens/planner/widgets/week_forecast_strip.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../scheduler/scheduler_test_doubles.dart';

/// Stub AppSettingsNotifier with a real lat/lon so the planner's location
/// guard short-circuits without hitting the DB (the new forecast tab uses the
/// same guard). Mirrors the stub in `planner_screen_test.dart`.
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async {
    return const AppSettingsState(latitude: 40.0, longitude: -75.0);
  }
}

/// The full leaf-override set for pumping the whole [PlannerScreen]. Every tab
/// in the IndexedStack is built eagerly, so all five tabs' leaf providers are
/// stubbed here.
List<Override> _allTabOverrides() {
  return [
    // Recommendation tab.
    tonightSuggestionsProvider.overrideWith((ref) async => const []),
    smartNightExposureContextProvider.overrideWith((ref) async => null),
    appSettingsProvider.overrideWith(() => _StubAppSettingsNotifier()),
    // Progress tab.
    allTargetProgressProvider.overrideWith(
      (ref) async => <int, TargetProgress>{},
    ),
    // Target Queue (scheduler) tab.
    schedulerEngineProvider.overrideWithValue(buildTestSchedulerEngine()),
    schedulerStatusProvider.overrideWith(
      (ref) => FakeSchedulerStatusNotifier(
        const SchedulerStatus(state: SchedulerState.idle),
      ),
    ),
    currentSchedulerDecisionProvider.overrideWith(
      (ref) => FakeCurrentSchedulerDecisionNotifier(null),
    ),
    allIntegrationGoalsProvider
        .overrideWith((ref) async => <IntegrationGoal>[]),
    integrationGoalProgressProvider
        .overrideWith((ref, _) async => <IntegrationGoalProgress>[]),
    // Projects tab (C9).
    projectListProvider.overrideWith((ref) => Stream.value(const <Project>[])),
    activeProjectProgressProvider.overrideWith((ref) async => null),
    // This Week tab (C10) — fail-closed forecast double, no HTTP.
    weekForecastProvider.overrideWith(
      (ref) async => const WeekForecast.unavailable(
        'Forecast disabled in tab-structure tests.',
      ),
    ),
  ];
}

Widget _harness({PlannerTab? initialTab, String? initialTabQuery}) {
  return ProviderScope(
    overrides: _allTabOverrides(),
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: PlannerScreen(
          initialTab: initialTab,
          initialTabQuery: initialTabQuery,
        ),
      ),
    ),
  );
}

Finder _selectedTab(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == label &&
          widget.isSelected,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('plannerTabFromQuery — Projects + This Week wiring', () {
    test('maps the Projects canonical name and aliases', () {
      expect(plannerTabFromQuery('projects'), PlannerTab.projects);
      expect(plannerTabFromQuery('project'), PlannerTab.projects);
      expect(plannerTabFromQuery('campaign'), PlannerTab.projects);
      expect(plannerTabFromQuery('campaigns'), PlannerTab.projects);
    });

    test('maps the This Week canonical name and aliases', () {
      expect(plannerTabFromQuery('week'), PlannerTab.week);
      expect(plannerTabFromQuery('forecast'), PlannerTab.week);
      expect(plannerTabFromQuery('thisweek'), PlannerTab.week);
      expect(plannerTabFromQuery('this-week'), PlannerTab.week);
    });

    test('is case-insensitive for the new tabs', () {
      expect(plannerTabFromQuery('Projects'), PlannerTab.projects);
      expect(plannerTabFromQuery('CAMPAIGNS'), PlannerTab.projects);
      expect(plannerTabFromQuery('Week'), PlannerTab.week);
      expect(plannerTabFromQuery('This-Week'), PlannerTab.week);
    });

    test('still maps the pre-existing tabs (no regression)', () {
      expect(plannerTabFromQuery('recommendation'), PlannerTab.recommendation);
      expect(plannerTabFromQuery('scheduler'), PlannerTab.scheduler);
      expect(plannerTabFromQuery('progress'), PlannerTab.progress);
    });

    test('returns null for junk and for null', () {
      expect(plannerTabFromQuery(null), isNull);
      expect(plannerTabFromQuery(''), isNull);
      expect(plannerTabFromQuery('weeky'), isNull);
      expect(plannerTabFromQuery('project-x'), isNull);
      expect(plannerTabFromQuery('not-a-tab'), isNull);
    });

    test('enum declares the intended planning-to-execution order', () {
      // C11 ordering decision: Projects sits next to Recommendation (planning
      // intent); This Week sits next to the scheduler queue (execution-timing
      // intent). Guards against an accidental reorder of the enum.
      expect(
        PlannerTab.values,
        const [
          PlannerTab.recommendation,
          PlannerTab.projects,
          PlannerTab.scheduler,
          PlannerTab.week,
          PlannerTab.progress,
        ],
      );
    });
  });

  group('PlannerScreen tab structure', () {
    void sizeDesktop(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets(
        'tab list length and IndexedStack child count both equal '
        'PlannerTab.values.length (enum/list drift guard)', (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 200));

      // One SubTabButton per enum value.
      expect(
        find.byType(SubTabButton),
        findsNWidgets(PlannerTab.values.length),
        reason: 'The rendered tab strip must have exactly one button per '
            'PlannerTab value; a mismatch means the tabs list drifted from '
            'the enum.',
      );

      // One IndexedStack child per enum value. A tab body (the embedded
      // scheduler) may nest its own IndexedStack, so identify the planner's
      // top-level stack as the one whose children are the tab bodies.
      // IndexedStack keeps unselected children mounted but Offstage, so we
      // must inspect the widget config directly rather than rely on rendered
      // descendants.
      final plannerStack = tester
          .widgetList<IndexedStack>(
            find.byType(IndexedStack, skipOffstage: false),
          )
          .singleWhere(
            (s) => s.children.any((c) => c is ProjectsTabContent),
            orElse: () => throw StateError(
              'No IndexedStack holds the planner tab bodies.',
            ),
          );
      expect(
        plannerStack.children.length,
        PlannerTab.values.length,
        reason: 'The IndexedStack must hold exactly one child per PlannerTab '
            'value; the selected index is PlannerTab.index, so a missing or '
            'extra child mis-routes the body for some tab.',
      );

      // The new tab bodies are present in the stack (built eagerly by
      // IndexedStack, though Offstage when not selected), proving the children
      // list was actually extended and not just the strip labels.
      expect(
        find.byType(ProjectsTabContent, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byType(SchedulerTabContent, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byType(WeekForecastStrip, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byType(ProgressTabContent, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('?tab=projects selects the Projects tab on initial render',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness(initialTabQuery: 'projects'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('Projects'), findsOneWidget);
      expect(_selectedTab('Recommendation'), findsNothing);
    });

    testWidgets('?tab=campaigns alias selects the Projects tab',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness(initialTabQuery: 'campaigns'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('Projects'), findsOneWidget);
    });

    testWidgets('?tab=week selects the This Week tab on initial render',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness(initialTabQuery: 'week'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('This Week'), findsOneWidget);
      expect(_selectedTab('Recommendation'), findsNothing);
    });

    testWidgets('?tab=forecast alias selects the This Week tab',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness(initialTabQuery: 'forecast'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('This Week'), findsOneWidget);
    });

    testWidgets('junk ?tab= falls back to the default Recommendation tab',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness(initialTabQuery: 'not-a-tab'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('Recommendation'), findsOneWidget);
    });

    testWidgets('tapping the This Week tab switches the selection',
        (tester) async {
      // Covers the user-gesture path (SubTabButton.onTap -> setState) for the
      // newly-inserted tab specifically: a regression that wired the label but
      // dropped the new entry's onTap would still pass the deep-link tests.
      sizeDesktop(tester);
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('Recommendation'), findsOneWidget,
          reason: 'Sanity: Recommendation is the default selection.');

      await tester.tap(find.text('This Week'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('This Week'), findsOneWidget);
      expect(_selectedTab('Recommendation'), findsNothing);
    });

    testWidgets('tapping the Projects tab switches the selection',
        (tester) async {
      sizeDesktop(tester);
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Projects'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(_selectedTab('Projects'), findsOneWidget);
      expect(_selectedTab('Recommendation'), findsNothing);
    });
  });
}
