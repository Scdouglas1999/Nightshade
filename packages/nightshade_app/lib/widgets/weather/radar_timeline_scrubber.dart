import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Timeline scrubber for radar frame animation
/// Shows past frames, current time, and forecast frames
class RadarTimelineScrubber extends ConsumerStatefulWidget {
  /// All available radar frames
  final List<RadarFrame> frames;

  /// Currently selected frame index
  final int currentIndex;

  /// Callback when frame selection changes
  final ValueChanged<int> onFrameChanged;

  /// Whether animation is playing
  final bool isPlaying;

  /// Callback to toggle play/pause
  final VoidCallback onPlayPauseToggle;

  /// Playback speed multiplier (1.0 = normal)
  final double playbackSpeed;

  /// Callback when playback speed changes
  final ValueChanged<double>? onSpeedChanged;

  const RadarTimelineScrubber({
    super.key,
    required this.frames,
    required this.currentIndex,
    required this.onFrameChanged,
    required this.isPlaying,
    required this.onPlayPauseToggle,
    this.playbackSpeed = 1.0,
    this.onSpeedChanged,
  });

  @override
  ConsumerState<RadarTimelineScrubber> createState() =>
      _RadarTimelineScrubberState();
}

class _RadarTimelineScrubberState
    extends ConsumerState<RadarTimelineScrubber> {
  Timer? _animationTimer;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _updateAnimationTimer();
  }

  @override
  void didUpdateWidget(RadarTimelineScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.playbackSpeed != widget.playbackSpeed) {
      _updateAnimationTimer();
    }
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  /// Updates the animation timer based on play state and speed
  void _updateAnimationTimer() {
    _animationTimer?.cancel();
    _animationTimer = null;

    if (widget.isPlaying && !_isDragging && widget.frames.isNotEmpty) {
      // Base interval: 500ms per frame (2 FPS)
      const baseInterval = Duration(milliseconds: 500);
      final adjustedInterval = Duration(
        milliseconds: (baseInterval.inMilliseconds / widget.playbackSpeed).round(),
      );

      _animationTimer = Timer.periodic(adjustedInterval, (_) {
        if (!_isDragging) {
          _advanceFrame();
        }
      });
    }
  }

  /// Advances to the next frame, looping back to start if at end
  void _advanceFrame() {
    if (widget.frames.isEmpty) return;

    final nextIndex = (widget.currentIndex + 1) % widget.frames.length;
    widget.onFrameChanged(nextIndex);
  }

  /// Steps backward one frame
  void _stepBackward() {
    if (widget.frames.isEmpty) return;

    final prevIndex = widget.currentIndex > 0
        ? widget.currentIndex - 1
        : widget.frames.length - 1;
    widget.onFrameChanged(prevIndex);
  }

  /// Steps forward one frame
  void _stepForward() {
    if (widget.frames.isEmpty) return;

    _advanceFrame();
  }

  /// Finds the index of the frame closest to current time
  int? _findNowIndex() {
    if (widget.frames.isEmpty) return null;

    final now = DateTime.now();
    int? closestIndex;
    Duration? smallestDiff;

    for (int i = 0; i < widget.frames.length; i++) {
      final diff = widget.frames[i].timestamp.difference(now).abs();
      if (smallestDiff == null || diff < smallestDiff) {
        smallestDiff = diff;
        closestIndex = i;
      }
    }

    // Only return if the closest frame is within 30 minutes of now
    if (smallestDiff != null && smallestDiff.inMinutes <= 30) {
      return closestIndex;
    }

    return null;
  }

  /// Formats timestamp for display
  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final isToday = time.day == now.day &&
        time.month == now.month &&
        time.year == now.year;

    if (isToday) {
      return DateFormat('HH:mm').format(time);
    } else {
      return DateFormat('MMM d HH:mm').format(time);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    if (widget.frames.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.cloudOff,
              size: 16,
              color: colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'No radar frames available',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final currentFrame = widget.frames[widget.currentIndex];
    final nowIndex = _findNowIndex();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Controls row
          Row(
            children: [
              // Play/Pause button
              IconButton(
                onPressed: widget.onPlayPauseToggle,
                icon: Icon(
                  widget.isPlaying ? LucideIcons.pause : LucideIcons.play,
                  size: 20,
                ),
                color: colors.textPrimary,
                tooltip: widget.isPlaying ? 'Pause' : 'Play',
              ),

              const SizedBox(width: 8),

              // Step backward
              IconButton(
                onPressed: _stepBackward,
                icon: const Icon(LucideIcons.skipBack, size: 18),
                color: colors.textSecondary,
                tooltip: 'Previous frame',
              ),

              // Slider track
              Expanded(
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isDragging = true;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;

                    final localPosition = box.globalToLocal(details.globalPosition);
                    final sliderWidth = box.size.width - 200; // Account for controls
                    final relativeX = (localPosition.dx - 100).clamp(0.0, sliderWidth);
                    final fraction = relativeX / sliderWidth;
                    final newIndex = (fraction * widget.frames.length).floor()
                        .clamp(0, widget.frames.length - 1);

                    if (newIndex != widget.currentIndex) {
                      widget.onFrameChanged(newIndex);
                    }
                  },
                  onHorizontalDragEnd: (_) {
                    setState(() {
                      _isDragging = false;
                    });
                    _updateAnimationTimer();
                  },
                  child: CustomPaint(
                    size: const Size(double.infinity, 40),
                    painter: _TimelineTrackPainter(
                      frames: widget.frames,
                      currentIndex: widget.currentIndex,
                      nowIndex: nowIndex,
                      colors: colors,
                    ),
                  ),
                ),
              ),

              // Step forward
              IconButton(
                onPressed: _stepForward,
                icon: const Icon(LucideIcons.skipForward, size: 18),
                color: colors.textSecondary,
                tooltip: 'Next frame',
              ),

              const SizedBox(width: 8),

              // Speed selector
              if (widget.onSpeedChanged != null)
                PopupMenuButton<double>(
                  initialValue: widget.playbackSpeed,
                  onSelected: widget.onSpeedChanged,
                  tooltip: 'Playback speed',
                  itemBuilder: (context) => [
                    _buildSpeedMenuItem(0.5, '0.5x'),
                    _buildSpeedMenuItem(1.0, '1x'),
                    _buildSpeedMenuItem(2.0, '2x'),
                    _buildSpeedMenuItem(4.0, '4x'),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.playbackSpeed}x',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.chevronsUpDown,
                          size: 12,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 12),

              // Time display
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: currentFrame.isForecast
                      ? colors.warning.withOpacity(0.1)
                      : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: currentFrame.isForecast
                        ? colors.warning.withOpacity(0.3)
                        : colors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentFrame.isForecast) ...[
                      Icon(
                        LucideIcons.clock,
                        size: 12,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _formatTimestamp(currentFrame.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: currentFrame.isForecast
                            ? colors.warning
                            : colors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Frame counter
          const SizedBox(height: 4),
          Text(
            'Frame ${widget.currentIndex + 1} of ${widget.frames.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<double> _buildSpeedMenuItem(double value, String label) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    return PopupMenuItem<double>(
      value: value,
      child: Row(
        children: [
          if (value == widget.playbackSpeed)
            Icon(
              LucideIcons.check,
              size: 14,
              color: colors.primary,
            )
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

/// Custom painter for the timeline track
class _TimelineTrackPainter extends CustomPainter {
  final List<RadarFrame> frames;
  final int currentIndex;
  final int? nowIndex;
  final NightshadeColors colors;

  _TimelineTrackPainter({
    required this.frames,
    required this.currentIndex,
    required this.nowIndex,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;

    const trackHeight = 6.0;
    const tickHeight = 12.0;
    const thumbRadius = 8.0;
    final trackY = size.height / 2;

    // Draw track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        0,
        trackY - trackHeight / 2,
        size.width,
        trackHeight,
      ),
      const Radius.circular(3),
    );

    final trackPaint = Paint()
      ..color = colors.surfaceAlt
      ..style = PaintingStyle.fill;

    canvas.drawRRect(trackRect, trackPaint);

    // Draw frame tick marks
    final segmentWidth = size.width / (frames.length - 1);

    for (int i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final x = i * segmentWidth;

      // Tick color based on frame type
      final tickColor = frame.isForecast
          ? colors.warning.withOpacity(0.5)
          : colors.textMuted.withOpacity(0.5);

      final tickPaint = Paint()
        ..color = tickColor
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, trackY - tickHeight / 2),
        Offset(x, trackY + tickHeight / 2),
        tickPaint,
      );
    }

    // Draw "now" marker if present
    if (nowIndex != null) {
      final nowX = nowIndex! * segmentWidth;
      final nowPaint = Paint()
        ..color = colors.success
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(nowX, trackY - tickHeight),
        Offset(nowX, trackY + tickHeight),
        nowPaint,
      );

      // Draw "NOW" label
      final textSpan = TextSpan(
        text: 'NOW',
        style: TextStyle(
          color: colors.success,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(nowX - textPainter.width / 2, trackY - tickHeight - 14),
      );
    }

    // Draw progress fill up to current frame
    if (currentIndex > 0) {
      final progressWidth = currentIndex * segmentWidth;
      final progressRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          trackY - trackHeight / 2,
          progressWidth,
          trackHeight,
        ),
        const Radius.circular(3),
      );

      final progressPaint = Paint()
        ..color = colors.primary.withOpacity(0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(progressRect, progressPaint);
    }

    // Draw current position thumb
    final thumbX = currentIndex * segmentWidth;
    final thumbPaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;

    final thumbBorderPaint = Paint()
      ..color = colors.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(thumbX, trackY),
      thumbRadius,
      thumbPaint,
    );

    canvas.drawCircle(
      Offset(thumbX, trackY),
      thumbRadius,
      thumbBorderPaint,
    );
  }

  @override
  bool shouldRepaint(_TimelineTrackPainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.nowIndex != nowIndex ||
        oldDelegate.frames.length != frames.length;
  }
}
