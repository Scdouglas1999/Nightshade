import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    hide FramingView;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../framing/altitude_chart.dart';
import '../framing/framing_screen.dart';
import '../planetarium/planetarium_screen.dart';
import '../your_sky/your_sky_screen.dart';
import '../constellation/constellation_screen.dart';
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
part 'planner_screen_parts/_autopilot_preview_banner.dart';
part 'planner_screen_parts/_header_and_controls_bar.dart';
part 'planner_screen_parts/_filter_controls.dart';
part 'planner_screen_parts/_candidate_list.dart';
part 'planner_screen_parts/_filtered_empty_state.dart';
part 'planner_screen_parts/_primary_target_card.dart';
part 'planner_screen_parts/_search_results.dart';
part 'planner_screen_parts/_projects_tab.dart';
part 'planner_screen_parts/_schedule_tab.dart';
part 'planner_screen_parts/_discover_tab.dart';

/// Identifies a Plan Tonight sub-tab for deep-linking via `?tab=` query
/// param. Order here matches the rendered tab order; Recommendation is the
/// default.
///
/// Order rationale — the tabs read left-to-right as a planning-to-execution
/// funnel, grouped by intent rather than by build order:
///   * [recommendation] — "what's best right now" (the landing page / default).
///   * [projects] — the multi-night campaign workspace: pick a campaign and
///     track per-target integration goals, or switch scope to the global
///     all-targets progress roll-up. (Absorbs the former standalone "Progress".)
///   * [schedule] — the seven-night forecast strip atop the dynamic target
///     queue: which upcoming nights to run, and the queue that runs them.
///     (Unifies the former "This Week" forecast + "Target Queue" scheduler.)
///   * [framing] / [planetarium] — the sky-work surfaces promoted to first-class
///     tabs (absorbed from the standalone `/framing` and `/planetarium` routes).
///   * [discover] — the Your Sky / Constellation discovery surfaces.
///
/// The rendered `tabs` list and the `IndexedStack` children in
/// [_PlannerScreenState.build] are kept in lockstep with this order because the
/// selected-tab index is [PlannerTab.index]; reordering here without matching
/// both lists would mis-route deep-links and tab taps.
enum PlannerTab {
  recommendation,
  projects,
  schedule,
  framing,
  planetarium,
  discover,
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
    case 'progress':
    case 'history':
      return PlannerTab.projects;
    case 'schedule':
    case 'scheduler':
    case 'queue':
    case 'target-queue':
    case 'targetqueue':
    case 'week':
    case 'forecast':
    case 'thisweek':
    case 'this-week':
      return PlannerTab.schedule;
    case 'framing':
      return PlannerTab.framing;
    case 'planetarium':
      return PlannerTab.planetarium;
    case 'discover':
    case 'sky':
    case 'yoursky':
    case 'your-sky':
    case 'constellation':
      return PlannerTab.discover;
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
  // Depend on the SELECT-based location provider, not the whole appSettings
  // future. The host broadcasts `settings/updated` very frequently (scheduler
  // runtime config), and awaiting appSettingsProvider.future re-ran this plan —
  // and thus reloaded the Recommendation tab — on every one. appObserverLocation
  // only emits when latitude/longitude actually change, so unrelated settings
  // churn no longer thrashes the tab.
  final location = ref.watch(appObserverLocationProvider);
  if (location == null ||
      (location.latitude == 0.0 && location.longitude == 0.0)) {
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
/// Six sub-tabs:
///   * Recommendation — the primary scoring engine: best target right now,
///     filterable / sortable / searchable candidate list, SIMBAD fallback,
///     risk factors and rationale.
///   * Projects — the multi-night campaign workspace ([_ProjectsTab]): a scope
///     switch between the active campaign's per-target integration goals
///     ([ProjectsTabContent], C9, with the C11 "Plan in Smart Night" handoff)
///     and the global all-targets progress roll-up ([ProgressTabContent]).
///   * Schedule — the seven-night forecast strip ([WeekForecastStrip], C10)
///     pinned above the RoboTarget-class dynamic scheduler ([SchedulerTabContent],
///     formerly the standalone `/scheduler` screen): which nights to run, and the
///     queue that runs them.
///   * Framing / Planetarium — the sky-work surfaces (absorbed from the
///     standalone `/framing` and `/planetarium` routes).
///   * Discover — the Your Sky / Constellation discovery surfaces.
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
  void didUpdateWidget(PlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router keys pages by path, not query, so navigating to a different
    // `?tab=` while the planner is already the active host reuses this State
    // without re-running initState. Re-resolve so deep-links and the in-planner
    // "Send to framing" / scheduler handoffs select the target tab.
    if (widget.initialTabQuery != oldWidget.initialTabQuery) {
      final resolved = plannerTabFromQuery(widget.initialTabQuery);
      if (resolved != null && resolved.index != _currentSubTab) {
        setState(() => _currentSubTab = resolved.index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Order MUST match [PlannerTab] declaration order: the selected index is
    // [PlannerTab.index], so a mismatch would mis-route deep-links and taps.
    // The assert is a developer guard against future drift; the tab-structure
    // tests assert the same invariant at runtime. Each tab carries an icon so
    // [AdaptiveTabBar] can collapse to icon-only on a compact phone rather than
    // overflowing the tab strip.
    final l10n = context.l10n;
    final tabs = <(PlannerTab, AdaptiveTab)>[
      (
        PlannerTab.recommendation,
        AdaptiveTab(
          label: l10n.text('plannerTabRecommendation'),
          icon: LucideIcons.sparkles,
        ),
      ),
      (
        PlannerTab.projects,
        AdaptiveTab(
          label: l10n.text('plannerTabProjects'),
          icon: LucideIcons.folderKanban,
        ),
      ),
      (
        PlannerTab.schedule,
        AdaptiveTab(
          label: l10n.text('plannerTabSchedule'),
          icon: LucideIcons.calendarDays,
        ),
      ),
      (
        PlannerTab.framing,
        AdaptiveTab(
          label: l10n.text('plannerTabFraming'),
          icon: LucideIcons.crop,
        ),
      ),
      (
        PlannerTab.planetarium,
        AdaptiveTab(
          label: l10n.text('plannerTabPlanetarium'),
          icon: LucideIcons.globe,
        ),
      ),
      (
        PlannerTab.discover,
        AdaptiveTab(
          label: l10n.text('plannerTabDiscover'),
          icon: LucideIcons.orbit,
        ),
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
                //
                // The last three are heavy LIVE-SKY views (HiPS tile maps with
                // time-ticking sky rotation, plus the animated living-sky in
                // Discover). IndexedStack keeps every child BUILT — which is what
                // we want for state preservation — but it does NOT pause their
                // animations when off-tab, so all four ran their 60fps repaints
                // at once and pegged idle CPU (~78%), flashing the panel.
                //
                // Wrap each heavy view in a TickerMode gated on "is this the
                // active tab". TickerMode mutes every AnimationController/Ticker
                // in the subtree while it's off-tab, so the continuous repaints
                // stop — but the widget stays mounted and its State (scroll,
                // selection, loaded tiles) is preserved, so switching back is
                // instant. Off-tab children are Offstage (don't paint), so the
                // only residual is a cheap ~1Hz clock rebuild that never paints.
                children: [
                  const _RecommendationTab(),
                  const _ProjectsTab(),
                  const _ScheduleTab(),
                  TickerMode(
                    enabled: _currentSubTab == PlannerTab.framing.index,
                    child: const FramingView(),
                  ),
                  TickerMode(
                    enabled: _currentSubTab == PlannerTab.planetarium.index,
                    child: const PlanetariumView(),
                  ),
                  TickerMode(
                    enabled: _currentSubTab == PlannerTab.discover.index,
                    child: const _DiscoverTab(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
