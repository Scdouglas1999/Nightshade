part of '../sequencer_screen.dart';

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
              // _RailDraggable is a fixed 36h tile + 3+3 vertical margin = 42.
              itemExtent: 42,
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
          decoration: NightshadeDecorations.selectedSurface(
            widget.tint,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            fillAlpha: 0.2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: widget.tint),
              const SizedBox(width: 6),
              Text(
                widget.item.name,
                style: NightshadeTypography.labelSm.copyWith(color: widget.colors.textPrimary),
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
                    ? NightshadeDecorations.tintedBadge(
                        widget.tint,
                        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                      ).color
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
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
