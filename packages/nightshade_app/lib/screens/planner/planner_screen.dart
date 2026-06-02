import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../framing/altitude_chart.dart';
import '../../localization/nightshade_localizations.dart';
import '../../utils/plan_tonight_sequencer_helper.dart';
import 'widgets/progress_tab_content.dart';
import 'widgets/projects_tab_content.dart';
import 'widgets/scheduler_tab_content.dart';
import 'widgets/week_forecast_strip.dart';
// ---------------------------------------------------------------------------
// File split: the rest of this library lives in `planner_screen_parts/`.
// Each part is `part of '../planner_screen.dart';` and contains a cohesive
// group of private widgets / helpers. Imports are owned here so part files
// inherit the same symbol scope.
// ---------------------------------------------------------------------------

part 'planner_screen_parts/_recommendation_tab.dart';
part 'planner_screen_parts/_header_and_controls_bar.dart';
part 'planner_screen_parts/_filter_controls.dart';
part 'planner_screen_parts/_candidate_list.dart';
part 'planner_screen_parts/_filtered_empty_state.dart';
part 'planner_screen_parts/_primary_target_card.dart';
part 'planner_screen_parts/_search_results.dart';

/// Identifies a Plan Tonight sub-tab for deep-linking via `?tab=` query
/// param. Order here matches the rendered tab order; Recommendation is the
/// default.
///
/// Order rationale — the tabs read left-to-right as a planning-to-execution
/// funnel, grouped by intent rather than by build order:
///   * [recommendation] — "what's best right now" (the landing page / default).
///   * [projects] — sits next to Recommendation because both are *planning
///     intent*: choose a campaign and set multi-night integration goals.
///   * [scheduler] — the dynamic target queue: *execution sequencing* of the
///     chosen work across the night.
///   * [week] — sits next to the scheduler because both are *execution-timing
///     intent*: the seven-night forecast answers "which upcoming nights to run
///     the queue on".
///   * [progress] — the retrospective roll-up, naturally last.
///
/// The rendered `tabs` list and the `IndexedStack` children in
/// [_PlannerScreenState.build] are kept in lockstep with this order because the
/// selected-tab index is [PlannerTab.index]; reordering here without matching
/// both lists would mis-route deep-links and tab taps.
enum PlannerTab {
  recommendation,
  projects,
  scheduler,
  week,
  progress,
}

/// Maps the router `?tab=` query value to a [PlannerTab]. Returns null for
/// an unrecognised value so the caller can fall back to a default. Public
/// so router code (and tests) can share the same canonical mapping.
PlannerTab? plannerTabFromQuery(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case 'recommendation':
    case 'recommend':
      return PlannerTab.recommendation;
    case 'projects':
    case 'project':
    case 'campaign':
    case 'campaigns':
      return PlannerTab.projects;
    case 'scheduler':
    case 'queue':
    case 'target-queue':
    case 'targetqueue':
      return PlannerTab.scheduler;
    case 'week':
    case 'forecast':
    case 'thisweek':
    case 'this-week':
      return PlannerTab.week;
    case 'progress':
    case 'history':
      return PlannerTab.progress;
  }
  return null;
}

/// Page size for the candidate list. The list starts at one page and grows
/// when the user taps "Load more" or scrolls to the bottom.
const int _kPlannerPageSize = 25;

/// FutureProvider that produces tonight's optimization plan from the
/// unfiltered suggestion pool. The primary recommendation is "best of
/// everything tonight" so it never disappears when the user narrows filters.
final _plannerOptimizationProvider =
    FutureProvider.autoDispose<SessionOptimizationPlan>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  if (settings.latitude == 0.0 && settings.longitude == 0.0) {
    throw StateError(
      'Observing location is not configured. '
      'Set your latitude and longitude in Settings before using the planner.',
    );
  }
  final suggestions = await ref.watch(tonightSuggestionsProvider.future);
  final exposureContext = suggestions.isEmpty
      ? null
      : await ref.watch(smartNightExposureContextProvider.future);
  return ref.watch(sessionOptimizerServiceProvider).buildPlanFromSuggestions(
        suggestions,
        generatedAt: DateTime.now(),
        exposureContext: exposureContext,
      );
});

/// Tracks how many candidate rows are currently rendered. Increments by
/// [_kPlannerPageSize] each time the user requests more.
final _plannerVisibleCountProvider = StateProvider.autoDispose<int>(
  (_) => _kPlannerPageSize,
);

