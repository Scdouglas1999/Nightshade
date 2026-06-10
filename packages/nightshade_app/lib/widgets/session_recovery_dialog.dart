import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog for recovering interrupted imaging sessions
class SessionRecoveryDialog extends ConsumerWidget {
  final List<SessionRecoveryInfo> incompleteSessions;

  const SessionRecoveryDialog({
    super.key,
    required this.incompleteSessions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.alertCircle,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Incomplete Sessions Found'),
        ],
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 600,
          preferredHeight: 500,
          minWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following imaging session(s) were not properly closed. '
              'Would you like to resume or discard them?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: incompleteSessions.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final session = incompleteSessions[index];
                  return _SessionCard(
                    session: session,
                    onRecover: () {
                      Navigator.of(context).pop();
                      _recoverSession(ref, session);
                    },
                    onDiscard: () async {
                      await _discardSession(ref, session);
                      if (incompleteSessions.length == 1) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Non-destructive escape hatch: the previous version forced the
        // user to either discard everything or interact with every row.
        // "Decide Later" closes the dialog without touching the sessions
        // so they remain available via whatever entry-point originally
        // surfaced this dialog (dashboard "Recover sessions" + startup
        // auto-open).
        NightshadeButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Decide Later',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => _confirmAndDiscardAll(context, ref),
          label: 'Discard All',
          variant: ButtonVariant.destructive,
          size: ButtonSize.small,
        ),
      ],
    );
  }

  Future<void> _confirmAndDiscardAll(
      BuildContext context, WidgetRef ref) async {
    final count = incompleteSessions.length;
    final sessionWord = count == 1 ? 'session' : 'sessions';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard all sessions?'),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            ctx,
            designMaxWidth: 440,
          ),
          child: Text(
            'Discard $count $sessionWord? Their data will be marked '
            "aborted and you won't be able to resume them.",
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          NightshadeButton(
            label: 'Discard',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Track per-session failures so a single failed mark-aborted call
    // doesn't silently leave the user thinking everything was discarded.
    // Errors are a feature: surface them.
    final failures = <SessionRecoveryInfo>[];
    for (final session in incompleteSessions) {
      try {
        final sessionService = ref.read(sessionServiceProvider);
        await sessionService.markSessionAborted(session.sessionId);
      } catch (_) {
        failures.add(session);
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();

    if (failures.isNotEmpty && ref.context.mounted) {
      final colors = NightshadeColors.of(ref.context);
      ScaffoldMessenger.of(ref.context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to discard ${failures.length} of $count '
            '$sessionWord.',
          ),
          backgroundColor: colors.error,
        ),
      );
    }
  }

  Future<void> _recoverSession(
      WidgetRef ref, SessionRecoveryInfo session) async {
    try {
      final sessionNotifier = ref.read(sessionStateProvider.notifier);
      await sessionNotifier.recoverSession(session);

      // Show success message
      if (ref.context.mounted) {
        final colors = NightshadeColors.of(ref.context);
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: Text(
              'Session recovered: ${session.sessionName ?? "Session ${session.sessionId}"}',
            ),
            backgroundColor: colors.success,
          ),
        );
      }
    } catch (e) {
      if (ref.context.mounted) {
        final colors = NightshadeColors.of(ref.context);
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: const Text('Could not recover the session. Please try again.'),
            backgroundColor: colors.error,
          ),
        );
      }
    }
  }

  Future<void> _discardSession(
      WidgetRef ref, SessionRecoveryInfo session) async {
    try {
      final sessionService = ref.read(sessionServiceProvider);
      await sessionService.markSessionAborted(session.sessionId);
    } catch (e) {
      if (ref.context.mounted) {
        final colors = NightshadeColors.of(ref.context);
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: const Text('Could not discard the session. Please try again.'),
            backgroundColor: colors.error,
          ),
        );
      }
    }
  }
}

class _SessionCard extends StatelessWidget {
  final SessionRecoveryInfo session;
  final VoidCallback onRecover;
  final VoidCallback onDiscard;

  const _SessionCard({
    required this.session,
    required this.onRecover,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NightshadeColors.of(context);
    final stats = session.stats;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session name and timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    session.sessionName ?? 'Session ${session.sessionId}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _formatDateTime(session.startTime),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            if (session.targetName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Target: ${session.targetName}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),

            // Statistics
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _StatChip(
                  icon: LucideIcons.camera,
                  label: _pluralize(stats.completedExposures, 'exposure'),
                ),
                _StatChip(
                  icon: LucideIcons.clock,
                  label: _formatDuration(session.duration),
                ),
                _StatChip(
                  icon: LucideIcons.timer,
                  label: _formatIntegration(stats.totalIntegrationSecs),
                ),
                if (stats.avgHfr != null)
                  _StatChip(
                    icon: LucideIcons.target,
                    label: 'HFR: ${stats.avgHfr!.toStringAsFixed(2)}',
                  ),
                if (stats.failedExposures > 0)
                  _StatChip(
                    icon: LucideIcons.alertTriangle,
                    label: '${stats.failedExposures} failed',
                    color: colors.warning,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NightshadeButton(
                  onPressed: onDiscard,
                  icon: LucideIcons.trash2,
                  label: 'Discard',
                  variant: ButtonVariant.destructive,
                  size: ButtonSize.small,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  onPressed: onRecover,
                  icon: LucideIcons.rotateCcw,
                  label: 'Resume',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m';
    }
    // Session opened and closed in well under a minute; "0m" reads as
    // "didn't run" which is wrong — there's clearly *some* runtime or we
    // wouldn't be in the recovery dialog.
    if (totalSeconds > 0) {
      return '<1m';
    }
    return '0m';
  }

  String _formatIntegration(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m total';
    }
    if (minutes > 0) {
      return '${minutes}m total';
    }
    // Sub-minute integration is meaningful (e.g. a couple of 10-second
    // calibration frames). Avoid the misleading "0m total" by reporting
    // the actual seconds when we have any, and "no integration" when we
    // genuinely have none.
    if (seconds > 0) {
      final secs = seconds.round();
      return _pluralize(secs, 'second', suffix: ' total');
    }
    return 'no integration';
  }

  String _pluralize(int count, String singular,
      {String? plural, String suffix = ''}) {
    final word = count == 1 ? singular : (plural ?? '${singular}s');
    return '$count $word$suffix';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _StatChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = color ?? theme.colorScheme.primary;

    return Chip(
      avatar: Icon(icon, size: 14, color: chipColor),
      label: Text(label),
      labelStyle: theme.textTheme.bodySmall,
      visualDensity: VisualDensity.compact,
    );
  }
}
