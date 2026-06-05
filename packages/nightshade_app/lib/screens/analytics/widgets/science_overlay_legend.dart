import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Per-overlay explainer dialog and legend strip.
///
/// Implements P2.2 of the science gap list — every science overlay now has
/// a discoverable explanation of what the colors mean and what action they
/// suggest. Used by both the Imaging HUD overlay chips and the Analytics
/// Overlay Composer.
class ScienceOverlayLegend {
  static const _entries = <String, _LegendEntry>{
    'psf': _LegendEntry(
      label: 'PSF heatmap',
      icon: LucideIcons.layoutGrid,
      summary:
          'Median FWHM per tile. Green tiles = tight stars; red = bloated or elongated.',
      readMoreId: 'PSF Field Map',
      gradientStops: ['Tight', 'Average', 'Bloated'],
      gradientColors: NightshadeChartColors.psfGradient,
    ),
    'uniformity': _LegendEntry(
      label: 'Uniformity',
      icon: LucideIcons.boxSelect,
      summary:
          'Background brightness CV per tile. Flat is good; gradients warn of vignetting or moonglow.',
      gradientStops: ['Flat', 'Mild', 'Strong'],
      gradientColors: NightshadeChartColors.uniformityGradient,
    ),
    'clip_high': _LegendEntry(
      label: 'Clip High',
      icon: LucideIcons.arrowUpRightSquare,
      summary:
          'Tiles where pixels saturate. Red regions are losing highlight detail — drop exposure or gain.',
      gradientStops: ['Safe', 'Some clip', 'Saturated'],
      gradientColors: NightshadeChartColors.clipHighGradient,
    ),
    'clip_low': _LegendEntry(
      label: 'Clip Low',
      icon: LucideIcons.arrowDownLeftSquare,
      summary:
          'Tiles where pixels hit the noise floor. Blue regions show lost shadow signal — increase exposure.',
      gradientStops: ['Safe', 'Some clip', 'Floor'],
      gradientColors: NightshadeChartColors.clipLowGradient,
    ),
    'residuals': _LegendEntry(
      label: 'Astrometric residuals',
      icon: LucideIcons.move,
      summary:
          'Vector field of plate-solve residuals. Concentric patterns hint at tilt, swirls hint at distortion.',
      readMoreId: 'Astrometric Residuals',
    ),
    'moving': _LegendEntry(
      label: 'Moving object tracks',
      icon: LucideIcons.rocket,
      summary:
          'Multi-frame trails of detected moving candidates. Confidence is encoded in opacity.',
      readMoreId: 'Moving Object Candidates',
    ),
    'fwhm': _LegendEntry(
      label: 'FWHM surface',
      icon: LucideIcons.layoutTemplate,
      summary:
          '3D surface of FWHM across the field. A flat plane = even focus. A tilted plane = tilt.',
      readMoreId: 'PSF Field Map',
    ),
  };

  /// Show the legend dialog for a single overlay key. `key` must match one of
  /// the entries declared above; unknown keys silently no-op.
  static void show(BuildContext context, String key) {
    final entry = _entries[key];
    if (entry == null) return;
    final colors = NightshadeColors.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          side: BorderSide(color: colors.borderHighlight),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: NightshadeDecorations.tintedBadge(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Icon(entry.icon, color: colors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            context,
            designMaxWidth: 480,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.summary,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13,
                  height: 1.5,
                ),
              ),
              if (entry.gradientStops != null &&
                  entry.gradientColors != null) ...[
                const SizedBox(height: 16),
                _GradientRow(
                  stops: entry.gradientStops!,
                  swatches: entry.gradientColors!,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Got it',
            variant: ButtonVariant.ghost,
          ),
        ],
      ),
    );
  }

  /// Inline legend strip — three swatches with labels. Renders nothing for
  /// overlays without a defined gradient.
  static Widget inlineFor(BuildContext context, String key) {
    final entry = _entries[key];
    if (entry == null ||
        entry.gradientColors == null ||
        entry.gradientStops == null) {
      return const SizedBox.shrink();
    }
    final colors = NightshadeColors.of(context);
    return _GradientRow(
      stops: entry.gradientStops!,
      swatches: entry.gradientColors!,
      colors: colors,
      compact: true,
    );
  }
}

class _LegendEntry {
  final String label;
  final IconData icon;
  final String summary;

  /// Key into the analytics tab's `_kScienceInfoContent` map for a deeper
  /// "what is this?" panel. Used today only by the analytics tab itself.
  final String? readMoreId;

  /// Three-stop colour ramp for swatch displays. When null, no inline swatch
  /// is rendered.
  final List<Color>? gradientColors;
  final List<String>? gradientStops;

  const _LegendEntry({
    required this.label,
    required this.icon,
    required this.summary,
    this.readMoreId,
    this.gradientColors,
    this.gradientStops,
  });
}

class _GradientRow extends StatelessWidget {
  final List<Color> swatches;
  final List<String> stops;
  final NightshadeColors colors;
  final bool compact;

  const _GradientRow({
    required this.swatches,
    required this.stops,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final swatchSize = compact ? 10.0 : 14.0;
    final fontSize = compact ? 10.0 : 11.0;
    final children = <Widget>[];
    for (var i = 0; i < swatches.length; i++) {
      children.add(
        Container(
          width: swatchSize,
          height: swatchSize,
          decoration: BoxDecoration(
            color: swatches[i],
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
            border: Border.all(color: colors.border, width: 0.5),
          ),
        ),
      );
      children.add(const SizedBox(width: 4));
      children.add(
        Text(
          stops[i],
          style: TextStyle(
            fontSize: fontSize,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      if (i != swatches.length - 1) {
        children.add(const SizedBox(width: 10));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
