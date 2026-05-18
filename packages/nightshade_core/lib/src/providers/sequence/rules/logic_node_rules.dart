import '../../../models/sequence/sequence_models.dart';
import '../sequence_validation.dart';

// =============================================================================
// LOGIC-NODE RULES
// =============================================================================
//
// Rules dedicated to the four "logic" node types (Recovery / Parallel /
// Conditional). EmptyContainerRule in `structure_rules.dart` covers the
// generic "container has no children" case; these rules look at the
// *type-specific* configuration each node carries that can make the node
// run-broken even with children present.
//
// Each rule emits one well-scoped issue type with `affectedNodeId` set so
// the tree paints a coloured border on the offending node.

/// Errors out when a [RecoveryNode] is misconfigured for runtime.
///
/// Two failure modes:
///   1. No [TriggerType] set — there is nothing to trigger the recovery
///      action, so the node can never fire. (Distinct from the executor's
///      missing-trigger fallback: the executor used to silently treat an
///      unset trigger as "never trigger", hiding the misconfiguration.)
///   2. [RecoveryActionType.customBranch] selected but the node has no
///      child branch — the executor would have nothing to execute when the
///      trigger fires.
///
/// Both fire as ERROR severity because the node is structurally broken,
/// not just suboptimal.
class RecoveryNodeConfigRule implements SequenceValidator {
  @override
  String get name => 'RecoveryNodeConfig';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! RecoveryNode) continue;

      if (node.triggerType == null) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.structure,
          title: 'Recovery Has No Trigger',
          description:
              'Recovery node "${node.name}" has no trigger configured. '
              'It will never fire.',
          affectedNodeId: node.id,
          resolutionHint:
              'Set a trigger type (HFR degraded, guiding failed, meridian '
              'flip, etc.) in the node properties.',
        ));
      }

      if (node.recoveryAction == RecoveryActionType.customBranch &&
          node.childIds.isEmpty) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.structure,
          title: 'Custom Branch Has No Children',
          description:
              'Recovery node "${node.name}" is set to "custom branch" but '
              'has no child nodes to execute when the trigger fires.',
          affectedNodeId: node.id,
          resolutionHint:
              'Add child nodes describing the recovery sequence, or change '
              'the recovery action to a built-in (Retry, Pause, etc.).',
        ));
      }
    }
    return issues;
  }
}

/// Errors out when a [ParallelNode.requiredSuccesses] exceeds the number
/// of children. The node would await N successes from fewer-than-N
/// branches; it can never succeed.
///
/// Null `requiredSuccesses` is treated as "all children must succeed" by
/// the executor and is fine. Zero is allowed (fire-and-forget).
class ParallelNodeRequiredSuccessesRule implements SequenceValidator {
  @override
  String get name => 'ParallelNodeRequiredSuccesses';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! ParallelNode) continue;
      final required = node.requiredSuccesses;
      if (required == null) continue;
      if (required > node.childIds.length) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.structure,
          title: 'Parallel Requires Too Many Successes',
          description:
              'Parallel node "${node.name}" requires $required successful '
              'branches but only has ${node.childIds.length}. It cannot '
              'succeed.',
          affectedNodeId: node.id,
          resolutionHint:
              'Lower the required successes count or add more child '
              'branches.',
        ));
      }
    }
    return issues;
  }
}

/// Warns when a [ConditionalNode] has no children to execute. The
/// `EmptyContainerRule` already covers the generic "empty container"
/// warning, but the conditional-specific phrasing makes the audit hit
/// easier to act on: "the gate is fine but there's nothing behind it".
///
/// Why warning, not error: an empty conditional is a no-op rather than
/// runtime broken — useful only as a placeholder during in-progress
/// edits, but not a reason to block execution.
class ConditionalNodeEmptyBranchRule implements SequenceValidator {
  @override
  String get name => 'ConditionalNodeEmptyBranch';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! ConditionalNode) continue;
      if (node.childIds.isNotEmpty) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.structure,
        title: 'Conditional Has No Branch',
        description:
            'Conditional "${node.name}" has no child nodes. It will '
            'evaluate its condition but never execute anything.',
        affectedNodeId: node.id,
        resolutionHint:
            'Add child nodes to the conditional, or remove the empty '
            'node.',
      ));
    }
    return issues;
  }
}

// =============================================================================
// LOOP TERMINATION ANALYSIS
// =============================================================================

/// Warns about Loop nodes whose termination condition is provably
/// unreachable inside any reasonable session window.
///
/// Concretely, this catches the "WhileDark loop whose body advances
/// time past sunrise" foot-gun: a `LoopConditionType.whileDark` loop
/// with no safety cap AND no `repeatUntil` AND no `repeatUntilAltitude`
/// is structurally identical to `UnboundedLoopRule`'s error case, but
/// the user's mental model is "it'll stop at dawn". We do not have a
/// sun-clock here so we cannot prove dawn won't come, but we *can*
/// prove the loop has no terminating signal Nightshade is observing —
/// at which point we hand off to [UnboundedLoopRule].
///
/// What this rule adds beyond UnboundedLoopRule:
///
///   * A bounded-by-time `repeatUntil` set to a moment **before** the
///     earliest plausible start (e.g. yesterday): `LoopEndTimePastRule`
///     warns about this, but for a `whileDark` loop with that timestamp
///     the loop is doubly broken (the "until" already passed AND the
///     "while" can never gate). We surface it as an additional warning
///     because the combination is rarely intended.
///
///   * A `LoopConditionType.integrationTime` loop with
///     `integrationTimeTarget` set to zero or negative: the target is
///     unreachable even at frame one, so the loop body would run once
///     then exit on the first integration accounting tick (or — worse,
///     depending on executor flooring — not at all). Warn so the user
///     can spot the field error.
///
/// Intentionally narrow: we do not try to prove generic termination
/// for arbitrary loop bodies. Anything stronger than these obvious
/// cases would be a static-analysis project unto itself.
class LoopUnreachableTerminationRule implements SequenceValidator {
  @override
  String get name => 'LoopUnreachableTermination';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    final now = DateTime.now();
    for (final node in sequence.nodes.values) {
      if (node is! LoopNode) continue;

      // Case 1: whileDark loop with a stale repeatUntil. Don't double-
      // fire if the existing LoopEndTimePastRule already covers it —
      // emit only when the loop is *also* whileDark, where the
      // combination is the foot-gun this rule exists to catch.
      if (node.conditionType == LoopConditionType.whileDark &&
          node.repeatUntil != null &&
          node.repeatUntil!.isBefore(now)) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          category: ValidationCategory.structure,
          title: 'WhileDark Loop With Past End Time',
          description:
              'Loop "${node.name}" runs while-dark but its end time has '
              'already passed. The end-time guard fires first; the '
              'while-dark check never gets to run.',
          affectedNodeId: node.id,
          resolutionHint:
              'Clear the end time or update it to a future moment, or '
              'switch the loop condition to count-based.',
        ));
      }

      // Case 2: integration-time loop with non-positive target.
      if (node.conditionType == LoopConditionType.integrationTime) {
        final target = node.integrationTimeTarget;
        if (target == null || target <= 0) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warning,
            category: ValidationCategory.structure,
            title: 'Integration-Time Loop Has No Target',
            description:
                'Loop "${node.name}" terminates on total integration time '
                'but its target is ${target ?? "unset"}. The loop will '
                'exit on the first accounting tick.',
            affectedNodeId: node.id,
            resolutionHint:
                'Set integrationTimeTarget to a positive number of '
                'seconds (or hours, depending on the UI).',
          ));
        }
      }
    }
    return issues;
  }
}
