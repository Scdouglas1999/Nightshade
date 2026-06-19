import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Tokenized chip / toggle-chip — replaces ad-hoc [InputChip], [FilterChip],
/// and hand-rolled pill widgets.
///
/// When [onTap] is non-null the chip is interactive and reflects [selected]
/// with the design system's accent fill. For a status indicator (icon + value
/// with semantic color) use [StatusPill] instead.
class NightshadeChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const NightshadeChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final foreground = selected ? colors.primary : colors.textSecondary;

    final chip = AnimatedContainer(
      duration: NightshadeTokens.durationQuick,
      curve: NightshadeTokens.curveSnappy,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: NightshadeTokens.opacitySubtle)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(
          color: selected
              ? colors.primary.withValues(alpha: NightshadeTokens.opacityStrong)
              : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: NightshadeTokens.iconXs, color: foreground),
            const SizedBox(width: NightshadeTokens.spaceXs),
          ],
          Text(
            label,
            style: NightshadeTypography.labelSm.copyWith(color: foreground),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      child: chip,
    );
  }
}
