part of '../sequencer_screen.dart';

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
    final isMobile = Responsive.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Tab buttons
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 20,
                vertical: 8,
              ),
              child: TabBar(
                controller: controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: NightshadeDecorations.statusChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(8),
                  bordered: false,
                ),
                dividerColor: Colors.transparent,
                labelColor: colors.primary,
                unselectedLabelColor: colors.textMuted,
                labelStyle: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(
                    key: SequencerTutorialKeys.tabBuilder,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.workflow, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('Builder'),
                      ],
                    ),
                  ),
                  Tab(
                    key: SequencerTutorialKeys.tabTargets,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.target, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('Targets'),
                      ],
                    ),
                  ),
                  Tab(
                    key: SequencerTutorialKeys.tabTemplates,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.fileStack, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('Templates'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.folderOpen, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('Sequences'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.library, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('Samples'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.history, size: isMobile ? 14 : 16),
                        SizedBox(width: isMobile ? 4 : 8),
                        const Text('History'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Running indicator (hidden on mobile - shown in playback bar instead)
          if (isRunning && !isMobile)
            Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: NightshadeDecorations.statusChip(
                colors.success,
                borderRadius: BorderRadius.circular(8),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
