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

  /// Optional short form for the ~60dp phone bottom-nav slots; `null` falls
  /// back to [label]. The full labels ("Planetarium", "Sequencer") all
  /// ellipsized at seven slots on a 430dp phone.
  final String Function(NightshadeLocalizations l10n)? shortLabel;

  /// The label the phone bottom nav renders.
  String bottomNavLabel(NightshadeLocalizations l10n) =>
      (shortLabel ?? label)(l10n);

  const ShellRouteDestination({
    required this.route,
    required this.icon,
    required this.label,
    this.shortLabel,
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
      shortLabel: _navDashboardShort,
    ),
    ShellRouteDestination(
      route: '/equipment',
      icon: NightshadeIcons.connected,
      label: _navEquipment,
      shortLabel: _navEquipmentShort,
    ),
    ShellRouteDestination(
      route: '/imaging',
      icon: NightshadeIcons.camera,
      label: _navImaging,
      shortLabel: _navImagingShort,
    ),
    ShellRouteDestination(
      route: '/sequencer',
      icon: NightshadeIcons.listOrdered,
      label: _navSequencer,
      shortLabel: _navSequencerShort,
    ),
    ShellRouteDestination(
      route: '/guiding',
      icon: NightshadeIcons.guider,
      label: _navGuiding,
      shortLabel: _navGuidingShort,
    ),
    ShellRouteDestination(
      route: '/planner',
      icon: LucideIcons.moonStar,
      label: _navPlanner,
      shortLabel: _navPlannerShort,
    ),
  ];

  /// Primary destinations that do NOT have a fixed bottom-nav slot on phone, in
  /// side-nav order — today Weather and Analytics. Surfaced through the bottom
  /// bar's "More" overflow so every top-level feature is reachable on mobile,
  /// not just the six core slots + Settings gear. (Your Sky and Constellation
  /// are Plan Tonight tabs, not rail destinations, so they arrive via Planner.)
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

  /// Index of the primary destination that HOSTS [location], or -1 when none
  /// does.
  ///
  /// Sub-routes resolve to their host: `/imaging/preview/42` (the
  /// image-ready deep link) is Imaging, `/settings/plate-solving` is not a rail
  /// destination at all. -1 means "no rail selection" — the shell must render
  /// nothing highlighted rather than pick a plausible-looking tab, because a lit
  /// rail item is a statement about where the operator is.
  static int primaryIndexForLocation(String location) {
    final path = _normalizePath(location);
    final exact = primaryRoutes.indexOf(path);
    if (exact >= 0) return exact;
    for (var i = 0; i < primaryRoutes.length; i++) {
      if (locationIsUnder(path, primaryRoutes[i])) return i;
    }
    return -1;
  }

  /// True when [location] is [route] itself or a route nested beneath it.
  ///
  /// Segment-aware: `/planner-archive` is not under `/planner`.
  static bool locationIsUnder(String location, String route) {
    final path = _normalizePath(location);
    return path == route || path.startsWith('$route/');
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
  static String _navDashboardShort(NightshadeLocalizations l10n) =>
      l10n.text('navDashboardShort');
  static String _navEquipmentShort(NightshadeLocalizations l10n) =>
      l10n.text('navEquipmentShort');
  static String _navImagingShort(NightshadeLocalizations l10n) =>
      l10n.text('navImagingShort');
  static String _navSequencerShort(NightshadeLocalizations l10n) =>
      l10n.text('navSequencerShort');
  static String _navGuidingShort(NightshadeLocalizations l10n) =>
      l10n.text('navGuidingShort');
  static String _navPlannerShort(NightshadeLocalizations l10n) =>
      l10n.text('navPlannerShort');
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
