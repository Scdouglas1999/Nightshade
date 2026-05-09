import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// List item for a celestial object in the annotation panel.
class AnnotationObjectListItem extends StatelessWidget {
  final CelestialObjectAnnotation object;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final bool isSelected;

  const AnnotationObjectListItem({
    super.key,
    required this.object,
    required this.colors,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colors.border.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Object type icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getTypeColor(object.type).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  _getTypeIcon(object.type),
                  size: 14,
                  color: _getTypeColor(object.type),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Object info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    object.commonName ?? object.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (object.commonName != null) ...[
                        Text(
                          object.name,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        getTypeShortLabel(object.type),
                        style: TextStyle(
                          color:
                              _getTypeColor(object.type).withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Magnitude
            if (object.magnitude != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'm${object.magnitude!.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return LucideIcons.disc3;
      case ObjectType.nebula:
        return LucideIcons.cloud;
      case ObjectType.starCluster:
        return LucideIcons.sparkles;
      case ObjectType.planetaryNebula:
        return LucideIcons.circle;
      case ObjectType.star:
        return LucideIcons.star;
      case ObjectType.doubleStar:
        return LucideIcons.gitMerge;
      case ObjectType.asterism:
        return LucideIcons.shapes;
      case ObjectType.unknown:
        return LucideIcons.helpCircle;
    }
  }

  Color _getTypeColor(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return const Color(0xFFE879F9); // Purple/Pink for galaxies
      case ObjectType.nebula:
        return const Color(0xFF60A5FA); // Blue for nebulae
      case ObjectType.starCluster:
        return const Color(0xFFFBBF24); // Yellow for clusters
      case ObjectType.planetaryNebula:
        return const Color(0xFF34D399); // Green for planetary nebulae
      case ObjectType.star:
        return const Color(0xFFFFF7ED); // Warm white for stars
      case ObjectType.doubleStar:
        return const Color(0xFFF472B6); // Pink for double stars
      case ObjectType.asterism:
        return const Color(0xFFA78BFA); // Violet for asterisms
      case ObjectType.unknown:
        return const Color(0xFF9CA3AF); // Gray for unknown
    }
  }
}

/// Short label for an [ObjectType], used in list item sub-text.
String getTypeShortLabel(ObjectType type) {
  switch (type) {
    case ObjectType.galaxy:
      return 'Galaxy';
    case ObjectType.nebula:
      return 'Nebula';
    case ObjectType.starCluster:
      return 'Cluster';
    case ObjectType.planetaryNebula:
      return 'PN';
    case ObjectType.star:
      return 'Star';
    case ObjectType.doubleStar:
      return 'Double';
    case ObjectType.asterism:
      return 'Asterism';
    case ObjectType.unknown:
      return 'Unknown';
  }
}
