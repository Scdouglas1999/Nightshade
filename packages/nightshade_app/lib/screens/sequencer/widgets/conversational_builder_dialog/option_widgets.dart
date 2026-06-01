part of '../conversational_builder_dialog.dart';

class _OptionChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? colors.primary : colors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusXl),
                ).color
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.4)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaxHoursPicker extends StatelessWidget {
  final NightshadeColors colors;
  final double? value;
  final ValueChanged<double?> onChanged;

  const _MaxHoursPicker({
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = <double?>[null, 2.0, 3.0, 4.0, 6.0, 8.0];
    return Wrap(
      spacing: 4,
      children: [
        for (final opt in options)
          ChoiceChip(
            label: Text(
              opt == null ? 'No cap' : '${opt.toStringAsFixed(0)}h',
              style: const TextStyle(fontSize: 11),
            ),
            selected: value == opt,
            onSelected: (_) => onChanged(opt),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
