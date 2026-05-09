import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backend/device_types.dart';
import '../models/equipment/equipment_models.dart';
import '../models/sequence/sequence_models.dart';
import 'equipment_provider.dart';
import 'sequence_provider.dart';
import 'settings_provider.dart';

// Re-use the validation types from the preflight dialog.
// We define them here so the provider layer doesn't depend on UI code.
// The UI's preflight_validation_dialog already has identical types; the app
// widget can import from either place. To avoid a circular dependency we
// duplicate only the tiny enum + value classes here and re-export them.

/// Validation issue severity
enum LiveValidationSeverity {
  error, // Cannot start sequence
  warning, // Can start but may cause issues
  info, // Informational
}

/// A single validation issue with optional node association
class LiveValidationIssue {
  final LiveValidationSeverity severity;
  final String category;
  final String title;
  final String description;
  final String? nodeId;
  final String? resolution;

  const LiveValidationIssue({
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    this.nodeId,
    this.resolution,
  });
}

/// Aggregated live validation state
class LiveValidationState {
  final List<LiveValidationIssue> issues;
  final Map<String, List<LiveValidationIssue>> issuesByNodeId;
  final int errorCount;
  final int warningCount;
  final int infoCount;
  final bool isValidating;

  const LiveValidationState({
    this.issues = const [],
    this.issuesByNodeId = const {},
    this.errorCount = 0,
    this.warningCount = 0,
    this.infoCount = 0,
    this.isValidating = false,
  });

  bool get hasErrors => errorCount > 0;
  bool get hasWarnings => warningCount > 0;
  int get totalCount => errorCount + warningCount + infoCount;

  /// Get worst severity for a specific node
  LiveValidationSeverity? worstSeverityForNode(String nodeId) {
    final nodeIssues = issuesByNodeId[nodeId];
    if (nodeIssues == null || nodeIssues.isEmpty) return null;
    if (nodeIssues.any((i) => i.severity == LiveValidationSeverity.error)) {
      return LiveValidationSeverity.error;
    }
    if (nodeIssues.any((i) => i.severity == LiveValidationSeverity.warning)) {
      return LiveValidationSeverity.warning;
    }
    return LiveValidationSeverity.info;
  }
}

/// Provider that runs live validation on the current sequence, debounced 500ms.
///
/// Watches:
/// - currentSequenceProvider (sequence structure changes)
/// - filterWheelStateProvider (connected filters)
/// - guiderStateProvider (guider connection)
/// - rotatorStateProvider (rotator connection)
/// - mountStateProvider (mount connection)
/// - cameraStateProvider (camera connection)
/// - focuserStateProvider (focuser connection)
final liveValidationProvider =
    StateNotifierProvider<LiveValidationNotifier, LiveValidationState>((ref) {
  return LiveValidationNotifier(ref);
});

class LiveValidationNotifier extends StateNotifier<LiveValidationState> {
  final Ref _ref;
  Timer? _debounceTimer;

  LiveValidationNotifier(this._ref) : super(const LiveValidationState()) {
    // Watch sequence changes
    _ref.listen(currentSequenceProvider, (_, __) {
      _scheduleValidation();
    });

    // Watch equipment state changes that affect validation
    _ref.listen(filterWheelStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(guiderStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(rotatorStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(mountStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(cameraStateProvider, (_, __) {
      _scheduleValidation();
    });
    _ref.listen(focuserStateProvider, (_, __) {
      _scheduleValidation();
    });

    // Run initial validation
    _scheduleValidation();
  }

  void _scheduleValidation() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _runValidation();
      }
    });
  }

  Future<void> _runValidation() async {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) {
      if (mounted) {
        state = const LiveValidationState();
      }
      return;
    }

    if (mounted) {
      state = LiveValidationState(
        issues: state.issues,
        issuesByNodeId: state.issuesByNodeId,
        errorCount: state.errorCount,
        warningCount: state.warningCount,
        infoCount: state.infoCount,
        isValidating: true,
      );
    }

    final issues = <LiveValidationIssue>[];

    // Run structural checks
    issues.addAll(_checkSequenceStructure(sequence));
    issues.addAll(_checkTargets(sequence));
    issues.addAll(_checkExposures(sequence));
    issues.addAll(_checkEquipment(sequence));
    issues.addAll(_checkFilterConflicts(sequence));
    issues.addAll(_checkSettings(sequence));
    issues.addAll(_checkTiming(sequence));

