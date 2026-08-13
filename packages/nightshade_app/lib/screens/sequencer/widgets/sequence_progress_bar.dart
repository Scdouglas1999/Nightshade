import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'pulse_lifecycle_mixin.dart';
import 'run_dashboard/run_dashboard_format.dart';

class SequenceProgressBar extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const SequenceProgressBar({super.key, required this.colors});

  @override
  ConsumerState<SequenceProgressBar> createState() =>
      SequenceProgressBarState();
}

/// Static alpha value used to tint the progress bar background when the
/// sequence is paused. Picked so it sits inside the running pulse range
/// (0.05–0.08) but stays constant, so users get a calm, non-animating
/// warning-tinted background instead of a strobing primary-tinted one.
const double _kPausedBackgroundAlpha = 0.06;

class SequenceProgressBarState extends ConsumerState<SequenceProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  /// Test-only accessor for the background-pulse `AnimationController`.
  ///
  /// Exposed so widget tests can assert pause/resume behaviour without
  /// having to walk the subtree's `AnimatedBuilder`s (which now collide
  /// with framework-internal AnimatedBuilders backed by `ValueNotifier`).
  @visibleForTesting
  AnimationController get debugPulseControllerForTesting => _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    // Defer starting the pulse to build(), which knows the current
    // execution state. This keeps the controller idle if the widget
    // mounts while already paused.
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Sync the pulse controller with the current paused state.
  /// Called from build() so it reacts to any provider change that flips
  /// `isPaused`, without needing a separate `didUpdateWidget` (which would
  /// not fire on provider changes anyway since `widget` is unchanged).
  void _syncPulse({required bool isPaused}) {
    if (isPaused) {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    } else {
      if (!_pulseController.isAnimating) {
        // Resume from current value so we don't snap back to 0.
        _pulseController.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(sequenceProgressProvider);
    final isPaused = ref.watch(sequenceExecutionStateProvider) ==
        SequenceExecutionState.paused;

    // React to isPaused flips by starting/stopping the pulse controller.
    // Doing this in build() keeps it in lockstep with the watched provider
    // and means we never start the ticker until we know we're not paused.
    _syncPulse(isPaused: isPaused);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final backgroundColor = isPaused
            ? widget.colors.warning.withValues(alpha: _kPausedBackgroundAlpha)
            : widget.colors.primary.withValues(
                alpha: 0.05 + _pulseController.value * 0.03,
              );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: NightshadeDecorations.statusChip(
                          widget.colors.warning,
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
                          bordered: false,
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
                                fontSize: NightshadeTypography.fontSize10,
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
                            progress.currentNodeName ??
                                (isPaused
                                    ? 'Paused — no active node'
                                    : 'Starting...'),
                            style: NightshadeTypography.labelStrong
                                .copyWith(color: widget.colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (progress.message != null)
                            Text(
                              progress.message!,
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize11,
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
              if (progress.currentTarget != null ||
                  progress.currentFilter != null) ...[
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
                              fontSize: NightshadeTypography.fontSize11,
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
                              fontSize: NightshadeTypography.fontSize11,
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
                            fontSize: NightshadeTypography.fontSize10,
                            color: widget.colors.textMuted,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${progress.completedExposures}/${progress.totalExposures}',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize10,
                                fontWeight: FontWeight.w600,
                                color: widget.colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: NightshadeDecorations.statusChip(
                                widget.colors.primary,
                                borderRadius: BorderRadius.circular(
                                    NightshadeTokens.radiusInline4),
                                bordered: false,
                              ),
                              child: Text(
                                '${(progress.progressPercent * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize10,
                                  fontWeight: FontWeight.w700,
                                  color: widget.colors.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
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
                            borderRadius: BorderRadius.circular(
                                NightshadeTokens.radiusInline4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.progressPercent.clamp(0.0, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.colors.primary,
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                          ),
                        ),
                        // Integration progress overlay
                        if (progress.totalIntegrationSecs > 0)
                          FractionallySizedBox(
                            widthFactor: (progress.completedIntegrationSecs /
                                    progress.totalIntegrationSecs)
                                .clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                // absolute: lightening sheen over the filled progress bar
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    NightshadeTokens.radiusInline4),
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
                        DurationFormat.seconds(progress.elapsedSecs,
                            rounding: DurationRounding.truncate),
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: widget.colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (progress.estimatedRemainingSecs != null)
                    Tooltip(
                      // The estimate is planned integration only — it does
                      // not include pending autofocus / dither / meridian-flip
                      // overhead, so the finish time is a floor, not a promise.
                      message: 'Integration time only — excludes pending '
                          'autofocus, dither, and meridian-flip overhead.',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.hourglass,
                            size: 12,
                            color: widget.colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '~${DurationFormat.seconds(progress.estimatedRemainingSecs!, rounding: DurationRounding.truncate)}'
                            ' · done ~${formatTimeOfDay(DateTime.now().add(Duration(seconds: progress.estimatedRemainingSecs!.round())))}',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: widget.colors.textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
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
    with SingleTickerProviderStateMixin, PulseLifecycleMixin {
  late AnimationController _controller;

  @override
  AnimationController get pulseController => _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    startPulse();
  }

  @override
  void dispose() {
    stopPulseLifecycle();
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
            color: widget.colors.success.withValues(
              alpha: 0.5 + _controller.value * 0.5,
            ),
          ),
        );
      },
    );
  }
}
