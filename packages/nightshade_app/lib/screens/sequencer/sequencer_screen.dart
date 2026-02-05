import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/animated_tab_bar_view.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/sequencer_keys.dart';
import 'widgets/sequence_toolbar.dart';
import 'widgets/node_palette.dart';
import 'widgets/snippet_palette.dart';
import 'widgets/sequence_tree.dart';
import 'widgets/node_properties_panel.dart';
import 'widgets/sequence_progress_bar.dart';
import 'widgets/mobile_playback_bar.dart';
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
final sequencerPropertiesCollapsedProvider = StateProvider<bool>((ref) => false);

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

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(sequencerTabProvider.notifier).state = _tabController.index;
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
    final currentTab = ref.watch(sequencerTabProvider);

    // Sync tab controller with provider
    if (_tabController.index != currentTab) {
      _tabController.animateTo(currentTab);
    }

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
                final selectedId = ref.read(selectedNodeIdProvider);
                if (selectedId != null) {
                  ref.read(currentSequenceProvider.notifier).removeNode(selectedId);
                  ref.read(selectedNodeIdProvider.notifier).state = null;
                }
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
              if (currentTab == 0) {
                final selectedId = ref.read(selectedNodeIdProvider);
                if (selectedId != null) {
                  ref.read(currentSequenceProvider.notifier).duplicateNode(selectedId);
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
            // Ctrl+T (or Cmd+T on Mac) to toggle snippet palette visibility
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              if (currentTab == 0) {
                final current = ref.read(snippetPaletteVisibleProvider);
                ref.read(snippetPaletteVisibleProvider.notifier).state = !current;
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
                  SequenceProgressBar(key: SequencerTutorialKeys.progressBar, colors: colors),

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
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.success.withValues(alpha: 0.3)),
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

  // Panel dimension constants
  static const double minCenterWidth = 300.0;
  static const double leftPanelExpandedWidth = 260.0;
  static const double rightPanelExpandedWidth = 320.0;
  static const double leftPanelMinWidth = 200.0;
  static const double rightPanelMinWidth = 250.0;
  static const double collapsedPanelWidth = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolboxCollapsed = ref.watch(sequencerToolboxCollapsedProvider);
    final propertiesCollapsed = ref.watch(sequencerPropertiesCollapsedProvider);
    final selectedNodeId = ref.watch(selectedNodeIdProvider);

    return Column(
      children: [
        // Top toolbar
        SequenceToolbar(key: SequencerTutorialKeys.toolbar, colors: colors),

        // Main content - use LayoutBuilder to adapt to available width
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;

              // Calculate space needed for different configurations
              const bothExpandedWidth = leftPanelExpandedWidth + minCenterWidth + rightPanelExpandedWidth;
              const bothCollapsedMinWidth = collapsedPanelWidth + minCenterWidth + collapsedPanelWidth;

              // On very narrow screens, use FAB overlays instead
              if (availableWidth < bothCollapsedMinWidth) {
                return _NarrowDesktopLayout(colors: colors);
              }

              // Determine if we need to force collapse based on space
              // If not enough space for both expanded, auto-collapse based on context
              final needsCollapse = availableWidth < bothExpandedWidth;

              // Auto-collapse logic: if space is tight, collapse one panel
              // Prefer keeping properties open if a node is selected
              bool effectiveToolboxCollapsed = toolboxCollapsed;
              bool effectivePropertiesCollapsed = propertiesCollapsed;

              if (needsCollapse && !toolboxCollapsed && !propertiesCollapsed) {
                // Not enough space and neither is collapsed - auto-collapse one
                if (selectedNodeId != null) {
                  // Node selected - collapse toolbox to show properties
                  effectiveToolboxCollapsed = true;
                } else {
                  // No node selected - collapse properties to show toolbox
                  effectivePropertiesCollapsed = true;
                }
              }

              return Row(
                children: [
                  // Left panel - Toolbox (Node Palette + Snippet Palette)
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectiveToolboxCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: effectivePropertiesCollapsed
                        ? leftPanelExpandedWidth
                        : leftPanelMinWidth,
                    minExpandedWidth: leftPanelMinWidth,
                    maxExpandedWidth: 400,
                    side: ResizeSide.right,
                    collapsedIcon: LucideIcons.layoutGrid,
                    collapsedTooltip: 'Show Toolbox',
                    onToggle: () {
                      final wasCollapsed = ref.read(sequencerToolboxCollapsedProvider);
                      ref.read(sequencerToolboxCollapsedProvider.notifier).state = !wasCollapsed;
                      // If expanding toolbox on tight screen, collapse properties
                      if (wasCollapsed && needsCollapse) {
                        ref.read(sequencerPropertiesCollapsedProvider.notifier).state = true;
                      }
                    },
                    child: _ToolboxPanel(
                      key: SequencerTutorialKeys.nodePalette,
                      colors: colors,
                      onCollapse: () {
                        ref.read(sequencerToolboxCollapsedProvider.notifier).state = true;
                      },
                    ),
                  ),

                  // Center - Sequence Tree
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: minCenterWidth),
                      child: SequenceTree(key: SequencerTutorialKeys.canvas, colors: colors),
                    ),
                  ),

                  // Right panel - Properties
                  _CollapsiblePanel(
                    colors: colors,
                    isCollapsed: effectivePropertiesCollapsed,
                    collapsedWidth: collapsedPanelWidth,
                    expandedWidth: effectiveToolboxCollapsed
                        ? rightPanelExpandedWidth
                        : rightPanelMinWidth,
                    minExpandedWidth: rightPanelMinWidth,
                    maxExpandedWidth: 500,
                    side: ResizeSide.left,
                    collapsedIcon: LucideIcons.settings2,
                    collapsedTooltip: selectedNodeId != null
                        ? 'Show Properties'
                        : 'No Node Selected',
                    collapsedDisabled: selectedNodeId == null,
                    onToggle: () {
                      if (selectedNodeId == null) return; // Can't expand without selection
                      final wasCollapsed = ref.read(sequencerPropertiesCollapsedProvider);
                      ref.read(sequencerPropertiesCollapsedProvider.notifier).state = !wasCollapsed;
                      // If expanding properties on tight screen, collapse toolbox
                      if (wasCollapsed && needsCollapse) {
                        ref.read(sequencerToolboxCollapsedProvider.notifier).state = true;
                      }
                    },
                    child: NodePropertiesPanel(
                      key: SequencerTutorialKeys.propertiesPanel,
                      colors: colors,
                      onCollapse: () {
                        ref.read(sequencerPropertiesCollapsedProvider.notifier).state = true;
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
    // Sync with provider state
    final showSnippets = ref.read(snippetPaletteVisibleProvider);
    if (showSnippets) {
      _tabController.animateTo(1);
    }
    _tabController.addListener(_onTabChanged);
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
    // Watch provider to sync tabs
    final showSnippets = ref.watch(snippetPaletteVisibleProvider);
    if (_tabController.index != (showSnippets ? 1 : 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tabController.animateTo(showSnippets ? 1 : 0);
        }
      });
    }

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
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(
                        height: 32,
                        child: Text('Nodes'),
                      ),
                      Tab(
                        height: 32,
                        child: Text('Snippets'),
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
  ConsumerState<_NodePaletteContent> createState() => _NodePaletteContentState();
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
      case 'target': return LucideIcons.target;
      case 'camera': return LucideIcons.camera;
      case 'circle': return LucideIcons.circle;
      case 'shuffle': return LucideIcons.shuffle;
      case 'compass': return LucideIcons.compass;
      case 'crosshair': return LucideIcons.crosshair;
      case 'parking-circle': return LucideIcons.parkingCircle;
      case 'unlock': return LucideIcons.unlock;
      case 'focus': return LucideIcons.focus;
      case 'snowflake': return LucideIcons.snowflake;
      case 'flame': return LucideIcons.flame;
      case 'rotate-cw': return LucideIcons.rotateCw;
      case 'workflow': return LucideIcons.workflow;
      case 'repeat': return LucideIcons.repeat;
      case 'git-merge': return LucideIcons.gitMerge;
      case 'git-branch': return LucideIcons.gitBranch;
      case 'shield-check': return LucideIcons.shieldCheck;
      case 'clock': return LucideIcons.clock;
      case 'timer': return LucideIcons.timer;
      case 'wrench': return LucideIcons.wrench;
      case 'bell': return LucideIcons.bell;
      case 'code': return LucideIcons.code;
      case 'aperture': return LucideIcons.aperture;
      default: return LucideIcons.box;
    }
  }

  Color _getCategoryColor(String categoryName) {
    switch (categoryName) {
      case 'Target': return widget.colors.warning;
      case 'Imaging': return widget.colors.primary;
      case 'Mount': return widget.colors.info;
      case 'Focus': return widget.colors.accent;
      case 'Camera': return widget.colors.primary;
      case 'Logic': return widget.colors.accent;
      case 'Timing': return widget.colors.warning;
      case 'Utilities': return widget.colors.textMuted;
      default: return widget.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(nodePaletteProvider);

    // Filter based on search
    final filteredCategories = categories.map((category) {
      if (_searchQuery.isEmpty) return category;

      final filteredItems = category.items
          .where((item) =>
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              item.description.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();

      return NodePaletteCategory(
        name: category.name,
        icon: category.icon,
        items: filteredItems,
      );
    }).where((c) => c.items.isNotEmpty).toList();

    return Column(
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 14,
                  color: widget.colors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search nodes...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                      size: 14,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Categories
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
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

        // Help tip
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: 12,
                color: widget.colors.info,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Drag nodes or double-click to add',
                  style: TextStyle(
                    fontSize: 9,
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
  ConsumerState<_NodeCategorySection> createState() => _NodeCategorySectionState();
}

class _NodeCategorySectionState extends ConsumerState<_NodeCategorySection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    widget.getIcon(widget.category.icon),
                    size: 11,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.category.name,
                    style: TextStyle(
                      fontSize: 11,
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
                    size: 12,
                    color: widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
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
    ref.read(currentSequenceProvider.notifier).addNode(
      node,
      parentId: selectedId,
    );
    ref.read(selectedNodeIdProvider.notifier).state = node.id;
  }

  @override
  Widget build(BuildContext context) {
    return Draggable<NodePaletteItem>(
      data: widget.item,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.categoryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: widget.categoryColor.withValues(alpha: 0.5)),
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
              Icon(widget.getIcon(widget.item.icon), size: 12, color: widget.categoryColor),
              const SizedBox(width: 6),
              Text(
                widget.item.name,
                style: TextStyle(
                  fontSize: 11,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    widget.getIcon(widget.item.icon),
                    size: 12,
                    color: widget.categoryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _isHovered
                              ? widget.colors.textPrimary
                              : widget.colors.textSecondary,
                        ),
                      ),
                      Text(
                        widget.item.description,
                        style: TextStyle(
                          fontSize: 8,
                          color: widget.colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isHovered)
                  Icon(LucideIcons.plus, size: 10, color: widget.categoryColor),
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
        ref.read(currentSequenceProvider.notifier).insertSnippet(
          snippet,
          parentId: selectedId,
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
    if (oldWidget.expandedWidth != widget.expandedWidth && !widget.isCollapsed) {
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
                    onPressed: widget.collapsedDisabled ? null : widget.onToggle,
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
              _currentExpandedWidth = newWidth;
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Layout for very narrow desktop/tablet screens
/// Shows only the sequence tree with FAB buttons for accessing panels
class _NarrowDesktopLayout extends ConsumerWidget {
  final NightshadeColors colors;

  const _NarrowDesktopLayout({required this.colors});

  void _showNodePaletteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    final selectedNodeId = ref.watch(selectedNodeIdProvider);

    return Stack(
      children: [
        // Sequence tree - full width
        SequenceTree(key: SequencerTutorialKeys.canvas, colors: colors),

        // FABs for accessing panels
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Properties FAB (only when a node is selected)
              if (selectedNodeId != null) ...[
                FloatingActionButton.small(
                  heroTag: 'narrow_properties_fab',
                  backgroundColor: colors.accent,
                  onPressed: () => _showPropertiesSheet(context, ref),
                  child: const Icon(LucideIcons.settings2, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 12),
              ],
              // Add node FAB
              FloatingActionButton(
                heroTag: 'narrow_add_node_fab',
                backgroundColor: colors.primary,
                onPressed: () => _showNodePaletteSheet(context),
                child: const Icon(LucideIcons.plus, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            if (isRunning) SequenceProgressBar(key: SequencerTutorialKeys.progressBar, colors: colors),

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
                  child: const Icon(LucideIcons.settings2, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 12),
              ],
              // Add node FAB
              FloatingActionButton(
                heroTag: 'add_node_fab',
                backgroundColor: colors.primary,
                onPressed: () => _showNodePaletteSheet(context, ref),
                child: const Icon(LucideIcons.plus, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
