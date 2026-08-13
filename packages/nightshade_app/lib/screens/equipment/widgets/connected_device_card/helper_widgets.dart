part of '../connected_device_card.dart';

// ============================================================================
// Helper Widgets
// ============================================================================

class _DeviceMetric {
  final String value;
  final String label;
  final Color? valueColor;

  _DeviceMetric({required this.value, required this.label, this.valueColor});
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final NightshadeColors colors;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.onLongPress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onTap == null ? null : onLongPress,
      child: NightshadeButton(
        onPressed: onTap,
        label: label,
        variant: ButtonVariant.outline,
        size: ButtonSize.small,
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final List<String> filterNames;
  final int? currentPosition;
  final ValueChanged<int> onFilterSelected;
  final bool enabled;
  final NightshadeColors colors;

  const _FilterDropdown({
    required this.filterNames,
    required this.currentPosition,
    required this.onFilterSelected,
    this.enabled = true,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (filterNames.isEmpty) {
      return _ActionButton(
        label: 'No filters',
        onTap: null,
        colors: colors,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: DropdownButtonHideUnderline(
        child: AccessibleDropdown<int>(
          value: currentPosition != null &&
                  currentPosition! >= 0 &&
                  currentPosition! < filterNames.length
              ? currentPosition
              : null,
          isDense: true,
          dropdownColor: colors.surface,
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary),
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          items: filterNames.asMap().entries.map((entry) {
            return DropdownMenuItem<int>(
              value: entry.key,
              child: Text(
                entry.value,
                style: TextStyle(color: colors.textPrimary),
              ),
            );
          }).toList(),
          onChanged: enabled
              ? (value) {
                  if (value != null) {
                    onFilterSelected(value);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TelemetryRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
