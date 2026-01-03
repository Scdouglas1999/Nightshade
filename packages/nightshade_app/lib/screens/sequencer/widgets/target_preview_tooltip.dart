import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Provider for target altitude data
final targetAltitudeProvider = FutureProvider.family<TargetAltitudeInfo?, TargetGroupNode>((ref, target) async {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  if (settings == null) return null;

  final lat = settings.latitude;
  final lon = settings.longitude;

  if (lat == 0.0 && lon == 0.0) {
    // No location set
    return null;
  }

  final now = DateTime.now().toUtc();

  // Calculate current altitude
  final currentAlt = _calculateAltitude(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    time: now,
    latitudeDegrees: lat,
    longitudeDegrees: lon,
  );

  // Calculate altitude in 10 minutes to determine if rising or setting
  final futureAlt = _calculateAltitude(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    time: now.add(const Duration(minutes: 10)),
    latitudeDegrees: lat,
    longitudeDegrees: lon,
  );

  final isRising = futureAlt > currentAlt;

  // Calculate transit time
  final transitTime = _calculateTransitTime(
    raHours: target.raHours,
    time: now,
    longitudeDegrees: lon,
  );

  // Calculate altitude at transit
  final transitAlt = _calculateAltitude(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    time: transitTime,
    latitudeDegrees: lat,
    longitudeDegrees: lon,
  );

  // Calculate azimuth
  final azimuth = _calculateAzimuth(
    raHours: target.raHours,
    decDegrees: target.decDegrees,
    time: now,
    latitudeDegrees: lat,
    longitudeDegrees: lon,
  );

  // Calculate hours above horizon
  final hoursAbove = _calculateHoursAboveHorizon(
    decDegrees: target.decDegrees,
    latitudeDegrees: lat,
    minAltitude: target.minAltitude ?? 0,
  );

  return TargetAltitudeInfo(
    currentAltitude: currentAlt,
    azimuth: azimuth,
    isRising: isRising,
    transitTime: transitTime,
    transitAltitude: transitAlt,
    hoursAboveHorizon: hoursAbove,
  );
});

/// Data class for target altitude info
class TargetAltitudeInfo {
  final double currentAltitude;
  final double azimuth;
  final bool isRising;
  final DateTime transitTime;
  final double transitAltitude;
  final double hoursAboveHorizon;

  const TargetAltitudeInfo({
    required this.currentAltitude,
    required this.azimuth,
    required this.isRising,
    required this.transitTime,
    required this.transitAltitude,
    required this.hoursAboveHorizon,
  });
}

/// Calculate altitude for a celestial object
double _calculateAltitude({
  required double raHours,
  required double decDegrees,
  required DateTime time,
  required double latitudeDegrees,
  required double longitudeDegrees,
}) {
  final dec = decDegrees * math.pi / 180.0;
  final lat = latitudeDegrees * math.pi / 180.0;
  final lst = _calculateLST(time, longitudeDegrees);
  final ha = (lst - raHours) * 15.0 * math.pi / 180.0;

  final sinAlt = math.sin(dec) * math.sin(lat) +
                 math.cos(dec) * math.cos(lat) * math.cos(ha);

  return math.asin(sinAlt.clamp(-1.0, 1.0)) * 180.0 / math.pi;
}

/// Calculate azimuth for a celestial object
double _calculateAzimuth({
  required double raHours,
  required double decDegrees,
  required DateTime time,
  required double latitudeDegrees,
  required double longitudeDegrees,
}) {
  final dec = decDegrees * math.pi / 180.0;
  final lat = latitudeDegrees * math.pi / 180.0;
  final lst = _calculateLST(time, longitudeDegrees);
  final ha = (lst - raHours) * 15.0 * math.pi / 180.0;

  final sinAlt = math.sin(dec) * math.sin(lat) +
                 math.cos(dec) * math.cos(lat) * math.cos(ha);
  final alt = math.asin(sinAlt.clamp(-1.0, 1.0));

  final cosAz = (math.sin(dec) - math.sin(alt) * math.sin(lat)) /
                (math.cos(alt) * math.cos(lat));

  var azimuth = math.acos(cosAz.clamp(-1.0, 1.0)) * 180.0 / math.pi;

  // Adjust for correct quadrant
  if (math.sin(ha) > 0) {
    azimuth = 360.0 - azimuth;
  }

  return azimuth;
}

/// Calculate Local Sidereal Time in hours
double _calculateLST(DateTime utcTime, double longitudeDegrees) {
  final jd = _julianDate(utcTime);
  final t = (jd - 2451545.0) / 36525.0;

  var gst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) +
            0.000387933 * t * t - t * t * t / 38710000.0;

  gst = gst % 360.0;
  if (gst < 0) gst += 360.0;

  var lst = gst + longitudeDegrees;
  lst = lst % 360.0;
  if (lst < 0) lst += 360.0;

  return lst / 15.0;
}

/// Calculate Julian Date
double _julianDate(DateTime dt) {
  final y = dt.year;
  final m = dt.month;
  final d = dt.day + dt.hour / 24.0 + dt.minute / 1440.0 + dt.second / 86400.0;

  int a = ((14 - m) / 12).floor();
  int yAdj = y + 4800 - a;
  int mAdj = m + 12 * a - 3;

  return d + ((153 * mAdj + 2) / 5).floor() + 365 * yAdj +
         (yAdj / 4).floor() - (yAdj / 100).floor() + (yAdj / 400).floor() - 32045;
}

