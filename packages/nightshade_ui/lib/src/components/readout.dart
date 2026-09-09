import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// The three readout scales: `lg` 28, `md` 20, `sm` 14.
enum ReadoutSize {
  /// 28px — hero numbers (sensor temperature on Equipment, HFR in a glance
  /// HUD).
  lg,

  /// 20px — the standard readout.
  md,

  /// 14px — readouts in dense rows and key/value lists.
  sm,
}

/// The em dash a readout shows when it has no value.
///
/// Never `---`, never `--:--`: those read as a value that happens to be
/// punctuation. One dash in muted grey reads as "not known".
const String kReadoutUnknown = '—';

/// A readout: a loud mono value over a quiet uppercase label.
///
/// The value is [NightshadeTypography.readoutLg]/`Md`/`Sm` in `textPrimary`
/// with tabular figures, the [unit] is the same style at 60% size in
/// `textMuted` attached with a 2px gap, and the [label] is
/// [NightshadeTypography.readoutLabel] in `textMuted` beneath it.
///
/// A null [value] renders [kReadoutUnknown] in `textMuted`; a screen never has
/// to invent a placeholder string of its own.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.size = ReadoutSize.md,
    this.valueColor,
  });

  /// The value. Null renders the em dash in `textMuted`.
  final String? value;

  /// The label beneath the value. Rendered uppercase.
  final String label;

  /// An optional unit attached to the value at 60% size in `textMuted`.
  final String? unit;

  /// Which of the three scales to use.
  final ReadoutSize size;

  /// Overrides the value colour — a status colour on a value that carries
  /// status. Ignored when [value] is null, which is always muted.
  final Color? valueColor;

  /// Gap between the value baseline row and the label.
  static const double labelGap = 2;

  /// Gap between the value and its unit.
  static const double unitGap = 2;

  /// The proportion of the value size a unit is drawn at.
  static const double unitScale = 0.6;

  TextStyle get _valueStyle => switch (size) {
    ReadoutSize.lg => NightshadeTypography.readoutLg,
    ReadoutSize.md => NightshadeTypography.readoutMd,
    ReadoutSize.sm => NightshadeTypography.readoutSm,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final unknown = value == null;
    final valueStyle = _valueStyle.copyWith(
      color: unknown ? colors.textMuted : (valueColor ?? colors.textPrimary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: unknown ? kReadoutUnknown : value,
            children: <InlineSpan>[
              if (!unknown && unit != null) ...<InlineSpan>[
                const WidgetSpan(child: SizedBox(width: unitGap)),
                TextSpan(
                  text: unit,
                  // A unit is part of the number, not a second field, so it
                  // scales WITH the value — `apply(fontSizeFactor:)`, never a
                  // fontSize literal.
                  style: valueStyle.apply(
                    fontSizeFactor: unitScale,
                    fontWeightDelta: -1,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          style: valueStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: labelGap),
        Text(
          label.toUpperCase(),
          style: NightshadeTypography.readoutLabel.copyWith(
            color: colors.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// A horizontal run of [Readout]s, top-aligned, with a 28px default gap.
class ReadoutRow extends StatelessWidget {
  const ReadoutRow({super.key, required this.children, this.gap = 28});

  /// The readouts, in reading order.
  final List<Readout> children;

  /// Horizontal gap between readouts.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          Flexible(child: children[i]),
        ],
      ],
    );
  }
}

/// A two-column key/value block: a 13px `textSecondary` key on the left and a
/// right-aligned mono value on the right.
///
/// Used where a panel lists facts that are not measurements loud enough to
/// deserve a [Readout] — weather figures, a target's catalogue entry.
class KeyValueList extends StatelessWidget {
  const KeyValueList({super.key, required this.rows});

  /// The rows, in reading order.
  final List<(String key, String value)> rows;

  /// Vertical gap between rows.
  static const double rowGap = 6;

  /// Minimum gap between a key and its value.
  static const double columnGap = NightshadeTokens.spaceLg;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: rowGap),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: columnGap),
              Text(
                rows[i].$2,
                textAlign: TextAlign.right,
                style: NightshadeTypography.readoutSm.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
