import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scene_snapshot_provider.dart';

/// Pulsing ring drawn at the currently-selected object's projected
/// position. Without this overlay the user gets an info panel out of
/// thin air on click with no visual cue tying it to a sky position.
///
/// The ring's center is read from [`SceneSnapshotDto.selected`] which the
/// Rust renderer re-projects every frame, so the ring stays glued to the
/// object as the user pans / zooms / waits for time to advance.
class SelectionIndicatorLayer extends ConsumerStatefulWidget {
  const SelectionIndicatorLayer({super.key});

  @override
  ConsumerState<SelectionIndicatorLayer> createState() =>
      _SelectionIndicatorLayerState();
}

class _SelectionIndicatorLayerState
    extends ConsumerState<SelectionIndicatorLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      sceneSnapshotProvider.select((s) => s.selected),
    );
    if (selected == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size.width <= 0 || size.height <= 0) {
            return const SizedBox.shrink();
          }

          // Selected screen coords are normalized [0, 1] from the Rust
          // snapshot. Off-screen selections (object below horizon, clipped
          // by projection) come back as ~(0.5, 0.5) with a flag we don't
          // currently expose — render anyway; the ring stays anchored
          // where the projection placed it.
          final center = Offset(
            selected.screenX * size.width,
            selected.screenY * size.height,
          );
          // Don't draw if the projection put it well outside the viewport.
          if (center.dx < -32 ||
              center.dy < -32 ||
              center.dx > size.width + 32 ||
              center.dy > size.height + 32) {
            return const SizedBox.shrink();
          }

          return AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              return CustomPaint(
                size: size,
                painter: _SelectionRingPainter(
                  center: center,
                  pulse: _pulse.value,
                  label: selected.displayName,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SelectionRingPainter extends CustomPainter {
  _SelectionRingPainter({
    required this.center,
    required this.pulse,
    required this.label,
  });

  final Offset center;
  /// 0..1 sweep used by the pulse animation.
  final double pulse;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    // Outer pulse ring: expands from 22 → 30 px, alpha 0.85 → 0.0.
    final pulseT = pulse;
    final pulseRadius = 22.0 + 8.0 * pulseT;
    final pulseAlpha = (1.0 - pulseT) * 0.85;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFD166).withValues(alpha: pulseAlpha);
    canvas.drawCircle(center, pulseRadius, pulsePaint);

    // Static reticle: 4 short tick marks + central gap, like Stellarium.
    final reticle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFD166);
    const inner = 8.0;
    const outer = 16.0;
    // N
    canvas.drawLine(
      center + const Offset(0, -inner),
      center + const Offset(0, -outer),
      reticle,
    );
    // S
    canvas.drawLine(
      center + const Offset(0, inner),
      center + const Offset(0, outer),
      reticle,
    );
    // E
    canvas.drawLine(
      center + const Offset(inner, 0),
      center + const Offset(outer, 0),
      reticle,
    );
    // W
    canvas.drawLine(
      center + const Offset(-inner, 0),
      center + const Offset(-outer, 0),
      reticle,
    );

    // Floating label, offset to the upper-right so it doesn't sit on the
    // reticle.
    if (label.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFFFD166),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Color(0xCC000000),
                offset: Offset(0, 0),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final labelOffset = center + const Offset(20, -22);
      textPainter.paint(canvas, labelOffset);
      textPainter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionRingPainter old) {
    // Repaint when the center moved, pulse phase advanced (>1% delta), or
    // label text changed. The tight pulse threshold lets us run at full
    // animation framerate while pose is steady, but skips redundant
    // repaints when the pose changes faster than the animation does.
    return old.center != center ||
        (math.max(old.pulse - pulse, pulse - old.pulse)) > 0.01 ||
        old.label != label;
  }
}
