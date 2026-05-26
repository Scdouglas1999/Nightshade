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

/// "Recommendation" tab — the original Plan Tonight body. Kept as a separate
/// widget so the search/filter state and infinite-scroll machinery stay
/// scoped to this tab (the other tabs don't need it).
class _RecommendationTab extends ConsumerStatefulWidget {
  const _RecommendationTab();

  @override
  ConsumerState<_RecommendationTab> createState() => _RecommendationTabState();
}

class _RecommendationTabState extends ConsumerState<_RecommendationTab> {
  int? _selectedAlternateIndex;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      final filtered =
          ref.read(plannerFilteredSuggestionsProvider).valueOrNull ?? const [];
      final current = ref.read(_plannerVisibleCountProvider);
      if (current < filtered.length) {
        ref.read(_plannerVisibleCountProvider.notifier).state =
            (current + _kPlannerPageSize).clamp(0, filtered.length);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final planAsync = ref.watch(_plannerOptimizationProvider);
    final filtersState = ref.watch(suggestionFilterProvider);
    final candidatesAsync = ref.watch(plannerFilteredSuggestionsProvider);

    // Keep the search field in sync if the provider changes from elsewhere.
    if (_searchController.text != filtersState.searchQuery) {
      _searchController.value = TextEditingValue(
        text: filtersState.searchQuery,
        selection:
            TextSelection.collapsed(offset: filtersState.searchQuery.length),
      );
    }

    return Column(
      children: [
        _PlannerControlsBar(
          colors: colors,
          controller: _searchController,
          filters: filtersState,
          candidatesAsync: candidatesAsync,
        ),
        Expanded(
          child: planAsync.when(
            data: (plan) => _buildBody(context, colors, plan, candidatesAsync),
            loading: () => _buildLoadingState(colors),
            error: (error, _) => _buildErrorState(context, colors, error),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    NightshadeColors colors,
    SessionOptimizationPlan plan,
    AsyncValue<List<TargetSuggestion>> candidatesAsync,
  ) {
    return candidatesAsync.when(
      data: (candidates) => _buildContent(context, colors, plan, candidates),
      loading: () => _buildLoadingState(colors),
      error: (error, _) => _buildErrorState(context, colors, error),
    );
  }

  Widget _buildContent(
    BuildContext context,
    NightshadeColors colors,
    SessionOptimizationPlan plan,
    List<TargetSuggestion> candidates,
  ) {
    final l10n = context.l10n;

    // Determine the effective primary (optimizer pick, alternate override,
    // or — when filters strip the optimizer pick out — fall back to the top
    // candidate in the filtered list).
    TargetSuggestion? effectivePrimary;
    if (_selectedAlternateIndex != null &&
        plan.alternates.isNotEmpty &&
        _selectedAlternateIndex! < plan.alternates.length) {
      effectivePrimary = plan.alternates[_selectedAlternateIndex!];
    } else if (plan.primaryTarget != null) {
      effectivePrimary = plan.primaryTarget;
    } else if (candidates.isNotEmpty) {
      effectivePrimary = candidates.first;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        final padding = isMobile
            ? NightshadeTokens.screenPaddingCompact
            : NightshadeTokens.screenPadding;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (effectivePrimary != null) ...[
                _PrimaryTargetCard(
                  target: effectivePrimary,
                  plan: plan,
                  colors: colors,
                  isMobile: isMobile,
                  isOverride: _selectedAlternateIndex != null,
                  onSendToFraming: () =>
                      _sendToFraming(context, ref, effectivePrimary!),
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                SizedBox(
                  width: double.infinity,
                  child: NightshadeButton(
                    label: l10n.text('plannerReviewInSequencer'),
                    icon: LucideIcons.listOrdered,
                    variant: ButtonVariant.primary,
                    onPressed: () => _createSequence(
                      context,
                      colors,
                      effectivePrimary!,
                      plan,
                    ),
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  l10n.text('plannerReviewHint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
              ],
              SectionHeader(
                title: candidates.isEmpty
                    ? 'No matching candidates'
                    : 'Tonight’s candidates',
                subtitle: candidates.isEmpty
                    ? 'Adjust filters below to bring more targets back.'
                    : '${candidates.length} target${candidates.length == 1 ? '' : 's'} after filters',
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              if (candidates.isEmpty)
                _FilteredEmptyState(colors: colors)
              else
                _CandidateList(
                  candidates: candidates,
                  colors: colors,
                  isMobile: isMobile,
                ),

              if (ref
                      .watch(suggestionFilterProvider)
                      .searchQuery
                      .trim()
                      .length >=
                  2)
                _InstalledCatalogResultsSection(
                  query: ref.watch(suggestionFilterProvider).searchQuery.trim(),
                  colors: colors,
                ),

              // External SIMBAD name resolver — shows up only when the user
              // is actively searching and either nothing local matched or
              // they want to broaden beyond the installed catalog. Reads the
              // current search query via ref so this method doesn't need a
              // filter parameter just to gate one widget.
              if (ref
                      .watch(suggestionFilterProvider)
                      .searchQuery
                      .trim()
                      .length >=
                  3)
                _SimbadResultsSection(
                  query: ref.watch(suggestionFilterProvider).searchQuery.trim(),
                  colors: colors,
                  hasLocalMatches: candidates.isNotEmpty,
                ),

              if (plan.riskFactors.isNotEmpty) ...[
                const SizedBox(height: NightshadeTokens.space2xl),
                SectionHeader(
                  title: l10n.text('plannerRiskFactors'),
                  subtitle: l10n.text('plannerRiskFactorsSubtitle'),
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _RiskFactorsList(riskFactors: plan.riskFactors, colors: colors),
              ],
              if (plan.rationale.isNotEmpty) ...[
                const SizedBox(height: NightshadeTokens.space2xl),
                SectionHeader(
                  title: l10n.text('plannerRationale'),
                  subtitle: l10n.text('plannerRationaleSubtitle'),
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _RationaleList(rationale: plan.rationale, colors: colors),
              ],
              const SizedBox(height: NightshadeTokens.space2xl),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createSequence(
    BuildContext context,
    NightshadeColors colors,
    TargetSuggestion target,
    SessionOptimizationPlan plan,
  ) async {
    try {
      final built = await buildPlanTonightTargetSequence(
        ref: ref,
        target: target,
        plan: plan,
        includeSessionPreamble: true,
      );
      if (!context.mounted) return;
      final loaded = await loadPlanTonightSequenceIntoEditor(
        context: context,
        ref: ref,
        result: built,
        replaceSequence: true,
      );
      if (!loaded || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.text(
              'plannerDraftCreated',
              params: {
                'target': target.targetName,
                'exposure': planTonightSequenceSummary(built),
              },
            ),
          ),
          backgroundColor: colors.success,
        ),
      );

      context.go('/sequencer');
    } on SmartNightBuildException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: colors.error,
        ),
      );
    }
  }

  void _sendToFraming(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion target,
  ) {
    ref.read(framingProvider.notifier).setTargetSuggestion(target);
    context.goNamed('framing');
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return ShimmerLoading(
      child: ListView.separated(
        padding: NightshadeTokens.screenPadding,
        itemCount: 6,
        separatorBuilder: (_, __) =>
            const SizedBox(height: NightshadeTokens.spaceMd),
        itemBuilder: (_, __) => _CandidateSkeleton(colors: colors),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    NightshadeColors colors,
    Object error,
  ) {
    final isLocationError = error is StateError;
    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLocationError ? LucideIcons.mapPin : LucideIcons.alertCircle,
              size: NightshadeTokens.icon2xl,
              color: isLocationError ? colors.warning : colors.error,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              isLocationError
                  ? context.l10n.text('plannerLocationMissingTitle')
                  : context.l10n.text('plannerPlanFailedTitle'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              isLocationError
                  ? context.l10n.text('plannerLocationMissingBody')
                  : context.l10n.text('plannerPlanFailedBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            if (isLocationError)
              NightshadeButton(
                label: context.l10n.text('plannerOpenSettings'),
                icon: LucideIcons.settings,
                onPressed: () => context.go('/settings'),
              )
            else
              NightshadeButton(
                label: context.l10n.text('plannerRetry'),
                icon: LucideIcons.refreshCw,
                onPressed: () => ref.invalidate(_plannerOptimizationProvider),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Header
// ============================================================================

class _PlannerHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _PlannerHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: NightshadeTokens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.moonStar, size: 20, color: colors.primary),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Text(
            context.l10n.text('plannerTitle'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Controls bar (search, filters, sort)
// ============================================================================

class _PlannerControlsBar extends ConsumerWidget {
  final NightshadeColors colors;
  final TextEditingController controller;
  final SuggestionFilterState filters;
  final AsyncValue<List<TargetSuggestion>> candidatesAsync;

  const _PlannerControlsBar({
    required this.colors,
    required this.controller,
    required this.filters,
    required this.candidatesAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final constellations = ref.watch(availableConstellationsProvider);
    final magRange = ref.watch(availableMagnitudeRangeProvider);
    final sizeRange = ref.watch(availableSizeRangeProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceMd,
        NightshadeTokens.spaceLg,
        NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchField(
            controller: controller,
            colors: colors,
            onChanged: (value) {
              final notifier = ref.read(suggestionFilterProvider.notifier);
              notifier.state = notifier.state.copyWith(searchQuery: value);
              ref.read(_plannerVisibleCountProvider.notifier).state =
                  _kPlannerPageSize;
            },
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ObjectTypeMultiSelect(
                colors: colors,
                selected: filters.selectedObjectTypes,
              ),
              _ConstellationDropdown(
                colors: colors,
                available: constellations,
                selected: filters.selectedConstellations.isEmpty
                    ? null
                    : filters.selectedConstellations.first,
              ),
              _MagnitudeRangeControl(
                colors: colors,
                bounds: magRange,
                min: filters.minMagnitude,
                max: filters.maxMagnitude,
              ),
              _SizeRangeControl(
                colors: colors,
                bounds: sizeRange,
                min: filters.minSizeArcmin,
                max: filters.maxSizeArcmin,
              ),
              _MinAltitudeControl(
                colors: colors,
                value: filters.minCurrentAltitude,
              ),
              _MoonSeparationControl(
                colors: colors,
                value: filters.minMoonDistance,
              ),
              _SortDropdown(
                colors: colors,
                value: filters.plannerSort ?? PlannerSortMode.score,
              ),
              if (filters.activeCount > 0)
                _ResetChip(
                  colors: colors,
                  onPressed: () {
                    ref.read(suggestionFilterProvider.notifier).state =
                        const SuggestionFilterState();
                    controller.clear();
                    ref.read(_plannerVisibleCountProvider.notifier).state =
                        _kPlannerPageSize;
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13, color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search tonight candidates and installed catalogs',
          hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
          prefixIcon:
              Icon(LucideIcons.search, size: 16, color: colors.textMuted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  iconSize: 14,
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: colors.surfaceAlt,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.primary),
          ),
        ),
      ),
    );
  }
}

class _ObjectTypeMultiSelect extends ConsumerWidget {
  final NightshadeColors colors;
  final Set<String> selected;

  const _ObjectTypeMultiSelect({required this.colors, required this.selected});

  static const _options = <String>[
    'galaxy',
    'nebula',
    'cluster',
    'planetary',
    'supernova remnant',
    'comet',
    'asteroid',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = selected.isEmpty
        ? 'Type: any'
        : 'Type: ${selected.map(_displayLabel).join(', ')}';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.shapes,
      label: label,
      active: selected.isNotEmpty,
      onTap: () async {
        final result = await showModalBottomSheet<Set<String>>(
          context: context,
          backgroundColor: colors.surface,
          builder: (sheetCtx) {
            final draft = Set<String>.of(selected);
            return StatefulBuilder(
              builder: (sheetCtx, setSheetState) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Object types',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceMd),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _options
                              .map((opt) => FilterChip(
                                    label: Text(_displayLabel(opt)),
                                    selected: draft.contains(opt),
                                    onSelected: (on) {
                                      setSheetState(() {
                                        if (on) {
                                          draft.add(opt);
                                        } else {
                                          draft.remove(opt);
                                        }
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceLg),
                        Row(
                          children: [
                            NightshadeButton(
                              label: 'Clear',
                              variant: ButtonVariant.ghost,
                              size: ButtonSize.small,
                              onPressed: () {
                                setSheetState(draft.clear);
                              },
                            ),
                            const Spacer(),
                            NightshadeButton(
                              label: 'Apply',
                              variant: ButtonVariant.primary,
                              size: ButtonSize.small,
                              onPressed: () =>
                                  Navigator.of(sheetCtx).pop(draft),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(selectedObjectTypes: result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }

  static String _displayLabel(String key) {
    return key
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _ConstellationDropdown extends ConsumerWidget {
  final NightshadeColors colors;
  final List<String> available;
  final String? selected;

  const _ConstellationDropdown({
    required this.colors,
    required this.available,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Constellation: any'),
      ),
      for (final c in available)
        DropdownMenuItem<String?>(
          value: c,
          child: Text('Constellation: $c'),
        ),
    ];

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected == null
            ? colors.surfaceAlt
            : NightshadeDecorations.tintedBadge(colors.primary).color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        border: Border.all(
          color: selected == null
              ? colors.border
              : colors.primary.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          items: items,
          isDense: true,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
          dropdownColor: colors.surface,
          iconSize: 14,
          onChanged: (value) {
            final notifier = ref.read(suggestionFilterProvider.notifier);
            notifier.state = notifier.state.copyWith(
              selectedConstellations:
                  value == null ? <String>{} : <String>{value},
            );
            ref.read(_plannerVisibleCountProvider.notifier).state =
                _kPlannerPageSize;
          },
        ),
      ),
    );
  }
}

class _MagnitudeRangeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final (double, double)? bounds;
  final double? min;
  final double? max;

  const _MagnitudeRangeControl({
    required this.colors,
    required this.bounds,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = min != null || max != null;
    String label;
    if (active) {
      final lo = min?.toStringAsFixed(1) ?? 'any';
      final hi = max?.toStringAsFixed(1) ?? 'any';
      label = 'Mag $lo–$hi';
    } else {
      label = 'Magnitude: any';
    }

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.sparkles,
      label: label,
      active: active,
      onTap: () async {
        final actualBounds = bounds ?? (-2.0, 18.0);
        final result = await showDialog<(double?, double?)>(
          context: context,
          builder: (dCtx) {
            double lo = min ?? actualBounds.$1;
            double hi = max ?? actualBounds.$2;
            return StatefulBuilder(
              builder: (dCtx, setDState) {
                return AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text(
                    'Magnitude range',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Brighter ${lo.toStringAsFixed(1)} – Dimmer ${hi.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      RangeSlider(
                        values: RangeValues(lo, hi),
                        min: actualBounds.$1,
                        max: actualBounds.$2,
                        divisions: 40,
                        labels: RangeLabels(
                          lo.toStringAsFixed(1),
                          hi.toStringAsFixed(1),
                        ),
                        onChanged: (v) {
                          setDState(() {
                            lo = v.start;
                            hi = v.end;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    NightshadeButton(
                      label: 'Clear',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((null, null)),
                    ),
                    NightshadeButton(
                      label: 'Apply',
                      variant: ButtonVariant.primary,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((lo, hi)),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minMagnitude: () => result.$1,
            maxMagnitude: () => result.$2,
          );
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

/// Sensible default bounds for the size slider when the data-derived range
/// is unavailable (e.g. before suggestions resolve). Covers planetary nebulae
/// (sub-arcminute) up to the largest M-class targets (~600').
const double _kSizeFilterMinArcmin = 0.1;
const double _kSizeFilterMaxArcmin = 600.0;

class _SizeRangeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final (double, double)? bounds;
  final double? min;
  final double? max;

  const _SizeRangeControl({
    required this.colors,
    required this.bounds,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = min != null || max != null;
    final label = active
        ? 'Size ${_formatSizeLabel(min)}–${_formatSizeLabel(max)}'
        : 'Size: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.ruler,
      label: label,
      active: active,
      onTap: () async {
        // Clamp the data-derived bounds into the slider's hard limits so the
        // RangeSlider doesn't assert when the catalog reports outliers.
        final dataLo = bounds?.$1 ?? _kSizeFilterMinArcmin;
        final dataHi = bounds?.$2 ?? _kSizeFilterMaxArcmin;
        final sliderLo =
            dataLo.clamp(_kSizeFilterMinArcmin, _kSizeFilterMaxArcmin);
        final sliderHi =
            dataHi.clamp(_kSizeFilterMinArcmin, _kSizeFilterMaxArcmin);
        final actualBounds = (
          sliderLo < _kSizeFilterMaxArcmin ? sliderLo : _kSizeFilterMinArcmin,
          sliderHi > sliderLo ? sliderHi : _kSizeFilterMaxArcmin,
        );

        final result = await showDialog<(double?, double?)>(
          context: context,
          builder: (dCtx) {
            double lo = (min ?? actualBounds.$1)
                .clamp(actualBounds.$1, actualBounds.$2);
            double hi = (max ?? actualBounds.$2)
                .clamp(actualBounds.$1, actualBounds.$2);
            return StatefulBuilder(
              builder: (dCtx, setDState) {
                return AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text(
                    'Angular size range',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_formatSizeLabel(lo)} – ${_formatSizeLabel(hi)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      RangeSlider(
                        values: RangeValues(lo, hi),
                        min: actualBounds.$1,
                        max: actualBounds.$2,
                        divisions: 60,
                        labels: RangeLabels(
                          _formatSizeLabel(lo),
                          _formatSizeLabel(hi),
                        ),
                        onChanged: (v) {
                          setDState(() {
                            lo = v.start;
                            hi = v.end;
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Targets without recorded size data are excluded '
                          'while this filter is active.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    NightshadeButton(
                      label: 'Clear',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((null, null)),
                    ),
                    NightshadeButton(
                      label: 'Apply',
                      variant: ButtonVariant.primary,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((lo, hi)),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minSizeArcmin: () => result.$1,
            maxSizeArcmin: () => result.$2,
          );
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

/// Format an arcminute value for compact display in size chips/labels.
/// Sub-arcminute → arcseconds (`45"`); >=1' → arcminutes with one decimal
/// (`12.4'`). Nulls and non-positive values render as "any".
String _formatSizeLabel(double? arcmin) {
  if (arcmin == null || arcmin <= 0) return 'any';
  if (arcmin < 1.0) {
    final arcsec = arcmin * 60.0;
    return '${arcsec.toStringAsFixed(0)}"';
  }
  return "${arcmin.toStringAsFixed(1)}'";
}

class _MinAltitudeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final double? value;

  const _MinAltitudeControl({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value != null;
    final label =
        active ? 'Alt now ≥ ${value!.toStringAsFixed(0)}°' : 'Alt now: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.mountain,
      label: label,
      active: active,
      onTap: () async {
        // Why: derive a sensible default from the user's horizon profile so
        // first-time users land on something that matches their site.
        final horizonProfile = ref.read(horizonProfileProvider);
        double seed = value ?? 0.0;
        if (!active && !horizonProfile.isFlat) {
          // Pick the maximum horizon obstruction as a starting guess.
          double maxAlt = 0.0;
          for (int az = 0; az < 360; az += 15) {
            final h = horizonProfile.altitudeAtAzimuth(az.toDouble());
            if (h > maxAlt) maxAlt = h;
          }
          seed = maxAlt;
        }
        final result = await _showAngleSlider(
          context: context,
          colors: colors,
          title: 'Minimum altitude right now',
          unit: '°',
          initial: seed,
          min: 0,
          max: 89,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state =
              notifier.state.copyWith(minCurrentAltitude: () => result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

class _MoonSeparationControl extends ConsumerWidget {
  final NightshadeColors colors;
  final double? value;

  const _MoonSeparationControl({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value != null;
    final label = active ? 'Moon ≥ ${value!.toStringAsFixed(0)}°' : 'Moon: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.moon,
      label: label,
      active: active,
      onTap: () async {
        final result = await _showAngleSlider(
          context: context,
          colors: colors,
          title: 'Minimum moon separation',
          unit: '°',
          initial: value ?? 30.0,
          min: 0,
          max: 180,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state =
              notifier.state.copyWith(minMoonDistance: () => result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

class _SortDropdown extends ConsumerWidget {
  final NightshadeColors colors;
  final PlannerSortMode value;

  const _SortDropdown({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const labels = {
      PlannerSortMode.score: 'Sort: Score',
      PlannerSortMode.altitude: 'Sort: Altitude',
      PlannerSortMode.magnitude: 'Sort: Magnitude',
      PlannerSortMode.size: 'Sort: Size (largest)',
      PlannerSortMode.constellation: 'Sort: Constellation',
      PlannerSortMode.objectType: 'Sort: Object type',
      PlannerSortMode.catalogId: 'Sort: Catalog ID',
    };

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PlannerSortMode>(
          value: value,
          items: [
            for (final m in PlannerSortMode.values)
              DropdownMenuItem(value: m, child: Text(labels[m]!)),
          ],
          isDense: true,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
          dropdownColor: colors.surface,
          iconSize: 14,
          onChanged: (v) {
            if (v == null) return;
            final notifier = ref.read(suggestionFilterProvider.notifier);
            notifier.state = notifier.state.copyWith(plannerSort: () => v);
          },
        ),
      ),
    );
  }
}

class _ResetChip extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _ResetChip({required this.colors, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _ControlChip(
      colors: colors,
      icon: LucideIcons.rotateCcw,
      label: 'Reset filters',
      active: true,
      onTap: onPressed,
    );
  }
}

class _ControlChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          ).color
        : colors.surfaceAlt;
    final border =
        active ? colors.primary.withValues(alpha: 0.5) : colors.border;
    final fg = active ? colors.primary : colors.textSecondary;

    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<double?> _showAngleSlider({
  required BuildContext context,
  required NightshadeColors colors,
  required String title,
  required String unit,
  required double initial,
  required double min,
  required double max,
}) async {
  return showDialog<double>(
    context: context,
    builder: (dCtx) {
      double val = initial.clamp(min, max);
      return StatefulBuilder(
        builder: (dCtx, setDState) {
          return AlertDialog(
            backgroundColor: colors.surface,
            title: Text(title, style: TextStyle(color: colors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${val.toStringAsFixed(0)}$unit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Slider(
                  value: val,
                  min: min,
                  max: max,
                  divisions: (max - min).round(),
                  label: '${val.toStringAsFixed(0)}$unit',
                  onChanged: (v) => setDState(() => val = v),
                ),
              ],
            ),
            actions: [
              NightshadeButton(
                label: 'Clear',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(dCtx).pop(-1.0),
              ),
              NightshadeButton(
                label: 'Apply',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(dCtx).pop(val),
              ),
            ],
          );
        },
      );
    },
  ).then((value) {
    if (value == null) return null;
    // -1 sentinel from the Clear button → tell caller to reset to null.
    if (value < 0) return double.nan;
    return value;
  }).then((v) {
    if (v == null) return null;
    if (v.isNaN) return null;
    return v;
  });
}

// ============================================================================
// Candidate list with pagination
// ============================================================================

class _CandidateList extends ConsumerWidget {
  final List<TargetSuggestion> candidates;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateList({
    required this.candidates,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCount =
        ref.watch(_plannerVisibleCountProvider).clamp(0, candidates.length);
    final visible = candidates.take(visibleCount).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final candidate in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
            child: _CandidateRow(
              key: ValueKey('candidate-${candidate.targetId}'),
              suggestion: candidate,
              colors: colors,
              isMobile: isMobile,
            ),
          ),
        if (visibleCount < candidates.length)
          Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
            child: Align(
              alignment: Alignment.center,
              child: NightshadeButton(
                label:
                    'Load more (${candidates.length - visibleCount} remaining)',
                icon: LucideIcons.chevronDown,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () {
                  final next = (visibleCount + _kPlannerPageSize)
                      .clamp(0, candidates.length);
                  ref.read(_plannerVisibleCountProvider.notifier).state = next;
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Target metadata and actions for a planner candidate card.
class _CandidateRowInfo extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final VoidCallback onSendToFraming;
  final VoidCallback onAddToObservingList;

  const _CandidateRowInfo({
    required this.suggestion,
    required this.colors,
    required this.onSendToFraming,
    required this.onAddToObservingList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peakAlt = suggestion.visibility.peakAltitude ??
        suggestion.visibility.currentAltitude;
    final hoursAbove = suggestion.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = suggestion.visibility.moonDistance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.targetName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (suggestion.catalogId != null &&
                      suggestion.catalogId != suggestion.targetName)
                    Text(
                      suggestion.catalogId!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            _ScoreBadge(score: suggestion.totalScore, colors: colors),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: 4,
          children: [
            if (suggestion.objectType != null)
              _StatChip(
                icon: LucideIcons.shapes,
                label: suggestion.objectType!,
                colors: colors,
              ),
            _StatChip(
              icon: LucideIcons.arrowUp,
              label: 'Peak ${peakAlt.toStringAsFixed(0)}°',
              colors: colors,
            ),
            _IntegrationEstimateChip(
              targetId: suggestion.targetId,
              fallbackVisibleHours: hoursAbove,
              colors: colors,
            ),
            _StatChip(
              icon: LucideIcons.moon,
              label: 'Moon ${moonDist.toStringAsFixed(0)}°',
              colors: colors,
              isWarning: moonDist < 45,
            ),
            if (suggestion.magnitude != null)
              _StatChip(
                icon: LucideIcons.sparkles,
                label: 'Mag ${suggestion.magnitude!.toStringAsFixed(1)}',
                colors: colors,
              ),
            // Why major-axis only: the DB Target schema does not store a
            // minor axis, so plumbing one through from OpenNGC would touch
            // out-of-scope files for this branch.
            if (suggestion.sizeArcmin != null && suggestion.sizeArcmin! > 0)
              _StatChip(
                icon: LucideIcons.ruler,
                label: _formatSizeLabel(suggestion.sizeArcmin),
                colors: colors,
              ),
            if (suggestion.constellation != null)
              _StatChip(
                icon: LucideIcons.star,
                label: suggestion.constellation!,
                colors: colors,
              ),
          ],
        ),
        if (suggestion.reasoning.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            suggestion.reasoning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.frame,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onSendToFraming,
            ),
            NightshadeButton(
              label: 'Add to observing list',
              icon: LucideIcons.listPlus,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onAddToObservingList,
            ),
          ],
        ),
      ],
    );
  }
}

/// Altitude visibility chart shown beside (or below on narrow) candidate info.
class _CandidateAltitudePanel extends StatelessWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;

  const _CandidateAltitudePanel({
    required this.suggestion,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
        child: AltitudeChart(
          raHours: suggestion.raHours,
          decDegrees: suggestion.decDegrees,
          targetName: suggestion.targetName,
        ),
      ),
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateRow({
    super.key,
    required this.suggestion,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoSection = _CandidateRowInfo(
      suggestion: suggestion,
      colors: colors,
      onSendToFraming: () => _sendToFraming(context, ref),
      onAddToObservingList: () => _addToObservingList(context, ref),
    );
    final chartPanel = _CandidateAltitudePanel(
      suggestion: suggestion,
      colors: colors,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoSection,
                const SizedBox(height: NightshadeTokens.spaceMd),
                chartPanel,
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = clampPanelWidth(
                  constraints.maxWidth,
                  fraction: 0.32,
                  min: 300,
                  max: 380,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: infoSection),
                    const SizedBox(width: NightshadeTokens.spaceLg),
                    SizedBox(
                      width: panelWidth,
                      child: chartPanel,
                    ),
                  ],
                );
              },
            ),
    );
  }

  void _sendToFraming(BuildContext context, WidgetRef ref) {
    ref.read(framingProvider.notifier).setTargetSuggestion(suggestion);
    context.goNamed('framing');
  }

  Future<void> _addToObservingList(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final lists = await ref.read(observingListsDaoProvider).getAllLists();
    if (!context.mounted) return;

    final chosenId = await showDialog<int>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Add to observing list',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: SizedBox(
            width: dialogMaxWidth(dCtx, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No observing lists yet. Create one to start adding targets.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: clampPanelWidth(
                        MediaQuery.sizeOf(dCtx).height,
                        fraction: 0.35,
                        min: 180,
                        max: 280,
                      ),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final list in lists)
                          ListTile(
                            dense: true,
                            title: Text(list.name,
                                style: TextStyle(color: colors.textPrimary)),
                            onTap: () => Navigator.of(dCtx).pop(list.id),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                NightshadeButton(
                  label: 'Create new list…',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: () async {
                    Navigator.of(dCtx).pop();
                    final newId = await _createListAndAdd(context, ref);
                    if (!context.mounted || newId == null) return;
                  },
                ),
              ],
            ),
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(),
            ),
          ],
        );
      },
    );

    if (chosenId == null) return;
    if (!context.mounted) return;
    final id = await ref.read(observingListNotifierProvider.notifier).addItem(
          listId: chosenId,
          objectName: suggestion.targetName,
          catalogId: suggestion.catalogId,
          objectType: suggestion.objectType,
          ra: suggestion.raHours,
          dec: suggestion.decDegrees,
          magnitude: suggestion.magnitude,
          sizeArcmin: suggestion.sizeArcmin,
        );
    if (!context.mounted) return;
    final colorsLocal = NightshadeColors.of(context);
    final notifierState = ref.read(observingListNotifierProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? (notifierState.errorMessage ?? 'Failed to add to list')
              : 'Added ${suggestion.targetName} to the list',
        ),
        backgroundColor: id == null ? colorsLocal.error : colorsLocal.success,
      ),
    );
  }

  Future<int?> _createListAndAdd(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text('New list', style: TextStyle(color: colors.textPrimary)),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'List name'),
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(),
            ),
            NightshadeButton(
              label: 'Create',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () => Navigator.of(dCtx).pop(nameController.text),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return null;
    final newId = await ref
        .read(observingListNotifierProvider.notifier)
        .createList(name: name.trim());
    if (newId == null) return null;
    if (!context.mounted) return null;
    final id = await ref.read(observingListNotifierProvider.notifier).addItem(
          listId: newId,
          objectName: suggestion.targetName,
          catalogId: suggestion.catalogId,
          objectType: suggestion.objectType,
          ra: suggestion.raHours,
          dec: suggestion.decDegrees,
          magnitude: suggestion.magnitude,
          sizeArcmin: suggestion.sizeArcmin,
        );
    if (!context.mounted) return null;
    final colorsLocal = NightshadeColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? 'Created list but failed to add target'
              : 'Created "$name" and added ${suggestion.targetName}',
        ),
        backgroundColor: id == null ? colorsLocal.error : colorsLocal.success,
      ),
    );
    return id;
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  final NightshadeColors colors;

  const _ScoreBadge({required this.score, required this.colors});

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    if (score >= 75) {
      badgeColor = colors.success;
    } else if (score >= 50) {
      badgeColor = colors.warning;
    } else {
      badgeColor = colors.error;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: NightshadeDecorations.kpiBadge(badgeColor),
      child: Center(
        child: Text(
          score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: badgeColor,
          ),
        ),
      ),
    );
  }
}

/// Shows filter-aware estimated integration when Smart Night context is
/// available; otherwise falls back to hours above minimum altitude.
class _IntegrationEstimateChip extends ConsumerWidget {
  final int targetId;
  final double fallbackVisibleHours;
  final NightshadeColors colors;

  const _IntegrationEstimateChip({
    required this.targetId,
    required this.fallbackVisibleHours,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewAsync =
        ref.watch(plannerTargetIntegrationPreviewProvider(targetId));

    return previewAsync.when(
      data: (preview) {
        if (preview != null && preview.estimatedIntegrationHours > 0) {
          return _StatChip(
            icon: LucideIcons.timer,
            label:
                '~${preview.estimatedIntegrationHours.toStringAsFixed(1)}h integration',
            colors: colors,
          );
        }
        if (fallbackVisibleHours > 0) {
          return _StatChip(
            icon: LucideIcons.clock,
            label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
            colors: colors,
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => fallbackVisibleHours > 0
          ? _StatChip(
              icon: LucideIcons.clock,
              label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
              colors: colors,
            )
          : const SizedBox.shrink(),
      error: (_, __) => fallbackVisibleHours > 0
          ? _StatChip(
              icon: LucideIcons.clock,
              label: '${fallbackVisibleHours.toStringAsFixed(1)}h visible',
              colors: colors,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isWarning;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = isWarning ? colors.warning : colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isWarning
          ? NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: BorderRadius.circular(6),
            )
          : BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateSkeleton extends StatelessWidget {
  final NightshadeColors colors;
  const _CandidateSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SkeletonText(width: 180, height: 14),
            Spacer(),
            SkeletonBox(
              width: 44,
              height: 44,
              borderRadius: NightshadeTokens.radiusFull,
            ),
          ]),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonText(width: 240, height: 12),
          SizedBox(height: NightshadeTokens.spaceSm),
          Row(children: [
            SkeletonBox(width: 60, height: 22),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 60, height: 22),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 60, height: 22),
          ]),
          SizedBox(height: NightshadeTokens.spaceMd),
          Row(children: [
            SkeletonBox(width: 120, height: 30),
            SizedBox(width: NightshadeTokens.spaceSm),
            SkeletonBox(width: 150, height: 30),
          ]),
        ],
      ),
    );
  }
}

// ============================================================================
// Empty state (filters applied) — explains which filter excluded the most
// ============================================================================

class _FilteredEmptyState extends ConsumerWidget {
  final NightshadeColors colors;

  const _FilteredEmptyState({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(plannerFilterExclusionProvider);
    final ranked = breakdown.excludedByFilter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.filterX,
                  size: NightshadeTokens.iconLg, color: colors.warning),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  breakdown.total == 0
                      ? 'No targets available'
                      : 'No targets match these filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (breakdown.total == 0) ...[
            // Why: when the suggestion pool is fully empty, the dominant
            // real-world cause is "the OpenNGC catalog hasn't been
            // downloaded yet" — not "your filters/altitude/twilight are
            // wrong." Detect that case and surface the actual fix.
            Builder(builder: (ctx) {
              final catalogState = ref.watch(catalogStateProvider);
              final catalogReady = catalogState.dsoCatalogStatus.isInstalled;
              if (!catalogReady) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The OpenNGC catalog is not installed. Without it, the planner can only score targets you have already saved to your library.',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: NightshadeTokens.spaceMd),
                    NightshadeButton(
                      label: 'Open catalog settings',
                      onPressed: () => context.go('/settings/plate-solving'),
                      icon: LucideIcons.download,
                      size: ButtonSize.small,
                    ),
                  ],
                );
              }
              return Text(
                'The scoring engine returned zero candidates for tonight. Verify your location, twilight window, and your minimum altitude/score in suggestion config.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              );
            }),
          ] else ...[
            Text(
              '${breakdown.total} candidate${breakdown.total == 1 ? '' : 's'} were scored, '
              '${breakdown.passed} passed the filters.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            if (ranked.isNotEmpty) ...[
              Text(
                'Filters with the largest impact:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              for (final entry in ranked.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.minusCircle,
                          size: 12, color: colors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '−${entry.value}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: NightshadeTokens.spaceLg),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: 'Reset filters',
              icon: LucideIcons.rotateCcw,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () {
                ref.read(suggestionFilterProvider.notifier).state =
                    const SuggestionFilterState();
                ref.read(_plannerVisibleCountProvider.notifier).state =
                    _kPlannerPageSize;
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Primary target card + auxiliary lists (kept from original screen)
// ============================================================================

class _PrimaryTargetCard extends ConsumerWidget {
  final TargetSuggestion target;
  final SessionOptimizationPlan plan;
  final NightshadeColors colors;
  final bool isMobile;
  final bool isOverride;
  final VoidCallback onSendToFraming;

  const _PrimaryTargetCard({
    required this.target,
    required this.plan,
    required this.colors,
    required this.isMobile,
    required this.isOverride,
    required this.onSendToFraming,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raFormatted = CoordinateUtils.formatRA(target.raHours);
    final decFormatted = CoordinateUtils.formatDec(target.decDegrees);
    final peakAlt =
        target.visibility.peakAltitude ?? target.visibility.currentAltitude;
    final hoursAbove = target.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = target.visibility.moonDistance;
    final integrationPreview =
        ref.watch(plannerTargetIntegrationPreviewProvider(target.targetId));

    final infoSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isOverride)
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: NightshadeTokens.spaceXs),
                      child: Text(
                        context.l10n.text('plannerUserOverride'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.warning,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  Text(
                    target.targetName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (target.catalogId != null &&
                      target.catalogId != target.targetName)
                    Text(
                      target.catalogId!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            _ScoreBadge(score: target.totalScore, colors: colors),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Row(
          children: [
            Icon(LucideIcons.locate, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Text(
              '$raFormatted  /  $decFormatted',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceMd,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            if (target.objectType != null)
              _StatChip(
                icon: LucideIcons.shapes,
                label: target.objectType!,
                colors: colors,
              ),
            _StatChip(
              icon: LucideIcons.arrowUp,
              label: context.l10n.text(
                'plannerPeak',
                params: {'value': peakAlt.toStringAsFixed(1)},
              ),
              colors: colors,
            ),
            _IntegrationEstimateChip(
              targetId: target.targetId,
              fallbackVisibleHours: hoursAbove,
              colors: colors,
            ),
            _StatChip(
              icon: LucideIcons.moon,
              label: context.l10n.text(
                'plannerMoon',
                params: {'value': moonDist.toStringAsFixed(0)},
              ),
              colors: colors,
              isWarning: moonDist < 45,
            ),
            _StatChip(
              icon: LucideIcons.camera,
              label: context.l10n.text(
                'plannerExposure',
                params: {
                  'value': plan.recommendedExposureSeconds.toStringAsFixed(0),
                },
              ),
              colors: colors,
            ),
            if (plan.recommendedFilterNames.isNotEmpty)
              _StatChip(
                icon: LucideIcons.aperture,
                label: plan.recommendedFilterNames.join(' · '),
                colors: colors,
              )
            else if (plan.recommendedFilterName != null)
              _StatChip(
                icon: LucideIcons.aperture,
                label: plan.recommendedFilterName!,
                colors: colors,
              ),
            if (target.magnitude != null)
              _StatChip(
                icon: LucideIcons.sparkles,
                label: context.l10n.text(
                  'plannerMagnitude',
                  params: {'value': target.magnitude!.toStringAsFixed(1)},
                ),
                colors: colors,
              ),
            if (target.sizeArcmin != null && target.sizeArcmin! > 0)
              _StatChip(
                icon: LucideIcons.ruler,
                label: _formatSizeLabel(target.sizeArcmin),
                colors: colors,
              ),
            if (target.constellation != null)
              _StatChip(
                icon: LucideIcons.star,
                label: target.constellation!,
                colors: colors,
              ),
          ],
        ),
        integrationPreview.when(
          data: (preview) {
            if (preview == null || preview.estimatedIntegrationHours <= 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: NightshadeTokens.spaceMd),
              child: Row(
                children: [
                  Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.text(
                      'plannerEstimatedIntegration',
                      params: {
                        'value': _formatUsableHours(
                          preview.estimatedIntegrationHours,
                        ),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.frame,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onSendToFraming,
            ),
          ],
        ),
        if (target.warnings.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          for (final warning in target.warnings.take(3))
            Padding(
              padding:
                  const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    size: 14,
                    color: _warningColor(warning.severity, colors),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      warning.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: _warningColor(warning.severity, colors),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
    final chartPanel = _CandidateAltitudePanel(
      suggestion: target,
      colors: colors,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(
          color: isOverride
              ? colors.warning.withValues(alpha: 0.5)
              : colors.primary.withValues(alpha: 0.4),
        ),
      ),
      padding: NightshadeTokens.cardPadding,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoSection,
                const SizedBox(height: NightshadeTokens.spaceMd),
                chartPanel,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoSection),
                const SizedBox(width: NightshadeTokens.spaceLg),
                SizedBox(
                  width: 360,
                  child: chartPanel,
                ),
              ],
            ),
    );
  }

  String _formatUsableHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Color _warningColor(WarningSeverity severity, NightshadeColors colors) {
    switch (severity) {
      case WarningSeverity.critical:
        return colors.error;
      case WarningSeverity.warning:
        return colors.warning;
      case WarningSeverity.caution:
        return colors.textSecondary;
      case WarningSeverity.info:
        return colors.textMuted;
    }
  }
}

class _RiskFactorsList extends StatelessWidget {
  final List<String> riskFactors;
  final NightshadeColors colors;

  const _RiskFactorsList({
    required this.riskFactors,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.05),
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.warning.withValues(alpha: 0.2)),
      ),
      padding: NightshadeTokens.cardPadding,
      child: Column(
        children: [
          for (int i = 0; i < riskFactors.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.alertTriangle,
                      size: 14, color: colors.warning),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    riskFactors[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (i < riskFactors.length - 1)
              Divider(
                color: colors.border,
                height: NightshadeTokens.spaceLg,
              ),
          ],
        ],
      ),
    );
  }
}

class _RationaleList extends StatelessWidget {
  final List<String> rationale;
  final NightshadeColors colors;

  const _RationaleList({
    required this.rationale,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: Column(
        children: [
          for (int i = 0; i < rationale.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.lightbulb,
                      size: 14, color: colors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rationale[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (i < rationale.length - 1)
              Divider(
                color: colors.border,
                height: NightshadeTokens.spaceLg,
              ),
          ],
        ],
      ),
    );
  }
}

/// Section that resolves a name fragment against SIMBAD and renders the
/// matches as send-to-framing rows. Only mounts when the planner search bar
/// has ≥3 characters typed.
class _InstalledCatalogResultsSection extends ConsumerWidget {
  final String query;
  final NightshadeColors colors;

  const _InstalledCatalogResultsSection({
    required this.query,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plannerInstalledCatalogSearchProvider(query));

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Searching installed catalogs for "$query"...',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Text(
          'Installed catalog lookup failed: $e',
          style: TextStyle(fontSize: 12, color: colors.warning),
        ),
      ),
      data: (matches) {
        if (matches.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: NightshadeTokens.space2xl),
            SectionHeader(
              title: 'Installed catalog',
              subtitle:
                  '${matches.length} match${matches.length == 1 ? '' : 'es'} for "$query" outside tonight\'s scored candidates',
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final match in matches)
              _CatalogResultRow(match: match, colors: colors),
          ],
        );
      },
    );
  }
}

class _CatalogResultRow extends StatelessWidget {
  final CatalogSearchResult match;
  final NightshadeColors colors;

  const _CatalogResultRow({
    required this.match,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      match.type,
      if (match.magnitude != null) 'mag ${match.magnitude!.toStringAsFixed(1)}',
      if (match.constellation != null && match.constellation!.isNotEmpty)
        match.constellation!,
      'RA ${_SimbadResultRow._formatRa(match.ra / 15.0)}  Dec ${_SimbadResultRow._formatDec(match.dec)}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  metaParts.join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'Send to Framing',
            icon: LucideIcons.crosshair,
            size: ButtonSize.small,
            onPressed: () {
              final uri = Uri(
                path: '/framing',
                queryParameters: {
                  'ra': (match.ra / 15.0).toStringAsFixed(6),
                  'dec': match.dec.toStringAsFixed(6),
                  'name': match.name,
                },
              );
              context.go(uri.toString());
            },
          ),
        ],
      ),
    );
  }
}

class _SimbadResultsSection extends ConsumerWidget {
  final String query;
  final NightshadeColors colors;
  final bool hasLocalMatches;

  const _SimbadResultsSection({
    required this.query,
    required this.colors,
    required this.hasLocalMatches,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(plannerSimbadResultsProvider(query));

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Searching SIMBAD for "$query"…',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
        child: Text(
          'SIMBAD lookup failed: $e',
          style: TextStyle(fontSize: 12, color: colors.warning),
        ),
      ),
      data: (matches) {
        if (matches.isEmpty) {
          if (hasLocalMatches) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.space2xl),
            child: Text(
              'SIMBAD found no objects matching "$query".',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: NightshadeTokens.space2xl),
            SectionHeader(
              title: 'From SIMBAD',
              subtitle:
                  '${matches.length} match${matches.length == 1 ? '' : 'es'} for "$query" — not scored for tonight',
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final m in matches) _SimbadResultRow(match: m, colors: colors),
          ],
        );
      },
    );
  }
}

class _SimbadResultRow extends ConsumerWidget {
  final SimbadNameMatch match;
  final NightshadeColors colors;

  const _SimbadResultRow({required this.match, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metaParts = <String>[];
    if (match.objectType != null && match.objectType!.isNotEmpty) {
      metaParts.add(match.objectType!);
    }
    if (match.magnitudeV != null) {
      metaParts.add('mag ${match.magnitudeV!.toStringAsFixed(1)}');
    }
    metaParts.add(
      'RA ${_formatRa(match.raHours)}  Dec ${_formatDec(match.decDegrees)}',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.mainId,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  metaParts.join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          NightshadeButton(
            label: 'Send to Framing',
            icon: LucideIcons.crosshair,
            size: ButtonSize.small,
            onPressed: () {
              final uri = Uri(
                path: '/framing',
                queryParameters: {
                  'ra': match.raHours.toStringAsFixed(6),
                  'dec': match.decDegrees.toStringAsFixed(6),
                  'name': match.mainId,
                },
              );
              context.go(uri.toString());
            },
          ),
        ],
      ),
    );
  }

  static String _formatRa(double hours) {
    final h = hours.floor();
    final mDec = (hours - h) * 60;
    final m = mDec.floor();
    final s = ((mDec - m) * 60);
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toStringAsFixed(1)}s';
  }

  static String _formatDec(double degrees) {
    final sign = degrees < 0 ? '-' : '+';
    final v = degrees.abs();
    final d = v.floor();
    final mDec = (v - d) * 60;
    final m = mDec.floor();
    final s = ((mDec - m) * 60);
    return '$sign${d.toString().padLeft(2, '0')}° ${m.toString().padLeft(2, '0')}\' ${s.toStringAsFixed(1)}"';
  }
}
