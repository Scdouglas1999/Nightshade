import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/tutorial_keys/dashboard_keys.dart';
import '../../../widgets/weather/dashboard_weather_widget.dart';
import '../dashboard_layout.dart';
import 'live_preview_card.dart';
import 'capture_settings_card.dart';
import 'session_progress_card.dart';
import 'guiding_card.dart';
import 'equipment_status_card.dart';
import 'quick_actions_card.dart';
import 'mount_control_card.dart';
import 'focus_card.dart';
import 'alerts_card.dart';
import 'quick_stats_card.dart';
import 'tonight_card.dart';
import 'storage_card.dart';
import '../../sequencer/widgets/run_dashboard/target_header_panel.dart';
import '../../sequencer/widgets/run_dashboard/live_frame_panel.dart';
import '../../sequencer/widgets/run_dashboard/exposure_progress_panel.dart';
import '../../sequencer/widgets/run_dashboard/filter_integration_panel.dart';
import '../../sequencer/widgets/run_dashboard/equipment_telemetry_panel.dart';
import '../../sequencer/widgets/run_dashboard/guiding_panel_card.dart';
import '../../sequencer/widgets/run_dashboard/weather_safety_card.dart';
import '../../sequencer/widgets/run_dashboard/session_warnings_panel.dart';
import '../../sequencer/widgets/run_dashboard/trigger_feed_panel.dart';
import '../../sequencer/widgets/run_dashboard/scheduler_panel.dart';
import '../../sequencer/widgets/run_dashboard/cloud_motion_panel.dart';
import '../../sequencer/widgets/run_dashboard/adaptive_conditions_panel.dart';
import '../../sequencer/widgets/run_dashboard/light_curve_panel.dart';
import '../../sequencer/widgets/run_dashboard/observatory_panel.dart';
import '../../sequencer/widgets/run_dashboard/quality_panel.dart';
import '../../sequencer/widgets/run_dashboard/forensics_panel.dart';
import '../../sequencer/widgets/secondary_rig_card.dart';
import 'cockpit_recent_frames.dart';
import 'cockpit_now_imaging.dart';
import 'cockpit_frames.dart';
import 'cockpit_session_vitals.dart';
import 'cockpit_sky_context.dart';
import 'cockpit_narrator.dart';
import 'cockpit_morning_report.dart';

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

  /// When true, the panel renders its own chrome (NightshadeCard / banner) and
  /// the dashboard tile frame must NOT draw a resting border/background — only
  /// the editing / drop-target / hero highlight border and the edit-mode
  /// affordances. Avoids double borders on the transplanted cockpit panels.
  final bool selfChromed;

  const DashboardWidgetDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.defaultZone,
    required this.builder,
    this.selfChromed = false,
  });
}

