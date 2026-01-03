import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact weather widget for the dashboard
///
/// Displays a mini radar preview with weather status indicator, cloud motion
/// analysis, and alert level. Tapping the widget navigates to the full weather
/// monitoring screen.
///
/// Shows:
/// - Current alert level badge (Clear/Watch/Warning/Critical)
/// - Compact radar status visualization
/// - Cloud motion ETA if clouds are approaching
/// - Loading and error states
class DashboardWeatherWidget extends ConsumerWidget {
  const DashboardWeatherWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final weatherStatus = ref.watch(weatherStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;

    // Check if location is configured
    final hasLocation = appSettings != null &&
        !(appSettings.latitude == 0.0 && appSettings.longitude == 0.0);

    return GestureDetector(
      onTap: () {
        context.go('/weather');
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with icon, title, and status badge
              _HeaderRow(
                colors: colors,
                currentLevel: weatherStatus.currentLevel,
              ),

              const SizedBox(height: 16),

              // Main content area
              if (!hasLocation)
                _LocationNotSetContent(colors: colors)
              else if (weatherStatus.isLoading)
                _LoadingContent(colors: colors)
              else if (weatherStatus.errorMessage != null)
                _ErrorContent(
                  colors: colors,
                  errorMessage: weatherStatus.errorMessage!,
                )
              else
                _WeatherContent(
                  colors: colors,
                  weatherStatus: weatherStatus,
                ),

              const SizedBox(height: 12),

              // Footer with navigation hint
              _FooterRow(colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header row with cloud icon, title, and status badge
class _HeaderRow extends StatelessWidget {
  final NightshadeColors colors;
  final AlertLevel currentLevel;

  const _HeaderRow({
    required this.colors,
    required this.currentLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
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
            Text(
              'Weather',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        _StatusBadge(
          colors: colors,
          level: currentLevel,
        ),
      ],
    );
  }

  /// Get color based on alert level
  Color _getStatusColor() {
    switch (currentLevel) {
      case AlertLevel.clear:
        return colors.success;
      case AlertLevel.watch:
        return colors.warning;
      case AlertLevel.warning:
        return const Color(0xFFFF9800); // Orange
      case AlertLevel.critical:
        return colors.error;
    }
  }
}

/// Status badge showing current alert level
class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final AlertLevel level;

  const _StatusBadge({
    required this.colors,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, textColor) = _getBadgeStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: textColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Get badge styling based on alert level
  (String, Color, Color) _getBadgeStyle() {
    switch (level) {
      case AlertLevel.clear:
        return ('Clear', colors.success.withValues(alpha: 0.2), colors.success);
      case AlertLevel.watch:
        return ('Watch', colors.warning.withValues(alpha: 0.2), const Color(0xFF855C00));
      case AlertLevel.warning:
        return ('Warning', const Color(0xFFFF9800).withValues(alpha: 0.2), const Color(0xFFC66900));
      case AlertLevel.critical:
        return ('Critical', colors.error.withValues(alpha: 0.2), colors.error);
    }
  }
}

/// Content shown when location is not configured
class _LocationNotSetContent extends StatelessWidget {
  final NightshadeColors colors;

  const _LocationNotSetContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.mapPin,
              size: 32,
              color: colors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Location not set',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure location in Settings',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading state content
class _LoadingContent extends StatelessWidget {
  final NightshadeColors colors;

  const _LoadingContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading radar data...',
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state content
class _ErrorContent extends StatelessWidget {
  final NightshadeColors colors;
  final String errorMessage;

  const _ErrorContent({
    required this.colors,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 32,
                color: colors.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Error loading weather',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to retry',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main weather content with radar visualization and status
class _WeatherContent extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;

  const _WeatherContent({
    required this.colors,
    required this.weatherStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mini radar preview area
        _RadarPreview(
          colors: colors,
          radarFrames: weatherStatus.radarFrames,
        ),

        const SizedBox(height: 12),

        // Status row with icon and message
        _StatusRow(
          colors: colors,
          weatherStatus: weatherStatus,
        ),
      ],
    );
  }
}

/// Compact radar preview visualization
class _RadarPreview extends StatelessWidget {
  final NightshadeColors colors;
  final List<RadarFrame> radarFrames;

  const _RadarPreview({
    required this.colors,
    required this.radarFrames,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Background grid pattern
            CustomPaint(
              painter: _GridPainter(colors: colors),
              size: Size.infinite,
            ),

            // Radar data visualization
            if (radarFrames.isNotEmpty)
              Center(
                child: Icon(
                  LucideIcons.cloudRain,
                  size: 48,
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              )
            else
              Center(
                child: Icon(
                  LucideIcons.cloudOff,
                  size: 48,
                  color: colors.textMuted.withValues(alpha: 0.3),
                ),
              ),

            // Frame count overlay
            if (radarFrames.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.layers,
                        size: 10,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${radarFrames.length} frames',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grid background painter for radar preview
class _GridPainter extends CustomPainter {
  final NightshadeColors colors;

  _GridPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.border.withValues(alpha: 0.1)
      ..strokeWidth = 1.0;

    const gridSize = 30.0;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Status row showing current conditions and ETA
class _StatusRow extends StatelessWidget {
  final NightshadeColors colors;
  final WeatherStatus weatherStatus;

  const _StatusRow({
    required this.colors,
    required this.weatherStatus,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, message) = _getStatusInfo();

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: _getStatusColor(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ),
        Icon(
          LucideIcons.chevronRight,
          size: 16,
          color: colors.textMuted,
        ),
      ],
    );
  }

  /// Get status icon and message based on current conditions
  (IconData, String) _getStatusInfo() {
    final alert = weatherStatus.activeAlert;
    final motion = weatherStatus.motion;

    if (weatherStatus.currentLevel == AlertLevel.critical) {
      return (LucideIcons.alertTriangle, alert?.message ?? 'Critical conditions');
    } else if (weatherStatus.currentLevel == AlertLevel.warning) {
      if (motion?.etaToLocation != null) {
        final minutes = motion!.etaToLocation!.inMinutes;
        return (LucideIcons.alertTriangle, 'Clouds ~$minutes min away');
      }
      return (LucideIcons.alertTriangle, alert?.message ?? 'Warning');
    } else if (weatherStatus.currentLevel == AlertLevel.watch) {
      return (LucideIcons.eye, alert?.message ?? 'Monitoring conditions');
    } else {
      return (LucideIcons.checkCircle, 'Skies clear');
    }
  }

  /// Get status color based on alert level
  Color _getStatusColor() {
    switch (weatherStatus.currentLevel) {
      case AlertLevel.clear:
        return colors.success;
      case AlertLevel.watch:
        return colors.warning;
      case AlertLevel.warning:
        return const Color(0xFFFF9800);
      case AlertLevel.critical:
        return colors.error;
    }
  }
}

/// Footer row with tap hint
class _FooterRow extends StatelessWidget {
  final NightshadeColors colors;

  const _FooterRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.mousePointerClick,
          size: 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          'Tap for detailed weather view',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
