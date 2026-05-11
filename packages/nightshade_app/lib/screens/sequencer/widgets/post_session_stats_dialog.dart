import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog showing detailed post-session statistics for a sequence run.
class PostSessionStatsDialog extends StatelessWidget {
  final NightshadeColors colors;
  final String sequenceName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final ParsedRunStats stats;

  const PostSessionStatsDialog({
    super.key,
    required this.colors,
    required this.sequenceName,
    required this.startedAt,
    this.endedAt,
    required this.status,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm:ss');

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.barChart3, size: 22, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          sequenceName,
                          style:
                              TextStyle(fontSize: 13, color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, color: colors.textMuted),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time info
                    _Section(
                      colors: colors,
                      title: 'Timing',
                      icon: LucideIcons.clock,
                      children: [
                        _StatRow(
                            colors: colors,
                            label: 'Started',
                            value: dateFormat.format(startedAt)),
                        if (endedAt != null)
                          _StatRow(
                              colors: colors,
                              label: 'Ended',
                              value: dateFormat.format(endedAt!)),
                        _StatRow(
                            colors: colors,
                            label: 'Wall Clock',
                            value: stats.formatDuration(stats.wallClockSecs)),
                        _StatRow(
                            colors: colors,
                            label: 'Integration Time',
                            value: stats.formatDuration(stats.integrationSecs)),
                        _StatRow(
                            colors: colors,
                            label: 'Overhead',
                            value: stats.formatDuration(stats.overheadSecs)),
                        if (stats.wallClockSecs > 0)
                          _StatRow(
                            colors: colors,
                            label: 'Efficiency',
                            value:
                                '${(stats.integrationSecs / stats.wallClockSecs * 100).toStringAsFixed(1)}%',
                          ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Frames
                    _Section(
                      colors: colors,
                      title: 'Frames',
                      icon: LucideIcons.camera,
                      children: [
                        _StatRow(
                            colors: colors,
                            label: 'Captured',
                            value: '${stats.framesCaptured}'),
                        _StatRow(
                            colors: colors,
                            label: 'Rejected',
                            value: '${stats.framesRejected}',
                            valueColor: stats.framesRejected > 0
                                ? colors.warning
                                : null),
                        _StatRow(
                            colors: colors,
                            label: 'Accepted',
                            value:
                                '${stats.framesCaptured - stats.framesRejected}'),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Operations
                    _Section(
                      colors: colors,
                      title: 'Operations',
                      icon: LucideIcons.settings,
                      children: [
                        _StatRow(
                            colors: colors,
                            label: 'Autofocus Runs',
                            value: '${stats.autofocusRuns}'),
                        _StatRow(
                            colors: colors,
                            label: 'Meridian Flips',
                            value: '${stats.meridianFlips}'),
                        _StatRow(
                            colors: colors,
                            label: 'Dithers',
                            value: '${stats.ditherCount}'),
                        _StatRow(
                            colors: colors,
                            label: 'Trigger Fires',
                            value: '${stats.triggerFires}'),
                      ],
                    ),

                    // Target/Filter Breakdown
                    if (stats.targetBreakdown.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Section(
                        colors: colors,
                        title: 'Target Breakdown',
                        icon: LucideIcons.target,
                        children: [
                          for (final te in stats.targetBreakdown.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                te.key,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            for (final fe in te.value.entries)
                              _StatRow(
                                colors: colors,
                                label:
                                    '  ${fe.key.isEmpty ? 'No filter' : fe.key}',
                                value:
                                    '${(fe.value['captured'] as num?)?.toInt() ?? 0} frames  |  '
                                    '${stats.formatDuration((fe.value['integrationSecs'] as num?)?.toDouble() ?? 0)}',
                              ),
                          ],
                        ],
                      ),
                    ],

                    // Errors
                    if (stats.errorMessages.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Section(
                        colors: colors,
                        title: 'Errors (${stats.errorMessages.length})',
                        icon: LucideIcons.alertTriangle,
                        titleColor: colors.error,
                        children: [
                          for (final msg in stats.errorMessages)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                msg,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final IconData icon;
  final Color? titleColor;
  final List<Widget> children;

  const _Section({
    required this.colors,
    required this.title,
    required this.icon,
    this.titleColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: titleColor ?? colors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: titleColor ?? colors.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatRow({
    required this.colors,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
