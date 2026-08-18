import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Centered "no data" / "nothing selected" placeholder used across screens
/// (diagnostics, science analytics) when a tab has nothing to render but
/// must still occupy its slot in an [IndexedStack] or scroll view.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final double _iconSize;
  final TextStyle _titleStyle;
  final double _iconTitleGap;
  final double _bodyGap;
  final double _actionGap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.all(24),
  }) : _iconSize = NightshadeTokens.iconXl,
       _titleStyle = NightshadeTypography.h5,
       _iconTitleGap = NightshadeTokens.spaceLg,
       _bodyGap = NightshadeTokens.spaceSm,
       _actionGap = NightshadeTokens.spaceLg;

  /// Tighter variant for side panels and embedded slots (32px icon).
  const EmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  }) : _iconSize = NightshadeTokens.iconXl,
       _titleStyle = NightshadeTypography.h6,
       _iconTitleGap = NightshadeTokens.spaceMd,
       _bodyGap = NightshadeTokens.spaceXs,
       _actionGap = NightshadeTokens.spaceMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: _iconSize, color: colors.textMuted),
              SizedBox(height: _iconTitleGap),
              Text(
                title,
                style: _titleStyle.copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              if (body != null) ...[
                SizedBox(height: _bodyGap),
                Text(
                  body!,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                SizedBox(height: _actionGap),
                // The action is a node of its own.
                //
                // A screen with a keyboard shortcut has a focusable ancestor
                // over everything on it — `CallbackShortcuts` builds a `Focus`,
                // and a `Focus` publishes `focusable` unless told not to — and
                // that one annotated node absorbs every descendant fragment
                // that is not bounded. An empty state is several paragraphs
                // around ONE interactive descendant, so the tap and the role of
                // that one control merged into the same node as all the words:
                // the Darkroom's "Nothing to open" state reached AT-SPI as a
                // single ~300-character button whose name was the screen title,
                // the reason, and this label twice over. There was no node
                // named for the action, so an exact-name lookup failed, and an
                // activation landed on a node whose extents were the whole
                // screen. States with two or more actions escaped it only
                // because two taps cannot merge into one node.
                //
                // The boundary stops the merge here: the words stay text and
                // the control keeps its own name and its own box.
                Semantics(container: true, child: action!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
