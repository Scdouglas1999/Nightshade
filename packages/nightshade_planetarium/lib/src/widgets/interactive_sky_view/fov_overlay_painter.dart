part of '../interactive_sky_view.dart';

/// FOV rectangle overlay painter
class _FOVOverlayPainter extends CustomPainter {
  final SkyViewState viewState;
  final double? fovWidth;
  final double? fovHeight;
  final CelestialCoordinate? fovCenter;
  final double rotation;

  _FOVOverlayPainter({
    required this.viewState,
    this.fovWidth,
    this.fovHeight,
    this.fovCenter,
    this.rotation = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fovWidth == null || fovHeight == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (viewState.fieldOfView / 2);

    // Convert FOV to screen pixels
    final rectWidth = fovWidth! * scale;
    final rectHeight = fovHeight! * scale;

    // Calculate offset if FOV center is different from view center
    Offset rectCenter = center;
    if (fovCenter != null) {
      // Calculate angular difference between view center and FOV center
      // RA is in hours, convert to degrees. Apply cos(dec) correction for RA.
      final viewCenterDecRad = viewState.centerDec * math.pi / 180;
      final deltaRA =
          (fovCenter!.ra - viewState.centerRA) *
          15 *
          math.cos(viewCenterDecRad);
      final deltaDec = fovCenter!.dec - viewState.centerDec;

      // Convert angular offset (degrees) to screen pixels
      // Positive deltaRA moves right, positive deltaDec moves up (screen Y is inverted)
      final offsetX = deltaRA * scale;
      final offsetY =
          -deltaDec * scale; // Negative because screen Y increases downward

      rectCenter = Offset(center.dx + offsetX, center.dy + offsetY);
    }

    // Draw FOV rectangle
    canvas.save();
    canvas.translate(rectCenter.dx, rectCenter.dy);
    canvas.rotate((rotation + viewState.rotation) * math.pi / 180);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: rectWidth,
      height: rectHeight,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(rect, borderPaint);

    // Draw corner brackets
    final bracketLength = math.min(rectWidth, rectHeight) * 0.1;
    final bracketPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(
      Offset(-rectWidth / 2, -rectHeight / 2 + bracketLength),
      Offset(-rectWidth / 2, -rectHeight / 2),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(-rectWidth / 2, -rectHeight / 2),
      Offset(-rectWidth / 2 + bracketLength, -rectHeight / 2),
      bracketPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(rectWidth / 2 - bracketLength, -rectHeight / 2),
      Offset(rectWidth / 2, -rectHeight / 2),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rectWidth / 2, -rectHeight / 2),
      Offset(rectWidth / 2, -rectHeight / 2 + bracketLength),
      bracketPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(rectWidth / 2, rectHeight / 2 - bracketLength),
      Offset(rectWidth / 2, rectHeight / 2),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rectWidth / 2, rectHeight / 2),
      Offset(rectWidth / 2 - bracketLength, rectHeight / 2),
      bracketPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(-rectWidth / 2 + bracketLength, rectHeight / 2),
      Offset(-rectWidth / 2, rectHeight / 2),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(-rectWidth / 2, rectHeight / 2),
      Offset(-rectWidth / 2, rectHeight / 2 - bracketLength),
      bracketPaint,
    );

    // Draw center crosshair
    final crosshairPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.5)
      ..strokeWidth = 1;

    canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), crosshairPaint);
    canvas.drawLine(const Offset(0, -15), const Offset(0, 15), crosshairPaint);

    // Draw rotation indicator
    if (rotation != 0) {
      canvas.drawLine(
        Offset(0, -rectHeight / 2 - 20),
        Offset(0, -rectHeight / 2 - 5),
        borderPaint,
      );
    }

    canvas.restore();

    // Draw FOV dimensions label
    final fovText =
        '${fovWidth!.toStringAsFixed(2)}° × ${fovHeight!.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: const TextStyle(
          color: Color(0xFF00E676),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        rectCenter.dx - textPainter.width / 2,
        rectCenter.dy + rectHeight / 2 + 10,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FOVOverlayPainter oldDelegate) {
    return viewState != oldDelegate.viewState ||
        fovWidth != oldDelegate.fovWidth ||
        fovHeight != oldDelegate.fovHeight ||
        rotation != oldDelegate.rotation;
  }
}
