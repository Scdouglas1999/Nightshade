import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sequence/sequence_models.dart';
// Wave 5 Agent 2: sky-brightness adaptive exposure validation rules.
import 'rules/adaptive_exposure_rules.dart';
// Wave 7 Agent 3: per-frame defect-map validation rules.
import 'rules/defect_map_rules.dart';
import 'rules/disk_space_rules.dart';
import 'rules/equipment_rules.dart';
import 'rules/exposure_rules.dart';
import 'rules/filter_rules.dart';
import 'rules/logic_node_rules.dart';
// Wave 5 Agent 3 — Pre-flight checks (darks + equipment health + optical train).
import 'rules/preflight_rules.dart';
import 'rules/settings_rules.dart';
// Wave 7 Agent 2: LiveStacking node validation rules.
import 'rules/live_stacking_rules.dart';
// Wave 7 Science: SciencePhotometry node validation rules.
import 'rules/science_photometry_rules.dart';
// Wave 3 Agent 2: SmartExposure node validation rules.
import 'rules/smart_exposure_rules.dart';
import 'rules/structure_rules.dart';
import 'rules/target_rules.dart';
// Wave 3 Agent 1: TargetScheduler node validation rules.
import 'rules/target_scheduler_rules.dart';
import 'rules/timing_rules.dart';

// =============================================================================
// UNIFIED SEQUENCE VALIDATION
// =============================================================================
//
// This file is the single source of truth for sequence validation. There was
// historically a second engine inside `preflight_validation_dialog.dart` (the
// "rich" model with category/resolutionHint, three severity levels) and a
// third inside `live_validation_provider.dart`. Both have been folded into
// the rule registry below.
//
//   * Pure structural rules are sync and live under `rules/`.
//   * Ref-aware rules (equipment connection, filter wheel content, app
//     settings, disk space) are also under `rules/` and take a
//     [ValidationContext].
//
// Live in-tree validation (the per-node coloured border + counts in the tree
// header) and the pre-flight dialog now both call into [SequenceValidator]
// here. Add a new rule by adding it to [defaultSequenceValidators] /
// [defaultRefAwareSequenceValidators]. Don't fork the engine.

/// Severity of a validation issue. Three levels:
///
///   * [error] — blocks sequence execution. The pre-flight dialog refuses to
///     start the sequence.
///   * [warning] — sequence will run but something is suspicious or could
///     misbehave at runtime.
///   * [info] — informational; no action required, but the user might want
///     to know.
enum ValidationSeverity { error, warning, info }

/// Coarse category used by the dialog UI to group issues. Adding a category
/// requires updating UI code that switches on it.
enum ValidationCategory {
  structure,
  targets,
  exposures,
  equipment,
  timing,
  settings,
  diskSpace,
  // Wave 5 Agent 3 — Pre-flight checks. New categories so the pre-flight
  // dialog can group these in their own collapsible sections instead of
  // mixing them with the structural / equipment-connection issues.
  /// Dark library coverage (matching dark frames for the sequence's
  /// (gain, offset, temp, duration, binning) combinations).
  darkLibrary,

  /// Long-term equipment health (USB stability, focuser range, mount
  /// alignment freshness, time sync, cooler delta, filter wheel
  /// homing).
  equipmentHealth,

  /// Optical-train drift / pre-session calibration comparison.
  opticalTrain,
}

/// Display label for [ValidationCategory] — used by the dialog UI.
extension ValidationCategoryLabel on ValidationCategory {
  String get label {
    switch (this) {
      case ValidationCategory.structure:
        return 'Structure';
      case ValidationCategory.targets:
        return 'Targets';
      case ValidationCategory.exposures:
        return 'Imaging';
      case ValidationCategory.equipment:
        return 'Equipment';
      case ValidationCategory.timing:
        return 'Timing';
      case ValidationCategory.settings:
        return 'Settings';
      case ValidationCategory.diskSpace:
        return 'Storage';
      case ValidationCategory.darkLibrary:
        return 'Dark Library';
      case ValidationCategory.equipmentHealth:
        return 'Equipment Health';
      case ValidationCategory.opticalTrain:
        return 'Optical Train';
    }
  }
}

/// A single validation finding.
///
/// Plain immutable value class with const constructor + value equality. We
/// intentionally do not use freezed here — the equivalent value classes in
/// the sequence subsystem ([SequenceProgress] etc.) are also hand-rolled,
/// and the additional codegen would not buy us anything.
class ValidationIssue {
  final ValidationSeverity severity;
  final ValidationCategory category;
  final String title;
  final String description;

