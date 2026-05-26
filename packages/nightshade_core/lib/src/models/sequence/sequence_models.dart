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
import '_json_converters.dart';
import 'instruction_progress_detail.dart';

part 'sequence_models.freezed.dart';
part 'sequence_models.g.dart';

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
class SequenceOverheadConfig with _$SequenceOverheadConfig {
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
class SequenceEstimate with _$SequenceEstimate {
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
  List<Object?> get props =>
      [id, name, isEnabled, childIds, parentId, orderIndex, comment];
}

/// Node category for coloring
enum NodeCategory { instruction, trigger, logic, target }

// =============================================================================
// MOSAIC PANEL INFO
// =============================================================================

/// Information about a mosaic panel for multi-panel imaging
@Freezed(fromJson: true, toJson: true)
class MosaicPanelInfo with _$MosaicPanelInfo {
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

// =============================================================================
// CONTAINER / LOGIC NODES
// =============================================================================

/// Wave 3 Agent 3 — Dart mirror of the Rust `FilterBudgetEntry`.
/// `Absolute(secs)` caps that filter at a fixed time; `Ratio(value)` is
/// normalised against the other ratios in the same target and the
/// target's `totalSecs`. JSON shape matches the Rust enum:
/// `{"kind":"Absolute","value":3600.0}` / `{"kind":"Ratio","value":4.0}`.
class FilterBudgetEntry {
  /// `'Absolute'` or `'Ratio'`.
  final String kind;
  final double value;

  const FilterBudgetEntry.absolute(this.value) : kind = 'Absolute';
  const FilterBudgetEntry.ratio(this.value) : kind = 'Ratio';

  bool get isAbsolute => kind == 'Absolute';
  bool get isRatio => kind == 'Ratio';

  Map<String, dynamic> toJson() => {'kind': kind, 'value': value};

  factory FilterBudgetEntry.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    final value = (json['value'] as num).toDouble();
    if (kind == 'Absolute') {
      return FilterBudgetEntry.absolute(value);
    } else if (kind == 'Ratio') {
      return FilterBudgetEntry.ratio(value);
    } else {
      throw FormatException(
          'Unknown FilterBudgetEntry kind "$kind"; expected Absolute or Ratio');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FilterBudgetEntry && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '$kind($value)';
}

/// Wave 3 Agent 3 — Per-target integration budget configuration.
///
/// Mirrors the Rust `IntegrationBudget` struct one-to-one for serde
/// round-tripping through the FRB bridge. See
/// `native/nightshade_native/sequencer/src/lib.rs` for the canonical
/// definition.
class IntegrationBudget {
  /// Total wall-clock integration cap across all filters (seconds).
  /// `0.0` means "no overall cap"; only `perFilter` entries apply.
  final double totalSecs;

  /// Per-filter budgets. Empty map means "only totalSecs applies".
  final Map<String, FilterBudgetEntry> perFilter;

  /// When the budget is hit, the TargetHeader returns Success and the
  /// executor advances to the next sibling. Default true.
  final bool stopOnBudgetMet;

  const IntegrationBudget({
    this.totalSecs = 0.0,
    this.perFilter = const {},
    this.stopOnBudgetMet = true,
  });

  /// True iff the budget has at least one cap that can ever fire. The
  /// UI uses this to suppress no-op budget panels.
  bool get isActive {
    if (totalSecs > 0.0) return true;
    return perFilter.values.any((e) => e.value > 0);
  }

  /// Resolved absolute cap (seconds) for a single filter, mirroring
  /// `IntegrationBudget::resolved_filter_cap` on the Rust side. Used
  /// by the properties UI's "what will this carve up to?" preview.
  double? resolvedFilterCap(String filter) {
    final entry = perFilter[filter];
    if (entry == null) return null;
    if (entry.isAbsolute) {
      return entry.value > 0 ? entry.value : null;
    }
    if (entry.isRatio) {
      if (entry.value <= 0 || totalSecs <= 0) return null;
      final sum = perFilter.values
          .where((e) => e.isRatio && e.value > 0)
          .fold<double>(0, (acc, e) => acc + e.value);
      if (sum <= 0) return null;
      return (entry.value / sum) * totalSecs;
    }
    return null;
  }

