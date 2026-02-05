import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../models/sequence/sequence_models.dart';

/// Optional location context for astronomical calculations
class _LocationContext {
  final double latitude;
  final double longitude;
  final DateTime date;

  const _LocationContext({
    required this.latitude,
    required this.longitude,
    required this.date,
  });
}

/// Timing information for a single sequence node
class NodeTiming {
  /// Unique identifier of the node
  final String nodeId;

  /// Display name of the node
  final String nodeName;

  /// Type identifier of the node (e.g., 'TakeExposure', 'Autofocus')
  final String nodeType;

  /// Estimated start time of this node
  final DateTime estimatedStart;

  /// Estimated end time of this node
  final DateTime estimatedEnd;

  /// Estimated duration of this node
  final Duration duration;

  /// Warning messages for timing conflicts (e.g., target below horizon)
  final List<String>? warnings;

  /// ID of the parent target header node, if any
  final String? targetHeaderId;

  NodeTiming({
    required this.nodeId,
    required this.nodeName,
    required this.nodeType,
    required this.estimatedStart,
    required this.estimatedEnd,
    required this.duration,
    this.warnings,
    this.targetHeaderId,
  });

  /// Create a copy with updated warnings
  NodeTiming copyWithWarnings(List<String> newWarnings) {
    return NodeTiming(
      nodeId: nodeId,
      nodeName: nodeName,
      nodeType: nodeType,
      estimatedStart: estimatedStart,
      estimatedEnd: estimatedEnd,
      duration: duration,
      warnings: newWarnings.isNotEmpty ? newWarnings : null,
      targetHeaderId: targetHeaderId,
    );
  }

  @override
  String toString() {
    return 'NodeTiming(nodeId: $nodeId, nodeName: $nodeName, nodeType: $nodeType, '
        'start: $estimatedStart, end: $estimatedEnd, duration: $duration, '
        'warnings: $warnings, targetHeaderId: $targetHeaderId)';
  }
}

/// Visibility window information for a target
class TargetWindow {
  /// Database ID of the target (from TargetHeaderNode)
  final String targetId;

  /// Display name of the target
  final String targetName;

  /// Time when the target rises above the minimum altitude
  final DateTime? riseTime;

  /// Time when the target crosses the meridian (highest altitude)
  final DateTime? transitTime;

  /// Time when the target sets below the minimum altitude
  final DateTime? setTime;

  /// Altitude at transit in degrees
  final double? transitAltitude;

  /// True if the target never sets below the minimum altitude
  final bool isCircumpolar;

  /// True if the target never rises above the minimum altitude
  final bool neverRises;

  TargetWindow({
    required this.targetId,
    required this.targetName,
    this.riseTime,
    this.transitTime,
    this.setTime,
    this.transitAltitude,
    this.isCircumpolar = false,
    this.neverRises = false,
  });

  /// Check if a given time falls within the visibility window
  bool isVisibleAt(DateTime time) {
    if (neverRises) return false;
    if (isCircumpolar) return true;

    if (riseTime == null || setTime == null) return false;

    // Handle window that crosses midnight
    if (setTime!.isBefore(riseTime!)) {
      // Window crosses midnight: visible if after rise OR before set
      return time.isAfter(riseTime!) || time.isBefore(setTime!);
    }

    return time.isAfter(riseTime!) && time.isBefore(setTime!);
  }

  @override
  String toString() {
    return 'TargetWindow(targetId: $targetId, targetName: $targetName, '
        'rise: $riseTime, transit: $transitTime, set: $setTime, '
        'transitAlt: $transitAltitude, circumpolar: $isCircumpolar, neverRises: $neverRises)';
  }
}

/// Service for estimating sequence execution timing with astronomical awareness.
///
/// This service walks a sequence tree to estimate when each node will execute,
/// calculates target visibility windows based on observer location, and
/// identifies timing conflicts where nodes may execute outside their target's
/// visibility window.
class SequenceTimeEstimator {
  // ============================================================================
  // Default timing constants (in seconds unless noted)
  // ============================================================================

  /// Download overhead per exposure in seconds (for CCD readout and save)
  static const double _downloadOverheadSecs = 2.0;

  /// Default dither duration in seconds
  static const double _ditherDurationSecs = 5.0;

  /// Default slew duration in seconds
  static const double _slewDurationSecs = 30.0;

