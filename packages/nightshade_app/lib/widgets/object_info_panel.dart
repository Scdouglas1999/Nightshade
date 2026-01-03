import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ObjectInfoPanel extends StatelessWidget {
  final ObjectData data;
  final VoidCallback onClose;

  const ObjectInfoPanel({
    super.key,
    required this.data,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        border: Border(left: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.catalogIds?['Name'] ?? 
                        data.catalogIds?['NGC'] ?? 
                        data.catalogIds?['IC'] ?? 
                        'Unknown Object',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.objectClass ?? 'Celestial Object',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: onClose,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (data.description != null) ...[
                  Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Catalog IDs
                if (data.catalogIds != null && data.catalogIds!.isNotEmpty) ...[
                  _SectionHeader(title: 'Designations', colors: colors),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: data.catalogIds!.entries.map((e) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Stellar Data
                if (data.spectralType != null || data.temperature != null) ...[
                  _SectionHeader(title: 'Stellar Properties', colors: colors),
                  if (data.spectralType != null)
                    _InfoRow(label: 'Spectral Type', value: data.spectralType.toString().split('.').last.toUpperCase(), colors: colors),
                  if (data.temperature != null)
                    _InfoRow(label: 'Temperature', value: '${data.temperature!.toStringAsFixed(0)} K', colors: colors),
                  if (data.mass != null)
                    _InfoRow(label: 'Mass', value: '${data.mass!.toStringAsFixed(2)} M☉', colors: colors),
                  if (data.distance != null)
                    _InfoRow(label: 'Distance', value: '${data.distance!.toStringAsFixed(1)} pc', colors: colors),
                  const SizedBox(height: 24),
                ],

                // Exoplanets
                if (data.exoplanets != null && data.exoplanets!.isNotEmpty) ...[
                  _SectionHeader(title: 'Exoplanets (${data.exoplanets!.length})', colors: colors),
                  ...data.exoplanets!.map((planet) => _ExoplanetCard(planet: planet, colors: colors)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final NightshadeColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _InfoRow({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, color: colors.textPrimary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ExoplanetCard extends StatelessWidget {
  final ExoplanetData planet;
  final NightshadeColors colors;

  const _ExoplanetCard({required this.planet, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                planet.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              if (planet.discoveryYear != null)
                Text(
                  '${planet.discoveryYear}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (planet.mass != null)
            _InfoRow(label: 'Mass', value: '${planet.mass} Mjup', colors: colors),
          if (planet.orbitalPeriod != null)
            _InfoRow(label: 'Period', value: '${planet.orbitalPeriod} days', colors: colors),
          if (planet.equilibriumTemp != null)
            _InfoRow(label: 'Temp', value: '${planet.equilibriumTemp} K', colors: colors),
        ],
      ),
    );
  }
}
