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
    _tabController = TabController(
      length: SequencerToolboxTab.values.length,
      vsync: this,
    );
    // Seed initial tab from the enum provider once. After this, sync flows
    // via the ref.listenManual hook below — keeps animateTo out of build()
    // (audit §4.3). The 3-tab controller and the 3-value enum are now the
    // same domain, so there is no lossy bool→3-tab mapping (audit §25).
    _tabController.index = ref.read(sequencerToolboxTabProvider).index;
    _tabController.addListener(_onTabChanged);

    ref.listenManual<SequencerToolboxTab>(sequencerToolboxTabProvider,
        (prev, next) {
      if (!mounted) return;
      if (_tabController.index != next.index) {
        _tabController.animateTo(next.index);
      }
    });

    // Backwards-compatible one-way bridge for the legacy
    // `snippetPaletteVisibleProvider` intent flag (§25): a cross-area caller
    // (Templates → "Go to Builder") flips it true to surface snippets. We act
    // on the rising edge by switching the enum, then reset the flag so it
    // stays a one-shot trigger with no bidirectional coupling.
    ref.listenManual<bool>(snippetPaletteVisibleProvider, (prev, next) {
      if (!mounted || !next) return;
      ref.read(sequencerToolboxTabProvider.notifier).state =
          SequencerToolboxTab.snippets;
      ref.read(snippetPaletteVisibleProvider.notifier).state = false;
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // Mirror every tab (including Queue) back to the enum provider so the
      // provider is the single source of truth for the active toolbox tab
      // and persists the user's last choice (audit §25).
      final tab = SequencerToolboxTab.values[_tabController.index];
      if (ref.read(sequencerToolboxTabProvider) != tab) {
        ref.read(sequencerToolboxTabProvider.notifier).state = tab;
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
                  child: Semantics(
                    enabled: true,
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
                      // Flutter's own `Tab` publishes a "Tab N of M" semantics
                      // node that never sets isEnabled, so AT-SPI reported all
                      // three of these as disabled — read off the running app
                      // 2026-08-09, alongside the app's own controls which are
                      // fixed at their widgets. Wrapping the strip states the
                      // truth for the framework's nodes without touching the
                      // TabBar's behaviour.
                      tabs: [
                        Tab(
                          height: Responsive.spacing(context, 34),
                          child: const Text('Nodes'),
                        ),
                        Tab(
                          height: Responsive.spacing(context, 34),
                          // §4: surface the Ctrl+T accelerator on the Snippets
                          // tab so the keyboard toggle is discoverable.
                          child: const Tooltip(
                            message: 'Toggle snippets (Ctrl+T)',
                            child: Text('Snippets'),
                          ),
                        ),
                        Tab(
                          height: Responsive.spacing(context, 34),
                          child: const Text('Queue'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: widget.onCollapse,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline4),
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
                // Target Queue panel mirrors the
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