  /// Default centering duration in seconds (includes plate solve + slew)
  static const double _centerDurationSecs = 30.0;

  /// Default meridian flip duration in seconds
  static const double _meridianFlipDurationSecs = 120.0;

  /// Default cooling duration in minutes
  static const double _defaultCoolingMins = 10.0;

  /// Minimum altitude for target visibility calculations (degrees)
  static const double _defaultMinAltitude = 0.0;

  /// Estimate timing for all nodes in a sequence.
  ///
  /// Walks the sequence tree in depth-first execution order from the root node,
  /// calculating start and end times for each enabled node based on its type
  /// and parameters.
  ///
  /// [sequence] - The sequence to estimate timing for
  /// [startTime] - The intended start time of the sequence
  /// [latitude] - Observer latitude in degrees (optional, needed for twilight waits)
  /// [longitude] - Observer longitude in degrees (optional, needed for twilight waits)
  ///
  /// Returns a list of [NodeTiming] objects in execution order.
  List<NodeTiming> estimateSequenceTiming(
    Sequence sequence,
    DateTime startTime, {
    double? latitude,
    double? longitude,
  }) {
    final timings = <NodeTiming>[];
    var currentTime = startTime;

    // Create location context if coordinates provided
    final locationContext = (latitude != null && longitude != null)
        ? _LocationContext(
            latitude: latitude,
            longitude: longitude,
            date: startTime,
          )
        : null;

    if (sequence.rootNodeId == null) {
      // No root node - process all target headers as separate roots
      final targetHeaders = sequence.targetHeaders;
      for (final target in targetHeaders) {
        currentTime = _processNode(
          node: target,
          sequence: sequence,
          currentTime: currentTime,
          timings: timings,
          currentTargetHeaderId: target.id,
          loopIterationNote: null,
          locationContext: locationContext,
        );
      }
    } else {
      // Process from root node
      final rootNode = sequence.nodes[sequence.rootNodeId];
      if (rootNode != null && rootNode.isEnabled) {
        _processNode(
          node: rootNode,
          sequence: sequence,
          currentTime: currentTime,
          timings: timings,
          currentTargetHeaderId: null,
          loopIterationNote: null,
          locationContext: locationContext,
        );
      }
    }

    return timings;
  }

  /// Process a single node and its children, returning the time after completion.
  DateTime _processNode({
    required SequenceNode node,
    required Sequence sequence,
    required DateTime currentTime,
    required List<NodeTiming> timings,
    required String? currentTargetHeaderId,
    required String? loopIterationNote,
    required _LocationContext? locationContext,
  }) {
    if (!node.isEnabled) {
      return currentTime;
    }

    // Update target header ID if this is a target header node
    final targetId =
        node is TargetHeaderNode ? node.id : currentTargetHeaderId;

    // Calculate duration for this node
    final nodeDuration = _estimateNodeDuration(node, currentTime, locationContext);

    // Add timing entry if this node has a meaningful duration
    if (nodeDuration.inSeconds > 0) {
      final endTime = currentTime.add(nodeDuration);
      final warnings = <String>[];

      // Add loop iteration note if applicable
      if (loopIterationNote != null) {
        warnings.add(loopIterationNote);
      }

      timings.add(NodeTiming(
        nodeId: node.id,
        nodeName: node.name,
        nodeType: node.nodeType,
        estimatedStart: currentTime,
        estimatedEnd: endTime,
        duration: nodeDuration,
        warnings: warnings.isNotEmpty ? warnings : null,
        targetHeaderId: targetId,
      ));

      currentTime = endTime;
    }

    // Process children in order
    if (node.childIds.isNotEmpty) {
      final children = sequence.getChildren(node.id);

      // Handle loop nodes specially - only estimate one iteration
      if (node is LoopNode) {
        final loopNote = _getLoopIterationNote(node);
        for (final child in children) {
          currentTime = _processNode(
            node: child,
            sequence: sequence,
            currentTime: currentTime,
            timings: timings,
            currentTargetHeaderId: targetId,
            loopIterationNote: loopNote,
            locationContext: locationContext,
          );
        }
      } else {
        for (final child in children) {
          currentTime = _processNode(
            node: child,
            sequence: sequence,
            currentTime: currentTime,
            timings: timings,
            currentTargetHeaderId: targetId,
            loopIterationNote: loopIterationNote,
            locationContext: locationContext,
          );
        }
      }
    }

    return currentTime;
  }

