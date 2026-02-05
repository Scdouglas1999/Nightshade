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
          Icon(LucideIcons.alertCircle, color: Theme.of(context).colorScheme.primary),
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
        NightshadeButton(
          onPressed: () async {
            // Discard all
            for (final session in incompleteSessions) {
              await _discardSession(ref, session);
            }
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
          label: 'Discard All',
          variant: ButtonVariant.destructive,
          size: ButtonSize.small,
        ),
      ],
    );
  }

  Future<void> _recoverSession(WidgetRef ref, SessionRecoveryInfo session) async {
    try {
      final sessionNotifier = ref.read(sessionStateProvider.notifier);
      await sessionNotifier.recoverSession(session);

      // Show success message
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: Text('Session recovered: ${session.sessionName ?? "Session ${session.sessionId}"}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: Text('Failed to recover session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _discardSession(WidgetRef ref, SessionRecoveryInfo session) async {
    try {
      final sessionService = ref.read(sessionServiceProvider);
      await sessionService.markSessionAborted(session.sessionId);
    } catch (e) {
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context).showSnackBar(
          SnackBar(
            content: Text('Failed to discard session: $e'),
            backgroundColor: Colors.red,
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
                  label: '${stats.completedExposures} exposures',
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
                    color: Colors.orange,
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
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatIntegration(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m total';
    }
    return '${minutes}m total';
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
