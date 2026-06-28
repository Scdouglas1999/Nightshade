import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

part 'suggestion_filters/chip_controls.dart';
part 'suggestion_filters/slider_controls.dart';
part 'suggestion_filters/sort_and_reset_controls.dart';

/// Widget for filtering and sorting target suggestions.
///
/// This widget provides controls for:
/// - Object type filtering via multi-select chips
/// - Constellation filtering via multi-select chips
/// - Magnitude range slider
/// - Object size range slider
/// - Moon distance minimum slider
/// - Imaging time minimum slider
/// - Minimum score slider (0-100)
/// - Minimum altitude slider (0-90 degrees)
/// - Sort mode selection
/// - Toggle for prioritizing incomplete targets
/// - Reset filters button
///
/// Object type / sort / score / altitude / incomplete changes update
/// [targetSuggestionConfigProvider]. Constellation / magnitude / size / moon /
/// imaging-time changes update [suggestionFilterProvider]. Both trigger the
/// suggestion list to refresh automatically.
class SuggestionFilters extends ConsumerWidget {
  /// If true, displays controls in a vertical layout suitable for mobile bottom sheets.
  /// If false, displays controls in a horizontal layout for desktop/tablet.
  final bool showAsSheet;

  const SuggestionFilters({
    super.key,
    this.showAsSheet = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final config = ref.watch(targetSuggestionConfigProvider);
    final filters = ref.watch(suggestionFilterProvider);

    // Fetch available object types from user's targets
    final targetsAsync = ref.watch(_availableObjectTypesProvider);
    final availableTypes = targetsAsync.valueOrNull ?? <String>[];

    // Derived data for filter bounds
    final availableConstellations = ref.watch(availableConstellationsProvider);
    final magRange = ref.watch(availableMagnitudeRangeProvider);
    final sizeRange = ref.watch(availableSizeRangeProvider);

    if (showAsSheet) {
      return _buildMobileLayout(
        context,
        ref,
        colors,
        config,
        filters,
        availableTypes,
        availableConstellations,
        magRange,
        sizeRange,
      );
    } else {
      return _buildDesktopLayout(
        context,
        ref,
        colors,
        config,
        filters,
        availableTypes,
        availableConstellations,
        magRange,
        sizeRange,
      );
    }
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    TargetSuggestionConfig config,
    SuggestionFilterState filters,
    List<String> availableTypes,
    List<String> availableConstellations,
    (double, double)? magRange,
    (double, double)? sizeRange,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Object types + sort + incomplete + reset
          Row(
            children: [
              if (availableTypes.isNotEmpty) ...[
                Expanded(
                  flex: 3,
                  child: _ObjectTypeChips(
                    availableTypes: availableTypes,
                    selectedTypes: config.preferredObjectTypes,
                    colors: colors,
                    onChanged: (types) => _updateConfig(
                      ref,
                      config.copyWith(preferredObjectTypes: types),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              _SortModeDropdown(
                value: config.sortMode,
                colors: colors,
                onChanged: (mode) => _updateConfig(
                  ref,
                  config.copyWith(sortMode: mode),
                ),
              ),
              const SizedBox(width: 12),
              _PrioritizeIncompleteToggle(
                value: config.prioritizeIncomplete,
                colors: colors,
                onChanged: (value) => _updateConfig(
                  ref,
                  config.copyWith(prioritizeIncomplete: value),
                ),
              ),
              const SizedBox(width: 12),
              _ResetFiltersButton(
                colors: colors,
                onPressed: () => _resetAll(ref),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Constellation chips + range sliders
          Row(
            children: [
              // Constellation chips (scrollable)
              if (availableConstellations.isNotEmpty) ...[
                Expanded(
                  flex: 3,
                  child: _ConstellationChips(
                    availableConstellations: availableConstellations,
                    selectedConstellations: filters.selectedConstellations,
                    colors: colors,
                    onChanged: (selected) => _updateFilter(
                      ref,
                      filters.copyWith(selectedConstellations: selected),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],

              // Magnitude range
              if (magRange != null) ...[
                Expanded(
                  flex: 2,
                  child: _RangeSliderControl(
                    label: 'Magnitude',
                    currentMin: filters.minMagnitude ?? magRange.$1,
                    currentMax: filters.maxMagnitude ?? magRange.$2,
                    rangeMin: magRange.$1,
                    rangeMax: magRange.$2,
                    divisions:
                        ((magRange.$2 - magRange.$1) * 2).round().clamp(1, 100),
                    minValueFormatter: (v) => v.toStringAsFixed(1),
                    maxValueFormatter: (v) => v.toStringAsFixed(1),
                    colors: colors,
                    onChanged: (min, max) {
                      final isMinDefault = (min - magRange.$1).abs() < 0.01;
                      final isMaxDefault = (max - magRange.$2).abs() < 0.01;
                      _updateFilter(
                        ref,
                        filters.copyWith(
                          minMagnitude: () => isMinDefault ? null : min,
                          maxMagnitude: () => isMaxDefault ? null : max,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
              ],

              // Size range
              if (sizeRange != null) ...[
                Expanded(
                  flex: 2,
                  child: _RangeSliderControl(
                    label: 'Size',
                    currentMin: filters.minSizeArcmin ?? sizeRange.$1,
                    currentMax: filters.maxSizeArcmin ?? sizeRange.$2,
                    rangeMin: sizeRange.$1,
                    rangeMax: sizeRange.$2,
                    divisions: ((sizeRange.$2 - sizeRange.$1) / 0.5)
                        .round()
                        .clamp(1, 100),
                    minValueFormatter: (v) => "${v.toStringAsFixed(1)}'",
                    maxValueFormatter: (v) => "${v.toStringAsFixed(1)}'",
                    colors: colors,
                    onChanged: (min, max) {
                      final isMinDefault = (min - sizeRange.$1).abs() < 0.01;
                      final isMaxDefault = (max - sizeRange.$2).abs() < 0.01;
                      _updateFilter(
                        ref,
                        filters.copyWith(
                          minSizeArcmin: () => isMinDefault ? null : min,
                          maxSizeArcmin: () => isMaxDefault ? null : max,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
              ],

              // Min score
              Expanded(
                flex: 2,
                child: _SliderControl(
                  label: 'Min Score',
                  value: config.minScore,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  valueFormatter: (v) => '${v.round()}',
                  colors: colors,
                  onChanged: (value) => _updateConfig(
                    ref,
                    config.copyWith(minScore: value),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Min altitude
              Expanded(
                flex: 2,
                child: _SliderControl(
                  label: 'Min Altitude',
                  value: config.minAltitude,
                  min: 0,
                  max: 90,
                  divisions: 18,
                  valueFormatter: (v) => '${v.round()}°',
                  colors: colors,
                  onChanged: (value) => _updateConfig(
                    ref,
                    config.copyWith(minAltitude: value),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    TargetSuggestionConfig config,
    SuggestionFilterState filters,
    List<String> availableTypes,
    List<String> availableConstellations,
    (double, double)? magRange,
    (double, double)? sizeRange,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with reset button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Suggestions',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                _ResetFiltersButton(
                  colors: colors,
                  onPressed: () => _resetAll(ref),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Object type chips
            if (availableTypes.isNotEmpty) ...[
              Text(
                'Object Types',
                style: NightshadeTypography.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _ObjectTypeChips(
                availableTypes: availableTypes,
                selectedTypes: config.preferredObjectTypes,
                colors: colors,
                onChanged: (types) => _updateConfig(
                  ref,
                  config.copyWith(preferredObjectTypes: types),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Constellation chips
            if (availableConstellations.isNotEmpty) ...[
              Text(
                'Constellation',
                style: NightshadeTypography.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _ConstellationChips(
                availableConstellations: availableConstellations,
                selectedConstellations: filters.selectedConstellations,
                colors: colors,
                onChanged: (selected) => _updateFilter(
                  ref,
                  filters.copyWith(selectedConstellations: selected),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Sort mode
            Text(
              'Sort By',
              style: NightshadeTypography.label.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _SortModeSegmentedButton(
              value: config.sortMode,
              colors: colors,
              onChanged: (mode) => _updateConfig(
                ref,
                config.copyWith(sortMode: mode),
              ),
            ),
            const SizedBox(height: 20),

            // Magnitude range slider
            if (magRange != null) ...[
              _RangeSliderControl(
                label: 'Magnitude Range',
                currentMin: filters.minMagnitude ?? magRange.$1,
                currentMax: filters.maxMagnitude ?? magRange.$2,
                rangeMin: magRange.$1,
                rangeMax: magRange.$2,
                divisions:
                    ((magRange.$2 - magRange.$1) * 2).round().clamp(1, 100),
                minValueFormatter: (v) => v.toStringAsFixed(1),
                maxValueFormatter: (v) => v.toStringAsFixed(1),
                minLabel: 'Brighter',
                maxLabel: 'Fainter',
                showLabel: true,
                colors: colors,
                onChanged: (min, max) {
                  final isMinDefault = (min - magRange.$1).abs() < 0.01;
                  final isMaxDefault = (max - magRange.$2).abs() < 0.01;
                  _updateFilter(
                    ref,
                    filters.copyWith(
                      minMagnitude: () => isMinDefault ? null : min,
                      maxMagnitude: () => isMaxDefault ? null : max,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // Object size range slider
            if (sizeRange != null) ...[
              _RangeSliderControl(
                label: 'Object Size',
                currentMin: filters.minSizeArcmin ?? sizeRange.$1,
                currentMax: filters.maxSizeArcmin ?? sizeRange.$2,
                rangeMin: sizeRange.$1,
                rangeMax: sizeRange.$2,
                divisions:
                    ((sizeRange.$2 - sizeRange.$1) / 0.5).round().clamp(1, 100),
                minValueFormatter: (v) => "${v.toStringAsFixed(1)}'",
                maxValueFormatter: (v) => "${v.toStringAsFixed(1)}'",
                showLabel: true,
                colors: colors,
                onChanged: (min, max) {
                  final isMinDefault = (min - sizeRange.$1).abs() < 0.01;
                  final isMaxDefault = (max - sizeRange.$2).abs() < 0.01;
                  _updateFilter(
                    ref,
                    filters.copyWith(
                      minSizeArcmin: () => isMinDefault ? null : min,
                      maxSizeArcmin: () => isMaxDefault ? null : max,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // Moon distance slider
            _SliderControl(
              label: 'Min Moon Distance',
              value: filters.minMoonDistance ?? 0,
              min: 0,
              max: 180,
              divisions: 36,
              valueFormatter: (v) => v.round() == 0 ? 'Off' : '${v.round()}°',
              colors: colors,
              onChanged: (value) => _updateFilter(
                ref,
                filters.copyWith(
                  minMoonDistance: () => value <= 0 ? null : value,
                ),
              ),
              showLabel: true,
            ),
            const SizedBox(height: 16),

            // Imaging time slider
            _SliderControl(
              label: 'Min Imaging Time',
              value: filters.minImagingHours ?? 0,
              min: 0,
              max: 10,
              divisions: 20,
              valueFormatter: (v) =>
                  v <= 0 ? 'Off' : '${v.toStringAsFixed(1)}h',
              colors: colors,
              onChanged: (value) => _updateFilter(
                ref,
                filters.copyWith(
                  minImagingHours: () => value <= 0 ? null : value,
                ),
              ),
              showLabel: true,
            ),
            const SizedBox(height: 16),

            // Minimum score slider
            _SliderControl(
              label: 'Minimum Score',
              value: config.minScore,
              min: 0,
              max: 100,
              divisions: 20,
              valueFormatter: (v) => '${v.round()}',
              colors: colors,
              onChanged: (value) => _updateConfig(
                ref,
                config.copyWith(minScore: value),
              ),
              showLabel: true,
            ),
            const SizedBox(height: 16),

            // Minimum altitude slider
            _SliderControl(
              label: 'Minimum Altitude',
              value: config.minAltitude,
              min: 0,
              max: 90,
              divisions: 18,
              valueFormatter: (v) => '${v.round()}°',
              colors: colors,
              onChanged: (value) => _updateConfig(
                ref,
                config.copyWith(minAltitude: value),
              ),
              showLabel: true,
            ),
            const SizedBox(height: 16),

            // Prioritize incomplete toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prioritize Incomplete Targets',
                        style: NightshadeTypography.label.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rank targets with less data collected higher',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                NightshadeSwitch(
                  value: config.prioritizeIncomplete,
                  onChanged: (value) => _updateConfig(
                    ref,
                    config.copyWith(prioritizeIncomplete: value),
                  ),
                ),
              ],
            ),

            // Bottom padding for safe area
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _updateConfig(WidgetRef ref, TargetSuggestionConfig newConfig) {
    ref.read(targetSuggestionConfigProvider.notifier).state = newConfig;
  }

  void _updateFilter(WidgetRef ref, SuggestionFilterState newFilter) {
    ref.read(suggestionFilterProvider.notifier).state = newFilter;
  }

  void _resetAll(WidgetRef ref) {
    // Reset the scoring/sort config
    ref.read(targetSuggestionConfigProvider.notifier).state =
        const TargetSuggestionConfig(
      minAltitude: 30.0,
      minScore: 50.0,
      prioritizeIncomplete: true,
      sortMode: SuggestionSortMode.bestScore,
      preferredObjectTypes: [],
    );
    // Reset the UI filter state
    ref.read(suggestionFilterProvider.notifier).state =
        const SuggestionFilterState();
  }
}

/// Provider that fetches distinct object types from the user's target list.
final _availableObjectTypesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final database = ref.watch(databaseProvider);
  final targets = await database.targetsDao.getAllTargets();

  // Extract unique object types
  final types = <String>{};
  for (final target in targets) {
    if (target.objectType != null && target.objectType!.isNotEmpty) {
      types.add(target.objectType!);
    }
  }

  // Sort alphabetically for consistent display
  final sortedTypes = types.toList()..sort();
  return sortedTypes;
});
