import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nightshade_ui/nightshade_ui.dart';

/// Shell chrome (side nav vs bottom nav) decisions.
///
/// **Bottom nav** — iOS/Android builds always use bottom navigation so tablet
/// widths do not swap to the desktop side rail ([KEEP] mobile shell rule).
///
/// **Side nav** — Windows/macOS/Linux use the side rail at widths ≥
/// [ShellChromeMetrics.shellLayoutBreakpoint] (768px). Narrow desktop windows
/// keep bottom nav for space.
abstract final class ShellChrome {
  ShellChrome._();

  /// True on phone/tablet native targets (not web).
  static bool get isNativeMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Whether the shell should render [NightshadeBottomNavigation].
  static bool useBottomNavigation(double width) {
    if (isNativeMobile) return true;
    return width < ShellChromeMetrics.shellLayoutBreakpoint;
  }

  /// Whether the shell should render [SideNavigation].
  static bool useSideNavigation(double width) => !useBottomNavigation(width);
}
