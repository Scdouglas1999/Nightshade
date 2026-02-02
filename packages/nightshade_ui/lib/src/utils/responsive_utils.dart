import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../theme/nightshade_tokens.dart';

/// Responsive breakpoint utilities for adaptive UI layouts.
///
/// Usage:
/// ```dart
/// if (Responsive.isMobile(context)) {
///   // Mobile layout
/// }
///
/// final padding = Responsive.value(
///   context,
///   mobile: 8.0,
///   tablet: 16.0,
///   desktop: 24.0,
/// );
/// ```
abstract final class Responsive {
  Responsive._();

  /// Returns true if the screen width is less than the tablet breakpoint (768px).
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < NightshadeTokens.breakpointTablet;

  /// Returns true if the screen width is between tablet (768px) and desktop (1024px) breakpoints.
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= NightshadeTokens.breakpointTablet &&
        width < NightshadeTokens.breakpointDesktop;
  }

  /// Returns true if the screen width is at least the desktop breakpoint (1024px).
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= NightshadeTokens.breakpointDesktop;

  /// Returns true if the screen width is at least the large desktop breakpoint (1440px).
  static bool isDesktopLarge(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= NightshadeTokens.breakpointDesktopLg;

  /// Returns true if the screen width is at least the ultra-wide breakpoint (1920px).
  static bool isUltraWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= NightshadeTokens.breakpointUltraWide;

  /// Returns a value based on screen size breakpoints.
  ///
  /// If [tablet] is not specified, falls back to [desktop].
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? desktop;
    return desktop;
  }

  /// Returns a value with additional breakpoints for large screens.
  static T valueExtended<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
    T? desktopLarge,
    T? ultraWide,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? desktop;
    if (isDesktopLarge(context)) {
      if (isUltraWide(context)) return ultraWide ?? desktopLarge ?? desktop;
      return desktopLarge ?? desktop;
    }
    return desktop;
  }

  /// Calculates responsive dialog constraints that fit within the viewport.
  ///
  /// [maxWidthPercent] - Maximum width as percentage of screen width (0.0 to 1.0)
  /// [maxHeightPercent] - Maximum height as percentage of screen height (0.0 to 1.0)
  /// [preferredWidth] - Preferred width in logical pixels, capped by maxWidthPercent
  /// [preferredHeight] - Preferred height in logical pixels, capped by maxHeightPercent
  /// [minWidth] - Minimum width in logical pixels
  /// [minHeight] - Minimum height in logical pixels
  ///
  /// Example:
  /// ```dart
  /// ConstrainedBox(
  ///   constraints: Responsive.dialogConstraints(
  ///     context,
  ///     preferredWidth: 900,
  ///     preferredHeight: 700,
  ///   ),
  ///   child: MyDialogContent(),
  /// )
  /// ```
  static BoxConstraints dialogConstraints(
    BuildContext context, {
    double maxWidthPercent = 0.9,
    double maxHeightPercent = 0.85,
    double? preferredWidth,
    double? preferredHeight,
    double? minWidth,
    double? minHeight,
  }) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width * maxWidthPercent;
    final maxH = size.height * maxHeightPercent;

    return BoxConstraints(
      minWidth: minWidth ?? 0.0,
      minHeight: minHeight ?? 0.0,
      maxWidth: preferredWidth != null ? math.min(preferredWidth, maxW) : maxW,
      maxHeight:
          preferredHeight != null ? math.min(preferredHeight, maxH) : maxH,
    );
  }

  /// Returns adaptive padding based on screen size.
  ///
  /// Mobile: compact padding
  /// Tablet: medium padding
  /// Desktop: standard padding
  static EdgeInsets adaptivePadding(BuildContext context) {
    return value(
      context,
      mobile: NightshadeTokens.screenPaddingCompact,
      tablet: NightshadeTokens.screenPadding,
      desktop: NightshadeTokens.screenPadding,
    );
  }

  /// Calculates responsive panel width based on screen size.
  ///
  /// [initialPercent] - Initial width as percentage of screen width
  /// [minPercent] - Minimum width as percentage of screen width
  /// [maxPercent] - Maximum width as percentage of screen width
  /// [absoluteMin] - Absolute minimum width in logical pixels
  /// [absoluteMax] - Absolute maximum width in logical pixels
  static ({double initial, double min, double max}) panelDimensions(
    BuildContext context, {
    double initialPercent = 0.25,
    double minPercent = 0.15,
    double maxPercent = 0.4,
    double absoluteMin = 200.0,
    double absoluteMax = 500.0,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return (
      initial: (screenWidth * initialPercent).clamp(absoluteMin, absoluteMax),
      min: (screenWidth * minPercent).clamp(absoluteMin * 0.8, absoluteMin),
      max: (screenWidth * maxPercent).clamp(absoluteMax * 0.7, absoluteMax),
    );
  }

  /// Returns the current breakpoint name for debugging.
  static String breakpointName(BuildContext context) {
    if (isMobile(context)) return 'mobile';
    if (isTablet(context)) return 'tablet';
    if (isDesktopLarge(context)) {
      if (isUltraWide(context)) return 'ultraWide';
      return 'desktopLarge';
    }
    return 'desktop';
  }

  // ===========================================================================
  // Universal Scaling
  // ===========================================================================

  /// Calculate a universal scale factor based on screen dimensions.
  ///
  /// This provides a 0.85-1.25 range scale factor based on the screen's
  /// minimum dimension relative to a reference size of 900px.
  ///
  /// - Smaller screens (< 900px min dimension): scale 0.85-1.0
  /// - Standard screens (900-1200px): scale 1.0
  /// - Large screens (> 1200px): scale 1.0-1.25
  static double scaleFactor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final minDimension = math.min(size.width, size.height);
    
    // Reference: 900px min dimension = 1.0 scale
    if (minDimension < 900) {
      // Scale down linearly from 1.0 to 0.85 as screen shrinks
      return 0.85 + (minDimension / 900) * 0.15;
    } else if (minDimension > 1200) {
      // Scale up linearly from 1.0 to 1.25 as screen grows
      final excess = (minDimension - 1200).clamp(0.0, 600.0);
      return 1.0 + (excess / 600) * 0.25;
    }
    return 1.0;
  }

  /// Returns a spacing value scaled to screen size.
  ///
  /// Use this for padding, margins, and gaps that should adapt to screen size.
  /// ```dart
  /// padding: EdgeInsets.all(Responsive.spacing(context, 16)),
  /// ```
  static double spacing(BuildContext context, double baseValue) {
    return baseValue * scaleFactor(context);
  }

  /// Returns a font size scaled to screen size.
  ///
  /// ```dart
  /// Text('Hello', style: TextStyle(fontSize: Responsive.fontSize(context, 14))),
  /// ```
  static double fontSize(BuildContext context, double baseSize) {
    // Font scaling is more conservative than spacing
    final scale = scaleFactor(context);
    // Keep font scaling in 0.9-1.15 range for readability
    final fontScale = 0.9 + (scale - 0.85) * (0.25 / 0.4);
    return baseSize * fontScale.clamp(0.9, 1.15);
  }

  /// Returns icon size scaled to screen size.
  ///
  /// ```dart
  /// Icon(Icons.home, size: Responsive.iconSize(context, 24)),
  /// ```
  static double iconSize(BuildContext context, double baseSize) {
    return baseSize * scaleFactor(context);
  }

  /// Returns scaled EdgeInsets for consistent responsive padding.
  ///
  /// ```dart
  /// Padding(padding: Responsive.edgeInsets(context, all: 16)),
  /// ```
  static EdgeInsets edgeInsets(
    BuildContext context, {
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final scale = scaleFactor(context);
    
    if (all != null) {
      return EdgeInsets.all(all * scale);
    }
    
    return EdgeInsets.only(
      left: (left ?? horizontal ?? 0) * scale,
      top: (top ?? vertical ?? 0) * scale,
      right: (right ?? horizontal ?? 0) * scale,
      bottom: (bottom ?? vertical ?? 0) * scale,
    );
  }

  // ===========================================================================
  // Aspect Ratio Detection
  // ===========================================================================

  /// Returns true if the screen is in portrait orientation.
  static bool isPortrait(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width;
  }

  /// Returns true if the screen is in landscape orientation.
  static bool isLandscape(BuildContext context) => !isPortrait(context);

  /// Returns true if the screen is ultrawide (aspect ratio > 2.0).
  ///
  /// Ultrawide screens (21:9, 32:9) need special layout considerations.
  static bool isUltraWideAspect(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width / size.height > 2.0;
  }

  /// Returns true if the screen is approximately square (aspect ratio 0.8-1.25).
  static bool isSquareAspect(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ratio = size.width / size.height;
    return ratio >= 0.8 && ratio <= 1.25;
  }

  /// Returns the aspect ratio of the screen (width / height).
  static double aspectRatio(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width / size.height;
  }

  /// Returns a value based on aspect ratio category.
  ///
  /// ```dart
  /// final columns = Responsive.aspectValue(
  ///   context,
  ///   portrait: 1,
  ///   square: 2,
  ///   landscape: 3,
  ///   ultrawide: 4,
  /// );
  /// ```
  static T aspectValue<T>(
    BuildContext context, {
    required T portrait,
    T? square,
    required T landscape,
    T? ultrawide,
  }) {
    if (isPortrait(context)) return portrait;
    if (isSquareAspect(context)) return square ?? landscape;
    if (isUltraWideAspect(context)) return ultrawide ?? landscape;
    return landscape;
  }

  // ===========================================================================
  // Layout Helpers
  // ===========================================================================

  /// Returns the number of columns for a grid based on screen width.
  ///
  /// [minItemWidth] - Minimum width for each item in logical pixels.
  /// [maxColumns] - Maximum number of columns allowed.
  static int gridColumns(
    BuildContext context, {
    double minItemWidth = 300,
    int maxColumns = 6,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / minItemWidth).floor();
    return columns.clamp(1, maxColumns);
  }

  /// Returns the optimal panel width for slide-out panels based on screen size.
  static double panelWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (isMobile(context)) return width; // Full width on mobile
    if (isTablet(context)) return math.min(400, width * 0.6);
    if (isUltraWideAspect(context)) return math.min(500, width * 0.25);
    return math.min(450, width * 0.35);
  }
}
