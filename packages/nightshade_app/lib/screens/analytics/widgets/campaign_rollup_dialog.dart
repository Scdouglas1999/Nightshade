import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../sequencer/widgets/session_report_dialog.dart';

/// Multi-night campaign rollup dialog (Feature B).
///
/// Opens from the project tracking panel; renders per-filter goal progress,
/// session count + date range, mean HFR / seeing / effective imaging, and a
/// session list with deep-links into the per-session report (Feature A).
class CampaignRollupDialog extends ConsumerWidget {
  final int targetId;

  const CampaignRollupDialog({super.key, required this.targetId});

  static Future<void> show(BuildContext context, int targetId) {
    return showDialog<void>(
      context: context,
      builder: (_) => CampaignRollupDialog(targetId: targetId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final rollupAsync = ref.watch(campaignRollupProvider(targetId));

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: rollupAsync.when(
          data: (rollup) => _Body(rollup: rollup, colors: colors),
          loading: () => SizedBox(
            height: 200,
            child: Center(
                child: CircularProgressIndicator(color: colors.primary)),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 32, color: colors.error),
                const SizedBox(height: 12),
                Text(
                  'Could not build campaign rollup',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$err',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final CampaignRollup rollup;
  final NightshadeColors colors;

  const _Body({required this.rollup, required this.colors});

  String _formatHours(double seconds) {
    final hours = seconds / 3600.0;
    return '${hours.toStringAsFixed(1)}h';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _formatDateTime(DateTime dt) =>
      DateFormat('MMM d, yyyy HH:mm').format(dt);

  @override
  Widget build(BuildContext context) {
    final totalPct = rollup.totalPercentComplete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.target, size: 22, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Campaign Rollup',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      rollup.targetName,
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
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary cards.
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _SummaryTile(
                      label: 'Sessions',
                      value: '${rollup.sessionCount}',
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'Total integration',
                      value: _formatHours(rollup.totalCapturedIntegrationSecs),
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'First session',
                      value: _formatDate(rollup.firstSessionAt),
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'Last session',
                      value: _formatDate(rollup.lastSessionAt),
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'Mean HFR',
                      value:
                          rollup.meanSessionHfr?.toStringAsFixed(2) ?? '-',
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'Mean seeing',
                      value: rollup.meanSessionSeeing != null
                          ? '${rollup.meanSessionSeeing!.toStringAsFixed(2)}"'
                          : '-',
                      colors: colors,
                    ),
                    _SummaryTile(
                      label: 'Effective imaging',
                      value:
                          '${(rollup.meanEffectiveImagingFraction * 100).toStringAsFixed(1)}%',
                      colors: colors,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Overall progress.
                if (totalPct != null) ...[
                  _OverallProgress(
                    pct: totalPct,
                    captured: rollup.totalCapturedIntegrationSecs,
                    goal: rollup.totalGoalIntegrationSecs ?? 0,
                    colors: colors,
                    isComplete: rollup.isComplete,
                  ),
                  const SizedBox(height: 16),
                ],

                _SectionTitle(
                  title: 'Per-filter progress',
                  icon: LucideIcons.layers,
                  colors: colors,
                ),
                if (rollup.filters.isEmpty)
                  Text(
                    'No frames captured for this target yet.',
                    style:
                        TextStyle(fontSize: 13, color: colors.textMuted),
                  )
                else
                  for (final f in rollup.filters)
                    _FilterRow(filter: f, colors: colors),

                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Sessions',
                  icon: LucideIcons.history,
                  colors: colors,
                ),
                if (rollup.sessions.isEmpty)
                  Text(
                    'No sessions recorded for this target.',
                    style:
                        TextStyle(fontSize: 13, color: colors.textMuted),
                  )
                else
                  for (final s in rollup.sessions)
                    _SessionRow(
                      session: s,
                      colors: colors,
                      onOpenReport: () =>
                          SessionReportDialog.show(context, s.sessionId),
                      formatDateTime: _formatDateTime,
                    ),
              ],
            ),
          ),
        ),
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final NightshadeColors colors;

  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colors.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverallProgress extends StatelessWidget {
  final double pct;
  final double captured;
  final double goal;
  final bool isComplete;
  final NightshadeColors colors;

  const _OverallProgress({
    required this.pct,
    required this.captured,
    required this.goal,
    required this.isComplete,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = goal - captured;
    final remainingHours = remaining > 0 ? remaining / 3600.0 : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Overall',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(pct * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isComplete ? colors.success : colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete ? colors.success : colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Captured ${(captured / 3600.0).toStringAsFixed(1)}h of ${(goal / 3600.0).toStringAsFixed(1)}h goal | Remaining: ${remainingHours.toStringAsFixed(1)}h',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final CampaignFilterRollup filter;
  final NightshadeColors colors;

  const _FilterRow({required this.filter, required this.colors});

  @override
  Widget build(BuildContext context) {
    final pct = filter.percentComplete;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                filter.filter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              if (filter.hasGoal)
                Text(
                  '${filter.capturedFrames}/${filter.goalFrames} frames',
                  style:
                      TextStyle(fontSize: 12, color: colors.textSecondary),
                )
              else
                Text(
                  '${filter.capturedFrames} frames captured (no goal)',
                  style:
                      TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              const Spacer(),
              Text(
                '${(filter.capturedIntegrationSecs / 3600.0).toStringAsFixed(1)}h',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: colors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 1.0 ? colors.success : colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(pct * 100).toStringAsFixed(0)}% complete | ${filter.remainingFrames} frames remaining',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final CampaignSessionRef session;
  final NightshadeColors colors;
  final VoidCallback onOpenReport;
  final String Function(DateTime) formatDateTime;

  const _SessionRow({
    required this.session,
    required this.colors,
    required this.onOpenReport,
    required this.formatDateTime,
  });

  Color _statusColor() {
    switch (session.status.toLowerCase()) {
      case 'completed':
        return colors.success;
      case 'active':
        return colors.info;
      case 'aborted':
      case 'stopped':
        return colors.warning;
      case 'error':
      case 'failed':
        return colors.error;
      default:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationSecs = session.wallClockDuration.inSeconds;
    final durationLabel = durationSecs > 0
        ? '${(durationSecs / 3600.0).toStringAsFixed(2)}h wall'
        : '-';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenReport,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.sessionName ?? 'Session ${session.sessionId}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDateTime(session.startTime)} | $durationLabel | ${(session.sessionIntegrationSecs / 3600.0).toStringAsFixed(2)}h integration',
                      style:
                          TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              if (session.avgHfr != null)
                _Chip(
                  label: 'HFR',
                  value: session.avgHfr!.toStringAsFixed(2),
                  colors: colors,
                ),
              const SizedBox(width: 6),
              if (session.avgGuidingRms != null)
                _Chip(
                  label: 'RMS',
                  value: session.avgGuidingRms!.toStringAsFixed(2),
                  colors: colors,
                ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight,
                  size: 16, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _Chip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
