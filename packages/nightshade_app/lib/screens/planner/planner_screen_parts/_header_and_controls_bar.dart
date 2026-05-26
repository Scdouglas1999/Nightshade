// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Top-of-screen chrome: the planner header (title + icon) and the controls bar that arranges search, filter chips, and sort.
part of '../planner_screen.dart';

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
