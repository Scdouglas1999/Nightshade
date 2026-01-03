import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/services/location_sync_service.dart';
import 'package:nightshade_app/widgets/session_recovery_checker.dart';
import 'package:nightshade_app/widgets/auto_discovery_launcher.dart';

class NightshadeApp extends ConsumerWidget {
  final bool isMobile;
  final bool isDesktop;

  const NightshadeApp({
    this.isMobile = false,
    this.isDesktop = false,
    super.key,
  });

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

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: AutoDiscoveryLauncher(
        child: SessionRecoveryChecker(
          child: MaterialApp.router(
            title: 'Nightshade',
            theme: _getThemeForSetting(themeSetting, accentColor),
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            builder: (context, child) {
              // Only add UpdateManager on desktop (not mobile - uses app stores)
              if (isDesktop) {
                return UpdateManagerWidget(child: child ?? const SizedBox.shrink());
              }
              return child ?? const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
