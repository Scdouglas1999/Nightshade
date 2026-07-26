// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Top-of-screen chrome: the planner header (title + icon) and the controls bar that arranges search, filter chips, and sort.
part of '../planner_screen.dart';

// ============================================================================
// Controls bar (search, filters, sort)
// ============================================================================

class _PlannerControlsBar extends ConsumerWidget {
  final NightshadeColors colors;
  final TextEditingController controller;
  final SuggestionFilterState filters;
  final AsyncValue<List<TargetSuggestion>> candidatesAsync;
  final bool keyboardCompact;

  const _PlannerControlsBar({
    required this.colors,
    required this.controller,
    required this.filters,
    required this.candidatesAsync,
    this.keyboardCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final constellations = ref.watch(availableConstellationsProvider);
    final magRange = ref.watch(availableMagnitudeRangeProvider);
    final sizeRange = ref.watch(availableSizeRangeProvider);

    // Phone-tier (device-class, orientation-independent) collapses the filter
    // cluster behind one "Filters" button. Keyed off [Responsive.isPhone] — NOT
    // the controls bar's own width — so a wide-but-short phone landscape (e.g. a
    // Fold cover screen at 905x369) still collapses instead of falling through
    // to the desktop chip wrap because its *width* happens to clear 600px.
    final isPhone = Responsive.isPhone(context);

    final searchField = _SearchField(
      controller: controller,
      colors: colors,
      compact: isPhone,
      height: keyboardCompact ? 32 : 36,
      onChanged: (value) {
        final notifier = ref.read(suggestionFilterProvider.notifier);
        notifier.state = notifier.state.copyWith(searchQuery: value);
        ref.read(_plannerVisibleCountProvider.notifier).state =
            _kPlannerPageSize;
      },
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        NightshadeTokens.spaceLg,
        keyboardCompact
            ? 0
            : isPhone
                ? NightshadeTokens.spaceSm
                : NightshadeTokens.spaceMd,
        NightshadeTokens.spaceLg,
        keyboardCompact ? 0 : NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: isPhone
          ? Row(
              children: [
                // Search and the Filters button share one compact row on phone
                // so the controls bar is a single strip rather than two stacked
                // rows — reclaiming a whole row's height for the candidate list.
                Expanded(child: searchField),
                const SizedBox(width: NightshadeTokens.spaceSm),
                _FiltersSheetButton(
                  colors: colors,
                  activeCount: filters.activeCount,
                  height: keyboardCompact ? 32 : 36,
                  // With the software keyboard up the shell hands the whole
                  // controls bar a ~34px slot, so the 48dp touch floor cannot
                  // fit — asking for it there overflows the strip instead of
                  // growing the target. The floor applies in the resting state,
                  // which is the state a finger actually aims at.
                  floorTouchTarget: !keyboardCompact,
                  onTap: () => _openFiltersSheet(
                    context,
                    ref,
                    constellations: constellations,
                    magRange: magRange,
                    sizeRange: sizeRange,
                  ),
                ),
                if (filters.activeCount > 0 && !keyboardCompact) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  _ResetChip(
                    colors: colors,
                    onPressed: () => _resetFilters(ref),
                  ),
                ],
              ],
            )
          : Column(
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
                            style: NightshadeTypography.h4.copyWith(
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
  final double height;

  /// Whether to floor the hit box at the Android 48dp minimum. Off only when
  /// the caller's own slot is shorter than that (see the keyboard-compact bar).
  final bool floorTouchTarget;

  const _FiltersSheetButton({
    required this.colors,
    required this.activeCount,
    required this.onTap,
    this.height = 36,
    this.floorTouchTarget = true,
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
    final pill = Container(
      // Matches the compact phone search-field height (36) so the two sit on
      // one tidy row. A label + active-count badge keep it self-explanatory
      // while staying narrow enough to leave the search field most of the
      // row.
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(
          color: active ? colors.primary.withValues(alpha: 0.5) : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.slidersHorizontal, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(
            'Filters',
            style: NightshadeTypography.labelStrong.copyWith(
              color: fg,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
              ),
              child: Text(
                '$activeCount',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      onTap: onTap,
      // The painted pill keeps its compact height, but the tappable box is
      // floored at the Android 48dp minimum — measured at 134.7x36.0 on every
      // phone width before this. `InkResponse` hit-tests opaquely, so the
      // floored box is genuinely tappable, not just a bigger semantics rect.
      child: floorTouchTarget ? TouchTargetFloor(child: pill) : pill,
    );
  }
}
