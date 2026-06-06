part of '../sequencer_screen.dart';

/// Sequencer tab strip.
///
/// Uses [AdaptiveTabBar] so the four tabs (Builder / Templates / Sequences /
/// History) scroll horizontally instead of overflowing on a 360 px phone —
/// and collapse their labels to icon-only on a compact phone (`< 480`). The
/// strip drives the screen's [TabController] so the existing keyboard
/// shortcuts, provider sync and tutorial flow keep working.
///
/// The Targets tab was removed (its planning lives in the Planner screen) and
/// the old standalone "Samples" tab was merged into "Templates" as a built-in
/// Starters section.
class _SequencerTabBar extends StatelessWidget {
  final NightshadeColors colors;
  final TabController controller;
  final bool isRunning;

  const _SequencerTabBar({
    required this.colors,
    required this.controller,
    this.isRunning = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = Responsive.isPhone(context);

    final tabs = <AdaptiveTab>[
      AdaptiveTab(
        label: 'Builder',
        icon: LucideIcons.workflow,
        buttonKey: SequencerTutorialKeys.tabBuilder,
      ),
      AdaptiveTab(
        label: 'Templates',
        icon: LucideIcons.fileStack,
        buttonKey: SequencerTutorialKeys.tabTemplates,
      ),
      const AdaptiveTab(label: 'Sequences', icon: LucideIcons.folderOpen),
      const AdaptiveTab(label: 'History', icon: LucideIcons.history),
    ];

    // On phone the running state is surfaced by the playback bar, so the
    // trailing "Sequence Running" chip is desktop/tablet only.
    final trailing = <Widget>[
      if (isRunning && !isPhone)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: NightshadeDecorations.statusChip(
              colors.success,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.success.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sequence Running',
                  style: NightshadeTypography.h6.copyWith(color: colors.success),
                ),
              ],
            ),
          ),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedBuilder(
            // Rebuild the strip when the controller's selection changes so the
            // highlighted tab + auto-scroll-into-view follow the active index
            // regardless of whether the change came from a tap, a keyboard
            // shortcut, or the provider→controller sync in initState.
            animation: controller.animation ?? controller,
            builder: (context, _) {
              return AdaptiveTabBar(
                tabs: tabs,
                selectedIndex: controller.index,
                horizontalPadding: isPhone ? 8 : 20,
                onSelected: (i) => controller.animateTo(i),
                trailing: trailing,
              );
            },
          ),
        ),
      ),
    );
  }
}
