part of '../design_reference_board.dart';

// ===========================================================================
// Section shell
// ===========================================================================

// ===========================================================================
// Semantic palette
// ===========================================================================

class _SemanticPaletteSection extends StatelessWidget {
  const _SemanticPaletteSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final swatches = <(String, Color)>[
      ('Primary', colors.primary),
      ('Accent', colors.accent),
      ('Background', colors.background),
      ('Surface', colors.surface),
      ('Surface Alt', colors.surfaceAlt),
      ('Surface Hover', colors.surfaceHover),
      ('Surface Elevated', colors.surfaceElevated),
      ('Surface Overlay', colors.surfaceOverlay),
      ('Border', colors.border),
      ('Border Highlight', colors.borderHighlight),
      ('Text Primary', colors.textPrimary),
      ('Text Secondary', colors.textSecondary),
      ('Text Muted', colors.textMuted),
      ('Success', colors.success),
      ('Warning', colors.warning),
      ('Error', colors.error),
      ('Info', colors.info),
    ];
    return ShowcaseSection.boxed(
      title: 'Semantic palette',
      child: Wrap(
        spacing: NightshadeTokens.spaceMd,
        runSpacing: NightshadeTokens.spaceMd,
        children: [
          for (final swatch in swatches)
            ShowcaseSwatch.board(
              label: swatch.$1,
              color: swatch.$2,
              frame: colors,
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Domain palettes (chart series + gradients, annotation types, backends)
// ===========================================================================

class _DomainPaletteSection extends StatelessWidget {
  const _DomainPaletteSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection.boxed(
      title: 'Domain palettes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel('Chart series', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Wrap(
            spacing: NightshadeTokens.spaceMd,
            runSpacing: NightshadeTokens.spaceMd,
            children: [
              ShowcaseSwatch.boardCompact(
                label: 'Blue',
                color: NightshadeChartColors.seriesBlue,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Violet',
                color: NightshadeChartColors.seriesViolet,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Green',
                color: NightshadeChartColors.seriesGreen,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Amber',
                color: NightshadeChartColors.seriesAmber,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Indigo',
                color: NightshadeChartColors.seriesIndigo,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Deep Blue',
                color: NightshadeChartColors.seriesDeepBlue,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Red',
                color: NightshadeChartColors.seriesRed,
              ),
              ShowcaseSwatch.boardCompact(
                label: 'Orange',
                color: NightshadeChartColors.seriesOrange,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Data-viz gradients', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _GradientBar(
            label: 'PSF (tight → bloated)',
            stops: NightshadeChartColors.psfGradient,
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _GradientBar(
            label: 'Uniformity',
            stops: NightshadeChartColors.uniformityGradient,
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _GradientBar(
            label: 'Clip-high',
            stops: NightshadeChartColors.clipHighGradient,
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _GradientBar(
            label: 'Clip-low',
            stops: NightshadeChartColors.clipLowGradient,
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Annotation object types', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              for (final type in const [
                ObjectType.galaxy,
                ObjectType.nebula,
                ObjectType.starCluster,
                ObjectType.planetaryNebula,
                ObjectType.star,
                ObjectType.doubleStar,
                ObjectType.asterism,
              ])
                _DotChip(
                  label: _objectTypeLabel(type),
                  color: AnnotationTypeColors.forType(type, colors),
                  colors: colors,
                ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Driver backends', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              for (final backend in const [
                DriverType.native,
                DriverType.ascom,
                DriverType.alpaca,
                DriverType.indi,
                DriverType.simulator,
              ])
                _DotChip(
                  label: _backendLabel(backend),
                  color: BackendProtocolColors.forBackend(backend, colors),
                  colors: colors,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _objectTypeLabel(ObjectType type) => switch (type) {
    ObjectType.galaxy => 'Galaxy',
    ObjectType.nebula => 'Nebula',
    ObjectType.starCluster => 'Star Cluster',
    ObjectType.planetaryNebula => 'Planetary Nebula',
    ObjectType.star => 'Star',
    ObjectType.doubleStar => 'Double Star',
    ObjectType.asterism => 'Asterism',
    ObjectType.unknown => 'Unknown',
  };

  static String _backendLabel(DriverType backend) => switch (backend) {
    DriverType.native => 'Native SDK',
    DriverType.ascom => 'ASCOM',
    DriverType.alpaca => 'Alpaca',
    DriverType.indi => 'INDI',
    DriverType.simulator => 'Simulator',
  };
}
