import 'dart:ui';

/// Tracks rendered label bounding boxes to avoid overlap within a frame.
///
/// The v1 [`LabelLayoutManager`] tried to cache the spatial grid across
/// frames via `clearIfViewChanged`, but v1 painted into a single CustomPainter
/// so the OLD frame's painted labels were already on screen — keeping the
/// grid blocked re-registration in the SAME slot, which was correct for the
/// "stable across micro-pan" use case.
///
/// **v2 differs**: overlays are real widgets that rebuild from scratch every
/// frame. If the grid weren't cleared, every label would self-collide with
/// its own prior-frame rect and `findPlacement` would drop everything except
/// brand-new labels. So v2 clears unconditionally per build. The
/// `clearIfViewChanged` API is kept for source compatibility with v1 call
/// sites but now always clears.
class LabelLayoutManager {
  final List<Rect> _renderedLabels = <Rect>[];
  final Map<int, List<Rect>> _grid = <int, List<Rect>>{};
  static const double _cellSize = 96.0;

  /// Clear the layout grid unconditionally.
  void clear() {
    _renderedLabels.clear();
    _grid.clear();
  }

  /// Resets the grid before a new layout pass.
  ///
  /// View parameters are accepted for source-compatibility with v1 — they
  /// are not used to skip clearing in v2 (see class doc).
  bool clearIfViewChanged(double centerRA, double centerDec, double fov) {
    clear();
    return false;
  }

  int _cellKey(int x, int y) => Object.hash(x, y);

  Iterable<Rect> _nearbyRects(Rect rect) sync* {
    final minCellX = (rect.left / _cellSize).floor();
    final maxCellX = (rect.right / _cellSize).floor();
    final minCellY = (rect.top / _cellSize).floor();
    final maxCellY = (rect.bottom / _cellSize).floor();

    for (int x = minCellX - 1; x <= maxCellX + 1; x++) {
      for (int y = minCellY - 1; y <= maxCellY + 1; y++) {
        final bucket = _grid[_cellKey(x, y)];
        if (bucket == null) continue;
        yield* bucket;
      }
    }
  }

  void _register(Rect rect) {
    _renderedLabels.add(rect);

    final minCellX = (rect.left / _cellSize).floor();
    final maxCellX = (rect.right / _cellSize).floor();
    final minCellY = (rect.top / _cellSize).floor();
    final maxCellY = (rect.bottom / _cellSize).floor();

    for (int x = minCellX; x <= maxCellX; x++) {
      for (int y = minCellY; y <= maxCellY; y++) {
        _grid.putIfAbsent(_cellKey(x, y), () => <Rect>[]).add(rect);
      }
    }
  }

  /// Returns true if label can be placed without overlap.
  bool canPlace(Rect labelRect) {
    final paddedRect = labelRect.inflate(2);
    for (final existing in _nearbyRects(paddedRect)) {
      if (paddedRect.overlaps(existing)) return false;
    }
    return true;
  }

  /// Try to find placement near [preferred]; returns offset or null.
  ///
  /// Fallback offsets stay within `_maxFallbackPixels` of the preferred
  /// position so the label remains visually associated with its anchor.
  /// When no in-bounds, non-overlapping slot fits inside that radius, the
  /// label is dropped — this is how lower-priority labels yield to brighter
  /// ones in crowded star fields rather than "floating" 20+ px away from
  /// their actual source.
  Offset? findPlacement(Offset preferred, Size labelSize, Size canvasSize) {
    const offsets = <Offset>[
      Offset.zero,
      Offset(0, -_maxFallbackPixels),
      Offset(0, _maxFallbackPixels),
      Offset(_maxFallbackPixels, 0),
      Offset(-_maxFallbackPixels, 0),
    ];

    for (final delta in offsets) {
      final offset = preferred + delta;
      final rect = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        labelSize.width,
        labelSize.height,
      );
      if (canPlace(rect) && _isInBounds(rect, canvasSize)) {
        _register(rect);
        return offset;
      }
    }
    return null;
  }

  /// Maximum displacement (px) a label may move from its preferred anchor.
  ///
  /// Larger values pack more labels at the cost of weaker anchor association.
  /// 6 px matches one Material caption-line of slack — enough to clear
  /// `inflate(2)` padding plus a sibling glyph, not enough to "float."
  static const double _maxFallbackPixels = 6.0;

  bool _isInBounds(Rect rect, Size canvasSize) {
    return rect.left >= 0 &&
        rect.top >= 0 &&
        rect.right <= canvasSize.width &&
        rect.bottom <= canvasSize.height;
  }
}
