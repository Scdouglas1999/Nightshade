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
