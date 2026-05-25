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
class LabelLayer extends ConsumerStatefulWidget {
  const LabelLayer({super.key});

  @override
  ConsumerState<LabelLayer> createState() => _LabelLayerState();
}

class _LabelLayerState extends ConsumerState<LabelLayer> {
  final LabelLayoutManager _layoutManager = LabelLayoutManager();

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(sceneSnapshotProvider);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (canvasSize.width <= 0 || canvasSize.height <= 0) {
            return const SizedBox.shrink();
          }

          final pose = snapshot.viewPose;
          final centerRaHours = pose.raRad * 12 / math.pi;
          final centerDecDegrees = pose.decRad * 180 / math.pi;
          final fovDegrees = pose.fovRad * 180 / math.pi;
          _layoutManager.clearIfViewChanged(
            centerRaHours,
            centerDecDegrees,
            fovDegrees,
          );

          final placed = _placeLabels(snapshot.labels, canvasSize);
          if (placed.isEmpty) {
            return const SizedBox.shrink();
          }

          return Stack(
            clipBehavior: Clip.none,
            children: placed,
          );
        },
      ),
    );
  }

  List<Widget> _placeLabels(List<LabelHintDto> labels, Size canvasSize) {
    final sorted = List<LabelHintDto>.from(labels)
      ..sort((a, b) => b.priority.compareTo(a.priority));

    final children = <Widget>[];
    for (final hint in sorted) {
      if (hint.text.isEmpty) continue;

      final displayText = labelDisplayText(hint);
      final style = labelTextStyleForHint(hint);
      final painter = TextPainter(
        text: TextSpan(text: displayText, style: style),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final labelSize = Size(painter.width, painter.height);
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

  Offset _preferredLabelOffset({
    required LabelHintDto hint,
    required Offset anchor,
    required Size labelSize,
  }) {
    return switch (hint.category) {
      LabelCategoryDto.constellation => anchor -
          Offset(labelSize.width / 2, labelSize.height / 2),
      LabelCategoryDto.body => anchor +
          Offset(-labelSize.width / 2, 4),
      LabelCategoryDto.dso => anchor +
          Offset(3, -labelSize.height / 2),
      _ => anchor + Offset(3, -labelSize.height / 2),
    };
  }
}
