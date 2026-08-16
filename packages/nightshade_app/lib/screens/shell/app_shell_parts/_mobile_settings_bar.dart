// The mobile settings bar shown in the shell chrome.
part of '../app_shell.dart';

class _MobileSettingsBar extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _MobileSettingsBar({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    // A narrow DESKTOP window still has no OS decorations (the runners set
    // TitleBarStyle.hidden), so this bar owns minimize/maximize/close and the
    // drag-to-move region below the side-nav breakpoint exactly as the full
    // TitleBar does above it. Without them, resizing under 768px left the
    // window with no mouse-reachable way to be closed, minimized or moved.
    final isDesktopWindow = ShellChrome.isDesktopWindow;

    final bar = Container(
      height: ShellChromeMetrics.titleBarHeight,
      color: colors.surface,
      // Caption buttons are flush to the window edge (platform convention and
      // Fitts' law), so the trailing inset is dropped when they are present.
      padding: EdgeInsets.only(
        left: NightshadeTokens.spaceLg,
        right: isDesktopWindow ? 0 : NightshadeTokens.spaceLg,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: NightshadeTokens.borderRadiusMd,
            ),
            child: Icon(NightshadeIcons.sparkle, size: 14, color: onPrimary),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm + 2),
          // The wordmark yields before the caption buttons do: on a very
          // narrow window the title may ellipsize, but close must not vanish.
          Flexible(
            child: Text(
              'NIGHTSHADE',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            key: TutorialKeys.navSettings,
            onTap: onOpenSettings,
            borderRadius: NightshadeTokens.borderRadiusInline4,
            child: Padding(
              padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
              child: Icon(
                NightshadeIcons.settings,
                size: NightshadeTokens.iconSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (isDesktopWindow) ...[
            const SizedBox(width: NightshadeTokens.spaceSm),
            WindowControls(colors: colors),
          ],
        ],
      ),
    );

    if (!isDesktopWindow) return bar;
    return WindowDragArea(child: bar);
  }
}