  IntegrationBudget copyWith({
    double? totalSecs,
    Map<String, FilterBudgetEntry>? perFilter,
    bool? stopOnBudgetMet,
  }) {
    return IntegrationBudget(
      totalSecs: totalSecs ?? this.totalSecs,
      perFilter: perFilter ?? this.perFilter,
      stopOnBudgetMet: stopOnBudgetMet ?? this.stopOnBudgetMet,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_secs': totalSecs,
        'per_filter': perFilter.map((k, v) => MapEntry(k, v.toJson())),
        'stop_on_budget_met': stopOnBudgetMet,
      };

  factory IntegrationBudget.fromJson(Map<String, dynamic> json) {
    return IntegrationBudget(
      totalSecs: (json['total_secs'] as num?)?.toDouble() ?? 0.0,
      perFilter: (json['per_filter'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(
              k, FilterBudgetEntry.fromJson(v as Map<String, dynamic>))),
      stopOnBudgetMet: json['stop_on_budget_met'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! IntegrationBudget) return false;
    if (other.totalSecs != totalSecs) return false;
    if (other.stopOnBudgetMet != stopOnBudgetMet) return false;
    if (other.perFilter.length != perFilter.length) return false;
    for (final entry in perFilter.entries) {
      if (other.perFilter[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        totalSecs,
        stopOnBudgetMet,
        Object.hashAllUnordered(
            perFilter.entries.map((e) => Object.hash(e.key, e.value))),
      );
}

// ============================================================================
// Wave 4 — Per-target start/end altitude crossings.
//
// `TargetTrigger` mirrors the Rust enum in
// `native/nightshade_native/sequencer/src/scheduling/target_trigger.rs`.
// Used by `TargetHeaderNode.startWhen` / `endWhen` to gate when a target
// begins / ends imaging. We use a hand-rolled sealed-class hierarchy so
// JSON encoding stays symmetric with the Rust
// `#[serde(tag = "kind", content = "value")]` shape.
// ============================================================================

/// One leaf or compound condition that can gate a target's start / end.
sealed class TargetTrigger {
  const TargetTrigger();

  /// JSON shape: `{"kind":"AltitudeAbove","value":35.0}` (and nested
  /// `value: [...]` for And/Or). Stays symmetric to the Rust
  /// `#[serde(tag = "kind", content = "value")]` encoding.
  Map<String, dynamic> toJson();

  /// Decode a `TargetTrigger` from JSON. Throws on unknown / malformed
  /// kinds — errors-are-a-feature; we never silently downgrade to a
  /// trigger that is "always false" or "always true".
  factory TargetTrigger.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    final raw = json['value'];
    switch (kind) {
      case 'AltitudeAbove':
        return AltitudeAboveTrigger((raw as num).toDouble());
      case 'AltitudeBelow':
        return AltitudeBelowTrigger((raw as num).toDouble());
      case 'TimeAfter':
        return TimeAfterTrigger((raw as num).toInt());
      case 'TimeBefore':
        return TimeBeforeTrigger((raw as num).toInt());
      case 'And':
        return AndTrigger((raw as List<dynamic>)
            .map((e) => TargetTrigger.fromJson(e as Map<String, dynamic>))
            .toList());
      case 'Or':
        return OrTrigger((raw as List<dynamic>)
            .map((e) => TargetTrigger.fromJson(e as Map<String, dynamic>))
            .toList());
      case 'HourAngleBetween':
        final m = raw as Map<String, dynamic>;
        return HourAngleBetweenTrigger(
          minHa: (m['minHa'] as num).toDouble(),
          maxHa: (m['maxHa'] as num).toDouble(),
        );
      default:
        throw FormatException(
            'Unknown TargetTrigger kind "$kind" — expected AltitudeAbove, '
            'AltitudeBelow, TimeAfter, TimeBefore, And, Or, or HourAngleBetween');
    }
  }

  /// Human-readable label used by the dashboard / live preview.
  String get label;

  /// True iff this trigger (or any nested sub-trigger) references an
  /// altitude threshold. Used by the validator to surface "this target
  /// never reaches that altitude from your location" errors.
  bool get referencesAltitude;

  /// Recursively detect empty And / Or compounds. Used by
  /// [TargetTriggerEmptyCompoundRule].
  bool get hasEmptyCompound;
}

class AltitudeAboveTrigger extends TargetTrigger {
  final double altitudeDeg;
  const AltitudeAboveTrigger(this.altitudeDeg);
  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'AltitudeAbove', 'value': altitudeDeg};
  @override
  String get label => 'altitude ≥ ${altitudeDeg.toStringAsFixed(1)}°';
  @override
  bool get referencesAltitude => true;
  @override
  bool get hasEmptyCompound => false;
  @override
  bool operator ==(Object other) =>
      other is AltitudeAboveTrigger && other.altitudeDeg == altitudeDeg;
  @override
  int get hashCode => Object.hash('AltitudeAbove', altitudeDeg);
}

class AltitudeBelowTrigger extends TargetTrigger {
  final double altitudeDeg;
  const AltitudeBelowTrigger(this.altitudeDeg);
  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'AltitudeBelow', 'value': altitudeDeg};
  @override
  String get label => 'altitude ≤ ${altitudeDeg.toStringAsFixed(1)}°';
  @override
  bool get referencesAltitude => true;
  @override
  bool get hasEmptyCompound => false;
  @override
  bool operator ==(Object other) =>
      other is AltitudeBelowTrigger && other.altitudeDeg == altitudeDeg;
  @override
  int get hashCode => Object.hash('AltitudeBelow', altitudeDeg);
}

class TimeAfterTrigger extends TargetTrigger {
  /// Unix timestamp (seconds).
  final int unixSeconds;
  const TimeAfterTrigger(this.unixSeconds);
  @override
  Map<String, dynamic> toJson() => {'kind': 'TimeAfter', 'value': unixSeconds};
  @override
  String get label => 'time ≥ $unixSeconds';
  @override
  bool get referencesAltitude => false;
  @override
  bool get hasEmptyCompound => false;
  @override
  bool operator ==(Object other) =>
      other is TimeAfterTrigger && other.unixSeconds == unixSeconds;
  @override
  int get hashCode => Object.hash('TimeAfter', unixSeconds);
}

class TimeBeforeTrigger extends TargetTrigger {
  /// Unix timestamp (seconds).
  final int unixSeconds;
  const TimeBeforeTrigger(this.unixSeconds);
  @override
  Map<String, dynamic> toJson() => {'kind': 'TimeBefore', 'value': unixSeconds};
  @override
  String get label => 'time < $unixSeconds';
  @override
  bool get referencesAltitude => false;
  @override
  bool get hasEmptyCompound => false;
  @override
  bool operator ==(Object other) =>
      other is TimeBeforeTrigger && other.unixSeconds == unixSeconds;
  @override
  int get hashCode => Object.hash('TimeBefore', unixSeconds);
}

class AndTrigger extends TargetTrigger {
  final List<TargetTrigger> children;
  const AndTrigger(this.children);
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'And',
        'value': children.map((c) => c.toJson()).toList(),
      };
  @override
  String get label => '(${children.map((c) => c.label).join(' AND ')})';
  @override
  bool get referencesAltitude => children.any((c) => c.referencesAltitude);
  @override
  bool get hasEmptyCompound =>
      children.isEmpty || children.any((c) => c.hasEmptyCompound);
  @override
  bool operator ==(Object other) {
    if (other is! AndTrigger) return false;
    if (other.children.length != children.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (other.children[i] != children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash('And', Object.hashAll(children));
}

class OrTrigger extends TargetTrigger {
  final List<TargetTrigger> children;
  const OrTrigger(this.children);
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'Or',
        'value': children.map((c) => c.toJson()).toList(),
      };
  @override
  String get label => '(${children.map((c) => c.label).join(' OR ')})';
  @override
  bool get referencesAltitude => children.any((c) => c.referencesAltitude);
  @override
  bool get hasEmptyCompound =>
      children.isEmpty || children.any((c) => c.hasEmptyCompound);
  @override
  bool operator ==(Object other) {
    if (other is! OrTrigger) return false;
    if (other.children.length != children.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (other.children[i] != children[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash('Or', Object.hashAll(children));
}

class HourAngleBetweenTrigger extends TargetTrigger {
  /// Minimum hour angle in hours (negative = east of meridian).
  final double minHa;

  /// Maximum hour angle in hours (positive = west of meridian).
  final double maxHa;

  const HourAngleBetweenTrigger({required this.minHa, required this.maxHa});
  @override
  Map<String, dynamic> toJson() => {
        'kind': 'HourAngleBetween',
        'value': {'minHa': minHa, 'maxHa': maxHa},
      };
  @override
  String get label =>
      '${minHa.toStringAsFixed(2)}h ≤ HA ≤ ${maxHa.toStringAsFixed(2)}h';
  @override
  bool get referencesAltitude => false;
  @override
  bool get hasEmptyCompound => false;
  @override
  bool operator ==(Object other) =>
      other is HourAngleBetweenTrigger &&
      other.minHa == minHa &&
      other.maxHa == maxHa;
  @override
  int get hashCode => Object.hash('HourAngleBetween', minHa, maxHa);
}

/// Evaluate a [TargetTrigger] against an observer / target / now snapshot.
/// Used by the dashboard live-preview and the
/// `TargetTriggerStartEndContradictionRule` validator. Mirrors the Rust
/// `TargetTrigger::is_satisfied`.
bool evaluateTargetTrigger(
  TargetTrigger trigger, {
  required double altitudeDeg,
  required double hourAngleHours,
  required int nowUnix,
}) {
  switch (trigger) {
    case AltitudeAboveTrigger(altitudeDeg: final t):
      return altitudeDeg >= t;
    case AltitudeBelowTrigger(altitudeDeg: final t):
      return altitudeDeg <= t;
    case TimeAfterTrigger(unixSeconds: final t):
      return nowUnix >= t;
    case TimeBeforeTrigger(unixSeconds: final t):
      return nowUnix < t;
    case AndTrigger(children: final cs):
      if (cs.isEmpty) return false;
      return cs.every((c) => evaluateTargetTrigger(c,
          altitudeDeg: altitudeDeg,
          hourAngleHours: hourAngleHours,
          nowUnix: nowUnix));
    case OrTrigger(children: final cs):
      if (cs.isEmpty) return false;
      return cs.any((c) => evaluateTargetTrigger(c,
          altitudeDeg: altitudeDeg,
          hourAngleHours: hourAngleHours,
          nowUnix: nowUnix));
    case HourAngleBetweenTrigger(minHa: final lo, maxHa: final hi):
      return hourAngleHours >= lo && hourAngleHours <= hi;
  }
}

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

  /// Wave 3 Agent 3 — optional per-target integration budget. `null` =
  /// no budget enforcement (current behaviour). When set, the
  /// TargetHeader runtime returns Success the moment the budget is met
  /// and the dashboard shows live per-filter progress bars.
  final IntegrationBudget? integrationBudget;

  /// Wave 4 — wait condition: target waits until this becomes true
  /// before imaging children. When `null` *and* none of the legacy
  /// `startAfter` / `minAltitude` fields are set, the target starts
  /// immediately.
  final TargetTrigger? startWhen;

  /// Wave 4 — stop condition: target ends as soon as this becomes true.
  /// When `null` *and* none of the legacy `endBefore` / `maxAltitude`
  /// fields are set, the target runs to natural completion of its
  /// children.
  final TargetTrigger? endWhen;

  /// Wave 4 — how often (seconds) the runtime polls `startWhen` /
  /// `endWhen`. Default 30s.
  final int triggerPollIntervalSecs;

  /// Wave 8 — brightness tier hint consulted by the TargetScheduler's
  /// adaptive-swap logic. `null` lets the scheduler infer the tier (or
  /// default to [BrightnessTier.medium]). Pinned values:
  /// [BrightnessTier.faint] for galaxies / faint nebulae,
  /// [BrightnessTier.medium] for bright galaxies / dim nebulae,
  /// [BrightnessTier.bright] for planetary nebulae / open clusters.
  final BrightnessTier? brightnessTierHint;

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
    this.integrationBudget,
    this.startWhen,
    this.endWhen,
    this.triggerPollIntervalSecs = 30,
    this.brightnessTierHint,
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

  /// Wave 3 Agent 3 — true iff the integration budget is configured and
  /// will actually enforce a cap. Used by UI to gate the "Budget" panel.
  bool get hasActiveIntegrationBudget =>
      integrationBudget != null && integrationBudget!.isActive;

  /// Wave 4 — true iff this target has an explicit start/end crossing
  /// configured. Used by the Targets tab to render the "Imaging window:
  /// HH:MM – HH:MM" row.
  bool get hasCrossingTriggers => startWhen != null || endWhen != null;

  /// Wave 4 — One-line label describing the imaging window in human
  /// terms ("starts when altitude ≥ 35°, ends when altitude ≤ 30°").
  /// Returns `null` when no triggers are set. The dashboard / Targets
  /// tab uses this to render a friendly row without re-deriving labels.
  String? get crossingWindowLabel {
    if (startWhen == null && endWhen == null) return null;
    final parts = <String>[];
    if (startWhen != null) parts.add('starts when ${startWhen!.label}');
    if (endWhen != null) parts.add('ends when ${endWhen!.label}');
    return parts.join(' · ');
  }

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
    Object? integrationBudget = _sentinel,
    Object? startWhen = _sentinel,
    Object? endWhen = _sentinel,
    int? triggerPollIntervalSecs,
    Object? brightnessTierHint = _sentinel,
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
      // sentinel-based copyWith so the caller can explicitly clear the
      // budget by passing `null` (`integrationBudget: null` => null,
      // omitted => keep this.integrationBudget).
      integrationBudget: identical(integrationBudget, _sentinel)
          ? this.integrationBudget
          : integrationBudget as IntegrationBudget?,
      startWhen: identical(startWhen, _sentinel)
          ? this.startWhen
          : startWhen as TargetTrigger?,
      endWhen: identical(endWhen, _sentinel)
          ? this.endWhen
          : endWhen as TargetTrigger?,
      triggerPollIntervalSecs:
          triggerPollIntervalSecs ?? this.triggerPollIntervalSecs,
      brightnessTierHint: identical(brightnessTierHint, _sentinel)
          ? this.brightnessTierHint
          : brightnessTierHint as BrightnessTier?,
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
        integrationBudget,
        startWhen,
        endWhen,
        triggerPollIntervalSecs,
        brightnessTierHint,
      ];
}

const Object _sentinel = Object();

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

  /// Audit C2 — when [conditionType] is [ConditionalType.safetyMonitorSafe]
  /// and the user has multiple safety monitors configured, this names the
  /// specific monitor the conditional branch should consult. `null` =
  /// fall back to the profile-default / aggregated safety state (current
  /// behaviour for single-monitor setups). Ignored for any other
  /// [ConditionalType].
  final String? safetyMonitorId;

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
    this.safetyMonitorId,
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
    // Sentinel-based optional: callers omit the argument to keep the
    // existing value, or pass `safetyMonitorId: null` to explicitly clear
    // it. The `?? this.X` pattern used for the other fields cannot
    // distinguish those two cases.
    Object? safetyMonitorId = _unsetSentinel,
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
      safetyMonitorId: identical(safetyMonitorId, _unsetSentinel)
          ? this.safetyMonitorId
          : safetyMonitorId as String?,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        conditionType,
        thresholdValue,
        thresholdTime,
        safetyMonitorId,
      ];
}

/// Sentinel used by [ConditionalNode.copyWith] to distinguish "argument
/// omitted" from "argument explicitly cleared to null". File-private; a
/// pure marker — never compared by value, only by identity.
const Object _unsetSentinel = Object();

/// Recovery node - handles errors with retry/recovery logic
class RecoveryNode extends SequenceNode {
  final RecoveryActionType recoveryAction;
  final int maxRetries;
  final TriggerType? triggerType;

  /// Generic threshold value whose meaning depends on [triggerType]:
  /// - For [TriggerType.hfrDegraded]: absolute HFR threshold in arcsec/px
  ///   (0 = disabled, use only relative mode)
  /// - For [TriggerType.altitudeLimit]: minimum altitude in degrees
  /// - For [TriggerType.humidityThreshold]: max percent humidity (e.g. 85)
  /// - For [TriggerType.driftLimit]: max drift in pixels (e.g. 30)
  /// - For [TriggerType.temperatureShift]: degrees of change to trigger
  /// - For [TriggerType.guidingFailed]: RMS threshold in arcsec
  /// - For [TriggerType.dawnApproaching]: minutes before astronomical twilight
  /// - For [TriggerType.autofocusInterval] / [TriggerType.ditherInterval]:
  ///   the integer cadence (every-N-frames) is read from [triggerEveryNFrames]
  ///   instead so the int type is preserved on the wire.
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

  // ===== Wave 1.5 Pack A trigger-config fields =====

  /// Cadence in frames for [TriggerType.autofocusInterval] /
  /// [TriggerType.ditherInterval]. The Rust side rejects 0 (`silently
  /// disables`); use the node's `enabled` flag to disable instead.
  final int triggerEveryNFrames;

  /// [TriggerType.focusDrift] rolling-window size (number of HFR samples).
  /// Rust clamps to [`FOCUS_DRIFT_WINDOW_MAX`] (100) at trigger-create time
  /// and now emits a user-visible ExecutorEvent::Error when clamping occurs.
  final int focusDriftWindowSize;

  /// [TriggerType.focusDrift] minimum number of consecutive increasing HFR
  /// samples before firing. Must be >= 2.
  final int focusDriftMinIncreasingCount;

  /// [TriggerType.focusDrift] minimum total HFR increase across the
  /// increasing run to fire.
  final double focusDriftMinTotalIncrease;

  /// [TriggerType.guidingFailed] required duration (seconds) of elevated RMS
  /// before firing.
  final double guidingFailedDurationSecs;

  // ===== Wave 5 Agent 4 cloud-motion trigger config fields =====

  /// [TriggerType.cloudArrivingIn] and [TriggerType.cloudOpeningIn]:
  /// fire when arrival/opening is at or below this many minutes.
  final double cloudMinutesBefore;

  /// [TriggerType.cloudArrivingIn]: required predicted coverage percentage
  /// (0-100). Trigger fires only when predicted cover exceeds this value.
  final double cloudCoverageThresholdPercent;

  /// [TriggerType.cloudOpeningIn]: minimum opening duration (seconds) that
  /// counts as imageable. Smaller gaps are ignored.
  final double cloudOpeningMinDurationSecs;

  /// [TriggerType.cloudCoverThreshold]: maximum allowed cover (0-100).
  /// Fire when current cover exceeds this value for [cloudCoverDurationSecs].
  final double cloudCoverMaxPercent;

  /// [TriggerType.cloudCoverThreshold]: required duration (seconds) above
  /// the threshold before firing. Acts as a debounce.
  final double cloudCoverDurationSecs;

  /// [TriggerType.transparencyDropped]: transparency fraction (0.0..=1.0)
  /// below which the trigger fires after [transparencyDurationSecs] of
  /// continuous samples at or below the threshold.
  final double transparencyBelowThreshold;

  /// [TriggerType.transparencyDropped]: required duration (seconds) at or
  /// below the threshold before firing. Acts as a debounce. Default 60s.
  final double transparencyDurationSecs;

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
    this.triggerEveryNFrames = 25,
    this.focusDriftWindowSize = 10,
    this.focusDriftMinIncreasingCount = 5,
    this.focusDriftMinTotalIncrease = 0.5,
    this.guidingFailedDurationSecs = 30.0,
    // Wave 5 Agent 4 — cloud-motion defaults. 10 min lead time + 70%
    // coverage matches the SGP-style "act before clouds hit" semantic;
    // the 30 s opening minimum prevents firing on a wisp.
    this.cloudMinutesBefore = 10.0,
    this.cloudCoverageThresholdPercent = 70.0,
    this.cloudOpeningMinDurationSecs = 300.0,
    this.cloudCoverMaxPercent = 80.0,
    this.cloudCoverDurationSecs = 60.0,
    // Wave 7 Science — transparency-adaptive trigger defaults. 0.7 +
    // 60s matches the brief's recommended "swap when transparency
    // drops below 70% for a minute" workflow.
    this.transparencyBelowThreshold = 0.7,
    this.transparencyDurationSecs = 60.0,
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
    int? triggerEveryNFrames,
    int? focusDriftWindowSize,
    int? focusDriftMinIncreasingCount,
    double? focusDriftMinTotalIncrease,
    double? guidingFailedDurationSecs,
    double? cloudMinutesBefore,
    double? cloudCoverageThresholdPercent,
    double? cloudOpeningMinDurationSecs,
    double? cloudCoverMaxPercent,
    double? cloudCoverDurationSecs,
    double? transparencyBelowThreshold,
    double? transparencyDurationSecs,
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
      triggerEveryNFrames: triggerEveryNFrames ?? this.triggerEveryNFrames,
      focusDriftWindowSize: focusDriftWindowSize ?? this.focusDriftWindowSize,
      focusDriftMinIncreasingCount:
          focusDriftMinIncreasingCount ?? this.focusDriftMinIncreasingCount,
      focusDriftMinTotalIncrease:
          focusDriftMinTotalIncrease ?? this.focusDriftMinTotalIncrease,
      guidingFailedDurationSecs:
          guidingFailedDurationSecs ?? this.guidingFailedDurationSecs,
      cloudMinutesBefore: cloudMinutesBefore ?? this.cloudMinutesBefore,
      cloudCoverageThresholdPercent:
          cloudCoverageThresholdPercent ?? this.cloudCoverageThresholdPercent,
      cloudOpeningMinDurationSecs:
          cloudOpeningMinDurationSecs ?? this.cloudOpeningMinDurationSecs,
      cloudCoverMaxPercent: cloudCoverMaxPercent ?? this.cloudCoverMaxPercent,
      cloudCoverDurationSecs:
          cloudCoverDurationSecs ?? this.cloudCoverDurationSecs,
      transparencyBelowThreshold:
          transparencyBelowThreshold ?? this.transparencyBelowThreshold,
      transparencyDurationSecs:
          transparencyDurationSecs ?? this.transparencyDurationSecs,
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
        triggerEveryNFrames,
        focusDriftWindowSize,
        focusDriftMinIncreasingCount,
        focusDriftMinTotalIncrease,
        guidingFailedDurationSecs,
        cloudMinutesBefore,
        cloudCoverageThresholdPercent,
        cloudOpeningMinDurationSecs,
        cloudCoverMaxPercent,
        cloudCoverDurationSecs,
        transparencyBelowThreshold,
        transparencyDurationSecs,
      ];

  /// Wave 1.5 Pack A: serialize the configured trigger into the Rust-side
  /// `TriggerType` JSON form. Mirrors the tagged-enum serde format used by
  /// `nightshade_sequencer::TriggerType`. `null` means "any error" (no
  /// type-specific trigger configured), which matches Rust's
  /// `RecoveryConfig::trigger: Option<TriggerType>` semantics.
  ///
  /// Returns either a `Map<String, dynamic>` (struct variants) or a `String`
  /// (unit variants) — serde's externally-tagged default encodes those forms
  /// as `{"VariantName": {...}}` and `"VariantName"` respectively. Callers
  /// pass the result through `jsonEncode` so both shapes round-trip.
  dynamic toRustTriggerConfig() {
    final type = triggerType;
    if (type == null) return null;
    switch (type) {
      case TriggerType.hfrDegraded:
        return {
          'HfrDegraded': {
            'threshold_percent': hfrThresholdPercent,
            'absolute_threshold': triggerThreshold ?? 0.0,
            'consecutive_frames': hfrConsecutiveFrames,
          }
        };
      case TriggerType.meridianFlip:
        // MeridianFlip carries a full MeridianFlipConfig payload. RecoveryNode
        // doesn't model that yet; default to the Rust-side serde defaults by
        // passing an empty object so the deserializer fills in the defaults.
        return {
          'MeridianFlip': {'config': <String, dynamic>{}}
        };
      case TriggerType.guidingFailed:
        return {
          'GuidingFailed': {
            'rms_threshold': triggerThreshold ?? 2.0,
            'duration_secs': guidingFailedDurationSecs,
          }
        };
      case TriggerType.altitudeLimit:
        return {
          'AltitudeLimit': {'min_altitude': triggerThreshold ?? 30.0}
        };
      case TriggerType.weatherUnsafe:
        return 'WeatherUnsafe';
      case TriggerType.temperatureShift:
        return {
          'TemperatureShift': {'degrees': triggerThreshold ?? 2.0}
        };
      case TriggerType.filterChange:
        return 'FilterChange';
      case TriggerType.dawnApproaching:
        return {
          'DawnApproaching': {'minutes_before': triggerThreshold ?? 30.0}
        };
      case TriggerType.humidityThreshold:
        return {
          'HumidityThreshold': {'max_percent': triggerThreshold ?? 85.0}
        };
      case TriggerType.focusDrift:
        return {
          'FocusDrift': {
            'window_size': focusDriftWindowSize,
            'min_increasing_count': focusDriftMinIncreasingCount,
            'min_total_increase': focusDriftMinTotalIncrease,
          }
        };
      case TriggerType.mountTrackingLost:
        return 'MountTrackingLost';
      case TriggerType.domeShutterNotOpen:
        return 'DomeShutterNotOpen';
      case TriggerType.guideStarLost:
        return 'GuideStarLost';
      case TriggerType.autofocusInterval:
        return {
          'AutofocusInterval': {'every_n_frames': triggerEveryNFrames}
        };
      case TriggerType.ditherInterval:
        return {
          'DitherInterval': {'every_n_frames': triggerEveryNFrames}
        };
      case TriggerType.driftLimit:
        return {
          'DriftLimit': {'max_pixels': triggerThreshold ?? 30.0}
        };
      // Wave 5 Agent 4 — cloud-motion-aware triggers. Field names match
      // the Rust serde-tagged enum form (`#[serde(...)]` external default).
      case TriggerType.cloudArrivingIn:
        return {
          'CloudArrivingIn': {
            'minutes_before': cloudMinutesBefore,
            'coverage_threshold': cloudCoverageThresholdPercent,
          }
        };
      case TriggerType.cloudOpeningIn:
        return {
          'CloudOpeningIn': {
            'minutes_before': cloudMinutesBefore,
            'minimum_duration_secs': cloudOpeningMinDurationSecs,
          }
        };
      case TriggerType.cloudCoverThreshold:
        return {
          'CloudCoverThreshold': {
            'max_percent': cloudCoverMaxPercent,
            'duration_secs': cloudCoverDurationSecs,
          }
        };
      // Wave 7 Science — transparency-adaptive trigger. Field names
      // match the Rust serde-tagged enum variant.
      case TriggerType.transparencyDropped:
        return {
          'TransparencyDropped': {
            'below_threshold': transparencyBelowThreshold,
            'duration_secs': transparencyDurationSecs,
          }
        };
    }
  }
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

/// Wave 5 Agent 2 — Sky-brightness adaptive exposure config carried on
/// an [ExposureNode] (or as a global default in app settings). Mirrors
/// the Rust `AdaptiveExposureConfig`. Plain immutable value class with
/// hand-rolled equality so we stay consistent with the rest of the
/// sequence-models package (no freezed annotations here).
@Freezed(fromJson: true, toJson: true)
class AdaptiveExposureConfig with _$AdaptiveExposureConfig {
  const AdaptiveExposureConfig._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory AdaptiveExposureConfig({
    /// Target SNR (informational; the current adapter scales by sky-
    /// background flux ratio rather than aiming at a numeric target).
    @Default(30.0) double targetSnr,

    /// Sky brightness in mag/arcsec² that the node's configured nominal
    /// exposure is calibrated for.
    @Default(21.5) double referenceSkyBrightnessMag,

    /// Global minimum exposure clamp (seconds).
    @Default(5.0) double minExposureSecs,

    /// Global maximum exposure clamp (seconds).
    @Default(600.0) double maxExposureSecs,

    /// Per-filter enable map. Filter name -> bool. Empty => apply globally.
    @Default(<String, bool>{}) Map<String, bool> perFilterEnabled,

    /// Per-filter minimum exposure overrides (seconds).
    @Default(<String, double>{}) Map<String, double> perFilterMinSecs,

    /// Per-filter maximum exposure overrides (seconds).
    @Default(<String, double>{}) Map<String, double> perFilterMaxSecs,

    /// Global enable toggle. When false the whole config is a no-op
    /// regardless of per-filter map content.
    @Default(true) bool enabled,
  }) = _AdaptiveExposureConfig;

  factory AdaptiveExposureConfig.fromJson(Map<String, dynamic> json) =>
      _$AdaptiveExposureConfigFromJson(json);

  /// Whether the adapter wants to act on the given filter. Mirrors the
  /// Rust `is_enabled_for_filter`.
  bool isEnabledForFilter(String? filter) {
    if (!enabled) return false;
    if (filter == null) return true;
    final per = perFilterEnabled[filter];
    if (per != null) return per;
    return perFilterEnabled.isEmpty;
  }

  /// Resolve the per-filter min clamp (per-filter wins over global).
  double minForFilter(String? filter) {
    if (filter != null) {
      final per = perFilterMinSecs[filter];
      if (per != null) return per;
    }
    return minExposureSecs;
  }

  /// Resolve the per-filter max clamp (per-filter wins over global).
  double maxForFilter(String? filter) {
    if (filter != null) {
      final per = perFilterMaxSecs[filter];
      if (per != null) return per;
    }
    return maxExposureSecs;
  }
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

  /// Wave 5 Agent 2 — per-node sky-brightness adaptive exposure config.
  /// `null` means "use the global default from app settings"; an
  /// explicit value overrides the global default for this node.
  final AdaptiveExposureConfig? adaptiveExposure;

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
    this.adaptiveExposure,
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
    // Wave 5 Agent 2: pass `clearAdaptiveExposure: true` to reset to
    // "use global default"; passing a non-null `adaptiveExposure`
    // installs an explicit per-node override.
    AdaptiveExposureConfig? adaptiveExposure,
    bool clearAdaptiveExposure = false,
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
      adaptiveExposure: clearAdaptiveExposure
          ? null
          : (adaptiveExposure ?? this.adaptiveExposure),
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
        adaptiveExposure,
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
/// Mirror of Rust `DitherPattern` (sequencer/src/lib.rs). `random` produces
/// classic uncorrelated offsets each call; `grid` cycles through an NxN
/// grid of positions, which yields more uniform sky coverage.
enum DitherPattern {
  random,
  grid,
}

class DitherNode extends SequenceNode {
  final double pixels;
  final double settleTime;
  final double settlePixels;

  /// Maximum time to wait for settling after dither (seconds)
  final double settleTimeout;

  /// If true, only dither in RA (useful for dec backlash-prone setups)
  final bool raOnly;

  /// Dither pattern selection. [DitherPattern.random] is classic; [DitherPattern.grid]
  /// walks a [gridSize] x [gridSize] grid for systematic coverage.
  final DitherPattern pattern;

  /// Grid side length (N for NxN) used when [pattern] is [DitherPattern.grid].
  /// Ignored for [DitherPattern.random]. Must be >= 2.
  final int gridSize;

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
    this.pattern = DitherPattern.random,
    this.gridSize = 3,
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
    DitherPattern? pattern,
    int? gridSize,
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
      pattern: pattern ?? this.pattern,
      gridSize: gridSize ?? this.gridSize,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        pixels,
        settleTime,
        settlePixels,
        settleTimeout,
        raOnly,
        pattern,
        gridSize,
      ];
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

  /// Wave 5 Agent 5 — explicit transport override for this node only.
  ///
  /// When non-null, the executor's NotificationNode dispatcher hands this
  /// list to `NotificationRouter.routeNotificationNode(explicitTransports:)`
  /// which bypasses the matrix's `custom` rule. When null (legacy), the
  /// node inherits the matrix's `custom` transports.
  final List<NotificationTransportKind>? explicitTransports;

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
    this.explicitTransports,
  });

  @override
  String get nodeType => 'Notification';

  @override
  String get iconName => 'bell';

  @override
  NodeCategory get category => NodeCategory.instruction;

  /// `copyWith` for `explicitTransports`. We need a three-state semantics
  /// here:
  ///   * leave alone     → pass nothing
  ///   * set to a value  → pass the new list
  ///   * clear (back to matrix-default) → set `clearExplicitTransports: true`
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
    List<NotificationTransportKind>? explicitTransports,
    bool clearExplicitTransports = false,
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
      explicitTransports: clearExplicitTransports
          ? null
          : (explicitTransports ?? this.explicitTransports),
    );
  }

