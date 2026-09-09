import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// A labelled control: the label sits to the LEFT in a fixed column, not above
/// the field.
///
/// A label above its field costs a whole line of height per setting and turns
/// a dense panel into a scroll. Beside it, the labels line up into a readable
/// column and the controls line up into another, which is what makes a form of
/// twelve rows scannable.
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = defaultLabelWidth,
    this.help,
  });

  /// The label, in `textSecondary` at 13.
  final String label;

  /// The control.
  final Widget child;

  /// Width of the label column. The spec's range is 84–104; pick one width per
  /// form and keep it for every row in that form.
  final double labelWidth;

  /// One short line under the control. Use sparingly — most rows do not need
  /// one, and a form of explanations is a form nobody reads.
  final String? help;

  /// The default label column width in logical pixels (`observatory.css`
  /// `.form .row` grid column).
  static const double defaultLabelWidth = 96;

  /// Gap between the label column and the control.
  static const double columnGap = NightshadeTokens.spaceMd;

  /// Vertical gap between rows of a form.
  static const double rowGap = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: columnGap),
        Expanded(child: child),
      ],
    );

    if (help == null) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        row,
        const SizedBox(height: NightshadeTokens.spaceXs),
        Padding(
          padding: EdgeInsets.only(left: labelWidth + columnGap),
          child: Text(
            help!,
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
