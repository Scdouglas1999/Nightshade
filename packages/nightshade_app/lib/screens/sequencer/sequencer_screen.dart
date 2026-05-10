import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/animated_tab_bar_view.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/sequencer_keys.dart';
import 'widgets/batch_operations_toolbar.dart';
import 'widgets/sequence_toolbar.dart';
import 'widgets/node_palette.dart';
import 'widgets/snippet_palette.dart';
import 'widgets/sequence_tree.dart';
import 'widgets/node_properties_panel.dart';
import 'widgets/sequence_progress_bar.dart';
import 'widgets/equipment_telemetry_strip.dart';
import 'widgets/mobile_playback_bar.dart';
import 'tabs/history_tab.dart';
import 'tabs/targets_tab.dart';
import 'tabs/templates_tab.dart';

/// Currently selected sequencer tab
final sequencerTabProvider = StateProvider<int>((ref) => 0);

/// Which panel is currently expanded in the sequencer
/// null = both panels at default sizes (when space permits)
/// 'toolbox' = toolbox expanded, properties collapsed
/// 'properties' = properties expanded, toolbox collapsed
final sequencerExpandedPanelProvider = StateProvider<String?>((ref) => null);

/// Whether the toolbox panel is collapsed (icon-only mode)
final sequencerToolboxCollapsedProvider = StateProvider<bool>((ref) => false);

/// Whether the properties panel is collapsed (icon-only mode)
final sequencerPropertiesCollapsedProvider =
    StateProvider<bool>((ref) => false);

/// Whether the snippet palette is visible in the toolbox panel
final snippetPaletteVisibleProvider = StateProvider<bool>((ref) => false);

class SequencerScreen extends ConsumerStatefulWidget {
  const SequencerScreen({super.key});

  @override
  ConsumerState<SequencerScreen> createState() => _SequencerScreenState();
}

