import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Live convergence visualization for all-sky polar alignment.
///
/// Renders a target reticle with a moving marker that reflects the
/// instantaneous polar-axis error vector. As the user adjusts the mount's
/// azimuth and altitude bolts, the marker drifts toward the bullseye; when
/// it sits inside the acceptance ring for the hold duration the alignment
/// auto-completes.
///
/// The visualization is intentionally **linear** in the error magnitude:
/// a 60″ error sits at 50% radius if the outer ring is 120″, a 30″ error
/// at 25% radius, etc. Users get a direct mechanical-feedback feel for how
/// much the bolts need to move.
class AllSkyTargetReticle extends StatelessWidget {
  /// Current azimuth error in arcseconds. Positive = mechanical pole east
  /// of true pole (rotate azimuth bolt westward).
  final double azimuthErrorArcsec;

  /// Current altitude error in arcseconds. Positive = mechanical pole above
  /// true pole (lower altitude bolt).
  final double altitudeErrorArcsec;

  /// Acceptance threshold in arcseconds. The inner highlighted ring is
  /// drawn at this radius; once the marker is inside it, alignment is
  /// good enough for the user's target imaging precision.
  final double acceptanceThresholdArcsec;

  /// Outer ring scale in arcseconds. Errors beyond this are clamped to the
  /// rim. Default = 4× threshold so coarse adjustment is still readable.
  final double outerScaleArcsec;

  /// Whether this is the first frame (no error data yet). Renders an empty
  /// reticle with a "waiting" overlay.
  final bool waitingForFirstFrame;

  /// Total side length in pixels (square widget).
  final double size;

  const AllSkyTargetReticle({
    super.key,
    required this.azimuthErrorArcsec,
    required this.altitudeErrorArcsec,
    required this.acceptanceThresholdArcsec,
    this.outerScaleArcsec = 0.0,
    this.waitingForFirstFrame = false,
    this.size = 280.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Default outer scale: 4× the acceptance threshold, but ensure a
    // sensible floor so a sub-arcsec threshold still renders cleanly.
    final outer = outerScaleArcsec > 0
        ? outerScaleArcsec
        : math.max(acceptanceThresholdArcsec * 4.0, 60.0);

    final totalError = math.sqrt(
      azimuthErrorArcsec * azimuthErrorArcsec +
          altitudeErrorArcsec * altitudeErrorArcsec,
    );
    final withinThreshold = totalError <= acceptanceThresholdArcsec;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _ReticlePainter(
              azimuthErrorArcsec: azimuthErrorArcsec,
              altitudeErrorArcsec: altitudeErrorArcsec,
              acceptanceThresholdArcsec: acceptanceThresholdArcsec,
              outerScaleArcsec: outer,
              waitingForFirstFrame: waitingForFirstFrame,
              colors: colors,
            ),
          ),
          if (!waitingForFirstFrame)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    '${totalError.toStringAsFixed(1)}″',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: withinThreshold
                          ? colors.success
                          : colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    withinThreshold
                        ? 'Within acceptance — hold steady'
                        : 'Az ${_formatSigned(azimuthErrorArcsec)}″   '
                            'Alt ${_formatSigned(altitudeErrorArcsec)}″',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          if (waitingForFirstFrame)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for first plate solve...',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatSigned(double value) {
    final sign = value >= 0 ? '+' : '−';
    return '$sign${value.abs().toStringAsFixed(1)}';
  }
}

class _ReticlePainter extends CustomPainter {
  final double azimuthErrorArcsec;
  final double altitudeErrorArcsec;
  final double acceptanceThresholdArcsec;
  final double outerScaleArcsec;
  final bool waitingForFirstFrame;
  final NightshadeColors colors;

  _ReticlePainter({
    required this.azimuthErrorArcsec,
    required this.altitudeErrorArcsec,
    required this.acceptanceThresholdArcsec,
    required this.outerScaleArcsec,
    required this.waitingForFirstFrame,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (math.min(size.width, size.height) / 2) - 16;
    final acceptanceRadius =
        maxRadius * (acceptanceThresholdArcsec / outerScaleArcsec);

    // Outer ring
    final outerPaint = Paint()
      ..color = colors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius, outerPaint);

    // Mid ring (50% scale)
    canvas.drawCircle(center, maxRadius * 0.5, outerPaint);

    // Acceptance threshold ring — highlighted
    final acceptancePaint = Paint()
      ..color = colors.success.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, acceptanceRadius, acceptancePaint);

