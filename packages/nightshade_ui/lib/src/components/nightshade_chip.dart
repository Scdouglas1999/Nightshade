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

  /// Whether an option chip can be chosen right now.
  ///
  /// This is NOT the same state as `onTap == null`, which means "this chip is a
  /// status label and was never an option". A disabled chip is an option that
  /// exists but is currently unavailable, and it has to READ that way: callers
  /// used to express it by passing a null [onTap], which rendered a chip
  /// pixel-identical to an unselected one, so an unavailable choice looked like
  /// a choice the operator simply had not clicked yet — and a screen reader was
  /// told nothing at all. Disabling dims the chip, announces it as a disabled
  /// button, and shows the not-allowed cursor.
  final bool enabled;

  const NightshadeChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final foreground = !enabled
        ? colors.textMuted.withValues(alpha: NightshadeTokens.opacityDisabled)
        : (selected ? colors.primary : colors.textSecondary);

    final chip = AnimatedContainer(
      duration: NightshadeTokens.durationQuick,
      curve: NightshadeTokens.curveSnappy,
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: !enabled
            ? colors.surfaceAlt.withValues(alpha: NightshadeTokens.opacityHalf)
            : selected
            ? colors.primary.withValues(alpha: NightshadeTokens.opacitySubtle)
            : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(
          color: !enabled
              ? colors.border.withValues(alpha: NightshadeTokens.opacityHalf)
              : selected
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

    if (onTap == null && enabled) {
      // A non-interactive chip is a status label; expose its text, but not a
      // button/selected role it cannot honour.
      return chip;
    }

    if (!enabled) {
      // Still announced as a button so assistive tech reports the option and
      // that it is unavailable, rather than reading a bare word with no role.
      return Semantics(
        button: true,
        enabled: false,
        selected: selected,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.forbidden,
          child: ExcludeSemantics(child: chip),
        ),
      );
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
