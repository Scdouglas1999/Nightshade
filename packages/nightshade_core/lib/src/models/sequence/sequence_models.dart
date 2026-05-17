import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../imaging/imaging_models.dart' show FrameType;
import '../meridian_flip_settings.dart'
    show MeridianTriggerMethod, FlipFailureAction;
export '../meridian_flip_settings.dart'
    show MeridianTriggerMethod, FlipFailureAction;
import '../../backend/nightshade_backend.dart' show DeviceType;

/// Sequence execution state
enum SequenceExecutionState {
  idle,
  running,
  paused,
  stopping,
  completed,
  failed
}

/// Node execution status
enum NodeStatus { pending, running, success, failure, skipped, cancelled }

// FrameType is imported from imaging_models.dart

/// Binning options
enum BinningMode { one, two, three, four }

extension BinningModeExtension on BinningMode {
  String get label {
    switch (this) {
      case BinningMode.one:
        return '1x1';
      case BinningMode.two:
        return '2x2';
      case BinningMode.three:
        return '3x3';
      case BinningMode.four:
        return '4x4';
    }
  }
}

/// Autofocus method
enum AutofocusMethod { vCurve, hyperbolic, quadratic }

/// Loop condition type
enum LoopConditionType {
  count,
  untilTime,
  untilAltitude,

  /// Loop until altitude is above threshold (condition_value = altitude degrees).
  /// Note: untilAltitude means "below", altitudeAbove means "above".
  altitudeAbove,

  /// Loop until accumulated integration time reaches threshold (condition_value = seconds)
  integrationTime,
  forever,
  whileDark,
}

/// Configurable per-operation overhead estimates for realistic time estimation.
/// These values represent typical real-world durations for each operation
/// beyond the raw integration time.
class SequenceOverheadConfig extends Equatable {
  /// Time for a slew operation (seconds)
  final double slewSecs;

  /// Time for an autofocus run (seconds)
  final double autofocusSecs;

  /// Time for a filter wheel change (seconds)
  final double filterChangeSecs;

  /// Time for a dither + settle cycle (seconds)
  final double ditherSecs;

  /// Time for a meridian flip including re-centering (seconds)
  final double meridianFlipSecs;

  /// Time for guide acquisition and settle (seconds)
  final double guideAcquireSecs;

  /// Time for a plate solve (seconds)
  final double plateSolveSecs;

  /// Time for camera cool-down (seconds)
  final double coolingSecs;

  /// Time for camera warm-up (seconds)
  final double warmingSecs;

  /// Per-exposure download overhead (seconds)
  final double downloadOverheadPerExposureSecs;

  /// Time for cover calibrator open/close (seconds)
  final double coverMoveSecs;

  /// Time for center target operation (plate solve + slew iterations) (seconds)
  final double centerTargetSecs;

  const SequenceOverheadConfig({
    this.slewSecs = 30.0,
    this.autofocusSecs = 180.0,
    this.filterChangeSecs = 10.0,
    this.ditherSecs = 15.0,
    this.meridianFlipSecs = 300.0,
    this.guideAcquireSecs = 30.0,
    this.plateSolveSecs = 15.0,
    this.coolingSecs = 600.0,
    this.warmingSecs = 300.0,
    this.downloadOverheadPerExposureSecs = 3.0,
    this.coverMoveSecs = 30.0,
    this.centerTargetSecs = 45.0,
  });

  @override
  List<Object?> get props => [
        slewSecs,
        autofocusSecs,
        filterChangeSecs,
        ditherSecs,
        meridianFlipSecs,
        guideAcquireSecs,
        plateSolveSecs,
        coolingSecs,
        warmingSecs,
        downloadOverheadPerExposureSecs,
        coverMoveSecs,
        centerTargetSecs,
      ];
}

/// Result of sequence integration time estimation
class SequenceEstimate extends Equatable {
  /// Estimated total integration time in seconds (pure shutter-open time)
  final double estimatedSecs;

  /// Estimated total overhead time in seconds (slews, AF, dithers, etc.)
  final double overheadSecs;

  /// Time for a single iteration (useful for unbounded loops)
  final double singleIterationSecs;

  /// Whether the sequence contains unbounded loops (forever, whileDark, etc.)
  final bool isUnbounded;

  /// For untilTime loops, the target end time
  final DateTime? untilTime;

  /// For unbounded loops, the condition type
  final LoopConditionType? conditionType;

  const SequenceEstimate({
    required this.estimatedSecs,
    this.overheadSecs = 0,
    required this.singleIterationSecs,
    required this.isUnbounded,
    this.untilTime,
    this.conditionType,
  });

  /// Total estimated wall-clock time (integration + overhead)
  double get totalEstimatedSecs => estimatedSecs + overheadSecs;

  /// Format the estimate as a human-readable string
  String format() {
    if (isUnbounded) {
      final iterationMins = (singleIterationSecs / 60).round();
      return '${iterationMins}m/iter (unbounded)';
    }
    final hours = (estimatedSecs / 3600).floor();
    final mins = ((estimatedSecs % 3600) / 60).round();
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Format with overhead-aware total time display
  /// Returns "Integration: 6h 30m | Est. total: ~9h 15m"
  String formatWithOverhead() {
    final integrationStr = format();
    if (overheadSecs <= 0 || isUnbounded) {
      return integrationStr;
    }
    final totalSecs = totalEstimatedSecs;
    final totalHours = (totalSecs / 3600).floor();
    final totalMins = ((totalSecs % 3600) / 60).round();
    String totalStr;
    if (totalHours > 0) {
      totalStr = '~${totalHours}h ${totalMins}m';
    } else {
      totalStr = '~${totalMins}m';
    }
    return 'Integration: $integrationStr | Est. total: $totalStr';
  }

  @override
  List<Object?> get props => [
        estimatedSecs,
        overheadSecs,
        singleIterationSecs,
        isUnbounded,
        untilTime,
        conditionType,
      ];
}

/// Conditional check type
enum ConditionalType {
  always,
  altitudeAbove,
  timeAfter,
  guidingRmsBelow,
  hfrBelow,
  weatherSafe,
  moonSeparationAbove,
  safetyMonitorSafe,
}

/// Recovery action type
enum RecoveryActionType {
  continueExecution,
  pause,
  autofocus,
  nextTarget,
  retry,
  parkAndAbort,
  customBranch
}

/// Trigger type
enum TriggerType {
  hfrDegraded,
  meridianFlip,
  guidingFailed,
  altitudeLimit,
  weatherUnsafe,
  temperatureShift,
  filterChange,
  dawnApproaching,
}

/// Notification level
enum NotificationLevel { info, warning, error, success }

/// Twilight type
enum TwilightType { civil, nautical, astronomical }

/// Base class for all sequence nodes.
///
/// Sealed for exhaustive switch matching: every `switch (node)` statement
/// must cover all 32 subtypes (or use a `_` wildcard) — adding a new node
/// type will produce compile-time errors at every dispatch site that
/// hasn't been updated.
///
/// All subclasses are declared in this same library, which is the
/// requirement for sealed types.
sealed class SequenceNode extends Equatable {
  final String id;
  final String name;
  final bool isEnabled;
  final List<String> childIds;
  final String? parentId;
  final int orderIndex;

  /// Optional user comment/annotation for this node
  final String? comment;