/// Calculate transit time
DateTime _calculateTransitTime({
  required double raHours,
  required DateTime time,
  required double longitudeDegrees,
}) {
  final lst = _calculateLST(time, longitudeDegrees);
  var hourAngle = lst - raHours;

  if (hourAngle > 12) hourAngle -= 24;
  if (hourAngle < -12) hourAngle += 24;

  final hoursToTransit = -hourAngle;
  return time.add(Duration(minutes: (hoursToTransit * 60).round()));
}

/// Calculate hours above minimum altitude
double _calculateHoursAboveHorizon({
  required double decDegrees,
  required double latitudeDegrees,
  required double minAltitude,
}) {
  final dec = decDegrees * math.pi / 180.0;
  final lat = latitudeDegrees * math.pi / 180.0;
  final alt = minAltitude * math.pi / 180.0;

  final cosH = (math.sin(alt) - math.sin(dec) * math.sin(lat)) /
               (math.cos(dec) * math.cos(lat));

  if (cosH <= -1.0) {
    return 24.0; // Circumpolar - always above horizon
  } else if (cosH >= 1.0) {
    return 0.0; // Never rises above minimum altitude
  }

  final hourAngle = math.acos(cosH) * 180.0 / math.pi / 15.0;
  return hourAngle * 2.0;
}

/// Target preview tooltip widget
class TargetPreviewTooltip extends ConsumerWidget {
  final TargetGroupNode target;
  final NightshadeColors colors;
  final Widget child;

  const TargetPreviewTooltip({
    super.key,
    required this.target,
    required this.colors,
    required this.child,
  });

  String _formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = (((raHours - hours) * 60 - minutes) * 60).floor();
    return '${hours}h ${minutes}m ${seconds}s';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absVal = decDegrees.abs();
    final degrees = absVal.floor();
    final minutes = ((absVal - degrees) * 60).floor();
    final seconds = (((absVal - degrees) * 60 - minutes) * 60).floor();
    return "$sign$degrees° $minutes' $seconds\"";
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final altitudeData = ref.watch(targetAltitudeProvider(target));

    return Tooltip(
      richMessage: WidgetSpan(
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.target,
                      size: 16,
                      color: colors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.targetName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (target.priority > 0)
                          Text(
                            'Priority: ${target.priority}',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 12),

              // Coordinates
              _InfoRow(
                colors: colors,
                icon: LucideIcons.compass,
                label: 'RA',
                value: _formatRA(target.raHours),
              ),
              const SizedBox(height: 6),
              _InfoRow(
                colors: colors,
                icon: LucideIcons.compass,
                label: 'Dec',
                value: _formatDec(target.decDegrees),
              ),

              if (target.rotation != null) ...[
                const SizedBox(height: 6),
                _InfoRow(
                  colors: colors,
                  icon: LucideIcons.rotateCw,
                  label: 'Rotation',
                  value: '${target.rotation!.toStringAsFixed(1)}°',
                ),
              ],

              // Altitude data
              altitudeData.when(
                data: (data) {
                  if (data == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Set observer location for altitude data',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: colors.textMuted,
                        ),
                      ),
                    );
                  }

                  final isAboveHorizon = data.currentAltitude > 0;
                  final altColor = data.currentAltitude < 20
                      ? colors.error
                      : data.currentAltitude < 40
                          ? colors.warning
                          : colors.success;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Divider(height: 1, color: colors.border),
                      const SizedBox(height: 12),

                      // Current position
                      Row(
                        children: [
                          Expanded(
                            child: _InfoRow(
                              colors: colors,
                              icon: LucideIcons.mountainSnow,
                              label: 'Alt',
                              value: '${data.currentAltitude.toStringAsFixed(1)}°',
                              valueColor: altColor,
                            ),
                          ),
                          Expanded(
                            child: _InfoRow(
                              colors: colors,
                              icon: LucideIcons.compass,
                              label: 'Az',
                              value: '${data.azimuth.toStringAsFixed(1)}°',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Status badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _StatusBadge(
                            colors: colors,
                            icon: data.isRising ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                            label: data.isRising ? 'Rising' : 'Setting',
                            color: data.isRising ? colors.success : colors.warning,
                          ),
                          if (!isAboveHorizon)
                            _StatusBadge(
                              colors: colors,
                              icon: LucideIcons.moonStar,
                              label: 'Below Horizon',
                              color: colors.error,
                            ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Transit info
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.clock,
                              size: 14,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Transit: ${_formatTime(data.transitTime)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Max altitude: ${data.transitAltitude.toStringAsFixed(1)}°',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (data.hoursAboveHorizon > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${data.hoursAboveHorizon.toStringAsFixed(1)}h',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Constraints
                      if (target.minAltitude != null || target.maxAltitude != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.sliders,
                              size: 12,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Constraints: ',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textMuted,
                              ),
                            ),
                            if (target.minAltitude != null)
                              Text(
                                'Min ${target.minAltitude!.toStringAsFixed(0)}°',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textSecondary,
                                ),
                              ),
                            if (target.minAltitude != null && target.maxAltitude != null)
                              Text(
                                ' - ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                            if (target.maxAltitude != null)
                              Text(
                                'Max ${target.maxAltitude!.toStringAsFixed(0)}°',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
                loading: () => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 10),
      preferBelow: false,
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final Color color;

  const _StatusBadge({
    required this.colors,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
