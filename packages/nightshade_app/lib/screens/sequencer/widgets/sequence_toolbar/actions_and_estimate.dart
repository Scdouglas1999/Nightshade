part of '../sequence_toolbar.dart';

/// A single toolbar action. `isDivider == true` represents a visual
/// separator between groups (inline) or the start of a new section in
/// the overflow menu. Both renderings are driven by the same data so a hidden
/// button never silently disappears.
class _ToolbarAction {
  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isDivider;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : isDivider = false;

  const _ToolbarAction.divider()
      : icon = null,
        label = null,
        onPressed = null,
        isDivider = true;
}

/// The canvas bar's "more" menu: every secondary action, in one popup.
///
/// The anchor is a [NightshadeIconButton], not `PopupMenuButton`'s own icon.
/// PopupMenuButton sizes its anchor from `kMinInteractiveDimension` (48) and
/// this button sits in a 44 px bar between two 28 px buttons — it cannot be
/// the one control that is twenty pixels taller than its neighbours, and on a
/// narrow canvas those twenty pixels are what overflowed the row. The menu is
/// opened with [showMenu] positioned on the button's own rect, so the popup
/// still hangs off the control the user pressed.
///
/// Entries are disabled-but-visible when an action's `onPressed` is null,
/// matching the inline behaviour.
class _ToolbarOverflowMenu extends StatelessWidget {
  final NightshadeColors colors;
  final List<_ToolbarAction> actions;

  const _ToolbarOverflowMenu({required this.colors, required this.actions});

  Future<void> _open(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;

    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + button.size.height,
      overlay.size.width - origin.dx - button.size.width,
      0,
    );

    final items = <PopupMenuEntry<int>>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      if (a.isDivider) {
        if (items.isNotEmpty) items.add(const PopupMenuDivider());
        continue;
      }
      items.add(
        PopupMenuItem<int>(
          value: i,
          enabled: a.onPressed != null,
          child: Row(
            children: [
              Icon(
                a.icon,
                size: 16,
                color: a.onPressed == null
                    ? colors.textMuted
                    : colors.textSecondary,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm + 2),
              Flexible(
                child: Text(
                  a.label!,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: a.onPressed == null
                        ? colors.textMuted
                        : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) return;

    final chosen = await showMenu<int>(
      context: context,
      position: position,
      items: items,
    );
    if (chosen == null) return;
    actions[chosen].onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    // NightshadeIconButton is a fixed 28/32/36 box on every platform: 05 §6
    // gives it no touch behaviour, so on a phone its tappable rect is 20 dp
    // under Android's 48 dp rule. Until wave 4 grows the component's hit area
    // (see reports/observatory/w3-sequencer/notes.md), touch platforms keep
    // the nightshade_ui button that already implements that padding
    // correctly. Same glyph, same tooltip, legal target.
    if (NightshadeTouchTarget.isTouch(context)) {
      return AccessibleIconButton(
        icon: LucideIcons.moreHorizontal,
        label: 'More actions',
        tooltip: 'More actions',
        onPressed: () => _open(context),
      );
    }
    return NightshadeIconButton(
      icon: LucideIcons.moreHorizontal,
      tooltip: 'More actions',
      size: IconButtonSize.sm,
      onPressed: () => _open(context),
    );
  }
}
