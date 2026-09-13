part of '../sequence_tree.dart';

// The Ledger gutter map (spec §7).
//
// Comfortable and Compact keep the 80 px strip under the tree, toggled from
// the canvas bar. Ledger's whole promise is that the night fits on one screen,
// so its overview is always on and lives where the eye already is — a narrow
// column down the right edge of the tree's own viewport, drawn by the same
// painter the strip uses.

/// Identifies the gutter for tests.
const Key sequenceGutterMapKey = Key('sequence-tree-gutter-map');

/// The gutter's width: wide enough that a block reads as a block and the
/// viewport rectangle is grabbable, narrow enough to cost the tree nothing.
const double _gutterMapWidth = 34.0;

class _SequenceGutterMap extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ScrollController scrollController;

  const _SequenceGutterMap({
    super.key,
    required this.colors,
    required this.scrollController,
  });

  @override
  ConsumerState<_SequenceGutterMap> createState() => _SequenceGutterMapState();
}

class _SequenceGutterMapState extends ConsumerState<_SequenceGutterMap> {
  /// Where the finger went down, and where the tree was scrolled to then.
  ///
  /// The drag is a DELTA from that pair rather than an absolute y → offset
  /// mapping, so grabbing the viewport rectangle anywhere inside it keeps the
  /// tree exactly where it is instead of snapping the grab point to the
  /// rectangle's centre.
  double? _dragAnchorY;
  double _dragAnchorOffset = 0;

  @override
  Widget build(BuildContext context) {
    final sequence = ref.watch(currentSequenceProvider);
    final entries = sequence == null
        ? const <SequenceMapEntry>[]
        : sequenceMapEntries(sequence, ref.watch(visibleNodeOrderProvider));
    final progress = ref.watch(sequenceProgressProvider);
    final selectedId = ref.watch(selectedNodeIdProvider);

    return SizedBox(
      width: _gutterMapWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.colors.surface,
          border: Border(left: BorderSide(color: widget.colors.border)),
        ),
        child: entries.isEmpty
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => navigateToSequenceMapRow(
                    ref,
                    entries,
                    sequenceMapRowAt(
                      details.localPosition.dy,
                      constraints.maxHeight,
                      entries.length,
                    ),
                    widget.scrollController,
                  ),
                  onVerticalDragStart: (details) {
                    final metrics = sequenceMapMetrics(widget.scrollController);
                    if (metrics == null) return;
                    _dragAnchorY = details.localPosition.dy;
                    _dragAnchorOffset = metrics.offset;
                  },
                  onVerticalDragUpdate: (details) => _dragTo(
                    details.localPosition.dy,
                    constraints.maxHeight,
                  ),
                  onVerticalDragEnd: (_) => _dragAnchorY = null,
                  onVerticalDragCancel: () => _dragAnchorY = null,
                  child: AnimatedBuilder(
                    animation: widget.scrollController,
                    builder: (context, _) => Semantics(
                      slider: true,
                      label: 'Sequence overview',
                      value: _positionLabel(entries.length),
                      // The blocks are a picture of the tree, not a second
                      // copy of it: every row they stand for is already
                      // reachable in the tree's own traversal order.
                      excludeSemantics: true,
                      child: CustomPaint(
                        size: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                        painter: SequenceMapPainter(
                          colors: widget.colors,
                          entries: entries,
                          progress: progress,
                          selectedId: selectedId,
                          scrollController: widget.scrollController,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// Scroll the tree by the distance the finger has travelled down the gutter,
  /// scaled from gutter pixels to content pixels.
  void _dragTo(double localY, double extent) {
    final anchorY = _dragAnchorY;
    if (anchorY == null || extent <= 0) return;
    final metrics = sequenceMapMetrics(widget.scrollController);
    if (metrics == null) return;
    final contentExtent = metrics.maxScrollExtent + metrics.viewportDimension;
    final offset =
        _dragAnchorOffset + ((localY - anchorY) / extent) * contentExtent;
    widget.scrollController.jumpTo(
      offset.clamp(0.0, metrics.maxScrollExtent),
    );
  }

  /// What the slider currently reads: the row at the top of the viewport.
  String _positionLabel(int rowCount) {
    final metrics = sequenceMapMetrics(widget.scrollController);
    final contentExtent =
        (metrics?.maxScrollExtent ?? 0) + (metrics?.viewportDimension ?? 0);
    if (metrics == null || contentExtent <= 0) return 'row 1 of $rowCount';
    final row = sequenceMapRowAt(metrics.offset, contentExtent, rowCount);
    return 'row ${row + 1} of $rowCount';
  }
}
