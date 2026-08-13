part of '../design_reference_board.dart';

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
