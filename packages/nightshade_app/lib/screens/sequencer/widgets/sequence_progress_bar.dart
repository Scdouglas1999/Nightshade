import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SequenceProgressBar extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const SequenceProgressBar({super.key, required this.colors});

  @override
  ConsumerState<SequenceProgressBar> createState() => _SequenceProgressBarState();
}

class _SequenceProgressBarState extends ConsumerState<SequenceProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(sequenceProgressProvider);
    final isPaused = ref.watch(sequenceExecutionStateProvider) == SequenceExecutionState.paused;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.colors.primary.withValues(alpha: 0.05 + _pulseController.value * 0.03),
                widget.colors.accent.withValues(alpha: 0.05 + _pulseController.value * 0.03),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: widget.colors.border),
            ),
          ),
          child: Row(
            children: [
              // Current node indicator
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    if (isPaused)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: widget.colors.warning.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.pause,
                              size: 12,
                              color: widget.colors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'PAUSED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: widget.colors.warning,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      _PulsingIndicator(colors: widget.colors),
                    
                    const SizedBox(width: 12),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            progress.currentNodeName ?? 'Starting...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (progress.message != null)
                            Text(
                              progress.message!,
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.colors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Target and filter
              if (progress.currentTarget != null || progress.currentFilter != null) ...[
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: widget.colors.border,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (progress.currentTarget != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.target,
                            size: 12,
                            color: widget.colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            progress.currentTarget!,
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    if (progress.currentFilter != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.circle,
                            size: 12,
                            color: widget.colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            progress.currentFilter!,
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],

              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: widget.colors.border,
              ),

              // Progress bar with percentage
              SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.colors.textMuted,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${progress.completedExposures}/${progress.totalExposures}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: widget.colors.textSecondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.colors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(progress.progressPercent * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: widget.colors.primary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Overall progress bar
                    Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: widget.colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.progressPercent.clamp(0.0, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.colors.primary,
                                  widget.colors.accent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.colors.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Integration progress overlay
                        if (progress.totalIntegrationSecs > 0)
                          FractionallySizedBox(
                            widthFactor: (progress.completedIntegrationSecs / progress.totalIntegrationSecs).clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: widget.colors.border,
              ),

              // Time info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.timer,
                        size: 12,
                        color: widget.colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(progress.elapsedSecs),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (progress.estimatedRemainingSecs != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.hourglass,
                          size: 12,
                          color: widget.colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '~${_formatDuration(progress.estimatedRemainingSecs!)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.colors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulsingIndicator extends StatefulWidget {
  final NightshadeColors colors;

  const _PulsingIndicator({required this.colors});

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
      duration: const Duration(milliseconds: 1000),
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
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.colors.success,
            boxShadow: [
              BoxShadow(
                color: widget.colors.success.withValues(alpha: 0.5 * (1 - _controller.value)),
                blurRadius: 4 + _controller.value * 8,
                spreadRadius: _controller.value * 4,
              ),
            ],
          ),
        );
      },
    );
  }
}



