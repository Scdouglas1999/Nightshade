// `@JsonSerializable(...)` and `@JsonKey(...)` are attached to the freezed
// redirecting factory constructors / their parameters below. freezed copies
// those decorators verbatim onto the generated concrete `class` (where they
// are valid) — see `freezed/lib/src/templates/concrete_template.dart`, which
// joins `constructor.decorators` directly above the emitted class. There is no
// other channel to pass per-class json_serializable options such as
// `fieldRename`, `explicitToJson`, and `includeIfNull`: the `@Freezed`
// annotation does not expose them (freezed_annotation 2.4.x), and a global
// `build.yaml` `field_rename` would also rewrite the camelCase models in this
// same file that intentionally keep their Dart key names. The analyzer reports
// these required-on-the-constructor annotations as `invalid_annotation_target`
// because json_annotation's `@Target` is `classType` / field-or-getter only;
// freezed's own generated output silences the identical false positive with
// this exact directive.
// ignore_for_file: invalid_annotation_target
import 'package:equatable/equatable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';
import '../imaging/imaging_models.dart' show FrameType;
import '../notification/notification_categories.dart'
    show NotificationTransportKind;
import '../meridian_flip_settings.dart'
    show MeridianTriggerMethod, FlipFailureAction;
export '../meridian_flip_settings.dart'
    show MeridianTriggerMethod, FlipFailureAction;
import '../../backend/nightshade_backend.dart' show DeviceType;
import '../../services/scheduler/horizon_profile.dart' show HorizonProfile;
import '_json_converters.dart';
import 'instruction_progress_detail.dart';
import 'sequence_tree_index.dart';
export 'sequence_tree_index.dart' show SequenceTreeIndex;

part 'sequence_models.freezed.dart';
part 'sequence_models.g.dart';
part 'sequence_models/advanced_nodes/cover_calibrator_nodes.dart';
part 'sequence_models/advanced_nodes/adaptive_swap_models.dart';
part 'sequence_models/advanced_nodes/target_scheduler_node.dart';
part 'sequence_models/advanced_nodes/smart_exposure_node.dart';
part 'sequence_models/advanced_nodes/live_stacking_node.dart';
part 'sequence_models/container_nodes/integration_budget_and_target_triggers.dart';
part 'sequence_models/container_nodes/target_header_node.dart';
part 'sequence_models/container_nodes/simple_logic_nodes.dart';
part 'sequence_models/container_nodes/recovery_node.dart';
part 'sequence_models/container_nodes/instruction_set_node.dart';
part 'sequence_models/instruction_nodes/capture_and_guiding.dart';
part 'sequence_models/instruction_nodes/equipment_timing_and_automation.dart';
part 'sequence_models/instruction_nodes/alignment_and_dome.dart';
part 'sequence_models/science_and_plugin_nodes.dart';
part 'sequence_models/sequence_state.dart';

/// Sequence execution state
///
/// Wave 4: `recovering` is the visible recovery-mode state. Mirrors the Rust
/// `ExecutorState::Recovering` variant — the Run Dashboard renders a
/// pulsing red LED, the persistent recovery banner with cause + attempt
/// counter + countdown, and the Try Now / Abort controls when this fires.
enum SequenceExecutionState {
  idle,
  running,
  paused,
  stopping,
  completed,
  failed,
  recovering,
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
@freezed
abstract class SequenceOverheadConfig with _$SequenceOverheadConfig {
  const factory SequenceOverheadConfig({
    /// Time for a slew operation (seconds)
    @Default(30.0) double slewSecs,

    /// Time for an autofocus run (seconds)
    @Default(180.0) double autofocusSecs,

    /// Time for a filter wheel change (seconds)
    @Default(10.0) double filterChangeSecs,

    /// Time for a dither + settle cycle (seconds)
    @Default(15.0) double ditherSecs,

    /// Time for a meridian flip including re-centering (seconds)
    @Default(300.0) double meridianFlipSecs,

    /// Time for guide acquisition and settle (seconds)
    @Default(30.0) double guideAcquireSecs,

    /// Time for a plate solve (seconds)
    @Default(15.0) double plateSolveSecs,

    /// Time for camera cool-down (seconds)
    @Default(600.0) double coolingSecs,

    /// Time for camera warm-up (seconds)
    @Default(300.0) double warmingSecs,

    /// Per-exposure download overhead (seconds)
    @Default(3.0) double downloadOverheadPerExposureSecs,

    /// Time for cover calibrator open/close (seconds)
    @Default(30.0) double coverMoveSecs,

    /// Time for center target operation (plate solve + slew iterations) (seconds)
    @Default(45.0) double centerTargetSecs,
  }) = _SequenceOverheadConfig;
}

/// Result of sequence integration time estimation
@freezed
abstract class SequenceEstimate with _$SequenceEstimate {
  const SequenceEstimate._();

