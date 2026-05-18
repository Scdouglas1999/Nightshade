import '../../../models/sequence/sequence_models.dart';
import '../sequence_validation.dart';

/// Warns when a WaitTime node's `waitUntil` is in the past. The sequence
/// will skip the wait entirely, which may not be what the user intended.
class WaitTimePastRule implements SequenceValidator {
  @override
  String get name => 'WaitTimePast';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final now = DateTime.now();
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! WaitTimeNode) continue;
      final waitUntil = node.waitUntil;
      if (waitUntil == null) continue;
      if (!waitUntil.isBefore(now)) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.timing,
        title: 'Wait Time Passed',
        description:
            'Wait node "${node.name}" is set for a time that has already passed.',
        affectedNodeId: node.id,
        resolutionHint: 'Update the wait time or remove the node.',
      ));
    }
    return issues;
  }
}

/// Warns when a LoopNode's `repeatUntil` is in the past. The loop will not
/// execute any iterations.
class LoopEndTimePastRule implements SequenceValidator {
  @override
  String get name => 'LoopEndTimePast';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final now = DateTime.now();
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! LoopNode) continue;
      final repeatUntil = node.repeatUntil;
      if (repeatUntil == null) continue;
      if (!repeatUntil.isBefore(now)) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.timing,
        title: 'Loop End Time Passed',
        description: 'Loop "${node.name}" end time has already passed.',
        affectedNodeId: node.id,
        resolutionHint: 'Update the end time or change loop condition.',
      ));
    }
    return issues;
  }
}
