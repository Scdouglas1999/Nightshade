import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Index of the frame a radar timeline should sit on when nobody has scrubbed:
/// the newest OBSERVATION, i.e. the live edge of the loop.
///
/// Chosen by TIMESTAMP, never by list position. The providers do not agree on
/// an order: RainViewer sorts ascending, Open-Meteo / MET Norway walk an
/// ascending hourly series, but NOAA NEXRAD builds its frames from timestamps
/// sorted reverse-chronologically (noaa_radar_provider.dart:348), so its
/// newest frame is `frames.first` and its two-hour-old frame is `frames.last`.
/// Nothing between the provider and the widget re-sorts. Picking "the last
/// non-forecast entry" would therefore open a NOAA user on the OLDEST frame —
/// exactly the staleness this helper exists to prevent.
///
/// Forecast frames are skipped: RainViewer appends nowcast tiles and
/// Open-Meteo / MET Norway append hours past `now`, and opening on one would
/// show predicted cloud as though it had been measured.
///
/// When every frame is a forecast there is no observation to show, so the one
/// nearest to now is the least-wrong choice. An empty list yields 0 (nothing
/// to point at).
int latestObservedRadarFrameIndex(List<RadarFrame> frames) {
  if (frames.isEmpty) return 0;

  int? newestObserved;
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].isForecast) continue;
    if (newestObserved == null ||
        frames[i].timestamp.isAfter(frames[newestObserved].timestamp)) {
      newestObserved = i;
    }
  }
  if (newestObserved != null) return newestObserved;

  final now = DateTime.now();
  var nearest = 0;
  var nearestDistance = frames[0].timestamp.difference(now).abs();
  for (var i = 1; i < frames.length; i++) {
    final distance = frames[i].timestamp.difference(now).abs();
    if (distance < nearestDistance) {
      nearest = i;
      nearestDistance = distance;
    }
  }
  return nearest;
}

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

