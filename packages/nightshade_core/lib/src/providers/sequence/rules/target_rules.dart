import '../../../models/sequence/sequence_models.dart';
import '../sequence_validation.dart';

/// Validates RA / Dec on TargetHeaderNode and the equivalent custom-coord
/// path on SlewNode. RA must be in [0, 24); Dec must be in [-90, +90].
class TargetCoordinatesRule implements SequenceValidator {
  @override
  String get name => 'TargetCoordinates';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! TargetHeaderNode) continue;
      if (node.raHours < 0 || node.raHours >= 24) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.targets,
          title: 'Invalid RA',
          description:
              'Target "${node.targetName}" has invalid RA: ${node.raHours}h',
          affectedNodeId: node.id,
          resolutionHint: 'RA must be between 0 and 24 hours.',
        ));
      }
      if (node.decDegrees < -90 || node.decDegrees > 90) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.targets,
          title: 'Invalid Dec',
          description:
              'Target "${node.targetName}" has invalid Dec: ${node.decDegrees}°',
          affectedNodeId: node.id,
          resolutionHint: 'Declination must be between -90 and +90 degrees.',
        ));
      }
    }
    return issues;
  }
}

/// Validates custom RA/Dec on `SlewNode`s that don't use target coords.
class SlewCoordinatesRule implements SequenceValidator {
  @override
  String get name => 'SlewCoordinates';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final node in sequence.nodes.values) {
      if (node is! SlewNode) continue;
      if (node.useTargetCoords) continue;

      final ra = node.customRa;
      final dec = node.customDec;
      if (ra != null && (ra < 0 || ra >= 24)) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.targets,
          title: 'Invalid Slew RA',
          description: 'Slew "${node.name}" has invalid RA: ${ra}h',
          affectedNodeId: node.id,
          resolutionHint: 'RA must be between 0 and 24 hours.',
        ));
      }
      if (dec != null && (dec < -90 || dec > 90)) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.targets,
          title: 'Invalid Slew Dec',
          description: 'Slew "${node.name}" has invalid Dec: $dec°',
          affectedNodeId: node.id,
          resolutionHint: 'Declination must be between -90 and +90 degrees.',
        ));
      }
    }
    return issues;
  }
}

/// Warns when a target has no instructions. Note: distinct from the generic
/// EmptyContainerRule because targets get a friendlier label.
class EmptyTargetRule implements SequenceValidator {
  @override
  String get name => 'EmptyTarget';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final target in sequence.targetHeaders) {
      if (target.childIds.isNotEmpty) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.targets,
        title: 'Empty Target',
        description: 'Target "${target.targetName}" has no instructions.',
        affectedNodeId: target.id,
        resolutionHint:
            'Add exposure or other instruction nodes to the target.',
      ));
    }
    return issues;
  }
}

/// Warns when a target's minimum altitude is unusually low (<10°). Imaging
/// that close to the horizon almost always yields bad data.
class LowAltitudeLimitRule implements SequenceValidator {
  @override
  String get name => 'LowAltitudeLimit';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final issues = <ValidationIssue>[];
    for (final target in sequence.targetHeaders) {
      final minAlt = target.minAltitude;
      if (minAlt == null) continue;
      if (minAlt >= 10) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.targets,
        title: 'Very Low Altitude Limit',
        description:
            'Target "${target.targetName}" minimum altitude is $minAlt°. '
            'Imaging near the horizon may result in poor quality.',
        affectedNodeId: target.id,
        resolutionHint: 'Consider setting minimum altitude to 20° or higher.',
      ));
    }
    return issues;
  }
}

/// Warns when there are enabled exposures but no target defined.
class NoTargetForExposuresRule implements SequenceValidator {
  @override
  String get name => 'NoTargetForExposures';

  @override
  List<ValidationIssue> validate(Sequence sequence) {
    final targets = sequence.targetHeaders;
    if (targets.isNotEmpty) return const [];

    final hasEnabledExposures = sequence.nodes.values
        .whereType<ExposureNode>()
        .any((n) => n.isEnabled);
    if (!hasEnabledExposures) return const [];

    return const [
      ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.targets,
        title: 'No Targets Defined',
        description:
            'Exposures exist but no target is defined. The mount will image at its current position.',
        resolutionHint: 'Add a Target Group node with coordinates.',
      ),
    ];
  }
}