  @override
  List<Object?> get props =>
      [...super.props, title, message, level, explicitTransports];
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
    final resolvedUseGlobalDefaults =
        useGlobalDefaults ?? (touchedConfig ? false : this.useGlobalDefaults);

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
// Wave 3 Agent 1: TargetScheduler — dynamic target picker
// =============================================================================

/// Wave 8 — brightness tier hint mirrored from
/// `crate::scheduling::adaptive_swap::BrightnessTier`. Used by
/// [TargetSchedulerNode]'s adaptive-swap logic to decide whether the
/// currently-running target's tier still accepts the live sky-conditions
/// score.
enum BrightnessTier {
  /// Galaxies, faint nebulae — needs pristine sky.
  faint,

  /// Bright galaxies, medium nebulae — tolerates degraded sky.
  medium,

  /// Planetary nebulae, open clusters — tolerates poor sky.
  bright;

  /// Stable wire string used by the Rust ↔ Dart bridge. Matches
  /// `BrightnessTier::as_str()` on the Rust side.
  String get wireValue => name; // 'faint' / 'medium' / 'bright'

  /// Human-friendly label for the properties editor dropdown.
  String get displayLabel {
    switch (this) {
      case BrightnessTier.faint:
        return 'Faint (galaxies, dim nebulae)';
      case BrightnessTier.medium:
        return 'Medium (bright galaxies, dim nebulae)';
      case BrightnessTier.bright:
        return 'Bright (planetary nebulae, open clusters)';
    }
  }

