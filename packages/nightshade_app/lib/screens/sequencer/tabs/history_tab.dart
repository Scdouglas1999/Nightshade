import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../widgets/post_session_stats_dialog.dart';

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final runsAsync = ref.watch(sequenceRunsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.history, size: 20, color: colors.primary),
              const SizedBox(width: 12),
              Text(
                'Execution History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Past sequence runs with statistics and performance data.',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
          const SizedBox(height: 24),

          // Content
          Expanded(
            child: runsAsync.when(
              data: (runs) {
                if (runs.isEmpty) {
                  return _EmptyState(colors: colors);
                }
                return ListView.separated(
                  itemCount: runs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _RunCard(colors: colors, run: runs[index]);
                  },
                );
              },
              loading: () =>
                  Center(child: CircularProgressIndicator(color: colors.primary)),
              error: (err, _) => Center(
                child: Text(
                  'Failed to load history: $err',
                  style: TextStyle(color: colors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.history, size: 48, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            'No runs yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Execute a sequence to see its history here.',
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceRun run;

  const _RunCard({required this.colors, required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');
    final status = run.status;
    final statusColor = _statusColor(status);
    final statusIcon = _statusIcon(status);

    ParsedRunStats? stats;
    try {
      stats = ParsedRunStats.fromJson(run.statsJson);
    } catch (_) {
      // Malformed stats JSON — show card without stats
    }

    final durationStr = run.endedAt != null
        ? _formatDuration(run.endedAt!.difference(run.startedAt))
        : 'In progress';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (stats != null) {
            showDialog(
              context: context,
              builder: (_) => PostSessionStatsDialog(
                colors: colors,
                sequenceName: run.sequenceName,
                startedAt: run.startedAt,
                endedAt: run.endedAt,
                status: run.status,
                stats: stats!,
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, size: 20, color: statusColor),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.sequenceName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(run.startedAt)}  |  $durationStr',
                      style:
                          TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),

              // Quick stats
              if (stats != null) ...[
                _StatChip(
                  colors: colors,
                  icon: LucideIcons.camera,
                  label: '${stats.framesCaptured}',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  colors: colors,
                  icon: LucideIcons.clock,
                  label: stats.formatDuration(stats.integrationSecs),
                ),
              ],

              const SizedBox(width: 8),

              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return colors.success;
      case 'failed':
        return colors.error;
      case 'aborted':
        return colors.warning;
      case 'running':
        return colors.info;
      default:
        return colors.textMuted;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return LucideIcons.checkCircle2;
      case 'failed':
        return LucideIcons.xCircle;
      case 'aborted':
        return LucideIcons.alertTriangle;
      case 'running':
        return LucideIcons.play;
      default:
        return LucideIcons.circle;
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final secs = d.inSeconds % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }
}

class _StatChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;

  const _StatChip({
    required this.colors,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
