import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Hide TwilightTimes from the core barrel — scheduler's sky_calculations
// exports its own; this widget consumes the planetarium's TwilightTimes via
// AstronomyCalculations.calculateTwilightTimes(...).
import 'package:nightshade_core/nightshade_core.dart' hide TwilightTimes;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

part 'sequence_timeline/segment_and_mini.dart';
part 'sequence_timeline/full_timeline.dart';
part 'sequence_timeline/supporting_widgets.dart';

/// A horizontal timeline visualization of the sequence
class SequenceTimeline extends ConsumerWidget {
  final NightshadeColors colors;
  final bool showMiniVersion;

  /// Optional start time for the sequence. If provided, the timeline will show
  /// actual clock times. If null, shows relative times from 0:00.
  final DateTime? startTime;

  /// Whether to show astronomical overlay bands (twilight zones)
  final bool showAstronomicalOverlay;

  const SequenceTimeline({
    required this.colors,
    this.showMiniVersion = false,
    this.startTime,
    this.showAstronomicalOverlay = true,
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
      startTime: startTime,
      showAstronomicalOverlay: showAstronomicalOverlay,
      sequence: sequence,
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
        customColor =
            node.filter != null ? _getFilterColor(node.filter!) : null;
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
        return const Color(0xFFFFFFFF);
      case 'r':
      case 'red':
        return const Color(0xFFEF4444);
      case 'g':
      case 'green':
        return const Color(0xFF22C55E);
      case 'b':
      case 'blue':
        return const Color(0xFF3B82F6);
      case 'ha':
      case 'h-alpha':
        return const Color(0xFFB91C1C);
      case 'oiii':
        return const Color(0xFF14B8A6);
      case 'sii':
        return const Color(0xFFEA580C);
      default:
        return null;
    }
  }
}