  SequenceNode({
    String? id,
    required this.name,
    this.isEnabled = true,
    this.childIds = const [],
    this.parentId,
    this.orderIndex = 0,
    this.comment,
  }) : id = id ?? const Uuid().v4();

  /// Get the node type identifier
  String get nodeType;

  /// Get the icon name for this node
  String get iconName;

  /// Get the color category for this node
  NodeCategory get category;

  /// Device types required by this node to execute.
  /// Override in subclasses that need specific hardware.
  Set<DeviceType> get requiredDevices => {};

  /// Create a copy with updated values
  SequenceNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  });

  @override
  List<Object?> get props =>
      [id, name, isEnabled, childIds, parentId, orderIndex, comment];
}

/// Node category for coloring
enum NodeCategory { instruction, trigger, logic, target }

// =============================================================================
// MOSAIC PANEL INFO
// =============================================================================

/// Information about a mosaic panel for multi-panel imaging
class MosaicPanelInfo extends Equatable {
  final String mosaicName;
  final int panelIndex;
  final int totalPanels;
  final int row;
  final int column;

  const MosaicPanelInfo({
    required this.mosaicName,
    required this.panelIndex,
    required this.totalPanels,
    required this.row,
    required this.column,
  });

  String get displayLabel => 'Panel ${panelIndex + 1}/$totalPanels';

  MosaicPanelInfo copyWith({
    String? mosaicName,
    int? panelIndex,
    int? totalPanels,
    int? row,
    int? column,
  }) {
    return MosaicPanelInfo(
      mosaicName: mosaicName ?? this.mosaicName,
      panelIndex: panelIndex ?? this.panelIndex,
      totalPanels: totalPanels ?? this.totalPanels,
      row: row ?? this.row,
      column: column ?? this.column,
    );
  }

  Map<String, dynamic> toJson() => {
        'mosaic_name': mosaicName,
        'panel_index': panelIndex,
        'total_panels': totalPanels,
        'row': row,
        'column': column,
      };

  factory MosaicPanelInfo.fromJson(Map<String, dynamic> json) =>
      MosaicPanelInfo(
        mosaicName: json['mosaic_name'] as String,
        panelIndex: json['panel_index'] as int,
        totalPanels: json['total_panels'] as int,
        row: json['row'] as int,
        column: json['column'] as int,
      );

  @override
  List<Object?> get props => [mosaicName, panelIndex, totalPanels, row, column];
}

// =============================================================================
// CONTAINER / LOGIC NODES
// =============================================================================

/// Target header - the root node containing imaging instructions for a target.
/// Each target acts as an independent root in the sequence tree.
/// Provides rich display with coordinates, altitude plot, and progress tracking.
class TargetHeaderNode extends SequenceNode {
  final String targetName;
  final double raHours;
  final double decDegrees;
  final double? rotation;
  final int priority;
  final double? minAltitude;
  final double? maxAltitude;
  final DateTime? startAfter;
  final DateTime? endBefore;
  final MosaicPanelInfo? mosaicPanel;

  TargetHeaderNode({
    super.id,
    super.name = 'Target',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    required this.targetName,
    required this.raHours,
    required this.decDegrees,
    this.rotation,
    this.priority = 0,
    this.minAltitude,
    this.maxAltitude,
    this.startAfter,
    this.endBefore,
    this.mosaicPanel,
  });

  @override
  String get nodeType => 'TargetHeader';

  @override
  String get iconName => 'target';

  @override
  NodeCategory get category => NodeCategory.target;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  /// Get display name including mosaic panel info if applicable
  String get displayName {
    if (mosaicPanel != null) {
      return '$targetName (${mosaicPanel!.displayLabel})';
    }
    return targetName;
  }

  /// Check if this target has time constraints
  bool get hasTimeConstraints => startAfter != null || endBefore != null;

  /// Check if this target has altitude constraints
  bool get hasAltitudeConstraints => minAltitude != null || maxAltitude != null;

  @override
  TargetHeaderNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? targetName,
    double? raHours,
    double? decDegrees,
    double? rotation,
    int? priority,
    double? minAltitude,
    double? maxAltitude,
    DateTime? startAfter,
    DateTime? endBefore,
    MosaicPanelInfo? mosaicPanel,
  }) {
    return TargetHeaderNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      targetName: targetName ?? this.targetName,
      raHours: raHours ?? this.raHours,
      decDegrees: decDegrees ?? this.decDegrees,
      rotation: rotation ?? this.rotation,
      priority: priority ?? this.priority,
      minAltitude: minAltitude ?? this.minAltitude,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      startAfter: startAfter ?? this.startAfter,
      endBefore: endBefore ?? this.endBefore,
      mosaicPanel: mosaicPanel ?? this.mosaicPanel,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        targetName,
        raHours,
        decDegrees,
        rotation,
        priority,
        minAltitude,
        maxAltitude,
        startAfter,
        endBefore,
        mosaicPanel,
      ];
}

/// Loop node - repeats children based on condition
class LoopNode extends SequenceNode {
  final LoopConditionType conditionType;
  final int? repeatCount;
  final DateTime? repeatUntil;
  final double? repeatUntilAltitude;

  /// Target total integration time in seconds for [LoopConditionType.integrationTime]
  final double? integrationTimeTarget;

  /// Safety limit for unbounded loops (Forever, WhileDark, etc.).
  /// Caps the maximum number of iterations to prevent runaway loops.
  /// null means no safety limit is set (a validation warning will be shown).
  final int? maxSafetyIterations;

  /// Whether this loop's condition type is unbounded (has no natural termination count).
  bool get isUnbounded =>
      conditionType == LoopConditionType.forever ||
      conditionType == LoopConditionType.whileDark;

  LoopNode({
    super.id,
    super.name = 'Loop',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    this.conditionType = LoopConditionType.count,
    this.repeatCount = 1,
    this.repeatUntil,
    this.repeatUntilAltitude,
    this.integrationTimeTarget,
    this.maxSafetyIterations,
  });

  @override
  String get nodeType => 'Loop';

  @override
  String get iconName => 'repeat';

  @override
  NodeCategory get category => NodeCategory.logic;

  @override
  LoopNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    LoopConditionType? conditionType,
    int? repeatCount,
    DateTime? repeatUntil,
    double? repeatUntilAltitude,
    double? integrationTimeTarget,
    int? maxSafetyIterations,
  }) {
    return LoopNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      conditionType: conditionType ?? this.conditionType,
      repeatCount: repeatCount ?? this.repeatCount,
      repeatUntil: repeatUntil ?? this.repeatUntil,
      repeatUntilAltitude: repeatUntilAltitude ?? this.repeatUntilAltitude,
      integrationTimeTarget:
          integrationTimeTarget ?? this.integrationTimeTarget,
      maxSafetyIterations: maxSafetyIterations ?? this.maxSafetyIterations,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        conditionType,
        repeatCount,
        repeatUntil,
        repeatUntilAltitude,
        integrationTimeTarget,
        maxSafetyIterations,
      ];
}

/// Parallel node - executes children in parallel
class ParallelNode extends SequenceNode {
  final int? requiredSuccesses;

  ParallelNode({
    super.id,
    super.name = 'Parallel',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    this.requiredSuccesses,
  });

  @override
  String get nodeType => 'Parallel';

  @override
  String get iconName => 'git-branch';

