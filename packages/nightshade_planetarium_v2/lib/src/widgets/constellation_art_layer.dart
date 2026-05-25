import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/constellation_art_placements_provider.dart';
import '../providers/render_config_provider.dart';
import '../providers/scene_snapshot_provider.dart';
import '../rendering/constellation_art_painter.dart';

/// Screen-space constellation art overlays from the native scene snapshot.
///
/// Rebuilds **only** when the art toggle, placement list, or view pose
/// changes — uses [`Provider.select`](Ref.watch) on each input so toggling
/// unrelated render-config flags (stars, grids, ...) or pure label-list
/// frame ticks don't repaint the constellation figures.
class ConstellationArtLayer extends ConsumerWidget {
  const ConstellationArtLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArt = ref.watch(
      renderConfigProvider.select((c) => c.showConstellationArt),
    );
    if (!showArt) {
      return const SizedBox.shrink();
    }

    final placements = ref.watch(constellationArtPlacementsProvider);
    if (placements.isEmpty) {
      return const SizedBox.shrink();
    }

    final viewPose = ref.watch(
      sceneSnapshotProvider.select((s) => s.viewPose),
    );

    return IgnorePointer(
      child: RepaintBoundary(
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
                viewPose: viewPose,
                placements: placements,
              ),
            );
          },
        ),
      ),
    );
  }
}
