import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../localization/nightshade_localizations.dart';

/// One primary shell destination (side nav + indexed tab selection).
class ShellPrimaryDestination {
  final String route;
  final IconData icon;
  final String Function(NightshadeLocalizations l10n) label;
  final String Function(NightshadeLocalizations l10n) description;

  const ShellPrimaryDestination({
    required this.route,
    required this.icon,
    required this.label,
    required this.description,
  });
}

/// Route-only destination for mobile bottom nav (no side-nav index).
class ShellRouteDestination {
  final String route;
  final IconData icon;
  final String Function(NightshadeLocalizations l10n) label;

  const ShellRouteDestination({
    required this.route,
    required this.icon,
    required this.label,
  });
}

/// Canonical shell routes shared by side nav, bottom nav, and GoRouter helpers.
abstract final class ShellNavigation {
  ShellNavigation._();

  /// Eleven primary features in side-nav order (matches desktop).
  static const List<ShellPrimaryDestination> primaryDestinations = [
    ShellPrimaryDestination(
      route: '/dashboard',
      icon: LucideIcons.layoutDashboard,
      label: _navDashboard,
      description: _navDashboardDesc,
    ),
    ShellPrimaryDestination(
      route: '/equipment',
      icon: LucideIcons.plug,
      label: _navEquipment,
      description: _navEquipmentDesc,
    ),
    ShellPrimaryDestination(
      route: '/imaging',
      icon: LucideIcons.camera,
      label: _navImaging,
      description: _navImagingDesc,
    ),
    ShellPrimaryDestination(
      route: '/guiding',
      icon: LucideIcons.crosshair,
      label: _navGuiding,
      description: _navGuidingDesc,
    ),
    ShellPrimaryDestination(
      route: '/sequencer',
      icon: LucideIcons.listOrdered,
      label: _navSequencer,
      description: _navSequencerDesc,
    ),
    ShellPrimaryDestination(
      route: '/planetarium',
      icon: LucideIcons.globe,
      label: _navPlanetarium,
      description: _navPlanetariumDesc,
    ),
    ShellPrimaryDestination(
      route: '/framing',
      icon: LucideIcons.frame,
      label: _navFraming,
      description: _navFramingDesc,
    ),
    ShellPrimaryDestination(
      route: '/analytics',
      icon: LucideIcons.barChart3,
      label: _navAnalytics,
      description: _navAnalyticsDesc,
    ),
    ShellPrimaryDestination(
      route: '/flat-wizard',
      icon: LucideIcons.sun,
      label: _navFlatWizard,
      description: _navFlatWizardDesc,
    ),
    ShellPrimaryDestination(
      route: '/weather',
      icon: LucideIcons.cloudRain,
      label: _navWeather,
      description: _navWeatherDesc,
    ),
    ShellPrimaryDestination(
      route: '/planner',
      icon: LucideIcons.moonStar,
      label: _navPlanner,
      description: _navPlannerDesc,
    ),
  ];

  /// Desktop title-bar routes (not in side nav).
  static const ShellRouteDestination transients = ShellRouteDestination(
    route: '/transients',
    icon: LucideIcons.sparkles,
    label: _navTransients,
  );

  static const ShellRouteDestination settings = ShellRouteDestination(
    route: '/settings',
    icon: LucideIcons.settings,
    label: _settingsTitle,
  );

  /// Thirteen mobile bottom-nav slots: 11 primary + transients + settings.
  ///
  /// Order keeps dashboard centered for thumb reach; matches desktop feature
  /// access (transients/settings live in the title bar on desktop).
  static const List<ShellRouteDestination> bottomNavigationDestinations = [
    ShellRouteDestination(
      route: '/equipment',
      icon: LucideIcons.plug,
      label: _navEquipment,
    ),
    ShellRouteDestination(
      route: '/imaging',
      icon: LucideIcons.camera,
      label: _navImaging,
    ),
    ShellRouteDestination(
      route: '/sequencer',
      icon: LucideIcons.listOrdered,
      label: _navSequencer,
    ),
    ShellRouteDestination(
      route: '/planetarium',
      icon: LucideIcons.globe,
      label: _navPlanetarium,
    ),
    ShellRouteDestination(
      route: '/dashboard',
      icon: LucideIcons.layoutDashboard,
      label: _navDashboard,
    ),
    ShellRouteDestination(
      route: '/guiding',
      icon: LucideIcons.crosshair,
      label: _navGuiding,
    ),
    ShellRouteDestination(
      route: '/framing',
      icon: LucideIcons.frame,
      label: _navFraming,
    ),
    ShellRouteDestination(
      route: '/analytics',
      icon: LucideIcons.barChart3,
      label: _navAnalytics,
    ),
    ShellRouteDestination(
      route: '/flat-wizard',
      icon: LucideIcons.sun,
      label: _navFlatWizard,
    ),
    ShellRouteDestination(
      route: '/weather',
      icon: LucideIcons.cloudRain,
      label: _navWeather,
    ),
    ShellRouteDestination(
      route: '/planner',
      icon: LucideIcons.moonStar,
      label: _navPlanner,
    ),
    transients,
    settings,
  ];

