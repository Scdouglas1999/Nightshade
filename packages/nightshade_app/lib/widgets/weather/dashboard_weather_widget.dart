import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact weather widget for the dashboard tertiary zone.
///
/// Shows weather status in a compact card matching other tertiary widgets
/// (Mount, Focus, Tonight). Tapping navigates to full weather screen.
class DashboardWeatherWidget extends ConsumerWidget {
  const DashboardWeatherWidget({super.key});

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
          padding: const EdgeInsets.all(16),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(colors, weatherStatus.currentLevel)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.cloud,
                      size: 16,
                      color: _getStatusColor(colors, weatherStatus.currentLevel),
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
                  _StatusBadge(colors: colors, level: weatherStatus.currentLevel),
                ],
              ),

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
        ),
      ),
    );
  }

  Color _getStatusColor(NightshadeColors colors, AlertLevel level) {
    return switch (level) {
      AlertLevel.clear => colors.success,
      AlertLevel.watch => colors.warning,
      AlertLevel.warning => const Color(0xFFFF9800),
      AlertLevel.critical => colors.error,
    };
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
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }

  (String, Color, Color) _getBadgeStyle() {
    return switch (level) {
      AlertLevel.clear => ('Clear', colors.success.withValues(alpha: 0.2), colors.success),
      AlertLevel.watch => ('Watch', colors.warning.withValues(alpha: 0.2), const Color(0xFF855C00)),
      AlertLevel.warning => ('Warning', const Color(0xFFFF9800).withValues(alpha: 0.2), const Color(0xFFC66900)),
      AlertLevel.critical => ('Critical', colors.error.withValues(alpha: 0.2), colors.error),
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textPrimary),
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

  const _WeatherStatusDisplay({required this.colors, required this.weatherStatus});

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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textPrimary),
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
        return (LucideIcons.cloudRain, 'Clouds approaching', '~$minutes min away');
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