  /// Get a note describing loop iteration limitations.
  String _getLoopIterationNote(LoopNode node) {
    switch (node.conditionType) {
      case LoopConditionType.count:
        final count = node.repeatCount ?? 1;
        if (count > 1) {
          return 'Showing 1 of $count loop iterations';
        }
        return 'Single loop iteration';
      case LoopConditionType.forever:
        return 'Unbounded loop - showing single iteration estimate';
      case LoopConditionType.whileDark:
        return 'Loop until dawn - showing single iteration estimate';
      case LoopConditionType.untilTime:
        final until = node.repeatUntil;
        if (until != null) {
          return 'Loop until ${_formatTime(until)} - showing single iteration';
        }
        return 'Time-based loop - showing single iteration estimate';
      case LoopConditionType.untilAltitude:
        final alt = node.repeatUntilAltitude;
        if (alt != null) {
          return 'Loop until altitude ${alt.toStringAsFixed(0)} degrees - showing single iteration';
        }
        return 'Altitude-based loop - showing single iteration estimate';
    }
  }

  /// Format time for display.
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Calculate when the specified twilight type will occur.
  ///
  /// Returns the next occurrence of the specified twilight (dusk or dawn),
  /// or null if it can't be calculated (e.g., polar regions in summer).
  DateTime? _calculateTwilightWaitTime(
    DateTime currentTime,
    TwilightType twilightType,
    _LocationContext locationContext,
  ) {
    final twilightTimes = AstronomyCalculations.calculateTwilightTimes(
      date: locationContext.date,
      latitudeDeg: locationContext.latitude,
      longitudeDeg: locationContext.longitude,
    );

    // Determine which twilight time to use based on type
    // For imaging, we typically wait for evening twilight (dusk)
    DateTime? targetTime;
    switch (twilightType) {
      case TwilightType.civil:
        // Civil twilight: sun 6° below horizon
        targetTime = twilightTimes.civilDusk;
        break;
      case TwilightType.nautical:
        // Nautical twilight: sun 12° below horizon
        targetTime = twilightTimes.nauticalDusk;
        break;
      case TwilightType.astronomical:
        // Astronomical twilight: sun 18° below horizon (truly dark)
        targetTime = twilightTimes.astronomicalDusk;
        break;
    }

    if (targetTime == null) {
      // Twilight doesn't occur (e.g., polar summer)
      return null;
    }

    // If the twilight time has already passed today, it means we're
    // already past dusk - no wait needed
    if (targetTime.isBefore(currentTime)) {
      return null;
    }

    return targetTime;
  }

