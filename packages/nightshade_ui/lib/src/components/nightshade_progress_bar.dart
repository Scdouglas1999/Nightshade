import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Progress bar style variants
enum NightshadeProgressStyle {
  /// Standard progress bar
  standard,

  /// Thin progress bar (4px height)
  thin,

  /// Thick progress bar (12px height)
  thick,

  /// Segmented progress bar (shows discrete steps)
  segmented,
}

/// Progress bar state for status coloring
enum NightshadeProgressState {
  /// Normal progress (primary color)
  normal,

  /// Success state (success color)
  success,

  /// Warning state (warning color)
  warning,

  /// Error state (error color)
  error,

  /// Paused state (muted color)
  paused,
}

/// A customizable progress bar component.
///
/// Features:
/// - Multiple styles (standard, thin, thick, segmented)
/// - State-based coloring (normal, success, warning, error, paused)
/// - Optional label and percentage display
/// - Animated transitions
/// - Indeterminate mode for unknown progress
class NightshadeProgressBar extends StatelessWidget {
  const NightshadeProgressBar({
    super.key,
    required this.value,
    this.style = NightshadeProgressStyle.standard,
    this.state = NightshadeProgressState.normal,
    this.label,
    this.showPercentage = false,
    this.indeterminate = false,
    this.segments,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.animationDuration,
  });

  /// Progress value from 0.0 to 1.0
  final double value;

  /// Visual style of the progress bar
  final NightshadeProgressStyle style;

  /// State for automatic color selection
  final NightshadeProgressState state;

  /// Optional label shown above the progress bar
  final String? label;

  /// Whether to show percentage text
  final bool showPercentage;

  /// Whether to show indeterminate animation
  final bool indeterminate;

  /// Number of segments (for segmented style)
  final int? segments;

  /// Custom height override
  final double? height;

  /// Custom background color
  final Color? backgroundColor;

  /// Custom foreground color
  final Color? foregroundColor;

  /// Custom animation duration
  final Duration? animationDuration;

