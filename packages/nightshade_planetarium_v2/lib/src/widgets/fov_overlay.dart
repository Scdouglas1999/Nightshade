import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../providers/scene_snapshot_provider.dart';
import '../rendering/fov_overlay_painter.dart';

/// Equipment sensor FOV rectangle over the Rust sky view.
///
/// Fed by [equipmentFovProvider] from [nightshade_core] and aligned to the
/// native [sceneSnapshotProvider] view pose. Watches only the snapshot's
/// `viewPose` slice so label/art/frameId changes don't repaint the reticle.
class FovOverlay extends ConsumerWidget {
  const FovOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipmentFov = ref.watch(equipmentFovProvider);
    if (!equipmentFov.hasFov) {
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
              key: const Key('fov_overlay_paint'),
              size: size,
              painter: FovOverlayPainter(
                viewPose: viewPose,
                widthDegrees: equipmentFov.widthDegrees!,
                heightDegrees: equipmentFov.heightDegrees!,
                rotationDegrees: equipmentFov.rotationDegrees,
              ),
            );
          },
        ),
      ),
    );
  }
}