const dashboardWidgetRegistry = <DashboardWidgetDefinition>[
  // ===========================================================================
  // Merged cockpit tiles (density pass). Self-chromed like the rest.
  // ===========================================================================
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitNowImaging,
    title: 'Now Imaging',
    subtitle: 'Active target, altitude, and run progress in one strip',
    icon: LucideIcons.target,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitNowImaging,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitFrames,
    title: 'Frames',
    subtitle: 'Current sub-exposure with recent-capture strip',
    icon: LucideIcons.image,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitFrames,
  ),

  // ===========================================================================
  // Cockpit panels (transplanted Run dashboard). All are self-chromed: each
  // wraps itself in a NightshadeCard / banner, so the tile frame draws no
  // resting border. They read their own providers and degrade gracefully idle.
  // ===========================================================================
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitTargetHeader,
    title: 'Target',
    subtitle: 'Active target, progress, and night-at-a-glance banner',
    icon: LucideIcons.target,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitTargetHeader,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitLiveFrame,
    title: 'Live Frame',
    subtitle: 'Most recent sub-exposure with quality readout',
    icon: LucideIcons.image,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitLiveFrame,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitExposureProgress,
    title: 'Exposure Progress',
    subtitle: 'Current exposure, dither, and download timing',
    icon: LucideIcons.timer,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitExposureProgress,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitRecentFrames,
    title: 'Recent Frames',
    subtitle: 'Newest captures with filter, exposure, and time',
    icon: LucideIcons.galleryThumbnails,
    defaultZone: DashboardZone.primary,
    selfChromed: true,
    builder: _buildCockpitRecentFrames,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitFilterIntegration,
    title: 'Filter Integration',
    subtitle: 'Accumulated integration time per filter',
    icon: LucideIcons.layers,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitFilterIntegration,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitEquipmentTelemetry,
    title: 'Equipment Telemetry',
    subtitle: 'Live device readouts (temp, position, status)',
    icon: LucideIcons.plug,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitEquipmentTelemetry,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitGuiding,
    title: 'Guiding',
    subtitle: 'RMS error and guiding graph',
    icon: LucideIcons.crosshair,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitGuiding,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitWeatherSafety,
    title: 'Weather & Safety',
    subtitle: 'Sky conditions and safety monitor status',
    icon: LucideIcons.cloud,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitWeatherSafety,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitSessionWarnings,
    title: 'Session Warnings',
    subtitle: 'Active warnings and degraded-condition notices',
    icon: LucideIcons.alertTriangle,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitSessionWarnings,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitTriggerFeed,
    title: 'Trigger Feed',
    subtitle: 'Recent automation trigger activity',
    icon: LucideIcons.zap,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitTriggerFeed,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitScheduler,
    title: 'Unattended Autopilot',
    subtitle: 'Runs unattended and re-picks targets all night — distinct from '
        'Plan Tonight',
    icon: LucideIcons.calendarClock,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitScheduler,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitCloudMotion,
    title: 'Cloud Motion',
    subtitle: 'Radar-derived cloud movement and trend',
    icon: LucideIcons.wind,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitCloudMotion,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitAdaptiveConditions,
    title: 'Adaptive Conditions',
    subtitle: 'Adaptive exposure/condition responses',
    icon: LucideIcons.slidersHorizontal,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitAdaptiveConditions,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitLightCurve,
    title: 'Light Curve',
    subtitle: 'Photometric light curve for the active target',
    icon: LucideIcons.activity,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitLightCurve,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitObservatory,
    title: 'Observatory',
    subtitle: 'Dome shutter/azimuth, flat cover, and power switches',
    icon: LucideIcons.warehouse,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitObservatory,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitSecondaryRig,
    title: 'Secondary Rig',
    subtitle: 'Piggyback camera loop with dither-coordinated capture',
    icon: LucideIcons.camera,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitSecondaryRig,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitQuality,
    title: 'Quality',
    subtitle: 'Frame accept/reject rate, HFR trend, and adaptive exposure',
    icon: LucideIcons.gauge,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitQuality,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitSessionVitals,
    title: 'Session Vitals',
    subtitle: 'Integration efficiency and live run counters',
    icon: LucideIcons.activity,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitSessionVitals,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitSkyContext,
    title: 'Sky Context',
    subtitle: 'Altitude, airmass, moon, and darkness window',
    icon: LucideIcons.orbit,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitSkyContext,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitForensics,
    title: 'Frame Forensics',
    subtitle: 'Recent rejections grouped by likely cause',
    icon: LucideIcons.search,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitForensics,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitNarrator,
    title: 'Night Narrator',
    subtitle: "Live interpretation of your session's science data",
    icon: LucideIcons.sparkles,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitNarrator,
  ),
  DashboardWidgetDefinition(
    id: DashboardWidgetId.cockpitMorningReport,
    title: 'Morning Report',
    subtitle: "Last night's accepted/rejected counts — tap to review",
    icon: LucideIcons.sunrise,
    defaultZone: DashboardZone.secondary,
    selfChromed: true,
    builder: _buildCockpitMorningReport,
  ),

  // ===========================================================================
  // Legacy control/info cards (disabled by default; retained for power users).
  // ===========================================================================
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
  DashboardWidgetDefinition(
    id: DashboardWidgetId.storage,
    title: 'Storage',
    subtitle: 'Free space and projected sequence size',
    icon: LucideIcons.hardDrive,
    defaultZone: DashboardZone.tertiary,
    builder: _buildStorage,
  ),
];

