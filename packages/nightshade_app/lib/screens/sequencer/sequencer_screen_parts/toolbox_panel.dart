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

  /// Strip width (excluding the collapse button) below which the three tab
  /// labels no longer fit at full size and the strip switches to equal shares.
  static const double _compactStripWidth = 240.0;

  /// A tab label that also states what it is to a screen reader.
  ///
  /// Flutter's [TabBar] wraps each tab in [MergeSemantics] and annotates it
  /// with `selected` + "Tab n of m", but never with an enabled state — so the
  /// AT-SPI tree published `panel: Nodes / Tab 1 of 3 [DISABLED]` for three
  /// tabs that switch panes on click (Wave D, WD-SEQ-N3). Declaring the state
  /// here merges it into that same node, the way the planner's filter chips
  /// were fixed (a95a1d500).
  ///
  /// Wave F: the `[DISABLED]` is gone, but the node is still ROLE-LESS —
  /// `panel: Nodes / Tab 1 of 3`. TabBar does wrap each tab in
  /// `Semantics(role: SemanticsRole.tab)`, but that is an ANCESTOR node, and
  /// the merged node carrying the label is the one an AT-SPI client reads.
  /// Declaring `button` here puts a role the Linux bridge demonstrably
  /// publishes on the node that actually carries the name.
  Widget _tabLabel(int index, String label, int activeIndex) {
    return Semantics(
      button: true,
      enabled: true,
      selected: activeIndex == index,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not read off the controller) so the tabs' selected-state
    // announcement rebuilds with the pane it describes.
    final activeIndex = ref.watch(sequencerToolboxTabProvider).index;
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
            // The strip has to fit the width the PANEL actually got, which is
            // not the width the screen has: at a 1000px window the palette is
            // ~200px wide and the scrollable strip clipped its outer labels —
            // "Nodes" rendered as "\odes" with the N cut off the left edge and
            // "Queue" as "Queu" with the e cut off behind the collapse button
            // (Wave D, NEW-C1). A scrollable strip in a too-small viewport
            // hides labels instead of resizing, so below the threshold we hand
            // the three tabs equal shares of the strip and shrink the type.
            child: LayoutBuilder(
              builder: (context, constraints) {
                const collapseButtonWidth = 24.0;
                final stripWidth = constraints.maxWidth -
                    (widget.onCollapse != null ? collapseButtonWidth : 0);
                final compact = stripWidth < _compactStripWidth;
                final labelFontSize =
                    compact ? 11.0 : Responsive.fontSize(context, 12);
                final labelPadding =
                    compact ? 4.0 : Responsive.spacing(context, 12);
                final tabHeight = Responsive.spacing(context, 34);

                return Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: !compact,
                        tabAlignment:
                            compact ? TabAlignment.fill : TabAlignment.start,
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
                        labelPadding:
                            EdgeInsets.symmetric(horizontal: labelPadding),
                        labelStyle: TextStyle(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                        tabs: [
                          Tab(
                            height: tabHeight,
                            child: _tabLabel(0, 'Nodes', activeIndex),
                          ),
                          Tab(
                            height: tabHeight,
                            // §4: surface the Ctrl+T accelerator on the
                            // Snippets tab so the keyboard toggle is
                            // discoverable.
                            child: Tooltip(
                              message: 'Toggle snippets (Ctrl+T)',
                              child: _tabLabel(1, 'Snippets', activeIndex),
                            ),
                          ),
                          Tab(
                            height: tabHeight,
                            child: _tabLabel(2, 'Queue', activeIndex),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onCollapse != null)
                      Tooltip(
                        message: 'Collapse panel',
                        child: InkWell(
                          onTap: widget.onCollapse,
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
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
                );
              },
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
