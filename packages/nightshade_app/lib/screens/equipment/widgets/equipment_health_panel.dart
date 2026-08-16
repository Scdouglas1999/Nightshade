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
    final colors = NightshadeColors.of(context);
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

// Header bar (always visible)

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
        decoration: NightshadeDecorations.tintedBadge(
          colors.warning,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Text(
          '$warningCount ${warningCount == 1 ? 'issue' : 'issues'}',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: colors.warning,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(LucideIcons.heartPulse, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'System Health',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  reportAsync.when(
                    data: (report) => _ScoreBadge(
                      score: report.score,
                      assessed: report.assessed,
                    ),
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
                  ..._warningCountWidgets(reportAsync, colors),
                ],
              ),
            ),
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

// Score badge

class _ScoreBadge extends StatelessWidget {
  final double score;

  /// False when there is no session history and no connected device, i.e. the
  /// degradation score had nothing to measure. Rendering the raw 100 then reads
  /// as "Excellent" on a rig that cannot even capture yet.
  final bool assessed;

  const _ScoreBadge({required this.score, this.assessed = true});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    if (!assessed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: NightshadeDecorations.statusChip(
          colors.textMuted,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        ),
        child: Text(
          'Not assessed',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
      );
    }
    final (badgeColor, label) = _scoreAppearance(score, colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: NightshadeDecorations.statusChip(
        badgeColor,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
              fontSize: NightshadeTypography.fontSize10,
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

// Health detail content (shown when expanded)

class _HealthDetailContent extends StatelessWidget {
  final EquipmentHealthReport report;
  final List<DeviceHealthSnapshot> deviceSnapshots;

  const _HealthDetailContent({
    required this.report,
    required this.deviceSnapshots,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score gauge + summary row
          _ScoreGaugeRow(score: report.score, assessed: report.assessed),
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
                fontSize: NightshadeTypography.fontSize10,
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

// Score gauge row

class _ScoreGaugeRow extends StatelessWidget {
  final double score;
  final bool assessed;

  const _ScoreGaugeRow({required this.score, this.assessed = true});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    // Un-assessed: show an empty muted gauge and a dash rather than a full
    // green bar at 100/100, which claimed a perfect rig before a single frame
    // had ever been captured.
    final (gaugeColor, _) = assessed
        ? _ScoreBadge._scoreAppearance(score, colors)
        : (colors.textMuted, '');

    return Row(
      children: [
        // Score number
        Text(
          assessed ? '${score.round()}' : '--',
          style: NightshadeTypography.telemetryLg.copyWith(
            fontWeight: FontWeight.w700,
            color: gaugeColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '/100',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize14,
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
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
                child: LinearProgressIndicator(
                  value: assessed ? score / 100.0 : 0.0,
                  minHeight: 6,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assessed
                    ? _scoreDescription(score)
                    : 'Not assessed yet — needs a completed session or a '
                        'connected device.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
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

// Insight card

class _InsightCard extends StatelessWidget {
  final EquipmentHealthInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final (iconData, iconColor) = _severityAppearance(insight.severity, colors);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                  style: NightshadeTypography.h6
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.message,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
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

// Device heartbeat chip

class _DeviceHeartbeatChip extends ConsumerWidget {
  final DeviceHealthSnapshot snapshot;

  const _DeviceHeartbeatChip({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final statusColor = snapshot.isHealthy ? colors.success : colors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _resolveDeviceName(ref, snapshot),
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.labelStrongSm
                      .copyWith(color: colors.textPrimary),
                ),
                Text(
                  _statusLine(snapshot),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize9,
                    color: snapshot.isHealthy ? colors.textMuted : colors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The friendly model name for the snapshot's device (e.g. "ZWO
  /// ASI1600MM-Cool"), resolved from the discovery cache so System Health
  /// matches the model names shown everywhere else instead of a raw driver-id
  /// segment. Falls back to the name the connected device reported, then to the
  /// id-pattern name.
  String _resolveDeviceName(WidgetRef ref, DeviceHealthSnapshot snapshot) {
    final deviceId = snapshot.deviceId;
    final discovered = ref.watch(unifiedDiscoveryProvider).rawDevices;
    for (final device in discovered) {
      if (device.id == deviceId &&
          device.name.isNotEmpty &&
          device.name != deviceId) {
        return device.name;
      }
    }
    final label = snapshot.deviceLabel;
    if (label != null && label.isNotEmpty && label != deviceId) return label;
    return friendlyNameFromDeviceId(deviceId);
  }

  /// What the chip says under the device name.
  ///
  /// Only the camera notifier records a successful-communication timestamp, so
  /// every other device arrives here with zero. An absent timestamp is UNKNOWN,
  /// not maximally stale: rendering it as an age prints the epoch as a contact
  /// time, and the panel whose job is to notice a device going quiet has to say
  /// it does not know.
  static String _statusLine(DeviceHealthSnapshot snapshot) {
    final health = snapshot.isHealthy ? 'OK' : 'Unhealthy';
    if (snapshot.lastSuccessfulTimestampMs <= 0) {
      return '$health - last contact unknown';
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(snapshot.lastSuccessfulTimestampMs),
    );
    return snapshot.isHealthy
        ? 'OK - ${_formatAge(age)} ago'
        : 'Unhealthy - last seen ${_formatAge(age)} ago';
  }

  static String _formatAge(Duration age) {
    if (age.inDays > 0) return '${age.inDays}d';
    if (age.inHours > 0) return '${age.inHours}h';
    if (age.inMinutes > 0) return '${age.inMinutes}m';
    return '${age.inSeconds}s';
  }
}

// Health error content

class _HealthErrorContent extends StatelessWidget {
  final Object error;

  const _HealthErrorContent({required this.error});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                  fontSize: NightshadeTypography.fontSize12,
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
