import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Toggle for mini-map visibility.
final minimapVisibleProvider = StateProvider<bool>((ref) => false);

/// A small thumbnail overview of the sequence tree, rendered as colored blocks.
/// Shows a viewport indicator for the currently visible region and highlights
/// the executing node. Click to navigate to that position in the tree.
class SequenceMinimap extends ConsumerWidget {
  final NightshadeColors colors;
  final ScrollController scrollController;

  const SequenceMinimap({
    super.key,
    required this.colors,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequence = ref.watch(currentSequenceProvider);
    if (sequence == null || sequence.rootNode == null) {
      return const SizedBox.shrink();
    }

    final progress = ref.watch(sequenceProgressProvider);
    final selectedId = ref.watch(selectedNodeIdProvider);

    // Flatten the tree into a list of (node, depth) pairs for rendering
    final flatNodes = <_MinimapEntry>[];
    _flattenTree(sequence, sequence.rootNode!.id, 0, flatNodes);

    if (flatNodes.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (details) {
              _navigateToPosition(
                details.localPosition.dy,
                constraints.maxHeight,
                flatNodes,
                ref,
              );
            },
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _MinimapPainter(
                colors: colors,
                flatNodes: flatNodes,
                progress: progress,
                selectedId: selectedId,
                scrollController: scrollController,
              ),
            ),
          );
        },
      ),
    );
  }

  void _flattenTree(
    Sequence sequence,
    String nodeId,
    int depth,
    List<_MinimapEntry> output,
  ) {
    final node = sequence.nodes[nodeId];
    if (node == null) return;

    output.add(_MinimapEntry(node: node, depth: depth));

    for (final childId in node.childIds) {
      _flattenTree(sequence, childId, depth + 1, output);
    }
  }

  void _navigateToPosition(
    double tapY,
    double totalHeight,
    List<_MinimapEntry> flatNodes,
    WidgetRef ref,
  ) {
    if (flatNodes.isEmpty) return;

    // Map tap position to a node index
    final nodeIndex =
        (tapY / totalHeight * flatNodes.length).floor().clamp(0, flatNodes.length - 1);
    final tappedNode = flatNodes[nodeIndex].node;

    // Select the node
    ref.read(multiSelectedNodeIdsProvider.notifier).clear();
    ref.read(selectedNodeIdProvider.notifier).state = tappedNode.id;

    // Scroll the main tree to show this node
    if (scrollController.hasClients) {
      final maxScroll = scrollController.position.maxScrollExtent;
      final targetScroll = maxScroll * (nodeIndex / flatNodes.length);
      scrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
}

class _MinimapEntry {
  final SequenceNode node;
  final int depth;

  _MinimapEntry({required this.node, required this.depth});
}

class _MinimapPainter extends CustomPainter {
  final NightshadeColors colors;
  final List<_MinimapEntry> flatNodes;
  final SequenceProgress progress;
  final String? selectedId;
  final ScrollController scrollController;

  _MinimapPainter({
    required this.colors,
    required this.flatNodes,
    required this.progress,
    required this.selectedId,
    required this.scrollController,
  }) : super(repaint: scrollController);

  @override
  void paint(Canvas canvas, Size size) {
    if (flatNodes.isEmpty) return;

    final nodeHeight = size.height / flatNodes.length;
    final maxDepth = flatNodes.fold<int>(
        0, (max, entry) => entry.depth > max ? entry.depth : max);
    final depthWidth = maxDepth > 0 ? size.width * 0.15 : 0.0;

    // Draw node blocks
    for (int i = 0; i < flatNodes.length; i++) {
      final entry = flatNodes[i];
      final y = i * nodeHeight;
      final indent = maxDepth > 0
          ? (entry.depth / (maxDepth + 1)) * depthWidth
          : 0.0;

      // Determine color based on node category
      Color blockColor;
      switch (entry.node.category) {
        case NodeCategory.instruction:
          blockColor = colors.primary;
          break;
        case NodeCategory.trigger:
          blockColor = colors.warning;
          break;
        case NodeCategory.logic:
          blockColor = colors.accent;
          break;
        case NodeCategory.target:
          blockColor = colors.warning;
          break;
      }

      // Dim disabled nodes
      if (!entry.node.isEnabled) {
        blockColor = blockColor.withValues(alpha: 0.2);
      }

      // Highlight based on execution status
      final nodeStatus = progress.nodeStatuses[entry.node.id];
      if (nodeStatus == NodeStatus.running) {
        blockColor = colors.info;
      } else if (nodeStatus == NodeStatus.success) {
        blockColor = colors.success.withValues(alpha: 0.7);
      } else if (nodeStatus == NodeStatus.failure) {
        blockColor = colors.error;
      }

      final rect = Rect.fromLTWH(
        indent,
        y,
        size.width - indent,
        (nodeHeight - 1).clamp(1, double.infinity),
      );

      canvas.drawRect(
        rect,
        Paint()
          ..color = blockColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.fill,
      );

      // Highlight selected node
      if (entry.node.id == selectedId) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Draw viewport indicator
    if (scrollController.hasClients &&
        scrollController.position.maxScrollExtent > 0) {
      final maxScroll = scrollController.position.maxScrollExtent;
      final viewportHeight = scrollController.position.viewportDimension;
      final totalContentHeight = maxScroll + viewportHeight;

      final viewportTop =
          (scrollController.offset / totalContentHeight) * size.height;
      final viewportSize =
          (viewportHeight / totalContentHeight) * size.height;

      final viewportRect = Rect.fromLTWH(
        0,
        viewportTop,
        size.width,
        viewportSize.clamp(8, size.height),
      );

      // Semi-transparent overlay outside viewport
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, viewportTop),
        Paint()
          ..color = colors.background.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Rect.fromLTWH(
            0, viewportTop + viewportSize, size.width, size.height),
        Paint()
          ..color = colors.background.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill,
      );

      // Viewport border
      canvas.drawRect(
        viewportRect,
        Paint()
          ..color = colors.primary.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Draw current execution position line
    if (progress.currentNodeId != null) {
      final execIndex = flatNodes
          .indexWhere((e) => e.node.id == progress.currentNodeId);
      if (execIndex >= 0) {
        final y = execIndex * nodeHeight + nodeHeight / 2;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = colors.info
            ..strokeWidth = 2.0,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) {
    return oldDelegate.flatNodes != flatNodes ||
        oldDelegate.progress != progress ||
        oldDelegate.selectedId != selectedId;
  }
}
