part of '../weather_screen.dart';

/// Cloud cover percentage display card
class _CloudCoverCard extends StatelessWidget {
  final double? cloudCoverPercent;
  final NightshadeColors colors;

  const _CloudCoverCard({
    required this.cloudCoverPercent,
    required this.colors,
  });

  Color _getCloudCoverColor(double percent) {
    if (percent <= 20) return colors.success;
    if (percent <= 40) return const Color(0xFF22C55E); // Green
    if (percent <= 60) return colors.warning;
    if (percent <= 80) return const Color(0xFFFB923C); // Orange
    return colors.error;
  }

  String _getCloudCoverLabel(double percent) {
    if (percent <= 10) return 'Clear';
    if (percent <= 25) return 'Mostly Clear';
    if (percent <= 50) return 'Partly Cloudy';
    if (percent <= 75) return 'Mostly Cloudy';
    if (percent <= 90) return 'Cloudy';
    return 'Overcast';
  }

  IconData _getCloudCoverIcon(double percent) {
    if (percent <= 20) return LucideIcons.sun;
    if (percent <= 50) return LucideIcons.cloudSun;
    if (percent <= 80) return LucideIcons.cloud;
    return LucideIcons.cloudFog;
  }

  @override
  Widget build(BuildContext context) {
    final percent = cloudCoverPercent ?? 0.0;
    final coverColor = _getCloudCoverColor(percent);
    final label = _getCloudCoverLabel(percent);
    final icon = _getCloudCoverIcon(percent);

    return Container(
      padding: _weatherCardPadding(context),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: NightshadeDecorations.tintedBadge(
              coverColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 24,
              color: coverColor,
            ),
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloud Cover',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      cloudCoverPercent != null ? '${percent.toInt()}%' : '--',
                      style: NightshadeTypography.telemetryLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: coverColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Progress indicator
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 6,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(coverColor),
                ),
                Text(
                  cloudCoverPercent != null ? '${percent.toInt()}' : '--',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hardware weather and safety device sensors card
/// Displays readings from connected hardware devices prominently
class _HardwareSensorsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _HardwareSensorsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherState = ref.watch(weatherStateProvider);
    final safetyState = ref.watch(safetyMonitorStateProvider);

    final hasWeatherDevice =
        weatherState.connectionState == DeviceConnectionState.connected;
    final hasSafetyDevice =
        safetyState.connectionState == DeviceConnectionState.connected;

    // Don't show if no hardware devices connected
    if (!hasWeatherDevice && !hasSafetyDevice) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: _weatherCardPadding(context),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.cpu,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Sensors',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Live readings from connected devices',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Safety monitor status (priority)
          if (hasSafetyDevice) ...[
            _SensorRow(
              colors: colors,
              icon: safetyState.isSafe
                  ? LucideIcons.shieldCheck
                  : LucideIcons.shieldAlert,
              label: 'Safety Monitor',
              value: safetyState.isSafe ? 'SAFE' : 'UNSAFE',
              valueColor: safetyState.isSafe ? colors.success : colors.error,
              deviceName: safetyState.deviceName,
            ),
            if (hasWeatherDevice) const SizedBox(height: 12),
          ],

          // Weather device readings
          if (hasWeatherDevice) ...[
            if (weatherState.temperature != null)
              _SensorRow(
                colors: colors,
                icon: LucideIcons.thermometer,
                label: 'Temperature',
                value: '${weatherState.temperature!.toStringAsFixed(1)}°C',
              ),
            if (weatherState.humidity != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.droplets,
                label: 'Humidity',
                value: '${weatherState.humidity!.toStringAsFixed(0)}%',
                valueColor: weatherState.humidity! > 80 ? colors.warning : null,
              ),
            ],
            if (weatherState.dewPoint != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.droplet,
                label: 'Dew Point',
                value: '${weatherState.dewPoint!.toStringAsFixed(1)}°C',
              ),
            ],
            if (weatherState.windSpeed != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.wind,
                label: 'Wind Speed',
                value: '${weatherState.windSpeed!.toStringAsFixed(1)} m/s',
                valueColor:
                    weatherState.windSpeed! > 15 ? colors.warning : null,
              ),
            ],
            if (weatherState.cloudCover != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.cloud,
                label: 'Cloud Cover',
                value: '${weatherState.cloudCover!.toStringAsFixed(0)}%',
                valueColor:
                    weatherState.cloudCover! > 60 ? colors.warning : null,
              ),
            ],
            if (weatherState.skyQuality != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.sparkles,
                label: 'Sky Quality',
                value:
                    '${weatherState.skyQuality!.toStringAsFixed(2)} mag/arcsec²',
              ),
            ],
            if (weatherState.rainRate != null &&
                weatherState.rainRate! > 0) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.cloudRain,
                label: 'Rain',
                value: '${weatherState.rainRate!.toStringAsFixed(1)} mm/hr',
                valueColor: colors.error,
              ),
            ],
          ],

          // Last updated
          if (weatherState.lastUpdated != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last updated: ${_formatTime(weatherState.lastUpdated!)}',
              style: TextStyle(
                fontSize: 10,
                color: colors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

/// Single sensor reading row
class _SensorRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? deviceName;

  const _SensorRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
              if (deviceName != null)
                Text(
                  deviceName!,
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
