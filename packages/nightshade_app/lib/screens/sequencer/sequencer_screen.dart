import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/animated_tab_bar_view.dart';
import '../../widgets/tutorial_keys/sequencer_keys.dart';
import 'widgets/sequence_toolbar.dart';
import 'widgets/node_palette.dart';
import 'widgets/sequence_tree.dart';
import 'widgets/node_properties_panel.dart';
import 'widgets/sequence_progress_bar.dart';
import 'widgets/mobile_playback_bar.dart';
import 'tabs/targets_tab.dart';
import 'tabs/templates_tab.dart';

/// Currently selected sequencer tab
final sequencerTabProvider = StateProvider<int>((ref) => 0);

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

    return FadeTransition(
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

/// Desktop layout: 3-column with resizable panels
/// Adapts to screen width by collapsing panels on narrower screens
class _DesktopBuilderLayout extends StatelessWidget {
  final NightshadeColors colors;

  const _DesktopBuilderLayout({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top toolbar
        SequenceToolbar(key: SequencerTutorialKeys.toolbar, colors: colors),

        // Main content - use LayoutBuilder to adapt to available width
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Minimum center width to ensure text displays properly
              const minCenterWidth = 300.0;
              // Panel widths
              const leftPanelWidth = 260.0;
              const rightPanelWidth = 320.0;
              const leftPanelMinWidth = 200.0;
              const rightPanelMinWidth = 250.0;

              // Calculate what layout mode we should use based on available width
              final availableWidth = constraints.maxWidth;

              // Thresholds for layout modes
              // Full: both panels visible at initial sizes
              // Compact: both panels at minimum sizes
              // SinglePanel: only one panel visible
              // NoPanels: no side panels, use mobile-style overlays
              const fullLayoutWidth = leftPanelWidth + minCenterWidth + rightPanelWidth;
              const compactLayoutWidth = leftPanelMinWidth + minCenterWidth + rightPanelMinWidth;
              const singlePanelWidth = leftPanelMinWidth + minCenterWidth;

              // Determine layout mode
              final showBothPanels = availableWidth >= compactLayoutWidth;
              final showLeftPanel = availableWidth >= singlePanelWidth;

              if (!showLeftPanel) {
                // Very narrow: Show only sequence tree with FAB overlays
                return _NarrowDesktopLayout(colors: colors);
              }

              if (!showBothPanels) {
                // Medium narrow: Show left panel and sequence tree only
                return Row(
                  children: [
                    // Node palette (left)
                    ResizablePanel(
                      initialWidth: leftPanelMinWidth,
                      minWidth: leftPanelMinWidth,
                      maxWidth: 350,
                      side: ResizeSide.right,
                      child: NodePalette(key: SequencerTutorialKeys.nodePalette, colors: colors),
                    ),
                    // Sequence tree (center) with minimum width
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: minCenterWidth),
                        child: SequenceTree(key: SequencerTutorialKeys.canvas, colors: colors),
                      ),
                    ),
                  ],
                );
              }

              // Full layout: both panels visible
              // Calculate responsive panel widths
              final leftWidth = availableWidth >= fullLayoutWidth
                  ? leftPanelWidth
                  : leftPanelMinWidth;
              final rightWidth = availableWidth >= fullLayoutWidth
                  ? rightPanelWidth
                  : rightPanelMinWidth;

              return Row(
                children: [
                  // Node palette (left)
                  ResizablePanel(
                    initialWidth: leftWidth,
                    minWidth: leftPanelMinWidth,
                    maxWidth: 400,
                    side: ResizeSide.right,
                    child: NodePalette(key: SequencerTutorialKeys.nodePalette, colors: colors),
                  ),

                  // Sequence tree (center) with minimum width constraint
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: minCenterWidth),
                      child: SequenceTree(key: SequencerTutorialKeys.canvas, colors: colors),
                    ),
                  ),

                  // Properties panel (right)
                  ResizablePanel(
                    initialWidth: rightWidth,
                    minWidth: rightPanelMinWidth,
                    maxWidth: 500,
                    side: ResizeSide.left,
                    child: NodePropertiesPanel(key: SequencerTutorialKeys.propertiesPanel, colors: colors),
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
