// Summary chips, quality-filter chips, science badges and detail rows.
part of '../image_thumbnail_strip.dart';

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        '$label: $value',
        style: NightshadeTypography.labelStrongSm.copyWith(
          color: color,
        ),
      ),
    );
  }
}

class _QualityFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QualityFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(
          color: selected ? colors.textPrimary : colors.textSecondary,
        ),
      ),
      selected: selected,
      selectedColor: colors.primary.withValues(alpha: 0.2),
      backgroundColor: colors.surfaceAlt,
      side: BorderSide(color: selected ? colors.primary : colors.border),
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

enum _FrameMenuAction { accept, reject, info }

class _ScienceBadge extends StatelessWidget {
  final String tooltip;
  final Color color;
  final String? label;
  final IconData? icon;

  const _ScienceBadge({
    required this.tooltip,
    required this.color,
    this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 3 : 4,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        ),
        child: icon != null
            ? Icon(icon, size: 9, color: const Color(0xFFFFFFFF))
            : Text(
                label ?? '',
                style: const TextStyle(
                  fontSize: NightshadeTypography.fontSize8,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF),
                ),
              ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _DetailRow(this.label, this.value, this.colors);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: NightshadeTypography.h6.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
