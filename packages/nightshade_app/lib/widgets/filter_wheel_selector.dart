import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../utils/snackbar_helper.dart';

/// Style options for the filter wheel selector.
enum FilterSelectorStyle {
  /// Shows filters as colored circular buttons.
  buttons,
  /// Shows filters in a dropdown menu.
  dropdown
}

/// Reusable widget for filter wheel selection.
///
/// This eliminates duplicate filter selection implementations across screens.
/// Supports both button-based and dropdown-based selection styles.
class FilterWheelSelector extends ConsumerStatefulWidget {
  /// The style of filter selection UI to display.
  final FilterSelectorStyle style;

  /// Callback invoked when a filter is selected.
  final void Function(int position, String name)? onFilterSelected;

  /// Whether to use compact sizing.
  final bool compact;

  const FilterWheelSelector({
    super.key,
    this.style = FilterSelectorStyle.buttons,
    this.onFilterSelected,
    this.compact = false,
  });

  @override
  ConsumerState<FilterWheelSelector> createState() => _FilterWheelSelectorState();

  /// Returns the display color for a filter based on its name.
  ///
  /// Common filter types are mapped to recognizable colors:
  /// - Red/R/Ha → Red
  /// - Green/G → Green
  /// - Blue/B → Blue
  /// - Lum/L/Clear → Grey
  /// - OIII/O3 → Teal
  /// - SII/S2 → Deep Orange
  /// - NII/N2 → Purple
  static Color getFilterColor(String name) {
    final n = name.toUpperCase();
    if (n.contains('RED') || n == 'R' || n.contains('HA') || n.contains('H-ALPHA')) return Colors.red;
    if (n.contains('GREEN') || n == 'G') return Colors.green;
    if (n.contains('BLUE') || n == 'B') return Colors.blue;
    if (n.contains('LUM') || n == 'L' || n.contains('CLEAR')) return Colors.grey;
    if (n.contains('OIII') || n.contains('O3') || n.contains('O-III')) return Colors.teal;
    if (n.contains('SII') || n.contains('S2') || n.contains('S-II')) return Colors.deepOrange;
    if (n.contains('NII') || n.contains('N2')) return Colors.purple;
    return Colors.grey;
  }
}

class _FilterWheelSelectorState extends ConsumerState<FilterWheelSelector> {
  Future<void> _selectFilter(int position) async {
    try {
      // Always use deviceService - it handles filter offsets
      await ref.read(deviceServiceProvider).setFilterWheelPosition(position);
      final fwState = ref.read(filterWheelStateProvider);
      if (widget.onFilterSelected != null && fwState.filterNames.length > position) {
        widget.onFilterSelected!(position, fwState.filterNames[position]);
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to change filter: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fwState = ref.watch(filterWheelStateProvider);
    final filterNames = fwState.filterNames;
    final currentPosition = fwState.currentPosition;
    final isMoving = fwState.isMoving;

    // Don't show if no filters configured
    if (filterNames.isEmpty) return const SizedBox.shrink();

    if (widget.style == FilterSelectorStyle.dropdown) {
      final validPosition = currentPosition != null && currentPosition >= 0 && currentPosition < filterNames.length;
      return DropdownButton<int>(
        value: validPosition ? currentPosition : null,
        items: filterNames.asMap().entries.map((e) => DropdownMenuItem(
          value: e.key,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: FilterWheelSelector.getFilterColor(e.value),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(e.value),
            ],
          ),
        )).toList(),
        onChanged: isMoving ? null : (pos) => pos != null ? _selectFilter(pos) : null,
      );
    }

    // Button style
    return Wrap(
      spacing: widget.compact ? 4 : 8,
      runSpacing: widget.compact ? 4 : 8,
      children: filterNames.asMap().entries.map((e) => _FilterButton(
        label: e.value,
        color: FilterWheelSelector.getFilterColor(e.value),
        isSelected: currentPosition != null && e.key == currentPosition,
        compact: widget.compact,
        onTap: isMoving ? null : () => _selectFilter(e.key),
      )).toList(),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool compact;
  final VoidCallback? onTap;

  const _FilterButton({
    required this.label,
    required this.color,
    required this.isSelected,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? color : color.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
