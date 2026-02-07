import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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
/// suggestion list to refresh automatically via [filteredSuggestionsProvider].
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
        context, ref, colors, config, filters,
        availableTypes, availableConstellations, magRange, sizeRange,
      );
    } else {
      return _buildDesktopLayout(
        context, ref, colors, config, filters,
        availableTypes, availableConstellations, magRange, sizeRange,
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
                    divisions: ((magRange.$2 - magRange.$1) * 2).round().clamp(1, 100),
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
                    divisions: ((sizeRange.$2 - sizeRange.$1) / 0.5).round().clamp(1, 100),
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                    fontSize: 18,
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
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
                divisions: ((magRange.$2 - magRange.$1) * 2).round().clamp(1, 100),
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
                divisions: ((sizeRange.$2 - sizeRange.$1) / 0.5).round().clamp(1, 100),
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
              valueFormatter: (v) => v <= 0 ? 'Off' : '${v.toStringAsFixed(1)}h',
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
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rank targets with less data collected higher',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: config.prioritizeIncomplete,
                  onChanged: (value) => _updateConfig(
                    ref,
                    config.copyWith(prioritizeIncomplete: value),
                  ),
                  activeTrackColor: colors.primary.withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return colors.primary;
                    }
                    return colors.textMuted;
                  }),
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

// ============================================================================
// Multi-select Chips
// ============================================================================

/// Multi-select chips for object type filtering.
class _ObjectTypeChips extends StatelessWidget {
  final List<String> availableTypes;
  final List<String> selectedTypes;
  final NightshadeColors colors;
  final ValueChanged<List<String>> onChanged;

  const _ObjectTypeChips({
    required this.availableTypes,
    required this.selectedTypes,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: availableTypes.map((type) {
        final isSelected = selectedTypes.contains(type);
        return _FilterChip(
          label: _formatObjectType(type),
          isSelected: isSelected,
          colors: colors,
          onTap: () {
            final newSelection = List<String>.from(selectedTypes);
            if (isSelected) {
              newSelection.remove(type);
            } else {
              newSelection.add(type);
            }
            onChanged(newSelection);
          },
        );
      }).toList(),
    );
  }

  String _formatObjectType(String type) {
    final displayNames = {
      'galaxy': 'Galaxy',
      'nebula': 'Nebula',
      'cluster': 'Cluster',
      'star': 'Star',
      'planet': 'Planet',
      'moon': 'Moon',
      'comet': 'Comet',
      'asteroid': 'Asteroid',
      'planetary_nebula': 'Planetary Nebula',
      'planetaryNebula': 'Planetary Nebula',
      'star_cluster': 'Star Cluster',
      'starCluster': 'Star Cluster',
      'open_cluster': 'Open Cluster',
      'openCluster': 'Open Cluster',
      'globular_cluster': 'Globular Cluster',
      'globularCluster': 'Globular Cluster',
      'emission_nebula': 'Emission Nebula',
      'emissionNebula': 'Emission Nebula',
      'reflection_nebula': 'Reflection Nebula',
      'reflectionNebula': 'Reflection Nebula',
      'dark_nebula': 'Dark Nebula',
      'darkNebula': 'Dark Nebula',
      'supernova_remnant': 'Supernova Remnant',
      'supernovaRemnant': 'Supernova Remnant',
      'double_star': 'Double Star',
      'doubleStar': 'Double Star',
      'asterism': 'Asterism',
      'other': 'Other',
      'unknown': 'Unknown',
    };

    final normalized = type.toLowerCase();
    if (displayNames.containsKey(normalized)) {
      return displayNames[normalized]!;
    }
    if (displayNames.containsKey(type)) {
      return displayNames[type]!;
    }

    if (type.isEmpty) return type;
    return type[0].toUpperCase() + type.substring(1);
  }
}

/// Multi-select chips for constellation filtering.
class _ConstellationChips extends StatelessWidget {
  final List<String> availableConstellations;
  final Set<String> selectedConstellations;
  final NightshadeColors colors;
  final ValueChanged<Set<String>> onChanged;

  const _ConstellationChips({
    required this.availableConstellations,
    required this.selectedConstellations,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: availableConstellations.map((constellation) {
        final isSelected = selectedConstellations.contains(constellation);
        return _FilterChip(
          label: constellation,
          isSelected: isSelected,
          colors: colors,
          onTap: () {
            final newSelection = Set<String>.from(selectedConstellations);
            if (isSelected) {
              newSelection.remove(constellation);
            } else {
              newSelection.add(constellation);
            }
            onChanged(newSelection);
          },
        );
      }).toList(),
    );
  }
}

/// Reusable filter chip used by both object type and constellation chips.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                LucideIcons.check,
                size: 12,
                color: colors.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Slider Controls
// ============================================================================

/// Slider control with label and value display.
class _SliderControl extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) valueFormatter;
  final NightshadeColors colors;
  final ValueChanged<double> onChanged;
  final bool showLabel;

  const _SliderControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueFormatter,
    required this.colors,
    required this.onChanged,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: showLabel ? 13 : 11,
                fontWeight: showLabel ? FontWeight.w500 : FontWeight.normal,
                color: showLabel ? colors.textSecondary : colors.textMuted,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                valueFormatter(value),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
            overlayColor: colors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Range slider control with label and two value badges showing min–max.
