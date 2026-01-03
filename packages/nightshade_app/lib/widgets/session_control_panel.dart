import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Widget for session controls - start, end, status display
class SessionControlPanel extends ConsumerWidget {
  final VoidCallback? onStartSession;
  final VoidCallback? onEndSession;
  final bool showParkMountOption;

  const SessionControlPanel({
    super.key,
    this.onStartSession,
    this.onEndSession,
    this.showParkMountOption = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final isActive = sessionState.isActive;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? LucideIcons.activity : LucideIcons.circle,
                  size: 16,
                  color: isActive ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Session',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (isActive) _buildSessionStatus(context, ref),
              ],
            ),
            const SizedBox(height: 12),
            if (isActive) _buildActiveSessionInfo(context, ref),
            const SizedBox(height: 12),
            _buildActionButtons(context, ref, isActive),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionStatus(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final duration = ref.watch(sessionDurationProvider);

    return Chip(
      avatar: const Icon(LucideIcons.clock, size: 14),
      label: Text(duration),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildActiveSessionInfo(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sessionState.targetName != null)
          _InfoRow(
            icon: LucideIcons.target,
            label: 'Target',
            value: sessionState.targetName!,
          ),
        const SizedBox(height: 4),
        _InfoRow(
          icon: LucideIcons.image,
          label: 'Exposures',
          value: '${sessionState.completedExposures}'
              '${sessionState.totalExposures > 0 ? ' / ${sessionState.totalExposures}' : ''}',
        ),
        const SizedBox(height: 4),
        _InfoRow(
          icon: LucideIcons.timer,
          label: 'Integration',
          value: _formatIntegration(sessionState.totalIntegrationSecs),
        ),
        if (sessionState.failedExposures > 0) ...[
          const SizedBox(height: 4),
          _InfoRow(
            icon: LucideIcons.alertTriangle,
            label: 'Failed',
            value: '${sessionState.failedExposures}',
            valueColor: Colors.orange,
          ),
        ],
        if (sessionState.avgHfr != null) ...[
          const SizedBox(height: 4),
          _InfoRow(
            icon: LucideIcons.focus,
            label: 'Avg HFR',
            value: sessionState.avgHfr!.toStringAsFixed(2),
          ),
        ],
        const SizedBox(height: 8),
        // Progress bar
        if (sessionState.totalExposures > 0) ...[
          LinearProgressIndicator(
            value: ref.watch(sessionProgressProvider),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 4),
          Text(
            '${(ref.watch(sessionProgressProvider) * 100).toStringAsFixed(0)}% complete',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, bool isActive) {
    return Row(
      children: [
        if (isActive) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showEndSessionDialog(context, ref),
              icon: const Icon(LucideIcons.stopCircle, size: 16),
              label: const Text('End Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ] else ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onStartSession,
              icon: const Icon(LucideIcons.playCircle, size: 16),
              label: const Text('Start Session'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showEndSessionDialog(BuildContext context, WidgetRef ref) async {
    final parkMount = showParkMountOption ? false : null;
    bool shouldParkMount = parkMount ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.stopCircle),
            SizedBox(width: 12),
            Text('End Session'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to end the current imaging session?'),
            const SizedBox(height: 16),
            if (showParkMountOption)
              StatefulBuilder(
                builder: (context, setState) => CheckboxListTile(
                  title: const Text('Park mount after ending session'),
                  value: shouldParkMount,
                  onChanged: (value) {
                    setState(() => shouldParkMount = value ?? false);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        // End the session
        await ref.read(sessionStateProvider.notifier).endSession();

        // Park mount if requested
        if (shouldParkMount && context.mounted) {
          final deviceService = ref.read(deviceServiceProvider);
          try {
            await deviceService.parkMount();
          } catch (e) {
            // Ignore errors parking mount - session has already ended
            print('Warning: Failed to park mount: $e');
          }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session ended successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Call callback if provided
        onEndSession?.call();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to end session: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatIntegration(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = (seconds % 60).toInt();

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
