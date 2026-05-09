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
          // Color gradient bar with more distinct stops
          Container(
            width: 100,
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0d0d18), // Very dark (clear sky)
                  Color(0xFF1a1a2e), // Dark (clear/warm)
                  Color(0xFF3a3a50), // Dark gray (very thin haze)
                  Color(0xFF6a6a82), // Medium gray (thin clouds)
                  Color(0xFFa0a0b8), // Light gray (moderate clouds)
                  Color(0xFFd0d0e0), // Light (thicker clouds)
                  Color(0xFFffffff), // White (thick/high clouds)
                ],
                stops: [0.0, 0.1, 0.25, 0.45, 0.65, 0.85, 1.0],
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
        borderRadius: BorderRadius.circular(8),
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

          // Color scale with labels - enhanced contrast gradient
          Row(
            children: [
              // Gradient bar with more distinct visual separation
              Expanded(
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0d0d18), // Very dark (clear sky)
                        Color(0xFF1a1a2e), // Dark (clear/warm)
                        Color(0xFF3a3a50), // Dark gray (very thin haze)
                        Color(0xFF5a5a72), // Medium-dark gray
                        Color(0xFF7a7a92), // Medium gray (thin clouds)
                        Color(0xFF9a9ab2), // Light-medium gray
                        Color(0xFFbabad2), // Light gray (moderate clouds)
                        Color(0xFFdadaf0), // Very light (thick clouds)
                        Color(0xFFffffff), // White (very thick/high clouds)
                      ],
                      stops: [0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92, 1.0],
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
            'Brighter = Colder cloud tops = Higher/thicker clouds\nUse contrast slider to enhance visibility',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontStyle: FontStyle.italic,
              height: 1.4,
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