  @override
  NodeCategory get category => NodeCategory.logic;

  @override
  ParallelNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    int? requiredSuccesses,
  }) {
    return ParallelNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      requiredSuccesses: requiredSuccesses ?? this.requiredSuccesses,
    );
  }

  @override
  List<Object?> get props => [...super.props, requiredSuccesses];
}

/// Conditional node - executes children only if condition is met
class ConditionalNode extends SequenceNode {
  final ConditionalType conditionType;
  final double? thresholdValue;
  final DateTime? thresholdTime;

  ConditionalNode({
    super.id,
    super.name = 'Conditional',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    this.conditionType = ConditionalType.always,
    this.thresholdValue,
    this.thresholdTime,
  });

  @override
  String get nodeType => 'Conditional';

  @override
  String get iconName => 'git-merge';

  @override
  NodeCategory get category => NodeCategory.logic;

  @override
  ConditionalNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    ConditionalType? conditionType,
    double? thresholdValue,
    DateTime? thresholdTime,
  }) {
    return ConditionalNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      conditionType: conditionType ?? this.conditionType,
      thresholdValue: thresholdValue ?? this.thresholdValue,
      thresholdTime: thresholdTime ?? this.thresholdTime,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        conditionType,
        thresholdValue,
        thresholdTime,
      ];
}

/// Recovery node - handles errors with retry/recovery logic
class RecoveryNode extends SequenceNode {
  final RecoveryActionType recoveryAction;
  final int maxRetries;
  final TriggerType? triggerType;

  /// Generic threshold value whose meaning depends on [triggerType]:
  /// - For [TriggerType.hfrDegraded]: absolute HFR threshold in arcsec/px
  ///   (0 = disabled, use only relative mode)
  /// - For [TriggerType.altitudeLimit]: minimum altitude in degrees
  final double? triggerThreshold;

  /// HFR-specific: percentage above baseline HFR that triggers recovery.
  /// E.g. 20.0 means trigger when HFR is 20% above the post-autofocus baseline.
  /// Only used when [triggerType] is [TriggerType.hfrDegraded].
  /// Set to 0 to disable relative mode and use only absolute threshold.
  final double hfrThresholdPercent;

  /// HFR-specific: number of consecutive frames that must exceed the threshold
  /// before the trigger fires. Prevents false positives from momentary seeing
  /// spikes. Only used when [triggerType] is [TriggerType.hfrDegraded].
  final int hfrConsecutiveFrames;

  RecoveryNode({
    super.id,
    super.name = 'Recovery',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    this.recoveryAction = RecoveryActionType.retry,
    this.maxRetries = 3,
    this.triggerType,
    this.triggerThreshold,
    this.hfrThresholdPercent = 20.0,
    this.hfrConsecutiveFrames = 3,
  });

  @override
  String get nodeType => 'Recovery';

  @override
  String get iconName => 'shield-check';

  @override
  NodeCategory get category => NodeCategory.logic;

  @override
  RecoveryNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    RecoveryActionType? recoveryAction,
    int? maxRetries,
    TriggerType? triggerType,
    double? triggerThreshold,
    double? hfrThresholdPercent,
    int? hfrConsecutiveFrames,
  }) {
    return RecoveryNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      recoveryAction: recoveryAction ?? this.recoveryAction,
      maxRetries: maxRetries ?? this.maxRetries,
      triggerType: triggerType ?? this.triggerType,
      triggerThreshold: triggerThreshold ?? this.triggerThreshold,
      hfrThresholdPercent: hfrThresholdPercent ?? this.hfrThresholdPercent,
      hfrConsecutiveFrames: hfrConsecutiveFrames ?? this.hfrConsecutiveFrames,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        recoveryAction,
        maxRetries,
        triggerType,
        triggerThreshold,
        hfrThresholdPercent,
        hfrConsecutiveFrames,
      ];
}

/// Instruction Set node - executes children sequentially once
class InstructionSetNode extends SequenceNode {
  InstructionSetNode({
    super.id,
    super.name = 'Instructions',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
  });

  @override
  String get nodeType => 'InstructionSet';

  @override
  String get iconName => 'list';

  @override
  NodeCategory get category => NodeCategory.logic;

  @override
  InstructionSetNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  }) {
    return InstructionSetNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
    );
  }
}

// =============================================================================
// INSTRUCTION NODES
// =============================================================================

/// Slew to target instruction
class SlewNode extends SequenceNode {
  final bool useTargetCoords;
  final double? customRa;
  final double? customDec;

  SlewNode({
    super.id,
    super.name = 'Slew to Target',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.useTargetCoords = true,
    this.customRa,
    this.customDec,
  });

  @override
  String get nodeType => 'SlewToTarget';

  @override
  String get iconName => 'compass';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  @override
  SlewNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    bool? useTargetCoords,
    double? customRa,
    double? customDec,
  }) {
    return SlewNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      useTargetCoords: useTargetCoords ?? this.useTargetCoords,
      customRa: customRa ?? this.customRa,
      customDec: customDec ?? this.customDec,
    );
  }

  @override
  List<Object?> get props =>
      [...super.props, useTargetCoords, customRa, customDec];
}

/// Center target (plate solve + sync + slew)
class CenterNode extends SequenceNode {
  final double accuracyArcsec;
  final int maxAttempts;
  final bool useTargetCoords;
  final double? customRa;
  final double? customDec;

  /// Exposure duration for plate solve captures (seconds)
  final double exposureDuration;

  /// Filter to use for plate solve captures (null = current filter)
  final String? filter;

  CenterNode({
    super.id,
    super.name = 'Center Target',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.accuracyArcsec = 5.0,
    this.maxAttempts = 5,
    this.useTargetCoords = true,
    this.customRa,
    this.customDec,
    this.exposureDuration = 5.0,
    this.filter,
  });

  @override
  String get nodeType => 'CenterTarget';

  @override
  String get iconName => 'crosshair';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount, DeviceType.camera};

  @override
  CenterNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? accuracyArcsec,
    int? maxAttempts,
    bool? useTargetCoords,
    double? customRa,
    double? customDec,
    double? exposureDuration,
    String? filter,
  }) {
    return CenterNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      accuracyArcsec: accuracyArcsec ?? this.accuracyArcsec,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      useTargetCoords: useTargetCoords ?? this.useTargetCoords,
      customRa: customRa ?? this.customRa,
      customDec: customDec ?? this.customDec,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        accuracyArcsec,
        maxAttempts,
        useTargetCoords,
        customRa,
        customDec,
        exposureDuration,
        filter,
      ];
}

/// Take exposure instruction
class ExposureNode extends SequenceNode {
  final double durationSecs;
  final int count;
  final FrameType frameType;
  final String? filter;

  /// Filter position (0-based index). When set, used instead of filter name for reliability.
  final int? filterIndex;
  final int? gain;
  final int? offset;
  final BinningMode binning;
  final int? ditherEvery;
  final List<Map<String, dynamic>> triggers;

  ExposureNode({
    super.id,
    super.name = 'Take Exposures',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.durationSecs = 60.0,
    this.count = 10,
    this.frameType = FrameType.light,
    this.filter,
    this.filterIndex,
    this.gain,
    this.offset,
    this.binning = BinningMode.one,
    this.ditherEvery = 1,
    this.triggers = const [],
  });

  /// Get estimated total duration
  double get totalDurationSecs => durationSecs * count;