  /// Parse from the wire string. Returns `null` for unrecognised values
  /// so callers can fall back to "auto" rather than silently accepting
  /// junk input — schema drift between Rust and Dart should be loud.
  static BrightnessTier? fromWire(String? s) {
    if (s == null) return null;
    switch (s.toLowerCase()) {
      case 'faint':
        return BrightnessTier.faint;
      case 'medium':
        return BrightnessTier.medium;
      case 'bright':
        return BrightnessTier.bright;
      default:
        return null;
    }
  }
}

/// Wave 8 — per-tier conditions-score floor preferences. Mirrors the
/// Rust `BrightnessTierPreferences` struct.
@Freezed(fromJson: true, toJson: true)
class BrightnessTierPreferences with _$BrightnessTierPreferences {
  const BrightnessTierPreferences._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory BrightnessTierPreferences({
    @Default(70.0) double faintMinScore,
    @Default(50.0) double mediumMinScore,
    @Default(30.0) double brightMinScore,
  }) = _BrightnessTierPreferences;

  factory BrightnessTierPreferences.fromJson(Map<String, dynamic> json) =>
      _$BrightnessTierPreferencesFromJson(json);

  double floorFor(BrightnessTier tier) {
    switch (tier) {
      case BrightnessTier.faint:
        return faintMinScore;
      case BrightnessTier.medium:
        return mediumMinScore;
      case BrightnessTier.bright:
        return brightMinScore;
    }
  }

  bool accepts(BrightnessTier tier, double score) => score >= floorFor(tier);
}

/// Wave 8 — per-axis weights applied when composing the live
/// ConditionsScore. Mirrors the Rust `ConditionsScoreWeights` struct.
@Freezed(fromJson: true, toJson: true)
class ConditionsScoreWeights with _$ConditionsScoreWeights {
  const ConditionsScoreWeights._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ConditionsScoreWeights({
    @Default(0.40) double transparencyWeight,
    @Default(0.25) double seeingWeight,
    @Default(0.25) double cloudWeight,
    @Default(0.10) double windWeight,
  }) = _ConditionsScoreWeights;

  factory ConditionsScoreWeights.fromJson(Map<String, dynamic> json) =>
      _$ConditionsScoreWeightsFromJson(json);

  double get sum =>
      transparencyWeight + seeingWeight + cloudWeight + windWeight;

  /// True when the weights sum to ~1.0 (validator lenient ±5% band).
  bool get isNormalised => sum >= 0.95 && sum <= 1.05;
}

/// Wave 8 — composite sky-conditions score (0..=100) pushed from Dart
/// to the Rust executor. Mirrors `ConditionsScore`.
@Freezed(fromJson: true, toJson: true)
class ConditionsScore with _$ConditionsScore {
  const ConditionsScore._();

  // `explicitToJson: true` so the nested `weights` field is materialised
  // as a `Map<String, dynamic>` (via `ConditionsScoreWeights.toJson`)
  // rather than left as a raw `ConditionsScoreWeights` instance in the
  // emitted Map. Phase 1's `to_json_uses_snake_case_and_unix_secs...`
  // contract test asserts `json['weights'] is Map<String, dynamic>`.
  @JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
  const factory ConditionsScore({
    required double score,
    double? transparencyScore,
    double? seeingScore,
    double? cloudScore,
    double? windScore,
    @Default(ConditionsScoreWeights()) ConditionsScoreWeights weights,
    // `generated_unix_secs` (int seconds) on the wire. The Rust side uses
    // `serde_with::TimestampSeconds<i64>`. PHASE-2-NOTE: The pre-freezed
    // fromJson fell back to `0` (epoch) on missing field; the freezed
    // form makes the field required, which is strictly stricter (errors
    // are a feature). The Rust producer always emits this field, so
    // production traffic is unaffected; only synthetic JSON missing the
    // key will now throw — matching CLAUDE.md's "silent fallback hides
    // bugs" policy. Phase 1's contract tests always provide the key.
    @JsonKey(name: 'generated_unix_secs')
    @UnixSecsDateTimeConverter()
    required DateTime generatedAt,
  }) = _ConditionsScore;

  factory ConditionsScore.fromJson(Map<String, dynamic> json) =>
      _$ConditionsScoreFromJson(json);

  /// Convenience: classify the score band.
  String get qualityLabel {
    if (score >= 90) return 'Pristine';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Degraded';
    return 'Bad';
  }
}

/// Wave 8 — runtime adaptive-swap state pushed from Rust to the dashboard.
/// Mirrors the Rust `AdaptiveSwapRuntimeState` struct.
@Freezed(fromJson: true, toJson: true)
class AdaptiveSwapRuntimeState with _$AdaptiveSwapRuntimeState {
  const AdaptiveSwapRuntimeState._();

  @JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: true)
  const factory AdaptiveSwapRuntimeState({
    String? currentTargetId,
    String? currentTier,
    String? lastDecisionKind,
    String? lastDecisionReason,
    // `last_swap_unix_secs` (nullable int seconds). When `null`, the
    // JSON field is present-with-null (not omitted) — Phase 1's
    // `null_last_swap_serialises_as_null_field` contract test pins this.
    @JsonKey(name: 'last_swap_unix_secs')
    @NullableUnixSecsDateTimeConverter()
    DateTime? lastSwapAt,
    String? lastSwapFromTargetId,
    String? lastSwapToTargetId,
    double? lastObservedScore,
    double? configuredThreshold,
    @Default(180.0) double configuredHysteresisSecs,
  }) = _AdaptiveSwapRuntimeState;

  factory AdaptiveSwapRuntimeState.fromJson(Map<String, dynamic> json) =>
      _$AdaptiveSwapRuntimeStateFromJson(json);

  /// Seconds until the next swap is allowed by hysteresis. Returns `null`
  /// when no swap has fired yet or the cooldown has elapsed.
  double? cooldownRemainingSecs(DateTime now) {
    final last = lastSwapAt;
    if (last == null) return null;
    final elapsed = now.difference(last).inMilliseconds / 1000.0;
    final remaining = configuredHysteresisSecs - elapsed;
    return remaining > 0 ? remaining : null;
  }
}

/// Wave 8 — paired snapshot returned by
/// `api_sequencer_get_adaptive_swap_json`. The score may be null when
/// telemetry has been lost while a previous adaptive-swap decision is
/// still on display, so the two fields are independent.
@Freezed(fromJson: true, toJson: true)
class AdaptiveSwapSnapshot with _$AdaptiveSwapSnapshot {
  // `explicitToJson: true` so the nested `score` and `state` fields are
  // serialised as `Map<String, dynamic>` rather than as raw freezed
  // instances. Phase 1's `to_json_nests_score_and_state` contract test
  // asserts both nested fields decode as Maps.
  @JsonSerializable(explicitToJson: true)
  const factory AdaptiveSwapSnapshot({
    ConditionsScore? score,
    // Default empty state used when the JSON payload is missing
    // `state` entirely (Phase 1's
    // `from_json_treats_missing_state_as_default_state` contract test).
    @Default(AdaptiveSwapRuntimeState()) AdaptiveSwapRuntimeState state,
  }) = _AdaptiveSwapSnapshot;

  factory AdaptiveSwapSnapshot.fromJson(Map<String, dynamic> json) =>
      _$AdaptiveSwapSnapshotFromJson(json);
}

/// Container node that picks the highest-scoring runnable [TargetHeaderNode]
/// child at runtime instead of executing them in author order.
///
/// Mirrors `TargetSchedulerConfig` in the Rust sequencer (see
/// `native/nightshade_native/sequencer/src/lib.rs`). All scoring weights and
/// thresholds are sent verbatim to the Rust scheduler which uses the same
/// scoring math as the planetarium-side `TargetScoringService` — see the
/// parity test in `target_scheduler/scoring.rs`.
class TargetSchedulerNode extends SequenceNode {
  /// Altitude axis weight (default 0.25).
  final double altitudeWeight;

  /// Moon-distance axis weight (default 0.25).
  final double moonDistanceWeight;

  /// Transit-proximity axis weight (default 0.20).
  final double transitProximityWeight;

  /// Darkness axis weight (default 0.15).
  final double darknessWeight;

  /// Airmass axis weight (default 0.15).
  final double airmassWeight;

  /// Minimum total score (0..=100) below which the scheduler treats every
  /// target as unrunnable. When no child clears this floor the node returns
  /// Skipped. Default 30.
  final double minScoreToRun;

  /// Recompute the schedule every N exposures completed inside the
  /// currently-running target's subtree. 0 means "boundary-only" — only
  /// re-decide when the current target finishes.
  final int recomputeEveryNExposures;

  /// Once a target's subtree starts, finish its current Loop iteration
  /// before switching even if a recompute would otherwise pick someone else.
  /// Prevents abandoning a partially-completed exposure burst. Default true.
  final bool finishIterationOnSwitch;

