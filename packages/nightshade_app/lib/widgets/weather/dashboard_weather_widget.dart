import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'weather_radar_map.dart';

/// Responsive weather widget for the dashboard.
///
/// Adapts its display based on available width:
/// - Compact (<300px): Text-only status with "View Radar" button
/// - Medium (300-450px): Text status + small inline radar preview (150x100px)
/// - Expanded (>450px): Text status + larger radar preview (200x150px) + weather alerts
class DashboardWeatherWidget extends ConsumerWidget {
  const DashboardWeatherWidget({super.key});

  // Width breakpoints for responsive layout
  static const double _compactMaxWidth = 300.0;
  static const double _mediumMaxWidth = 450.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final weatherStatus = ref.watch(weatherStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;

    final hasLocation = appSettings != null &&
        !(appSettings.latitude == 0.0 && appSettings.longitude == 0.0);

    return GestureDetector(
      onTap: () => context.go('/weather'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (width < _compactMaxWidth) {
                return _CompactLayout(
                  colors: colors,
                  weatherStatus: weatherStatus,
                  hasLocation: hasLocation,
                );
              } else if (width < _mediumMaxWidth) {
                return _MediumLayout(
                  colors: colors,
                  weatherStatus: weatherStatus,
                  hasLocation: hasLocation,
                  appSettings: appSettings,
                  ref: ref,
                );
              } else {
                return _ExpandedLayout(
                  colors: colors,
                  weatherStatus: weatherStatus,
                  hasLocation: hasLocation,
                  appSettings: appSettings,
                  ref: ref,
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Compact layout (<300px) - Text-only status with "View Radar" button
class _CompactLayout extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;
  final bool hasLocation;

  const _CompactLayout({
    required this.colors,
    required this.weatherStatus,
    required this.hasLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          _WeatherHeader(colors: colors, level: weatherStatus.currentLevel),

          const SizedBox(height: 12),

          // Status info - compact display
          if (!hasLocation)
            _CompactStatus(
              icon: LucideIcons.mapPin,
              text: 'Location not set',
              subtext: 'Configure in Settings',
              colors: colors,
              iconColor: colors.textMuted,
            )
          else if (weatherStatus.isLoading)
            _CompactStatus(
              icon: LucideIcons.loader2,
              text: 'Loading...',
              colors: colors,
              iconColor: colors.textMuted,
            )
          else if (weatherStatus.errorMessage != null)
            _CompactStatus(
              icon: LucideIcons.alertCircle,
              text: 'Error',
              subtext: 'Tap to retry',
              colors: colors,
              iconColor: colors.error,
            )
          else
            _WeatherStatusDisplay(colors: colors, weatherStatus: weatherStatus),

          const SizedBox(height: 12),

          // Open weather button
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: 'View Radar',
              icon: LucideIcons.radar,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => context.go('/weather'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Medium layout (300-450px) - Text status + small radar preview (150x100px)
class _MediumLayout extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;
  final bool hasLocation;
  final AppSettings? appSettings;
  final WidgetRef ref;

  const _MediumLayout({
    required this.colors,
    required this.weatherStatus,
    required this.hasLocation,
    required this.appSettings,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          _WeatherHeader(colors: colors, level: weatherStatus.currentLevel),

          const SizedBox(height: 12),

          // Content row: status on left, radar preview on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status info
              Expanded(
                child: _buildStatusContent(context),
              ),

              const SizedBox(width: 12),

              // Small radar preview
              if (hasLocation &&
                  !weatherStatus.isLoading &&
                  weatherStatus.errorMessage == null)
                _RadarPreview(
                  colors: colors,
                  weatherStatus: weatherStatus,
                  appSettings: appSettings!,
                  ref: ref,
                  width: 150,
                  height: 100,
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Open weather button
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: 'View Radar',
              icon: LucideIcons.radar,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => context.go('/weather'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContent(BuildContext context) {
    if (!hasLocation) {
      return _CompactStatus(
        icon: LucideIcons.mapPin,
        text: 'Location not set',
        subtext: 'Configure in Settings',
        colors: colors,
        iconColor: colors.textMuted,
      );
    } else if (weatherStatus.isLoading) {
      return _CompactStatus(
        icon: LucideIcons.loader2,
        text: 'Loading...',
        colors: colors,
        iconColor: colors.textMuted,
      );
    } else if (weatherStatus.errorMessage != null) {
      return _CompactStatus(
        icon: LucideIcons.alertCircle,
        text: 'Error',
        subtext: 'Tap to retry',
        colors: colors,
        iconColor: colors.error,
      );
    } else {
      return _WeatherStatusDisplay(
          colors: colors, weatherStatus: weatherStatus);
    }
  }
}

/// Expanded layout (>450px) - Text status + larger radar preview (200x150px) + weather alerts
class _ExpandedLayout extends ConsumerWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;
  final bool hasLocation;
  final AppSettings? appSettings;
  final WidgetRef ref;

  const _ExpandedLayout({
    required this.colors,
    required this.weatherStatus,
    required this.hasLocation,
    required this.appSettings,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    // Watch for alerts in expanded mode
    final alertAsync = widgetRef.watch(evaluateWeatherConditionsProvider);
    final alert = alertAsync.valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          _WeatherHeader(colors: colors, level: weatherStatus.currentLevel),

          const SizedBox(height: 12),

          // Content row: status on left, radar preview on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status info + alert
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusContent(context),

                    // Weather alert (if any, warning or critical level)
                    if (hasLocation &&
                        !weatherStatus.isLoading &&
                        weatherStatus.errorMessage == null &&
                        alert != null &&
                        (alert.level == AlertLevel.warning ||
                            alert.level == AlertLevel.critical)) ...[
                      const SizedBox(height: 12),
                      _AlertBanner(colors: colors, alert: alert),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Larger radar preview
              if (hasLocation &&
                  !weatherStatus.isLoading &&
                  weatherStatus.errorMessage == null)
                _RadarPreview(
                  colors: colors,
                  weatherStatus: weatherStatus,
                  appSettings: appSettings!,
                  ref: ref,
                  width: 200,
                  height: 150,
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Open weather button
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: 'View Radar',
              icon: LucideIcons.radar,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () => context.go('/weather'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContent(BuildContext context) {
    if (!hasLocation) {
      return _CompactStatus(
        icon: LucideIcons.mapPin,
        text: 'Location not set',
        subtext: 'Configure in Settings',
        colors: colors,
        iconColor: colors.textMuted,
      );
    } else if (weatherStatus.isLoading) {
      return _CompactStatus(
        icon: LucideIcons.loader2,
        text: 'Loading...',
        colors: colors,
        iconColor: colors.textMuted,
      );
    } else if (weatherStatus.errorMessage != null) {
      return _CompactStatus(
        icon: LucideIcons.alertCircle,
        text: 'Error',
        subtext: 'Tap to retry',
        colors: colors,
        iconColor: colors.error,
      );
    } else {
      return _WeatherStatusDisplay(
          colors: colors, weatherStatus: weatherStatus);
    }
  }
}

/// Radar preview thumbnail widget
class _RadarPreview extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;
  final AppSettings appSettings;
  final WidgetRef ref;
  final double width;
  final double height;

  const _RadarPreview({
    required this.colors,
    required this.weatherStatus,
    required this.appSettings,
    required this.ref,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final weatherSettings = ref.watch(weatherSettingsProvider);
    final motionAsync = ref.watch(analyzeCloudMotionProvider);
    final motionDirection = motionAsync.valueOrNull?.directionDegrees;

    // Get the first radar frame (most recent)
    final currentFrame = weatherStatus.radarFrames.isNotEmpty
        ? weatherStatus.radarFrames.first
        : null;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: currentFrame != null
          ? WeatherRadarMap(
              currentFrame: currentFrame,
              latitude: appSettings.latitude,
              longitude: appSettings.longitude,
              compact: true,
              alertRadiusKm: weatherSettings.triggerDistanceKm,
              radarOpacity: 0.7,
              motionDirection: motionDirection,
              onTap: () => context.go('/weather'),
            )
          : _RadarLoadingCard(colors: colors),
    );
  }
}

/// Loading state card for radar preview
class _RadarLoadingCard extends StatelessWidget {
  final NightshadeColors colors;

  const _RadarLoadingCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceAlt,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading radar...',
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact alert banner for expanded layout
class _AlertBanner extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherAlert alert;

  const _AlertBanner({
    required this.colors,
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, iconColor, icon) = _getAlertStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bgColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getAlertTitle(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: iconColor,
                  ),
                ),
                if (alert.eta != null)
                  Text(
                    _formatEta(alert.eta!),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, IconData) _getAlertStyle() {
    switch (alert.level) {
      case AlertLevel.warning:
        return (
          const Color(0xFFFF9800),
          const Color(0xFFC66900),
          LucideIcons.alertTriangle,
        );
      case AlertLevel.critical:
        return (
          colors.error,
          colors.error,
          LucideIcons.alertOctagon,
        );
      default:
        return (
          colors.warning,
          colors.warning,
          LucideIcons.cloud,
        );
    }
  }

  String _getAlertTitle() {
    switch (alert.level) {
      case AlertLevel.warning:
        return 'Weather Warning';
      case AlertLevel.critical:
        return 'Critical Alert';
      default:
        return 'Weather Watch';
    }
  }

  String _formatEta(DateTime eta) {
    final now = DateTime.now();
    final diff = eta.difference(now);

    if (diff.isNegative) {
      return 'Arrived';
    } else if (diff.inMinutes < 60) {
      return 'ETA: ${diff.inMinutes} min';
    } else {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return 'ETA: ${hours}h ${mins}m';
    }
  }
}

/// Weather card header with icon and title
class _WeatherHeader extends StatelessWidget {
  final NightshadeColors colors;
  final AlertLevel level;

  const _WeatherHeader({
    required this.colors,
    required this.level,
  });

  Color _getStatusColor() {
    return switch (level) {
      AlertLevel.clear => colors.success,
      AlertLevel.watch => colors.warning,
      AlertLevel.warning => const Color(0xFFFF9800),
      AlertLevel.critical => colors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getStatusColor().withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            LucideIcons.cloud,
            size: 16,
            color: _getStatusColor(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Weather',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _StatusBadge(colors: colors, level: level),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final AlertLevel level;

  const _StatusBadge({required this.colors, required this.level});

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, textColor) = _getBadgeStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: textColor),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }

  (String, Color, Color) _getBadgeStyle() {
    return switch (level) {
      AlertLevel.clear => (
          'Clear',
          colors.success.withValues(alpha: 0.2),
          colors.success
        ),
      AlertLevel.watch => (
          'Watch',
          colors.warning.withValues(alpha: 0.2),
          const Color(0xFF855C00)
        ),
      AlertLevel.warning => (
          'Warning',
          const Color(0xFFFF9800).withValues(alpha: 0.2),
          const Color(0xFFC66900)
        ),
      AlertLevel.critical => (
          'Critical',
          colors.error.withValues(alpha: 0.2),
          colors.error
        ),
    };
  }
}

class _CompactStatus extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtext;
  final NightshadeColors colors;
  final Color iconColor;

  const _CompactStatus({
    required this.icon,
    required this.text,
    required this.colors,
    required this.iconColor,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary),
              ),
              if (subtext != null)
                Text(
                  subtext!,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeatherStatusDisplay extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;

  const _WeatherStatusDisplay(
      {required this.colors, required this.weatherStatus});

  @override
  Widget build(BuildContext context) {
    final (icon, statusText, subtext) = _getStatusInfo();

    return Row(
      children: [
        Icon(icon, size: 16, color: _getStatusColor()),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary),
              ),
              if (subtext != null)
                Text(
                  subtext,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  (IconData, String, String?) _getStatusInfo() {
    final motion = weatherStatus.motion;

    if (weatherStatus.currentLevel == AlertLevel.critical) {
      return (LucideIcons.alertTriangle, 'Critical conditions', 'Check radar');
    } else if (weatherStatus.currentLevel == AlertLevel.warning) {
      if (motion?.etaToLocation != null) {
        final minutes = motion!.etaToLocation!.inMinutes;
        return (
          LucideIcons.cloudRain,
          'Clouds approaching',
          '~$minutes min away'
        );
      }
      return (LucideIcons.alertTriangle, 'Warning', 'Monitor conditions');
    } else if (weatherStatus.currentLevel == AlertLevel.watch) {
      return (LucideIcons.eye, 'Watching', 'Conditions changing');
    } else {
      return (LucideIcons.checkCircle, 'Skies clear', 'Good for imaging');
    }
  }

  Color _getStatusColor() {
    return switch (weatherStatus.currentLevel) {
      AlertLevel.clear => colors.success,
      AlertLevel.watch => colors.warning,
      AlertLevel.warning => const Color(0xFFFF9800),
      AlertLevel.critical => colors.error,
    };
  }
}