/// Full "Plan Tonight" workspace.
///
/// Five sub-tabs (W8-SCHED-MERGE + multi-night planning, C11):
///   * Recommendation — the primary scoring engine: best target right now,
///     filterable / sortable / searchable candidate list, SIMBAD fallback,
///     risk factors and rationale.
///   * Projects — the multi-night campaign layer ([ProjectsTabContent], C9):
///     group targets into a campaign, set per-filter integration goals, and
///     track accrued-vs-remaining progress across clear nights. Includes the
///     C11 Smart Night handoff: "Plan in Smart Night" seeds the wizard with the
///     active campaign's still-incomplete targets so one click plans the
///     campaign rather than the generic "best of everything tonight" set.
///   * Target Queue — RoboTarget-class dynamic scheduler, formerly the
///     standalone `/scheduler` screen. The body is embedded via
///     [SchedulerTabContent] so the `/scheduler` deep-link redirect lands
///     on the same code path.
///   * This Week — the seven-night forecast strip ([WeekForecastStrip], C10):
///     ranks upcoming nights for the active campaign's incomplete targets.
///   * Progress — per-target imaging progress + ETA, consumes
///     `allTargetProgressProvider`.
///
/// Query param `?tab=` selects the initial tab via [plannerTabFromQuery].
class PlannerScreen extends ConsumerStatefulWidget {
  /// Optional initial tab selection. When null, falls back to
  /// [initialTabQuery] parsing, then to [PlannerTab.recommendation].
  final PlannerTab? initialTab;

  /// Raw `?tab=` value parsed from the router. Lets deep-links select a
  /// specific Plan Tonight tab (notably `?tab=scheduler` from the legacy
  /// `/scheduler` redirect).
  final String? initialTabQuery;

  const PlannerScreen({
    super.key,
    this.initialTab,
    this.initialTabQuery,
  });

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late int _currentSubTab;

  @override
  void initState() {
    super.initState();
    final resolved = widget.initialTab ??
        plannerTabFromQuery(widget.initialTabQuery) ??
        PlannerTab.recommendation;
    _currentSubTab = resolved.index;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Order MUST match [PlannerTab] declaration order: the selected index is
    // [PlannerTab.index], so a mismatch would mis-route deep-links and taps.
    // The assert is a developer guard against future drift; the tab-structure
    // tests assert the same invariant at runtime. Each tab carries an icon so
    // [AdaptiveTabBar] can collapse to icon-only on a compact phone rather than
    // overflowing the five tabs.
    final tabs = <(PlannerTab, AdaptiveTab)>[
      (
        PlannerTab.recommendation,
        const AdaptiveTab(label: 'Recommendation', icon: LucideIcons.sparkles),
      ),
      (
        PlannerTab.projects,
        const AdaptiveTab(label: 'Projects', icon: LucideIcons.folderKanban),
      ),
      (
        PlannerTab.scheduler,
        const AdaptiveTab(label: 'Target Queue', icon: LucideIcons.listOrdered),
      ),
      (
        PlannerTab.week,
        const AdaptiveTab(label: 'This Week', icon: LucideIcons.calendarDays),
      ),
      (
        PlannerTab.progress,
        const AdaptiveTab(label: 'Progress', icon: LucideIcons.trendingUp),
      ),
    ];
    assert(
      tabs.length == PlannerTab.values.length &&
          tabs.asMap().entries.every((e) => e.value.$1.index == e.key),
      'Planner tab list is out of sync with PlannerTab: each entry must sit at '
      'its enum index and the list must cover every value.',
    );

    // On a phone the bottom nav already names the screen, so the standalone
    // ~56px "Plan Tonight" title row is dead vertical space — costly on a short
    // landscape phone (e.g. a Fold cover screen). Fold a compact title inline to
    // the left of the (scrollable) tab strip so the two collapse into a single
    // row. Tablet/desktop keep the full title header above the tabs.
    final isPhone = Responsive.isPhone(context);

    final tabBar = AdaptiveTabBar(
      tabs: [for (final t in tabs) t.$2],
      selectedIndex: _currentSubTab,
      onSelected: (index) => setState(() => _currentSubTab = index),
      // On phone the leading title icon already supplies the left inset, so the
      // tab strip starts tight against it.
      horizontalPadding:
          isPhone ? NightshadeTokens.spaceSm : NightshadeTokens.spaceLg,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            if (!isPhone) _PlannerHeader(colors: colors),
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: isPhone
                  ? Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: NightshadeTokens.spaceLg,
                            right: NightshadeTokens.spaceSm,
                          ),
                          child: Icon(
                            LucideIcons.moonStar,
                            size: 18,
                            color: colors.primary,
                          ),
                        ),
                        Expanded(child: tabBar),
                      ],
                    )
                  : tabBar,
            ),
            Expanded(
              child: IndexedStack(
                index: _currentSubTab,
                // Order MUST match `tabs` / [PlannerTab] — one child per enum
                // value, at the same index.
                children: const [
                  _RecommendationTab(),
                  ProjectsTabContent(),
                  SchedulerTabContent(),
                  WeekForecastStrip(),
                  ProgressTabContent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
