import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show ObjectType, DriverType;

import '../components/nightshade_alert.dart';
import '../components/nightshade_button.dart';
import '../components/nightshade_card.dart';
import '../components/nightshade_checkbox.dart';
import '../components/nightshade_progress_bar.dart';
import '../components/nightshade_switch.dart';
import '../components/nightshade_text_field.dart';
import '../components/screen_header.dart';
import '../components/status_dot.dart';
import '../components/status_pill.dart';
import '../components/sub_tab_button.dart';
import '../theme/annotation_type_colors.dart';
import '../theme/backend_protocol_colors.dart';
import '../theme/nightshade_chart_colors.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// A single, fully-static reference board that renders the entire Nightshade
/// design language on one canvas: the semantic palette, the chart / annotation /
/// backend domain palettes, the complete named typography scale (every style
/// labelled with its name + spec), and a representative pass over the component
/// library (cards, buttons, inputs, pills, dots, progress, alerts, headers).
///
/// Unlike [NightshadeDesignSystemGallery] this board is intentionally
/// stateless and interaction-free so it produces a deterministic frame — it is
/// the source widget for the committed golden-screenshot reference images under
/// `docs/design/goldens/`. Render it inside a themed [MaterialApp] and the whole
/// board re-skins from the active [NightshadeColors] extension, so the same
/// widget yields the light/dark board and the red-night board.
class NightshadeDesignReferenceBoard extends StatelessWidget {
  const NightshadeDesignReferenceBoard({super.key, this.themeLabel});

