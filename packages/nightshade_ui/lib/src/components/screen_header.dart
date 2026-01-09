import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// A styled screen header with accent gradient and bottom border.
///
/// Features:
/// - Subtle bottom border with gradient fade (accent → transparent)
/// - Optional background gradient for subtle warmth
/// - Consistent spacing and typography
class ScreenHeader extends StatelessWidget {
  /// The title text to display
  final String title;

  /// Optional subtitle or description
  final String? subtitle;

  /// Optional icon to display before the title
  final IconData? icon;

  /// Optional trailing widget (e.g., action buttons)
  final Widget? trailing;

  /// Whether to show the accent gradient background
  final bool showBackgroundGradient;

  /// Custom padding for the header
  final EdgeInsets? padding;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.showBackgroundGradient = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        // Optional subtle accent gradient background (2-3% opacity)
        gradient: showBackgroundGradient
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.primary.withValues(alpha: 0.03),
                  Colors.transparent,
                ],
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
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
          const SizedBox(height: 16),
          // Bottom border with gradient fade (accent → transparent)
          _AccentGradientBorder(color: colors.primary),
        ],
      ),
    );
  }
}

/// A gradient border that fades from accent color to transparent.
class _AccentGradientBorder extends StatelessWidget {
  final Color color;

  const _AccentGradientBorder({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withValues(alpha: 0.5),
            color.withValues(alpha: 0.2),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// A section header with left accent bar.
///
/// Use this for organizing content within a screen into logical sections.
class SectionHeader extends StatelessWidget {
  /// The section title
  final String title;

  /// Optional subtitle
  final String? subtitle;

  /// Optional trailing widget
  final Widget? trailing;

  /// Width of the accent bar
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Left accent bar
          Container(
            width: accentBarWidth,
            height: subtitle != null ? 36 : 24,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(accentBarWidth / 2),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.3),
                  blurRadius: 4,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
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

/// A container for grouped controls with inset shadow background.
///
/// Use this to visually group related controls within a section.
class SectionWell extends StatelessWidget {
  /// The child content
  final Widget child;

  /// Padding inside the well
  final EdgeInsets padding;

  /// Border radius of the well
  final BorderRadius? borderRadius;

  const SectionWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final effectiveRadius = borderRadius ?? NightshadeTokens.borderRadiusMd;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: effectiveRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.3),
        ),
        // Simulated inset shadow using gradient
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.05),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0.0, 0.15, 1.0],
        ),
      ),
      child: child,
    );
  }
}
