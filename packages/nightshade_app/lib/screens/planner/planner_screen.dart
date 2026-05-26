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
import 'widgets/scheduler_tab_content.dart';
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
enum PlannerTab {
  recommendation,
  scheduler,
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
    case 'scheduler':
    case 'queue':
    case 'target-queue':
    case 'targetqueue':
      return PlannerTab.scheduler;
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
/// Three sub-tabs (W8-SCHED-MERGE):
///   * Recommendation — the primary scoring engine: best target right now,
///     filterable / sortable / searchable candidate list, SIMBAD fallback,
///     risk factors and rationale.
///   * Target Queue — RoboTarget-class dynamic scheduler, formerly the
///     standalone `/scheduler` screen. The body is embedded via
///     [SchedulerTabContent] so the `/scheduler` deep-link redirect lands
///     on the same code path.
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

    final tabs = <(PlannerTab, String)>[
      (PlannerTab.recommendation, 'Recommendation'),
      (PlannerTab.scheduler, 'Target Queue'),
      (PlannerTab.progress, 'Progress'),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          _PlannerHeader(colors: colors),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                ...tabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final label = entry.value.$2;
                  return SubTabButton(
                    label: label,
                    isSelected: index == _currentSubTab,
                    onTap: () => setState(() => _currentSubTab = index),
                  );
                }),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentSubTab,
              children: const [
                _RecommendationTab(),
                SchedulerTabContent(),
                ProgressTabContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
