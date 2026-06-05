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
              ? colors.primary.withValues(alpha: NightshadeTokens.opacitySubtle)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: colors.border),
          ),
        ),
        child: Row(
          children: [
            // Object type icon
            Container(
              width: 28,
              height: 28,
              decoration: NightshadeDecorations.iconChip(
                _getTypeColor(object.type),
                borderRadius: NightshadeTokens.borderRadiusMd,
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
                      fontSize: NightshadeTypography.fontSize12,
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
                            fontSize: NightshadeTypography.fontSize10,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        getTypeShortLabel(object.type),
                        style: TextStyle(
                          color:
                              _getTypeColor(object.type).withValues(alpha: 0.8),
                          fontSize: NightshadeTypography.fontSize10,
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
                  borderRadius: NightshadeTokens.borderRadiusInline4,
                ),
                child: Text(
                  'm${object.magnitude!.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize10,
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
        return NightshadeIcons.cloud;
      case ObjectType.starCluster:
        return NightshadeIcons.sparkle;
      case ObjectType.planetaryNebula:
        return NightshadeIcons.circle;
      case ObjectType.star:
        return NightshadeIcons.star;
      case ObjectType.doubleStar:
        return LucideIcons.gitMerge;
      case ObjectType.asterism:
        return LucideIcons.shapes;
      case ObjectType.unknown:
        return NightshadeIcons.help;
    }
  }

  Color _getTypeColor(ObjectType type) {
    return AnnotationTypeColors.forType(type, colors);
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