  static final List<String> primaryRoutes =
      primaryDestinations.map((d) => d.route).toList(growable: false);

  static int primaryIndexForLocation(String location) {
    final path = _normalizePath(location);
    final idx = primaryRoutes.indexOf(path);
    return idx;
  }

  static String? primaryRouteForIndex(int index) {
    if (index < 0 || index >= primaryRoutes.length) return null;
    return primaryRoutes[index];
  }

  static bool isBottomNavRoute(String location) {
    final path = _normalizePath(location);
    if (path == transients.route || path == settings.route) return true;
    return primaryRoutes.contains(path);
  }

  static String _normalizePath(String location) {
    final uri = Uri.tryParse(location);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    return location.split('?').first;
  }

  static String _navDashboard(NightshadeLocalizations l10n) =>
      l10n.text('navDashboard');
  static String _navDashboardDesc(NightshadeLocalizations l10n) =>
      l10n.text('navDashboardDesc');
  static String _navEquipment(NightshadeLocalizations l10n) =>
      l10n.text('navEquipment');
  static String _navEquipmentDesc(NightshadeLocalizations l10n) =>
      l10n.text('navEquipmentDesc');
  static String _navImaging(NightshadeLocalizations l10n) =>
      l10n.text('navImaging');
  static String _navImagingDesc(NightshadeLocalizations l10n) =>
      l10n.text('navImagingDesc');
  static String _navGuiding(NightshadeLocalizations l10n) =>
      l10n.text('navGuiding');
  static String _navGuidingDesc(NightshadeLocalizations l10n) =>
      l10n.text('navGuidingDesc');
  static String _navSequencer(NightshadeLocalizations l10n) =>
      l10n.text('navSequencer');
  static String _navSequencerDesc(NightshadeLocalizations l10n) =>
      l10n.text('navSequencerDesc');
  static String _navPlanetarium(NightshadeLocalizations l10n) =>
      l10n.text('navPlanetarium');
  static String _navPlanetariumDesc(NightshadeLocalizations l10n) =>
      l10n.text('navPlanetariumDesc');
  static String _navFraming(NightshadeLocalizations l10n) =>
      l10n.text('navFraming');
  static String _navFramingDesc(NightshadeLocalizations l10n) =>
      l10n.text('navFramingDesc');
  static String _navAnalytics(NightshadeLocalizations l10n) =>
      l10n.text('navAnalytics');
  static String _navAnalyticsDesc(NightshadeLocalizations l10n) =>
      l10n.text('navAnalyticsDesc');
  static String _navFlatWizard(NightshadeLocalizations l10n) =>
      l10n.text('navFlatWizard');
  static String _navFlatWizardDesc(NightshadeLocalizations l10n) =>
      l10n.text('navFlatWizardDesc');
  static String _navWeather(NightshadeLocalizations l10n) =>
      l10n.text('navWeather');
  static String _navWeatherDesc(NightshadeLocalizations l10n) =>
      l10n.text('navWeatherDesc');
  static String _navPlanner(NightshadeLocalizations l10n) =>
      l10n.text('navPlanner');
  static String _navPlannerDesc(NightshadeLocalizations l10n) =>
      l10n.text('navPlannerDesc');
  static String _navTransients(NightshadeLocalizations l10n) =>
      l10n.text('navTransients');
  static String _settingsTitle(NightshadeLocalizations l10n) =>
      l10n.text('settingsTitle');
}
