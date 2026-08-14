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
///   * both single-line and ellipsised, so a narrow window truncates rather
///     than reflows the surrounding toolbar row.
///
/// Callers keep their own icons and action buttons in the surrounding Row —
/// this owns the words only. `sequencer_tab_header_test.dart` pins the rule and
/// asserts every tab uses it.
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

  @override
  Widget build(BuildContext context) {
    assert(
      subtitle.endsWith('.'),
      'Sequencer tab subtitles are one sentence and end in a full stop; '
      'got "$subtitle"',
    );
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize24,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
