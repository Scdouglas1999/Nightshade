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

    if (onTap == null) {
      // A non-interactive chip is a status label; expose its text, but not a
      // button/selected role it cannot honour.
      return chip;
    }

    // Announce the interactive chip as a toggle button and carry its
    // selected-state so a screen reader says e.g. "Confirmed, selected, button"
    // on the active filter — the `selected` flag drove only color before.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: ExcludeSemantics(child: chip),
      ),
    );
  }
}
