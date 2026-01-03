import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Weather status card showing current conditions and alerts
class WeatherStatusCard extends ConsumerStatefulWidget {
  /// Current weather alert (if any)
  final WeatherAlert? alert;

  /// Cloud motion data (if available)
  final CloudMotion? motion;

  /// Last data update time
  final DateTime? lastUpdate;

  /// Whether to show expanded details
  final bool expanded;

  /// Callback to toggle expanded state
  final VoidCallback? onExpandToggle;

  const WeatherStatusCard({
    super.key,
    this.alert,
    this.motion,
    this.lastUpdate,
    this.expanded = true,
    this.onExpandToggle,
  });

  @override
  ConsumerState<WeatherStatusCard> createState() => _WeatherStatusCardState();
}

class _WeatherStatusCardState extends ConsumerState<WeatherStatusCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Get icon for alert level
  IconData _getAlertIcon(AlertLevel level) {
    switch (level) {
      case AlertLevel.clear:
        return LucideIcons.checkCircle;
      case AlertLevel.watch:
        return LucideIcons.eye;
      case AlertLevel.warning:
        return LucideIcons.alertTriangle;
      case AlertLevel.critical:
        return LucideIcons.alertOctagon;
    }
  }

  /// Get color for alert level
  Color _getAlertColor(AlertLevel level, NightshadeColors colors) {
    switch (level) {
      case AlertLevel.clear:
        return colors.success;
      case AlertLevel.watch:
        return colors.warning;
      case AlertLevel.warning:
        return const Color(0xFFFB923C); // Orange
      case AlertLevel.critical:
        return colors.error;
    }
  }

  /// Get text label for alert level
  String _getAlertLabel(AlertLevel level) {
    switch (level) {
      case AlertLevel.clear:
        return 'Clear';
      case AlertLevel.watch:
        return 'Watch';
      case AlertLevel.warning:
        return 'Warning';
      case AlertLevel.critical:
        return 'Critical';
    }
  }

  /// Format ETA duration
  String _formatEta(Duration eta) {
    final minutes = eta.inMinutes;
    if (minutes < 2) {
      return 'Imminent';
    } else if (minutes < 60) {
      return '~$minutes min';
    } else {
      final hours = eta.inHours;
      final remainingMinutes = minutes % 60;
      return '~${hours}h ${remainingMinutes}m';
    }
  }

  /// Convert degrees to cardinal direction
  String _degreesToCardinal(double degrees) {
    // Normalize to 0-360
    final normalized = degrees % 360;

    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((normalized + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }

  /// Format last update time as relative
  String _formatLastUpdate(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} sec ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Default to clear if no alert
    final alertLevel = widget.alert?.level ?? AlertLevel.clear;
    final alertIcon = _getAlertIcon(alertLevel);
    final alertColor = _getAlertColor(alertLevel, colors);
    final alertLabel = _getAlertLabel(alertLevel);

    if (!widget.expanded) {
      return _buildCollapsedView(colors, alertIcon, alertColor, alertLabel);
    }

    return Container(
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: alertColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      alertIcon,
                      size: 16,
                      color: alertColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    alertLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (widget.onExpandToggle != null)
                IconButton(
                  icon: Icon(
                    LucideIcons.chevronUp,
                    size: 18,
                    color: colors.textMuted,
                  ),
                  onPressed: widget.onExpandToggle,
                  tooltip: 'Collapse',
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Alert message (if present)
          if (widget.alert != null) ...[
            Text(
              widget.alert!.message,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ETA countdown (if approaching)
          if (widget.alert?.eta != null) ...[
            _buildEtaCountdown(colors, alertLevel),
            const SizedBox(height: 16),
          ],

          // Cloud info section (if motion data available)
          if (widget.motion != null) ...[
            _buildCloudInfo(colors),
            const SizedBox(height: 16),
          ],

          // Last updated
          if (widget.lastUpdate != null)
            Text(
              'Updated ${_formatLastUpdate(widget.lastUpdate!)}',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  /// Build collapsed view
  Widget _buildCollapsedView(
    NightshadeColors colors,
    IconData alertIcon,
    Color alertColor,
    String alertLabel,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(alertIcon, size: 16, color: alertColor),
              const SizedBox(width: 8),
              Text(
                alertLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
              if (widget.alert?.eta != null) ...[
                const SizedBox(width: 12),
                Text(
                  _formatEta(widget.alert!.eta!.difference(DateTime.now())),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (widget.onExpandToggle != null)
            IconButton(
              icon: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: colors.textMuted,
              ),
              onPressed: widget.onExpandToggle,
              tooltip: 'Expand',
            ),
        ],
      ),
    );
  }

  /// Build ETA countdown box
  Widget _buildEtaCountdown(NightshadeColors colors, AlertLevel alertLevel) {
    final eta = widget.alert!.eta!;
    final now = DateTime.now();
    final remaining = eta.difference(now);

    // Pulsing animation for critical alerts and imminent arrivals
    final shouldPulse = alertLevel == AlertLevel.critical || remaining.inMinutes < 5;

    Widget content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getAlertColor(alertLevel, colors).withValues(alpha: 0.15),
            _getAlertColor(alertLevel, colors).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getAlertColor(alertLevel, colors).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            _formatEta(remaining),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _getAlertColor(alertLevel, colors),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'until arrival',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (shouldPulse) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_pulseController.value * 0.02),
            child: Opacity(
              opacity: 0.85 + (_pulseController.value * 0.15),
              child: child,
            ),
          );
        },
        child: content,
      );
    }

    return content;
  }

  /// Build cloud info section
  Widget _buildCloudInfo(NightshadeColors colors) {
    final motion = widget.motion!;
    final cardinal = _degreesToCardinal(motion.directionDegrees);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cloud metrics row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CloudMetric(
              label: 'Density',
              value: '${widget.alert?.cloudDensityPercent.toStringAsFixed(0) ?? '0'}%',
              colors: colors,
            ),
            _CloudMetric(
              label: 'Distance',
              value: '${motion.distanceKm.toStringAsFixed(1)} km',
              colors: colors,
            ),
            _CloudMetric(
              label: 'Speed',
              value: '${motion.speedKmh.toStringAsFixed(1)} km/h',
              colors: colors,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Direction indicator
        Row(
          children: [
            Icon(
              LucideIcons.wind,
              size: 14,
              color: colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Moving from ',
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            Text(
              cardinal,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            _DirectionArrow(
              directionDegrees: motion.directionDegrees,
              color: colors.textMuted,
            ),
          ],
        ),
      ],
    );
  }
}

/// Cloud metric display
class _CloudMetric extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CloudMetric({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Directional arrow showing cloud movement direction
class _DirectionArrow extends StatelessWidget {
  final double directionDegrees;
  final Color color;

  const _DirectionArrow({
    required this.directionDegrees,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: (directionDegrees - 90) * math.pi / 180, // Rotate arrow to point in direction
      child: Icon(
        LucideIcons.arrowRight,
        size: 16,
        color: color,
      ),
    );
  }
}