// Cockpit panel builders. These panels read their own Riverpod providers, so
// the colors/pulseController arguments are intentionally unused.
Widget _buildCockpitNowImaging(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitNowImaging();
}

Widget _buildCockpitFrames(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitFrames();
}

Widget _buildCockpitTargetHeader(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardTargetHeader();
}

Widget _buildCockpitLiveFrame(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardLiveFrame();
}

Widget _buildCockpitExposureProgress(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardExposureProgress();
}

Widget _buildCockpitRecentFrames(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitRecentFrames();
}

Widget _buildCockpitFilterIntegration(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardFilterIntegration();
}

Widget _buildCockpitEquipmentTelemetry(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardEquipmentPanel();
}

Widget _buildCockpitGuiding(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardGuidingCard();
}

Widget _buildCockpitWeatherSafety(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardWeatherSafetyCard();
}

Widget _buildCockpitSessionWarnings(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardSessionWarningsPanel();
}

Widget _buildCockpitTriggerFeed(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardTriggerFeed();
}

Widget _buildCockpitScheduler(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardSchedulerPanel();
}

Widget _buildCockpitCloudMotion(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardCloudMotionPanel();
}

Widget _buildCockpitAdaptiveConditions(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardAdaptiveConditionsPanel();
}

Widget _buildCockpitLightCurve(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const LightCurvePanel();
}

Widget _buildCockpitObservatory(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardObservatoryPanel();
}

Widget _buildCockpitSecondaryRig(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const SecondaryRigCard();
}

Widget _buildCockpitQuality(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const RunDashboardQualityPanel();
}

Widget _buildCockpitSessionVitals(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitSessionVitals();
}

Widget _buildCockpitSkyContext(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitSkyContext();
}

// The forensics panel takes a session id (String) so it can backfill and
// filter live rejections for the active run. Resolve it from the live session
// state — `dbSessionId` is an int, so stringify it; the panel treats a null id
// as "live events only" and hides itself (empty state) when no rejections
// exist, so an idle dashboard stays clean.
Widget _buildCockpitForensics(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return Consumer(
    builder: (context, ref, _) {
      final dbSessionId = ref.watch(
        sessionStateProvider.select((s) => s.dbSessionId),
      );
      return RunDashboardForensicsPanel(
        sessionId: dbSessionId?.toString(),
      );
    },
  );
}

Widget _buildCockpitNarrator(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitNarrator();
}

Widget _buildCockpitMorningReport(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const CockpitMorningReport();
}

Widget _buildLivePreview(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return LivePreviewCard(
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
  return CaptureSettingsCard(
      key: DashboardTutorialKeys.captureControls, colors: colors);
}

Widget _buildSequenceStatus(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return SessionProgressCard(
      key: DashboardTutorialKeys.sessionWidget, colors: colors);
}

Widget _buildGuiding(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return GuidingCard(key: DashboardTutorialKeys.guidingWidget, colors: colors);
}

Widget _buildMountControl(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return MountControlCard(
      key: DashboardTutorialKeys.mountWidget, colors: colors);
}

Widget _buildEquipmentStatus(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return EquipmentStatusCard(
      key: DashboardTutorialKeys.equipmentStatus, colors: colors);
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
  return FocusCard(key: DashboardTutorialKeys.focuserWidget, colors: colors);
}

Widget _buildAlerts(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return AlertsCard(colors: colors);
}

Widget _buildQuickActions(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return QuickActionsCard(colors: colors);
}

Widget _buildQuickStats(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return QuickStatsCard(colors: colors);
}

Widget _buildTonight(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return TonightCard(colors: colors);
}

Widget _buildStorage(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return StorageCard(colors: colors);
}
