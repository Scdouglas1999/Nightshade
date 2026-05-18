import '../../../models/backend/device_types.dart';
import '../../../models/equipment/equipment_models.dart';
import '../../../models/sequence/sequence_models.dart';
import '../../equipment_provider.dart';
import '../sequence_validation.dart';

/// Cross-checks the device types required by enabled nodes against the
/// currently-connected equipment.
///
/// Strict map between [DeviceType] and connection state:
///   * camera — error if missing
///   * mount — error if missing (only when there are slewing/tracking nodes)
///   * focuser — error if missing (only when there are autofocus nodes)
///   * filter wheel — warning if missing (some users image without one)
///   * guider — warning if missing (per-node warnings on the actual guider
///     nodes, plus a high-level message if any node requires it)
///   * rotator — info if missing
///   * dome — info if missing
class EquipmentConnectionRule implements RefAwareSequenceValidator {
  @override
  String get name => 'EquipmentConnection';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final required = <DeviceType>{};
    for (final node in sequence.nodes.values) {
      if (!node.isEnabled) continue;
      required.addAll(node.requiredDevices);
    }
    if (required.isEmpty) return const [];

    final issues = <ValidationIssue>[];
    final ref = ctx.ref;

    bool isConnected(DeviceConnectionState s) =>
        s == DeviceConnectionState.connected;

    if (required.contains(DeviceType.camera)) {
      final cs = ref.read(cameraStateProvider);
      if (!isConnected(cs.connectionState)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.equipment,
          title: 'No Camera Connected',
          description: 'This sequence requires a camera to capture images.',
          resolutionHint: 'Connect a camera in the Equipment panel.',
        ));
      }
    }

    if (required.contains(DeviceType.mount)) {
      final ms = ref.read(mountStateProvider);
      if (!isConnected(ms.connectionState)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.equipment,
          title: 'No Mount Connected',
          description:
              'This sequence includes slewing or tracking operations that require a mount.',
          resolutionHint: 'Connect a mount in the Equipment panel.',
        ));
      }
    }

    if (required.contains(DeviceType.focuser)) {
      final fs = ref.read(focuserStateProvider);
      if (!isConnected(fs.connectionState)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.error,
          category: ValidationCategory.equipment,
          title: 'No Focuser Connected',
          description:
              'This sequence includes autofocus operations that require a focuser.',
          resolutionHint: 'Connect a focuser in the Equipment panel.',
        ));
      }
    }

    if (required.contains(DeviceType.filterWheel)) {
      final fws = ref.read(filterWheelStateProvider);
      if (!isConnected(fws.connectionState)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.warning,
          category: ValidationCategory.equipment,
          title: 'No Filter Wheel Connected',
          description:
              'This sequence includes filter changes that require a filter wheel.',
          resolutionHint: 'Connect a filter wheel in the Equipment panel.',
        ));
      }
    }

    if (required.contains(DeviceType.guider)) {
      final gs = ref.read(guiderStateProvider);
      if (!isConnected(gs.connectionState)) {
        // Add a top-level summary issue + per-node warnings so the tree
        // borders highlight the affected nodes.
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.warning,
          category: ValidationCategory.equipment,
          title: 'No Guider Connected',
          description:
              'This sequence includes guiding or dithering operations that require PHD2.',
          resolutionHint: 'Connect to PHD2 in the Guiding panel.',
        ));
        for (final node in sequence.nodes.values) {
          if (!node.isEnabled) continue;
          if (!node.requiredDevices.contains(DeviceType.guider)) continue;
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warning,
            category: ValidationCategory.equipment,
            title: 'Guider Not Connected',
            description:
                '${node.name} requires a guider (PHD2) but none is connected.',
            affectedNodeId: node.id,
            resolutionHint: 'Connect to PHD2 in the Guiding panel.',
          ));
        }
      }
    }

    if (required.contains(DeviceType.rotator)) {
      final rs = ref.read(rotatorStateProvider);
      if (!isConnected(rs.connectionState)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.info,
          category: ValidationCategory.equipment,
          title: 'No Rotator Connected',
          description: 'This sequence includes rotator operations.',
          resolutionHint: 'Connect a rotator in the Equipment panel.',
        ));
      }
    }

    if (required.contains(DeviceType.dome)) {
      // Dome state is not yet a first-class provider; surface an info note
      // rather than silently skipping the check.
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.info,
        category: ValidationCategory.equipment,
        title: 'Dome Operations Present',
        description:
            'This sequence includes dome operations. Cannot verify dome connection at edit time.',
        resolutionHint:
            'Verify the dome is connected before starting the sequence.',
      ));
    }

    return issues;
  }
}

/// Warns when a target specifies a rotation angle but no rotator is
/// connected. The rotator command will fail at runtime.
class RotatorRotationConflictRule implements RefAwareSequenceValidator {
  @override
  String get name => 'RotatorRotationConflict';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final issues = <ValidationIssue>[];
    final rotatorState = ctx.ref.read(rotatorStateProvider);
    final connected =
        rotatorState.connectionState == DeviceConnectionState.connected;
    if (connected) return const [];

    for (final target in sequence.targetHeaders) {
      final rotation = target.rotation;
      if (rotation == null) continue;
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.equipment,
        title: 'Rotator Not Connected',
        description:
            'Target "${target.targetName}" specifies rotation (${rotation.toStringAsFixed(1)}°) '
            'but no rotator is connected.',
        affectedNodeId: target.id,
        resolutionHint: 'Connect a rotator or remove the rotation setting.',
      ));
    }
    return issues;
  }
}
