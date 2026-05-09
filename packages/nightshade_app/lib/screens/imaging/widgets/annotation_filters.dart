import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Maps an [ObjectType] to its corresponding set of [AnnotationObjectFilter]s.
Set<AnnotationObjectFilter> filtersForObjectType(ObjectType type) {
  switch (type) {
    case ObjectType.galaxy:
      return {AnnotationObjectFilter.galaxies};
    case ObjectType.nebula:
      return {AnnotationObjectFilter.nebulae};
    case ObjectType.planetaryNebula:
      return {AnnotationObjectFilter.planetaryNebulae};
    case ObjectType.starCluster:
      return {AnnotationObjectFilter.starClusters};
    case ObjectType.star:
    case ObjectType.doubleStar:
      return {AnnotationObjectFilter.stars};
    case ObjectType.asterism:
    case ObjectType.unknown:
      return {AnnotationObjectFilter.other};
  }
}

/// Returns true if the given [ObjectType] is visible given the current
/// set of active [AnnotationObjectFilter]s.
bool isTypeVisibleFromSettings(
  ObjectType type,
  Set<AnnotationObjectFilter> filters,
) {
  return filtersForObjectType(type).any(filters.contains);
}

/// Filter chip for object type filtering
class AnnotationFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const AnnotationFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  color: isSelected
                      ? colors.primary.withValues(alpha: 0.7)
                      : colors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