  /// Optional concrete hint the user can act on. Surfaced beneath the
  /// description in the pre-flight dialog.
  final String? resolutionHint;

  /// Optional id of the offending node. When present, the tree paints a
  /// matching coloured border / badge on that node.
  final String? affectedNodeId;

  /// Optional stable machine-readable code (e.g.
  /// `image_output_path_not_configured`). Set on issues that REST
  /// clients need to programmatically branch on so the wire payload
  /// doesn't depend on the human-readable `title` text.
  final String? code;

  const ValidationIssue({
    required this.severity,
    required this.category,
    required this.title,
    required this.description,
    this.resolutionHint,
    this.affectedNodeId,
    this.code,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationIssue &&
          runtimeType == other.runtimeType &&
          severity == other.severity &&
          category == other.category &&
          title == other.title &&
          description == other.description &&
          resolutionHint == other.resolutionHint &&
          affectedNodeId == other.affectedNodeId &&
          code == other.code;

  @override
  int get hashCode => Object.hash(
        severity,
        category,
        title,
        description,
        resolutionHint,
        affectedNodeId,
        code,
      );

  @override
  String toString() =>
      'ValidationIssue($severity, $category, "$title"${affectedNodeId != null ? ", node=$affectedNodeId" : ""}${code != null ? ", code=$code" : ""})';
}

/// Aggregated result of running all validators against a sequence.
class ValidationResult {
  final List<ValidationIssue> issues;
  final DateTime validatedAt;

  const ValidationResult({
    required this.issues,
    required this.validatedAt,
  });

  factory ValidationResult.empty() => ValidationResult(
        issues: const [],
        validatedAt: DateTime.now(),
      );

  bool get hasErrors =>
      issues.any((i) => i.severity == ValidationSeverity.error);
  bool get hasWarnings =>
      issues.any((i) => i.severity == ValidationSeverity.warning);
  bool get hasInfo => issues.any((i) => i.severity == ValidationSeverity.info);

  /// Sequence may start iff there are no errors.
  bool get isValid => !hasErrors;

  int get errorCount =>
      issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount =>
      issues.where((i) => i.severity == ValidationSeverity.warning).length;
  int get infoCount =>
      issues.where((i) => i.severity == ValidationSeverity.info).length;

  int get totalCount => issues.length;

  /// Returns issues grouped by `affectedNodeId`. Issues with a null
  /// affectedNodeId are not included.
  Map<String, List<ValidationIssue>> get issuesByNodeId {
    final byNode = <String, List<ValidationIssue>>{};
    for (final issue in issues) {
      final id = issue.affectedNodeId;
      if (id != null) {
        byNode.putIfAbsent(id, () => <ValidationIssue>[]).add(issue);
      }
    }
    return byNode;
  }

  /// Worst severity (error > warning > info) attached to a given node, or
  /// null if the node has no issues.
  ValidationSeverity? worstSeverityForNode(String nodeId) {
    final nodeIssues = issuesByNodeId[nodeId];
    if (nodeIssues == null || nodeIssues.isEmpty) return null;
    if (nodeIssues.any((i) => i.severity == ValidationSeverity.error)) {
      return ValidationSeverity.error;
    }
    if (nodeIssues.any((i) => i.severity == ValidationSeverity.warning)) {
      return ValidationSeverity.warning;
    }
    return ValidationSeverity.info;
  }
}

/// Context passed to ref-aware validators. Carries the Riverpod `Ref` so
/// rules can `read` equipment state / settings without dragging Riverpod
/// types into the rule constructors.
class ValidationContext {
  final Ref ref;
  const ValidationContext(this.ref);
}

/// A single composable validator that knows how to check one specific class
/// of problem. Implementations should be small and grep-able — one rule per
/// class. Synchronous; rules needing async data should resolve it via
/// [ValidationContext.ref.read] of an already-loaded provider (the disk-space
/// rule is the lone async exception and implements [AsyncSequenceValidator]).
abstract class SequenceValidator {
  /// Stable, human-readable name. Used by debugging / logs and in test
  /// failure messages.
  String get name;

  /// Run this rule against a sequence. Implementations MUST NOT return null;
  /// return an empty list if the rule is clean. Implementations must not
  /// silently swallow missing context — if data is unavailable, emit an
  /// `info` severity issue explaining that the check could not run.
  List<ValidationIssue> validate(Sequence sequence);
}

/// Variant of [SequenceValidator] that needs `Ref` to read providers (e.g.
/// equipment connection state). Always pass a [ValidationContext].
abstract class RefAwareSequenceValidator {
  String get name;

  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx);
}

/// Variant that does async I/O (disk-space queries currently). Kept separate
/// so the live in-tree validator can skip async checks and stay sync.
abstract class AsyncSequenceValidator {
  String get name;

