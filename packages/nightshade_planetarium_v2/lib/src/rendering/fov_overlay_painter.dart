import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../models/celestial_coordinate.dart';

/// Equipment sensor rectangle overlay (ported from v1 sky view FOV painter).
class FovOverlayPainter extends CustomPainter {
  FovOverlayPainter({
    required this.viewPose,
    required this.widthDegrees,
    required this.heightDegrees,
    this.rotationDegrees = 0,
    this.fovCenter,
    this.color = const Color(0xFF00E676),
  });

  final ViewPoseDto viewPose;
  final double widthDegrees;
  final double heightDegrees;
  final double rotationDegrees;
  final CelestialCoordinate? fovCenter;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final fovDegrees = viewPose.fovRad * 180 / math.pi;
    final scale = math.min(size.width, size.height) / 2 / (fovDegrees / 2);

    final rectWidth = widthDegrees * scale;
    final rectHeight = heightDegrees * scale;

    var rectCenter = center;
    if (fovCenter != null) {
      final centerRaHours = viewPose.raRad * 12 / math.pi;
      final centerDecDegrees = viewPose.decRad * 180 / math.pi;
      final viewCenterDecRad = centerDecDegrees * math.pi / 180;
      final deltaRa = (fovCenter!.ra - centerRaHours) *
          15 *
          math.cos(viewCenterDecRad);
      final deltaDec = fovCenter!.dec - centerDecDegrees;
      rectCenter = Offset(
        center.dx + deltaRa * scale,
        center.dy - deltaDec * scale,
      );
    }

    canvas.save();
    canvas.translate(rectCenter.dx, rectCenter.dy);
    final rollDegrees = viewPose.rollRad * 180 / math.pi;
    canvas.rotate((rotationDegrees + rollDegrees) * math.pi / 180);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: rectWidth,
      height: rectHeight,
    );

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);

    final bracketLength = math.min(rectWidth, rectHeight) * 0.1;
    final bracketPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    _drawCornerBracket(
      canvas,
      Offset(-rectWidth / 2, -rectHeight / 2),
      Offset(-rectWidth / 2 + bracketLength, -rectHeight / 2),
      Offset(-rectWidth / 2, -rectHeight / 2 + bracketLength),
      bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      Offset(rectWidth / 2, -rectHeight / 2),
      Offset(rectWidth / 2 - bracketLength, -rectHeight / 2),
      Offset(rectWidth / 2, -rectHeight / 2 + bracketLength),
      bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      Offset(rectWidth / 2, rectHeight / 2),
      Offset(rectWidth / 2 - bracketLength, rectHeight / 2),
      Offset(rectWidth / 2, rectHeight / 2 - bracketLength),
      bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      Offset(-rectWidth / 2, rectHeight / 2),
      Offset(-rectWidth / 2 + bracketLength, rectHeight / 2),
      Offset(-rectWidth / 2, rectHeight / 2 - bracketLength),
      bracketPaint,
    );

    final crosshairPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), crosshairPaint);
    canvas.drawLine(const Offset(0, -15), const Offset(0, 15), crosshairPaint);

    if (rotationDegrees != 0) {
      canvas.drawLine(
        Offset(0, -rectHeight / 2 - 20),
        Offset(0, -rectHeight / 2 - 5),
        borderPaint,
      );
    }

    canvas.restore();

    final fovText =
        '${widthDegrees.toStringAsFixed(2)}° × ${heightDegrees.toStringAsFixed(2)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: fovText,
        style: TextStyle(
          color: color,
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

  void _drawCornerBracket(
    Canvas canvas,
    Offset corner,
    Offset alongX,
    Offset alongY,
    Paint paint,
  ) {
    canvas.drawLine(corner, alongX, paint);
    canvas.drawLine(corner, alongY, paint);
  }

  @override
  bool shouldRepaint(covariant FovOverlayPainter oldDelegate) {
    return viewPose != oldDelegate.viewPose ||
        widthDegrees != oldDelegate.widthDegrees ||
        heightDegrees != oldDelegate.heightDegrees ||
        rotationDegrees != oldDelegate.rotationDegrees ||
        fovCenter != oldDelegate.fovCenter ||
        color != oldDelegate.color;
  }
}
