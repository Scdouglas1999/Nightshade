import '../../models/sequence/sequence_models.dart';

/// Severity of a validation issue
enum ValidationSeverity { error, warning }

/// A validation issue found in a sequence
class SequenceValidationIssue {
  final ValidationSeverity severity;
  final String message;
  final String? nodeId;

  const SequenceValidationIssue({
    required this.severity,
    required this.message,
    this.nodeId,
  });
}

/// Validate a sequence before execution.
///
/// Returns a list of issues (warnings + errors). Device connection validation
/// is intentionally not performed here — the backend sequencer reports those at
/// execution time, so that "validate then run" cannot race with disconnections.
List<SequenceValidationIssue> validateSequence(Sequence sequence) {
  final issues = <SequenceValidationIssue>[];

  if (sequence.nodes.isEmpty) {
    issues.add(const SequenceValidationIssue(
      severity: ValidationSeverity.error,
      message: 'Sequence is empty',
      nodeId: null,
    ));
    return issues;
  }

  if (sequence.rootNodeId == null) {
    issues.add(const SequenceValidationIssue(
      severity: ValidationSeverity.error,
      message: 'Sequence has no root node',
      nodeId: null,
    ));
    return issues;
  }

  for (final node in sequence.nodes.values) {
    if (isContainerNode(node) && node.childIds.isEmpty) {
      issues.add(SequenceValidationIssue(
        severity: ValidationSeverity.warning,
        message: '${node.name} is empty and will be skipped',
        nodeId: node.id,
      ));
    }

    if (node is ExposureNode) {
      if (node.durationSecs <= 0) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Exposure "${node.name}" has invalid duration',
          nodeId: node.id,
        ));
      }
      if (node.count <= 0) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Exposure "${node.name}" has invalid count',
          nodeId: node.id,
        ));
      }
    }

    if (node is TargetHeaderNode) {
      if (node.raHours < 0 || node.raHours > 24) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message:
              'Target "${node.name}" has invalid RA (must be 0-24 hours)',
          nodeId: node.id,
        ));
      }
      if (node.decDegrees < -90 || node.decDegrees > 90) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message:
              'Target "${node.name}" has invalid Dec (must be -90 to +90 degrees)',
          nodeId: node.id,
        ));
      }
    }

    if (node is LoopNode &&
        node.isUnbounded &&
        node.maxSafetyIterations == null) {
      issues.add(SequenceValidationIssue(
        severity: ValidationSeverity.warning,
        message:
            'Loop "${node.name}" has no safety iteration limit and could run indefinitely',
        nodeId: node.id,
      ));
    }

    if (node is SlewNode && !node.useTargetCoords) {
      if (node.customRa != null &&
          (node.customRa! < 0 || node.customRa! > 24)) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Slew "${node.name}" has invalid RA',
          nodeId: node.id,
        ));
      }
      if (node.customDec != null &&
          (node.customDec! < -90 || node.customDec! > 90)) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Slew "${node.name}" has invalid Dec',
          nodeId: node.id,
        ));
      }
    }
  }

  return issues;
}

/// True for node types that own a child list (Target/Loop/Parallel/Conditional/
/// Recovery/InstructionSet). Used by [validateSequence] to flag empty
/// containers and by editor logic that decides where to attach new nodes.
bool isContainerNode(SequenceNode node) {
  return node is TargetHeaderNode ||
      node is LoopNode ||
      node is ParallelNode ||
      node is ConditionalNode ||
      node is RecoveryNode ||
      node is InstructionSetNode;
}