    // Crosshair lines
    final crosshairPaint = Paint()
      ..color = colors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      crosshairPaint,
    );

    // Labels: N/S/E/W mark the cardinal bolt-direction hints
    _drawCardinal(canvas, center, maxRadius, 'Up', Alignment.topCenter);
    _drawCardinal(canvas, center, maxRadius, 'Dn', Alignment.bottomCenter);
    _drawCardinal(canvas, center, maxRadius, 'E', Alignment.centerRight);
    _drawCardinal(canvas, center, maxRadius, 'W', Alignment.centerLeft);

    if (waitingForFirstFrame) {
      return;
    }

    // Convert (az, alt) error in arcseconds into pixel offset from center.
    // Sign convention from PolarMisalignment:
    //   * azimuth_error > 0 → mechanical pole sits east of true pole.
    //     Render the marker on the EAST side of the reticle (positive X).
    //   * altitude_error > 0 → mechanical pole sits above true pole.
    //     Render the marker on the TOP side (negative Y, since screen Y
    //     grows downward).
    final dx = (azimuthErrorArcsec / outerScaleArcsec) * maxRadius;
    final dy = -(altitudeErrorArcsec / outerScaleArcsec) * maxRadius;

    // Clamp the marker to the rim so off-scale errors are still visible.
    final magnitude = math.sqrt(dx * dx + dy * dy);
    final double clampedDx;
    final double clampedDy;
    if (magnitude > maxRadius) {
      final scale = maxRadius / magnitude;
      clampedDx = dx * scale;
      clampedDy = dy * scale;
    } else {
      clampedDx = dx;
      clampedDy = dy;
    }

    final markerCenter =
        Offset(center.dx + clampedDx, center.dy + clampedDy);

    final totalError = math.sqrt(
      azimuthErrorArcsec * azimuthErrorArcsec +
          altitudeErrorArcsec * altitudeErrorArcsec,
    );
    final withinThreshold = totalError <= acceptanceThresholdArcsec;

    // Draw a guide arrow from the center to the marker indicating the
    // direction the mechanical pole is offset.
    if (totalError > 1.0) {
      final arrowPaint = Paint()
        ..color = withinThreshold
            ? colors.success.withValues(alpha: 0.4)
            : colors.warning.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawLine(center, markerCenter, arrowPaint);

      // Arrowhead
      final angle = math.atan2(clampedDy, clampedDx);
      const headSize = 8.0;
      final head1 = Offset(
        markerCenter.dx - headSize * math.cos(angle - math.pi / 6),
        markerCenter.dy - headSize * math.sin(angle - math.pi / 6),
      );
      final head2 = Offset(
        markerCenter.dx - headSize * math.cos(angle + math.pi / 6),
        markerCenter.dy - headSize * math.sin(angle + math.pi / 6),
      );
      canvas.drawLine(markerCenter, head1, arrowPaint);
      canvas.drawLine(markerCenter, head2, arrowPaint);
    }

    // Marker dot
    final markerPaint = Paint()
      ..color = withinThreshold ? colors.success : colors.error
      ..style = PaintingStyle.fill;
    canvas.drawCircle(markerCenter, 6.0, markerPaint);

    final markerOutline = Paint()
      ..color = colors.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(markerCenter, 6.0, markerOutline);

    // Center bullseye
    final bullseyePaint = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, bullseyePaint);
  }

  void _drawCardinal(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    Alignment alignment,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = 4.0;
    Offset textOffset;
    if (alignment == Alignment.topCenter) {
      textOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy - radius - textPainter.height - padding,
      );
    } else if (alignment == Alignment.bottomCenter) {
      textOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy + radius + padding,
      );
    } else if (alignment == Alignment.centerRight) {
      textOffset = Offset(
        center.dx + radius + padding,
        center.dy - textPainter.height / 2,
      );
    } else {
      textOffset = Offset(
        center.dx - radius - textPainter.width - padding,
        center.dy - textPainter.height / 2,
      );
    }
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.azimuthErrorArcsec != azimuthErrorArcsec ||
      old.altitudeErrorArcsec != altitudeErrorArcsec ||
      old.acceptanceThresholdArcsec != acceptanceThresholdArcsec ||
      old.outerScaleArcsec != outerScaleArcsec ||
      old.waitingForFirstFrame != waitingForFirstFrame;
}
