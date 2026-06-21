import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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

  /// The consolidated top-level features in side-nav order (matches desktop):
  /// Dashboard, Equipment, Imaging, Sequencer, Guiding, Weather, Planner,
  /// Analytics. The rail leads with the tools an imager touches every night;
  /// less-frequent surfaces are nested rather than given a rail slot. Folded
  /// destinations resolve via redirects: Framing/Planetarium and Your
  /// Sky/Constellation live inside Plan Tonight's tabs, Science + Transients
  /// inside Analytics, and Settings is reached from the title-bar / app-bar gear.
  static const List<ShellPrimaryDestination> primaryDestinations = [
    ShellPrimaryDestination(
      route: '/dashboard',
      icon: LucideIcons.layoutDashboard,
      label: _navDashboard,
      description: _navDashboardDesc,
    ),
    ShellPrimaryDestination(
      route: '/equipment',
      icon: NightshadeIcons.connected,
      label: _navEquipment,
      description: _navEquipmentDesc,
    ),
    ShellPrimaryDestination(
      route: '/imaging',
      icon: NightshadeIcons.camera,
      label: _navImaging,
      description: _navImagingDesc,
    ),
    ShellPrimaryDestination(
      route: '/sequencer',
      icon: NightshadeIcons.listOrdered,
      label: _navSequencer,
      description: _navSequencerDesc,
    ),
    ShellPrimaryDestination(
      route: '/guiding',
      icon: NightshadeIcons.guider,
      label: _navGuiding,
      description: _navGuidingDesc,
    ),
    ShellPrimaryDestination(
      route: '/weather',
      icon: NightshadeIcons.weather,
      label: _navWeather,
      description: _navWeatherDesc,
    ),
    ShellPrimaryDestination(
      route: '/planner',
      icon: LucideIcons.moonStar,
      label: _navPlanner,
      description: _navPlannerDesc,
    ),
    ShellPrimaryDestination(
      route: '/analytics',
      icon: LucideIcons.barChart3,
      label: _navAnalytics,
      description: _navAnalyticsDesc,
    ),
  ];

  static const ShellPrimaryDestination settings = ShellPrimaryDestination(
    route: '/settings',
    icon: NightshadeIcons.settings,
    label: _settingsTitle,
    description: _settingsDesc,
  );

  /// Mobile bottom-nav slots — exactly the six core routes, fixed width.
  ///
  /// Dashboard leads for thumb reach; Settings leaves the bar and is reachable
  /// from the mobile app-bar gear.
  static const List<ShellRouteDestination> bottomNavigationDestinations = [
    ShellRouteDestination(
      route: '/dashboard',
      icon: LucideIcons.layoutDashboard,
      label: _navDashboard,
    ),
    ShellRouteDestination(
      route: '/equipment',
      icon: NightshadeIcons.connected,
      label: _navEquipment,
    ),
    ShellRouteDestination(
      route: '/imaging',
      icon: NightshadeIcons.camera,
      label: _navImaging,
    ),
    ShellRouteDestination(
      route: '/sequencer',
      icon: NightshadeIcons.listOrdered,
      label: _navSequencer,
    ),
    ShellRouteDestination(
      route: '/guiding',
      icon: NightshadeIcons.guider,
      label: _navGuiding,
    ),
    ShellRouteDestination(
      route: '/planner',
      icon: LucideIcons.moonStar,
      label: _navPlanner,
    ),
  ];

  /// Primary destinations that do NOT have a fixed bottom-nav slot on phone, in
  /// side-nav order. Surfaced through the bottom bar's "More" overflow so every
  /// top-level feature (notably Your Sky + Constellation) is reachable on mobile,
  /// not just the six core slots + Settings gear.
  static List<ShellPrimaryDestination> get overflowDestinations {
    final bottomRoutes =
        bottomNavigationDestinations.map((d) => d.route).toSet();
    return [
      for (final dest in primaryDestinations)
        if (!bottomRoutes.contains(dest.route) && dest.route != settings.route)
          dest,
    ];
  }

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
  static String _navSequencer(NightshadeLocalizations l10n) =>
      l10n.text('navSequencer');
  static String _navSequencerDesc(NightshadeLocalizations l10n) =>
      l10n.text('navSequencerDesc');
  static String _navAnalytics(NightshadeLocalizations l10n) =>
      l10n.text('navAnalytics');
  static String _navAnalyticsDesc(NightshadeLocalizations l10n) =>
      l10n.text('navAnalyticsDesc');
  static String _navGuiding(NightshadeLocalizations l10n) =>
      l10n.text('navGuiding');
  static String _navGuidingDesc(NightshadeLocalizations l10n) =>
      l10n.text('navGuidingDesc');
  static String _navWeather(NightshadeLocalizations l10n) =>
      l10n.text('navWeather');
  static String _navWeatherDesc(NightshadeLocalizations l10n) =>
      l10n.text('navWeatherDesc');
  static String _navPlanner(NightshadeLocalizations l10n) =>
      l10n.text('navPlanner');
  static String _navPlannerDesc(NightshadeLocalizations l10n) =>
      l10n.text('navPlannerDesc');
  static String _settingsTitle(NightshadeLocalizations l10n) =>
      l10n.text('settingsTitle');
  static String _settingsDesc(NightshadeLocalizations l10n) =>
      l10n.text('settingsDesc');
}
