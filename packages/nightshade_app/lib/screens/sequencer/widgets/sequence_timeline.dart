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

/// Full timeline view with labels, astronomical overlays, and details
class _FullTimeline extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final List<TimelineSegment> segments;
  final double totalDuration;
  final bool isRunning;
  final DateTime? startTime;
  final bool showAstronomicalOverlay;
  final Sequence sequence;

  const _FullTimeline({
    required this.colors,
    required this.segments,
    required this.totalDuration,
    required this.isRunning,
    required this.startTime,
    required this.showAstronomicalOverlay,
    required this.sequence,
  });

  @override
  ConsumerState<_FullTimeline> createState() => _FullTimelineState();
}

class _FullTimelineState extends ConsumerState<_FullTimeline>
    with WidgetsBindingObserver {
  Timer? _nowTimer;
  DateTime _now = DateTime.now();

  // Cached twilight times to avoid recalculation on every build
  TwilightTimes? _twilightTimes;
  DateTime? _twilightCacheDate;
  double? _twilightCacheLat;
  double? _twilightCacheLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNowTimer();
  }

  void _startNowTimer() {
    _nowTimer?.cancel();
    // Update the "now" indicator every minute
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Suspend the now-indicator timer when the app is backgrounded so a
    // hidden timeline doesn't repaint every minute (§4.33).
    if (state == AppLifecycleState.resumed) {
      if (_nowTimer == null || !_nowTimer!.isActive) {
        setState(() => _now = DateTime.now());
        _startNowTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _nowTimer?.cancel();
      _nowTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nowTimer?.cancel();
    super.dispose();
  }

  /// Calculate twilight times, caching to avoid redundant computations
  TwilightTimes? _getTwilightTimes(double lat, double lon, DateTime date) {
    final cacheDate = DateTime(date.year, date.month, date.day);

    if (_twilightTimes != null &&
        _twilightCacheDate == cacheDate &&
        _twilightCacheLat == lat &&
        _twilightCacheLon == lon) {
      return _twilightTimes;
    }

    _twilightTimes = AstronomyCalculations.calculateTwilightTimes(
      date: date,
      latitudeDeg: lat,
      longitudeDeg: lon,
    );
    _twilightCacheDate = cacheDate;
    _twilightCacheLat = lat;
    _twilightCacheLon = lon;

    return _twilightTimes;
  }

  /// Calculate target visibility windows for rise/set markers
  Map<String, ObjectVisibility> _getTargetWindows(
    double lat,
    double lon,
    DateTime date,
  ) {
    final windows = <String, ObjectVisibility>{};

    for (final node in widget.sequence.nodes.values) {
      if (node is TargetHeaderNode && node.isEnabled) {
        final visibility = AstronomyCalculations.calculateObjectVisibility(
          raDeg: node.raHours * 15.0, // Convert RA hours to degrees
          decDeg: node.decDegrees,
          date: date,
          latitudeDeg: lat,
          longitudeDeg: lon,
          minAltitude: node.minAltitude ?? 0,
        );
        windows[node.id] = visibility;
      }
    }

    return windows;
  }

  DateTime get _effectiveStartTime => widget.startTime ?? DateTime.now();

  DateTime get _estimatedEndTime =>
      _effectiveStartTime.add(Duration(seconds: widget.totalDuration.round()));

  bool get _isNowInRange {
    if (widget.totalDuration <= 0) return false;
    return _now.isAfter(_effectiveStartTime) &&
        _now.isBefore(_estimatedEndTime);
  }

  double? get _nowFraction {
    if (!_isNowInRange || widget.totalDuration <= 0) return null;
    final elapsed = _now.difference(_effectiveStartTime).inSeconds;
    return elapsed / widget.totalDuration;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => _buildWithoutOverlay(),
      error: (_, __) => _buildWithoutOverlay(),
      data: (settings) {
        final lat = settings.latitude;
        final lon = settings.longitude;

        // Only show astronomical overlay if we have valid location
        final hasValidLocation = lat != 0.0 || lon != 0.0;
        final shouldShowOverlay =
            widget.showAstronomicalOverlay && hasValidLocation;

        TwilightTimes? twilight;
        Map<String, ObjectVisibility>? targetWindows;

        if (shouldShowOverlay) {
          twilight = _getTwilightTimes(lat, lon, _effectiveStartTime);
          targetWindows = _getTargetWindows(lat, lon, _effectiveStartTime);
        }

        return _buildTimeline(
          twilight: twilight,
          targetWindows: targetWindows,
          showOverlay: shouldShowOverlay,
        );
      },
    );
  }

  Widget _buildWithoutOverlay() {
    return _buildTimeline(
      twilight: null,
      targetWindows: null,
      showOverlay: false,
    );
  }

  Widget _buildTimeline({
    required TwilightTimes? twilight,
    required Map<String, ObjectVisibility>? targetWindows,
    required bool showOverlay,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(LucideIcons.ganttChart,
                  size: 14, color: widget.colors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Sequence Timeline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(widget.totalDuration),
                style: TextStyle(
                  fontSize: 11,
                  color: widget.colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        // Timeline bar with overlays
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              height: 40,
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: widget.colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    // Twilight overlay bands (behind the timeline segments)
                    if (showOverlay && twilight != null)
                      _buildTwilightOverlay(twilight, constraints.maxWidth),

                    // Timeline segments
                    widget.totalDuration > 0
                        ? Row(
                            children: widget.segments.map((segment) {
                              final widthFraction =
                                  segment.duration / widget.totalDuration;
                              return Expanded(
                                flex: (widthFraction * 1000)
                                    .round()
                                    .clamp(1, 1000),
                                child: _TimelineBlock(
                                  colors: widget.colors,
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
                                color: widget.colors.textMuted,
                              ),
                            ),
                          ),

                    // Target rise/set markers
                    if (showOverlay && targetWindows != null)
                      ..._buildTargetMarkers(
                          targetWindows, constraints.maxWidth),

                    // "Now" indicator
                    if (_nowFraction != null)
                      _buildNowIndicator(constraints.maxWidth),
                  ],
                ),
              ),
            );
          },
        ),

        // Estimated completion time
        if (widget.startTime != null || widget.totalDuration > 0) ...[
          const SizedBox(height: 8),
          _buildCompletionInfo(),
        ],

        // Legend
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _LegendItem(
                colors: widget.colors,
                color: widget.colors.primary,
                label: 'Exposure'),
            _LegendItem(
                colors: widget.colors,
                color: widget.colors.warning,
                label: 'Focus'),
            _LegendItem(
                colors: widget.colors,
                color: widget.colors.accent,
                label: 'Slew'),
            _LegendItem(
                colors: widget.colors,
                color: widget.colors.info,
                label: 'Dither'),
            _LegendItem(
                colors: widget.colors,
                color: widget.colors.textMuted,
                label: 'Wait'),
            if (showOverlay) ...[
              const SizedBox(width: 8),
              _LegendItem(
                colors: widget.colors,
                color: Colors.lightBlue.withValues(alpha: 0.2),
                label: 'Civil',
              ),
              _LegendItem(
                colors: widget.colors,
                color: Colors.blue.withValues(alpha: 0.3),
                label: 'Nautical',
              ),
              _LegendItem(
                colors: widget.colors,
                color: Colors.indigo.withValues(alpha: 0.4),
                label: 'Astro',
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Build twilight overlay bands behind the timeline
  Widget _buildTwilightOverlay(TwilightTimes twilight, double totalWidth) {
    if (widget.totalDuration <= 0) {
      return const SizedBox.shrink();
    }

    final start = _effectiveStartTime;
    final end = _estimatedEndTime;

    // Build list of twilight regions within our timeline range
    final regions = <_TwilightRegion>[];

    // Helper to add a region if it overlaps with our timeline
    void addRegion(DateTime? regionStart, DateTime? regionEnd, Color color) {
      if (regionStart == null || regionEnd == null) return;
      if (regionEnd.isBefore(start) || regionStart.isAfter(end)) return;

      // Clamp to timeline range
      final clampedStart = regionStart.isBefore(start) ? start : regionStart;
      final clampedEnd = regionEnd.isAfter(end) ? end : regionEnd;

      final startFraction =
          clampedStart.difference(start).inSeconds / widget.totalDuration;
      final endFraction =
          clampedEnd.difference(start).inSeconds / widget.totalDuration;

      if (endFraction > startFraction) {
        regions.add(_TwilightRegion(
          startFraction: startFraction.clamp(0.0, 1.0),
          endFraction: endFraction.clamp(0.0, 1.0),
          color: color,
        ));
      }
    }

    // Civil twilight (evening): sunset to civil dusk
    addRegion(
      twilight.sunset,
      twilight.civilDusk,
      Colors.lightBlue.withValues(alpha: 0.2),
    );

    // Nautical twilight (evening): civil dusk to nautical dusk
    addRegion(
      twilight.civilDusk,
      twilight.nauticalDusk,
      Colors.blue.withValues(alpha: 0.3),
    );

    // Astronomical twilight (evening): nautical dusk to astronomical dusk
    addRegion(
      twilight.nauticalDusk,
      twilight.astronomicalDusk,
      Colors.indigo.withValues(alpha: 0.4),
    );

    // Astronomical twilight (morning): astronomical dawn to nautical dawn
    addRegion(
      twilight.astronomicalDawn,
      twilight.nauticalDawn,
      Colors.indigo.withValues(alpha: 0.4),
    );

    // Nautical twilight (morning): nautical dawn to civil dawn
    addRegion(
      twilight.nauticalDawn,
      twilight.civilDawn,
      Colors.blue.withValues(alpha: 0.3),
    );

    // Civil twilight (morning): civil dawn to sunrise
    addRegion(
      twilight.civilDawn,
      twilight.sunrise,
      Colors.lightBlue.withValues(alpha: 0.2),
    );

    return Stack(
      children: regions.map((region) {
        return Positioned(
          left: region.startFraction * totalWidth,
          width: (region.endFraction - region.startFraction) * totalWidth,
          top: 0,
          bottom: 0,
          child: Container(color: region.color),
        );
      }).toList(),
    );
  }

  /// Build target rise/set markers as vertical lines with tooltips
  List<Widget> _buildTargetMarkers(
    Map<String, ObjectVisibility> targetWindows,
    double totalWidth,
  ) {
    if (widget.totalDuration <= 0) {
      return [];
    }

    final markers = <Widget>[];
    final start = _effectiveStartTime;
    final end = _estimatedEndTime;

    for (final entry in targetWindows.entries) {
      final targetNode = widget.sequence.nodes[entry.key];
      if (targetNode is! TargetHeaderNode) continue;

      final visibility = entry.value;
      final targetName = targetNode.targetName;

      // Rise marker
      if (visibility.riseTime != null &&
          visibility.riseTime!.isAfter(start) &&
          visibility.riseTime!.isBefore(end)) {
        final fraction = visibility.riseTime!.difference(start).inSeconds /
            widget.totalDuration;
        markers.add(_buildTargetMarker(
          fraction: fraction,
          totalWidth: totalWidth,
          label: '$targetName rises',
          color: widget.colors.success,
          icon: LucideIcons.sunrise,
        ));
      }

      // Set marker
      if (visibility.setTime != null &&
          visibility.setTime!.isAfter(start) &&
          visibility.setTime!.isBefore(end)) {
        final fraction = visibility.setTime!.difference(start).inSeconds /
            widget.totalDuration;
        markers.add(_buildTargetMarker(
          fraction: fraction,
          totalWidth: totalWidth,
          label: '$targetName sets',
          color: widget.colors.warning,
          icon: LucideIcons.sunset,
        ));
      }

      // Transit marker (optional - can add if desired)
      if (visibility.transitTime != null &&
          visibility.transitTime!.isAfter(start) &&
          visibility.transitTime!.isBefore(end)) {
        final fraction = visibility.transitTime!.difference(start).inSeconds /
            widget.totalDuration;
        markers.add(_buildTargetMarker(
          fraction: fraction,
          totalWidth: totalWidth,
          label: '$targetName transit',
          color: widget.colors.info,
          icon: LucideIcons.moveVertical,
        ));
      }
    }

    return markers;
  }

  Widget _buildTargetMarker({
    required double fraction,
    required double totalWidth,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Positioned(
      left: fraction * totalWidth - 6, // Center the 12px wide marker
      top: 0,
      bottom: 0,
      child: Tooltip(
        message: label,
        child: Container(
          width: 12,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: color.withValues(alpha: 0.8),
                width: 2,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Icon(
                icon,
                size: 8,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the "now" indicator as a vertical red line
  Widget _buildNowIndicator(double totalWidth) {
    final fraction = _nowFraction;
    if (fraction == null) return const SizedBox.shrink();

    return Positioned(
      left: fraction * totalWidth - 1, // Center the 2px wide line
      top: 0,
      bottom: 0,
      child: Tooltip(
        message: 'Now: ${_formatClockTime(_now)}',
        child: Container(
          width: 2,
          decoration: BoxDecoration(
            color: widget.colors.error,
            boxShadow: [
              BoxShadow(
                color: widget.colors.error.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.colors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build estimated completion info
  Widget _buildCompletionInfo() {
    final remaining = _estimatedEndTime.difference(_now);
    final isInPast = remaining.isNegative;

    String completionText;
    if (widget.startTime != null) {
      completionText =
          'Est. completion: ${_formatClockTime(_estimatedEndTime)}';
      if (!isInPast && remaining.inMinutes > 0) {
        completionText +=
            ' (~${_formatRemainingDuration(remaining)} remaining)';
      } else if (isInPast) {
        completionText += ' (completed)';
      }
    } else {
      completionText = 'Duration: ${_formatRemainingDuration(
        Duration(seconds: widget.totalDuration.round()),
      )}';
    }

    return Row(
      children: [
        Icon(
          LucideIcons.clock,
          size: 12,
          color: widget.colors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          completionText,
          style: TextStyle(
            fontSize: 11,
            color: widget.colors.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
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

  String _formatRemainingDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatClockTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Helper class for twilight regions
class _TwilightRegion {
  final double startFraction;
  final double endFraction;
  final Color color;

  const _TwilightRegion({
    required this.startFraction,
    required this.endFraction,
    required this.color,
  });
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
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.5), width: 1)
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
