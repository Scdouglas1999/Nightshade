import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../widgets/notes_panel.dart';
import '../widgets/post_session_stats_dialog.dart';
import '../widgets/replay_debug_screen.dart';
import '../widgets/sequence_diff_dialog.dart';

/// One-shot "open this run on first paint" hint for the history tab.
///
/// The Run Dashboard idle-state's "Jump to last run" button writes a run
/// id here and switches the active tab to History. The history tab
/// reads + clears this provider the first time it builds with a value,
/// then opens the post-session stats dialog for that run.
///
/// Cleared to `null` immediately after consumption so re-entering the
/// History tab doesn't re-open the dialog.
final historyOpenRunIdProvider = StateProvider<int?>((ref) => null);

class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  bool _consumedOpenHint = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final runsAsync = ref.watch(sequenceRunsProvider);
    final openRunId = ref.watch(historyOpenRunIdProvider);

    // If the dashboard asked us to open a specific run, honor it once.
    // We schedule the dialog via post-frame because we cannot call
    // showDialog during a build.
    if (openRunId != null && !_consumedOpenHint && runsAsync.hasValue) {
      _consumedOpenHint = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final runs = runsAsync.value!;
        // Reset the hint regardless so a subsequent open clears.
        ref.read(historyOpenRunIdProvider.notifier).state = null;
        SequenceRun? match;
        for (final r in runs) {
          if (r.id == openRunId) {
            match = r;
            break;
          }
        }
        if (match == null) return;
        ParsedRunStats? stats;
        try {
          stats = ParsedRunStats.fromJson(match.statsJson);
        } on Object catch (e) {
          // Why: legacy/corrupted statsJson should not block the rest of the
          // history-tab open flow. We log so the user-visible "no stats"
          // outcome is traceable to a parse error in diagnostics.
          debugPrint('history_tab: ParsedRunStats.fromJson failed: $e');
        }
        if (stats == null) return;
        showDialog(
          context: context,
          builder: (_) => PostSessionStatsDialog(
            colors: colors,
            sequenceName: match!.sequenceName,
            startedAt: match.startedAt,
            endedAt: match.endedAt,
            status: match.status,
            stats: stats!,
          ),
        );
      });
    }

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
                  return const EmptyState(
                    icon: LucideIcons.history,
                    title: 'No runs yet',
                    body: 'Execute a sequence to see its history here.',
                  );
                }
                return ListView.separated(
                  itemCount: runs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _RunCard(colors: colors, run: runs[index]);
                  },
                );
              },
              loading: () => Center(
                  child: CircularProgressIndicator(color: colors.primary)),
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
                decoration: NightshadeDecorations.tintedBadge(
                  statusColor,
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
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
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
                const SizedBox(width: 8),
                // Wave 7 — Campaign rollup badge. Resolves the per-run
                // primary target (the first key of the targetBreakdown
                // blob) into a [CampaignRollup] via the all-targets
                // provider. Hidden when (a) the run has no target
                // breakdown, (b) the target has no other sessions
                // (rollup.sessionCount <= 1), or (c) the lookup fails.
                if (stats.targetBreakdown.isNotEmpty)
                  _CampaignBadge(
                    targetName: stats.targetBreakdown.keys.first,
                  ),
              ],

              const SizedBox(width: 8),

              // Wave 6 Agent 5 — "Diff vs previous" affordance. Opens
              // the structural diff between the sequence backing this
              // run and its previous run. Disabled (via tooltip-only
              // hint) when the run has no linked sequence id; the
              // dialog itself also guards for that case.
              if (run.sequenceId != null)
                IconButton(
                  onPressed: () => SequenceDiffDialog.showForRun(
                    context,
                    ref,
                    run: run,
                  ),
                  icon: const Icon(LucideIcons.gitCompare, size: 16),
                  tooltip: 'Diff vs previous run',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),

              // Wave 8 Replay Debug — open the chronological decision
              // feed for this run. The badge surfaces the count so the
              // user can see at a glance whether the run has any
              // recorded decisions before opening (older runs that
              // pre-date Wave 8 will show 0).
              Consumer(builder: (context, ref, _) {
                final countAsync = ref.watch(
                  decisionCountForRunProvider(run.id),
                );
                final count = countAsync.maybeWhen(
                  data: (n) => n,
                  orElse: () => 0,
                );
                return IconButton(
                  onPressed: () => ReplayDebugScreen.push(
                    context,
                    sequenceRunId: run.id,
                    sequenceName: run.sequenceName,
                    startedAt: run.startedAt,
                    endedAt: run.endedAt,
                  ),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(LucideIcons.history, size: 16),
                      if (count > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 9,
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: count == 0
                      ? 'Open replay (no decisions recorded)'
                      : 'Open replay ($count decisions)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                );
              }),

              // Wave 6 Agent 5 — quick "open notes" affordance keyed
              // on this run id. Notes attached to the run from any
              // surface (target card, session report) appear here
              // because the underlying provider streams from a single
              // database row set.
              Consumer(builder: (context, ref, _) {
                final notesAsync = ref.watch(notesForRunProvider(run.id));
                final count = notesAsync.maybeWhen(
                  data: (notes) => notes.length,
                  orElse: () => 0,
                );
                return IconButton(
                  onPressed: () => _openNotesForRun(context, ref, run),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(LucideIcons.bookOpen, size: 16),
                      if (count > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 9,
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: count == 0 ? 'Add note' : 'Notes ($count)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                );
              }),

              const SizedBox(width: 4),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: NightshadeDecorations.tintedBadge(
                  statusColor,
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

  /// Resolve the primary target name for the run (best-effort: the
  /// stats blob's first target breakdown key) and pop the per-run
  /// notes drawer.
  Future<void> _openNotesForRun(
      BuildContext context, WidgetRef ref, SequenceRun run) async {
    final colors = NightshadeColors.of(context);
    String? primaryTarget;
    try {
      final stats = ParsedRunStats.fromJson(run.statsJson);
      if (stats.targetBreakdown.isNotEmpty) {
        primaryTarget = stats.targetBreakdown.keys.first;
      }
    } on Object catch (e) {
      // Why: stats blob may be missing/corrupt for legacy runs — fall back to
      // the sequence name (assigned below). Logged so the fallback isn't silent.
      debugPrint('history_tab: notes-drawer stats parse failed: $e');
    }
    primaryTarget ??= run.sequenceName;
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 640,
      designHeight: 600,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.border),
        ),
        child: SizedBox(
          width: dialogSize.width,
          height: dialogSize.height,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.bookOpen, size: 20, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Notes — ${run.sequenceName}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: RunNotesSection(
                  sequenceRunId: run.id,
                  targetId: primaryTarget!,
                  colors: colors,
                  embedded: true,
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

/// Wave 7 — Per-run campaign rollup badge.
///
/// Surfaces "Campaign: 6h total across 3 sessions" when the target has
/// been imaged on more than one night. Silently hides when the target
/// is unknown, has only one session, or the rollup lookup fails.
class _CampaignBadge extends ConsumerWidget {
  final String targetName;

  const _CampaignBadge({required this.targetName});

  String _formatHours(double seconds) {
    final hours = seconds / 3600.0;
    return '${hours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final rollupAsync = ref.watch(campaignRollupByNameProvider(targetName));
    return rollupAsync.maybeWhen(
      data: (rollup) {
        if (rollup == null || rollup.sessionCount <= 1) {
          return const SizedBox.shrink();
        }
        final total = _formatHours(rollup.totalCapturedIntegrationSecs);
        return Tooltip(
          message: 'Campaign: $total across ${rollup.sessionCount} sessions',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 4),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.layers, size: 12, color: colors.primary),
                const SizedBox(width: 4),
                Text(
                  '$total / ${rollup.sessionCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
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
