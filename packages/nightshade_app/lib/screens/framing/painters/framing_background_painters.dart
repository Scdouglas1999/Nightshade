import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Paints the survey image background fitted to the canvas, honoring pan/zoom.
class FramingSurveyImagePainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final double panX;
  final double panY;

  FramingSurveyImagePainter({
    required this.image,
    required this.zoom,
    required this.panX,
    required this.panY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;

    // Calculate scaling to fit image to canvas
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;

    double drawWidth, drawHeight;
    if (imageAspect > canvasAspect) {
      drawWidth = size.width * zoom;
      drawHeight = drawWidth / imageAspect;
    } else {
      drawHeight = size.height * zoom;
      drawWidth = drawHeight * imageAspect;
    }

    final center = Offset(size.width / 2 + panX, size.height / 2 + panY);
    final destRect = Rect.fromCenter(
      center: center,
      width: drawWidth,
      height: drawHeight,
    );

    final srcRect =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

    canvas.drawImageRect(image, srcRect, destRect, paint);
  }

  @override
  bool shouldRepaint(covariant FramingSurveyImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        zoom != oldDelegate.zoom ||
        panX != oldDelegate.panX ||
        panY != oldDelegate.panY;
  }
}

/// Static deterministic starfield + soft nebula hint, used when no survey image
/// is loaded. The seed is fixed so the backdrop is stable across rebuilds.
class FramingStarBackgroundPainter extends CustomPainter {
  final NightshadeColors colors;

  FramingStarBackgroundPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final random = _SeededRandom(42);

    // Background gradient
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Color(0xFF12121A),
          Color(0xFF08080C),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw stars
    for (var i = 0; i < 300; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.5 + 0.2;
      final radius = random.nextDouble() * 1.5 + 0.3;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Draw faint nebula hint in center
    final center = Offset(size.width / 2, size.height / 2);
    final gradient = RadialGradient(
      colors: [
        colors.primary.withValues(alpha: 0.1),
        colors.accent.withValues(alpha: 0.05),
        Colors.transparent,
      ],
    );
    final rect = Rect.fromCircle(center: center, radius: 150);
    paint.shader = gradient.createShader(rect);
    canvas.drawCircle(center, 150, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SeededRandom {
  int _seed;

  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}

/// Grid overlay aligned with canvas pan/zoom; brighter cross-hairs on the
/// current center.
class FramingGridPainter extends CustomPainter {
  final double zoom;
  final double panX;
  final double panY;
  final Color color;

  FramingGridPainter({
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    final center = Offset(size.width / 2 + panX, size.height / 2 + panY);
    final spacing = 60.0 * zoom;

    // Draw vertical lines
    for (var x = center.dx % spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (var y = center.dy % spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw center lines (brighter)
    paint.color = color.withValues(alpha: 0.5);
    paint.strokeWidth = 1;
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
  }

  @override
  bool shouldRepaint(covariant FramingGridPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        panX != oldDelegate.panX ||
        panY != oldDelegate.panY;
  }
}

/// Center crosshair (full-width and full-height lines + center circle) drawn
/// on top of the survey image to mark the framing reticle.
class FramingCrosshairPainter extends CustomPainter {
  final NightshadeColors colors;

  FramingCrosshairPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.error.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);

    // Horizontal line
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);

    // Vertical line
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Center circle
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(center, 6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
