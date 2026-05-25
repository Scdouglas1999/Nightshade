import 'dart:ui';

/// Tracks rendered label bounding boxes to avoid overlap.
///
/// Caches its spatial grid across frames when the view hasn't moved
/// significantly. Only rebuilds when view center moves >0.5 degrees
/// or zoom changes >5%.
///
/// Ported from v1 [`LabelLayoutManager`] in `nightshade_planetarium`.
class LabelLayoutManager {
  final List<Rect> _renderedLabels = [];
  final Map<int, List<Rect>> _grid = <int, List<Rect>>{};
  static const double _cellSize = 96.0;

  double _cachedCenterRA = double.nan;
  double _cachedCenterDec = double.nan;
  double _cachedFOV = double.nan;
  bool _cacheValid = false;

  /// Clear the layout grid unconditionally.
  void clear() {
    _renderedLabels.clear();
    _grid.clear();
    _cacheValid = false;
  }

  /// Conditionally clear the layout grid based on view movement.
  ///
  /// [centerRA] is right ascension in hours (0–24).
  /// [centerDec] is declination in degrees.
  /// [fov] is field of view in degrees.
  ///
  /// Returns true if the cache was valid and reused, false if it was cleared.
  bool clearIfViewChanged(double centerRA, double centerDec, double fov) {
    if (_cacheValid) {
      final raDelta = (centerRA - _cachedCenterRA).abs();
      final decDelta = (centerDec - _cachedCenterDec).abs();
      final fovRatio = _cachedFOV > 0 ? (fov / _cachedFOV) : 0.0;

      final raWrapped = raDelta > 12 ? 24 - raDelta : raDelta;
      final raDeg = raWrapped * 15.0;

      if (raDeg < 0.5 && decDelta < 0.5 && fovRatio > 0.95 && fovRatio < 1.05) {
        return true;
      }
    }

    _renderedLabels.clear();
    _grid.clear();
    _cachedCenterRA = centerRA;
    _cachedCenterDec = centerDec;
    _cachedFOV = fov;
    _cacheValid = true;
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