    // Build per-node issue map
    final byNode = <String, List<LiveValidationIssue>>{};
    for (final issue in issues) {
      if (issue.nodeId != null) {
        byNode.putIfAbsent(issue.nodeId!, () => []).add(issue);
      }
    }

    if (mounted) {
      state = LiveValidationState(
        issues: issues,
        issuesByNodeId: byNode,
        errorCount: issues
            .where((i) => i.severity == LiveValidationSeverity.error)
            .length,
        warningCount: issues
            .where((i) => i.severity == LiveValidationSeverity.warning)
            .length,
        infoCount: issues
            .where((i) => i.severity == LiveValidationSeverity.info)
            .length,
        isValidating: false,
      );
    }
  }

  // --------------------------------------------------------------------------
  // Validation checks (mirrors SequenceValidator but synchronous where possible
  // and adds conflict-specific checks)
  // --------------------------------------------------------------------------

  List<LiveValidationIssue> _checkSequenceStructure(Sequence sequence) {
    final issues = <LiveValidationIssue>[];

    if (sequence.nodes.isEmpty) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.error,
        category: 'Structure',
        title: 'Empty Sequence',
        description:
            'The sequence has no nodes. Add at least one instruction to run.',
        resolution: 'Add exposure or other instruction nodes to the sequence.',
      ));
    }

    if (sequence.rootNodeId == null) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.error,
        category: 'Structure',
        title: 'No Root Node',
        description: 'The sequence has no root node to execute.',
        resolution: 'Ensure the sequence has a root node.',
      ));
    }

    return issues;
  }

  List<LiveValidationIssue> _checkTargets(Sequence sequence) {
    final issues = <LiveValidationIssue>[];
    final targets = sequence.targetHeaders;
    final exposures = sequence.nodes.values
        .whereType<ExposureNode>()
        .where((n) => n.isEnabled)
        .toList();

    if (targets.isEmpty && exposures.isNotEmpty) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Targets',
        title: 'No Targets Defined',
        description:
            'Exposures exist but no target is defined. The mount will image at its current position.',
        resolution: 'Add a Target Group node with coordinates.',
      ));
    }

    for (final target in targets) {
      if (target.raHours < 0 || target.raHours >= 24) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.error,
          category: 'Targets',
          title: 'Invalid RA',
          description:
              'Target "${target.targetName}" has invalid RA: ${target.raHours}h',
          nodeId: target.id,
          resolution: 'RA must be between 0 and 24 hours.',
        ));
      }

      if (target.decDegrees < -90 || target.decDegrees > 90) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.error,
          category: 'Targets',
          title: 'Invalid Dec',
          description:
              'Target "${target.targetName}" has invalid Dec: ${target.decDegrees}°',
          nodeId: target.id,
          resolution: 'Declination must be between -90 and +90 degrees.',
        ));
      }

      if (target.childIds.isEmpty) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.warning,
          category: 'Targets',
          title: 'Empty Target',
          description: 'Target "${target.targetName}" has no instructions.',
          nodeId: target.id,
          resolution:
              'Add exposure or other instruction nodes to the target.',
        ));
      }

      // Check minimum altitude
      if (target.minAltitude != null && target.minAltitude! < 10) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.warning,
          category: 'Targets',
          title: 'Very Low Altitude Limit',
          description:
              'Target "${target.targetName}" minimum altitude is ${target.minAltitude}°. '
              'Imaging near the horizon may result in poor quality.',
          nodeId: target.id,
          resolution: 'Consider setting minimum altitude to 20° or higher.',
        ));
      }

      // Conflict: Target has rotation set but no rotator connected
      if (target.rotation != null) {
        final rotatorState = _ref.read(rotatorStateProvider);
        if (rotatorState.connectionState != DeviceConnectionState.connected) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Equipment',
            title: 'Rotator Not Connected',
            description:
                'Target "${target.targetName}" specifies rotation (${target.rotation!.toStringAsFixed(1)}°) '
                'but no rotator is connected.',
            nodeId: target.id,
            resolution: 'Connect a rotator or remove the rotation setting.',
          ));
        }
      }
    }

    return issues;
  }

  List<LiveValidationIssue> _checkExposures(Sequence sequence) {
    final issues = <LiveValidationIssue>[];
    final exposures = sequence.nodes.values
        .whereType<ExposureNode>()
        .where((n) => n.isEnabled)
        .toList();

    if (exposures.isEmpty) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Imaging',
        title: 'No Exposures',
        description:
            'No exposure nodes found. The sequence will run but capture no images.',
        resolution: 'Add Exposure nodes to capture images.',
      ));
      return issues;
    }

    for (final exposure in exposures) {
      if (exposure.durationSecs <= 0) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.error,
          category: 'Imaging',
          title: 'Invalid Exposure Time',
          description:
              'Exposure "${exposure.name}" has invalid duration: ${exposure.durationSecs}s',
          nodeId: exposure.id,
          resolution: 'Set a positive exposure duration.',
        ));
      }

      if (exposure.durationSecs > 1800) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.warning,
          category: 'Imaging',
          title: 'Very Long Exposure',
          description:
              'Exposure "${exposure.name}" is ${(exposure.durationSecs / 60).toStringAsFixed(0)} minutes. '
              'Very long exposures may fail due to tracking errors.',
          nodeId: exposure.id,
          resolution:
              'Consider breaking into shorter exposures or using auto-guiding.',
        ));
      }

      if (exposure.count <= 0) {
        issues.add(LiveValidationIssue(
          severity: LiveValidationSeverity.error,
          category: 'Imaging',
          title: 'Invalid Frame Count',
          description:
              'Exposure "${exposure.name}" has count of ${exposure.count}.',
          nodeId: exposure.id,
          resolution: 'Set at least 1 frame to capture.',
        ));
      }
    }

    return issues;
  }

  /// Check equipment connection status based on required devices
  List<LiveValidationIssue> _checkEquipment(Sequence sequence) {
    final issues = <LiveValidationIssue>[];

    // Collect required device types from enabled nodes
    final requiredDevices = <DeviceType>{};
    for (final node in sequence.nodes.values) {
      if (node.isEnabled) {
        requiredDevices.addAll(node.requiredDevices);
      }
    }

    if (requiredDevices.isEmpty) return issues;

    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final fwState = _ref.read(filterWheelStateProvider);
    final guiderState = _ref.read(guiderStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);

    if (requiredDevices.contains(DeviceType.camera) &&
        cameraState.connectionState != DeviceConnectionState.connected) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.error,
        category: 'Equipment',
        title: 'No Camera Connected',
        description: 'This sequence requires a camera to capture images.',
        resolution: 'Connect a camera in the Equipment panel.',
      ));
    }

    if (requiredDevices.contains(DeviceType.mount) &&
        mountState.connectionState != DeviceConnectionState.connected) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Equipment',
        title: 'No Mount Connected',
        description:
            'This sequence includes slewing or tracking operations that require a mount.',
        resolution: 'Connect a mount in the Equipment panel.',
      ));
    }

    if (requiredDevices.contains(DeviceType.focuser) &&
        focuserState.connectionState != DeviceConnectionState.connected) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Equipment',
        title: 'No Focuser Connected',
        description:
            'This sequence includes autofocus operations that require a focuser.',
        resolution: 'Connect a focuser in the Equipment panel.',
      ));
    }

    if (requiredDevices.contains(DeviceType.filterWheel) &&
        fwState.connectionState != DeviceConnectionState.connected) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Equipment',
        title: 'No Filter Wheel Connected',
        description:
            'This sequence includes filter changes that require a filter wheel.',
        resolution: 'Connect a filter wheel in the Equipment panel.',
      ));
    }

    if (requiredDevices.contains(DeviceType.guider) &&
        guiderState.connectionState != DeviceConnectionState.connected) {
      // Per-node warnings for guider nodes
      for (final node in sequence.nodes.values) {
        if (node.isEnabled &&
            node.requiredDevices.contains(DeviceType.guider)) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Equipment',
            title: 'Guider Not Connected',
            description:
                '${node.name} requires a guider (PHD2) but none is connected.',
            nodeId: node.id,
            resolution: 'Connect to PHD2 in the Guiding panel.',
          ));
        }
      }
    }

    if (requiredDevices.contains(DeviceType.rotator) &&
        rotatorState.connectionState != DeviceConnectionState.connected) {
      issues.add(const LiveValidationIssue(
        severity: LiveValidationSeverity.warning,
        category: 'Equipment',
        title: 'No Rotator Connected',
        description: 'This sequence includes rotator operations.',
        resolution: 'Connect a rotator in the Equipment panel.',
      ));
    }

    return issues;
  }

  /// Conflict-specific checks: filter names not in wheel, etc.
  List<LiveValidationIssue> _checkFilterConflicts(Sequence sequence) {
    final issues = <LiveValidationIssue>[];
    final fwState = _ref.read(filterWheelStateProvider);

    // Only check filter conflicts if a filter wheel is connected
    if (fwState.connectionState != DeviceConnectionState.connected) {
      return issues;
    }

    final availableFilters =
        fwState.filterNames.map((f) => f.toLowerCase()).toSet();
    if (availableFilters.isEmpty) return issues;

    // Check exposure nodes with filter names not in the wheel
    for (final node in sequence.nodes.values) {
      if (!node.isEnabled) continue;

      if (node is ExposureNode && node.filter != null) {
        if (!availableFilters.contains(node.filter!.toLowerCase())) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Filters',
            title: 'Filter Not in Wheel',
            description:
                'Exposure "${node.name}" uses filter "${node.filter}" which is not '
                'in the connected filter wheel. Available: ${fwState.filterNames.join(", ")}.',
            nodeId: node.id,
            resolution:
                'Change the filter name or check the filter wheel configuration.',
          ));
        }
      }

      if (node is FilterChangeNode) {
        if (!availableFilters.contains(node.filterName.toLowerCase())) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Filters',
            title: 'Filter Not in Wheel',
            description:
                'Filter change "${node.name}" uses filter "${node.filterName}" which is not '
                'in the connected filter wheel. Available: ${fwState.filterNames.join(", ")}.',
            nodeId: node.id,
            resolution:
                'Change the filter name or check the filter wheel configuration.',
          ));
        }
      }
    }

    return issues;
  }

  List<LiveValidationIssue> _checkSettings(Sequence sequence) {
    final issues = <LiveValidationIssue>[];

    // Check if image output path is configured
    final appSettingsAsync = _ref.read(appSettingsProvider);
    final appSettings = appSettingsAsync.valueOrNull;
    if (appSettings == null || appSettings.imageOutputPath.isEmpty) {
      final hasExposures = sequence.nodes.values
          .whereType<ExposureNode>()
          .any((n) => n.isEnabled);
      if (hasExposures) {
        issues.add(const LiveValidationIssue(
          severity: LiveValidationSeverity.warning,
          category: 'Settings',
          title: 'No Image Save Path',
          description:
              'No image output directory is configured. Captured images will NOT be saved to disk.',
          resolution: 'Configure an image save location in Settings.',
        ));
      }
    }

    // Check for meridian flip trigger in long sequences with targets
    final targets = sequence.targetHeaders;
    if (targets.isNotEmpty) {
      final hasMeridianFlipNode = sequence.nodes.values
          .any((node) => node is MeridianFlipNode && node.isEnabled);
      final hasRecoveryWithMeridianFlip = sequence.nodes.values.any((node) =>
          node is RecoveryNode &&
          node.isEnabled &&
          node.triggerType == TriggerType.meridianFlip);

      if (!hasMeridianFlipNode && !hasRecoveryWithMeridianFlip) {
        double totalExposureMins = 0;
        for (final node in sequence.nodes.values) {
          if (node is ExposureNode && node.isEnabled) {
            totalExposureMins += (node.durationSecs * node.count) / 60.0;
          }
        }
        if (totalExposureMins >= 120) {
          issues.add(const LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Mount',
            title: 'No Meridian Flip Trigger',
            description:
                'This sequence has targets and runs for over 2 hours but has no meridian flip trigger.',
            resolution:
                'Add a MeridianFlip node or enable auto meridian flip in Settings.',
          ));
        }
      }
    }

    return issues;
  }

  List<LiveValidationIssue> _checkTiming(Sequence sequence) {
    final issues = <LiveValidationIssue>[];

    for (final node in sequence.nodes.values) {
      if (node is WaitTimeNode && node.waitUntil != null) {
        if (node.waitUntil!.isBefore(DateTime.now())) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Timing',
            title: 'Wait Time Passed',
            description:
                'Wait node "${node.name}" is set for a time that has already passed.',
            nodeId: node.id,
            resolution: 'Update the wait time or remove the node.',
          ));
        }
      }

      if (node is LoopNode && node.repeatUntil != null) {
        if (node.repeatUntil!.isBefore(DateTime.now())) {
          issues.add(LiveValidationIssue(
            severity: LiveValidationSeverity.warning,
            category: 'Timing',
            title: 'Loop End Time Passed',
            description: 'Loop "${node.name}" end time has already passed.',
            nodeId: node.id,
            resolution: 'Update the end time or change loop condition.',
          ));
        }
      }
    }

    return issues;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