  /// Wave 8 — conditions-score floor below which adaptive swap engages.
  /// `null` disables the feature for this scheduler instance.
  final double? swapOnConditionsBelow;

  /// Wave 8 — minimum seconds between consecutive adaptive swaps
  /// (hysteresis). Default 180s (3 minutes).
  final double swapHysteresisSecs;

  /// Wave 8 — per-tier conditions-score floors. Defaults follow the
  /// brief (faint ≥ 70, medium ≥ 50, bright ≥ 30).
  final BrightnessTierPreferences brightnessTierPreferences;

  /// Wave 8 — score readings older than this are treated as missing
  /// telemetry and the scheduler falls back to the ordinary ranking.
  /// Default 300s (5 minutes).
  final int maxConditionsScoreAgeSecs;

  TargetSchedulerNode({
    super.id,
    super.name = 'Scheduler',
    super.isEnabled,
    super.childIds,
    super.parentId,
    super.orderIndex,
    super.comment,
    this.altitudeWeight = 0.25,
    this.moonDistanceWeight = 0.25,
    this.transitProximityWeight = 0.20,
    this.darknessWeight = 0.15,
    this.airmassWeight = 0.15,
    this.minScoreToRun = 30.0,
    this.recomputeEveryNExposures = 0,
    this.finishIterationOnSwitch = true,
    this.swapOnConditionsBelow,
    this.swapHysteresisSecs = 180.0,
    this.brightnessTierPreferences = const BrightnessTierPreferences(),
    this.maxConditionsScoreAgeSecs = 300,
  });

  /// Stable nodeType identifier. Must match the Rust `NodeType` discriminant
  /// (`TargetScheduler`) so `serde_json::from_str` on the round-tripped
  /// config picks the right variant.
  @override
  String get nodeType => 'TargetScheduler';

  @override
  String get iconName => 'scheduler';

  /// Categorised as `logic` because the node is a container; the editor
  /// colour-codes it the same way as Loop/Parallel.
  @override
  NodeCategory get category => NodeCategory.logic;

  /// The scheduler does not directly require any device — its children
  /// (TargetHeaders) accumulate the device requirements.
  @override
  Set<DeviceType> get requiredDevices => {DeviceType.mount};

  /// True when the five weights sum to approximately 1.0 (lenient ±5% band
  /// so floating-point rounding from UI sliders doesn't trip the warning).
  /// Used by the validator's [TargetSchedulerWeightsRule].
  bool get weightsNormalised {
    final sum = altitudeWeight +
        moonDistanceWeight +
        transitProximityWeight +
        darknessWeight +
        airmassWeight;
    return sum >= 0.95 && sum <= 1.05;
  }

  /// Sum of all five weights — surfaced in the UI's "normalised: 1.00"
  /// indicator.
  double get weightsSum =>
      altitudeWeight +
      moonDistanceWeight +
      transitProximityWeight +
      darknessWeight +
      airmassWeight;

  /// Return a copy whose weights sum to exactly 1.0. Used by the
  /// properties-editor "Normalise" button so users don't have to nudge five
  /// sliders by hand.
  TargetSchedulerNode normalisedWeights() {
    final sum = weightsSum;
    if (sum <= 0) return this;
    return copyWith(
      altitudeWeight: altitudeWeight / sum,
      moonDistanceWeight: moonDistanceWeight / sum,
      transitProximityWeight: transitProximityWeight / sum,
      darknessWeight: darknessWeight / sum,
      airmassWeight: airmassWeight / sum,
    );
  }

  @override
  TargetSchedulerNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    double? altitudeWeight,
    double? moonDistanceWeight,
    double? transitProximityWeight,
    double? darknessWeight,
    double? airmassWeight,
    double? minScoreToRun,
    int? recomputeEveryNExposures,
    bool? finishIterationOnSwitch,
    Object? swapOnConditionsBelow = _sentinel,
    double? swapHysteresisSecs,
    BrightnessTierPreferences? brightnessTierPreferences,
    int? maxConditionsScoreAgeSecs,
  }) {
    return TargetSchedulerNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      altitudeWeight: altitudeWeight ?? this.altitudeWeight,
      moonDistanceWeight: moonDistanceWeight ?? this.moonDistanceWeight,
      transitProximityWeight:
          transitProximityWeight ?? this.transitProximityWeight,
      darknessWeight: darknessWeight ?? this.darknessWeight,
      airmassWeight: airmassWeight ?? this.airmassWeight,
      minScoreToRun: minScoreToRun ?? this.minScoreToRun,
      recomputeEveryNExposures:
          recomputeEveryNExposures ?? this.recomputeEveryNExposures,
      finishIterationOnSwitch:
          finishIterationOnSwitch ?? this.finishIterationOnSwitch,
      swapOnConditionsBelow: identical(swapOnConditionsBelow, _sentinel)
          ? this.swapOnConditionsBelow
          : switch (swapOnConditionsBelow) {
              null => null,
              num value => value.toDouble(),
              _ => throw ArgumentError.value(
                  swapOnConditionsBelow,
                  'swapOnConditionsBelow',
                  'Expected a number or null',
                ),
            },
      swapHysteresisSecs: swapHysteresisSecs ?? this.swapHysteresisSecs,
      brightnessTierPreferences:
          brightnessTierPreferences ?? this.brightnessTierPreferences,
      maxConditionsScoreAgeSecs:
          maxConditionsScoreAgeSecs ?? this.maxConditionsScoreAgeSecs,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        altitudeWeight,
        moonDistanceWeight,
        transitProximityWeight,
        darknessWeight,
        airmassWeight,
        minScoreToRun,
        recomputeEveryNExposures,
        finishIterationOnSwitch,
        swapOnConditionsBelow,
        swapHysteresisSecs,
        brightnessTierPreferences,
        maxConditionsScoreAgeSecs,
      ];
}

// =============================================================================
// Wave 3 Agent 2: SmartExposure — multi-filter container instruction
// =============================================================================

/// One row in a [SmartExposureNode]'s filter plan.
///
/// Mirrors the Rust `FilterPlan` struct in
/// `native/nightshade_native/sequencer/src/lib.rs`. The field set is the
/// minimal "what to take per filter": filter name (+ optional index), how
/// many subs, sub-length, gain/offset/binning, and a per-plan dither
/// cadence override.
@Freezed(fromJson: true, toJson: true)
class FilterPlan with _$FilterPlan {
  const FilterPlan._();

  @JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: true)
  const factory FilterPlan({
    /// Filter wheel slot name (e.g. "L", "Ha"). Matched against the
    /// connected filter wheel's name list when [filterIndex] is null.
    @Default('') String filterName,

    /// 0-based filter wheel index. Preferred over [filterName] for
    /// reliability — matches `ExposureNode.filterIndex` / Rust
    /// `FilterConfig::filter_index`.
    int? filterIndex,

    /// Total number of exposures to take for this filter.
    @Default(10) int count,

    /// Sub-exposure duration in seconds.
    @Default(60.0) double durationSecs,

    /// Optional gain override. null means "use camera/profile default".
    int? gain,

    /// Optional offset override.
    int? offset,

    /// Binning for this filter. Defaults to 1x1.
    @Default(BinningMode.one) @BinningModeJsonConverter() BinningMode binning,

    /// Per-plan dither cadence (every N frames). null disables dithering for
    /// this filter regardless of any global default. 0 is treated as "no
    /// dither" — matches `ExposureNode.ditherEvery`.
    int? ditherEvery,
  }) = _FilterPlan;

  factory FilterPlan.fromJson(Map<String, dynamic> json) =>
      _$FilterPlanFromJson(json);

  /// Estimated integration time for this row, in seconds (count * duration).
  /// Does NOT include filter change or dither overhead — that's added by
  /// `SmartExposureNode.estimateTotalSecs`.
  double get integrationSecs => count * durationSecs;
}

// Note: the `_sentinel` constant declared earlier in this file (above
// `LoopNode`) is reused here by `FilterPlan.copyWith` so callers can pass
// an explicit `null` to clear a nullable field without colliding with the
// "no-argument" default.

/// Map [BinningMode] to the PascalCase string Rust's serde expects.
/// Kept private and local because the rest of the file uses sequence
/// _executor's binning string helper; here we need the same mapping for
/// `FilterPlan.toJson` without dragging the executor's private helper into
/// the models layer.
String _binningModeToRustString(BinningMode mode) {
  switch (mode) {
    case BinningMode.one:
      return 'One';
    case BinningMode.two:
      return 'Two';
    case BinningMode.three:
      return 'Three';
    case BinningMode.four:
      return 'Four';
  }
}

BinningMode _rustStringToBinningMode(String? value) {
  switch (value) {
    case 'One':
      return BinningMode.one;
    case 'Two':
      return BinningMode.two;
    case 'Three':
      return BinningMode.three;
    case 'Four':
      return BinningMode.four;
    default:
      return BinningMode.one;
  }
}

/// SmartExposure container instruction. One row per filter; the node
/// internally handles filter changes, dither cadence, and rotation order
/// — see the Rust `SmartExposureConfig` doc-comment for the full execution
/// semantics.
///
/// SmartExposure is a *leaf* in the Dart tree (no childIds): the per-filter
/// behaviour is fully encoded in the [plans] field. The Rust executor
/// dispatches each plan row through the existing `TakeExposure` /
/// `ChangeFilter` instruction nodes via the InstructionRegistry, so a
/// hand-authored `FilterChange → Loop(N) → TakeExposure` chain and a
/// SmartExposure with the equivalent plan rows produce indistinguishable
/// imaging output.
class SmartExposureNode extends SequenceNode {
  /// Ordered list of per-filter plans. Rotation order when [rotateFilters]
  /// is true.
  final List<FilterPlan> plans;

  /// If true, take one batch from each plan in order before repeating
  /// (RGRGRG …). If false, drain each plan before moving to the next
  /// (RRRRRGGG …). Default true (rotation).
  final bool rotateFilters;

  /// If true, run a dither between filter changes in addition to the
  /// per-plan [FilterPlan.ditherEvery]. Default false.
  final bool ditherOnFilterChange;

  /// Global integration budget cap in seconds. When > 0 and the
  /// node-local accumulated exposure time exceeds this value, SmartExposure
  /// returns Success even if some plans have unfilled counts.
  ///
  /// 0 = no cap (run every plan to completion).
  final double integrationBudgetSecs;

  /// Number of exposures to take per filter before rotating to the next
  /// (only meaningful when [rotateFilters] is true). Default 1.
  final int batchSize;

  SmartExposureNode({
    super.id,
    super.name = 'Smart Exposure',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.plans = const [],
    this.rotateFilters = true,
    this.ditherOnFilterChange = false,
    this.integrationBudgetSecs = 0.0,
    this.batchSize = 1,
  });

  @override
  String get nodeType => 'SmartExposure';

  @override
  String get iconName => 'layers';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices =>
      {DeviceType.camera, DeviceType.filterWheel};

  /// Sum of per-plan integration time across all filter rows (count *
  /// duration), in seconds. The dashboard's "estimated total" indicator
  /// reads this; wall-clock estimates that include filter-change and
  /// dither overhead live in `sequence_time_estimator.dart`.
  double get totalIntegrationSecs =>
      plans.fold(0.0, (sum, p) => sum + p.integrationSecs);

  /// Number of distinct filter names across [plans]. Used by the UI's
  /// "duplicate filter" warning — two plans with the same filter name are
  /// legal (e.g. two different exposure lengths for the same band) but
  /// usually a UX mistake.
  int get distinctFilterCount => plans.map((p) => p.filterName).toSet().length;

  /// True when at least two plans share the same filter name. Surfaced by
  /// [SmartExposureDuplicateFilterRule].
  bool get hasDuplicateFilter => distinctFilterCount != plans.length;

