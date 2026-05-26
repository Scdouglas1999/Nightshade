import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../utils/responsive_utils.dart';

/// Typography-led screen header with a crisp bottom divider.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets? padding;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Container(
      padding: padding ?? Responsive.adaptivePadding(context),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.75)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: NightshadeTokens.iconMd,
              color: colors.textSecondary,
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: NightshadeTypography.h3.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  Text(
                    subtitle!,
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Section header using typography hierarchy instead of decorative accents.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double accentBarWidth;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accentBarWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: NightshadeTypography.h5.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  Text(
                    subtitle!,
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A container for grouped controls with tonal separation.
class SectionWell extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const SectionWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NightshadeTokens.spaceLg),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final effectiveRadius = borderRadius ?? NightshadeTokens.borderRadiusMd;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: effectiveRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.65),
        ),
      ),
      child: child,
    );
  }
}