  @override
  String get nodeType => 'TakeExposure';

  @override
  String get iconName => 'camera';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.camera};

  @override
  ExposureNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? durationSecs,
    int? count,
    FrameType? frameType,
    String? filter,
    int? filterIndex,
    int? gain,
    int? offset,
    BinningMode? binning,
    int? ditherEvery,
    List<Map<String, dynamic>>? triggers,
  }) {
    return ExposureNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      durationSecs: durationSecs ?? this.durationSecs,
      count: count ?? this.count,
      frameType: frameType ?? this.frameType,
      filter: filter ?? this.filter,
      filterIndex: filterIndex ?? this.filterIndex,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      binning: binning ?? this.binning,
      ditherEvery: ditherEvery ?? this.ditherEvery,
      triggers: triggers ?? this.triggers,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        durationSecs,
        count,
        frameType,
        filter,
        filterIndex,
        gain,
        offset,
        binning,
        ditherEvery,
        triggers,
      ];
}

/// Autofocus instruction
///
/// When [useSettingsDefaults] is true, the node's own values are ignored at
/// execution time and the persisted AppSettings AF parameters are used instead.
/// This lets users configure AF in one place and have all sequencer AF nodes
/// follow those settings automatically.
class AutofocusNode extends SequenceNode {
  final AutofocusMethod method;
  final int stepSize;
  final int stepsOut;
  final int exposuresPerPoint;
  final double exposureDuration;

  /// When true, ignore node-level values and use AppSettings defaults at runtime.
  final bool useSettingsDefaults;

  /// Maximum time in seconds the autofocus run is allowed to take before it
  /// is aborted and treated as a failure. Default 600s (10 minutes).
  final double maxDurationSecs;

  AutofocusNode({
    super.id,
    super.name = 'Autofocus',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.method = AutofocusMethod.vCurve,
    this.stepSize = 100,
    this.stepsOut = 7,
    this.exposuresPerPoint = 1,
    this.exposureDuration = 3.0,
    this.useSettingsDefaults = true,
    this.maxDurationSecs = 600.0,
  });

  @override
  String get nodeType => 'Autofocus';

  @override
  String get iconName => 'focus';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices =>
      {DeviceType.camera, DeviceType.focuser};

  @override
  AutofocusNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    AutofocusMethod? method,
    int? stepSize,
    int? stepsOut,
    int? exposuresPerPoint,
    double? exposureDuration,
    bool? useSettingsDefaults,
    double? maxDurationSecs,
  }) {
    return AutofocusNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      method: method ?? this.method,
      stepSize: stepSize ?? this.stepSize,
      stepsOut: stepsOut ?? this.stepsOut,
      exposuresPerPoint: exposuresPerPoint ?? this.exposuresPerPoint,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      useSettingsDefaults: useSettingsDefaults ?? this.useSettingsDefaults,
      maxDurationSecs: maxDurationSecs ?? this.maxDurationSecs,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        method,
        stepSize,
        stepsOut,
        exposuresPerPoint,
        exposureDuration,
        useSettingsDefaults,
        maxDurationSecs,
      ];
}

/// Dither instruction
class DitherNode extends SequenceNode {
  final double pixels;
  final double settleTime;
  final double settlePixels;

  /// Maximum time to wait for settling after dither (seconds)
  final double settleTimeout;

  /// If true, only dither in RA (useful for dec backlash-prone setups)
  final bool raOnly;

  DitherNode({
    super.id,
    super.name = 'Dither',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.pixels = 5.0,
    this.settleTime = 30.0,
    this.settlePixels = 1.5,
    this.settleTimeout = 120.0,
    this.raOnly = false,
  });

  @override
  String get nodeType => 'Dither';

  @override
  String get iconName => 'shuffle';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.guider};

  @override
  DitherNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? pixels,
    double? settleTime,
    double? settlePixels,
    double? settleTimeout,
    bool? raOnly,
  }) {
    return DitherNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      pixels: pixels ?? this.pixels,
      settleTime: settleTime ?? this.settleTime,
      settlePixels: settlePixels ?? this.settlePixels,
      settleTimeout: settleTimeout ?? this.settleTimeout,
      raOnly: raOnly ?? this.raOnly,
    );
  }

  @override
  List<Object?> get props =>
      [...super.props, pixels, settleTime, settlePixels, settleTimeout, raOnly];
}

/// Start guiding instruction - connects to PHD2 and starts guiding
class StartGuidingNode extends SequenceNode {
  final double settlePixels;
  final double settleTime;
  final double settleTimeout;
  final bool autoSelectStar;

  StartGuidingNode({
    super.id,
    super.name = 'Start Guiding',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.settlePixels = 1.5,
    this.settleTime = 10.0,
    this.settleTimeout = 60.0,
    this.autoSelectStar = true,
  });

  @override
  String get nodeType => 'StartGuiding';

  @override
  String get iconName => 'crosshair';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.guider};

  @override
  StartGuidingNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? settlePixels,
    double? settleTime,
    double? settleTimeout,
    bool? autoSelectStar,
  }) {
    return StartGuidingNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      settlePixels: settlePixels ?? this.settlePixels,
      settleTime: settleTime ?? this.settleTime,
      settleTimeout: settleTimeout ?? this.settleTimeout,
      autoSelectStar: autoSelectStar ?? this.autoSelectStar,
    );
  }

  @override
  List<Object?> get props =>
      [...super.props, settlePixels, settleTime, settleTimeout, autoSelectStar];
}

/// Stop guiding instruction - stops PHD2 guiding
class StopGuidingNode extends SequenceNode {
  StopGuidingNode({
    super.id,
    super.name = 'Stop Guiding',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
  });

  @override
  String get nodeType => 'StopGuiding';

  @override
  String get iconName => 'x-circle';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.guider};

  @override
  StopGuidingNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  }) {
    return StopGuidingNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
    );
  }

  @override
  List<Object?> get props => super.props;
}

/// Change filter instruction
class FilterChangeNode extends SequenceNode {
  final String filterName;
  final int? filterPosition;

  FilterChangeNode({
    super.id,
    super.name = 'Change Filter',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    required this.filterName,
    this.filterPosition,
  });

  @override
  String get nodeType => 'ChangeFilter';

  @override
  String get iconName => 'circle';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.filterWheel};

  @override
  FilterChangeNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? filterName,
    int? filterPosition,
  }) {
    return FilterChangeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      filterName: filterName ?? this.filterName,
      filterPosition: filterPosition ?? this.filterPosition,
    );
  }

  @override
  List<Object?> get props => [...super.props, filterName, filterPosition];
}

/// Cool camera instruction
class CoolCameraNode extends SequenceNode {
  final double targetTemp;
  final double? durationMins;

  CoolCameraNode({
    super.id,
    super.name = 'Cool Camera',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.targetTemp = -10.0,
    this.durationMins = 10.0,
  });

  @override
  String get nodeType => 'CoolCamera';

  @override
  String get iconName => 'snowflake';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.camera};

  @override
  CoolCameraNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? targetTemp,
    double? durationMins,
  }) {
    return CoolCameraNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      targetTemp: targetTemp ?? this.targetTemp,
      durationMins: durationMins ?? this.durationMins,
    );
  }

  @override
  List<Object?> get props => [...super.props, targetTemp, durationMins];
}

