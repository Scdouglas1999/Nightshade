part of '../sequencer_screen.dart';

class _ToolboxPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final VoidCallback? onCollapse;

  const _ToolboxPanel({
    super.key,
    required this.colors,
    this.onCollapse,
  });

  @override
  ConsumerState<_ToolboxPanel> createState() => _ToolboxPanelState();
}

class _ToolboxPanelState extends ConsumerState<_ToolboxPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Seed initial tab from the provider once. After this, sync flows via
    // the ref.listenManual hook below — keeps animateTo out of build()
    // (audit §4.3).
    final initialShowSnippets = ref.read(snippetPaletteVisibleProvider);
    if (initialShowSnippets) {
      _tabController.index = 1;
    }
    _tabController.addListener(_onTabChanged);

    ref.listenManual<bool>(snippetPaletteVisibleProvider, (prev, next) {
      if (!mounted) return;
      // The snippet tab provider is binary; only nudge tab 0 ↔ 1.
      // Tab 2 (target queue) is selected manually by the user and
      // does not write back to the snippet provider.
      if (_tabController.index == 2) return;
      final target = next ? 1 : 0;
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // Only mirror tab 0 ↔ 1 to the snippet provider. Tab 2 (target
      // queue) leaves the snippet pref untouched so that flipping
      // back to "Nodes" or "Snippets" lands on the user's last
      // non-queue choice.
      if (_tabController.index < 2) {
        ref.read(snippetPaletteVisibleProvider.notifier).state =
            _tabController.index == 1;
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surface,
        border: Border(right: BorderSide(color: widget.colors.border)),
      ),
      child: Column(
        children: [
          // Tab bar header
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: widget.colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: NightshadeDecorations.statusChip(
                      widget.colors.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      bordered: false,
                    ),
                    dividerColor: Colors.transparent,
                    labelColor: widget.colors.primary,
                    unselectedLabelColor: widget.colors.textMuted,
                    labelPadding: EdgeInsets.symmetric(
                      horizontal: Responsive.spacing(context, 12),
                    ),
                    labelStyle: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: [
                      Tab(
                        height: Responsive.spacing(context, 34),
                        child: const Text('Nodes'),
                      ),
                      Tab(
                        height: Responsive.spacing(context, 34),
                        child: const Text('Snippets'),
                      ),
                      Tab(
                        height: Responsive.spacing(context, 34),
                        child: const Text('Queue'),
                      ),
                    ],
                  ),
                ),
                if (widget.onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: widget.onCollapse,
                      borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          LucideIcons.panelLeftClose,
                          size: 16,
                          color: widget.colors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Node Palette (without its own header since we have tabs)
                _NodePaletteContent(colors: widget.colors),
                // Snippet Palette
                _SnippetPaletteContent(colors: widget.colors),
                // Wave 5 Agent 1 — Target Queue panel mirrors the
                // planetarium's queue and lets the user drag queued
                // targets onto the sequence tree.
                TargetQueuePanel(colors: widget.colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Node palette content without header (used in toolbox tabs)
