import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A horizontal timeline visualization of the sequence
class SequenceTimeline extends ConsumerWidget {
  final NightshadeColors colors;
  final bool showMiniVersion;

  const SequenceTimeline({
    required this.colors,
    this.showMiniVersion = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    final executionState = ref.watch(sequenceExecutionStateProvider);

    if (sequence == null || sequence.nodes.isEmpty) {
      return _buildEmptyState();
    }

    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;

    // Flatten the sequence into timeline segments
    final segments = _buildTimelineSegments(sequence);
    final totalDuration = sequence.totalIntegrationSecs;

    if (showMiniVersion) {
      return _MiniTimeline(
        colors: colors,
        segments: segments,
        totalDuration: totalDuration,
        isRunning: isRunning,
      );
    }

    return _FullTimeline(
      colors: colors,
      segments: segments,
      totalDuration: totalDuration,
      isRunning: isRunning,
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Center(
        child: Text(
          'No sequence nodes to visualize',
          style: TextStyle(
            fontSize: 12,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }

  List<TimelineSegment> _buildTimelineSegments(Sequence sequence) {
    final segments = <TimelineSegment>[];

    // Get all execution-relevant nodes in order
    void processNode(SequenceNode node, int depth) {
      if (!node.isEnabled) return;

      // Calculate duration based on node type
      double duration = 0;
      TimelineSegmentType type = TimelineSegmentType.instruction;
      Color? customColor;

      if (node is ExposureNode) {
        duration = node.totalDurationSecs;
        type = TimelineSegmentType.exposure;
        customColor = node.filter != null ? _getFilterColor(node.filter!) : null;
      } else if (node is AutofocusNode) {
        duration = node.exposureDuration * 10; // Estimate ~10 exposures
        type = TimelineSegmentType.focus;
      } else if (node is DitherNode) {
        duration = 5; // Dither typically takes ~5 seconds
        type = TimelineSegmentType.dither;
      } else if (node is DelayNode) {
        duration = node.seconds;
        type = TimelineSegmentType.wait;
      } else if (node is WaitTimeNode) {
        // Calculate time until wait
        if (node.waitUntil != null) {
          final now = DateTime.now();
          duration = node.waitUntil!.difference(now).inSeconds.toDouble();
          if (duration < 0) duration = 0;
        }
        type = TimelineSegmentType.wait;
      } else if (node is SlewNode || node is CenterNode) {
        duration = 30; // Estimate 30 seconds for slew operations
        type = TimelineSegmentType.slew;
      } else if (node is MeridianFlipNode) {
        duration = 120; // Estimate 2 minutes for meridian flip
        type = TimelineSegmentType.flip;
      } else if (node is FilterChangeNode) {
        duration = 10; // Estimate 10 seconds for filter change
        type = TimelineSegmentType.filter;
      }

      if (duration > 0) {
        segments.add(TimelineSegment(
          nodeId: node.id,
          name: node.name,
          duration: duration,
          type: type,
          customColor: customColor,
        ));
      }

      // Process children
      for (final childId in node.childIds) {
        final child = sequence.nodes[childId];
        if (child != null) {
          processNode(child, depth + 1);
        }
      }
    }

    // Start from root
    if (sequence.rootNodeId != null) {
      final root = sequence.nodes[sequence.rootNodeId!];
      if (root != null) {
        processNode(root, 0);
      }
    }

    // Also process any top-level target groups
    for (final node in sequence.nodes.values) {
      if (node is TargetHeaderNode && node.isEnabled) {
        processNode(node, 0);
      }
    }

    return segments;
  }

  Color? _getFilterColor(String filter) {
    switch (filter.toLowerCase()) {
      case 'l':
      case 'luminance':
        return Colors.white;
      case 'r':
      case 'red':
        return Colors.red;
      case 'g':
      case 'green':
        return Colors.green;
      case 'b':
      case 'blue':
        return Colors.blue;
      case 'ha':
      case 'h-alpha':
        return Colors.red.shade700;
      case 'oiii':
        return Colors.teal;
      case 'sii':
        return Colors.deepOrange;
      default:
        return null;
    }
  }
}

/// Type of timeline segment
enum TimelineSegmentType {
  exposure,
  focus,
  dither,
  wait,
  slew,
  flip,
  filter,
  instruction,
}

/// A segment in the timeline
class TimelineSegment {
  final String nodeId;
  final String name;
  final double duration; // seconds
  final TimelineSegmentType type;
  final Color? customColor;

  const TimelineSegment({
    required this.nodeId,
    required this.name,
    required this.duration,
    required this.type,
    this.customColor,
  });
}

/// Mini timeline for bottom status bar
class _MiniTimeline extends StatelessWidget {
  final NightshadeColors colors;
  final List<TimelineSegment> segments;
  final double totalDuration;
  final bool isRunning;

  const _MiniTimeline({
    required this.colors,
    required this.segments,
    required this.totalDuration,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDuration == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: segments.map((segment) {
            final widthFraction = segment.duration / totalDuration;
            return Expanded(
              flex: (widthFraction * 1000).round().clamp(1, 1000),
              child: Container(
                color: _getSegmentColor(segment),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getSegmentColor(TimelineSegment segment) {
    if (segment.customColor != null) {
      return segment.customColor!.withValues(alpha: 0.7);
    }

    switch (segment.type) {
      case TimelineSegmentType.exposure:
        return colors.primary.withValues(alpha: 0.7);
      case TimelineSegmentType.focus:
        return colors.warning.withValues(alpha: 0.7);
      case TimelineSegmentType.dither:
        return colors.info.withValues(alpha: 0.7);
      case TimelineSegmentType.wait:
        return colors.textMuted.withValues(alpha: 0.5);
      case TimelineSegmentType.slew:
        return colors.accent.withValues(alpha: 0.7);
      case TimelineSegmentType.flip:
        return colors.error.withValues(alpha: 0.5);
      case TimelineSegmentType.filter:
        return colors.success.withValues(alpha: 0.7);
      case TimelineSegmentType.instruction:
        return colors.surfaceAlt;
    }
  }
}

/// Full timeline view with labels and details
class _FullTimeline extends StatelessWidget {
  final NightshadeColors colors;
  final List<TimelineSegment> segments;
  final double totalDuration;
  final bool isRunning;

  const _FullTimeline({
    required this.colors,
    required this.segments,
    required this.totalDuration,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(LucideIcons.ganttChart, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Sequence Timeline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(totalDuration),
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        // Timeline bar
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: totalDuration > 0
                ? Row(
                    children: segments.map((segment) {
                      final widthFraction = segment.duration / totalDuration;
                      return Expanded(
                        flex: (widthFraction * 1000).round().clamp(1, 1000),
                        child: _TimelineBlock(
                          colors: colors,
                          segment: segment,
                        ),
                      );
                    }).toList(),
                  )
                : Center(
                    child: Text(
                      'No timed activities',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
          ),
        ),

        // Legend
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _LegendItem(colors: colors, color: colors.primary, label: 'Exposure'),
            _LegendItem(colors: colors, color: colors.warning, label: 'Focus'),
            _LegendItem(colors: colors, color: colors.accent, label: 'Slew'),
            _LegendItem(colors: colors, color: colors.info, label: 'Dither'),
            _LegendItem(colors: colors, color: colors.textMuted, label: 'Wait'),
          ],
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();

    if (hours > 0) {
      return '${hours}h ${minutes}m total';
    }
    return '${minutes}m total';
  }
}

/// Individual block in the timeline
class _TimelineBlock extends StatefulWidget {
  final NightshadeColors colors;
  final TimelineSegment segment;

  const _TimelineBlock({
    required this.colors,
    required this.segment,
  });

  @override
  State<_TimelineBlock> createState() => _TimelineBlockState();
}

class _TimelineBlockState extends State<_TimelineBlock> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _getSegmentColor();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: '${widget.segment.name}\n${_formatSegmentDuration()}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          decoration: BoxDecoration(
            color: _isHovered ? color : color.withValues(alpha: 0.7),
            border: _isHovered
                ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1)
                : null,
          ),
          child: widget.segment.duration > 60
              ? Center(
                  child: Text(
                    _getShortLabel(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    overflow: TextOverflow.clip,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Color _getSegmentColor() {
    if (widget.segment.customColor != null) {
      return widget.segment.customColor!;
    }

    switch (widget.segment.type) {
      case TimelineSegmentType.exposure:
        return widget.colors.primary;
      case TimelineSegmentType.focus:
        return widget.colors.warning;
      case TimelineSegmentType.dither:
        return widget.colors.info;
      case TimelineSegmentType.wait:
        return widget.colors.textMuted;
      case TimelineSegmentType.slew:
        return widget.colors.accent;
      case TimelineSegmentType.flip:
        return widget.colors.error;
      case TimelineSegmentType.filter:
        return widget.colors.success;
      case TimelineSegmentType.instruction:
        return widget.colors.surfaceAlt;
    }
  }

  String _getShortLabel() {
    switch (widget.segment.type) {
      case TimelineSegmentType.exposure:
        return 'EXP';
      case TimelineSegmentType.focus:
        return 'AF';
      case TimelineSegmentType.dither:
        return 'D';
      case TimelineSegmentType.wait:
        return 'W';
      case TimelineSegmentType.slew:
        return 'SLW';
      case TimelineSegmentType.flip:
        return 'MF';
      case TimelineSegmentType.filter:
        return 'F';
      case TimelineSegmentType.instruction:
        return '';
    }
  }

  String _formatSegmentDuration() {
    final secs = widget.segment.duration;
    if (secs >= 3600) {
      return '${(secs / 3600).toStringAsFixed(1)}h';
    } else if (secs >= 60) {
      return '${(secs / 60).toStringAsFixed(0)}m';
    }
    return '${secs.toStringAsFixed(0)}s';
  }
}

/// Legend item
class _LegendItem extends StatelessWidget {
  final NightshadeColors colors;
  final Color color;
  final String label;

  const _LegendItem({
    required this.colors,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
