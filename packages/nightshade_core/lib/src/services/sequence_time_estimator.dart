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
  const SequenceTimeEstimator();

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
  static const int _defaultScriptTimeoutSecs = 60;

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

    if (node is TargetHeaderNode) {
      final startAfter = _effectiveStartAfter(node);
      if (startAfter != null && currentTime.isBefore(startAfter)) {
        currentTime = startAfter;
      }
    }

    // Update target header ID if this is a target header node
    final targetId = node is TargetHeaderNode ? node.id : currentTargetHeaderId;

    // Calculate duration for this node
    final nodeDuration =
        _estimateNodeDuration(node, currentTime, locationContext);

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

      // Handle loop nodes specially - the timeline still renders detail for a
      // SINGLE iteration (with a "1 of N" warning), but the cumulative clock
      // must advance by the full loop so downstream nodes + the
      // meridian/dawn conflict checks see the real end time. Previously the
      // clock only advanced one pass, so a Count loop under-reported its
      // duration by the loop factor (e.g. Loop(count=50) over a 5-min body
      // showed ~5 min instead of ~250 min). For unbounded / condition-based
      // loops the iteration count isn't known statically, so we keep the
      // single-pass estimate (documented by the warning note).
      if (node is LoopNode) {
        final loopNote = _getLoopIterationNote(node);
        final loopStartTime = currentTime;
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
        if (node.conditionType == LoopConditionType.count) {
          final iterations = node.repeatCount ?? 1;
          if (iterations > 1) {
            final singlePass = currentTime.difference(loopStartTime);
            // Advance the clock by the remaining (count - 1) iterations'
            // worth of body time. The first pass is already reflected in
            // `currentTime` (and rendered in the timeline).
            currentTime = currentTime.add(singlePass * (iterations - 1));
          }
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
          return 'Loop until altitude below ${alt.toStringAsFixed(0)} degrees - showing single iteration';
        }
        return 'Altitude-based loop - showing single iteration estimate';
      case LoopConditionType.altitudeAbove:
        final alt = node.repeatUntilAltitude;
        if (alt != null) {
          return 'Loop until altitude above ${alt.toStringAsFixed(0)} degrees - showing single iteration';
        }
        return 'Altitude-based loop - showing single iteration estimate';
      case LoopConditionType.integrationTime:
        final target = node.integrationTimeTarget;
        if (target != null && target > 0) {
          final mins = (target / 60).round();
          return 'Loop until ${mins}m integration time reached - showing single iteration';
        }
        return 'Integration time loop - showing single iteration estimate';
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
    // Exhaustive switch over the sealed SequenceNode hierarchy. A new node
    // subtype will fail to compile here rather than silently fall through to
    // a zero-duration default and mis-estimate sequence timing.
    return switch (node) {
      ExposureNode() => Duration(
          milliseconds: ((node.count * node.durationSecs +
                      node.count * _downloadOverheadSecs) *
                  1000)
              .round(),
        ),
      // Wave 3 Agent 2: SmartExposure. Sum of (count * duration) across
      // all plans + per-frame download overhead + one filter-change penalty
      // per plan + dither-cost for each dither point. When an integration
      // budget is set and is lower than the natural duration, we clamp to
      // the budget so the Run Dashboard's "estimated total" shrinks to
      // match expected behaviour.
      SmartExposureNode() => () {
          if (node.plans.isEmpty) return Duration.zero;
          // Per-plan integration time + per-frame download overhead.
          double secs = 0.0;
          for (final p in node.plans) {
            secs += p.count * p.durationSecs;
            secs += p.count * _downloadOverheadSecs;
            // Dither cost: one settle cycle per ditherEvery frames (treat
            // 0 / null as "no dither"). Same heuristic as ExposureNode but
            // applied per-plan.
            final every = p.ditherEvery ?? 0;
            if (every > 0) {
              final ditherCount = (p.count / every).floor();
              secs += ditherCount * _ditherDurationSecs;
            }
          }
          // One filter change per plan (skipped only if two consecutive
          // plans share the same filter — the estimator can't tell which
          // ones will overlap with the live current-filter state, so we
          // assume worst case). 10s mirrors the FilterChangeNode case
          // below.
          const filterChangeDurationSecs = 10.0;
          secs += node.plans.length * filterChangeDurationSecs;
          // Clamp to the integration budget when one is set. The budget
          // measures *integration* not wall-clock — we approximate by
          // capping the integration component only.
          if (node.integrationBudgetSecs > 0 &&
              node.totalIntegrationSecs > node.integrationBudgetSecs) {
            final overshoot =
                node.totalIntegrationSecs - node.integrationBudgetSecs;
            secs -= overshoot;
          }
          return Duration(milliseconds: (secs * 1000).round());
        }(),
      AutofocusNode() => Duration(
          milliseconds: (((node.stepsOut * 2 + 1) *
                      node.exposuresPerPoint *
                      node.exposureDuration) *
                  1000)
              .round(),
        ),
      DitherNode() => Duration(
          milliseconds:
              (((node.settleTime > 0 ? node.settleTime : _ditherDurationSecs)) *
                      1000)
                  .round(),
        ),
      DelayNode() => Duration(milliseconds: (node.seconds * 1000).round()),
      WaitTimeNode() =>
        _estimateWaitTimeDuration(node, currentTime, locationContext),
      SlewNode() => const Duration(seconds: 30),
      CenterNode() => () {
          // Centering involves multiple plate solves and slews. Estimate:
          // maxAttempts iterations of (expose + solve + slew). In practice,
          // usually succeeds in 1-3 attempts.
          final estimatedAttempts = (node.maxAttempts / 2).ceil();
          const secsPerAttempt = 10.0 + _slewDurationSecs / 2;
          final totalSecs = estimatedAttempts * secsPerAttempt;
          return Duration(milliseconds: (totalSecs * 1000).round());
        }(),
      MeridianFlipNode() => () {
          // Flip includes: stop guiding, slew, recenter, restart guiding.
          double totalSecs = _meridianFlipDurationSecs;
          if (node.autoCenter) {
            totalSecs += _centerDurationSecs;
          }
          totalSecs += node.settleTime;
          return Duration(milliseconds: (totalSecs * 1000).round());
        }(),
      FilterChangeNode() => const Duration(seconds: 10),
      RotatorNode() => const Duration(seconds: 15),
      ParkNode() || UnparkNode() => const Duration(seconds: 30),
      CoolCameraNode() =>
        Duration(minutes: (node.durationMins ?? _defaultCoolingMins).round()),
      WarmCameraNode() => () {
          // Estimate warming time using a typical 30 C delta (e.g., -10 to +20)
          // at the configured rate.
          const deltaTemp = 30.0;
          final mins = deltaTemp / node.ratePerMin;
          return Duration(minutes: mins.round());
        }(),
      StartGuidingNode() =>
        Duration(milliseconds: (node.settleTimeout * 1000).round()),
      StopGuidingNode() => const Duration(seconds: 2),
      OpenDomeNode() ||
      CloseDomeNode() ||
      ParkDomeNode() =>
        const Duration(seconds: 60),
      // Mechanical cover and calibrator toggles are quick — ~5 seconds covers
      // both the dust cover motion and the EL panel power cycle.
      OpenCoverNode() ||
      CloseCoverNode() ||
      CalibratorOnNode() ||
      CalibratorOffNode() =>
        const Duration(seconds: 5),
      PolarAlignmentNode() => const Duration(minutes: 5),
      ScriptNode() =>
        Duration(seconds: node.timeoutSecs ?? _defaultScriptTimeoutSecs),
      NotificationNode() => Duration.zero,
      // Container nodes (TargetHeaderNode, LoopNode, ParallelNode,
      // ConditionalNode, RecoveryNode, InstructionSetNode) have no intrinsic
      // duration — their cost is the sum of their children, handled by the
      // recursive walk in `_processNode`.
      TargetHeaderNode() ||
      LoopNode() ||
      ParallelNode() ||
      ConditionalNode() ||
      RecoveryNode() ||
      InstructionSetNode() ||
      // Wave 3 Agent 1: TargetScheduler — duration is the sum of its
      // selected child's runtime, accounted for by the recursive walker.
      TargetSchedulerNode() ||
      // Wave 7 Agent 2: LiveStacking — side-effect node that arms the
      // broadcast service and returns immediately. The actual wall-clock
      // cost is paid by sibling exposure nodes, which are accounted for
      // separately. Zero intrinsic duration.
      LiveStackingNode() =>
        Duration.zero,
      // Wave 7 Science: SciencePhotometry — count * exposure + per-frame
      // download overhead, plus one filter change at the start. No
      // dithering during photometry runs.
      SciencePhotometryNode() => Duration(
          milliseconds: ((node.count * node.exposureSecs +
                      node.count * _downloadOverheadSecs +
                      10.0 /* filter change */) *
                  1000)
              .round(),
        ),
      // Audit §11 — plugin nodes execute opaque user-authored logic.
      // We cannot estimate their duration without round-tripping into
      // the plugin, so we use the optional per-node timeout as the
      // upper bound; with no timeout configured the estimator returns
      // zero (matching how it treats NotificationNode and other
      // short-running side effects).
      PluginInstructionNode() => node.timeoutSecs != null && node.timeoutSecs! > 0
          ? Duration(seconds: node.timeoutSecs!)
          : Duration.zero,
    };
  }

  /// Helper for [_estimateNodeDuration] that resolves a [WaitTimeNode] to a
  /// concrete duration, supporting both absolute wait-until timestamps and
  /// twilight-relative waits when a location context is available.
  Duration _estimateWaitTimeDuration(
    WaitTimeNode node,
    DateTime currentTime,
    _LocationContext? locationContext,
  ) {
    if (node.waitUntil != null) {
      final waitDuration = node.waitUntil!.difference(currentTime);
      if (waitDuration.isNegative) {
        return Duration.zero;
      }
      return waitDuration;
    }

    if (node.waitForTwilight != null && locationContext != null) {
      final twilightTime = _calculateTwilightWaitTime(
        currentTime,
        node.waitForTwilight!,
        locationContext,
      );
      if (twilightTime != null) {
        final waitDuration = twilightTime.difference(currentTime);
        if (waitDuration.isNegative) {
          return Duration.zero;
        }
        return waitDuration;
      }
    }
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
        final effectiveMinAltitude = _effectiveMinAltitude(node, minAltitude);
        final visibility = AstronomyCalculations.calculateObjectVisibility(
          raDeg: node.raHours * 15.0, // Convert RA hours to degrees
          decDeg: node.decDegrees,
          date: date,
          latitudeDeg: latitude,
          longitudeDeg: longitude,
          minAltitude: effectiveMinAltitude,
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
      final targetNode = sequence.nodes[timing.targetHeaderId];
      final targetName =
          targetNode is TargetHeaderNode ? targetNode.targetName : 'Target';

      if (targetNode is TargetHeaderNode) {
        final startAfter = _effectiveStartAfter(targetNode);
        if (startAfter != null && timing.estimatedStart.isBefore(startAfter)) {
          conflicts.add(
            '$targetName: "${timing.nodeName}" scheduled at ${_formatTime(timing.estimatedStart)} '
            'before target start time ${_formatTime(startAfter)}',
          );
        }

        final endBefore = _effectiveEndBefore(targetNode);
        if (endBefore != null && timing.estimatedEnd.isAfter(endBefore)) {
          conflicts.add(
            '$targetName: "${timing.nodeName}" ends at ${_formatTime(timing.estimatedEnd)} '
            'after target end time ${_formatTime(endBefore)}',
          );
        }
      }

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
        conflicts.add(
          '$targetName: "${timing.nodeName}" ends at ${_formatTime(timing.estimatedEnd)} '
          'after target sets at ${_formatTime(window.setTime!)}',
        );
      }
    }

    // Deduplicate conflicts (same target may have multiple nodes)
    return conflicts.toSet().toList();
  }

  DateTime? _effectiveStartAfter(TargetHeaderNode node) {
    final triggerTime = _startTimeAfter(node.startWhen);
    return _maxDate(node.startAfter, triggerTime);
  }

  DateTime? _effectiveEndBefore(TargetHeaderNode node) {
    final triggerTime = _endTimeAfter(node.endWhen);
    return _minDate(node.endBefore, triggerTime);
  }

  double _effectiveMinAltitude(TargetHeaderNode node, double globalMinAltitude) {
    final triggerAltitude = _startAltitudeAbove(node.startWhen);
    return [
      globalMinAltitude,
      if (node.minAltitude != null) node.minAltitude!,
      if (triggerAltitude != null) triggerAltitude,
    ].reduce((a, b) => a > b ? a : b);
  }

  DateTime? _startTimeAfter(TargetTrigger? trigger) {
    return switch (trigger) {
      null => null,
      TimeAfterTrigger(unixSeconds: final ts) => _fromUnixSeconds(ts),
      AndTrigger(children: final children) => children
          .map(_startTimeAfter)
          .whereType<DateTime>()
          .fold<DateTime?>(null, _maxDate),
      // An OR can be satisfied by a non-time term, so waiting on one branch
      // would fabricate precision the runtime does not guarantee.
      OrTrigger() => null,
      _ => null,
    };
  }

  DateTime? _endTimeAfter(TargetTrigger? trigger) {
    return switch (trigger) {
      null => null,
      TimeAfterTrigger(unixSeconds: final ts) => _fromUnixSeconds(ts),
      OrTrigger(children: final children) => children
          .map(_endTimeAfter)
          .whereType<DateTime>()
          .fold<DateTime?>(null, _minDate),
      // AND requires every term to become true, so a TimeAfter child is only
      // a lower bound, not a reliable stop cap.
      AndTrigger() => null,
      _ => null,
    };
  }

  double? _startAltitudeAbove(TargetTrigger? trigger) {
    return switch (trigger) {
      null => null,
      AltitudeAboveTrigger(altitudeDeg: final altitude) => altitude,
      AndTrigger(children: final children) => children
          .map(_startAltitudeAbove)
          .whereType<double>()
          .fold<double?>(null, (current, next) {
        if (current == null) return next;
        return current > next ? current : next;
      }),
      // As with time ORs, an altitude OR may be satisfied by a different
      // branch; treating it as a hard floor would over-constrain simulation.
      OrTrigger() => null,
      _ => null,
    };
  }

  DateTime _fromUnixSeconds(int unixSeconds) =>
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);

  DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  DateTime? _minDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
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

    // The cumulative end clock is the latest end across all timing entries
    // PLUS any time the walk advanced past the last rendered entry. The
    // latter matters for Count loops: the timeline renders one iteration of
    // body detail (the last timing entry ends at the first pass), but the
    // walk advances the clock by the full loop. Re-walk to recover that
    // end-of-sequence clock and take the max so a loop-bounded sequence
    // reports its real duration.
    final walkEnd = _walkEndTime(
      sequence,
      startTime,
      latitude: latitude,
      longitude: longitude,
    );
    final lastTiming = timings.last;
    final end = lastTiming.estimatedEnd.isAfter(walkEnd)
        ? lastTiming.estimatedEnd
        : walkEnd;
    return end.difference(startTime);
  }

  /// Walks the sequence the same way [estimateSequenceTiming] does but returns
  /// the final cumulative clock instead of the per-node timing list. Used by
  /// [estimateTotalDuration] so loop-multiplied time (which advances the clock
  /// without adding a timeline entry) is reflected in the total.
  DateTime _walkEndTime(
    Sequence sequence,
    DateTime startTime, {
    double? latitude,
    double? longitude,
  }) {
    final throwaway = <NodeTiming>[];
    final locationContext = (latitude != null && longitude != null)
        ? _LocationContext(
            latitude: latitude,
            longitude: longitude,
            date: startTime,
          )
        : null;

    var currentTime = startTime;
    if (sequence.rootNodeId == null) {
      for (final target in sequence.targetHeaders) {
        currentTime = _processNode(
          node: target,
          sequence: sequence,
          currentTime: currentTime,
          timings: throwaway,
          currentTargetHeaderId: target.id,
          loopIterationNote: null,
          locationContext: locationContext,
        );
      }
    } else {
      final rootNode = sequence.nodes[sequence.rootNodeId];
      if (rootNode != null && rootNode.isEnabled) {
        currentTime = _processNode(
          node: rootNode,
          sequence: sequence,
          currentTime: currentTime,
          timings: throwaway,
          currentTargetHeaderId: null,
          loopIterationNote: null,
          locationContext: locationContext,
        );
      }
    }
    return currentTime;
  }
}