  /// Estimate the duration of a single node based on its type.
  Duration _estimateNodeDuration(
    SequenceNode node,
    DateTime currentTime,
    _LocationContext? locationContext,
  ) {
    if (node is ExposureNode) {
      // Exposure time + download overhead for each frame
      final totalSecs =
          node.count * node.durationSecs + node.count * _downloadOverheadSecs;
      return Duration(milliseconds: (totalSecs * 1000).round());
    }

    if (node is AutofocusNode) {
      // Estimate based on number of samples and exposure duration
      // Default: stepsOut * 2 + 1 data points, each with exposuresPerPoint exposures
      final dataPoints = node.stepsOut * 2 + 1;
      final totalExposures = dataPoints * node.exposuresPerPoint;
      final totalSecs = totalExposures * node.exposureDuration;
      return Duration(milliseconds: (totalSecs * 1000).round());
    }

    if (node is DitherNode) {
      // Use settle time if specified, otherwise default
      final secs = node.settleTime > 0 ? node.settleTime : _ditherDurationSecs;
      return Duration(milliseconds: (secs * 1000).round());
    }

    if (node is DelayNode) {
      return Duration(milliseconds: (node.seconds * 1000).round());
    }

    if (node is WaitTimeNode) {
      if (node.waitUntil != null) {
        final waitDuration = node.waitUntil!.difference(currentTime);
        if (waitDuration.isNegative) {
          return Duration.zero;
        }
        return waitDuration;
      }

      // Handle waitForTwilight by calculating twilight time
      if (node.waitForTwilight != null && locationContext != null) {
        final twilightTime = _calculateTwilightWaitTime(
          currentTime,
          node.waitForTwilight!,
          locationContext,
        );
        if (twilightTime != null) {
          final waitDuration = twilightTime.difference(currentTime);
          if (waitDuration.isNegative) {
            // Twilight already passed - no wait needed
            return Duration.zero;
          }
          return waitDuration;
        }
      }
      return Duration.zero;
    }

    if (node is SlewNode) {
      return const Duration(seconds: 30);
    }

    if (node is CenterNode) {
      // Centering involves multiple plate solves and slews
      // Estimate: maxAttempts iterations of (expose + solve + slew)
      // In practice, usually succeeds in 1-3 attempts
      final estimatedAttempts = (node.maxAttempts / 2).ceil();
      final secsPerAttempt = 10.0 + _slewDurationSecs / 2; // solve + partial slew
      final totalSecs = estimatedAttempts * secsPerAttempt;
      return Duration(milliseconds: (totalSecs * 1000).round());
    }

    if (node is MeridianFlipNode) {
      // Flip includes: stop guiding, slew, recenter, restart guiding
      double totalSecs = _meridianFlipDurationSecs;
      if (node.autoCenter) {
        totalSecs += _centerDurationSecs;
      }
      totalSecs += node.settleTime;
      return Duration(milliseconds: (totalSecs * 1000).round());
    }

    if (node is FilterChangeNode) {
      return const Duration(seconds: 10);
    }

    if (node is RotatorNode) {
      return const Duration(seconds: 15);
    }

    if (node is ParkNode || node is UnparkNode) {
      return const Duration(seconds: 30);
    }

    if (node is CoolCameraNode) {
      final mins = node.durationMins ?? _defaultCoolingMins;
      return Duration(minutes: mins.round());
    }

    if (node is WarmCameraNode) {
      // Estimate warming time based on typical delta and rate
      // Assume 30C delta (e.g., -10C to +20C) at given rate
      final deltaTemp = 30.0;
      final mins = deltaTemp / node.ratePerMin;
      return Duration(minutes: mins.round());
    }

    if (node is StartGuidingNode) {
      return Duration(milliseconds: (node.settleTimeout * 1000).round());
    }

    if (node is StopGuidingNode) {
      return const Duration(seconds: 2);
    }

    if (node is OpenDomeNode ||
        node is CloseDomeNode ||
        node is ParkDomeNode) {
      return const Duration(seconds: 60);
    }

    if (node is PolarAlignmentNode) {
      // 3 plate solves + user adjustment time
      return const Duration(minutes: 5);
    }

    if (node is ScriptNode) {
      // Use timeout if specified, otherwise assume quick script
      return Duration(seconds: node.timeoutSecs ?? 30);
    }

    if (node is NotificationNode) {
      return Duration.zero; // Notifications are instantaneous
    }

    // Container nodes (TargetHeaderNode, LoopNode, ParallelNode, etc.)
    // have their duration determined by children, not intrinsically
    return Duration.zero;
  }

  /// Calculate visibility windows for all targets in a sequence.
  ///
  /// For each TargetHeaderNode in the sequence, calculates rise, transit, and
  /// set times based on the observer's location.
  ///
  /// [sequence] - The sequence containing target headers
  /// [date] - The date to calculate visibility for
  /// [latitude] - Observer latitude in degrees
  /// [longitude] - Observer longitude in degrees
  /// [minAltitude] - Minimum altitude in degrees for visibility (default: 0)
  ///
  /// Returns a map from target header node ID to [TargetWindow].
  Map<String, TargetWindow> calculateTargetWindows(
    Sequence sequence,
    DateTime date, {
    required double latitude,
    required double longitude,
    double minAltitude = _defaultMinAltitude,
  }) {
    final windows = <String, TargetWindow>{};

    // Find all TargetHeaderNode instances in the sequence
    for (final node in sequence.nodes.values) {
      if (node is TargetHeaderNode && node.isEnabled) {
        final visibility = AstronomyCalculations.calculateObjectVisibility(
          raDeg: node.raHours * 15.0, // Convert RA hours to degrees
          decDeg: node.decDegrees,
          date: date,
          latitudeDeg: latitude,
          longitudeDeg: longitude,
          minAltitude: minAltitude,
        );

        windows[node.id] = TargetWindow(
          targetId: node.id,
          targetName: node.targetName,
          riseTime: visibility.riseTime,
          transitTime: visibility.transitTime,
          setTime: visibility.setTime,
          transitAltitude: visibility.transitAltitude,
          isCircumpolar: visibility.isCircumpolar,
          neverRises: visibility.neverRises,
        );
      }
    }

    return windows;
  }

