import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The heading every Sequencer tab wears.
///
/// CON-52: the four tabs each did their own thing — Builder had no heading at
/// all, Templates and Sequence Library used a 24px title with a subtitle that
/// had no full stop, History used an 18px title with a subtitle that did. The
/// rule is not interesting; having one is. It lives here:
///
///   * a title in title case, 24px, semibold;
///   * exactly one subtitle sentence, 13px muted, ending in a full stop;
///   * both single-line, so a narrow window never reflows the surrounding
///     toolbar row.
///
/// WF-EQ-N1: single-line originally meant "ellipsised", and at 1000x800 that
/// cost the two tabs that share their row with a toolbar their own names —
/// "Sequenc…" and "Sequence Te…", beside a Builder copy of this same widget
/// rendering in full because it owns a full-width row. A heading that does not
/// say which tab you are on has stopped being a heading, so the title now
/// SHRINKS to fit the width it is given, down to a floor, and only ellipsises
/// below that. Callers were also fixed to stop handing the toolbar the slack;
/// this is the belt to that braces.
///
/// Callers keep their own icons and action buttons in the surrounding Row —
/// this owns the words only. `sequencer_tab_header_test.dart` pins the rule and
/// asserts every tab uses it; `sequencer_tab_title_width_test.dart` pins the
/// shrink-before-cut behaviour at the size Wave F drove.
class SequencerTabTitle extends StatelessWidget {
  final String title;

  /// One sentence. Asserted to end in a full stop, because "which tabs
  /// punctuate their subtitle" is exactly the kind of thing that drifts.
  final String subtitle;

  const SequencerTabTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  /// Smallest the title may be scaled to before an ellipsis is the honest
  /// answer. Still unmistakably a heading beside 13px body text.
  static const double minTitleFontSize = 16.0;

  @override
  Widget build(BuildContext context) {
    assert(
      subtitle.endsWith('.'),
      'Sequencer tab subtitles are one sentence and end in a full stop; '
      'got "$subtitle"',
    );
    final colors = NightshadeColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = _fittedTitleFontSize(context, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: title,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // The sentence may still be cut on a very tight row; unlike the
            // title it is not the tab's identity, and the tooltip carries it
            // whole.
            Tooltip(
              message: subtitle,
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The largest size in `[minTitleFontSize, 24]` at which [title] fits
  /// [maxWidth] on one line.
  double _fittedTitleFontSize(BuildContext context, double maxWidth) {
    const full = NightshadeTypography.fontSize24;
    if (!maxWidth.isFinite || maxWidth <= 0) return full;
    final natural = _titleWidth(context, full);
    if (natural <= maxWidth || natural <= 0) return full;
    // Text width scales linearly with font size for a single line.
    final scaled = full * (maxWidth / natural);
    return scaled < minTitleFontSize ? minTitleFontSize : scaled;
  }

  double _titleWidth(BuildContext context, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
