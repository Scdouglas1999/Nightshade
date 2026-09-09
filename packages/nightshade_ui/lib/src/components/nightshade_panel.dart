import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// A panel — the `surface`-toned container that every non-tappable block of
/// content sits in.
///
/// Replaces [NightshadeCard] wherever the container was never a control.
/// Depth comes from TONE, so a panel carries no visible border on the dark
/// palettes (only the 4% ring in [NightshadeDecorations.panel] so the edge
/// does not vanish on a poor monitor) and a real 1px `border` on light, where
/// white on off-white has no tone to separate with.
///
/// A panel has no hover and no `onTap`: a tappable container is a ROW or a
/// CANDIDATE, not a panel. A panel inside a panel does not exist either — the
/// deepest the ladder goes is `panel → well`.
class NightshadePanel extends StatelessWidget {
  const NightshadePanel({
    super.key,
    required this.child,
    this.head,
    this.padding = NightshadeTokens.paddingLg,
    this.flush = false,
    this.selected = false,
  });

  /// The panel's content.
  final Widget child;

  /// An optional [PanelHead] rendered above [child] with a 12px gap.
  final Widget? head;

  /// Internal padding. Ignored when [flush] is true.
  final EdgeInsets padding;

  /// Zero padding, clipped to the panel radius — for panels whose content is
  /// an image or a chart that should run to the corners.
  final bool flush;

  /// Draws the 1px `primary` ring at [NightshadeTokens.opacitySelectedRing]
  /// instead of the resting outline.
  final bool selected;

  /// The gap between a [PanelHead] and the panel body.
  static const double headGap = NightshadeTokens.spaceMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final decoration = selected
        ? NightshadeDecorations.panelSelected(colors)
        : NightshadeDecorations.panel(colors);

    Widget content = child;
    if (head != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          head!,
          const SizedBox(height: headGap),
          // NOT Flexible: a panel is normally laid out in a scroll view, where
          // the incoming height is unbounded and a flex child would throw.
          child,
        ],
      );
    }

    if (flush) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Container(decoration: decoration, padding: padding, child: content);
  }
}

/// The one-row label at the top of a [NightshadePanel]:
/// `[icon 15 muted] [eyebrow] … [trailing gap 8]`, 20px tall.
///
/// The eyebrow is [NightshadeTypography.eyebrow] in `textMuted` and uppercased
/// here so call sites write the label the way it reads in prose.
class PanelHead extends StatelessWidget {
  const PanelHead({
    super.key,
    required this.label,
    this.icon,
    this.trailing = const <Widget>[],
  });

  /// The panel label. Rendered uppercase.
  final String label;

  /// Optional 15px leading icon in `textMuted`.
  final IconData? icon;

  /// Trailing widgets, laid out with an 8px gap.
  final List<Widget> trailing;

  /// The head's fixed height in logical pixels.
  static const double height = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: _panelHeadIconSize, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: NightshadeTypography.eyebrow.copyWith(
                color: colors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var i = 0; i < trailing.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: NightshadeTokens.spaceSm),
            trailing[i],
          ],
        ],
      ),
    );
  }
}

/// Icon size inside a panel head, in logical pixels (03 §6: 15–16 in panel
/// heads; the scale has 14 and 16 but not 15).
// TODO(observatory): promote to NightshadeTokens.iconPanelHead
const double _panelHeadIconSize = 15;
