// Tests for the Plan Tonight screen tab structure after Scheduler was
// merged in as a tab (W8-SCHED-MERGE). The full Riverpod graph requires a
// real drift database and FFI backend, so we override the providers each
// tab actually reads with deterministic test doubles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/framing/altitude_chart.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../scheduler/scheduler_test_doubles.dart';

List<Override> _commonOverrides() {
  return [
    // Recommendation tab dependencies — empty pool so the loading state
    // resolves quickly into the "no candidates" empty state without
    // touching the database.
    tonightSuggestionsProvider.overrideWith((ref) async => const []),
    smartNightExposureContextProvider.overrideWith((ref) async => null),
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
    allIntegrationGoalsProvider
        .overrideWith((ref) async => <IntegrationGoal>[]),
    integrationGoalProgressProvider
        .overrideWith((ref, _) async => <IntegrationGoalProgress>[]),
    // Projects tab + This Week tab dependencies. The planner body
    // is an IndexedStack, which builds *every* child eagerly regardless of the
    // selected tab, so these leaf providers must resolve without a DB / HTTP
    // client even when the test only asserts on the Recommendation tab.
    projectListProvider.overrideWith((ref) => Stream.value(const <Project>[])),
    activeProjectProgressProvider.overrideWith((ref) async => null),
    weekForecastProvider.overrideWith(
      (ref) async => const WeekForecast.unavailable(
        'Forecast disabled in tab-structure tests.',
      ),
    ),
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

/// The live [AdaptiveTabBar.selectedIndex] — the single source of truth for
/// which planner tab is active.
int _selectedTabIndex(WidgetTester tester) =>
    tester.widget<AdaptiveTabBar>(find.byType(AdaptiveTabBar)).selectedIndex;

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
      expect(plannerTabFromQuery('recommendation'), PlannerTab.recommendation);
      // Scheduler folded into Schedule; Progress folded into Projects.
      expect(plannerTabFromQuery('scheduler'), PlannerTab.schedule);
      expect(plannerTabFromQuery('progress'), PlannerTab.projects);
    });

    test('accepts case-insensitive aliases', () {
      expect(plannerTabFromQuery('Scheduler'), PlannerTab.schedule);
      expect(plannerTabFromQuery('queue'), PlannerTab.schedule);
      expect(plannerTabFromQuery('target-queue'), PlannerTab.schedule);
      expect(plannerTabFromQuery('history'), PlannerTab.projects);
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

  testWidgets(
      'renders all sub-tabs (Recommendation, Projects, Schedule, '
      'Framing, Planetarium, Discover)', (tester) async {
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

    // The tab strip is now an AdaptiveTabBar; on this 1400px desktop viewport
    // labels render as Text (icons-only collapse only happens below 480px).
    expect(find.byType(AdaptiveTabBar), findsOneWidget);
    final bar = tester.widget<AdaptiveTabBar>(find.byType(AdaptiveTabBar));
    expect(
      bar.tabs.map((t) => t.label).toList(),
      const [
        'Recommendation',
        'Projects',
        'Schedule',
        'Framing',
        'Planetarium',
        'Discover',
      ],
    );
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

    expect(_selectedTabIndex(tester), PlannerTab.recommendation.index);
  });

  testWidgets(
      '?tab=scheduler (folded) selects the Schedule tab on initial '
      'render', (tester) async {
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

    expect(_selectedTabIndex(tester), PlannerTab.schedule.index);
  });

  testWidgets(
      '?tab=progress (folded) selects the Projects tab on initial '
      'render', (tester) async {
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

    expect(_selectedTabIndex(tester), PlannerTab.projects.index);
  });

  // ===========================================================================
  // Behavior tests beyond initial selection.
  // ===========================================================================

  testWidgets(
      'tapping_Target_Queue_tab_switches_selection_away_from_Recommendation: '
      'verifies setState pathway flips _currentSubTab when a sibling tab is '
      'tapped', (tester) async {
    // The initial-selection tests cover where the screen lands at first
    // pump; this one covers the *user gesture* path through
    // SubTabButton.onTap → setState. A regression that left
    // SubTabButton.isSelected wired correctly but broke the tap callback
    // (e.g. by routing the tap through a stale closure) would still pass
    // the static "?tab=" tests but silently freeze the user on whichever
    // tab they landed on.
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

    // Pre-condition: Recommendation selected by default.
    expect(_selectedTabIndex(tester), PlannerTab.recommendation.index,
        reason: 'Sanity: Recommendation must be selected by default.');

    // Tap Schedule. find.text matches the tab's label text.
    await tester.tap(find.text('Schedule'));
    await tester.pump(const Duration(milliseconds: 200));

    // Post-condition: Schedule is selected (single-selection model).
    expect(_selectedTabIndex(tester), PlannerTab.schedule.index,
        reason: 'Tapping the Schedule tab must mark it as selected; if the '
            'onSelected callback or setState pathway is broken the strip would '
            'continue to show Recommendation as selected.');
  });

  testWidgets('tapping the right-most Discover tab switches the selection',
      (tester) async {
    // Companion to the Schedule tap test — covers the right-most tab and
    // proves the tap callback works for every entry, not just a middle one. A
    // regression that dropped the last entry's onSelected (e.g. a missing index
    // in the asMap().entries loop) would pass the Schedule test but fail here.
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

    // Tap Discover (the right-most tab).
    await tester.tap(find.text('Discover'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(_selectedTabIndex(tester), PlannerTab.discover.index,
        reason: 'Tapping Discover must mark it as selected; if the right-most '
            'entry in the tabs loop lost its onSelected, the user gets stuck '
            'on Recommendation.');
  });

  testWidgets('primary recommendation exposes Send to Framing action',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const suggestion = TargetSuggestion(
      targetId: 7,
      targetName: 'North America Nebula',
      raHours: 20.98,
      decDegrees: 44.33,
      totalScore: 91,
      visibility: TargetVisibilityInfo(
        currentAltitude: 62,
        currentAzimuth: 120,
        airmass: 1.1,
        moonDistance: 110,
        peakAltitude: 75,
        hoursAboveMinAlt: 5.5,
      ),
      objectType: 'Emission Nebula',
      magnitude: 4.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(),
          tonightSuggestionsProvider.overrideWith((ref) async => [suggestion]),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: PlannerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.widgetWithText(NightshadeButton, 'Send to Framing'),
      findsNWidgets(2),
      reason:
          'The primary card and the matching candidate row should both offer framing.',
    );
  });

  testWidgets(
      'candidate row exposes a Review in Sequencer action (not only the '
      'primary)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Two distinct suggestions so the optimizer promotes one to the primary
    // card while the other only ever appears as a candidate row. The
    // regression this guards: candidate rows previously had no path to the
    // sequencer, so only the top recommendation could be reviewed.
    const primary = TargetSuggestion(
      targetId: 11,
      targetName: 'North America Nebula',
      raHours: 20.98,
      decDegrees: 44.33,
      totalScore: 95,
      visibility: TargetVisibilityInfo(
        currentAltitude: 62,
        currentAzimuth: 120,
        airmass: 1.1,
        moonDistance: 110,
        peakAltitude: 75,
        hoursAboveMinAlt: 5.5,
      ),
      objectType: 'Emission Nebula',
      magnitude: 4.0,
    );
    const secondary = TargetSuggestion(
      targetId: 12,
      targetName: 'Pelican Nebula',
      raHours: 20.85,
      decDegrees: 44.36,
      totalScore: 80,
      visibility: TargetVisibilityInfo(
        currentAltitude: 60,
        currentAzimuth: 122,
        airmass: 1.15,
        moonDistance: 108,
        peakAltitude: 73,
        hoursAboveMinAlt: 5.2,
      ),
      objectType: 'Emission Nebula',
      magnitude: 8.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(),
          tonightSuggestionsProvider
              .overrideWith((ref) async => [primary, secondary]),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: PlannerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The primary card's full-width button plus each candidate row's button
    // all carry the same "Review in Sequencer" label. With one primary card
    // and two candidate rows that is three occurrences; the key point is that
    // it appears MORE than once, i.e. the candidates are no longer stranded.
    final reviewButtons =
        find.widgetWithText(NightshadeButton, 'Review in Sequencer');
    expect(
      reviewButtons,
      findsNWidgets(3),
      reason:
          'Every candidate row must offer "Review in Sequencer" alongside the '
          'primary card — not just the top recommendation.',
    );
  });

  testWidgets(
      'candidate row shows altitude chart without expand toggle on desktop',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const suggestion = TargetSuggestion(
      targetId: 42,
      targetName: 'Andromeda Galaxy',
      raHours: 0.67,
      decDegrees: 41.27,
      totalScore: 88,
      visibility: TargetVisibilityInfo(
        currentAltitude: 55,
        currentAzimuth: 180,
        airmass: 1.2,
        moonDistance: 90,
        peakAltitude: 70,
        hoursAboveMinAlt: 6.0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._commonOverrides(),
          tonightSuggestionsProvider.overrideWith((ref) async => [suggestion]),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: PlannerScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Show altitude curve'), findsNothing);
    expect(find.text('Hide altitude curve'), findsNothing);
    expect(
      find.byType(AltitudeChart),
      findsNWidgets(2),
      reason:
          'Primary recommendation and candidate row should each show an altitude chart.',
    );
  });
}