class _RangeSliderControl extends StatelessWidget {
  final String label;
  final double currentMin;
  final double currentMax;
  final double rangeMin;
  final double rangeMax;
  final int divisions;
  final String Function(double) minValueFormatter;
  final String Function(double) maxValueFormatter;
  final NightshadeColors colors;
  final void Function(double min, double max) onChanged;
  final String? minLabel;
  final String? maxLabel;
  final bool showLabel;

  const _RangeSliderControl({
    required this.label,
    required this.currentMin,
    required this.currentMax,
    required this.rangeMin,
    required this.rangeMax,
    required this.divisions,
    required this.minValueFormatter,
    required this.maxValueFormatter,
    required this.colors,
    required this.onChanged,
    this.minLabel,
    this.maxLabel,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    // Clamp values to the valid range
    final clampedMin = currentMin.clamp(rangeMin, rangeMax);
    final clampedMax = currentMax.clamp(rangeMin, rangeMax);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: showLabel ? 13 : 11,
                fontWeight: showLabel ? FontWeight.w500 : FontWeight.normal,
                color: showLabel ? colors.textSecondary : colors.textMuted,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _valueBadge(minValueFormatter(clampedMin)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '–',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
                _valueBadge(maxValueFormatter(clampedMax)),
              ],
            ),
          ],
        ),
        // Optional min/max semantic labels
        if (minLabel != null || maxLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (minLabel != null)
                Text(
                  minLabel!,
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              if (maxLabel != null)
                Text(
                  maxLabel!,
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceAlt,
            thumbColor: colors.primary,
            overlayColor: colors.primary.withValues(alpha: 0.2),
            trackHeight: 4,
            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: RangeSlider(
            values: RangeValues(clampedMin, clampedMax),
            min: rangeMin,
            max: rangeMax,
            divisions: divisions,
            onChanged: (values) => onChanged(values.start, values.end),
          ),
        ),
      ],
    );
  }

  Widget _valueBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

// ============================================================================
// Sort & Toggle Controls
// ============================================================================

/// Dropdown for selecting sort mode (desktop).
class _SortModeDropdown extends StatelessWidget {
  final SuggestionSortMode value;
  final NightshadeColors colors;
  final ValueChanged<SuggestionSortMode> onChanged;

  const _SortModeDropdown({
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sort',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButton<SuggestionSortMode>(
            value: value,
            onChanged: (mode) {
              if (mode != null) onChanged(mode);
            },
            underline: const SizedBox.shrink(),
            isDense: true,
            dropdownColor: colors.surfaceAlt,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
            ),
            items: SuggestionSortMode.values.map((mode) {
              return DropdownMenuItem(
                value: mode,
                child: Text(_sortModeLabel(mode)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _sortModeLabel(SuggestionSortMode mode) {
    switch (mode) {
      case SuggestionSortMode.bestScore:
        return 'Best Score';
      case SuggestionSortMode.highestAltitude:
        return 'Highest Altitude';
      case SuggestionSortMode.nearestTransit:
        return 'Nearest Transit';
      case SuggestionSortMode.leastDataCollected:
        return 'Least Data';
    }
  }
}

/// Segmented button for selecting sort mode (mobile).
class _SortModeSegmentedButton extends StatelessWidget {
  final SuggestionSortMode value;
  final NightshadeColors colors;
  final ValueChanged<SuggestionSortMode> onChanged;

  const _SortModeSegmentedButton({
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: SuggestionSortMode.values.map((mode) {
        final isSelected = mode == value;
        return InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.15)
                  : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.5)
                    : colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _sortModeIcon(mode),
                  size: 14,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _sortModeLabel(mode),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? colors.primary : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _sortModeIcon(SuggestionSortMode mode) {
    switch (mode) {
      case SuggestionSortMode.bestScore:
        return LucideIcons.trophy;
      case SuggestionSortMode.highestAltitude:
        return LucideIcons.arrowUp;
      case SuggestionSortMode.nearestTransit:
        return LucideIcons.clock;
      case SuggestionSortMode.leastDataCollected:
        return LucideIcons.database;
    }
  }

  String _sortModeLabel(SuggestionSortMode mode) {
    switch (mode) {
      case SuggestionSortMode.bestScore:
        return 'Best Score';
      case SuggestionSortMode.highestAltitude:
        return 'Highest';
      case SuggestionSortMode.nearestTransit:
        return 'Transit';
      case SuggestionSortMode.leastDataCollected:
        return 'Least Data';
    }
  }
}

/// Toggle switch for prioritizing incomplete targets (desktop).
class _PrioritizeIncompleteToggle extends StatelessWidget {
  final bool value;
  final NightshadeColors colors;
  final ValueChanged<bool> onChanged;

  const _PrioritizeIncompleteToggle({
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Rank targets with less data collected higher',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: value
                ? colors.primary.withValues(alpha: 0.15)
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: value
                  ? colors.primary.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? LucideIcons.checkCircle : LucideIcons.circle,
                size: 14,
                color: value ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'Incomplete',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                  color: value ? colors.primary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button to reset all filters to defaults.
class _ResetFiltersButton extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _ResetFiltersButton({
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Reset all filters to defaults',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.rotateCcw,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Reset',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