  @override
  SmartExposureNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    List<FilterPlan>? plans,
    bool? rotateFilters,
    bool? ditherOnFilterChange,
    double? integrationBudgetSecs,
    int? batchSize,
  }) {
    return SmartExposureNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      plans: plans ?? this.plans,
      rotateFilters: rotateFilters ?? this.rotateFilters,
      ditherOnFilterChange: ditherOnFilterChange ?? this.ditherOnFilterChange,
      integrationBudgetSecs:
          integrationBudgetSecs ?? this.integrationBudgetSecs,
      batchSize: batchSize ?? this.batchSize,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        plans,
        rotateFilters,
        ditherOnFilterChange,
        integrationBudgetSecs,
        batchSize,
      ];
}

// =============================================================================
// LIVE STACKING (Wave 7 Agent 2)
// =============================================================================

/// Operating mode for a [LiveStackingNode].
///
/// `broadcastOnly` keeps the building stack in memory only. The
/// captured FITS files are untouched; the broadcast simply pulls a
/// rendered JPEG of the current stack on demand.
///
/// `recordAndBroadcast` additionally writes the stacked JPEG to the
/// session's save directory after every accepted frame so the user
/// keeps a build-up timelapse alongside the raw subs.
enum LiveStackingMode {
  broadcastOnly,
  recordAndBroadcast;

  String get storageKey => switch (this) {
        LiveStackingMode.broadcastOnly => 'broadcast_only',
        LiveStackingMode.recordAndBroadcast => 'record_and_broadcast',
      };

  String get label => switch (this) {
        LiveStackingMode.broadcastOnly => 'Broadcast only',
        LiveStackingMode.recordAndBroadcast => 'Record + broadcast',
      };

  static LiveStackingMode fromStorageKey(String? key) => switch (key) {
        'record_and_broadcast' => LiveStackingMode.recordAndBroadcast,
        _ => LiveStackingMode.broadcastOnly,
      };
}

/// Stack-combine method for the live stack.
///
/// Wire form is snake_case to match the Rust `StackMethod` enum
/// (see `native/nightshade_native/sequencer/src/lib.rs`).
enum LiveStackingMethod {
  average,
  medianRej,
  sigma;

  String get storageKey => switch (this) {
        LiveStackingMethod.average => 'average',
        LiveStackingMethod.medianRej => 'median_rej',
        LiveStackingMethod.sigma => 'sigma',
      };

  String get label => switch (this) {
        LiveStackingMethod.average => 'Average',
        LiveStackingMethod.medianRej => 'Median + Rejection',
        LiveStackingMethod.sigma => 'Sigma-clipped',
      };

  static LiveStackingMethod fromStorageKey(String? key) => switch (key) {
        'median_rej' => LiveStackingMethod.medianRej,
        'sigma' => LiveStackingMethod.sigma,
        _ => LiveStackingMethod.average,
      };
}

/// EAA / outreach broadcast node.
///
/// When entered, the node arms the broadcast service (a Rust singleton
/// shared with the Dart `BroadcastService`) and immediately returns
/// success. Sibling exposure nodes inside the same `Loop` / target
/// subtree continue to capture frames; each `FrameAccepted` event on
/// the backend feeds the saved FITS into the live-stacking engine and
/// publishes the result as a JPEG on the broadcast endpoint.
///
/// The instruction itself is non-blocking — a user dropping this node
/// in front of an `ExposureNode` does not have to wait on it. Stopping
/// the sequence (or starting a new one) automatically deactivates the
/// broadcast, so a paused public outreach run cannot leak imagery into
/// the next session.
class LiveStackingNode extends SequenceNode {
  /// Operating mode: broadcast only, or also write JPEG snapshots to
  /// disk for a built-up "timelapse" record.
  final LiveStackingMode mode;

  /// Stack-combine method (average / median+rej / sigma-clipped).
  final LiveStackingMethod stackMethod;

  /// Hard cap on number of frames added to the stack. `0` = unlimited.
  /// Long public events should set this so memory does not unbounded-
  /// grow over a multi-hour outreach session.
  final int maxFramesToStack;

  /// Whether the broadcast endpoint serves requests. Off => stack
  /// builds in memory but `/api/broadcast/live-stack` returns 404.
  final bool broadcastEnabled;

  /// TCP port for the broadcast endpoints. Defaults to 8081. Must
  /// not clash with the headless API server's port (validated by
  /// [LiveStackingPortClashRule] at edit time).
  final int broadcastPort;

  /// HTTP path prefix the broadcast HTML page is served at. Defaults
  /// to `/broadcast`. Useful for vanity URLs at public events.
  final String broadcastPath;

  /// Optional shared secret. When set (non-empty), every broadcast
  /// endpoint requires `?token=…` matching this value. `null` (or
  /// empty) = public access — appropriate for outreach but the
  /// settings UI defaults to private to make public an explicit
  /// opt-in.
  final String? authToken;

  /// Optional watermark text rendered on the broadcast JPEG. Variable
  /// interpolation (Wave 4) is applied at render time so the user can
  /// write templates like `"M42 — L ${integration.hms}"`. `null`
  /// disables the watermark.
  final String? watermarkText;

  /// Output thumbnail width × height for the broadcast JPEG.
  /// Default 1280 × 720 keeps the payload phone-friendly while
  /// preserving enough detail for the EAA viewer.
  final int thumbnailWidth;
  final int thumbnailHeight;

  LiveStackingNode({
    super.id,
    super.name = 'Live Stacking',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.mode = LiveStackingMode.broadcastOnly,
    this.stackMethod = LiveStackingMethod.average,
    this.maxFramesToStack = 0,
    this.broadcastEnabled = true,
    this.broadcastPort = 8081,
    this.broadcastPath = '/broadcast',
    this.authToken,
    this.watermarkText,
    this.thumbnailWidth = 1280,
    this.thumbnailHeight = 720,
  });

  @override
  String get nodeType => 'LiveStacking';

  @override
  String get iconName => 'cast_connected';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices => const <DeviceType>{};

  /// True when the user has explicitly set a non-empty auth token.
  /// Used by the run-dashboard "Public" / "Private" badge.
  bool get isPublic => authToken == null || authToken!.isEmpty;

  /// True when a watermark template is configured.
  bool get hasWatermark =>
      watermarkText != null && watermarkText!.trim().isNotEmpty;

  @override
  LiveStackingNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    LiveStackingMode? mode,
    LiveStackingMethod? stackMethod,
    int? maxFramesToStack,
    bool? broadcastEnabled,
    int? broadcastPort,
    String? broadcastPath,
    // Use Object? sentinel so callers can clear auth_token to null
    // (the regular Dart "null means leave alone" copyWith pattern
    // cannot distinguish "leave alone" from "clear" without this).
    Object? authToken = _unset,
    Object? watermarkText = _unset,
    int? thumbnailWidth,
    int? thumbnailHeight,
  }) {
    return LiveStackingNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      mode: mode ?? this.mode,
      stackMethod: stackMethod ?? this.stackMethod,
      maxFramesToStack: maxFramesToStack ?? this.maxFramesToStack,
      broadcastEnabled: broadcastEnabled ?? this.broadcastEnabled,
      broadcastPort: broadcastPort ?? this.broadcastPort,
      broadcastPath: broadcastPath ?? this.broadcastPath,
      authToken: authToken == _unset ? this.authToken : authToken as String?,
      watermarkText: watermarkText == _unset
          ? this.watermarkText
          : watermarkText as String?,
      thumbnailWidth: thumbnailWidth ?? this.thumbnailWidth,
      thumbnailHeight: thumbnailHeight ?? this.thumbnailHeight,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        mode,
        stackMethod,
        maxFramesToStack,
        broadcastEnabled,
        broadcastPort,
        broadcastPath,
        authToken,
        watermarkText,
        thumbnailWidth,
        thumbnailHeight,
      ];
}

/// Sentinel for [LiveStackingNode.copyWith] so callers can distinguish
/// "leave unchanged" (default) from "explicitly clear" (`authToken: null`).
const Object _unset = Object();

/// Parse a duration string of the form "4h 30m", "90m", "3600s", "1.5h"
/// into seconds. Returns null for unparseable input. Used by the
/// integration-budget input on the SmartExposure properties editor.
///
/// Supported units (case-insensitive, may follow a number with or without
/// space): `s` (seconds), `m` (minutes), `h` (hours), `d` (days).
/// Multiple terms are summed: "1h 30m" → 5400. A bare number (no unit) is
/// interpreted as seconds for backwards compatibility with raw entry.
double? parseHumanDurationSecs(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // Bare number → seconds.
  final asNumber = double.tryParse(trimmed);
  if (asNumber != null) return asNumber;

  // Token scan: alternating (number, unit) pairs. Whitespace optional.
  final pattern = RegExp(r'(\d+(?:\.\d+)?)\s*([smhdSMHD])');
  final matches = pattern.allMatches(trimmed);
  if (matches.isEmpty) return null;

  double total = 0.0;
  for (final m in matches) {
    final value = double.tryParse(m.group(1) ?? '');
    final unit = m.group(2)?.toLowerCase();
    if (value == null || unit == null) return null;
    switch (unit) {
      case 's':
        total += value;
        break;
      case 'm':
        total += value * 60.0;
        break;
      case 'h':
        total += value * 3600.0;
        break;
      case 'd':
        total += value * 86400.0;
        break;
    }
  }
  return total;
}

/// Format a duration in seconds as a compact "Xh Ym" string. Used by the
/// integration-budget read-back in the properties editor and the Run
/// Dashboard's filter-integration panel.
String formatHumanDurationSecs(double secs) {
  if (secs <= 0) return '0s';
  final totalSecs = secs.round();
  final hours = totalSecs ~/ 3600;
  final minutes = (totalSecs % 3600) ~/ 60;
  final seconds = totalSecs % 60;
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  if (minutes > 0 && seconds > 0) return '${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m';
  return '${seconds}s';
}

// =============================================================================
// SEQUENCE
// =============================================================================

