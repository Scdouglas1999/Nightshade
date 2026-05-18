import '../../../models/sequence/sequence_models.dart';
import '../../settings_provider.dart';
import '../sequence_validation.dart';

/// Warns when no image output directory is configured. Captured images
/// would not be saved.
class ImageOutputPathRule implements RefAwareSequenceValidator {
  @override
  String get name => 'ImageOutputPath';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    // Only relevant if the sequence will actually capture.
    final hasEnabledExposure = sequence.nodes.values
        .whereType<ExposureNode>()
        .any((n) => n.isEnabled);
    if (!hasEnabledExposure) return const [];

    // appSettingsProvider is an AsyncNotifier; `.read()` returns AsyncValue.
    // We use the public `value` getter, which returns null while loading or
    // in an error state. Either way, the rule emits an info-severity issue
    // rather than skipping silently.
    final settingsAsync = ctx.ref.read(appSettingsProvider);
    final settings = settingsAsync.value;
    if (settings == null) {
      // App settings not loaded yet — we can't validate. Surface clearly
      // rather than skipping silently.
      return const [
        ValidationIssue(
          severity: ValidationSeverity.info,
          category: ValidationCategory.settings,
          title: 'Settings Not Loaded',
          description:
              'Cannot validate image output path — app settings are still loading.',
        ),
      ];
    }

    if (settings.imageOutputPath.isEmpty) {
      return const [
        ValidationIssue(
          severity: ValidationSeverity.warning,
          category: ValidationCategory.settings,
          title: 'No Image Save Path',
          description:
              'No image output directory is configured. Captured images will NOT be saved to disk.',
          resolutionHint:
              'Configure an image save location in Settings → File Output.',
        ),
      ];
    }
    return const [];
  }
}

/// Info-only: flag a sequence still named "Untitled Sequence".
class DefaultSequenceNameRule implements RefAwareSequenceValidator {
  @override
  String get name => 'DefaultSequenceName';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final n = sequence.name;
    if (n.isEmpty || n == 'Untitled Sequence') {
      return const [
        ValidationIssue(
          severity: ValidationSeverity.info,
          category: ValidationCategory.settings,
          title: 'Default Sequence Name',
          description:
              'Consider naming your sequence for easier identification.',
        ),
      ];
    }
    return const [];
  }
}

/// Info-only: flag a very long estimated duration. Users running 10+ hour
/// sequences usually want to know.
class LongEstimatedDurationRule implements RefAwareSequenceValidator {
  @override
  String get name => 'LongEstimatedDuration';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final mins = sequence.estimatedDurationMins;
    if (mins == null) return const [];
    if (mins <= 600) return const [];
    return const [
      ValidationIssue(
        severity: ValidationSeverity.info,
        category: ValidationCategory.settings,
        title: 'Long Sequence',
        description: 'This sequence is estimated to run for over 10 hours.',
      ),
    ];
  }
}

/// Warns when the sequence has targets, runs > 2 hours, but has no
/// meridian-flip handling (no MeridianFlipNode + no Recovery node with
/// meridianFlip trigger). Targets crossing the meridian during a long run
/// will smash the mount into tracking limits without a flip.
class MeridianFlipTriggerRule implements RefAwareSequenceValidator {
  @override
  String get name => 'MeridianFlipTrigger';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final targets = sequence.targetHeaders;
    if (targets.isEmpty) return const [];

    final hasFlipNode = sequence.nodes.values.any(
      (n) => n is MeridianFlipNode && n.isEnabled,
    );
    if (hasFlipNode) return const [];

    final hasRecoveryFlip = sequence.nodes.values.any((n) =>
        n is RecoveryNode &&
        n.isEnabled &&
        n.triggerType == TriggerType.meridianFlip);
    if (hasRecoveryFlip) return const [];

    double totalMins = 0;
    for (final node in sequence.nodes.values) {
      if (node is! ExposureNode) continue;
      if (!node.isEnabled) continue;
      totalMins += (node.durationSecs * node.count) / 60.0;
    }
    if (totalMins < 120) return const [];

    return const [
      ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.equipment,
        title: 'No Meridian Flip Trigger',
        description:
            'This sequence has targets and runs for over 2 hours but has no meridian flip trigger. '
            'If targets cross the meridian during imaging, the mount may hit its tracking limits.',
        resolutionHint:
            'Add a MeridianFlip node to the sequence or enable auto meridian flip in Settings → Meridian Flip.',
      ),
    ];
  }
}
