// Top-of-screen chrome: the planner header (title + icon) and the controls bar that arranges search, filter chips, and sort.
part of '../planner_screen.dart';

/// The two facts the page header carries about tonight: the moon's
/// illumination and the astronomical-dark window.
///
/// Both are measured FROM the observing site, so with no site there is nothing
/// to state and the chips are absent — the tab body's one `EmptyState` is then
/// the single place that problem is represented (06 §Plan; 02 rule 5).
class _PlanNightChips extends ConsumerWidget {
  const _PlanNightChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(appObserverLocationProvider);
    if (plannerSiteUnset(location)) return const SizedBox.shrink();
    // Below the shell's layout breakpoint the header is 48px of title and tab
    // strip with nothing to spare; two chips of prose there push the row into
    // overflow. The same two facts are one tap away in the tab body.
    if (MediaQuery.sizeOf(context).width <
        ShellChromeMetrics.shellLayoutBreakpoint) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final illumination = AstronomyCalculations.moonIllumination(now);
    final twilight = AstronomyCalculations.calculateTwilightTimes(
      date: now,
      latitudeDeg: location!.latitude,
      longitudeDeg: location.longitude,
    );
    final dusk = twilight.astronomicalDusk;
    final dawn = twilight.astronomicalDawn;
    final l10n = context.l10n;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NightshadeChip(
          icon: LucideIcons.moon,
          label: l10n.text(
            'plannerChipMoon',
            params: {'value': illumination.round().toString()},
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        NightshadeChip(
          icon: LucideIcons.clock,
          label: dusk == null || dawn == null
              ? l10n.text('plannerChipDarkNone')
              : l10n.text(
                  'plannerChipDark',
                  params: {'start': _hhmm(dusk), 'end': _hhmm(dawn)},
                ),
        ),
      ],
    );
  }

  /// 24-hour clock, zero-padded. `DateFormat.Hm()` would follow the device
  /// locale into a 12-hour clock; every other time on this screen is 24-hour.
  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

// Controls bar (search, filters, sort)

/// The search field's width on the desktop filter row (06 §Plan: "300 px
/// search field").
const double _kPlannerSearchWidth = 300;

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

    // The row the mockup draws: a 300px search field, the two or three
    // most-used filters, a "More" chip for the rest, and the sort right-
    // aligned. Everything past "More" lives in the same sheet the phone
    // layout has always used, so no filter loses its control.
    final moreChip = _ControlChip(
      colors: colors,
      icon: LucideIcons.filter,
      label: filters.activeCount > 0 ? 'More (${filters.activeCount})' : 'More',
      active: filters.activeCount > 0,
      onTap: () => _openFiltersSheet(
        context,
        ref,
        constellations: constellations,
        magRange: magRange,
        sizeRange: sizeRange,
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        isPhone ? NightshadeTokens.spaceLg : NightshadeTokens.space2xl,
        keyboardCompact ? 0 : NightshadeTokens.spaceMd,
        isPhone ? NightshadeTokens.spaceLg : NightshadeTokens.space2xl,
        keyboardCompact ? 0 : NightshadeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: isPhone
          ? Row(
              children: [
                // Search and the Filters chip share one compact row on phone
                // so the controls bar is a single strip rather than two stacked
                // rows — reclaiming a whole row's height for the candidate
                // list.
                Expanded(child: searchField),
                const SizedBox(width: NightshadeTokens.spaceSm),
                moreChip,
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final sort = _SortDropdown(
                  colors: colors,
                  value: filters.plannerSort ?? PlannerSortMode.score,
                );

                // Below the desktop breakpoint the three inline chips do not
                // fit beside a 300 px search field and the sort, and the
                // horizontal scroll they used to live in simply SLICED the
                // last one — "Alt now: any" was cut mid-chip with the sort
                // apparently sitting on top of it, which reads as a broken
                // layout rather than as something scrollable.
                //
                // So they collapse into the Filters sheet, which already
                // carries all six controls (see _ControlsBarChips): nothing
                // loses its control, and the row keeps the two things the
                // mockup insists on, search and sort.
                if (constraints.maxWidth < NightshadeTokens.breakpointDesktop) {
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      moreChip,
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      sort,
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(width: _kPlannerSearchWidth, child: searchField),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ObjectTypeMultiSelect(
                              colors: colors,
                              selected: filters.selectedObjectTypes,
                            ),
                            const SizedBox(width: NightshadeTokens.spaceSm),
                            _MinAltitudeControl(
                              colors: colors,
                              value: filters.minCurrentAltitude,
                            ),
                            const SizedBox(width: NightshadeTokens.spaceSm),
                            _MoonSeparationControl(
                              colors: colors,
                              value: filters.minMoonDistance,
                            ),
                            const SizedBox(width: NightshadeTokens.spaceSm),
                            moreChip,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    sort,
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
                            style: NightshadeTypography.sectionTitle.copyWith(
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
