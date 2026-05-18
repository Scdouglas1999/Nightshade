import '../../../models/sequence/sequence_models.dart';
import '../sequence_validation.dart';

/// Validates duration and count on every ExposureNode (enabled or not).
///
/// Disabled nodes still get validated for correctness — toggling them on
/// later should not surprise the user.
class ExposureParamsRule implements SequenceValidator {
  @override
  String get name => 'ExposureParams';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! ExposureNode) continue;
      if (node.durationSecs <= 0) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.exposures,
          title: 'Invalid Exposure Time',
          description:
              'Exposure "${node.name}" has invalid duration: ${node.durationSecs}s',
          affectedNodeId: node.id,
          resolutionHint: 'Set a positive exposure duration.',
        ));
      } else if (node.durationSecs > 1800) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          category: ValidationCategory.exposures,
          title: 'Very Long Exposure',
          description:
              'Exposure "${node.name}" is ${(node.durationSecs / 60).toStringAsFixed(0)} minutes. '
              'Very long exposures may fail due to tracking errors.',
          affectedNodeId: node.id,
          resolutionHint:
              'Consider breaking into shorter exposures or using auto-guiding.',
        ));
      }
      if (node.count <= 0) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.exposures,
          title: 'Invalid Frame Count',
          description:
              'Exposure "${node.name}" has count of ${node.count}.',
          affectedNodeId: node.id,
          resolutionHint: 'Set at least 1 frame to capture.',
        ));
      }
    }
    return issues;
  }
}

/// Info-only note for high binning (3x3, 4x4). Loses resolution; users
/// usually didn't mean to set this.
class HighBinningRule implements SequenceValidator {
  @override
  String get name => 'HighBinning';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! ExposureNode) continue;
      if (!node.isEnabled) continue;
      if (node.binning != BinningMode.three &&
          node.binning != BinningMode.four) {
        continue;
      }
      issues.add(ValidationIssue(
        severity: ValidationSeverity.info,
        category: ValidationCategory.exposures,
        title: 'High Binning',
        description:
            'Exposure "${node.name}" uses ${node.binning.label} binning which reduces resolution.',
        affectedNodeId: node.id,
      ));
    }
    return issues;
  }
}

/// Warns when the sequence has no enabled exposures. The sequence will run
/// but capture no images.
class NoExposuresRule implements SequenceValidator {
  @override
  String get name => 'NoExposures';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final hasEnabledExposure = sequence.nodes.values
        .whereType<ExposureNode>()
        .any((n) => n.isEnabled);
    if (hasEnabledExposure) return const [];

    // Don't fire if the sequence is itself empty — EmptySequenceRule covers
    // that.
    if (sequence.nodes.isEmpty) return const [];

    return const [
      ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.exposures,
        title: 'No Exposures',
        description:
            'No exposure nodes found. The sequence will run but capture no images.',
        resolutionHint: 'Add Exposure nodes to capture images.',
      ),
    ];
  }
}

/// Warns when the projected total integration time exceeds 8 hours. The
/// user can split the run across nights for safety.
class LongTotalIntegrationRule implements SequenceValidator {
  @override
  String get name => 'LongTotalIntegration';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final totalSecs = sequence.totalIntegrationSecs;
    if (totalSecs <= 28800) return const [];

    return [
      ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.timing,
        title: 'Very Long Sequence',
        description:
            'Total integration time is ${(totalSecs / 3600).toStringAsFixed(1)} hours. '
            'Consider splitting across multiple nights.',
      ),
    ];
  }
}