  double get _height {
    if (height != null) return height!;
    return switch (style) {
      NightshadeProgressStyle.thin => 4.0,
      NightshadeProgressStyle.standard => 8.0,
      NightshadeProgressStyle.thick => 12.0,
      NightshadeProgressStyle.segmented => 8.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final bgColor = backgroundColor ?? colors.surfaceAlt;
    final fgColor = foregroundColor ?? _getStateColor(colors);

    Widget progressBar;

    if (indeterminate) {
      progressBar = _IndeterminateProgressBar(
        height: _height,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      );
    } else if (style == NightshadeProgressStyle.segmented && segments != null) {
      progressBar = _SegmentedProgressBar(
        value: value,
        segments: segments!,
        height: _height,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      );
    } else {
      progressBar = _StandardProgressBar(
        value: value,
        height: _height,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        animationDuration: animationDuration ?? NightshadeTokens.durationNormal,
      );
    }

    if (label == null && !showPercentage) {
      return progressBar;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || showPercentage)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  Expanded(
                    child: Text(
                      label!,
                      style: NightshadeTypography.labelSm.copyWith(
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (showPercentage)
                  Text(
                    '${(value * 100).round()}%',
                    style: NightshadeTypography.monoSm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        progressBar,
      ],
    );
  }

  Color _getStateColor(NightshadeColors colors) {
    return switch (state) {
      NightshadeProgressState.normal => colors.primary,
      NightshadeProgressState.success => colors.success,
      NightshadeProgressState.warning => colors.warning,
      NightshadeProgressState.error => colors.error,
      NightshadeProgressState.paused => colors.textMuted,
    };
  }
}

class _StandardProgressBar extends StatefulWidget {
  const _StandardProgressBar({
    required this.value,
    required this.height,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.animationDuration,
  });

  final double value;
  final double height;
  final Color backgroundColor;
  final Color foregroundColor;
  final Duration animationDuration;

  @override
  State<_StandardProgressBar> createState() => _StandardProgressBarState();
}

class _StandardProgressBarState extends State<_StandardProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _completionController;
  late Animation<double> _glowAnimation;
  bool _wasComplete = false;

  /// Creates a slightly lighter shade of the given color
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
      duration: NightshadeTokens.durationSmooth,
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _completionController, curve: Curves.easeOut),
    );
    _wasComplete = widget.value >= 1.0;
  }

  @override
  void didUpdateWidget(_StandardProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger completion glow when progress reaches 100%
    final isComplete = widget.value >= 1.0;
    if (isComplete && !_wasComplete) {
      _completionController.forward().then((_) {
        if (mounted) _completionController.reverse();
      });
    }
    _wasComplete = isComplete;
  }

  @override
  void dispose() {
    _completionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isComplete = widget.value >= 1.0;

    // Shift to success color on completion
    final effectiveFgColor = isComplete ? colors.success : widget.foregroundColor;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.height / 2),
            // Inner shadow for depth (recessed track)
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
                blurStyle: BlurStyle.inner,
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  AnimatedContainer(
                    duration: widget.animationDuration,
                    curve: NightshadeTokens.curvePrecise,
                    width: constraints.maxWidth * widget.value.clamp(0.0, 1.0),
                    height: widget.height,
                    decoration: BoxDecoration(
                      // Gradient fill
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _lightenColor(effectiveFgColor, 0.1),
                          effectiveFgColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      // Completion glow
                      boxShadow: _glowAnimation.value > 0
                          ? [
                              BoxShadow(
                                color: effectiveFgColor.withValues(
                                  alpha: _glowAnimation.value,
                                ),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SegmentedProgressBar extends StatelessWidget {
  const _SegmentedProgressBar({
    required this.value,
    required this.segments,
    required this.height,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final double value;
  final int segments;
  final double height;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final completedSegments = (value * segments).floor();
    final partialProgress = (value * segments) - completedSegments;

    return Row(
      children: List.generate(segments, (index) {
        final isCompleted = index < completedSegments;
        final isPartial = index == completedSegments;

        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.only(
              right: index < segments - 1 ? 2 : 0,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            clipBehavior: Clip.hardEdge,
            child: isCompleted || isPartial
                ? FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: isCompleted ? 1.0 : partialProgress,
                    child: AnimatedContainer(
                      duration: NightshadeTokens.durationNormal,
                      decoration: BoxDecoration(
                        color: foregroundColor,
                        borderRadius: BorderRadius.circular(height / 2),
                      ),
                    ),
                  )
                : null,
          ),
        );
      }),
    );
  }
}

class _IndeterminateProgressBar extends StatefulWidget {
  const _IndeterminateProgressBar({
    required this.height,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final double height;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  State<_IndeterminateProgressBar> createState() =>
      _IndeterminateProgressBarState();
}

class _IndeterminateProgressBarState extends State<_IndeterminateProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -0.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(widget.height / 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return FractionallySizedBox(
            alignment: Alignment((_animation.value * 2) - 1, 0),
            widthFactor: 0.4,
            child: Container(
              decoration: BoxDecoration(
                color: widget.foregroundColor,
                borderRadius: BorderRadius.circular(widget.height / 2),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A circular progress indicator with optional percentage display.
class NightshadeCircularProgress extends StatelessWidget {
  const NightshadeCircularProgress({
    super.key,
    required this.value,
    this.size = 64,
    this.strokeWidth = 6,
    this.state = NightshadeProgressState.normal,
    this.showPercentage = false,
    this.indeterminate = false,
    this.backgroundColor,
    this.foregroundColor,
    this.child,
  });

  /// Progress value from 0.0 to 1.0
  final double value;

  /// Size of the circular progress
  final double size;

  /// Width of the progress stroke
  final double strokeWidth;

  /// State for automatic color selection
  final NightshadeProgressState state;

  /// Whether to show percentage in center
  final bool showPercentage;

  /// Whether to show indeterminate animation
  final bool indeterminate;

  /// Custom background color
  final Color? backgroundColor;

  /// Custom foreground color
  final Color? foregroundColor;

  /// Custom center widget
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final bgColor = backgroundColor ?? colors.surfaceAlt;
    final fgColor = foregroundColor ?? _getStateColor(colors);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background circle
          CircularProgressIndicator(
            value: 1.0,
            strokeWidth: strokeWidth,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation(bgColor),
            strokeCap: StrokeCap.round,
          ),
          // Progress circle
          if (indeterminate)
            CircularProgressIndicator(
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation(fgColor),
              strokeCap: StrokeCap.round,
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
              duration: NightshadeTokens.durationNormal,
              curve: NightshadeTokens.curveStandard,
              builder: (context, animatedValue, _) {
                return CircularProgressIndicator(
                  value: animatedValue,
                  strokeWidth: strokeWidth,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(fgColor),
                  strokeCap: StrokeCap.round,
                );
              },
            ),
          // Center content
          if (child != null || showPercentage)
            Center(
              child: child ??
                  Text(
                    '${(value * 100).round()}%',
                    style: NightshadeTypography.monoSm.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
        ],
      ),
    );
  }

  Color _getStateColor(NightshadeColors colors) {
    return switch (state) {
      NightshadeProgressState.normal => colors.primary,
      NightshadeProgressState.success => colors.success,
      NightshadeProgressState.warning => colors.warning,
      NightshadeProgressState.error => colors.error,
      NightshadeProgressState.paused => colors.textMuted,
    };
  }
}
