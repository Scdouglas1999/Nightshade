// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Owns the Recommendation tab: its state notifier, scroll-driven pagination, and the orchestrating build/error/loading scaffolding around primary card + candidate list + risk/rationale sections.
part of '../planner_screen.dart';

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
    final position = _scrollController.position;
    // Page in a screenful ahead of the end. A fixed 240px lead is most of a
    // page on a phone but a sliver of a tall desktop viewport, where the list
    // ran dry mid-flick before the next page was appended.
    final lead = position.viewportDimension * 0.5;
    if (position.pixels >= position.maxScrollExtent - lead) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // A parent Scaffold may consume viewInsets before this subtree sees
        // them. Use the actual remaining height as the final authority so the
        // search stays usable even when MediaQuery reports no keyboard.
        final keyboardCompact = constraints.maxHeight < 120;

        return Column(
          children: [
            _PlannerControlsBar(
              colors: colors,
              controller: _searchController,
              filters: filtersState,
              candidatesAsync: candidatesAsync,
              keyboardCompact: keyboardCompact,
            ),
            Expanded(
              // NEVER FLASH: the optimization plan refreshes whenever its inputs
              // change (location, the 30s state re-hydration, a real target/profile
              // edit). `when(loading:)` would drop the whole tab to a skeleton on
              // every one of those, blanking the screen even when the result is
              // identical. Instead, keep rendering the LAST good plan while a
              // refresh is in flight (Riverpod retains the previous value across a
              // reload), and only fall back to the skeleton on the very first load
              // or the error screen when there is no value to keep showing. The
              // content updates seamlessly in place when new data actually arrives.
              child: _whenWithPrevious<SessionOptimizationPlan>(
                planAsync,
                data: (plan) =>
                    _buildBody(context, colors, plan, candidatesAsync),
                loading: () => _buildLoadingState(colors),
                error: (error) => _buildErrorState(context, colors, error),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Renders [data] using the latest-or-previous value of [async], so an
  /// in-flight refresh keeps the current content on screen instead of flashing
  /// the [loading] state. [loading] is only used before the first value exists;
  /// [error] only when there is no value to fall back to.
  Widget _whenWithPrevious<T>(
    AsyncValue<T> async, {
    required Widget Function(T value) data,
    required Widget Function() loading,
    required Widget Function(Object error) error,
  }) {
    if (async.hasValue) return data(async.requireValue);
    if (async.hasError) return error(async.error!);
    return loading();
  }

  Widget _buildBody(
    BuildContext context,
    NightshadeColors colors,
    SessionOptimizationPlan plan,
    AsyncValue<List<TargetSuggestion>> candidatesAsync,
  ) {
    return _whenWithPrevious<List<TargetSuggestion>>(
      candidatesAsync,
      data: (candidates) => _buildContent(context, colors, plan, candidates),
      loading: () => _buildLoadingState(colors),
      error: (error) => _buildErrorState(context, colors, error),
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
              // Authoritative headline: a READ-ONLY preview of the live
              // SchedulerEngine's decision — the exact target the autopilot
              // would slew to right now. This is what the rig runs; the
              // suggestion-based card below is the whole-night OUTLOOK
              // supplement (peak altitude / transit / window hours), not a
              // competing #1 ranker (architecture-unification plan, §1).
              _AutopilotPreviewBanner(colors: colors),
              const SizedBox(height: NightshadeTokens.spaceMd),
              const TransientAlertsPanel(initiallyExpanded: false),
              const SizedBox(height: NightshadeTokens.space2xl),
              if (effectivePrimary != null) ...[
                _OutlookSectionLabel(colors: colors),
                const SizedBox(height: NightshadeTokens.spaceSm),
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
                    fontSize: NightshadeTypography.fontSize12,
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
                    ? 'Adjust the filters on this tab to bring more targets back.'
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
                  // The rationale is always about the OPTIMIZER's pick, which
                  // is not necessarily the card above it: a search or filter
                  // can leave a different hero card on screen, and then the
                  // generic "Why this plan was chosen" read as an explanation
                  // of that card while contradicting every number on it. Name
                  // the target the numbers belong to.
                  subtitle: plan.primaryTarget == null
                      ? l10n.text('plannerRationaleSubtitle')
                      : l10n.text(
                          'plannerRationaleSubtitleNamed',
                          params: {'target': plan.primaryTarget!.targetName},
                        ),
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _RationaleList(rationale: plan.rationale, colors: colors),
              ],
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
    // On a phone in landscape the tab body is only ~200 px tall once the
    // header/filters are subtracted, which is shorter than this icon + title +
    // body + action column. Center it when there is room, but fall back to a
    // scroll when the viewport is too short so the call-to-action button stays
    // reachable instead of overflowing the bottom edge.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: NightshadeTokens.screenPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLocationError
                          ? LucideIcons.mapPin
                          : LucideIcons.alertCircle,
                      size: NightshadeTokens.icon2xl,
                      color: isLocationError ? colors.warning : colors.error,
                    ),
                    const SizedBox(height: NightshadeTokens.spaceLg),
                    Text(
                      isLocationError
                          ? context.l10n.text('plannerLocationMissingTitle')
                          : context.l10n.text('plannerPlanFailedTitle'),
                      style: NightshadeTypography.h4.copyWith(
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
                        fontSize: NightshadeTypography.fontSize13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: NightshadeTokens.spaceXl),
                    if (isLocationError)
                      NightshadeButton(
                        label: context.l10n.text('plannerOpenSettings'),
                        icon: LucideIcons.mapPin,
                        onPressed: () =>
                            context.go('/settings?section=location'),
                      )
                    else
                      NightshadeButton(
                        label: context.l10n.text('plannerRetry'),
                        icon: LucideIcons.refreshCw,
                        onPressed: () =>
                            ref.invalidate(_plannerOptimizationProvider),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
