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

  // Corner radii are deliberately tighter than the common 8/12/16 "soft card"
  // defaults. Crisper corners read as a precision instrument rather than a
  // generic rounded web dashboard, while staying clearly non-boxy. The scale
  // keeps real hierarchy (near-square chips → moderate panels → softer dialogs)
  // instead of rounding everything to the same radius.

  /// 3px - Small radius (pills, badges, chips)
  static const double radiusXs = 3.0;

  /// 5px - Small-medium radius (buttons, tooltips)
  static const double radiusSm = 5.0;

  /// 6px - Default radius (inputs, small cards)
  static const double radiusMd = 6.0;

  /// 7px - Filled accent buttons
  static const double radiusButton = 7.0;

  /// 10px - Large radius (cards, panels)
  static const double radiusLg = 10.0;

  /// 13px - Extra large radius (dialogs, large panels)
  static const double radiusXl = 13.0;

  /// Fully rounded (for circular elements)
  static const double radiusFull = 999.0;

  // ---------------------------------------------------------------------------
  // In-use migration radii (value-preserving; pending scale consolidation)
  // ---------------------------------------------------------------------------
  //
  // The named scale above (3/5/6/7/10/13) is the GO-FORWARD design intent, but
  // the screen layer still carries ~1150 hardcoded `BorderRadius.circular(n)`
  // literals at values that don't land on that scale. These constants give
  // every in-use literal an EXACT-valued named token so the per-directory
  // screen migration can replace `BorderRadius.circular(8)` with
  // `BorderRadius.circular(NightshadeTokens.radiusInline8)` with ZERO visual
  // change. They are intentionally value-named (not semantic-named) because
  // their only job is to make a mechanical, look-preserving migration possible;
  // once the screens are migrated, a follow-up design pass can re-map these to
  // the semantic scale (e.g. radiusInline8 → radiusLg) where the design agrees.
  //
  // Do NOT add new call sites at these values in fresh code — reach for the
  // semantic scale (radiusXs..radiusXl) instead. Full literal→token mapping
  // table: docs/design/token-migration-map.md.

  /// 2px - in-use literal (radius 2; 29 sites). Pending scale consolidation.
  static const double radiusInline2 = 2.0;

  /// 4px - in-use literal (radius 4; 215 sites). Pending scale consolidation.
  static const double radiusInline4 = 4.0;

  /// 8px - in-use literal (radius 8; 523 sites — the single most common).
  /// Pending scale consolidation (design intent maps toward [radiusLg]).
  static const double radiusInline8 = 8.0;

  /// 9px - in-use literal (radius 9; 1 site). Pending scale consolidation.
  static const double radiusInline9 = 9.0;

  /// 11px - in-use literal (radius 11; 1 site). Pending scale consolidation.
  static const double radiusInline11 = 11.0;

  // Convenience BorderRadius objects
  static final BorderRadius borderRadiusXs = BorderRadius.circular(radiusXs);
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusButton =
      BorderRadius.circular(radiusButton);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // Convenience BorderRadius objects for the in-use migration radii above.
  static final BorderRadius borderRadiusInline2 =
      BorderRadius.circular(radiusInline2);
  static final BorderRadius borderRadiusInline4 =
      BorderRadius.circular(radiusInline4);
  static final BorderRadius borderRadiusInline8 =
      BorderRadius.circular(radiusInline8);
  static final BorderRadius borderRadiusInline9 =
      BorderRadius.circular(radiusInline9);
  static final BorderRadius borderRadiusInline11 =
      BorderRadius.circular(radiusInline11);

  // ===========================================================================
  // Animation Durations
  // ===========================================================================

  /// 100ms - Micro interactions (hover color changes)
  static const Duration durationMicro = Duration(milliseconds: 100);

  /// 100ms - Instant feedback (hover, active states) - alias for durationMicro
  static const Duration durationFast = Duration(milliseconds: 100);

  /// 150ms - Quick transitions (button presses)
  static const Duration durationQuick = Duration(milliseconds: 150);

  /// 200ms - Normal transitions (card hovers, toggles)
  static const Duration durationNormal = Duration(milliseconds: 200);

  /// 300ms - Smooth transitions (page transitions, expanding panels)
  static const Duration durationSmooth = Duration(milliseconds: 300);

  /// 300ms - Slow transitions - alias for durationSmooth
  static const Duration durationSlow = Duration(milliseconds: 300);

  /// 400ms - Cinematic transitions (modal appearances)
  static const Duration durationCinematic = Duration(milliseconds: 400);

  /// 500ms - Very slow transitions (complex animations)
  static const Duration durationSluggish = Duration(milliseconds: 500);

  /// 1500ms - Shimmer/loading animation cycle
  static const Duration durationShimmer = Duration(milliseconds: 1500);

  /// 2000ms - Pulse animation cycle (status indicators)
  static const Duration durationPulse = Duration(milliseconds: 2000);

  // ===========================================================================
  // Animation Curves
  // ===========================================================================

  /// Standard easing curve for most animations
  static const Curve curveStandard = Curves.easeInOut;

  /// Deceleration curve for entering elements
  static const Curve curveDecelerate = Curves.easeOut;

  /// Acceleration curve for exiting elements
  static const Curve curveAccelerate = Curves.easeIn;

  /// Bouncy curve for playful interactions (use sparingly)
  static const Curve curveBounce = Curves.elasticOut;

  /// Sharp curve for snappy feedback
  static const Curve curveSharp = Curves.easeOutCubic;

  /// Snappy curve for responsive UI feedback (buttons, hovers)
  static const Curve curveSnappy = Curves.easeOutCubic;

  /// Precise curve for state transitions
  static const Curve curvePrecise = Curves.easeInOutCubic;

  /// Settle curve with slight overshoot for toggles/switches
  static const Curve curveSettle = Curves.easeOutBack;

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

  /// In-screen Material [AppBar] height (56px).
  ///
  /// Frameless desktop window chrome uses 40px (`ShellChromeMetrics.titleBarHeight`)
  /// instead — do not substitute this value for the custom title bar.
  static const double appBarHeight = 56.0;

  /// Minimum touch target (iOS HIG / Material accessibility).
  static const double minTouchTarget = 44.0;

  // ===========================================================================
  // Shadows & Elevation
  // ===========================================================================
  //
  // Cards use borders for separation — not box shadows.
  // Shadows are reserved for floating overlays (menus, toasts, modals, drag
  // feedback) where tonal lift is needed above the base surface.

  /// Subtle shadow for floating menus and toasts
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Medium shadow for dropdowns and popovers
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];

  /// Large shadow for dialogs/modals
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  // ===========================================================================
  // Elevation System (Dark Theme Optimized)
  // ===========================================================================

  /// Level 1 - Reserved for tonal separation; cards rely on borders instead.
  static const List<BoxShadow> elevationLevel1 = [];

  /// Level 2 - Light hover emphasis on interactive panels and drag feedback
  static const List<BoxShadow> elevationLevel2 = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 5,
      offset: Offset(0, 2),
    ),
  ];

  /// Level 3 - Floating elevation for modals and dialogs only
  static List<BoxShadow> elevationLevel3(Color accentColor) => shadowLg;

  /// Inset shadow for recessed elements (input fields, wells)
  /// Creates depth by appearing pressed into the surface
  static const List<BoxShadow> elevationInset = [
    BoxShadow(
      color: Color(0x66000000), // 40% opacity
      blurRadius: 4,
      offset: Offset(0, 2),
      blurStyle: BlurStyle.inner,
    ),
  ];

  /// Transition shadow from level 1 to level 2 (for hover animations)
  static const List<BoxShadow> elevationLevel1to2 = elevationLevel2;

  // ===========================================================================
  // Opacity Levels
  // ===========================================================================

  /// Disabled state opacity
  static const double opacityDisabled = 0.38;

  /// Muted/secondary content opacity
  static const double opacityMuted = 0.6;

  /// Subtle background overlay
  static const double opacitySubtle = 0.1;

  /// Status chip and KPI badge fill
  static const double opacityStatusFill = 0.15;

  /// Medium overlay (hover states)
  static const double opacityMedium = 0.2;

  /// Strong overlay (pressed states)
  static const double opacityStrong = 0.3;

  /// Very light primary/accent tint for selected surfaces (4%)
  static const double opacityTint = 0.04;

  /// Icon chip and medium-strength accent borders (25%)
  static const double opacityBorderMedium = 0.25;

  /// Selected nav/card accent border emphasis (45%)
  static const double opacityEmphasisBorder = 0.45;

  /// Half-opacity for disabled filled buttons (50%)
  static const double opacityHalf = 0.5;

  /// Hover border emphasis on interactive cards (85%)
  static const double opacityHoverBorder = 0.85;

  /// KPI/score badge border strength (40%)
  static const double opacityBadgeBorder = 0.4;

  /// Lighten amount for filled button hover state
  static const double buttonHoverLighten = 0.04;

  /// Darken amount for filled button border
  static const double buttonBorderDarken = 0.12;

  // ===========================================================================
  // Panel Row Layout (imaging side panel)
  // ===========================================================================

  /// Internal padding for grouped panel sections in the imaging side panel.
  static const double panelSectionPadding = 14.0;

  /// Flex weight for label column in label/control row pairs.
  static const int panelRowLabelFlex = 2;

  /// Flex weight for control column in label/control row pairs.
  static const int panelRowControlFlex = 3;

  /// Font size for panel section titles and row labels.
  static const double fontSizePanelLabel = 12.0;

  /// Font size for compact panel captions and section headers.
  static const double fontSizePanelCaption = 10.0;
}