/// Complete sequence.
///
/// **Tree representation contract** (W1.7 refactor):
///
///   * `nodes` (a flat `Map<String, SequenceNode>`) remains the canonical
///     content store and the on-disk serialization shape. Every node carries
///     its own `childIds: List<String>` and `parentId: String?`. The on-the-
///     wire JSON (executor payload + `.nseq.json` export) is unchanged.
///
///   * `_childrenByParent` and `_parentById` are **derived** runtime indexes
///     built lazily from `nodes` on first access. They make `childrenOf(p)`,
///     `parentOf(c)`, and descendant walks O(1) per hop without scanning the
///     full node map.
///
///   * The runtime invariant is: `_childrenByParent[parentId]` is the
///     authoritative ordering of children under `parentId`, and `parentId`
///     in each node's `parentId` field matches `_parentById[node.id]`. The
///     index is built FROM `nodes[*].childIds` + `nodes[*].parentId`, so the
///     two representations are kept consistent by construction — every
///     mutation goes through `CurrentSequenceNotifier`, which produces a
///     fresh `Sequence` via `copyWith(nodes: ...)`; the new instance rebuilds
///     its indexes from the new `nodes` map.
///
///   * `orderIndex` on each node is preserved as a load-bearing persistence
///     field (Drift uses it for `ORDER BY` on load). The editor renumbers
///     `orderIndex` only within the affected parent's children list — never
///     a tree-wide rewrite — so reorder/insert/remove cost is bounded by the
///     parent's sibling count, not by the total tree size.
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

  // ---------------------------------------------------------------------
  // Derived tree indexes (lazy, cached per-Sequence-instance).
  //
  // These are NOT part of [props] / equality — they are pure functions of
  // [nodes]. Two sequences with equal `nodes` maps will have equal indexes.
  // ---------------------------------------------------------------------

  /// Maps `parentId -> ordered child IDs`. The key `null` collects orphan
  /// nodes (those whose `parentId == null`). The list ordering matches the
  /// canonical `parent.childIds` ordering; we do NOT depend on
  /// `node.orderIndex` for runtime traversal — that field is reserved for
  /// persistence/serialization round-trips.
  late final Map<String?, List<String>> _childrenByParent =
      _buildChildrenIndex();

  /// Maps `node_id -> parent_id` (with `null` for nodes whose `parentId` is
  /// null). Note: the root node has `parentId == null` and is therefore in
  /// this map with a `null` value, which is distinct from "node not found".
  late final Map<String, String?> _parentById = _buildParentIndex();

  Map<String?, List<String>> _buildChildrenIndex() {
    final index = <String?, List<String>>{};
    for (final entry in nodes.entries) {
      final node = entry.value;
      // Seed the parent's bucket from this node's `childIds`. We iterate
      // `nodes` rather than walking from a root because:
      //   * the editor occasionally constructs partially-detached nodes
      //     (e.g., during snippet inserts);
      //   * we want every node referenced by some parent.childIds to be
      //     resolvable without depending on which order keys appear in.
      // Reading `node.childIds` for the bucket keyed by `node.id` is the
      // authoritative source — `parent.childIds` is what the model has
      // always documented as canonical.
      index.putIfAbsent(node.id, () => <String>[]).addAll(node.childIds);
    }
    // Ensure every node id has a (possibly empty) bucket so `childrenOf`
    // returns `const <String>[]` for leaves without a map-miss check.
    for (final id in nodes.keys) {
      index.putIfAbsent(id, () => <String>[]);
    }
    return index;
  }

  Map<String, String?> _buildParentIndex() {
    final index = <String, String?>{};
    // Pass 1: seed from each node's own `parentId` field. This is the
    // authoritative source — the editor maintains node.parentId on every
    // structural mutation, and the database load path reconstructs it.
    for (final entry in nodes.entries) {
      index[entry.key] = entry.value.parentId;
    }
    return index;
  }

  /// Children of [parentId] in their canonical order. Returns the materialized
  /// `SequenceNode` instances (skipping any IDs that don't resolve — which is
  /// a corrupt-state condition the editor never produces but defensive code
  /// elsewhere does need to tolerate, e.g. mid-import).
  ///
  /// O(K) where K is the number of children of [parentId]. Does **not** sort
  /// by `orderIndex` — the `_childrenByParent` list is already in canonical
  /// order, matching `nodes[parentId].childIds`.
  List<SequenceNode> childrenOf(String parentId) {
    final ids = _childrenByParent[parentId];
    if (ids == null || ids.isEmpty) return const <SequenceNode>[];
    final out = <SequenceNode>[];
    for (final id in ids) {
      final n = nodes[id];
      if (n != null) out.add(n);
    }
    return out;
  }

  /// Parent ID of [nodeId], or `null` if [nodeId] is a root node OR is not
  /// in this sequence. Use [nodes.containsKey] to distinguish those cases.
  ///
  /// O(1).
  String? parentOf(String nodeId) => _parentById[nodeId];

  /// IDs of all descendants of [nodeId] in DFS pre-order (children first, then
  /// grandchildren, ...). The node itself is NOT included.
  ///
  /// Cycles cannot exist if [invariants] holds, but we guard with a visited
  /// set anyway so a corrupted import doesn't loop forever.
  List<String> descendantsOf(String nodeId) {
    if (!nodes.containsKey(nodeId)) return const <String>[];
    final out = <String>[];
    final visited = <String>{nodeId};
    void walk(String id) {
      final children = _childrenByParent[id];
      if (children == null) return;
      for (final childId in children) {
        if (!visited.add(childId)) continue;
        if (!nodes.containsKey(childId)) continue;
        out.add(childId);
        walk(childId);
      }
    }

    walk(nodeId);
    return out;
  }

  /// Verify the structural invariants of this sequence. Returns a list of
  /// human-readable violation messages; empty list means OK. Intended for
  /// debug asserts and tests — not called on every mutation in release mode
  /// because rebuilding the indexes is O(N).
  ///
  /// Invariants checked:
  ///   1. Every ID in `_childrenByParent[X]` exists in `nodes`.
  ///   2. Every ID in `_childrenByParent[X]` has `_parentById[id] == X`.
  ///   3. Every node in `nodes` has a `_parentById` entry.
  ///   4. The graph is acyclic (no node is in its own ancestry).
  ///   5. `node.childIds` matches `_childrenByParent[node.id]` (the two
  ///      tree views agree).
  List<String> invariants() {
    final issues = <String>[];

    // (3) Every node has a parent entry.
    for (final id in nodes.keys) {
      if (!_parentById.containsKey(id)) {
        issues.add('node "$id" missing from _parentById');
      }
    }

    // (1), (2), (5)
    for (final entry in _childrenByParent.entries) {
      final parent = entry.key;
      final list = entry.value;
      for (final childId in list) {
        if (!nodes.containsKey(childId)) {
          // It's legal to have an entry in _childrenByParent for a parent
          // that's no longer in nodes (orphaned bucket) only if the bucket
          // is empty; non-empty buckets pointing at missing nodes are bad.
          issues
              .add('child "$childId" of parent "$parent" not present in nodes');
          continue;
        }
        final parentOfChild = _parentById[childId];
        if (parentOfChild != parent) {
          issues
              .add('child "$childId" of "$parent" has parentId=$parentOfChild');
        }
      }
      // (5) cross-check childIds.
      if (parent != null) {
        final parentNode = nodes[parent];
        if (parentNode != null) {
          final declared = parentNode.childIds;
          if (declared.length != list.length) {
            issues.add(
                'parent "$parent" childIds length ${declared.length} != index ${list.length}');
          } else {
            for (var i = 0; i < declared.length; i++) {
              if (declared[i] != list[i]) {
                issues.add(
                    'parent "$parent" childIds[$i]=${declared[i]} != index[$i]=${list[i]}');
                break;
              }
            }
          }
        }
      }
    }

    // (4) No cycles. Walk every node's ancestry; bail when we find a
    // revisit. We bound the walk length to nodes.length so a true cycle
    // can't run forever.
    for (final id in nodes.keys) {
      var hops = 0;
      var cursor = _parentById[id];
      final seen = <String>{id};
      while (cursor != null) {
        if (!seen.add(cursor)) {
          issues.add('cycle detected at "$id" via ancestor "$cursor"');
          break;
        }
        if (++hops > nodes.length) {
          issues.add('ancestry walk for "$id" exceeded node count');
          break;
        }
        cursor = _parentById[cursor];
      }
    }

    return issues;
  }

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

  /// Get target headers (root nodes for each target).
  ///
  /// Flattens every enabled [TargetHeaderNode] in the tree regardless of
  /// nesting depth (targets may live under root, under a loop, or under any
  /// container). Sorted by `orderIndex` to keep the legacy UI ordering — the
  /// alternative (tree-walk-canonical-order) would not work for sequences
  /// where targets are spread across multiple parent containers, which the
  /// `CrossParentReorderException` test in `sequence_editor_trust_patch_test`
  /// pins as supported behavior.
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

  /// Get children of a node. See [childrenOf] for the index-backed equivalent;
  /// this is the legacy entry point kept for backward compatibility with
  /// consumers that already use `getChildren`. Both return the same list.
  List<SequenceNode> getChildren(String parentId) => childrenOf(parentId);

  /// Count all descendants of [nodeId] (children, grandchildren, ...).
  ///
  /// Returns 0 when [nodeId] does not exist or is a leaf. The node itself
  /// is **not** counted — only its subtree. Used by the UI to decide
  /// whether deleting a node warrants a confirmation dialog (e.g.,
  /// "Delete N nodes?" for non-leaf containers).
  ///
  /// Backed by `_childrenByParent` (single DFS over the parent-keyed index),
  /// so the cost is O(size-of-subtree) — no nodes outside the subtree are
  /// visited. The defensive cycle guard from the pre-W1.7 implementation is
  /// preserved as defense-in-depth against malformed import data, even
  /// though [invariants] would have rejected it.
  int countDescendants(String nodeId) => descendantsOf(nodeId).length;

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

  /// Per-node structured instruction progress detail.
  final Map<String, InstructionProgressDetail> nodeProgressStructuredDetail;

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
    this.nodeProgressStructuredDetail = const {},
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
    Map<String, InstructionProgressDetail>? nodeProgressStructuredDetail,
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
      nodeProgressStructuredDetail:
          nodeProgressStructuredDetail ?? this.nodeProgressStructuredDetail,
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
        nodeProgressStructuredDetail,
      ];
}

// =============================================================================
// Wave 7 Science — SciencePhotometryNode + transparency-adaptive support.
// =============================================================================

/// Per-frame photometric quality gates. Mirrors the Rust
/// `PhotometryQualityGates` struct one-to-one. Frames failing any gate
/// are routed to the Wave 3 Image Grading reject folder and their
/// `photometry_measurements` row is marked outlier.
class PhotometryQualityGates extends Equatable {
  /// Minimum target SNR. AAVSO research-grade default is 50.
  final double minSnr;

  /// Maximum acceptable FWHM in arcseconds. Default 5".
  final double maxFwhmArcsec;

  /// When true, frames where any reference star failed to extract are
  /// rejected.
  final bool requireAllRefsVisible;

  /// Maximum airmass. AAVSO Bright Star Monitor cut-off ≈ 2.5.
  final double maxAirmass;

  const PhotometryQualityGates({
    this.minSnr = 50.0,
    this.maxFwhmArcsec = 5.0,
    this.requireAllRefsVisible = true,
    this.maxAirmass = 2.5,
  });

  PhotometryQualityGates copyWith({
    double? minSnr,
    double? maxFwhmArcsec,
    bool? requireAllRefsVisible,
    double? maxAirmass,
  }) {
    return PhotometryQualityGates(
      minSnr: minSnr ?? this.minSnr,
      maxFwhmArcsec: maxFwhmArcsec ?? this.maxFwhmArcsec,
      requireAllRefsVisible:
          requireAllRefsVisible ?? this.requireAllRefsVisible,
      maxAirmass: maxAirmass ?? this.maxAirmass,
    );
  }

  Map<String, dynamic> toJson() => {
        'min_snr': minSnr,
        'max_fwhm_arcsec': maxFwhmArcsec,
        'require_all_refs_visible': requireAllRefsVisible,
        'max_airmass': maxAirmass,
      };

  factory PhotometryQualityGates.fromJson(Map<String, dynamic> json) {
    return PhotometryQualityGates(
      minSnr: (json['min_snr'] as num?)?.toDouble() ?? 50.0,
      maxFwhmArcsec: (json['max_fwhm_arcsec'] as num?)?.toDouble() ?? 5.0,
      requireAllRefsVisible: json['require_all_refs_visible'] as bool? ?? true,
      maxAirmass: (json['max_airmass'] as num?)?.toDouble() ?? 2.5,
    );
  }

  @override
  List<Object?> get props =>
      [minSnr, maxFwhmArcsec, requireAllRefsVisible, maxAirmass];
}

/// Standard photometric bands recognised by the Dart-side validator.
/// Matches `SciencePhotometryConfig::is_photometric_filter_name` in Rust.
const Set<String> kPhotometricFilterBands = {
  'V',
  'B',
  'R',
  'I',
  'U',
  'g',
  'r',
  'i',
  'z',
  "g'",
  "r'",
  "i'",
  "z'",
  'Clear',
  'CV',
  'CR',
  'CB',
};

bool isPhotometricFilterBand(String name) =>
    kPhotometricFilterBands.contains(name.trim());

/// Cadence-enforced photometric capture node. Mirrors the Rust
/// `NodeType::SciencePhotometry(SciencePhotometryConfig)` variant.
///
/// The node delegates per-frame capture to the standard
/// `TakeExposure` pipeline and layers in per-frame photometric
/// reduction (instrumental + differential magnitude) + cadence
/// tracking. Frames failing the configured quality gates are routed
/// to the Wave 3 Image Grading reject path.
class SciencePhotometryNode extends SequenceNode {
  /// Target object identifier (catalogue ID, e.g. "V0376 Per").
  final String targetDesignation;