/// Warm camera instruction
class WarmCameraNode extends SequenceNode {
  final double ratePerMin;
  final double targetTemp;

  WarmCameraNode({
    super.id,
    super.name = 'Warm Camera',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.ratePerMin = 2.0,
    this.targetTemp = 20.0,
  });

  @override
  String get nodeType => 'WarmCamera';

  @override
  String get iconName => 'flame';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.camera};

  @override
  WarmCameraNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? ratePerMin,
    double? targetTemp,
  }) {
    return WarmCameraNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      ratePerMin: ratePerMin ?? this.ratePerMin,
      targetTemp: targetTemp ?? this.targetTemp,
    );
  }

  @override
  List<Object?> get props => [...super.props, ratePerMin, targetTemp];
}

/// Move rotator instruction
class RotatorNode extends SequenceNode {
  final double targetAngle;
  final bool relative;

  RotatorNode({
    super.id,
    super.name = 'Move Rotator',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.targetAngle = 0.0,
    this.relative = false,
  });

  @override
  String get nodeType => 'MoveRotator';

  @override
  String get iconName => 'rotate-cw';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.rotator};

  @override
  RotatorNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? targetAngle,
    bool? relative,
  }) {
    return RotatorNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      targetAngle: targetAngle ?? this.targetAngle,
      relative: relative ?? this.relative,
    );
  }

  @override
  List<Object?> get props => [...super.props, targetAngle, relative];
}

/// Park mount instruction
class ParkNode extends SequenceNode {
  ParkNode({
    super.id,
    super.name = 'Park Mount',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
  });

  @override
  String get nodeType => 'Park';

  @override
  String get iconName => 'parking-circle';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  @override
  ParkNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  }) {
    return ParkNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
    );
  }
}

/// Unpark mount instruction
class UnparkNode extends SequenceNode {
  UnparkNode({
    super.id,
    super.name = 'Unpark Mount',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
  });

  @override
  String get nodeType => 'Unpark';

  @override
  String get iconName => 'unlock';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  @override
  UnparkNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  }) {
    return UnparkNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
    );
  }
}

/// Wait for time instruction
class WaitTimeNode extends SequenceNode {
  final DateTime? waitUntil;
  final TwilightType? waitForTwilight;

  WaitTimeNode({
    super.id,
    super.name = 'Wait for Time',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.waitUntil,
    this.waitForTwilight,
  });

  @override
  String get nodeType => 'WaitForTime';

  @override
  String get iconName => 'clock';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  WaitTimeNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    DateTime? waitUntil,
    TwilightType? waitForTwilight,
  }) {
    return WaitTimeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      waitUntil: waitUntil ?? this.waitUntil,
      waitForTwilight: waitForTwilight ?? this.waitForTwilight,
    );
  }

  @override
  List<Object?> get props => [...super.props, waitUntil, waitForTwilight];
}

/// Delay instruction
class DelayNode extends SequenceNode {
  final double seconds;

  DelayNode({
    super.id,
    super.name = 'Delay',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.seconds = 5.0,
  });

  @override
  String get nodeType => 'Delay';

  @override
  String get iconName => 'timer';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  DelayNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? seconds,
  }) {
    return DelayNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      seconds: seconds ?? this.seconds,
    );
  }

  @override
  List<Object?> get props => [...super.props, seconds];
}

/// Notification instruction
class NotificationNode extends SequenceNode {
  final String title;
  final String message;
  final NotificationLevel level;

  NotificationNode({
    super.id,
    super.name = 'Send Notification',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.title = '',
    this.message = '',
    this.level = NotificationLevel.info,
  });

  @override
  String get nodeType => 'Notification';

  @override
  String get iconName => 'bell';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  NotificationNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? title,
    String? message,
    NotificationLevel? level,
  }) {
    return NotificationNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      title: title ?? this.title,
      message: message ?? this.message,
      level: level ?? this.level,
    );
  }

  @override
  List<Object?> get props => [...super.props, title, message, level];
}

/// Script instruction
class ScriptNode extends SequenceNode {
  final String scriptPath;
  final List<String> arguments;
  final int? timeoutSecs;

  ScriptNode({
    super.id,
    super.name = 'Run Script',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.scriptPath = '',
    this.arguments = const [],
    this.timeoutSecs,
  });

  @override
  String get nodeType => 'RunScript';

  @override
  String get iconName => 'code';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  ScriptNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? scriptPath,
    List<String>? arguments,
    int? timeoutSecs,
  }) {
    return ScriptNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      scriptPath: scriptPath ?? this.scriptPath,
      arguments: arguments ?? this.arguments,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
    );
  }

  @override
  List<Object?> get props =>
      [...super.props, scriptPath, arguments, timeoutSecs];
}

/// Meridian Flip instruction
class MeridianFlipNode extends SequenceNode {
  // Trigger conditions
  final MeridianTriggerMethod triggerMethod;
  final double minutesPastMeridian;
  final double minutesBeforeLimit;
  final double hourAngleThreshold;

  // Flip sequence options
  final bool pauseGuiding;
  final bool autoCenter;
  final bool refocusAfter;
  final double settleTime;
  final bool resumeGuiding;

  // Error handling
  final int maxRetries;
  final FlipFailureAction failureAction;

  /// Whether this node should pull its effective configuration from the global
  /// `globalMeridianFlipSettingsProvider` at execution time.
  ///
  /// Why: the Sequencer Settings panel exposes a 16-row "Meridian Flip"
  /// section that operators reasonably expect to govern flip behavior. Fresh
  /// nodes (from the palette / quick-start wizard / canonical importers) carry
  /// `useGlobalDefaults: true` so any subsequent change in Sequencer Settings
  /// takes effect without per-node editing. The node's own fields still exist
  /// to allow explicit per-node overrides; touching any of them via
  /// [copyWith] flips this flag to `false`, capturing the intent as a sticky
  /// override.
  final bool useGlobalDefaults;

  MeridianFlipNode({
    super.id,
    super.name = 'Meridian Flip',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.triggerMethod = MeridianTriggerMethod.minutesPastMeridian,
    this.minutesPastMeridian = 5.0,
    this.minutesBeforeLimit = 10.0,
    this.hourAngleThreshold = 0.5,
    this.pauseGuiding = true,
    this.autoCenter = true,
    this.refocusAfter = false,
    this.settleTime = 10.0,
    this.resumeGuiding = true,
    this.maxRetries = 3,
    this.failureAction = FlipFailureAction.pauseAndAlert,
    this.useGlobalDefaults = true,
  });

  @override
  String get nodeType => 'MeridianFlip';

