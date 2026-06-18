part of '../sequencer_screen.dart';

class _BuilderContent extends ConsumerWidget {
  final NightshadeColors colors;

  const _BuilderContent({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phone-first reflow. We treat the builder as a phone whenever the
    // *shorter* side of the region is below the phone breakpoint (`< 600`).
    // That keeps a phone held in LANDSCAPE (e.g. 844×390) on the phone-first
    // mobile builder — which uses the extra width for a side-by-side
    // tree+properties split — instead of falling into the desktop 3-column
    // layout, whose dense toolbar/header rows overflow at that height.
    //
    // The old `Responsive.isMobile` (`< 768`) lumped small tablets in with
    // phones AND switched on width alone, so a rotated phone got the squished
    // desktop path. Branching on the short side fixes both.
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        if (BreakpointTokens.isPhone(shortSide)) {
          return _MobileBuilderLayout(colors: colors);
        }
        // §24: thread this LayoutBuilder's width down to the desktop layout
        // instead of opening a second nested LayoutBuilder. The outer builder
        // is intentionally kept (not MediaQuery) so the short-side / split-
        // pane logic stays correct when the sequencer is embedded in a
        // sub-region (see the comment above).
        return _DesktopBuilderLayout(
          colors: colors,
          availableWidth: constraints.maxWidth,
        );
      },
    );
  }
}

/// Desktop layout: 3-column with collapsible panels
/// Uses mutually exclusive panel expansion - when one opens, the other closes
/// Adapts to screen width by using collapsed states on narrower screens
class _DesktopBuilderLayout extends ConsumerWidget {
  final NightshadeColors colors;
  final double availableWidth;

  const _DesktopBuilderLayout({
    required this.colors,
    required this.availableWidth,
  });

  // Base panel dimension constants (for ~1024px screens)
  static const double minCenterWidth = 300.0;
  static const double collapsedPanelWidth = 48.0;

  /// §7: bucket the raw available width to the nearest 64px before computing
  /// panel dimensions, so a continuous window-resize drag only steps the
  /// derived panel sizes occasionally instead of re-tweening every frame.
  static double _bucketWidth(double width) => (width / 64.0).round() * 64.0;

