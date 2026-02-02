part of 'dashboard_screen.dart';

typedef DashboardWidgetBuilder = Widget Function(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
);

/// Widget definition with zone-aware metadata for the command center layout.
class DashboardWidgetDefinition {
  final DashboardWidgetId id;
  final String title;
  final String subtitle;
  final IconData icon;
  final DashboardZone defaultZone;
  final DashboardWidgetBuilder builder;

  const DashboardWidgetDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.defaultZone,
    required this.builder,
  });
}

const dashboardWidgetRegistry = <DashboardWidgetDefinition>[
  // Primary zone widgets (hero content)
  DashboardWidgetDefinition(
    id: DashboardWidgetId.livePreview,
    title: 'Live Preview',
    subtitle: 'Current image, capture status, and image stats',
    icon: LucideIcons.image,
    defaultZone: DashboardZone.primary,
    builder: _buildLivePreview,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.captureSettings,
    title: 'Capture Settings',
    subtitle: 'Exposure, gain, filter, and capture controls',
    icon: LucideIcons.camera,
    defaultZone: DashboardZone.primary,
    builder: _buildCaptureSettings,
  ),

  // Secondary zone widgets (supporting info and controls)
  DashboardWidgetDefinition(
    id: DashboardWidgetId.sequenceStatus,
    title: 'Sequence Status',
    subtitle: 'Active sequence progress and timing',
    icon: LucideIcons.listOrdered,
    defaultZone: DashboardZone.secondary,
    builder: _buildSequenceStatus,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.guiding,
    title: 'Guiding',
    subtitle: 'RMS and guiding graph',
    icon: LucideIcons.crosshair,
    defaultZone: DashboardZone.secondary,
    builder: _buildGuiding,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.equipmentStatus,
    title: 'Equipment',
    subtitle: 'Device connectivity overview',
    icon: LucideIcons.plug,
    defaultZone: DashboardZone.secondary,
    builder: _buildEquipmentStatus,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.quickActions,
    title: 'Quick Actions',
    subtitle: 'Snapshot, autofocus, centering, and parking',
    icon: LucideIcons.zap,
    defaultZone: DashboardZone.secondary,
    builder: _buildQuickActions,
  ),

  // Tertiary zone widgets (compact status cards)
  DashboardWidgetDefinition(
    id: DashboardWidgetId.mountControl,
    title: 'Mount Control',
    subtitle: 'Mount connection and control actions',
    icon: LucideIcons.move3d,
    defaultZone: DashboardZone.tertiary,
    builder: _buildMountControl,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.focus,
    title: 'Focus',
    subtitle: 'Focuser stats and autofocus controls',
    icon: LucideIcons.focus,
    defaultZone: DashboardZone.tertiary,
    builder: _buildFocus,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.weather,
    title: 'Weather',
    subtitle: 'Cloud status and safety conditions',
    icon: LucideIcons.cloud,
    defaultZone: DashboardZone.tertiary,
    builder: _buildWeather,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.tonight,
    title: 'Tonight',
    subtitle: 'Twilight, moon, and imaging window',
    icon: LucideIcons.moon,
    defaultZone: DashboardZone.tertiary,
    builder: _buildTonight,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.alerts,
    title: 'Alerts',
    subtitle: 'Active operations and recent notifications',
    icon: LucideIcons.bell,
    defaultZone: DashboardZone.tertiary,
    builder: _buildAlerts,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.quickStats,
    title: 'Quick Stats',
    subtitle: 'Sensor temp, focus, HFR, and RMS',
    icon: LucideIcons.activity,
    defaultZone: DashboardZone.tertiary,
    builder: _buildQuickStats,
  ),
];

Widget _buildLivePreview(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _LivePreviewCard(
    key: DashboardTutorialKeys.livePreview,
    colors: colors,
    pulseController: pulseController,
  );
}

Widget _buildCaptureSettings(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _CaptureSettingsCard(key: DashboardTutorialKeys.captureControls, colors: colors);
}

Widget _buildSequenceStatus(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _SessionProgressCard(key: DashboardTutorialKeys.sessionWidget, colors: colors);
}

Widget _buildGuiding(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _GuidingCard(key: DashboardTutorialKeys.guidingWidget, colors: colors);
}

Widget _buildMountControl(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _MountControlCard(key: DashboardTutorialKeys.mountWidget, colors: colors);
}

Widget _buildEquipmentStatus(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _EquipmentStatusCard(key: DashboardTutorialKeys.equipmentStatus, colors: colors);
}

Widget _buildWeather(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return DashboardWeatherWidget(key: DashboardTutorialKeys.weatherWidget);
}

Widget _buildFocus(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _FocusCard(key: DashboardTutorialKeys.focuserWidget, colors: colors);
}

Widget _buildAlerts(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _AlertsCard(colors: colors);
}

Widget _buildQuickActions(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _QuickActionsCard(colors: colors);
}

Widget _buildQuickStats(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _QuickStatsCard(colors: colors);
}

Widget _buildTonight(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return _TonightCard(colors: colors);
}
