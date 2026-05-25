import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/constellation_art_placements_provider.dart';
import '../providers/render_config_provider.dart';
import '../providers/scene_snapshot_provider.dart';
import '../rendering/constellation_art_painter.dart';

/// Screen-space constellation art overlays from the native scene snapshot.
///
/// Consumes [constellationArtPlacementsProvider] (empty until Task 74 populates
/// the snapshot) and draws curated procedural figures when
/// [RenderConfigState.showConstellationArt] is enabled.
class ConstellationArtLayer extends ConsumerWidget {
  const ConstellationArtLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(renderConfigProvider).showConstellationArt) {
      return const SizedBox.shrink();
    }

    final snapshot = ref.watch(sceneSnapshotProvider);
    final placements = ref.watch(constellationArtPlacementsProvider);
    if (placements.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size.width <= 0 || size.height <= 0) {
            return const SizedBox.shrink();
          }

          return CustomPaint(
            key: const Key('constellation_art_layer_paint'),
            size: size,
            painter: ConstellationArtPainter(
              viewPose: snapshot.viewPose,
              placements: placements,
            ),
          );
        },
      ),
    );
  }
}