  Future<List<ValidationIssue>> validate(
      Sequence sequence, ValidationContext ctx);
}

/// The full set of pure structural validators. Order is preserved in the
/// output.
final List<SequenceValidator> defaultSequenceValidators =
    List<SequenceValidator>.unmodifiable(<SequenceValidator>[
  EmptySequenceRule(),
  MissingRootNodeRule(),
  OrphanedNodesRule(),
  EmptyContainerRule(),
  TargetCoordinatesRule(),
  EmptyTargetRule(),
  LowAltitudeLimitRule(),
  // Wave 3 Agent 3 — per-target integration budget validators.
  IntegrationBudgetEmptyRule(),
  IntegrationBudgetRatioZeroSumRule(),
  IntegrationBudgetRatioWithoutTotalRule(),
  // Wave 4 — per-target altitude/time crossing validators. The
  // ImpossibleAltitude rule needs an observer latitude to be useful; we
  // wire it up below in `sequenceValidatorsFor(latitude)` if/when the
  // caller has one. The structural rules (empty compound,
  // start/end contradiction) work without an observer.
  TargetTriggerEmptyCompoundRule(),
  TargetTriggerStartEndContradictionRule(),
  NoTargetForExposuresRule(),
  ExposureParamsRule(),
  HighBinningRule(),
  NoExposuresRule(),
  LongTotalIntegrationRule(),
  UnboundedLoopRule(),
  SlewCoordinatesRule(),
  WaitTimePastRule(),
  LoopEndTimePastRule(),
  // Logic-node-specific rules (Recovery / Parallel / Conditional).
  RecoveryNodeConfigRule(),
  // Wave 5 Agent 4 — cloud-motion-aware trigger config validation.
  CloudTriggerConfigRule(),
  ParallelNodeRequiredSuccessesRule(),
  ConditionalNodeEmptyBranchRule(),
  LoopUnreachableTerminationRule(),
  // Wave 3 Agent 2: SmartExposure validation.
  SmartExposureEmptyPlansRule(),
  SmartExposureNegativeCountRule(),
  // Wave 7 Science: SciencePhotometry validation.
  SciencePhotometryFilterRule(),
  SciencePhotometryReferenceStarsEmptyRule(),
  SciencePhotometryCadenceRule(),
  // Wave 7 Agent 2: LiveStacking node validation.
  LiveStackingNoExposureRule(),
  LiveStackingPortClashRule(),
  // Wave 3 Agent 1: TargetScheduler validation.
  TargetSchedulerNoChildrenRule(),
  TargetSchedulerNonTargetChildRule(),
  TargetSchedulerWeightsRule(),
  // Wave 5 Agent 2: Sky-brightness adaptive exposure validation.
  AdaptiveExposureBoundsRule(),
  AdaptiveExposureNoFilterEnabledRule(),
  AdaptiveExposureNominalOutOfBoundsRule(),
]);

/// The full set of ref-aware validators (read providers but no I/O).
final List<RefAwareSequenceValidator> defaultRefAwareSequenceValidators =
    List<RefAwareSequenceValidator>.unmodifiable(<RefAwareSequenceValidator>[
  EquipmentConnectionRule(),
  RotatorRotationConflictRule(),
  FilterInWheelRule(),
  ImageOutputPathRule(),
  DefaultSequenceNameRule(),
  LongEstimatedDurationRule(),
  MeridianFlipTriggerRule(),
  // Wave 3 Agent 2: SmartExposure needs a filter wheel.
  SmartExposureFilterWheelMissingRule(),
  // Audit C6: every SmartExposure row's filterName must match a filter
  // configured in the active equipment profile.
  SmartExposureFilterUnknownRule(),
  // Wave 5 Agent 3 — Pre-flight equipment-health checks (synchronous —
  // they only read providers, no network / disk I/O).
  UsbStabilityRule(),
  FocuserRangeRule(),
  PolarAlignmentFreshnessRule(),
  CoolerDeltaRule(),
  FilterWheelHomingRule(),
  OpticalTrainPreflightRule(),
  // Wave 7 Agent 3 — defect-map calibration check. Warns when the user
  // enabled auto-apply but no map exists for the current camera/bucket.
  DefectMapAppliedButCalibrationOffRule(),
]);

/// The full set of async validators (perform I/O — disk space).
final List<AsyncSequenceValidator> defaultAsyncSequenceValidators =
    List<AsyncSequenceValidator>.unmodifiable(<AsyncSequenceValidator>[
  DiskSpaceProjectionRule(),
  // Wave 5 Agent 3 — Pre-flight async checks (query dark library DAO,
  // NTP). Live in the async tier so the live in-tree validator (which
  // runs on every keystroke) doesn't trigger them.
  DarkLibraryCoverageRule(),
  HistoryDrivenQualityRule(),
  TimeSyncRule(),
]);

/// Provider that exposes the canonical validator. UI / providers consume
/// this — they should not new up [SequenceValidator] directly except in
/// tests.
final sequenceValidatorProvider =
    Provider.autoDispose<SequenceValidatorService>((ref) {
  return SequenceValidatorService(
    ref: ref,
    syncRules: defaultSequenceValidators,
    refAwareRules: defaultRefAwareSequenceValidators,
    asyncRules: defaultAsyncSequenceValidators,
  );
});

/// Service that runs all registered validators against a sequence.
///
/// Has two modes:
///   * [validateSync] — runs only the pure structural and ref-aware rules.
///     Used by the live in-tree validation provider where we don't want
///     async work on every keystroke.
///   * [validate] — runs the full set including disk-space (async).
///     Used by the pre-flight dialog before the sequence starts.
class SequenceValidatorService {
  final Ref _ref;
  final List<SequenceValidator> _syncRules;
  final List<RefAwareSequenceValidator> _refAwareRules;
  final List<AsyncSequenceValidator> _asyncRules;

