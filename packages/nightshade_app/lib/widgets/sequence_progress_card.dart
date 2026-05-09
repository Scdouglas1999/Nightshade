import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Mobile-optimized sequence progress card
class SequenceProgressCard extends ConsumerWidget {
  const SequenceProgressCard({super.key});

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(sequenceProgressProvider);
    final theme = Theme.of(context);
    final colors = Theme.of(context).extension<NightshadeColors>();

    // Safe color access with fallbacks
    final surfaceColor = colors?.surface ?? theme.cardColor;
    final borderColor = colors?.border ?? theme.colorScheme.outlineVariant;
    final textColor = colors?.textPrimary ??
        theme.textTheme.bodyLarge?.color ??
        theme.colorScheme.onSurface;
    final textSecondary = colors?.textSecondary ??
        theme.textTheme.bodyMedium?.color ??
        theme.colorScheme.onSurfaceVariant;
    final primaryColor = colors?.primary ?? theme.colorScheme.primary;

    // Don't show card if sequence is idle
    if (progress.state == SequenceExecutionState.idle) {
      return const SizedBox.shrink();
    }

    final progressPercent = progress.progressPercent;
    final estimatedRemaining = progress.estimatedRemainingSecs;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with status
          Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _getStatusColor(
                    progress.state,
                    colors,
                    primaryColor,
                    textSecondary,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _getStatusText(progress.state),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const Spacer(),
              // Overall progress percentage
              Text(
                '${(progressPercent * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Target and node info
          if (progress.currentTarget != null) ...[
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    progress.currentTarget!,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          if (progress.currentNodeName != null) ...[
            Row(
              children: [
                Icon(Icons.play_circle_outline, size: 16, color: textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    progress.currentNodeName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressPercent,
              backgroundColor: borderColor.withValues(alpha: 0.3),
              color: primaryColor,
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 12),

          // Exposure info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Completed exposures
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frames',
                    style: TextStyle(
                      fontSize: 10,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${progress.completedExposures}/${progress.totalExposures}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),

              // Integration time
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Integration',
                    style: TextStyle(
                      fontSize: 10,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(progress.completedIntegrationSecs),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),

              // Time remaining
              if (estimatedRemaining != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Remaining',
                      style: TextStyle(
                        fontSize: 10,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDuration(estimatedRemaining),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Current filter
          if (progress.currentFilter != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.filter_alt, size: 14, color: textSecondary),
                const SizedBox(width: 6),
                Text(
                  progress.currentFilter!,
                  style: TextStyle(
                    fontSize: 11,
                    color: textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],

          // Status message
          if (progress.message != null && progress.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                progress.message!,
                style: TextStyle(
                  fontSize: 11,
                  color: textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(
    SequenceExecutionState state,
    NightshadeColors? colors,
    Color primaryColor,
    Color mutedColor,
  ) {
    switch (state) {
      case SequenceExecutionState.idle:
        return colors?.textMuted ?? mutedColor;
      case SequenceExecutionState.running:
        return colors?.success ?? primaryColor;
      case SequenceExecutionState.paused:
        return colors?.warning ?? primaryColor;
      case SequenceExecutionState.stopping:
        return colors?.error ?? primaryColor;
      case SequenceExecutionState.completed:
        return colors?.info ?? primaryColor;
      case SequenceExecutionState.failed:
        return colors?.error ?? primaryColor;
    }
  }

  String _getStatusText(SequenceExecutionState state) {
    switch (state) {
      case SequenceExecutionState.idle:
        return 'Idle';
      case SequenceExecutionState.running:
        return 'Running';
      case SequenceExecutionState.paused:
        return 'Paused';
      case SequenceExecutionState.stopping:
        return 'Stopping';
      case SequenceExecutionState.completed:
        return 'Completed';
      case SequenceExecutionState.failed:
        return 'Failed';
    }
  }
}
