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
        return _DesktopBuilderLayout(colors: colors);
      },
    );
  }
}

/// Desktop layout: 3-column with collapsible panels
/// Uses mutually exclusive panel expansion - when one opens, the other closes
/// Adapts to screen width by using collapsed states on narrower screens
class _DesktopBuilderLayout extends ConsumerWidget {
  final NightshadeColors colors;

  const _DesktopBuilderLayout({required this.colors});

  // Base panel dimension constants (for ~1024px screens)
  static const double minCenterWidth = 300.0;
  static const double collapsedPanelWidth = 48.0;

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
    final selectedNodeId = ref.watch(selectedNodeIdProvider);

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

        // Main content - use LayoutBuilder to adapt to available width
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final dims = _panelDimensions(availableWidth);

              // Calculate space needed for different configurations
              final bothExpandedWidth =
                  dims.leftExpanded + minCenterWidth + dims.rightExpanded;
              const bothCollapsedMinWidth =
                  collapsedPanelWidth + minCenterWidth + collapsedPanelWidth;

              // Below the absolute minimum, fall back to a rail-only layout
              // that keeps a thin draggable icon palette so users can still
              // drop nodes onto the tree (audit §4.7).
              if (availableWidth < bothCollapsedMinWidth) {
                return _NarrowDesktopLayout(colors: colors);
              }

              // §4.7: auto-collapse is *derived* — never write back to the
              // user-pref providers. When the user later widens the
              // window, their original toolboxCollapsed/propertiesCollapsed
              // preferences come back unchanged.
              final spaceTight = availableWidth < bothExpandedWidth;

              // If both prefs say "expanded" but we can't fit both, pick
              // which one to force-collapse based on whether a node is
              // selected (selected = show its properties).
              final autoCollapseToolbox = spaceTight &&
                  !toolboxCollapsed &&
                  !propertiesCollapsed &&
                  selectedNodeId != null;
              final autoCollapseProperties = spaceTight &&
                  !toolboxCollapsed &&
                  !propertiesCollapsed &&
                  selectedNodeId == null;

              final effectiveToolboxCollapsed =
                  toolboxCollapsed || autoCollapseToolbox;
              final effectivePropertiesCollapsed =
                  propertiesCollapsed || autoCollapseProperties;

              return Row(
                children: [
                  // Left panel - Toolbox (Node Palette + Snippet Palette)
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectiveToolboxCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: effectivePropertiesCollapsed
                        ? dims.leftExpanded
                        : dims.leftMin,
                    minExpandedWidth: dims.leftMin,
                    maxExpandedWidth: dims.leftMax,
                    side: ResizeSide.right,
                    collapsedIcon: LucideIcons.layoutGrid,
                    collapsedTooltip: 'Show Toolbox',
                    onToggle: () {
                      // Only toggle this panel's pref. The derived
                      // effective* values above handle the other panel
                      // automatically when space is tight (§4.7).
                      final wasCollapsed =
                          ref.read(sequencerToolboxCollapsedProvider);
                      ref
                          .read(sequencerToolboxCollapsedProvider.notifier)
                          .state = !wasCollapsed;
                    },
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

                  // Right panel - Properties
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectivePropertiesCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: effectiveToolboxCollapsed
                        ? dims.rightExpanded
                        : dims.rightMin,
                    minExpandedWidth: dims.rightMin,
                    maxExpandedWidth: dims.rightMax,
                    side: ResizeSide.left,
                    collapsedIcon: LucideIcons.settings2,
                    collapsedTooltip: selectedNodeId != null
                        ? 'Show Properties'
                        : 'No Node Selected',
                    collapsedDisabled: selectedNodeId == null,
                    onToggle: () {
                      if (selectedNodeId == null) {
                        return; // Can't expand without selection
                      }
                      final wasCollapsed =
                          ref.read(sequencerPropertiesCollapsedProvider);
                      ref
                          .read(sequencerPropertiesCollapsedProvider.notifier)
                          .state = !wasCollapsed;
                    },
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