  SequenceValidatorService({
    required Ref ref,
    required List<SequenceValidator> syncRules,
    required List<RefAwareSequenceValidator> refAwareRules,
    required List<AsyncSequenceValidator> asyncRules,
  })  : _ref = ref,
        _syncRules = syncRules,
        _refAwareRules = refAwareRules,
        _asyncRules = asyncRules;

  /// Runs only synchronous rules. Safe to call from non-async UI paths.
  ValidationResult validateSync(Sequence sequence) {
    final issues = <ValidationIssue>[];
    final ctx = ValidationContext(_ref);
    for (final rule in _syncRules) {
      issues.addAll(rule.validate(sequence));
    }
    for (final rule in _refAwareRules) {
      issues.addAll(rule.validate(sequence, ctx));
    }
    return ValidationResult(issues: issues, validatedAt: DateTime.now());
  }

  /// Runs the full validator stack including async rules (disk space).
  Future<ValidationResult> validate(Sequence sequence) async {
    final issues = <ValidationIssue>[];
    final ctx = ValidationContext(_ref);
    for (final rule in _syncRules) {
      issues.addAll(rule.validate(sequence));
    }
    for (final rule in _refAwareRules) {
      issues.addAll(rule.validate(sequence, ctx));
    }
    for (final rule in _asyncRules) {
      issues.addAll(await rule.validate(sequence, ctx));
    }
    return ValidationResult(issues: issues, validatedAt: DateTime.now());
  }
}

/// Convenience top-level function for the pure structural validators only.
///
/// Kept for callers that have no `Ref` (e.g. the sequence executor's
/// `start()` pre-check, which already executes inside Riverpod but needed a
/// way to validate before paying for equipment lookups). For full
/// validation including equipment / disk space, depend on
/// [sequenceValidatorProvider] instead.
List<ValidationIssue> validateSequence(Sequence sequence) {
  final issues = <ValidationIssue>[];
  for (final rule in defaultSequenceValidators) {
    issues.addAll(rule.validate(sequence));
  }
  return issues;
}

/// Audit C3: typed exception thrown by start paths (executor.start(),
/// sequence_action_service.start(), the headless POST /sequencer/start
/// handler) when pre-flight validation finds at least one
/// [ValidationSeverity.error] issue.
///
/// Carries the full [ValidationResult] so callers can surface ALL findings
/// to the user instead of the historical "first error wins" `Exception`.
/// CLAUDE.md mandate: errors are a feature; silent truncation of additional
/// errors is a bug.
class SequenceValidationException implements Exception {
  /// Complete validation result. Includes errors, warnings, and info-level
  /// issues. Callers should typically only block on `result.errorCount`.
  final ValidationResult result;

