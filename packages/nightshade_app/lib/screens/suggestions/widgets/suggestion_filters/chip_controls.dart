part of '../suggestion_filters.dart';

// ============================================================================
// Multi-select Chips
// ============================================================================

/// Multi-select chips for object type filtering.
class _ObjectTypeChips extends StatelessWidget {
  final List<String> availableTypes;
  final List<String> selectedTypes;
  final NightshadeColors colors;
  final ValueChanged<List<String>> onChanged;

  const _ObjectTypeChips({
    required this.availableTypes,
    required this.selectedTypes,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: availableTypes.map((type) {
        final isSelected = selectedTypes.contains(type);
        return _FilterChip(
          label: _formatObjectType(type),
          isSelected: isSelected,
          colors: colors,
          onTap: () {
            final newSelection = List<String>.from(selectedTypes);
            if (isSelected) {
              newSelection.remove(type);
            } else {
              newSelection.add(type);
            }
            onChanged(newSelection);
          },
        );
      }).toList(),
    );
  }

  String _formatObjectType(String type) {
    final displayNames = {
      'galaxy': 'Galaxy',
      'nebula': 'Nebula',
      'cluster': 'Cluster',
      'star': 'Star',
      'planet': 'Planet',
      'moon': 'Moon',
      'comet': 'Comet',
      'asteroid': 'Asteroid',
      'planetary_nebula': 'Planetary Nebula',
      'planetaryNebula': 'Planetary Nebula',
      'star_cluster': 'Star Cluster',
      'starCluster': 'Star Cluster',
      'open_cluster': 'Open Cluster',
      'openCluster': 'Open Cluster',
      'globular_cluster': 'Globular Cluster',
      'globularCluster': 'Globular Cluster',
      'emission_nebula': 'Emission Nebula',
      'emissionNebula': 'Emission Nebula',
      'reflection_nebula': 'Reflection Nebula',
      'reflectionNebula': 'Reflection Nebula',
      'dark_nebula': 'Dark Nebula',
      'darkNebula': 'Dark Nebula',
      'supernova_remnant': 'Supernova Remnant',
      'supernovaRemnant': 'Supernova Remnant',
      'double_star': 'Double Star',
      'doubleStar': 'Double Star',
      'asterism': 'Asterism',
      'other': 'Other',
      'unknown': 'Unknown',
    };

    final normalized = type.toLowerCase();
    if (displayNames.containsKey(normalized)) {
      return displayNames[normalized]!;
    }
    if (displayNames.containsKey(type)) {
      return displayNames[type]!;
    }

    if (type.isEmpty) return type;
    return type[0].toUpperCase() + type.substring(1);
  }
}

/// Multi-select chips for constellation filtering.
class _ConstellationChips extends StatelessWidget {
  final List<String> availableConstellations;
  final Set<String> selectedConstellations;
  final NightshadeColors colors;
  final ValueChanged<Set<String>> onChanged;

  const _ConstellationChips({
    required this.availableConstellations,
    required this.selectedConstellations,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: availableConstellations.map((constellation) {
        final isSelected = selectedConstellations.contains(constellation);
        return _FilterChip(
          label: constellation,
          isSelected: isSelected,
          colors: colors,
          onTap: () {
            final newSelection = Set<String>.from(selectedConstellations);
            if (isSelected) {
              newSelection.remove(constellation);
            } else {
              newSelection.add(constellation);
            }
            onChanged(newSelection);
          },
        );
      }).toList(),
    );
  }
}

/// Reusable filter chip used by both object type and constellation chips.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                LucideIcons.check,
                size: 12,
                color: colors.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.primary : colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