  @override
  String get iconName => 'refresh-cw';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  @override
  MeridianFlipNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    MeridianTriggerMethod? triggerMethod,
    double? minutesPastMeridian,
    double? minutesBeforeLimit,
    double? hourAngleThreshold,
    bool? pauseGuiding,
    bool? autoCenter,
    bool? refocusAfter,
    double? settleTime,
    bool? resumeGuiding,
    int? maxRetries,
    FlipFailureAction? failureAction,
    bool? useGlobalDefaults,
  }) {
    // Why: touching any meridian-specific field is a deliberate per-node
    // override. Implicitly clear the global-defaults flag so the executor
    // honors the new value instead of overwriting it from settings on the
    // next run. Pure structural copies (id/name/parent/etc.) leave the flag
    // alone. An explicit `useGlobalDefaults:` arg always wins (used by the
    // properties panel's "Use global defaults" toggle and by JSON load paths
    // that must preserve the persisted flag verbatim).
    final touchedConfig = triggerMethod != null ||
        minutesPastMeridian != null ||
        minutesBeforeLimit != null ||
        hourAngleThreshold != null ||
        pauseGuiding != null ||
        autoCenter != null ||
        refocusAfter != null ||
        settleTime != null ||
        resumeGuiding != null ||
        maxRetries != null ||
        failureAction != null;
    final resolvedUseGlobalDefaults = useGlobalDefaults ??
        (touchedConfig ? false : this.useGlobalDefaults);

    return MeridianFlipNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      triggerMethod: triggerMethod ?? this.triggerMethod,
      minutesPastMeridian: minutesPastMeridian ?? this.minutesPastMeridian,
      minutesBeforeLimit: minutesBeforeLimit ?? this.minutesBeforeLimit,
      hourAngleThreshold: hourAngleThreshold ?? this.hourAngleThreshold,
      pauseGuiding: pauseGuiding ?? this.pauseGuiding,
      autoCenter: autoCenter ?? this.autoCenter,
      refocusAfter: refocusAfter ?? this.refocusAfter,
      settleTime: settleTime ?? this.settleTime,
      resumeGuiding: resumeGuiding ?? this.resumeGuiding,
      maxRetries: maxRetries ?? this.maxRetries,
      failureAction: failureAction ?? this.failureAction,
      useGlobalDefaults: resolvedUseGlobalDefaults,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        triggerMethod,
        minutesPastMeridian,
        minutesBeforeLimit,
        hourAngleThreshold,
        pauseGuiding,
        autoCenter,
        refocusAfter,
        settleTime,
        resumeGuiding,
        maxRetries,
        failureAction,
        useGlobalDefaults,
      ];
}

/// Open Dome instruction
class OpenDomeNode extends SequenceNode {
  final bool shutterOnly;

  OpenDomeNode({
    super.id,
    super.name = 'Open Dome',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.shutterOnly = false,
  });

  @override
  String get nodeType => 'OpenDome';

  @override
  String get iconName => 'home';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.dome};

  @override
  OpenDomeNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    bool? shutterOnly,
  }) {
    return OpenDomeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      shutterOnly: shutterOnly ?? this.shutterOnly,
    );
  }

  @override
  List<Object?> get props => [...super.props, shutterOnly];
}

/// Close Dome instruction
class CloseDomeNode extends SequenceNode {
  final bool shutterOnly;

  CloseDomeNode({
    super.id,
    super.name = 'Close Dome',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.shutterOnly = false,
  });

  @override
  String get nodeType => 'CloseDome';

  @override
  String get iconName => 'home';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.dome};

  @override
  CloseDomeNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    bool? shutterOnly,
  }) {
    return CloseDomeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      shutterOnly: shutterOnly ?? this.shutterOnly,
    );
  }

  @override
  List<Object?> get props => [...super.props, shutterOnly];
}

/// Park Dome instruction
class ParkDomeNode extends SequenceNode {
  final bool shutterOnly;

  ParkDomeNode({
    super.id,
    super.name = 'Park Dome',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.shutterOnly = false,
  });

  @override
  String get nodeType => 'ParkDome';

  @override
  String get iconName => 'parking-circle';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.dome};

  @override
  ParkDomeNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    bool? shutterOnly,
  }) {
    return ParkDomeNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      shutterOnly: shutterOnly ?? this.shutterOnly,
    );
  }

  @override
  List<Object?> get props => [...super.props, shutterOnly];
}

/// Polar alignment instruction
class PolarAlignmentNode extends SequenceNode {
  final double exposureDuration;
  final int binning;
  final double startAltitude;
  final double rotationStep;
  final int? gain;
  final int? offset;
  final bool startFromCurrent;
  final bool isNorth;
  final bool manualSlew;

  PolarAlignmentNode({
    super.id,
    super.name = 'Polar Alignment',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.exposureDuration = 2.0,
    this.binning = 2,
    this.startAltitude = 45.0,
    this.rotationStep = 20.0,
    this.gain,
    this.offset,
    this.startFromCurrent = true,
    this.isNorth = true,
    this.manualSlew = false,
  });

  @override
  String get nodeType => 'PolarAlignment';

  @override
  String get iconName => 'compass';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.camera, DeviceType.mount};

  @override
  PolarAlignmentNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? exposureDuration,
    int? binning,
    double? startAltitude,
    double? rotationStep,
    int? gain,
    int? offset,
    bool? startFromCurrent,
    bool? isNorth,
    bool? manualSlew,
  }) {
    return PolarAlignmentNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      binning: binning ?? this.binning,
      startAltitude: startAltitude ?? this.startAltitude,
      rotationStep: rotationStep ?? this.rotationStep,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      startFromCurrent: startFromCurrent ?? this.startFromCurrent,
      isNorth: isNorth ?? this.isNorth,
      manualSlew: manualSlew ?? this.manualSlew,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        exposureDuration,
        binning,
        startAltitude,
        rotationStep,
        gain,
        offset,
        startFromCurrent,
        isNorth,
        manualSlew,
      ];
}

// =============================================================================
// COVER CALIBRATOR / FLAT PANEL NODES
// =============================================================================

/// Open cover instruction - opens a motorized dust cover / flat panel cover
class OpenCoverNode extends SequenceNode {
  final int timeoutSecs;

  OpenCoverNode({
    super.id,
    super.name = 'Open Cover',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.timeoutSecs = 60,
  });

  @override
  String get nodeType => 'OpenCover';

  @override
  String get iconName => 'door-open';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.coverCalibrator};

  @override
  OpenCoverNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    int? timeoutSecs,
  }) {
    return OpenCoverNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
    );
  }

  @override
  List<Object?> get props => [...super.props, timeoutSecs];
}

/// Close cover instruction - closes a motorized dust cover / flat panel cover
class CloseCoverNode extends SequenceNode {
  final int timeoutSecs;

  CloseCoverNode({
    super.id,
    super.name = 'Close Cover',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.timeoutSecs = 60,
  });

  @override
  String get nodeType => 'CloseCover';

  @override
  String get iconName => 'door-closed';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.coverCalibrator};

  @override
  CloseCoverNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    int? timeoutSecs,
  }) {
    return CloseCoverNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
    );
  }

  @override
  List<Object?> get props => [...super.props, timeoutSecs];
}

/// Calibrator on instruction - turns on flat panel at specified brightness
class CalibratorOnNode extends SequenceNode {
  final int brightness;
  final int timeoutSecs;

  CalibratorOnNode({
    super.id,
    super.name = 'Calibrator On',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.brightness = 128,
    this.timeoutSecs = 30,
  });

  @override
  String get nodeType => 'CalibratorOn';

  @override
  String get iconName => 'lightbulb';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.coverCalibrator};

  @override
  CalibratorOnNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    int? brightness,
    int? timeoutSecs,
  }) {
    return CalibratorOnNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      brightness: brightness ?? this.brightness,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
    );
  }

  @override
  List<Object?> get props => [...super.props, brightness, timeoutSecs];
}

/// Calibrator off instruction - turns off flat panel light
class CalibratorOffNode extends SequenceNode {
  final int timeoutSecs;

