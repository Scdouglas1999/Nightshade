import 'package:flutter/widgets.dart';

import '../theme/nightshade_tokens.dart';
import '../utils/responsive_utils.dart';

/// Layout metrics for app shell chrome (title bar, status bar, bottom nav).
///
/// Desktop uses a compact custom title bar ([titleBarHeight]) distinct from
/// in-screen [NightshadeTokens.appBarHeight] headers.
abstract final class ShellChromeMetrics {
  ShellChromeMetrics._();

  /// Width at which desktop shell switches side nav ↔ bottom nav.
  static const double shellLayoutBreakpoint = NightshadeTokens.breakpointTablet;

  /// Custom window title bar height (desktop shell).
  static const double titleBarHeight = 40.0;

  /// Windows-style caption button width.
  static const double windowControlWidth = 46.0;

  /// Caption button height; matches [titleBarHeight].
  static const double windowControlHeight = titleBarHeight;

  /// Desktop status bar height (non-compact shell).
  static const double statusBarHeight = 36.0;

  /// Compact status bar height (bottom-nav / narrow shell).
  static const double statusBarHeightCompact = 40.0;

  /// Base max width for device-name text in status pills before ellipsis.
  static const double statusPillValueMaxWidth = 120.0;

  /// Preferred width for the remote-access share dialog content.
  static const double shareDialogPreferredWidth = 420.0;

  /// Status divider height inside the status bar.
  static const double statusBarDividerHeight = 20.0;

  /// Chrome below the main content [Stack]: status bar plus bottom nav when
  /// active. Excludes system safe-area padding.
  static double contentStackBottomChromeHeight({required bool useBottomNav}) {
    final statusBar = useBottomNav ? statusBarHeightCompact : statusBarHeight;
    final bottomNav = useBottomNav ? BottomNavMetrics.barHeight : 0.0;
    return statusBar + bottomNav;
  }

  /// Minimum bottom offset for floating overlays in the content stack
  /// (autofocus progress, mobile sequence controls, etc.).
  static double floatingOverlayBottomInset(
    BuildContext context, {
    required bool useBottomNav,
    double margin = 16.0,
  }) {
    return MediaQuery.paddingOf(context).bottom +
        contentStackBottomChromeHeight(useBottomNav: useBottomNav) +
        margin;
  }

  /// Scales [statusPillValueMaxWidth] for viewport size with sane bounds.
  static double scaledStatusPillValueMaxWidth(BuildContext context) {
    final scaled = statusPillValueMaxWidth * Responsive.scaleFactor(context);
    return scaled.clamp(72.0, 180.0);
  }
}

/// Bottom navigation strip metrics used by [NightshadeBottomNavigation].
abstract final class BottomNavMetrics {
  BottomNavMetrics._();

  static const double barHeight = 78.0;
  static const double itemGap = 8.0;
  static const double listHorizontalPadding = 10.0;
  static const double listVerticalPadding = 8.0;

  static const double itemWidthMin = 84.0;
  static const double itemWidthMax = 116.0;

  static const double breakpointSlots8 = 960.0;
  static const double breakpointSlots7 = 780.0;
  static const double breakpointSlots6 = 640.0;
  static const double breakpointSlots5 = 520.0;

  /// Aspect ratio (width/height) above which fewer slots are shown.
  static const double narrowAspectRatioThreshold = 0.56;

  static const double visibleSlotsUltraWide = 8.0;
  static const double visibleSlotsWide = 7.0;
  static const double visibleSlotsMedium = 6.0;
  static const double visibleSlotsNarrow = 5.25;
  static const double visibleSlotsPortrait = 4.6;
  static const double visibleSlotsDefault = 4.15;

  static const Duration scrollAnimationDuration = Duration(milliseconds: 220);

  static const Duration itemSelectionAnimationDuration = Duration(
    milliseconds: 180,
  );

  static const EdgeInsets itemPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );

  static const double itemBorderRadius = 8.0;
  static const double itemIconSize = 18.0;
  static const double itemIconLabelGap = 6.0;
  static const double itemLabelFontSize = 10.0;

  /// Computes per-item width from viewport and screen size.
  static double itemWidth(Size screenSize, double viewportWidth) {
    final aspectRatio = screenSize.width / screenSize.height;
    final visibleSlots = switch (viewportWidth) {
      >= breakpointSlots8 => visibleSlotsUltraWide,
      >= breakpointSlots7 => visibleSlotsWide,
      >= breakpointSlots6 => visibleSlotsMedium,
      >= breakpointSlots5 => visibleSlotsNarrow,
      _ when aspectRatio > narrowAspectRatioThreshold => visibleSlotsPortrait,
      _ => visibleSlotsDefault,
    };

    const horizontalInset = listHorizontalPadding * 2;
    final computed = (viewportWidth - horizontalInset) / visibleSlots;
    return computed.clamp(itemWidthMin, itemWidthMax);
  }
}
