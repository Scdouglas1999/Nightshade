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

/// Single overflow popup that subsumes every secondary action below the
/// compact breakpoint. PopupMenuItems are disabled-but-visible when an
/// action's `onPressed` is null, matching inline behaviour.
class _ToolbarOverflowMenu extends StatelessWidget {
  final NightshadeColors colors;
  final List<_ToolbarAction> actions;

  const _ToolbarOverflowMenu({required this.colors, required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      icon: Icon(
        LucideIcons.moreHorizontal,
        size: 18,
        color: colors.textSecondary,
      ),
      onSelected: (index) {
        final action = actions[index];
        action.onPressed?.call();
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<int>>[];
        for (var i = 0; i < actions.length; i++) {
          final a = actions[i];
          if (a.isDivider) {
            if (items.isNotEmpty) {
              items.add(const PopupMenuDivider());
            }
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
                  const SizedBox(width: 10),
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
        return items;
      },
    );
  }
}
