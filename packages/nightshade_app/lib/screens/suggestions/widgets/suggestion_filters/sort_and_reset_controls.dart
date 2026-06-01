part of '../suggestion_filters.dart';

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
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
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
              color:
                  value ? colors.primary.withValues(alpha: 0.5) : colors.border,
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