  CalibratorOffNode({
    super.id,
    super.name = 'Calibrator Off',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.timeoutSecs = 30,
  });

  @override
  String get nodeType => 'CalibratorOff';

  @override
  String get iconName => 'lightbulb-off';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => {DeviceType.coverCalibrator};

  @override
  CalibratorOffNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    int? timeoutSecs,
  }) {
    return CalibratorOffNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
    );
  }

  @override
  List<Object?> get props => [...super.props, timeoutSecs];
}

// =============================================================================
// SEQUENCE
// =============================================================================

/// Complete sequence
class Sequence extends Equatable {
  final String id;
  final int? databaseId; // Database primary key (null if not persisted)
  final String name;
  final String description;
  final Map<String, SequenceNode> nodes;
  final String? rootNodeId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isTemplate;
  final int? estimatedDurationMins;

  Sequence({
    String? id,
    this.databaseId,
    required this.name,
    this.description = '',
    Map<String, SequenceNode>? nodes,
    this.rootNodeId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.isTemplate = false,
    this.estimatedDurationMins,
  })  : id = id ?? const Uuid().v4(),
        nodes = nodes ?? {},
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  /// Get total exposure count
  int get totalExposures {
    int count = 0;
    for (final node in nodes.values) {
      if (node is ExposureNode && node.isEnabled) {
        count += node.count;
      }
    }
    return count;
  }

  /// Get total integration time in seconds
  /// This walks the tree structure and accounts for loop iterations
  double get totalIntegrationSecs {
    return estimateIntegrationSecs().estimatedSecs;
  }

  /// Estimate integration time with overhead awareness.
  /// Walks the sequence tree counting occurrences of each operation type
  /// and applies configurable per-operation overhead estimates.
  SequenceEstimate estimateWithOverhead({
    SequenceOverheadConfig config = const SequenceOverheadConfig(),
    DateTime? referenceTime,
  }) {
    final base = estimateIntegrationSecs(referenceTime: referenceTime);

    // Walk tree counting overhead-generating operations
    double overheadSecs = 0;

    if (rootNodeId != null && nodes[rootNodeId] != null) {
      overheadSecs = _calculateOverhead(rootNodeId!, config, 1);
    } else {
      // No tree structure - just count nodes directly
      for (final node in nodes.values) {
        if (!node.isEnabled) continue;
        overheadSecs += _nodeOverhead(node, config);
      }
    }

    return SequenceEstimate(
      estimatedSecs: base.estimatedSecs,
      overheadSecs: overheadSecs,
      singleIterationSecs: base.singleIterationSecs,
      isUnbounded: base.isUnbounded,
      untilTime: base.untilTime,
      conditionType: base.conditionType,
    );
  }

  /// Calculate overhead for a node and its subtree, respecting loop multipliers
  double _calculateOverhead(
      String nodeId, SequenceOverheadConfig config, int multiplier) {
    final node = nodes[nodeId];
    if (node == null || !node.isEnabled) return 0;

    // Leaf node overhead
    final selfOverhead = _nodeOverhead(node, config) * multiplier;

    // Children overhead
    double childrenOverhead = 0;
    int childMultiplier = multiplier;
    if (node is LoopNode) {
      if (node.conditionType == LoopConditionType.count) {
        childMultiplier = multiplier * (node.repeatCount ?? 1);
      }
      // For unbounded loops, keep multiplier at 1 for overhead
    }

    for (final childId in node.childIds) {
      childrenOverhead += _calculateOverhead(childId, config, childMultiplier);
    }

    return selfOverhead + childrenOverhead;
  }

  /// Get the overhead contribution for a single node instance
  double _nodeOverhead(SequenceNode node, SequenceOverheadConfig config) {
    if (node is SlewNode) return config.slewSecs;
    if (node is CenterNode) return config.centerTargetSecs;
    if (node is AutofocusNode) return config.autofocusSecs;
    if (node is FilterChangeNode) return config.filterChangeSecs;
    if (node is DitherNode) return config.ditherSecs;
    if (node is StartGuidingNode) return config.guideAcquireSecs;
    if (node is MeridianFlipNode) return config.meridianFlipSecs;
    if (node is CoolCameraNode) return config.coolingSecs;
    if (node is WarmCameraNode) return config.warmingSecs;
    if (node is OpenCoverNode || node is CloseCoverNode) {
      return config.coverMoveSecs;
    }
    if (node is ExposureNode) {
      // Download overhead per exposure
      return config.downloadOverheadPerExposureSecs * node.count;
    }
    return 0;
  }

  /// Estimate integration time with detailed info about bounded/unbounded status
  /// [referenceTime] is used for calculating time-based loop durations (default: now)
  SequenceEstimate estimateIntegrationSecs({DateTime? referenceTime}) {
    referenceTime ??= DateTime.now();

    // If no root node, fall back to simple sum of all exposures
    if (rootNodeId == null || nodes[rootNodeId] == null) {
      double total = 0;
      for (final node in nodes.values) {
        if (node is ExposureNode && node.isEnabled) {
          total += node.totalDurationSecs;
        }
      }
      return SequenceEstimate(
        estimatedSecs: total,
        singleIterationSecs: total,
        isUnbounded: false,
      );
    }

    // Walk the tree from root
    return _estimateNodeIntegration(rootNodeId!, referenceTime);
  }

