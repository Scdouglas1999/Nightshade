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

    final searchField = _SearchField(
      controller: controller,
      colors: colors,
      onChanged: (value) {
        final notifier = ref.read(suggestionFilterProvider.notifier);
        notifier.state = notifier.state.copyWith(searchQuery: value);
        ref.read(_plannerVisibleCountProvider.notifier).state =
            _kPlannerPageSize;
      },
    );

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Phone-first: collapse the filter/sort chip cluster behind a single
          // "Filters" button that opens a bottom sheet, so the controls bar
          // stays a tidy two-row strip (search + one button) instead of a tall
          // wrapping pile that pushes the candidate list off-screen. Tablet and
          // desktop keep the inline chip row.
          final isPhone =
              constraints.maxWidth < BreakpointTokens.breakpointPhone;

          if (isPhone) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                searchField,
                const SizedBox(height: NightshadeTokens.spaceSm),
                Row(
                  children: [
                    Expanded(
                      child: _FiltersSheetButton(
                        colors: colors,
                        activeCount: filters.activeCount,
                        onTap: () => _openFiltersSheet(
                          context,
                          ref,
                          constellations: constellations,
                          magRange: magRange,
                          sizeRange: sizeRange,
                        ),
                      ),
                    ),
                    if (filters.activeCount > 0) ...[
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      _ResetChip(
                        colors: colors,
                        onPressed: () => _resetFilters(ref),
                      ),
                    ],
                  ],
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchField,
              const SizedBox(height: NightshadeTokens.spaceSm),
              Wrap(
                spacing: NightshadeTokens.spaceSm,
                runSpacing: NightshadeTokens.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _ControlsBarChips(
                  colors: colors,
                  filters: filters,
                  constellations: constellations,
                  magRange: magRange,
                  sizeRange: sizeRange,
                  controller: controller,
                ).chips(ref),
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetFilters(WidgetRef ref) {
    ref.read(suggestionFilterProvider.notifier).state =
        const SuggestionFilterState();
    controller.clear();
    ref.read(_plannerVisibleCountProvider.notifier).state = _kPlannerPageSize;
  }

  Future<void> _openFiltersSheet(
    BuildContext context,
    WidgetRef ref, {
    required List<String> constellations,
    required (double, double)? magRange,
    required (double, double)? sizeRange,
  }) {
    return showAdaptiveModal<void>(
      context: context,
      designWidth: 520,
      designHeight: 520,
      builder: (sheetContext) {
        // Re-read the live filter state inside the sheet so chips reflect taps
        // made while the sheet is open (each chip mutates the provider, which
        // rebuilds this consumer).
        return Consumer(
          builder: (innerContext, innerRef, _) {
            final liveFilters = innerRef.watch(suggestionFilterProvider);
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filters & sort',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (liveFilters.activeCount > 0)
                          NightshadeButton(
                            label: 'Reset',
                            variant: ButtonVariant.ghost,
                            size: ButtonSize.small,
                            icon: LucideIcons.rotateCcw,
                            onPressed: () => _resetFilters(innerRef),
                          ),
                      ],
                    ),
                    const SizedBox(height: NightshadeTokens.spaceMd),
                    Wrap(
                      spacing: NightshadeTokens.spaceSm,
                      runSpacing: NightshadeTokens.spaceSm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _ControlsBarChips(
                        colors: colors,
                        filters: liveFilters,
                        constellations: constellations,
                        magRange: magRange,
                        sizeRange: sizeRange,
                        controller: controller,
                      ).chips(innerRef),
                    ),
                    const SizedBox(height: NightshadeTokens.spaceLg),
                    SizedBox(
                      width: double.infinity,
                      child: NightshadeButton(
                        label: 'Done',
                        variant: ButtonVariant.primary,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Pin to share the chip-building logic between the inline desktop row and the
/// phone filter sheet without duplicating the chip list. Constructed per-build
/// from the live filter state.
class _ControlsBarChips {
  final NightshadeColors colors;
  final SuggestionFilterState filters;
  final List<String> constellations;
  final (double, double)? magRange;
  final (double, double)? sizeRange;
  final TextEditingController controller;

  const _ControlsBarChips({
    required this.colors,
    required this.filters,
    required this.constellations,
    required this.magRange,
    required this.sizeRange,
    required this.controller,
  });

  List<Widget> chips(WidgetRef ref) {
    void resetFilters() {
      ref.read(suggestionFilterProvider.notifier).state =
          const SuggestionFilterState();
      controller.clear();
      ref.read(_plannerVisibleCountProvider.notifier).state = _kPlannerPageSize;
    }

    return [
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
        _ResetChip(colors: colors, onPressed: resetFilters),
    ];
  }
}

/// Phone-tier launcher for the filter sheet. Mirrors the visual weight of a
/// `_ControlChip` but spans the row and shows an active-count badge.
class _FiltersSheetButton extends StatelessWidget {
  final NightshadeColors colors;
  final int activeCount;
  final VoidCallback onTap;

  const _FiltersSheetButton({
    required this.colors,
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final fg = active ? colors.primary : colors.textSecondary;
    final bg = active
        ? NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          ).color
        : colors.surfaceAlt;
    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(
            color:
                active ? colors.primary.withValues(alpha: 0.5) : colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.slidersHorizontal, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(
              'Filters & sort',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const Spacer(),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusXl),
                ),
                child: Text(
                  '$activeCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.onPrimary,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}
