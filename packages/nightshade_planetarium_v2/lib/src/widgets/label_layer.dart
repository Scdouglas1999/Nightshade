import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../providers/scene_snapshot_provider.dart';
import '../rendering/label_layout_manager.dart';
import '../rendering/label_style.dart';

/// Screen-space object labels from the native renderer snapshot.
///
/// Consumes [sceneSnapshotProvider] label hints and places non-overlapping
/// [Text] widgets using the v1 [LabelLayoutManager] overlap resolution.
///
/// **Perf:** the snapshot watch is scoped to `(labels, viewPose)` via
/// [Provider.select] so unrelated snapshot fields (constellation art,
/// selection, frame id metadata) don't re-trigger layout. TextPainter
/// results are cached across rebuilds keyed on `(text, mag bucket,
/// category)` — the dominant cost at 10 k+ labels is `TextPainter.layout`,
/// and consecutive frames typically resize the same label set.
class LabelLayer extends ConsumerStatefulWidget {
  const LabelLayer({super.key});

  @override
  ConsumerState<LabelLayer> createState() => _LabelLayerState();
}

/// Cached layout result for `(displayText, mag bucket, category)`.
class _LabelMetrics {
  const _LabelMetrics(this.width, this.height);
  final double width;
  final double height;
}

class _LabelLayerState extends ConsumerState<LabelLayer> {
  final LabelLayoutManager _layoutManager = LabelLayoutManager();
  final Map<int, _LabelMetrics> _metricsCache = <int, _LabelMetrics>{};

  /// Bound the metrics cache so a long observing session that scrubs through
  /// thousands of unique labels doesn't grow it without bound. 8k entries
  /// covers a Tycho-2-class catalog visible at any one zoom level.
  static const int _maxCachedMetrics = 8192;

  @override
  Widget build(BuildContext context) {
    // Watch only the inputs we actually consume — labels, viewPose. Skipping
    // selected/constellationArt/frameId here means a selection click or
    // constellation-art-only delta does NOT relay out every label.
    final labels = ref.watch(
      sceneSnapshotProvider.select((s) => s.labels),
    );
    final pose = ref.watch(
      sceneSnapshotProvider.select((s) => s.viewPose),
    );

    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            if (canvasSize.width <= 0 || canvasSize.height <= 0) {
              return const SizedBox.shrink();
            }

            final centerRaHours = pose.raRad * 12 / math.pi;
            final centerDecDegrees = pose.decRad * 180 / math.pi;
            final fovDegrees = pose.fovRad * 180 / math.pi;
            _layoutManager.clearIfViewChanged(
              centerRaHours,
              centerDecDegrees,
              fovDegrees,
            );

            final placed = _placeLabels(labels, canvasSize);
            if (placed.isEmpty) {
              return const SizedBox.shrink();
            }

            return Stack(
              clipBehavior: Clip.none,
              children: placed,
            );
          },
        ),
      ),
    );
  }

  List<Widget> _placeLabels(List<LabelHintDto> labels, Size canvasSize) {
    if (labels.isEmpty) {
      return const <Widget>[];
    }

    // Sort highest-priority first WITHOUT reallocating when the input is
    // already in priority order (cheap fast-path for typical Rust snapshots).
    final sorted = _sortByPriorityDescending(labels);

    final children = <Widget>[];
    for (final hint in sorted) {
      if (hint.text.isEmpty) continue;

      // Off-canvas fast reject before any TextPainter work.
      if (hint.screenX < -64 ||
          hint.screenY < -64 ||
          hint.screenX > canvasSize.width + 64 ||
          hint.screenY > canvasSize.height + 64) {
        continue;
      }

      final displayText = labelDisplayText(hint);
      final style = labelTextStyleForHint(hint);

      final metrics = _measure(displayText, style, hint);
      final labelSize = Size(metrics.width, metrics.height);
      final anchor = Offset(hint.screenX, hint.screenY);
      final preferred = _preferredLabelOffset(
        hint: hint,
        anchor: anchor,
        labelSize: labelSize,
      );

      final placement = _layoutManager.findPlacement(
        preferred,
        labelSize,
        canvasSize,
      );
      if (placement == null) continue;

      children.add(
        Positioned(
          left: placement.dx,
          top: placement.dy,
          child: Text(displayText, style: style),
        ),
      );
    }
    return children;
  }

  List<LabelHintDto> _sortByPriorityDescending(List<LabelHintDto> labels) {
    var sorted = true;
    for (var i = 1; i < labels.length; i++) {
      if (labels[i - 1].priority < labels[i].priority) {
        sorted = false;
        break;
      }
    }
    if (sorted) {
      return labels;
    }
    return List<LabelHintDto>.of(labels)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  _LabelMetrics _measure(
    String displayText,
    TextStyle style,
    LabelHintDto hint,
  ) {
    final key = _metricsKey(displayText, hint);
    final cached = _metricsCache[key];
    if (cached != null) {
      return cached;
    }

    final painter = TextPainter(
      text: TextSpan(text: displayText, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final metrics = _LabelMetrics(painter.width, painter.height);
    painter.dispose();

    if (_metricsCache.length >= _maxCachedMetrics) {
      // Cheap LRU-ish eviction: clear half the cache when full. Avoids the
      // cost of tracking per-entry recency at this size.
      final keys = _metricsCache.keys.take(_metricsCache.length ~/ 2).toList();
      for (final k in keys) {
        _metricsCache.remove(k);
      }
    }
    _metricsCache[key] = metrics;
    return metrics;
  }

  /// Cache key folds magnitude into 0.5-mag buckets so glyphs sharing both
  /// text and a style bucket reuse the same TextPainter layout result.
  int _metricsKey(String displayText, LabelHintDto hint) {
    final magBucket = (hint.apparentMag * 2).round();
    return Object.hash(displayText, magBucket, hint.category);
  }

  Offset _preferredLabelOffset({
    required LabelHintDto hint,
    required Offset anchor,
    required Size labelSize,
  }) {
    return switch (hint.category) {
      LabelCategoryDto.constellation =>
        anchor - Offset(labelSize.width / 2, labelSize.height / 2),
      LabelCategoryDto.body => anchor + Offset(-labelSize.width / 2, 4),
      LabelCategoryDto.dso => anchor + Offset(3, -labelSize.height / 2),
      _ => anchor + Offset(3, -labelSize.height / 2),
    };
  }
}