  /// Find timing conflicts between node execution times and target visibility.
  ///
  /// Checks each node's execution window against its target's visibility window
  /// and returns warnings for any conflicts (e.g., exposures scheduled when
  /// target is below horizon).
  ///
  /// [timings] - List of node timings from [estimateSequenceTiming]
  /// [windows] - Map of target windows from [calculateTargetWindows]
  /// [sequence] - The sequence being analyzed
  ///
  /// Returns a list of warning strings describing any conflicts found.
  List<String> findTimingConflicts(
    List<NodeTiming> timings,
    Map<String, TargetWindow> windows,
    Sequence sequence,
  ) {
    final conflicts = <String>[];

    for (final timing in timings) {
      // Skip nodes without a target header
      if (timing.targetHeaderId == null) continue;

      final window = windows[timing.targetHeaderId];
      if (window == null) continue;

      // Check if the node executes during the target's visibility window
      if (window.neverRises) {
        conflicts.add(
          '${window.targetName}: Target never rises above minimum altitude at this location',
        );
        continue;
      }

      if (window.isCircumpolar) {
        // Circumpolar targets are always visible, no conflict possible
        continue;
      }

      // Check start time
      if (!window.isVisibleAt(timing.estimatedStart)) {
        final targetNode = sequence.nodes[timing.targetHeaderId];
        final targetName =
            targetNode is TargetHeaderNode ? targetNode.targetName : 'Target';

        if (window.riseTime != null &&
            timing.estimatedStart.isBefore(window.riseTime!)) {
          conflicts.add(
            '$targetName: "${timing.nodeName}" scheduled at ${_formatTime(timing.estimatedStart)} '
            'before target rises at ${_formatTime(window.riseTime!)}',
          );
        } else if (window.setTime != null) {
          conflicts.add(
            '$targetName: "${timing.nodeName}" scheduled at ${_formatTime(timing.estimatedStart)} '
            'after target sets at ${_formatTime(window.setTime!)}',
          );
        }
      }

      // Check end time
      if (window.setTime != null &&
          timing.estimatedEnd.isAfter(window.setTime!) &&
          !window.isCircumpolar) {
        final targetNode = sequence.nodes[timing.targetHeaderId];
        final targetName =
            targetNode is TargetHeaderNode ? targetNode.targetName : 'Target';

        conflicts.add(
          '$targetName: "${timing.nodeName}" ends at ${_formatTime(timing.estimatedEnd)} '
          'after target sets at ${_formatTime(window.setTime!)}',
        );
      }
    }

    // Deduplicate conflicts (same target may have multiple nodes)
    return conflicts.toSet().toList();
  }

  /// Convenience method to perform full timing analysis.
  ///
  /// Combines [estimateSequenceTiming], [calculateTargetWindows], and
  /// [findTimingConflicts] into a single call.
  ///
  /// Returns a tuple of (timings, windows, conflicts).
  ({
    List<NodeTiming> timings,
    Map<String, TargetWindow> windows,
    List<String> conflicts,
  }) analyzeSequence(
    Sequence sequence,
    DateTime startTime, {
    required double latitude,
    required double longitude,
    double minAltitude = _defaultMinAltitude,
  }) {
    final timings = estimateSequenceTiming(
      sequence,
      startTime,
      latitude: latitude,
      longitude: longitude,
    );
    final windows = calculateTargetWindows(
      sequence,
      startTime,
      latitude: latitude,
      longitude: longitude,
      minAltitude: minAltitude,
    );
    final conflicts = findTimingConflicts(timings, windows, sequence);

    return (timings: timings, windows: windows, conflicts: conflicts);
  }

  /// Calculate the total estimated duration of a sequence.
  ///
  /// Note: For unbounded loops (forever, whileDark), this returns the duration
  /// of a single iteration only.
  ///
  /// [latitude] and [longitude] are optional but required for accurate twilight wait estimates.
  Duration estimateTotalDuration(
    Sequence sequence,
    DateTime startTime, {
    double? latitude,
    double? longitude,
  }) {
    final timings = estimateSequenceTiming(
      sequence,
      startTime,
      latitude: latitude,
      longitude: longitude,
    );
    if (timings.isEmpty) {
      return Duration.zero;
    }

    final lastTiming = timings.last;
    return lastTiming.estimatedEnd.difference(startTime);
  }
}
