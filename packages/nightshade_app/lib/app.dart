import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/services/location_sync_service.dart';
import 'package:nightshade_app/widgets/quick_start_checker.dart';
import 'package:nightshade_app/widgets/auto_discovery_launcher.dart';

class NightshadeApp extends ConsumerWidget {
  final bool isMobile;
  final bool isDesktop;

  const NightshadeApp({
    this.isMobile = false,
    this.isDesktop = false,
    super.key,
  });

  /// Calculate UI scale factor for high-DPI displays
  ///
  /// On Linux and some other platforms, Flutter may not properly scale UI
  /// elements for high-DPI displays. This detects the device pixel ratio
  /// and applies additional scaling to make the UI readable.
  double _calculateUiScaleFactor(BuildContext context, String? uiScaleSetting) {
    // If user has explicitly set a scale, use it
    if (uiScaleSetting != null && uiScaleSetting != 'Auto') {
      switch (uiScaleSetting) {
        case 'Small (0.8x)':
          return 0.8;
        case 'Normal (1.0x)':
          return 1.0;
        case 'Large (1.2x)':
          return 1.2;
        case 'Extra Large (1.4x)':
          return 1.4;
      }
    }

    // Auto-detect scale for high-DPI displays
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    // On Linux with high-DPI displays, apply additional scaling
    // Linux Wayland/X11 doesn't always properly scale Flutter apps
    // High-DPI is typically > 1.5 device pixel ratio
    if (!kIsWeb && Platform.isLinux && devicePixelRatio > 1.5) {
      // For high DPI displays, apply more aggressive scaling
      // DPR 2.0 -> 1.25x scale, DPR 2.5 -> 1.5x scale, DPR 3.0 -> 1.75x scale
      final extraScale = 1.0 + (devicePixelRatio - 1.5) * 0.5;
      return extraScale.clamp(1.0, 1.75);
    }

    // For desktops with small windows, don't scale down
    // For mobile, let Flutter handle it naturally
    return 1.0;
  }

  /// Parse hex color string (e.g., '#6366F1' or '6366F1') to Color
  Color? _parseAccentColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    try {
      final hex = hexColor.replaceFirst('#', '');
      if (hex.length != 6) return null;
      return Color(int.parse('0xFF$hex'));
    } catch (e) {
      return null;
    }
  }

  /// Get text scale factor from font size setting
  double _getTextScaleFactor(String fontSize) {
    switch (fontSize) {
      case 'Small':
        return 0.85;
      case 'Large':
        return 1.15;
      case 'Medium':
      default:
        return 1.0;
    }
  }

  ThemeData _getThemeForSetting(String themeSetting, Color? accentColor) {
    // Red night theme always uses red - don't apply custom accent
    if (themeSetting == 'redNight') {
      return NightshadeTheme.redNight;
    }

    // If no custom accent, use default themes
    if (accentColor == null) {
      switch (themeSetting) {
        case 'light':
          return NightshadeTheme.light;
        case 'dark':
        default:
          return NightshadeTheme.dark;
      }
    }

    // Apply custom accent color
    switch (themeSetting) {
      case 'light':
        return NightshadeTheme.lightWithAccent(accentColor);
      case 'dark':
      default:
        return NightshadeTheme.darkWithAccent(accentColor);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Activate location sync to keep planetarium in sync with settings
    ref.watch(locationSyncProvider);

    // Get settings
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final themeSetting = settings?.theme ?? 'dark';
    final accentColor = _parseAccentColor(settings?.accentColor);
    final textScaleFactor = _getTextScaleFactor(settings?.fontSize ?? 'Medium');
    final uiScaleSetting = settings?.uiScale;

    return AutoDiscoveryLauncher(
      child: QuickStartChecker(
        child: MaterialApp.router(
          title: 'Nightshade',
          theme: _getThemeForSetting(themeSetting, accentColor),
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          builder: (context, child) {
            // Calculate UI scale factor INSIDE builder where we have proper MediaQuery
            // The outer context doesn't have accurate devicePixelRatio from the window
            final uiScaleFactor = _calculateUiScaleFactor(context, uiScaleSetting);
            final combinedTextScale = textScaleFactor * uiScaleFactor;

            // Apply text scaling for UI accessibility
            // Note: We only scale text, not the entire UI widget tree.
            // Flutter handles DPI scaling natively on most platforms.
            // The previous Transform.scale approach caused rendering artifacts.
            final appChild = child ?? const SizedBox.shrink();
            Widget scaledChild = appChild;

            if (uiScaleFactor != 1.0 || textScaleFactor != 1.0) {
              // Apply combined text scaling from both UI scale and font size settings
              scaledChild = MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(combinedTextScale),
                ),
                child: appChild,
              );
            }
            // Wrap with ScaledConfigProvider to make responsive scaling
            // configuration available to all descendant widgets
            Widget result = ScaledConfigProvider(child: scaledChild);

            // Only add UpdateManager on desktop (not mobile - uses app stores)
            if (isDesktop) {
              return UpdateManagerWidget(child: result);
            }
            return result;
          },
        ),
      ),
    );
  }
}
