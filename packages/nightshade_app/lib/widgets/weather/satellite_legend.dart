import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Legend widget for GOES infrared satellite imagery.
///
/// Displays a color scale explaining what the infrared colors represent:
/// - White/bright = cold cloud tops (high/thick clouds)
/// - Gray = lower/thinner clouds
/// - Dark = clear sky (warm ground)
class SatelliteLegend extends StatelessWidget {
  /// Whether to show in compact horizontal mode
  final bool compact;

  const SatelliteLegend({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>() ??
        NightshadeColors.dark;

    if (compact) {
      return _buildCompactLegend(colors);
    }

    return _buildFullLegend(colors);
  }

  Widget _buildCompactLegend(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color gradient bar
          Container(
            width: 100,
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1a1a2e), // Dark (clear/warm)
                  Color(0xFF4a4a5a), // Gray (thin clouds)
                  Color(0xFF8a8a9a), // Light gray
                  Color(0xFFccccdd), // Light (clouds)
                  Color(0xFFffffff), // White (thick clouds)
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Clear',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward,
            size: 10,
            color: colors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            'Cloudy',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullLegend(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Infrared Satellite',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Color scale with labels
          Row(
            children: [
              // Gradient bar
              Expanded(
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF1a1a2e), // Dark (clear/warm)
                        Color(0xFF3a3a4a),
                        Color(0xFF5a5a6a),
                        Color(0xFF7a7a8a),
                        Color(0xFF9a9aaa),
                        Color(0xFFbabaca),
                        Color(0xFFdadaea),
                        Color(0xFFffffff), // White (thick clouds)
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Labels below gradient
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LegendLabel(
                text: 'Clear\n(Warm)',
                color: colors.textMuted,
              ),
              _LegendLabel(
                text: 'Thin\nClouds',
                color: colors.textMuted,
              ),
              _LegendLabel(
                text: 'Thick\nClouds',
                color: colors.textMuted,
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Additional info
          Text(
            'Brighter = Colder cloud tops = Higher/thicker clouds',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _LegendLabel({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10,
        color: color,
        height: 1.2,
      ),
    );
  }
}