  /// Catalogue IDs of reference stars used for differential photometry.
  /// Empty when [applyDifferential] is false.
  final List<String> referenceStars;

  /// Maximum inter-frame start-to-start gap (seconds) before a
  /// cadence-broken warning is emitted. 0.0 disables the check.
  /// Default 2.0s — matches the brief's V0376 Per example.
  final double maxCadenceGapSecs;

  /// Photometric filter (one of [kPhotometricFilterBands]).
  final String filter;

  /// Per-frame exposure duration in seconds.
  final double exposureSecs;

  /// Number of frames to capture in the burst.
  final int count;

  /// When true, the runtime extracts the target's instrumental
  /// magnitude from each captured frame in real time and writes a row
  /// to `photometry_measurements`.
  final bool reduceLive;

  /// When true (and [reduceLive] is true), additionally computes the
  /// differential magnitude against [referenceStars].
  final bool applyDifferential;

  /// Per-frame quality gates.
  final PhotometryQualityGates quality;

  /// Optional gain override.
  final int? gain;

  /// Optional offset override.
  final int? offset;

  /// Binning.
  final BinningMode binning;

  SciencePhotometryNode({
    super.id,
    super.name = 'Science Photometry',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    this.targetDesignation = '',
    this.referenceStars = const [],
    this.maxCadenceGapSecs = 2.0,
    this.filter = 'Clear',
    this.exposureSecs = 60.0,
    this.count = 60,
    this.reduceLive = true,
    this.applyDifferential = true,
    this.quality = const PhotometryQualityGates(),
    this.gain,
    this.offset,
    this.binning = BinningMode.one,
  });

  @override
  String get nodeType => 'SciencePhotometry';

  @override
  String get iconName => 'analytics';

  @override
  NodeCategory get category => NodeCategory.instruction;

  @override
  Set<DeviceType> get requiredDevices =>
      {DeviceType.camera, DeviceType.filterWheel};

  bool get isPhotometricFilter => isPhotometricFilterBand(filter);

  /// True when the configured cadence is structurally invalid. The
  /// runtime computes the start-to-start gap and compares it against
  /// `exposure_secs + max_cadence_gap_secs`, so the only nonsense
  /// values are negative or NaN. We treat `< 0` as impossible.
  bool get hasImpossibleCadence => maxCadenceGapSecs < 0.0;

  @override
  SciencePhotometryNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? targetDesignation,
    List<String>? referenceStars,
    double? maxCadenceGapSecs,
    String? filter,
    double? exposureSecs,
    int? count,
    bool? reduceLive,
    bool? applyDifferential,
    PhotometryQualityGates? quality,
    Object? gain = _sentinel,
    Object? offset = _sentinel,
    BinningMode? binning,
  }) {
    return SciencePhotometryNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      targetDesignation: targetDesignation ?? this.targetDesignation,
      referenceStars: referenceStars ?? this.referenceStars,
      maxCadenceGapSecs: maxCadenceGapSecs ?? this.maxCadenceGapSecs,
      filter: filter ?? this.filter,
      exposureSecs: exposureSecs ?? this.exposureSecs,
      count: count ?? this.count,
      reduceLive: reduceLive ?? this.reduceLive,
      applyDifferential: applyDifferential ?? this.applyDifferential,
      quality: quality ?? this.quality,
      gain: identical(gain, _sentinel) ? this.gain : gain as int?,
      offset: identical(offset, _sentinel) ? this.offset : offset as int?,
      binning: binning ?? this.binning,
    );
  }

  /// Serialise to the JSON shape expected by the Rust
  /// `SciencePhotometryConfig` (snake_case keys, externally tagged).
  Map<String, dynamic> toRustConfigJson() => {
        'target_designation': targetDesignation,
        'reference_stars': referenceStars,
        'max_cadence_gap_secs': maxCadenceGapSecs,
        'filter': filter,
        'exposure_secs': exposureSecs,
        'count': count,
        'reduce_live': reduceLive,
        'apply_differential': applyDifferential,
        'quality': quality.toJson(),
        'gain': gain,
        'offset': offset,
        'binning': _binningModeToRustString(binning),
      };

  factory SciencePhotometryNode.fromRustConfigJson(
    Map<String, dynamic> json, {
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
  }) {
    final refs = (json['reference_stars'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];
    final qualityJson = json['quality'];
    final quality = qualityJson is Map<String, dynamic>
        ? PhotometryQualityGates.fromJson(qualityJson)
        : const PhotometryQualityGates();
    return SciencePhotometryNode(
      id: id,
      name: name ?? 'Science Photometry',
      isEnabled: isEnabled ?? true,
      childIds: childIds ?? const [],
      parentId: parentId,
      orderIndex: orderIndex ?? 0,
      comment: comment,
      targetDesignation: (json['target_designation'] as String?) ?? '',
      referenceStars: refs,
      maxCadenceGapSecs:
          (json['max_cadence_gap_secs'] as num?)?.toDouble() ?? 2.0,
      filter: (json['filter'] as String?) ?? 'Clear',
      exposureSecs: (json['exposure_secs'] as num?)?.toDouble() ?? 60.0,
      count: (json['count'] as num?)?.toInt() ?? 60,
      reduceLive: json['reduce_live'] as bool? ?? true,
      applyDifferential: json['apply_differential'] as bool? ?? true,
      quality: quality,
      gain: (json['gain'] as num?)?.toInt(),
      offset: (json['offset'] as num?)?.toInt(),
      binning: _rustStringToBinningMode(json['binning'] as String?),
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        targetDesignation,
        referenceStars,
        maxCadenceGapSecs,
        filter,
        exposureSecs,
        count,
        reduceLive,
        applyDifferential,
        quality,
        gain,
        offset,
        binning,
      ];
}

/// Operator-configured backup plan consulted by
/// `RecoveryActionType.switchTargetOrFilter`. Mirrors the Rust
/// `TransparencyBackupPlan` struct.
///
/// Either [backupFilter] or [backupTargetId] may be set independently
/// (or both). When both are null the recovery action falls back to
/// `PauseAndWaitForClear` rather than silently no-oping.
class TransparencyBackupPlan extends Equatable {
  /// Filter to switch to when transparency drops (e.g. `"Lum"`).
  final String? backupFilter;

  /// Sequence node id to skip to when transparency drops.
  final String? backupTargetId;

  /// Optional human-readable description surfaced in the UI / logs.
  final String? description;

  const TransparencyBackupPlan({
    this.backupFilter,
    this.backupTargetId,
    this.description,
  });

  bool get isEmpty => backupFilter == null && backupTargetId == null;

  TransparencyBackupPlan copyWith({
    Object? backupFilter = _sentinel,
    Object? backupTargetId = _sentinel,
    Object? description = _sentinel,
  }) {
    return TransparencyBackupPlan(
      backupFilter: identical(backupFilter, _sentinel)
          ? this.backupFilter
          : backupFilter as String?,
      backupTargetId: identical(backupTargetId, _sentinel)
          ? this.backupTargetId
          : backupTargetId as String?,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'backup_filter': backupFilter,
        'backup_target_id': backupTargetId,
        'description': description,
      };

  factory TransparencyBackupPlan.fromJson(Map<String, dynamic> json) {
    return TransparencyBackupPlan(
      backupFilter: json['backup_filter'] as String?,
      backupTargetId: json['backup_target_id'] as String?,
      description: json['description'] as String?,
    );
  }

  @override
  List<Object?> get props => [backupFilter, backupTargetId, description];
}

/// Audit §11 — Plugin-contributed sequence instruction.
///
/// Holds the metadata required to identify a plugin-authored node in the
/// sequence tree (`pluginId`, `nodeTypeId`) and the opaque plugin-authored
/// JSON config that the Dart-side `PluginNodeExecutor` will pass to
/// `PluginSequenceNode.execute` at runtime. The Rust executor only forwards
/// these fields verbatim — every interpretation of `configJson` happens on
/// the Dart side.
///
/// The node is a *leaf*: container behaviour is owned by the plugin itself
/// (which can fan out internally via the plugin event bus / nested executor
/// hooks), so the editor refuses child drops.
///
/// Serialisation contract (Rust `NodeType::PluginNode`):
///
/// ```json
/// {
///   "type": "PluginNode",
///   "plugin_id": "<pluginId>",
///   "node_type_id": "<nodeTypeId>",
///   "config_json": "<configJson>",
///   "display_name": "<name>",
///   "timeout_secs": <timeoutSecs?>
/// }
/// ```
class PluginInstructionNode extends SequenceNode {
  /// Stable plugin identifier the host registered the owning plugin under
  /// (e.g. `com.example.pushover`).
  final String pluginId;

  /// Stable per-plugin node-type id (e.g. `pushover.notify`). Combined with
  /// [pluginId] this is the composite registry key the Dart-side executor
  /// uses to look up the plugin's `SequenceNodeDefinition`.
  final String nodeTypeId;

  /// Opaque JSON blob the plugin author owns. The dispatcher passes this
  /// through `jsonDecode` and hands the resulting map to
  /// `PluginSequenceNode.execute(params)`. Defaults to `'{}'` so a
  /// freshly-dropped palette node round-trips through `jsonDecode` cleanly.
  final String configJson;

  /// Optional per-node timeout override (seconds). `null` falls back to the
  /// Rust executor default (600s). `0` is treated the same as `null` by the
  /// Rust side rather than as a zero-second fail-now.
  final int? timeoutSecs;

  /// Human-readable plugin name surfaced in logs / properties panel. Mirrors
  /// the [pluginId] registration; pinned to the node so importing a
  /// sequence whose owning plugin is currently unavailable still shows a
  /// sensible label.
  final String pluginName;

  /// Icon hint forwarded from the plugin's `SequenceNodeDefinition`. The
  /// palette widget falls back to the generic puzzle-piece icon when the
  /// hint is unknown.
  final String iconHint;

  PluginInstructionNode({
    super.id,
    super.name = 'Plugin Node',
    super.isEnabled,
    super.childIds = const [],
    super.parentId,
    super.orderIndex,
    super.comment,
    required this.pluginId,
    required this.nodeTypeId,
    this.configJson = '{}',
    this.timeoutSecs,
    this.pluginName = '',
    this.iconHint = 'puzzle',
  });

  @override
  String get nodeType => 'PluginNode';

  @override
  String get iconName => iconHint;

  @override
  NodeCategory get category => NodeCategory.instruction;

  /// Composite registry key, mirroring `PluginNodeRegistration.composeKey`.
  /// Lives here so the executor can build the lookup key without depending
  /// on the plugins package.
  String get registrationKey => '$pluginId::$nodeTypeId';

  @override
  PluginInstructionNode copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    List<String>? childIds,
    String? parentId,
    int? orderIndex,
    String? comment,
    String? pluginId,
    String? nodeTypeId,
    String? configJson,
    int? timeoutSecs,
    String? pluginName,
    String? iconHint,
  }) {
    return PluginInstructionNode(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      childIds: childIds ?? this.childIds,
      parentId: parentId ?? this.parentId,
      orderIndex: orderIndex ?? this.orderIndex,
      comment: comment ?? this.comment,
      pluginId: pluginId ?? this.pluginId,
      nodeTypeId: nodeTypeId ?? this.nodeTypeId,
      configJson: configJson ?? this.configJson,
      timeoutSecs: timeoutSecs ?? this.timeoutSecs,
      pluginName: pluginName ?? this.pluginName,
      iconHint: iconHint ?? this.iconHint,
    );
  }

  @override
  List<Object?> get props => [
        ...super.props,
        pluginId,
        nodeTypeId,
        configJson,
        timeoutSecs,
        pluginName,
        iconHint,
      ];
}