  /// Recursively estimate integration time for a node and its children
  SequenceEstimate _estimateNodeIntegration(
      String nodeId, DateTime referenceTime) {
    final node = nodes[nodeId];
    if (node == null || !node.isEnabled) {
      return const SequenceEstimate(
        estimatedSecs: 0,
        singleIterationSecs: 0,
        isUnbounded: false,
      );
    }

    // For exposure nodes, return the direct duration
    if (node is ExposureNode) {
      final duration = node.totalDurationSecs;
      return SequenceEstimate(
        estimatedSecs: duration,
        singleIterationSecs: duration,
        isUnbounded: false,
      );
    }

    // For nodes with children, sum up children's estimates
    double childrenSecs = 0;
    double childrenSingleIteration = 0;
    bool anyChildUnbounded = false;

    for (final childId in node.childIds) {
      final childEstimate = _estimateNodeIntegration(childId, referenceTime);
      childrenSecs += childEstimate.estimatedSecs;
      childrenSingleIteration += childEstimate.singleIterationSecs;
      if (childEstimate.isUnbounded) anyChildUnbounded = true;
    }

    // For loop nodes, apply the loop multiplier
    if (node is LoopNode) {
      switch (node.conditionType) {
        case LoopConditionType.count:
          // Fixed iteration count
          final iterations = node.repeatCount ?? 1;
          return SequenceEstimate(
            estimatedSecs: childrenSecs * iterations,
            singleIterationSecs: childrenSingleIteration,
            isUnbounded: anyChildUnbounded,
          );

        case LoopConditionType.untilTime:
          // Time-based loop: estimate iterations based on available time
          if (node.repeatUntil != null && childrenSingleIteration > 0) {
            final availableSecs = node.repeatUntil!
                .difference(referenceTime)
                .inSeconds
                .toDouble();
            if (availableSecs > 0) {
              // Estimate how many iterations can fit in the time window
              final estimatedIterations =
                  (availableSecs / childrenSingleIteration).floor();
              final estimatedTotal =
                  childrenSingleIteration * estimatedIterations;
              return SequenceEstimate(
                estimatedSecs: estimatedTotal,
                singleIterationSecs: childrenSingleIteration,
                isUnbounded: false,
                untilTime: node.repeatUntil,
              );
            }
          }
          // If repeatUntil is in the past or not set, return single iteration
          return SequenceEstimate(
            estimatedSecs: childrenSingleIteration,
            singleIterationSecs: childrenSingleIteration,
            isUnbounded: false,
            untilTime: node.repeatUntil,
          );

        case LoopConditionType.forever:
        case LoopConditionType.whileDark:
        case LoopConditionType.untilAltitude:
        case LoopConditionType.altitudeAbove:
          // Unbounded loops - return single iteration time but mark as unbounded
          return SequenceEstimate(
            estimatedSecs: childrenSingleIteration,
            singleIterationSecs: childrenSingleIteration,
            isUnbounded: true,
            conditionType: node.conditionType,
          );

        case LoopConditionType.integrationTime:
          // Integration time loop: estimate iterations based on target integration time
          if (node.integrationTimeTarget != null &&
              node.integrationTimeTarget! > 0 &&
              childrenSingleIteration > 0) {
            // Find total exposure time per iteration from children
            double exposurePerIteration = 0;
            for (final childId in node.childIds) {
              final child = nodes[childId];
              if (child is ExposureNode && child.isEnabled) {
                exposurePerIteration += child.totalDurationSecs;
              }
            }
            if (exposurePerIteration > 0) {
              final estimatedIterations =
                  (node.integrationTimeTarget! / exposurePerIteration).ceil();
              return SequenceEstimate(
                estimatedSecs: childrenSingleIteration * estimatedIterations,
                singleIterationSecs: childrenSingleIteration,
                isUnbounded: false,
              );
            }
          }
          // If we can't estimate, treat as unbounded
          return SequenceEstimate(
            estimatedSecs: childrenSingleIteration,
            singleIterationSecs: childrenSingleIteration,
            isUnbounded: true,
            conditionType: node.conditionType,
          );
      }
    }

    // For other container nodes (Parallel, Conditional, etc.), just return children sum
    return SequenceEstimate(
      estimatedSecs: childrenSecs,
      singleIterationSecs: childrenSingleIteration,
      isUnbounded: anyChildUnbounded,
    );
  }

  /// Get target headers (root nodes for each target)
  List<TargetHeaderNode> get targetHeaders {
    return nodes.values
        .whereType<TargetHeaderNode>()
        .where((n) => n.isEnabled)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  /// Get node by ID
  SequenceNode? getNode(String id) => nodes[id];

  /// Get root node
  SequenceNode? get rootNode => rootNodeId != null ? nodes[rootNodeId] : null;

  /// Get children of a node
  List<SequenceNode> getChildren(String parentId) {
    final parent = nodes[parentId];
    if (parent == null) return [];
    return parent.childIds
        .map((id) => nodes[id])
        .whereType<SequenceNode>()
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Sequence copyWith({
    String? id,
    int? databaseId,
    String? name,
    String? description,
    Map<String, SequenceNode>? nodes,
    String? rootNodeId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isTemplate,
    int? estimatedDurationMins,
  }) {
    return Sequence(
      id: id ?? this.id,
      databaseId: databaseId ?? this.databaseId,
      name: name ?? this.name,
      description: description ?? this.description,
      nodes: nodes ?? this.nodes,
      rootNodeId: rootNodeId ?? this.rootNodeId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isTemplate: isTemplate ?? this.isTemplate,
      estimatedDurationMins:
          estimatedDurationMins ?? this.estimatedDurationMins,
    );
  }

  @override
  List<Object?> get props => [
        id,
        databaseId,
        name,
        description,
        nodes,
        rootNodeId,
        createdAt,
        modifiedAt,
        isTemplate,
        estimatedDurationMins,
      ];
}

/// Progress of sequence execution
class SequenceProgress extends Equatable {
  final SequenceExecutionState state;
  final String? currentNodeId;
  final String? currentNodeName;
  final NodeStatus? currentNodeStatus;
  final int totalExposures;
  final int completedExposures;
  final double totalIntegrationSecs;
  final double completedIntegrationSecs;
  final double elapsedSecs;
  final double? estimatedRemainingSecs;
  final String? currentTarget;
  final String? currentFilter;
  final String? message;
  final Map<String, NodeStatus> nodeStatuses;

  /// Per-node instruction progress (0-100 percent)
  final Map<String, double> nodeProgressPercent;

  /// Per-node instruction progress detail message
  final Map<String, String> nodeProgressDetail;

  const SequenceProgress({
    this.state = SequenceExecutionState.idle,
    this.currentNodeId,
    this.currentNodeName,
    this.currentNodeStatus,
    this.totalExposures = 0,
    this.completedExposures = 0,
    this.totalIntegrationSecs = 0,
    this.completedIntegrationSecs = 0,
    this.elapsedSecs = 0,
    this.estimatedRemainingSecs,
    this.currentTarget,
    this.currentFilter,
    this.message,
    this.nodeStatuses = const {},
    this.nodeProgressPercent = const {},
    this.nodeProgressDetail = const {},
  });

  double get progressPercent {
    if (totalExposures == 0) return 0;
    return completedExposures / totalExposures;
  }

  SequenceProgress copyWith({
    SequenceExecutionState? state,
    String? currentNodeId,
    String? currentNodeName,
    NodeStatus? currentNodeStatus,
    int? totalExposures,
    int? completedExposures,
    double? totalIntegrationSecs,
    double? completedIntegrationSecs,
    double? elapsedSecs,
    double? estimatedRemainingSecs,
    String? currentTarget,
    String? currentFilter,
    String? message,
    Map<String, NodeStatus>? nodeStatuses,
    Map<String, double>? nodeProgressPercent,
    Map<String, String>? nodeProgressDetail,
  }) {
    return SequenceProgress(
      state: state ?? this.state,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      currentNodeName: currentNodeName ?? this.currentNodeName,
      currentNodeStatus: currentNodeStatus ?? this.currentNodeStatus,
      totalExposures: totalExposures ?? this.totalExposures,
      completedExposures: completedExposures ?? this.completedExposures,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      completedIntegrationSecs:
          completedIntegrationSecs ?? this.completedIntegrationSecs,
      elapsedSecs: elapsedSecs ?? this.elapsedSecs,
      estimatedRemainingSecs:
          estimatedRemainingSecs ?? this.estimatedRemainingSecs,
      currentTarget: currentTarget ?? this.currentTarget,
      currentFilter: currentFilter ?? this.currentFilter,
      message: message ?? this.message,
      nodeStatuses: nodeStatuses ?? this.nodeStatuses,
      nodeProgressPercent: nodeProgressPercent ?? this.nodeProgressPercent,
      nodeProgressDetail: nodeProgressDetail ?? this.nodeProgressDetail,
    );
  }

  @override
  List<Object?> get props => [
        state,
        currentNodeId,
        currentNodeName,
        currentNodeStatus,
        totalExposures,
        completedExposures,
        totalIntegrationSecs,
        completedIntegrationSecs,
        elapsedSecs,
        estimatedRemainingSecs,
        currentTarget,
        currentFilter,
        message,
        nodeStatuses,
        nodeProgressPercent,
        nodeProgressDetail,
      ];
}
