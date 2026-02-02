import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Displays estimated completion time for the sequence with breakdown
class EstimatedCompletionWidget extends ConsumerWidget {
  final NightshadeColors colors;

  const EstimatedCompletionWidget({required this.colors, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    final executionState = ref.watch(sequenceExecutionStateProvider);

    if (sequence == null) return const SizedBox.shrink();

    final totalTime = sequence.totalIntegrationSecs;
    final estimatedCompletion = DateTime.now().add(Duration(seconds: totalTime.toInt()));
    final isRunning = executionState == SequenceExecutionState.running;
    final targetGroups = sequence.targetHeaders;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Completion time
          _InfoChip(
            colors: colors,
            icon: LucideIcons.clock,
            label: 'Finish',
            value: _formatCompletionTime(estimatedCompletion),
            isActive: isRunning,
          ),
          const SizedBox(width: 16),

          // Total duration
          _InfoChip(
            colors: colors,
            icon: LucideIcons.timer,
            label: 'Duration',
            value: _formatDuration(totalTime),
          ),
          const SizedBox(width: 16),

          // Total frames
          _InfoChip(
            colors: colors,
            icon: LucideIcons.camera,
            label: 'Frames',
            value: '${sequence.totalExposures}',
          ),
          const SizedBox(width: 16),

          // Targets with breakdown on hover
          if (targetGroups.isNotEmpty) ...[
            _TargetBreakdownChip(
              colors: colors,
              targets: targetGroups,
            ),
            const SizedBox(width: 16),
          ],

          const Spacer(),

          // Running indicator
          if (isRunning) ...[
            _PulsingIndicator(color: colors.success),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.success.withValues(alpha: 0.3)),
              ),
              child: Text(
                'RUNNING',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.success,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCompletionTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    return '$displayHour:$minute $period';
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }
}

/// Info chip widget for the completion bar
class _InfoChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final bool isActive;

  const _InfoChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isActive ? colors.success : colors.textMuted,
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: colors.textMuted,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? colors.success : colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Chip showing target count with hover breakdown
class _TargetBreakdownChip extends StatefulWidget {
  final NightshadeColors colors;
  final List<TargetHeaderNode> targets;

  const _TargetBreakdownChip({
    required this.colors,
    required this.targets,
  });

  @override
  State<_TargetBreakdownChip> createState() => _TargetBreakdownChipState();
}

class _TargetBreakdownChipState extends State<_TargetBreakdownChip> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) => _buildOverlay(),
        child: MouseRegion(
          onEnter: (_) => _overlayController.show(),
          onExit: (_) => _overlayController.hide(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.target,
                size: 14,
                color: widget.colors.textMuted,
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Targets',
                    style: TextStyle(
                      fontSize: 9,
                      color: widget.colors.textMuted,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.targets.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.chevronDown,
                        size: 12,
                        color: widget.colors.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      offset: const Offset(0, -8),
      child: MouseRegion(
        onEnter: (_) => _overlayController.show(),
        onExit: (_) => _overlayController.hide(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Target Breakdown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...widget.targets.map((target) => _buildTargetRow(target)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetRow(TargetHeaderNode target) {
    // Format coordinates for display
    final raStr = '${target.raHours.toStringAsFixed(2)}h';
    final decStr = '${target.decDegrees >= 0 ? '+' : ''}${target.decDegrees.toStringAsFixed(1)}°';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.colors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              target.targetName,
              style: TextStyle(
                fontSize: 11,
                color: widget.colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            raStr,
            style: TextStyle(
              fontSize: 10,
              color: widget.colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            decStr,
            style: TextStyle(
              fontSize: 10,
              color: widget.colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

}

/// Pulsing indicator for running state
class _PulsingIndicator extends StatefulWidget {
  final Color color;

  const _PulsingIndicator({required this.color});

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = (1 - _controller.value).clamp(0.3, 1.0);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: value * 0.6),
                blurRadius: 4 + (1 - value) * 6,
                spreadRadius: (1 - value) * 3,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Badge showing loop iteration progress
class LoopIterationBadge extends StatelessWidget {
  final int current;
  final int total;
  final NightshadeColors colors;

  const LoopIterationBadge({
    required this.current,
    required this.total,
    required this.colors,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final progress = current / total;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.2),
            colors.accent.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.lerp(colors.primary, colors.accent, progress)!,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.refresh,
            size: 12,
            color: Color.lerp(colors.primary, colors.accent, progress),
          ),
          const SizedBox(width: 4),
          Text(
            '$current/$total',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color.lerp(colors.primary, colors.accent, progress),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress indicator overlay for exposure/wait nodes
class NodeProgressIndicator extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final NightshadeColors colors;
  final bool isActive;

  const NodeProgressIndicator({
    required this.progress,
    required this.colors,
    this.isActive = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          // Progress bar background
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [progress, progress],
                  colors: [
                    isActive
                        ? colors.success.withValues(alpha: 0.15)
                        : colors.primary.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Active glow border
          if (isActive)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.success,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.success.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Active branch highlighter for the execution path
class ActiveBranchHighlight extends StatelessWidget {
  final bool isActive;
  final NightshadeColors colors;
  final Widget child;

  const ActiveBranchHighlight({
    required this.isActive,
    required this.colors,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return child;

    return Stack(
      children: [
        // Glow effect
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(-4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: colors.success.withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        ),
        // Actual content with border
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.success.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}
