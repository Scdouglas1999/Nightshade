import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// A section heading inside a side panel or a settings page:
/// `[icon 15 muted] [sectionTitle] … [trailing]`, 8px gap, 8px below.
///
/// Replaces the Imaging 4 × 2 tile grid and the Sequencer properties header —
/// a section needs a name, not a chrome of its own.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  /// The section name, in sentence case.
  final String title;

  /// An optional 15px leading glyph in `textMuted`.
  final IconData? icon;

  /// An optional trailing control, right-aligned.
  final Widget? trailing;

  /// Gap between the icon and the title.
  static const double gap = NightshadeTokens.spaceSm;

  /// Space between the title row and the section's content.
  static const double bottomGap = NightshadeTokens.spaceSm;

  /// Icon size, in logical pixels.
  // TODO(observatory): promote to NightshadeTokens.iconGlyphSection
  static const double iconSize = 15;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: iconSize, color: colors.textMuted),
            const SizedBox(width: gap),
          ],
          Expanded(
            child: Text(
              title,
              style: NightshadeTypography.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
