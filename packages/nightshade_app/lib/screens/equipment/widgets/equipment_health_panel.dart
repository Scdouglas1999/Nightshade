import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Whether the equipment health panel is expanded in the equipment screen.
final equipmentHealthExpandedProvider = StateProvider<bool>((ref) => false);

/// Collapsible equipment health panel showing system health score, insights,
/// and per-device heartbeat status.
class EquipmentHealthPanel extends ConsumerWidget {
  const EquipmentHealthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isExpanded = ref.watch(equipmentHealthExpandedProvider);
    final reportAsync = ref.watch(equipmentHealthReportProvider);
    final deviceSnapshots = ref.watch(deviceHealthSnapshotsProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar - always visible, acts as toggle
          _HealthHeaderBar(
            reportAsync: reportAsync,
            isExpanded: isExpanded,
            onToggle: () {
              ref.read(equipmentHealthExpandedProvider.notifier).state =
                  !isExpanded;
            },
          ),

          // Expandable detail content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: reportAsync.when(
              data: (report) => _HealthDetailContent(
                report: report,
                deviceSnapshots: deviceSnapshots,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => _HealthErrorContent(error: error),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Header Bar (always visible)
// =============================================================================

class _HealthHeaderBar extends StatelessWidget {
  final AsyncValue<EquipmentHealthReport> reportAsync;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _HealthHeaderBar({
    required this.reportAsync,
    required this.isExpanded,
    required this.onToggle,
  });

  static List<Widget> _warningCountWidgets(
      AsyncValue<EquipmentHealthReport> reportAsync, NightshadeColors colors) {
    final report = reportAsync.valueOrNull;
    if (report == null) return const [];
    final warningCount = report.insights
        .where((i) =>
            i.severity == EquipmentHealthSeverity.warning ||
            i.severity == EquipmentHealthSeverity.critical)
        .length;
    if (warningCount == 0) return const [];
    return [
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$warningCount ${warningCount == 1 ? 'issue' : 'issues'}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.warning,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(LucideIcons.heartPulse, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'System Health',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            // Inline score badge
            reportAsync.when(
              data: (report) => _ScoreBadge(score: report.score),
              loading: () => SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colors.textMuted,
                ),
              ),
              error: (_, __) => Icon(
                LucideIcons.alertTriangle,
                size: 14,
                color: colors.error,
              ),
            ),
            // Show warning count if any
            ..._warningCountWidgets(reportAsync, colors),
            const Spacer(),
            Icon(
              isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Score Badge
// =============================================================================

class _ScoreBadge extends StatelessWidget {
  final double score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (badgeColor, label) = _scoreAppearance(score, colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badgeColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${score.round()} - $label',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  static (Color, String) _scoreAppearance(
      double score, NightshadeColors colors) {
    if (score >= 85) return (colors.success, 'Excellent');
    if (score >= 70) return (colors.info, 'Good');
    if (score >= 50) return (colors.warning, 'Fair');
    return (colors.error, 'Poor');
  }
}

// =============================================================================
// Health Detail Content (shown when expanded)
// =============================================================================

class _HealthDetailContent extends StatelessWidget {
  final EquipmentHealthReport report;
  final List<DeviceHealthSnapshot> deviceSnapshots;

  const _HealthDetailContent({
    required this.report,
    required this.deviceSnapshots,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score gauge + summary row
          _ScoreGaugeRow(score: report.score),
          const SizedBox(height: 16),

          // Insights list
          ...report.insights.map((insight) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InsightCard(insight: insight),
              )),

          // Device heartbeat section (only if there are snapshots)
          if (deviceSnapshots.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'DEVICE HEARTBEATS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: deviceSnapshots
                  .map((s) => _DeviceHeartbeatChip(snapshot: s))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Score Gauge Row
// =============================================================================

class _ScoreGaugeRow extends StatelessWidget {
  final double score;

  const _ScoreGaugeRow({required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (gaugeColor, _) = _ScoreBadge._scoreAppearance(score, colors);

    return Row(
      children: [
        // Score number
        Text(
          '${score.round()}',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: gaugeColor,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '/100',
          style: TextStyle(
            fontSize: 14,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: 16),
        // Progress bar
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: score / 100.0,
                  minHeight: 6,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _scoreDescription(score),
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _scoreDescription(double score) {
    if (score >= 85) {
      return 'All metrics within normal ranges. Equipment performing well.';
    }
    if (score >= 70) {
      return 'Minor deviations detected. Review insights below.';
    }
    if (score >= 50) {
      return 'Several metrics outside normal ranges. Attention recommended.';
    }
    return 'Significant issues detected. Immediate attention required.';
  }
}

// =============================================================================
// Insight Card
// =============================================================================

class _InsightCard extends StatelessWidget {
  final EquipmentHealthInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (iconData, iconColor) = _severityAppearance(insight.severity, colors);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color) _severityAppearance(
      EquipmentHealthSeverity severity, NightshadeColors colors) {
    switch (severity) {
      case EquipmentHealthSeverity.info:
        return (LucideIcons.checkCircle2, colors.success);
      case EquipmentHealthSeverity.warning:
        return (LucideIcons.alertTriangle, colors.warning);
      case EquipmentHealthSeverity.critical:
        return (LucideIcons.alertOctagon, colors.error);
    }
  }
}

// =============================================================================
// Device Heartbeat Chip
// =============================================================================

class _DeviceHeartbeatChip extends StatelessWidget {
  final DeviceHealthSnapshot snapshot;

  const _DeviceHeartbeatChip({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final statusColor = snapshot.isHealthy ? colors.success : colors.error;
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(
        snapshot.lastSuccessfulTimestampMs);
    final age = DateTime.now().difference(lastSeen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatDeviceId(snapshot.deviceId),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                snapshot.isHealthy
                    ? 'OK - ${_formatAge(age)} ago'
                    : 'Unhealthy - last seen ${_formatAge(age)} ago',
                style: TextStyle(
                  fontSize: 9,
                  color: snapshot.isHealthy
                      ? colors.textMuted
                      : colors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Extract a human-readable name from device IDs like "native:zwo:0" or
  /// "indi:host:port:device_name".
  static String _formatDeviceId(String deviceId) {
    final parts = deviceId.split(':');
    // Use the last meaningful segment as the display name
    if (parts.length >= 3) {
      return parts.sublist(1).join(':');
    }
    return deviceId;
  }

  static String _formatAge(Duration age) {
    if (age.inDays > 0) return '${age.inDays}d';
    if (age.inHours > 0) return '${age.inHours}h';
    if (age.inMinutes > 0) return '${age.inMinutes}m';
    return '${age.inSeconds}s';
  }
}

// =============================================================================
// Health Error Content
// =============================================================================

class _HealthErrorContent extends StatelessWidget {
  final Object error;

  const _HealthErrorContent({required this.error});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.error.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertOctagon, size: 16, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Failed to load health report: $error',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