  /// Compute responsive panel dimensions based on available screen width.
  /// On a 2560px screen, panels grow proportionally wider so text doesn't
  /// look cramped. On a 1024px tablet, sizes stay compact.
  static ({
    double leftExpanded,
    double leftMin,
    double leftMax,
    double rightExpanded,
    double rightMin,
    double rightMax,
  }) _panelDimensions(double screenWidth) {
    // Scale factor: 1.0 at 1024px, up to ~1.4 at 2560px, minimum 1.0
    final scale = (screenWidth / 1024.0).clamp(1.0, 1.4);

    return (
      leftExpanded: (260.0 * scale).clamp(260.0, 380.0),
      leftMin: (220.0 * scale).clamp(220.0, 300.0),
      leftMax: (400.0 * scale).clamp(400.0, 560.0),
      rightExpanded: (320.0 * scale).clamp(320.0, 440.0),
      rightMin: (270.0 * scale).clamp(270.0, 360.0),
      rightMax: (500.0 * scale).clamp(500.0, 680.0),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolboxCollapsed = ref.watch(sequencerToolboxCollapsedProvider);
    final propertiesCollapsed = ref.watch(sequencerPropertiesCollapsedProvider);
    final persistedLeftWidth = ref.watch(sequencerLeftPanelWidthProvider);
    final persistedRightWidth = ref.watch(sequencerRightPanelWidthProvider);

    // §7: derive panel sizes from a bucketed width so a continuous resize
    // drag only steps the dimensions every ~64px instead of every frame.
    final dims = _panelDimensions(_bucketWidth(availableWidth));

    // Calculate space needed for different configurations.
    final bothExpandedWidth =
        dims.leftExpanded + minCenterWidth + dims.rightExpanded;
    const bothCollapsedMinWidth =
        collapsedPanelWidth + minCenterWidth + collapsedPanelWidth;

    return Column(
      children: [
        // Top toolbar
        SequenceToolbar(key: SequencerTutorialKeys.toolbar, colors: colors),

        // Equipment telemetry strip (visible during execution)
        Consumer(
          builder: (context, ref, child) {
            final executionState = ref.watch(sequenceExecutionStateProvider);
            final isExecuting =
                executionState == SequenceExecutionState.running ||
                    executionState == SequenceExecutionState.paused;
            if (!isExecuting) return const SizedBox.shrink();
            return EquipmentTelemetryStrip(colors: colors);
          },
        ),

        // Batch operations toolbar (visible during multi-select)
        Consumer(
          builder: (context, ref, child) {
            final isMultiSelect = ref.watch(isMultiSelectActiveProvider);
            if (!isMultiSelect) return const SizedBox.shrink();
            return BatchOperationsToolbar(colors: colors);
          },
        ),

        // Main content. Width comes from _BuilderContent's LayoutBuilder
        // (§24) so there is no second nested LayoutBuilder here.
        Expanded(
          child: Builder(
            builder: (context) {
              // Below the absolute minimum, fall back to a rail-only layout
              // that keeps a thin draggable icon palette so users can still
              // drop nodes onto the tree (audit §4.7).
              if (availableWidth < bothCollapsedMinWidth) {
                return _NarrowDesktopLayout(colors: colors);
              }

              // §8: when space is tight we no longer yank a whole panel
              // collapsed the instant a node is selected. Both panels stay
              // visible at their *min* widths in the tight band; the truly
              // narrow case below bothCollapsedMinWidth already drops to the
              // rail layout above. Auto-collapse is *derived* — we never
              // write back to the user-pref providers (§4.7), so widening
              // the window restores the user's saved expanded preference.
              final spaceTight = availableWidth < bothExpandedWidth;

              // Honor only the explicit user collapse prefs; tight space
              // packs both panels to *Min instead of collapsing one.
              final effectiveToolboxCollapsed = toolboxCollapsed;
              final effectivePropertiesCollapsed = propertiesCollapsed;

              // Derived expanded widths. When space is tight, both panels use
              // their min width. Otherwise a panel may grow to its expanded
              // width when the *other* panel is collapsed. A user-dragged
              // width (persisted, §6) overrides the derived width.
              final leftDerived = spaceTight
                  ? dims.leftMin
                  : (effectivePropertiesCollapsed
                      ? dims.leftExpanded
                      : dims.leftMin);
              final rightDerived = spaceTight
                  ? dims.rightMin
                  : (effectiveToolboxCollapsed
                      ? dims.rightExpanded
                      : dims.rightMin);
              final leftWidth = (persistedLeftWidth ?? leftDerived).clamp(
                dims.leftMin,
                dims.leftMax,
              );
              final rightWidth = (persistedRightWidth ?? rightDerived).clamp(
                dims.rightMin,
                dims.rightMax,
              );

              return Row(
                children: [
                  // Left panel - Toolbox (Node Palette + Snippet Palette)
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectiveToolboxCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: leftWidth,
                    minExpandedWidth: dims.leftMin,
                    maxExpandedWidth: dims.leftMax,
                    side: ResizeSide.right,
                    collapsedIcon: LucideIcons.layoutGrid,
                    collapsedTooltip: 'Show Toolbox',
                    onToggle: () {
                      final wasCollapsed =
                          ref.read(sequencerToolboxCollapsedProvider);
                      ref
                          .read(sequencerToolboxCollapsedProvider.notifier)
                          .state = !wasCollapsed;
                    },
                    // §6: persist a drag so it survives the next layout pass
                    // instead of snapping back to the derived width.
                    onWidthChanged: (w) => ref
                        .read(sequencerLeftPanelWidthProvider.notifier)
                        .state = w.clamp(dims.leftMin, dims.leftMax),
                    child: _ToolboxPanel(
                      key: SequencerTutorialKeys.nodePalette,
                      colors: colors,
                      onCollapse: () {
                        ref
                            .read(sequencerToolboxCollapsedProvider.notifier)
                            .state = true;
                      },
                    ),
                  ),

                  // Center - Sequence Tree
                  Expanded(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: minCenterWidth),
                      child: SequenceTree(
                          key: SequencerTutorialKeys.canvas, colors: colors),
                    ),
                  ),

                  // Right panel - Properties. §21: the panel can now expand
                  // with an empty state, so the toggle is always live and the
                  // affordance is discoverable before a node is selected —
                  // the panel renders NodePropertiesPanel's own "select a
                  // node" empty state.
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectivePropertiesCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: rightWidth,
                    minExpandedWidth: dims.rightMin,
                    maxExpandedWidth: dims.rightMax,
                    side: ResizeSide.left,
                    collapsedIcon: LucideIcons.settings2,
                    collapsedTooltip: 'Show Properties',
                    onToggle: () {
                      final wasCollapsed =
                          ref.read(sequencerPropertiesCollapsedProvider);
                      ref
                          .read(sequencerPropertiesCollapsedProvider.notifier)
                          .state = !wasCollapsed;
                    },
                    onWidthChanged: (w) => ref
                        .read(sequencerRightPanelWidthProvider.notifier)
                        .state = w.clamp(dims.rightMin, dims.rightMax),
                    child: NodePropertiesPanel(
                      key: SequencerTutorialKeys.propertiesPanel,
                      colors: colors,
                      onCollapse: () {
                        ref
                            .read(sequencerPropertiesCollapsedProvider.notifier)
                            .state = true;
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Combined toolbox panel with Node Palette and Snippet Palette tabs
