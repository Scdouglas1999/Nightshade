import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/animated_tab_bar_view.dart';
import 'widgets/sequence_toolbar.dart';
import 'widgets/node_palette.dart';
import 'widgets/sequence_tree.dart';
import 'widgets/node_properties_panel.dart';
import 'widgets/sequence_progress_bar.dart';
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
                SequenceProgressBar(colors: colors),

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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Tab buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.workflow, size: 16),
                      SizedBox(width: 8),
                      Text('Builder'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.target, size: 16),
                      SizedBox(width: 8),
                      Text('Targets'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.fileStack, size: 16),
                      SizedBox(width: 8),
                      Text('Templates'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Running indicator
          if (isRunning)
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

class _BuilderContent extends StatelessWidget {
  final NightshadeColors colors;

  const _BuilderContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top toolbar
        SequenceToolbar(colors: colors),

        // Main content
        Expanded(
          child: Row(
            children: [
              // Node palette (left)
              ResizablePanel(
                initialWidth: 260,
                minWidth: 200,
                maxWidth: 400,
                side: ResizeSide.right,
                child: NodePalette(colors: colors),
              ),

              // Sequence tree (center)
              Expanded(
                child: SequenceTree(colors: colors),
              ),

              // Properties panel (right)
              ResizablePanel(
                initialWidth: 320,
                minWidth: 250,
                maxWidth: 500,
                side: ResizeSide.left,
                child: NodePropertiesPanel(colors: colors),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