class _SequencerScreenState extends ConsumerState<SequencerScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(sequencerTabProvider.notifier).state = _tabController.index;
      }
    });

    // Sync provider -> controller via a listen hook rather than peeking at
    // the provider during build(). The build-time animateTo() worked most
    // of the time but fired under window-resize storms / hot-reload,
    // causing flicker (audit §4.3).
    ref.listenManual<int>(sequencerTabProvider, (prev, next) {
      if (!mounted) return;
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    });

    // Create a default sequence if none exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sequence = ref.read(currentSequenceProvider);
      if (sequence == null) {
        ref.read(currentSequenceProvider.notifier).createSequence();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;
    // Tab sync runs via ref.listenManual in initState (audit §4.3). The
    // current value is still read for the shortcut bindings below that
    // gate behaviour to the Builder tab.
    final currentTab = ref.watch(sequencerTabProvider);

    return ContextualTourPrompt(
      screenId: 'sequencer',
      tourCategory: TutorialCategory.sequencerTour,
      title: 'Sequencer Tour',
      description: 'Learn how to create and run automated imaging sequences.',
      durationMinutes: 4,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOut,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
              if (currentTab == 0) {
                ref.read(currentSequenceProvider.notifier).undo();
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
              if (currentTab == 0) {
                ref.read(currentSequenceProvider.notifier).redo();
              }
            },
            const SingleActivator(LogicalKeyboardKey.delete): () {
              if (currentTab == 0) {
                final multiSelected = ref.read(multiSelectedNodeIdsProvider);
                if (multiSelected.isNotEmpty) {
                  ref
                      .read(multiSelectedNodeIdsProvider.notifier)
                      .deleteSelected();
                } else {
                  final selectedId = ref.read(selectedNodeIdProvider);
                  if (selectedId != null) {
                    ref
                        .read(currentSequenceProvider.notifier)
                        .removeNode(selectedId);
                    ref.read(selectedNodeIdProvider.notifier).state = null;
                  }
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
              if (currentTab == 0) {
                final selectedId = ref.read(selectedNodeIdProvider);
                if (selectedId != null) {
                  ref
                      .read(currentSequenceProvider.notifier)
                      .duplicateNode(selectedId);
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (currentTab == 0) {
                final multiSelected = ref.read(multiSelectedNodeIdsProvider);
                if (multiSelected.isNotEmpty) {
                  ref.read(multiSelectedNodeIdsProvider.notifier).clear();
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
              if (currentTab == 0) {
                final multiSelected = ref.read(multiSelectedNodeIdsProvider);
                if (multiSelected.isNotEmpty) {
                  ref
                      .read(multiSelectedNodeIdsProvider.notifier)
                      .copySelected();
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
              if (currentTab == 0) {
                final clipboard = ref.read(nodeCopyClipboardProvider);
                if (clipboard != null && clipboard.isNotEmpty) {
                  ref
                      .read(multiSelectedNodeIdsProvider.notifier)
                      .pasteFromClipboard();
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () {
              _tabController.animateTo(0);
            },
            const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () {
              _tabController.animateTo(1);
            },
            const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () {
              _tabController.animateTo(2);
            },
            const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () {
              _tabController.animateTo(3);
            },
            // Ctrl+T (or Cmd+T on Mac) to toggle snippet palette visibility
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              if (currentTab == 0) {
                final current = ref.read(snippetPaletteVisibleProvider);
                ref.read(snippetPaletteVisibleProvider.notifier).state =
                    !current;
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                // Tab bar
                _SequencerTabBar(
                  colors: colors,
                  controller: _tabController,
                  isRunning: isRunning,
                ),

                // Progress bar (when running)
                if (isRunning)
                  SequenceProgressBar(
                      key: SequencerTutorialKeys.progressBar, colors: colors),

                // Tab content
                Expanded(
                  child: AnimatedTabBarView(
                    controller: _tabController,
                    children: [
                      // Builder tab
                      _BuilderContent(colors: colors),
                      // Targets tab
                      const TargetsTab(),
                      // Templates tab
                      const TemplatesTab(),
                      // History tab
                      const HistoryTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
                indicator: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
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
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: colors.success.withValues(alpha: 0.3)),
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

class _BuilderContent extends ConsumerWidget {
  final NightshadeColors colors;

  const _BuilderContent({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return _MobileBuilderLayout(colors: colors);
    }
    return _DesktopBuilderLayout(colors: colors);
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
    _tabController = TabController(length: 2, vsync: this);
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
      final target = next ? 1 : 0;
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      ref.read(snippetPaletteVisibleProvider.notifier).state =
          _tabController.index == 1;
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
                    indicator: BoxDecoration(
                      color: widget.colors.primary.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
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
                    ],
                  ),
                ),
                if (widget.onCollapse != null)
                  Tooltip(
                    message: 'Collapse panel',
                    child: InkWell(
                      onTap: widget.onCollapse,
                      borderRadius: BorderRadius.circular(4),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Node palette content without header (used in toolbox tabs)
class _NodePaletteContent extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _NodePaletteContent({required this.colors});

  @override
  ConsumerState<_NodePaletteContent> createState() =>
      _NodePaletteContentState();
}

class _NodePaletteContentState extends ConsumerState<_NodePaletteContent> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'workflow':
        return LucideIcons.workflow;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'wrench':
        return LucideIcons.wrench;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      case 'aperture':
        return LucideIcons.aperture;
      default:
        return LucideIcons.box;
    }
  }

  Color _getCategoryColor(String categoryName) {
    switch (categoryName) {
      case 'Target':
        return widget.colors.warning;
      case 'Imaging':
        return widget.colors.primary;
      case 'Mount':
        return widget.colors.info;
      case 'Focus':
        return widget.colors.accent;
      case 'Camera':
        return widget.colors.primary;
      case 'Logic':
        return widget.colors.accent;
      case 'Timing':
        return widget.colors.warning;
      case 'Utilities':
        return widget.colors.textMuted;
      default:
        return widget.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(nodePaletteProvider);

    // Filter based on search
    final filteredCategories = categories
        .map((category) {
          if (_searchQuery.isEmpty) return category;

          final filteredItems = category.items
              .where((item) =>
                  item.name
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ||
                  item.description
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()))
              .toList();

          return NodePaletteCategory(
            name: category.name,
            icon: category.icon,
            items: filteredItems,
          );
        })
        .where((c) => c.items.isNotEmpty)
        .toList();

    final searchFontSize = Responsive.fontSize(context, 13);
    final searchIconSize = Responsive.iconSize(context, 15);
    final searchPadding = Responsive.spacing(context, 12);

    return Column(
      children: [
        // Search field
        Padding(
          padding: EdgeInsets.all(searchPadding),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: searchPadding),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: searchIconSize,
                  color: widget.colors.textMuted,
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(
                      fontSize: searchFontSize,
                      color: widget.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search nodes...',
                      hintStyle: TextStyle(
                        fontSize: searchFontSize,
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: Responsive.spacing(context, 10),
                      ),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(
                      LucideIcons.x,
                      size: searchIconSize,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Categories
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: Responsive.spacing(context, 8)),
              itemCount: filteredCategories.length,
              itemBuilder: (context, index) {
                final category = filteredCategories[index];
                return _NodeCategorySection(
                  category: category,
                  colors: widget.colors,
                  categoryColor: _getCategoryColor(category.name),
                  getIcon: _getIcon,
                );
              },
            ),
          ),
        ),

        // Help tip
        Container(
          padding: EdgeInsets.all(Responsive.spacing(context, 10)),
          margin: EdgeInsets.all(Responsive.spacing(context, 10)),
          decoration: BoxDecoration(
            color: widget.colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: widget.colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: Responsive.iconSize(context, 13),
                color: widget.colors.info,
              ),
              SizedBox(width: Responsive.spacing(context, 6)),
              Expanded(
                child: Text(
                  'Drag nodes or double-click to add',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: widget.colors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Node category section for the palette content
class _NodeCategorySection extends ConsumerStatefulWidget {
  final NodePaletteCategory category;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;

  const _NodeCategorySection({
    required this.category,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
  });

  @override
  ConsumerState<_NodeCategorySection> createState() =>
      _NodeCategorySectionState();
}

class _NodeCategorySectionState extends ConsumerState<_NodeCategorySection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final badgeSize = Responsive.spacing(context, 26);
    final badgeIconSize = Responsive.iconSize(context, 13);
    final categoryFontSize = Responsive.fontSize(context, 12);
    final chevronSize = Responsive.iconSize(context, 14);
    final hPadding = Responsive.spacing(context, 12);
    final vPadding = Responsive.spacing(context, 8);
    final itemPadding = Responsive.spacing(context, 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
            child: Row(
              children: [
                Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.getIcon(widget.category.icon),
                    size: badgeIconSize,
                    color: widget.categoryColor,
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: Text(
                    widget.category.name,
                    style: TextStyle(
                      fontSize: categoryFontSize,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.textPrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: chevronSize,
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Padding(
            padding: EdgeInsets.only(
                left: itemPadding, right: itemPadding, bottom: 4),
            child: Column(
              children: widget.category.items.map((item) {
                return _DraggableNodeItemCompact(
                  item: item,
                  colors: widget.colors,
                  categoryColor: widget.categoryColor,
                  getIcon: widget.getIcon,
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

/// Compact draggable node item for the toolbox
class _DraggableNodeItemCompact extends ConsumerStatefulWidget {
  final NodePaletteItem item;
  final NightshadeColors colors;
  final Color categoryColor;
  final IconData Function(String) getIcon;

  const _DraggableNodeItemCompact({
    required this.item,
    required this.colors,
    required this.categoryColor,
    required this.getIcon,
  });

  @override
  ConsumerState<_DraggableNodeItemCompact> createState() =>
      _DraggableNodeItemCompactState();
}

class _DraggableNodeItemCompactState
    extends ConsumerState<_DraggableNodeItemCompact> {
  bool _isHovered = false;

  void _addNode() {
    final node = widget.item.createNode();
    final selectedId = ref.read(selectedNodeIdProvider);
    final notifier = ref.read(currentSequenceProvider.notifier);
    notifier.addNode(
      node,
      parentId: selectedId,
    );

    // Add any pre-configured children (e.g. Autofocus inside HFR Triggered AF)
    final children = widget.item.createChildren?.call();
    if (children != null) {
      for (final child in children) {
        notifier.addNode(child, parentId: node.id);
      }
    }

    ref.read(selectedNodeIdProvider.notifier).state = node.id;
  }

  @override
  Widget build(BuildContext context) {
    final nameFontSize = Responsive.fontSize(context, 12);
    final descFontSize = Responsive.fontSize(context, 10);
    final feedbackFontSize = Responsive.fontSize(context, 12);
    final iconBoxSize = Responsive.spacing(context, 28);
    final itemIconSize = Responsive.iconSize(context, 14);
    final feedbackIconSize = Responsive.iconSize(context, 13);
    final plusIconSize = Responsive.iconSize(context, 12);
    final hPadding = Responsive.spacing(context, 10);
    final vPadding = Responsive.spacing(context, 8);

    return Draggable<NodePaletteItem>(
      data: widget.item,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 6),
          decoration: BoxDecoration(
            color: widget.categoryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: widget.categoryColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: widget.categoryColor.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.getIcon(widget.item.icon),
                  size: feedbackIconSize, color: widget.categoryColor),
              const SizedBox(width: 6),
              Text(
                widget.item.name,
                style: TextStyle(
                  fontSize: feedbackFontSize,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onDoubleTap: _addNode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(top: 3),
            padding:
                EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.colors.surfaceAlt
                  : widget.colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovered
                    ? widget.categoryColor.withValues(alpha: 0.5)
                    : widget.colors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.getIcon(widget.item.icon),
                    size: itemIconSize,
                    color: widget.categoryColor,
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: TextStyle(
                          fontSize: nameFontSize,
                          fontWeight: FontWeight.w500,
                          color: _isHovered
                              ? widget.colors.textPrimary
                              : widget.colors.textSecondary,
                        ),
                      ),
                      Text(
                        widget.item.description,
                        style: TextStyle(
                          fontSize: descFontSize,
                          color: widget.colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isHovered)
                  Icon(LucideIcons.plus,
                      size: plusIconSize, color: widget.categoryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Snippet palette content for the toolbox
class _SnippetPaletteContent extends ConsumerWidget {
  final NightshadeColors colors;

  const _SnippetPaletteContent({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SnippetPalette(
      colors: colors,
      onSnippetTap: (snippet) {
        // Insert the snippet when tapped/double-clicked
        final selectedId = ref.read(selectedNodeIdProvider);
        final profile = ref.read(activeEquipmentProfileProvider);
        ref.read(currentSequenceProvider.notifier).insertSnippet(
              snippet,
              parentId: selectedId,
              profileFilterNames: profile?.filterNames,
            );
      },
    );
  }
}

/// A panel that can collapse to a thin icon strip or expand to full content
class _CollapsiblePanel extends StatefulWidget {
  final NightshadeColors colors;
  final bool isCollapsed;
  final double collapsedWidth;
  final double expandedWidth;
  final double minExpandedWidth;
  final double maxExpandedWidth;
  final ResizeSide side;
  final IconData collapsedIcon;
  final String collapsedTooltip;
  final bool collapsedDisabled;
  final VoidCallback onToggle;
  final Widget child;

  const _CollapsiblePanel({
    required this.colors,
    required this.isCollapsed,
    required this.collapsedWidth,
    required this.expandedWidth,
    required this.minExpandedWidth,
    required this.maxExpandedWidth,
    required this.side,
    required this.collapsedIcon,
    required this.collapsedTooltip,
    this.collapsedDisabled = false,
    required this.onToggle,
    required this.child,
  });

  @override
  State<_CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<_CollapsiblePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;
  double _currentExpandedWidth = 0;

  @override
  void initState() {
    super.initState();
    _currentExpandedWidth = widget.expandedWidth;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _updateAnimation();
    if (!widget.isCollapsed) {
      _animationController.value = 1.0;
    }
  }

  void _updateAnimation() {
    _widthAnimation = Tween<double>(
      begin: widget.collapsedWidth,
      end: _currentExpandedWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_CollapsiblePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCollapsed != widget.isCollapsed) {
      if (widget.isCollapsed) {
        _animationController.reverse();
      } else {
        _currentExpandedWidth = widget.expandedWidth;
        _updateAnimation();
        _animationController.forward();
      }
    }
    if (oldWidget.expandedWidth != widget.expandedWidth &&
        !widget.isCollapsed) {
      _currentExpandedWidth = widget.expandedWidth;
      _updateAnimation();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        final width = _widthAnimation.value;
        final isEffectivelyCollapsed = width < widget.collapsedWidth + 20;

        if (isEffectivelyCollapsed) {
          // Collapsed state - show icon button strip
          return Container(
            width: widget.collapsedWidth,
            decoration: BoxDecoration(
              color: widget.colors.surface,
              border: Border(
                left: widget.side == ResizeSide.left
                    ? BorderSide(color: widget.colors.border)
                    : BorderSide.none,
                right: widget.side == ResizeSide.right
                    ? BorderSide(color: widget.colors.border)
                    : BorderSide.none,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Tooltip(
                  message: widget.collapsedTooltip,
                  child: IconButton(
                    icon: Icon(
                      widget.collapsedIcon,
                      size: 20,
                      color: widget.collapsedDisabled
                          ? widget.colors.textMuted
                          : widget.colors.textSecondary,
                    ),
                    onPressed:
                        widget.collapsedDisabled ? null : widget.onToggle,
                  ),
                ),
              ],
            ),
          );
        }

        // Expanded state - show resizable panel with content
        return SizedBox(
          width: width,
          child: ResizablePanel(
            initialWidth: width,
            minWidth: widget.minExpandedWidth,
            maxWidth: widget.maxExpandedWidth,
            side: widget.side,
            onWidthChanged: (newWidth) {
              setState(() {
                _currentExpandedWidth = newWidth;
                _updateAnimation();
              });
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Layout for very narrow desktop/tablet screens.
///
/// Per audit §4.7: below the minimum-width threshold we keep a thin
/// draggable icon-only rail on the left so users can still drag nodes
/// onto the tree. A "More..." button at the bottom of the rail opens the
/// full node palette sheet for search/discovery. The properties FAB is
/// preserved for editing the selected node.
class _NarrowDesktopLayout extends ConsumerWidget {
  final NightshadeColors colors;

  const _NarrowDesktopLayout({required this.colors});

  static const double _railWidth = 48.0;

  void _showNodePaletteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => NodePalette(
          colors: colors,
          scrollController: scrollController,
          isMobileSheet: true,
          onNodeAdded: () {
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  void _showPropertiesSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => NodePropertiesPanel(
          colors: colors,
          scrollController: scrollController,
          isMobileSheet: true,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final selectedNodeId = ref.watch(selectedNodeIdProvider);

    return Stack(
      children: [
        Row(
          children: [
            _NarrowNodePaletteRail(
              colors: colors,
              width: _railWidth,
              onShowFullPalette: () => _showNodePaletteSheet(context),
            ),
            Expanded(
              child:
                  SequenceTree(key: SequencerTutorialKeys.canvas, colors: colors),
            ),
          ],
        ),

        // Properties FAB — selecting a node still needs an editing affordance
        // on the narrow layout. The rail handles node insertion.
        if (selectedNodeId != null)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'narrow_properties_fab',
              backgroundColor: colors.accent,
              onPressed: () => _showPropertiesSheet(context, ref),
              child: Icon(
                LucideIcons.settings2,
                color: onPrimary,
                size: 20,
              ),
            ),
          ),
      ],
    );
  }
}

/// Vertical icon strip showing one draggable button per palette item,
/// for use under the narrow-desktop threshold (audit §4.7). Each icon is
/// a `Draggable<NodePaletteItem>` whose drop is accepted by the same
/// `DragTarget<Object>` in `sequence_tree.dart` that the expanded palette
/// uses, so insertion semantics are identical.
class _NarrowNodePaletteRail extends ConsumerWidget {
  final NightshadeColors colors;
  final double width;
  final VoidCallback onShowFullPalette;

  const _NarrowNodePaletteRail({
    required this.colors,
    required this.width,
    required this.onShowFullPalette,
  });

  IconData _resolveIcon(String iconName) {
    switch (iconName) {
      case 'target':
        return LucideIcons.target;
      case 'camera':
        return LucideIcons.camera;
      case 'circle':
        return LucideIcons.circle;
      case 'shuffle':
        return LucideIcons.shuffle;
      case 'compass':
        return LucideIcons.compass;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'parking-circle':
        return LucideIcons.parkingCircle;
      case 'unlock':
        return LucideIcons.unlock;
      case 'focus':
        return LucideIcons.focus;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'flame':
        return LucideIcons.flame;
      case 'rotate-cw':
        return LucideIcons.rotateCw;
      case 'workflow':
        return LucideIcons.workflow;
      case 'repeat':
        return LucideIcons.repeat;
      case 'git-merge':
        return LucideIcons.gitMerge;
      case 'git-branch':
        return LucideIcons.gitBranch;
      case 'shield-check':
        return LucideIcons.shieldCheck;
      case 'clock':
        return LucideIcons.clock;
      case 'timer':
        return LucideIcons.timer;
      case 'wrench':
        return LucideIcons.wrench;
      case 'bell':
        return LucideIcons.bell;
      case 'code':
        return LucideIcons.code;
      case 'aperture':
        return LucideIcons.aperture;
      case 'door-open':
        return LucideIcons.doorOpen;
      case 'door-closed':
        return LucideIcons.doorClosed;
      case 'lightbulb':
        return LucideIcons.lightbulb;
      case 'lightbulb-off':
        return LucideIcons.lightbulbOff;
      default:
        return LucideIcons.box;
    }
  }

  Color _categoryColor(String name) {
    switch (name) {
      case 'Target':
        return colors.warning;
      case 'Imaging':
        return colors.primary;
      case 'Mount':
        return colors.info;
      case 'Focus':
        return colors.accent;
      case 'Camera':
        return colors.primary;
      case 'Logic':
        return colors.accent;
      case 'Timing':
        return colors.warning;
      case 'Utilities':
        return colors.textMuted;
      case 'Flat Panel':
        return colors.warning;
      case 'Dome':
        return colors.info;
      case 'Guiding':
        return colors.primary;
      default:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(nodePaletteProvider);

    final flat = <({NodePaletteItem item, Color tint})>[
      for (final cat in categories)
        for (final item in cat.items)
          (item: item, tint: _categoryColor(cat.name)),
    ];

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: flat.length,
              itemBuilder: (context, index) {
                final entry = flat[index];
                return _RailDraggable(
                  item: entry.item,
                  tint: entry.tint,
                  icon: _resolveIcon(entry.item.icon),
                  colors: colors,
                );
              },
            ),
          ),
          Divider(height: 1, color: colors.border),
          Tooltip(
            message: 'More nodes…',
            child: IconButton(
              icon: Icon(
                LucideIcons.moreHorizontal,
                size: 18,
                color: colors.textSecondary,
              ),
              onPressed: onShowFullPalette,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailDraggable extends ConsumerStatefulWidget {
  final NodePaletteItem item;
  final Color tint;
  final IconData icon;
  final NightshadeColors colors;

  const _RailDraggable({
    required this.item,
    required this.tint,
    required this.icon,
    required this.colors,
  });

  @override
  ConsumerState<_RailDraggable> createState() => _RailDraggableState();
}

class _RailDraggableState extends ConsumerState<_RailDraggable> {
  bool _hovered = false;

  void _addNodeViaDoubleTap() {
    // Mirrors `_NodePaletteItem._addNode` in node_palette.dart so the rail
    // double-tap matches the expanded-palette insertion semantics.
    final node = widget.item.createNode();
    final selectedId = ref.read(selectedNodeIdProvider);
    final notifier = ref.read(currentSequenceProvider.notifier);
    notifier.addNode(node, parentId: selectedId);
    final children = widget.item.createChildren?.call();
    if (children != null) {
      for (final c in children) {
        notifier.addNode(c, parentId: node.id);
      }
    }
    ref.read(selectedNodeIdProvider.notifier).state = node.id;
  }

  @override
  Widget build(BuildContext context) {
    return Draggable<NodePaletteItem>(
      data: widget.item,
      onDragStarted: () =>
          ref.read(isDraggingNodeProvider.notifier).state = true,
      onDragEnd: (_) =>
          ref.read(isDraggingNodeProvider.notifier).state = false,
      onDraggableCanceled: (_, __) =>
          ref.read(isDraggingNodeProvider.notifier).state = false,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.tint.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.tint.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: widget.tint),
              const SizedBox(width: 6),
              Text(
                widget.item.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Tooltip(
        message: widget.item.name,
        waitDuration: const Duration(milliseconds: 300),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onDoubleTap: _addNodeViaDoubleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              height: 36,
              decoration: BoxDecoration(
                color: _hovered
                    ? widget.tint.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _hovered
                      ? widget.tint.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 18, color: widget.tint),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile layout: Full-screen tree with FAB and bottom sheets
class _MobileBuilderLayout extends ConsumerWidget {
  final NightshadeColors colors;

  const _MobileBuilderLayout({required this.colors});

  void _showNodePaletteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => NodePalette(
          colors: colors,
          scrollController: scrollController,
          isMobileSheet: true,
          onNodeAdded: () {
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  void _showPropertiesSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => NodePropertiesPanel(
          colors: colors,
          scrollController: scrollController,
          isMobileSheet: true,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;

    return Stack(
      children: [
        // Main content
        Column(
          children: [
            // Compact playback controls
            MobilePlaybackBar(colors: colors),

            // Progress bar (when running)
            if (isRunning)
              SequenceProgressBar(
                  key: SequencerTutorialKeys.progressBar, colors: colors),

            // Sequence tree - full width, scrollable
            Expanded(
              child: SequenceTree(
                colors: colors,
                isMobile: true,
                onNodeTap: (nodeId) {
                  ref.read(selectedNodeIdProvider.notifier).state = nodeId;
                  _showPropertiesSheet(context, ref);
                },
              ),
            ),
          ],
        ),

        // FAB for adding nodes
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Properties FAB (only when a node is selected)
              if (selectedNodeId != null) ...[
                FloatingActionButton.small(
                  heroTag: 'properties_fab',
                  backgroundColor: colors.accent,
                  onPressed: () => _showPropertiesSheet(context, ref),
                  child: Icon(
                    LucideIcons.settings2,
                    color: onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Add node FAB
              FloatingActionButton(
                heroTag: 'add_node_fab',
                backgroundColor: colors.primary,
                onPressed: () => _showNodePaletteSheet(context, ref),
                child: Icon(LucideIcons.plus, color: onPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
