import '../../../models/equipment/equipment_models.dart';
import '../../../models/sequence/sequence_models.dart';
import '../../equipment_provider.dart';
import '../sequence_validation.dart';

/// Warns when a node references a filter by name that the connected filter
/// wheel does not have. Only runs when a filter wheel is connected — if no
/// wheel is connected, the EquipmentConnectionRule already complained.
class FilterInWheelRule implements RefAwareSequenceValidator {
  @override
  String get name => 'FilterInWheel';

  @override
  List<ValidationIssue> validate(Sequence sequence, ValidationContext ctx) {
    final fwState = ctx.ref.read(filterWheelStateProvider);
    if (fwState.connectionState != DeviceConnectionState.connected) {
      // Not connected — different rule. Don't double-complain.
      return const [];
    }

    final available = fwState.filterNames.map((f) => f.toLowerCase()).toSet();
    if (available.isEmpty) {
      // Connected but driver hasn't reported filter names yet. Surface as
      // info — we can't validate, but the user should know.
      return [
        const ValidationIssue(
          severity: ValidationSeverity.info,
          category: ValidationCategory.equipment,
          title: 'Filter Wheel Reports No Filters',
          description:
              'A filter wheel is connected but reports no filter names. Filter validation skipped.',
          resolutionHint:
              'Configure filter names in the equipment profile or wait for the driver to populate them.',
        ),
      ];
    }

    final issues = <ValidationIssue>[];
    final availableLabel = fwState.filterNames.join(', ');

    for (final node in sequence.nodes.values) {
      if (!node.isEnabled) continue;

      if (node is ExposureNode) {
        final filter = node.filter;
        if (filter == null || filter.isEmpty) continue;
        if (!available.contains(filter.toLowerCase())) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warning,
            category: ValidationCategory.equipment,
            title: 'Filter Not in Wheel',
            description:
                'Exposure "${node.name}" uses filter "$filter" which is not '
                'in the connected filter wheel. Available: $availableLabel.',
            affectedNodeId: node.id,
            resolutionHint:
                'Change the filter name or check the filter wheel configuration.',
          ));
        }
      } else if (node is FilterChangeNode) {
        final filter = node.filterName;
        if (filter.isEmpty) continue;
        if (!available.contains(filter.toLowerCase())) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warning,
            category: ValidationCategory.equipment,
            title: 'Filter Not in Wheel',
            description:
                'Filter change "${node.name}" uses filter "$filter" which is not '
                'in the connected filter wheel. Available: $availableLabel.',
            affectedNodeId: node.id,
            resolutionHint:
                'Change the filter name or check the filter wheel configuration.',
          ));
        }
      }
    }
    return issues;
  }
}
