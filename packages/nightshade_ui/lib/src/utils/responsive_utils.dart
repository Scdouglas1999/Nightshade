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
}