  const SequenceValidationException(this.result);

  /// All blocking issues (severity == error). Convenience accessor.
  List<ValidationIssue> get errors => result.issues
      .where((i) => i.severity == ValidationSeverity.error)
      .toList(growable: false);

  /// Concise one-line summary suitable for a snackbar / log line. Includes
  /// the count and the title of every error (joined with `; `) so callers
  /// that simply `print(e)` still surface every blocking finding.
  @override
  String toString() {
    final errs = errors;
    if (errs.isEmpty) {
      // Defensive: callers should not throw this without errors, but if
      // they do we still produce a useful string instead of an empty one.
      return 'SequenceValidationException(no errors)';
    }
    final titles = errs.map((e) => e.title).join('; ');
    return 'Cannot start sequence: ${errs.length} validation '
        '${errs.length == 1 ? 'error' : 'errors'}: $titles';
  }

  /// Structured form for the headless API / remote callers. Mirrors the
  /// shape of the in-app pre-flight dialog so a remote dashboard can
  /// render the same UI as the desktop.
  Map<String, Object?> toJsonBody() => {
        'code': 'sequence_validation_failed',
        'message': toString(),
        'errorCount': result.errorCount,
        'warningCount': result.warningCount,
        'infoCount': result.infoCount,
        'issues': result.issues
            .map((i) => {
                  'severity': i.severity.name,
                  'category': i.category.name,
                  'title': i.title,
                  'description': i.description,
                  if (i.resolutionHint != null)
                    'resolutionHint': i.resolutionHint,
                  if (i.affectedNodeId != null)
                    'affectedNodeId': i.affectedNodeId,
                  if (i.code != null) 'code': i.code,
                })
            .toList(),
      };
}

/// True for node types that own a child list (Target/Loop/Parallel/Conditional/
/// Recovery/InstructionSet). Used by validation rules to flag empty
/// containers and by editor logic that decides where to attach new nodes.
///
/// `SequenceNode` is sealed, so every concrete subtype must be classified
/// below. Adding a new node type will produce a compile-time error here
/// instead of silently defaulting to "not a container".
bool isContainerNode(SequenceNode node) {
  return switch (node) {
    TargetHeaderNode _ ||
    LoopNode _ ||
    ParallelNode _ ||
    ConditionalNode _ ||
    RecoveryNode _ ||
    InstructionSetNode _ ||
    // Wave 3 Agent 1: TargetScheduler holds child target headers and picks
    // among them at runtime.
    TargetSchedulerNode _ =>
      true,
    // Leaf nodes (instructions / triggers) do not own children
    ExposureNode _ ||
    SlewNode _ ||
    CenterNode _ ||
    AutofocusNode _ ||
    DitherNode _ ||
    StartGuidingNode _ ||
    StopGuidingNode _ ||
    FilterChangeNode _ ||
    CoolCameraNode _ ||
    WarmCameraNode _ ||
    RotatorNode _ ||
    ParkNode _ ||
    UnparkNode _ ||
    WaitTimeNode _ ||
    DelayNode _ ||
    NotificationNode _ ||
    ScriptNode _ ||
    MeridianFlipNode _ ||
    OpenDomeNode _ ||
    CloseDomeNode _ ||
    ParkDomeNode _ ||
    PolarAlignmentNode _ ||
    OpenCoverNode _ ||
    CloseCoverNode _ ||
    CalibratorOnNode _ ||
    CalibratorOffNode _ ||
    // Wave 3 Agent 2: SmartExposure — leaf instruction (per-filter
    // behaviour is encoded in `plans`, no children).
    SmartExposureNode _ ||
    // Wave 7 Agent 2: LiveStacking — leaf side-effect instruction.
    LiveStackingNode _ ||
    // Wave 7 Science: SciencePhotometry — leaf instruction.
    SciencePhotometryNode _ ||
    // Audit §11 — plugin-contributed instruction. Leaf.
    PluginInstructionNode _ =>
      false,
  };
}
