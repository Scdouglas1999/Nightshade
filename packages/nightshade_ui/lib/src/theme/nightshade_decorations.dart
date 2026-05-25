import 'package:flutter/material.dart';

import 'nightshade_colors.dart';
import 'nightshade_tokens.dart';

/// Shared [BoxDecoration] helpers and color utilities for the Nightshade UI.
///
/// Use these for tinted surfaces, chips, and interactive states inside custom
/// layouts. Prefer [NightshadeCard] when you need a full card container with
/// padding, hover/selection behavior, and standard surface backgrounds.
abstract final class NightshadeDecorations {
  NightshadeDecorations._();

  /// Subtle tinted container for icon chips and accent badges.
  ///
  /// Use for small icon backgrounds inside rows or list items. For a full
  /// bordered content panel, use [NightshadeCard] instead.
  static BoxDecoration iconChip(
    Color color, {
    BorderRadius? borderRadius,
    bool bordered = true,
    double borderAlpha = NightshadeTokens.opacityBorderMedium,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: NightshadeTokens.opacitySubtle),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: bordered
          ? Border.all(color: color.withValues(alpha: borderAlpha))
          : null,
    );
  }

  /// Tinted surface with emphasis border (10% fill, 30% border).
  ///
  /// Use for inline emphasis blocks inside a parent surface — not a card shell.
  static BoxDecoration emphasisSurface(
    Color color, {
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: NightshadeTokens.opacitySubtle),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: color.withValues(alpha: NightshadeTokens.opacityStrong),
      ),
    );
  }

  /// Tinted badge background without a border.
  ///
  /// Use for compact inline badges; pair with [NightshadeCard] when the badge
  /// wraps substantial content.
  static BoxDecoration tintedBadge(
    Color color, {
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: NightshadeTokens.opacitySubtle),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
    );
  }

  /// Status or state indicator chip ([NightshadeTokens.opacityStatusFill] fill,
  /// optional [NightshadeTokens.opacityStrong] border).
  ///
  /// Use for status pills and inline state chips — not full card containers.
  static BoxDecoration statusChip(
    Color color, {
    BorderRadius? borderRadius,
    bool bordered = true,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: NightshadeTokens.opacityStatusFill),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: bordered
          ? Border.all(
              color: color.withValues(alpha: NightshadeTokens.opacityStrong),
            )
          : null,
    );
  }

  /// Selected or active toggle surface.
  ///
  /// Use for selectable tiles and toggles inside lists. [NightshadeCard] with
  /// [CardVariant.elevated] covers full card selection chrome.
  static BoxDecoration selectedSurface(
    Color color, {
    BorderRadius? borderRadius,
    double fillAlpha = NightshadeTokens.opacityStatusFill,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: fillAlpha),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: color.withValues(alpha: NightshadeTokens.opacityStrong),
      ),
    );
  }

  /// Background and border colors for solid accent buttons on hover.
  ///
  /// Matches the hover treatment used by [NightshadeButton] filled variants.
  static ({Color background, Color border}) filledButtonColors(
    Color base, {
    required bool isHovered,
    required bool isDisabled,
  }) {
    if (isDisabled) {
      return (
        background: base.withValues(alpha: NightshadeTokens.opacityHalf),
        border: base.withValues(alpha: NightshadeTokens.opacityHalf),
      );
    }
    return (
      background: isHovered
          ? Color.lerp(
              base,
              const Color(0xFFFFFFFF),
              NightshadeTokens.buttonHoverLighten,
            )!
          : base,
      border: Color.lerp(
        base,
        const Color(0xFF000000),
        NightshadeTokens.buttonBorderDarken,
      )!,
    );
  }

  /// Selected navigation rail / sidebar item (4% primary tint, emphasis border).
  ///
  /// Navigation-specific; [NightshadeCard] handles generic card selection.
  static BoxDecoration navSelected(
    NightshadeColors colors, {
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: Color.alphaBlend(
        colors.primary.withValues(alpha: NightshadeTokens.opacityTint),
        colors.surfaceAlt,
      ),
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: colors.primary
            .withValues(alpha: NightshadeTokens.opacityEmphasisBorder),
      ),
    );
  }

  /// Selected card with accent tint and emphasis border — no colored glow.
  ///
  /// Lower-level than [NightshadeCard.isSelected]; use when building custom
  /// card chrome outside the component.
  static BoxDecoration cardSelected(
    Color accent, {
    Color? background,
    BorderRadius? borderRadius,
    double borderWidth = 1,
  }) {
    final fill = background != null
        ? Color.alphaBlend(
            accent.withValues(alpha: NightshadeTokens.opacityTint),
            background,
          )
        : accent.withValues(alpha: NightshadeTokens.opacityTint);
    return BoxDecoration(
      color: fill,
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: accent.withValues(alpha: NightshadeTokens.opacityEmphasisBorder),
        width: borderWidth,
      ),
    );
  }

  /// Hover state for interactive cards — border emphasis only.
  ///
  /// Pair with [NightshadeCard.enableHover] when possible; use this for custom
  /// hover targets that are not [NightshadeCard] instances.
  static BoxDecoration cardHover(
    NightshadeColors colors, {
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: colors.surfaceHover,
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: colors.borderHighlight.withValues(
          alpha: NightshadeTokens.opacityHoverBorder,
        ),
      ),
    );
  }

  /// Drag-and-drop feedback frame — neutral elevation, no colored glow.
  static BoxDecoration dragFeedback(
    NightshadeColors colors, {
    BorderRadius? borderRadius,
    Color? accentColor,
  }) {
    final accent = accentColor ?? colors.primary;
    return BoxDecoration(
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusMd,
      border: Border.all(
        color: accent.withValues(alpha: NightshadeTokens.opacityStrong),
      ),
      boxShadow: NightshadeTokens.elevationLevel2,
    );
  }

  /// Circular or rounded KPI / score badge (15% fill, 40% border).
  static BoxDecoration kpiBadge(
    Color color, {
    BorderRadius? borderRadius,
    BoxShape shape = BoxShape.circle,
  }) {
    return BoxDecoration(
      shape: shape,
      color: color.withValues(alpha: NightshadeTokens.opacityStatusFill),
      borderRadius: shape == BoxShape.circle
          ? null
          : (borderRadius ?? NightshadeTokens.borderRadiusMd),
      border: Border.all(
        color: color.withValues(alpha: NightshadeTokens.opacityBadgeBorder),
      ),
    );
  }

  /// Full decoration for a solid accent button.
  static BoxDecoration filledButton(
    Color base, {
    required bool isHovered,
    required bool isDisabled,
    BorderRadius? borderRadius,
  }) {
    final colors = filledButtonColors(
      base,
      isHovered: isHovered,
      isDisabled: isDisabled,
    );
    return BoxDecoration(
      color: colors.background,
      borderRadius: borderRadius ?? NightshadeTokens.borderRadiusButton,
      border: Border.all(color: colors.border),
    );
  }
}
