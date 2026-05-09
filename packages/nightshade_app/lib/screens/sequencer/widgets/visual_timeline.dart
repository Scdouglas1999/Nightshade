import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Toggle for timeline view visibility.
final timelineVisibleProvider = StateProvider<bool>((ref) => false);

/// Provider that computes NodeTiming list from the current sequence.
final sequenceTimelineProvider = Provider<List<NodeTiming>>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  if (sequence == null) return [];

  final estimator = SequenceTimeEstimator();
  return estimator.estimateSequenceTiming(sequence, DateTime.now());
});

/// Horizontal timeline view showing each node as a colored bar.
/// Width of each bar proportional to estimated duration.
/// Current execution position shown as a vertical line.
class VisualTimeline extends ConsumerWidget {
  final NightshadeColors colors;

  const VisualTimeline({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timings = ref.watch(sequenceTimelineProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final sequence = ref.watch(currentSequenceProvider);

    if (timings.isEmpty || sequence == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Center(
          child: Text(
            'No timeline data available',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ),
      );
    }

    // Calculate total duration
    final firstStart = timings.first.estimatedStart;
    final lastEnd = timings.last.estimatedEnd;
    final totalDuration = lastEnd.difference(firstStart);
    final totalSecs = totalDuration.inSeconds.toDouble();

    if (totalSecs <= 0) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Center(
          child: Text(
            'Sequence has no estimated duration',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ),
      );
    }

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(LucideIcons.ganttChart, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Timeline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatTotalDuration(totalDuration),
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                const Spacer(),
                // Close button
                GestureDetector(
                  onTap: () {
                    ref.read(timelineVisibleProvider.notifier).state = false;
                  },
                  child: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
                ),
              ],
            ),
          ),

          // Timeline bars - scrollable horizontally
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                // Minimum 800px wide, or scaled wider for long sequences
                width: (totalSecs / 60 * 4).clamp(800, 4000).toDouble(),
                child: CustomPaint(
                  painter: _TimelinePainter(
                    colors: colors,
                    timings: timings,
                    firstStart: firstStart,
                    totalSecs: totalSecs,
                    progress: progress,
                    sequence: sequence,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // Time axis labels
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('HH:mm').format(firstStart),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
                Text(
                  DateFormat('HH:mm').format(
                    firstStart.add(Duration(seconds: (totalSecs / 4).round())),
                  ),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
                Text(
                  DateFormat('HH:mm').format(
                    firstStart.add(Duration(seconds: (totalSecs / 2).round())),
                  ),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
                Text(
                  DateFormat('HH:mm').format(
                    firstStart
                        .add(Duration(seconds: (totalSecs * 3 / 4).round())),
                  ),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
                Text(
                  DateFormat('HH:mm').format(lastEnd),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTotalDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m total';
    return '${mins}m total';
  }
}

class _TimelinePainter extends CustomPainter {
  final NightshadeColors colors;
  final List<NodeTiming> timings;
  final DateTime firstStart;
  final double totalSecs;
  final SequenceProgress progress;
  final Sequence sequence;

  _TimelinePainter({
    required this.colors,
    required this.timings,
    required this.firstStart,
    required this.totalSecs,
    required this.progress,
    required this.sequence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topMargin = 4.0;
    final barAreaHeight = size.height - topMargin;

    // Group timings by target header for stacking
    // Each target gets its own row
    final targetGroups = <String?, List<NodeTiming>>{};
    for (final timing in timings) {
      targetGroups.putIfAbsent(timing.targetHeaderId, () => []).add(timing);
    }

    final rowCount = targetGroups.length.clamp(1, 6);
    final rowHeight = (barAreaHeight / rowCount).clamp(12.0, 30.0);
    const barGap = 1.0;

    // Draw time grid lines
    _drawTimeGrid(canvas, size, topMargin);

    // Draw bars for each target group
    int rowIndex = 0;
    for (final entry in targetGroups.entries) {
      final y = topMargin + rowIndex * rowHeight;

      for (final timing in entry.value) {
        final startOffset =
            timing.estimatedStart.difference(firstStart).inSeconds.toDouble();
        final durationSecs = timing.duration.inSeconds.toDouble();

        final x = (startOffset / totalSecs) * size.width;
        final w = ((durationSecs / totalSecs) * size.width)
            .clamp(2.0, double.infinity);

        // Determine color from node category
        final node = sequence.nodes[timing.nodeId];
        Color barColor;
        if (node != null) {
          switch (node.category) {
            case NodeCategory.instruction:
              barColor = colors.primary;
              break;
            case NodeCategory.trigger:
              barColor = colors.warning;
              break;
            case NodeCategory.logic:
              barColor = colors.accent;
              break;
            case NodeCategory.target:
              barColor = colors.warning;
              break;
          }
        } else {
          barColor = colors.textMuted;
        }

        // Highlight based on execution status
        final nodeStatus = progress.nodeStatuses[timing.nodeId];
        if (nodeStatus == NodeStatus.running) {
          barColor = colors.info;
        } else if (nodeStatus == NodeStatus.success) {
          barColor = colors.success;
        } else if (nodeStatus == NodeStatus.failure) {
          barColor = colors.error;
        }

        final rect = Rect.fromLTWH(x, y + barGap, w, rowHeight - barGap * 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = barColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.fill,
        );

        // Draw node name label if bar is wide enough
        if (w > 40) {
          final labelColor =
              ThemeData.estimateBrightnessForColor(barColor) == Brightness.dark
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF000000);
          final textPainter = TextPainter(
            text: TextSpan(
              text: timing.nodeName,
              style: TextStyle(
                fontSize: 9,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: w - 6);
          textPainter.paint(
            canvas,
            Offset(x + 3,
                y + barGap + (rowHeight - barGap * 2 - textPainter.height) / 2),
          );
        }
      }

      rowIndex++;
    }

    // Draw current execution position line
    if (progress.currentNodeId != null) {
      final currentTiming =
          timings.where((t) => t.nodeId == progress.currentNodeId).firstOrNull;
      if (currentTiming != null) {
        final elapsed =
            DateTime.now().difference(currentTiming.estimatedStart).inSeconds;
        final startOffset = currentTiming.estimatedStart
            .difference(firstStart)
            .inSeconds
            .toDouble();
        final xPos = ((startOffset + elapsed) / totalSecs) * size.width;

        canvas.drawLine(
          Offset(xPos, 0),
          Offset(xPos, size.height),
          Paint()
            ..color = colors.info
            ..strokeWidth = 2.0,
        );

        // Draw small triangle at top
        final path = Path()
          ..moveTo(xPos - 4, 0)
          ..lineTo(xPos + 4, 0)
          ..lineTo(xPos, 6)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.info
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size, double topMargin) {
    // Draw 4 evenly spaced grid lines
    final gridPaint = Paint()
      ..color = colors.border.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, size.height),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) {
    return oldDelegate.timings != timings || oldDelegate.progress != progress;
  }
}