  /// Human label for the theme this board is rendered under (e.g. "Dark",
  /// "Red Night"). Shown in the board header so a captured PNG is
  /// self-identifying.
  final String? themeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Material(
      color: colors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NightshadeTokens.space2xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boardHeader(colors),
                const SizedBox(height: NightshadeTokens.space2xl),
                _twoColumn(
                  left: _SemanticPaletteSection(colors: colors),
                  right: _DomainPaletteSection(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                _BoardSection(
                  title: 'Typography scale',
                  child: _TypographyScale(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                _twoColumn(
                  left: _ComponentsSection(colors: colors),
                  right: _StatusAndFeedbackSection(colors: colors),
                ),
                const SizedBox(height: NightshadeTokens.space2xl),
                _BoardSection(
                  title: 'Layout primitives',
                  child: _LayoutPrimitivesSection(colors: colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardHeader(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Nightshade Design Language',
              style: NightshadeTypography.h1.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            if (themeLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NightshadeTokens.spaceMd,
                    vertical: NightshadeTokens.spaceXs,
                  ),
                  decoration: NightshadeDecorations.emphasisSurface(
                    colors.primary,
                    borderRadius: NightshadeTokens.borderRadiusSm,
                  ),
                  child: Text(
                    themeLabel!.toUpperCase(),
                    style: NightshadeTypography.overline.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Precision-instrument visual baseline — semantic palette, domain '
          'colors, full type scale, and the component library on one canvas.',
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _twoColumn({required Widget left, required Widget right}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: NightshadeTokens.space2xl),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: NightshadeTokens.space2xl),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Section shell
// ===========================================================================

class _BoardSection extends StatelessWidget {
  const _BoardSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: NightshadeTypography.overline.copyWith(
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

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
    return _BoardSection(
      title: 'Semantic palette',
      child: Wrap(
        spacing: NightshadeTokens.spaceMd,
        runSpacing: NightshadeTokens.spaceMd,
        children: [
          for (final swatch in swatches)
            _Swatch(label: swatch.$1, color: swatch.$2, frame: colors),
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
    return _BoardSection(
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
              _Swatch.compact(
                label: 'Blue',
                color: NightshadeChartColors.seriesBlue,
              ),
              _Swatch.compact(
                label: 'Violet',
                color: NightshadeChartColors.seriesViolet,
              ),
              _Swatch.compact(
                label: 'Green',
                color: NightshadeChartColors.seriesGreen,
              ),
              _Swatch.compact(
                label: 'Amber',
                color: NightshadeChartColors.seriesAmber,
              ),
              _Swatch.compact(
                label: 'Indigo',
                color: NightshadeChartColors.seriesIndigo,
              ),
              _Swatch.compact(
                label: 'Deep Blue',
                color: NightshadeChartColors.seriesDeepBlue,
              ),
              _Swatch.compact(
                label: 'Red',
                color: NightshadeChartColors.seriesRed,
              ),
              _Swatch.compact(
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

// ===========================================================================
// Full typography scale
// ===========================================================================

class _TypographyScale extends StatelessWidget {
  const _TypographyScale({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    // (name, spec, sample, style) for every named style in NightshadeTypography.
    final specimens = <(String, String, String, TextStyle)>[
      ('h1', '32 / w600', 'Aa Sequence Run', NightshadeTypography.h1),
      ('h2', '24 / w600', 'Aa Sequence Run', NightshadeTypography.h2),
      ('h3', '20 / w600', 'Aa Card Title', NightshadeTypography.h3),
      ('h4', '16 / w600', 'Aa Widget Title', NightshadeTypography.h4),
      ('h5', '14 / w600', 'Aa Label Title', NightshadeTypography.h5),
      ('h6', '12 / w600', 'Aa Small Heading', NightshadeTypography.h6),
      (
        'bodyLg',
        '16 / w400',
        'The quick brown fox',
        NightshadeTypography.bodyLg,
      ),
      ('body', '14 / w400', 'The quick brown fox', NightshadeTypography.body),
      (
        'bodyMedium',
        '14 / w500',
        'The quick brown fox',
        NightshadeTypography.bodyMedium,
      ),
      (
        'bodySm',
        '13 / w400',
        'The quick brown fox',
        NightshadeTypography.bodySm,
      ),
      ('labelLg', '14 / w500', 'Navigation Item', NightshadeTypography.labelLg),
      ('label', '13 / w500', 'Form Label', NightshadeTypography.label),
      ('labelSm', '12 / w500', 'Helper Badge', NightshadeTypography.labelSm),
      (
        'labelQuiet',
        '11 / w500',
        'Sidebar description',
        NightshadeTypography.labelQuiet,
      ),
      (
        'caption',
        '12 / w400',
        'Metadata · timestamp',
        NightshadeTypography.caption,
      ),
      (
        'captionSm',
        '11 / w400',
        'Very small caption',
        NightshadeTypography.captionSm,
      ),
      (
        'overline',
        '10 / w600 caps',
        'SECTION LABEL',
        NightshadeTypography.overline,
      ),
      ('monoLg', '18 / mono', 'RA 05h 35m 17s', NightshadeTypography.monoLg),
      (
        'telemetryLg',
        '22 / mono tab',
        '02:45:11',
        NightshadeTypography.telemetryLg,
      ),
      (
        'telemetryMd',
        '18 / mono tab',
        '18 min · 0.42 rms',
        NightshadeTypography.telemetryMd,
      ),
      ('mono', '14 / mono', 'EXP 120s · GAIN 100', NightshadeTypography.mono),
      (
        'monoSm',
        '12 / mono',
        'HFR 2.13 · ECC 0.41',
        NightshadeTypography.monoSm,
      ),
      ('monoXs', '11 / mono', '-10.0°C · 33%', NightshadeTypography.monoXs),
      ('statValue', '36 / w700 mono', '247', NightshadeTypography.statValue),
      (
        'statLabel',
        '12 / w500 caps',
        'FRAMES CAPTURED',
        NightshadeTypography.statLabel,
      ),
      ('button', '14 / w500', 'Start Sequence', NightshadeTypography.button),
      ('buttonSm', '13 / w500', 'Cancel', NightshadeTypography.buttonSm),
      ('input', '14 / w400', 'M31 Andromeda', NightshadeTypography.input),
      ('inputMono', '14 / mono', '05:35:17.3', NightshadeTypography.inputMono),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < specimens.length; i++) ...[
          if (i > 0)
            Divider(
              height: NightshadeTokens.spaceLg,
              thickness: 1,
              color: colors.border.withValues(alpha: 0.5),
            ),
          _TypeRow(
            name: specimens[i].$1,
            spec: specimens[i].$2,
            sample: specimens[i].$3,
            style: specimens[i].$4,
            colors: colors,
          ),
        ],
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.name,
    required this.spec,
    required this.sample,
    required this.style,
    required this.colors,
  });

  final String name;
  final String spec;
  final String sample;
  final TextStyle style;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            name,
            style: NightshadeTypography.monoSm.copyWith(color: colors.primary),
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            spec,
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            sample,
            style: style.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Components
// ===========================================================================

class _ComponentsSection extends StatelessWidget {
  const _ComponentsSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return _BoardSection(
      title: 'Components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel('Buttons', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              NightshadeButton(
                label: 'Capture',
                icon: LucideIcons.camera,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'Settings',
                icon: LucideIcons.settings,
                variant: ButtonVariant.outline,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'More',
                icon: LucideIcons.moreHorizontal,
                variant: ButtonVariant.ghost,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'Stop',
                icon: LucideIcons.octagon,
                variant: ButtonVariant.destructive,
                onPressed: _noop,
              ),
              NightshadeButton(label: 'Disabled', icon: LucideIcons.lock),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Cards', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CardSpecimen(
                  title: 'STANDARD',
                  value: 'Ready',
                  variant: CardVariant.standard,
                ),
              ),
              SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: _CardSpecimen(
                  title: 'ELEVATED',
                  value: 'Guiding',
                  variant: CardVariant.elevated,
                ),
              ),
              SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: _CardSpecimen(
                  title: 'SELECTED',
                  value: 'Profile A',
                  variant: CardVariant.standard,
                  isSelected: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Inputs', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeTextField(
            label: 'Target',
            initialValue: 'M31',
            prefixIcon: LucideIcons.search,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeTextField(
            label: 'Exposure',
            initialValue: '120',
            suffix: 'sec',
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              const NightshadeSwitch(value: true, onChanged: _noopBool),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Cooling',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              const NightshadeCheckbox(
                value: true,
                onChanged: _noopNullableBool,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Autosave',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Sub-tabs', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Row(
            children: [
              SubTabButton(label: 'Capture', isSelected: true, onTap: _noop),
              SubTabButton(label: 'Focus', isSelected: false, onTap: _noop),
              SubTabButton(label: 'Guiding', isSelected: false, onTap: _noop),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Status + feedback
// ===========================================================================

class _StatusAndFeedbackSection extends StatelessWidget {
  const _StatusAndFeedbackSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return _BoardSection(
      title: 'Status & feedback',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel('Status pills', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              StatusPill(
                icon: LucideIcons.radio,
                label: 'Camera',
                value: 'Connected',
                status: StatusPillStatus.active,
              ),
              StatusPill(
                icon: LucideIcons.checkCircle2,
                label: 'Solver',
                value: 'Solved',
                status: StatusPillStatus.success,
              ),
              StatusPill(
                icon: LucideIcons.cloudRain,
                label: 'Weather',
                value: 'Warning',
                status: StatusPillStatus.warning,
              ),
              StatusPill(
                icon: LucideIcons.wifiOff,
                label: 'Mount',
                value: 'Offline',
                status: StatusPillStatus.error,
              ),
              StatusPill(
                icon: LucideIcons.circleDashed,
                label: 'Rotator',
                value: 'Idle',
                status: StatusPillStatus.inactive,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Status dots', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              StatusDot(color: colors.success),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Online',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              StatusDot(
                color: colors.warning,
                variant: StatusDotVariant.attention,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Attention',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              StatusDot(color: colors.error, variant: StatusDotVariant.urgent),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Urgent',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Progress', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeProgressBar(
            value: 0.64,
            label: 'Sequence progress',
            showPercentage: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          const NightshadeProgressBar(
            value: 0.4,
            state: NightshadeProgressState.warning,
            label: 'Disk usage',
            showPercentage: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Alerts', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Self-test complete',
            message: 'Backend, storage, and route metadata passed.',
            severity: NightshadeAlertSeverity.info,
            compact: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Unsafe weather',
            message: 'Sequence start is blocked until safety clears.',
            severity: NightshadeAlertSeverity.warning,
            compact: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Restore failed',
            message: 'Backup file is missing a version field.',
            severity: NightshadeAlertSeverity.error,
            compact: true,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Layout primitives (ScreenHeader / SectionHeader / SectionWell)
// ===========================================================================

class _LayoutPrimitivesSection extends StatelessWidget {
  const _LayoutPrimitivesSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubLabel('ScreenHeader', colors: colors),
        const SizedBox(height: NightshadeTokens.spaceSm),
        ClipRRect(
          borderRadius: NightshadeTokens.borderRadiusSm,
          child: const ScreenHeader(
            title: 'Sequencer',
            subtitle: 'Build and run unattended imaging sequences',
            icon: LucideIcons.listOrdered,
            trailing: NightshadeButton(
              label: 'Run',
              icon: LucideIcons.play,
              size: ButtonSize.small,
              onPressed: _noop,
            ),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        _SubLabel('SectionHeader + SectionWell', colors: colors),
        const SizedBox(height: NightshadeTokens.spaceSm),
        SectionWell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Cooling',
                subtitle: 'Set point and ramp behavior',
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Row(
                children: [
                  const NightshadeSwitch(value: true, onChanged: _noopBool),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    'Cool camera before capture',
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Small shared building blocks
// ===========================================================================

void _noop() {}
void _noopBool(bool _) {}
void _noopNullableBool(bool? _) {}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text, {required this.colors});

  final String text;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: NightshadeTypography.label.copyWith(color: colors.textSecondary),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color, required this.frame})
    : compactMode = false;

  const _Swatch.compact({required this.label, required this.color})
    : frame = null,
      compactMode = true;

  final String label;
  final Color color;
  final NightshadeColors? frame;
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final colors = frame ?? context.nightshadeColors;
    final width = compactMode ? 92.0 : 116.0;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: compactMode ? 34 : 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: NightshadeTokens.borderRadiusSm,
              border: Border.all(color: colors.border),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            label,
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
          Text(
            _hex(color),
            style: NightshadeTypography.monoXs.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class _GradientBar extends StatelessWidget {
  const _GradientBar({
    required this.label,
    required this.stops,
    required this.colors,
  });

  final String label;
  final List<Color> stops;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 18,
          decoration: BoxDecoration(
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(color: colors.border),
            gradient: LinearGradient(colors: stops),
          ),
        ),
      ],
    );
  }
}

class _DotChip extends StatelessWidget {
  const _DotChip({
    required this.label,
    required this.color,
    required this.colors,
  });

  final String label;
  final Color color;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            label,
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSpecimen extends StatelessWidget {
  const _CardSpecimen({
    required this.title,
    required this.value,
    this.variant = CardVariant.standard,
    this.isSelected = false,
  });

  final String title;
  final String value;
  final CardVariant variant;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      variant: variant,
      isSelected: isSelected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: NightshadeTypography.overline.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            value,
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