class _RadarTimelineScrubberState extends ConsumerState<RadarTimelineScrubber>
    with WidgetsBindingObserver {
  Timer? _animationTimer;
  bool _isDragging = false;
  bool _isAppPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateAnimationTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppPaused = false;
      _updateAnimationTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isAppPaused = true;
      if (_animationTimer != null && _animationTimer!.isActive) {
        _animationTimer?.cancel();
        _animationTimer = null;
      }
    }
  }

  @override
  void didUpdateWidget(RadarTimelineScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.playbackSpeed != widget.playbackSpeed ||
        !identical(oldWidget.frames, widget.frames)) {
      _updateAnimationTimer();
    }

    if (widget.frames.isNotEmpty &&
        (widget.currentIndex < 0 ||
            widget.currentIndex >= widget.frames.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.frames.isEmpty) return;
        if (widget.currentIndex < 0 ||
            widget.currentIndex >= widget.frames.length) {
          widget.onFrameChanged(_safeCurrentIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationTimer?.cancel();
    super.dispose();
  }

  /// Updates the animation timer based on play state and speed
  void _updateAnimationTimer() {
    _animationTimer?.cancel();
    _animationTimer = null;

    // Only animate when there are at least two frames to cycle through. A
    // single frame has no loop, so a timer would just re-select index 0.
    if (widget.isPlaying &&
        !_isDragging &&
        !_isAppPaused &&
        widget.frames.length > 1 &&
        widget.playbackSpeed.isFinite &&
        widget.playbackSpeed > 0) {
      // Base interval: 500ms per frame (2 FPS)
      const baseInterval = Duration(milliseconds: 500);
      final adjustedInterval = Duration(
        milliseconds:
            (baseInterval.inMilliseconds / widget.playbackSpeed).round(),
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

    final nextIndex = (_safeCurrentIndex + 1) % widget.frames.length;
    widget.onFrameChanged(nextIndex);
  }

  /// Steps backward one frame
  void _stepBackward() {
    if (widget.frames.isEmpty) return;

    final currentIndex = _safeCurrentIndex;
    final prevIndex =
        currentIndex > 0 ? currentIndex - 1 : widget.frames.length - 1;
    widget.onFrameChanged(prevIndex);
  }

  /// Steps forward one frame
  void _stepForward() {
    if (widget.frames.isEmpty) return;

    _advanceFrame();
  }

  int get _safeCurrentIndex {
    if (widget.frames.isEmpty) return 0;
    return widget.currentIndex.clamp(0, widget.frames.length - 1);
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
    // Frames carry absolute instants whose `DateTime` zone varies by provider
    // (RainViewer/NOAA build local-zoned instants from a Unix epoch, OpenMeteo
    // builds UTC instants). Normalize to local before formatting so the label
    // reads in the operator's wall-clock regardless of the source zone.
    final local = time.toLocal();
    final now = DateTime.now();
    final isToday = local.day == now.day &&
        local.month == now.month &&
        local.year == now.year;

    if (isToday) {
      return DateFormat('HH:mm').format(local);
    } else {
      return DateFormat('MMM d HH:mm').format(local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NightshadeColors.of(context);

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

    // A single frame can't be animated or scrubbed: there is nothing to seek
    // through and nothing for the play loop to advance to. Some sources (e.g.
    // the GOES satellite composite) only expose the latest image, so rather
    // than show dead transport controls we present a clean static readout of
    // the one frame's timestamp. Multi-frame sources (NOAA NEXRAD, RainViewer)
    // get the full animated timeline below.
    if (widget.frames.length == 1) {
      return _buildSingleFrame(context, colors, widget.frames.first);
    }

    final currentIndex = _safeCurrentIndex;
    final currentFrame = widget.frames[currentIndex];
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Scrub against the track's own width. The drag used to be
                    // measured off the whole control row and corrected with a
                    // hardcoded 100/200px for the transport buttons, which is
                    // only ever an estimate — the speed selector is optional
                    // and its label width varies — so the frame you landed on
                    // never matched the thumb you dragged.
                    final trackWidth = constraints.maxWidth;
                    return GestureDetector(
                      onHorizontalDragStart: (_) {
                        setState(() {
                          _isDragging = true;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (widget.frames.isEmpty || trackWidth <= 0) return;

                        final fraction = (details.localPosition.dx / trackWidth)
                            .clamp(0.0, 1.0);
                        final newIndex = (fraction * widget.frames.length)
                            .floor()
                            .clamp(0, widget.frames.length - 1);

                        if (newIndex != currentIndex) {
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
                          currentIndex: currentIndex,
                          nowIndex: nowIndex,
                          colors: colors,
                        ),
                      ),
                    );
                  },
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
                decoration: currentFrame.isForecast
                    ? NightshadeDecorations.emphasisSurface(
                        colors.warning,
                        borderRadius: BorderRadius.circular(4),
                      )
                    : BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.border),
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
            'Frame ${currentIndex + 1} of ${widget.frames.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Static readout for a single-frame source (no animation possible).
  ///
  /// Shows the frame's capture time and a "latest image" note instead of dead
  /// play/scrub controls, which would do nothing with only one frame.
  Widget _buildSingleFrame(
    BuildContext context,
    NightshadeColors colors,
    RadarFrame frame,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            frame.isForecast ? LucideIcons.clock : LucideIcons.satellite,
            size: 16,
            color: frame.isForecast ? colors.warning : colors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  frame.isForecast ? 'Forecast snapshot' : 'Latest image',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This source provides a single live frame — no loop to play.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              _formatTimestamp(frame.timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<double> _buildSpeedMenuItem(double value, String label) {
    final colors = NightshadeColors.of(context);

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
    final hasMultipleFrames = frames.length > 1;
    final segmentWidth =
        hasMultipleFrames ? size.width / (frames.length - 1) : 0.0;
    final singleFrameX = size.width / 2;

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
    for (int i = 0; i < frames.length; i++) {
      final frame = frames[i];
      final x = hasMultipleFrames ? i * segmentWidth : singleFrameX;

      // Tick color based on frame type
      final tickColor = frame.isForecast
          ? colors.warning.withValues(alpha: 0.5)
          : colors.textMuted.withValues(alpha: 0.5);

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
      final nowX = hasMultipleFrames ? nowIndex! * segmentWidth : singleFrameX;
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
    if (currentIndex > 0 && hasMultipleFrames) {
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
        ..color = colors.primary.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(progressRect, progressPaint);
    }

    // Draw current position thumb
    final thumbX =
        hasMultipleFrames ? currentIndex * segmentWidth : singleFrameX;
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
