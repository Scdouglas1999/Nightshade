import 'package:flutter/material.dart';

/// Design tokens for consistent spacing, sizing, and timing across the app.
///
/// Usage:
/// ```dart
/// Padding(padding: NightshadeTokens.paddingMd)
/// Container(margin: NightshadeTokens.marginLg)
/// AnimatedContainer(duration: NightshadeTokens.durationNormal)
/// ```
abstract final class NightshadeTokens {
  NightshadeTokens._();

  // ===========================================================================
  // Spacing Scale (based on 4px grid)
  // ===========================================================================

  /// 4px - Tight spacing for dense UIs
  static const double spaceXs = 4.0;

  /// 8px - Small spacing
  static const double spaceSm = 8.0;

  /// 12px - Medium-small spacing
  static const double spaceMd = 12.0;

  /// 16px - Default spacing
  static const double spaceLg = 16.0;

  /// 20px - Medium-large spacing
  static const double spaceXl = 20.0;

  /// 24px - Large spacing (screen padding)
  static const double space2xl = 24.0;

  /// 32px - Extra large spacing
  static const double space3xl = 32.0;

  /// 48px - Section spacing
  static const double space4xl = 48.0;

  /// 64px - Large section spacing
  static const double space5xl = 64.0;

  // ===========================================================================
  // Edge Insets (Padding/Margin)
  // ===========================================================================

  static const EdgeInsets paddingXs = EdgeInsets.all(spaceXs);
  static const EdgeInsets paddingSm = EdgeInsets.all(spaceSm);
  static const EdgeInsets paddingMd = EdgeInsets.all(spaceMd);
  static const EdgeInsets paddingLg = EdgeInsets.all(spaceLg);
  static const EdgeInsets paddingXl = EdgeInsets.all(spaceXl);
  static const EdgeInsets padding2xl = EdgeInsets.all(space2xl);

  /// Standard screen padding (24px horizontal, 20px vertical)
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: space2xl,
    vertical: spaceXl,
  );

  /// Compact screen padding for smaller screens
  static const EdgeInsets screenPaddingCompact = EdgeInsets.symmetric(
    horizontal: spaceLg,
    vertical: spaceMd,
  );

  /// Card internal padding
  static const EdgeInsets cardPadding = EdgeInsets.all(spaceLg);

  /// Dialog internal padding
  static const EdgeInsets dialogPadding = EdgeInsets.all(space2xl);

  /// Button internal padding (horizontal, vertical)
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: spaceLg,
    vertical: spaceMd,
  );

  /// Input field internal padding
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: spaceMd,
    vertical: spaceMd,
  );

  // ===========================================================================
  // Border Radius Scale
  // ===========================================================================

  /// 4px - Small radius (pills, badges)
  static const double radiusXs = 4.0;

  /// 6px - Small-medium radius (buttons, tooltips)
  static const double radiusSm = 6.0;

  /// 8px - Default radius (inputs, small cards)
  static const double radiusMd = 8.0;

  /// 12px - Large radius (cards, panels)
  static const double radiusLg = 12.0;

  /// 16px - Extra large radius (dialogs, large panels)
  static const double radiusXl = 16.0;

  /// Fully rounded (for circular elements)
  static const double radiusFull = 999.0;

  // Convenience BorderRadius objects
  static final BorderRadius borderRadiusXs = BorderRadius.circular(radiusXs);
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // ===========================================================================
  // Animation Durations
  // ===========================================================================

  /// 100ms - Instant feedback (hover, active states)
  static const Duration durationFast = Duration(milliseconds: 100);

  /// 150ms - Quick transitions (button presses, toggles)
  static const Duration durationQuick = Duration(milliseconds: 150);

  /// 200ms - Normal transitions (most UI animations)
  static const Duration durationNormal = Duration(milliseconds: 200);

  /// 300ms - Slow transitions (expanding panels, modals)
  static const Duration durationSlow = Duration(milliseconds: 300);

  /// 500ms - Very slow transitions (complex animations)
  static const Duration durationSluggish = Duration(milliseconds: 500);

  /// 1500ms - Shimmer/loading animation cycle
  static const Duration durationShimmer = Duration(milliseconds: 1500);

  // ===========================================================================
  // Animation Curves
  // ===========================================================================

  /// Standard easing curve for most animations
  static const Curve curveStandard = Curves.easeInOut;

  /// Deceleration curve for entering elements
  static const Curve curveDecelerate = Curves.easeOut;

  /// Acceleration curve for exiting elements
  static const Curve curveAccelerate = Curves.easeIn;

  /// Bouncy curve for playful interactions
  static const Curve curveBounce = Curves.elasticOut;

  /// Sharp curve for snappy feedback
  static const Curve curveSharp = Curves.easeOutCubic;

  // ===========================================================================
  // Icon Sizes
  // ===========================================================================

  /// 14px - Inline icons
  static const double iconXs = 14.0;

  /// 16px - Small icons
  static const double iconSm = 16.0;

  /// 20px - Default icons
  static const double iconMd = 20.0;

  /// 24px - Large icons
  static const double iconLg = 24.0;

  /// 32px - Extra large icons
  static const double iconXl = 32.0;

  /// 48px - Hero icons
  static const double icon2xl = 48.0;

  // ===========================================================================
  // Responsive Breakpoints
  // ===========================================================================

  /// Mobile: 0 - 480px
  static const double breakpointMobile = 480.0;

  /// Tablet: 480 - 768px
  static const double breakpointTablet = 768.0;

  /// Small desktop: 768 - 1024px
  static const double breakpointDesktop = 1024.0;

  /// Large desktop: 1024 - 1440px
  static const double breakpointDesktopLg = 1440.0;

  /// Ultra-wide: 1440px+
  static const double breakpointUltraWide = 1920.0;

  // ===========================================================================
  // Component Sizes
  // ===========================================================================

  /// Standard button height
  static const double buttonHeight = 40.0;

  /// Small button height
  static const double buttonHeightSm = 32.0;

  /// Large button height
  static const double buttonHeightLg = 48.0;

  /// Standard input height
  static const double inputHeight = 40.0;

  /// Navigation sidebar width (collapsed)
  static const double sidebarCollapsed = 72.0;

  /// Navigation sidebar width (expanded)
  static const double sidebarExpanded = 220.0;

  /// Standard app bar height
  static const double appBarHeight = 56.0;

  // ===========================================================================
  // Shadows
  // ===========================================================================

  /// Subtle shadow for cards
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  /// Medium shadow for elevated cards
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  /// Large shadow for dialogs/modals
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];

  /// Glow shadow for highlighted elements
  static List<BoxShadow> shadowGlow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.3),
      blurRadius: 12,
      spreadRadius: 2,
    ),
  ];

  // ===========================================================================
  // Opacity Levels
  // ===========================================================================

  /// Disabled state opacity
  static const double opacityDisabled = 0.38;

  /// Muted/secondary content opacity
  static const double opacityMuted = 0.6;

  /// Subtle background overlay
  static const double opacitySubtle = 0.1;

  /// Medium overlay (hover states)
  static const double opacityMedium = 0.2;

  /// Strong overlay (pressed states)
  static const double opacityStrong = 0.3;
}