  const factory SequenceEstimate({
    /// Estimated total integration time in seconds (pure shutter-open time)
    required double estimatedSecs,

    /// Estimated total overhead time in seconds (slews, AF, dithers, etc.)
    @Default(0.0) double overheadSecs,

    /// Time for a single iteration (useful for unbounded loops)
    required double singleIterationSecs,

    /// Whether the sequence contains unbounded loops (forever, whileDark, etc.)
    required bool isUnbounded,

    /// For untilTime loops, the target end time
    DateTime? untilTime,

    /// For unbounded loops, the condition type
    LoopConditionType? conditionType,
  }) = _SequenceEstimate;

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
  customBranch,
  // Wave 5 Agent 4 — cloud-motion-aware recovery actions. `pauseAndWaitForClear`
  // promotes the pause to a Wave 4 RecoveryCause::WeatherUnsafe so the
  // dashboard banner / audible alert fire; `slewToGapAndContinue` re-points
  // the mount to a clear-sky direction reported by the analyzer.
  pauseAndWaitForClear,
  slewToGapAndContinue,
  // Wave 7 Science — transparency-adaptive recovery. Paired with
  // [TriggerType.transparencyDropped]. Consults the operator's
  // pre-configured backup plan (backup filter and/or backup target id)
  // and either swaps the filter, skips to the backup target, or both.
  switchTargetOrFilter,
}

/// Trigger type.
///
/// Mirrors the Rust `TriggerType` enum in
/// `native/nightshade_native/sequencer/src/lib.rs`. Adding a new variant here
/// REQUIRES extending [`SequenceExecutor._nodeToConfig`]'s RecoveryNode
/// serializer so the trigger config round-trips to Rust correctly. The
/// `Wave 1.5 Pack A` set fills in the long-standing gap where the Rust side
/// had 17 trigger variants but Dart only modelled 8.
enum TriggerType {
  hfrDegraded,
  meridianFlip,
  guidingFailed,
  altitudeLimit,
  weatherUnsafe,
  temperatureShift,
  filterChange,
  dawnApproaching,
  // Wave 1.5 Pack A additions — config payload fields are stored in the
  // dedicated columns on [`RecoveryNode`] (triggerThreshold for single-double
  // payloads; the FocusDrift-specific window/count/increase fields are
  // dedicated). Trigger types that take no payload (mountTrackingLost,
  // domeShutterNotOpen, guideStarLost) read no config.
  humidityThreshold,
  focusDrift,
  mountTrackingLost,
  domeShutterNotOpen,
  guideStarLost,
  autofocusInterval,
  ditherInterval,
  driftLimit,
  // Wave 5 Agent 4 — cloud-motion-aware triggers backed by the live
  // CloudMotionAnalyzer. The runtime sample data is pushed from Dart via
  // `backend.sequencerUpdateCloudMotion` on a ~60s cadence; the trigger
  // config payloads are stored on [`RecoveryNode`] in the dedicated
  // cloud* fields below.
  cloudArrivingIn,
  cloudOpeningIn,
  cloudCoverThreshold,
  // Wave 7 Science — transparency-adaptive trigger backed by the live
  // sky transparency sampler. The runtime sample data is pushed from
  // the Dart science pipeline via `backend.sequencerUpdateTransparency`.
  // Paired with [RecoveryActionType.switchTargetOrFilter] for the
  // "swap from faint RGB target to a brighter Lum backup when the sky
  // goes hazy" workflow.
  transparencyDropped,
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
  List<Object?> get props => [
    id,
    name,
    isEnabled,
    childIds,
    parentId,
    orderIndex,
    comment,
  ];
}

/// Node category for coloring
enum NodeCategory { instruction, trigger, logic, target }

// =============================================================================
// MOSAIC PANEL INFO
// =============================================================================

/// Information about a mosaic panel for multi-panel imaging
@Freezed(fromJson: true, toJson: true)
abstract class MosaicPanelInfo with _$MosaicPanelInfo {
  const MosaicPanelInfo._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory MosaicPanelInfo({
    required String mosaicName,
    required int panelIndex,
    required int totalPanels,
    required int row,
    required int column,
  }) = _MosaicPanelInfo;

  String get displayLabel => 'Panel ${panelIndex + 1}/$totalPanels';

  factory MosaicPanelInfo.fromJson(Map<String, dynamic> json) =>
      _$MosaicPanelInfoFromJson(json);
}
