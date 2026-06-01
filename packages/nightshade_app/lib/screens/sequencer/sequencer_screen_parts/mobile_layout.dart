part of '../sequencer_screen.dart';

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
            // File/edit actions (New, Open, Save, Undo) — desktop builder has
            // SequenceToolbar; mobile remote clients need the same affordances.
            SequenceToolbar(key: SequencerTutorialKeys.toolbar, colors: colors),

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
