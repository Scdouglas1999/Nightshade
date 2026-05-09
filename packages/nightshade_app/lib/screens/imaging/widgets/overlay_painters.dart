import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

class StarFieldPainter extends CustomPainter {
  final NightshadeColors colors;

  StarFieldPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint();

    for (var i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.25 + 0.05;
      final radius = random.nextDouble() * 1.2 + 0.3;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CrosshairOverlayPainter extends CustomPainter {
  final Color color;

  CrosshairOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Horizontal line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      paint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      paint,
    );

    // Center circle
    paint.style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(centerX, centerY), 20, paint);
    canvas.drawCircle(Offset(centerX, centerY), 40, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GridOverlayPainter extends CustomPainter {
  final Color color;

  GridOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const gridSize = 50.0;

    // Vertical lines
    for (double x = gridSize; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = gridSize; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StarOverlayPainter extends CustomPainter {
  final List<DetectedStar> stars;
  final Color color;
  final double zoomLevel;
  final Offset imageOffset;

  StarOverlayPainter({
    required this.stars,
    required this.color,
    required this.zoomLevel,
    required this.imageOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    for (final star in stars) {
      final x = star.x * zoomLevel + imageOffset.dx;
      final y = star.y * zoomLevel + imageOffset.dy;

      // Skip stars outside the visible area
      if (x < -50 || x > size.width + 50 || y < -50 || y > size.height + 50) {
        continue;
      }

      final position = Offset(x, y);

      // Draw circle around star (radius based on HFR)
      final radius = (star.hfr * zoomLevel).clamp(3.0, 30.0);
      canvas.drawCircle(position, radius, fillPaint);
      canvas.drawCircle(position, radius, paint);

      // Draw crosshair
      const crosshairSize = 3.0;
      canvas.drawLine(
        Offset(x - crosshairSize, y),
        Offset(x + crosshairSize, y),
        paint,
      );
      canvas.drawLine(
        Offset(x, y - crosshairSize),
        Offset(x, y + crosshairSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StarOverlayPainter oldDelegate) {
    return stars != oldDelegate.stars ||
        color != oldDelegate.color ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageOffset != oldDelegate.imageOffset;
  }
}

class SciencePsfOverlayPainter extends CustomPainter {
  final List<PsfFieldTileRow> tiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;

  SciencePsfOverlayPainter({
    required this.tiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) {
      return;
    }

    var maxRow = 0;
    var maxCol = 0;
    var maxFwhm = 0.0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
      if (tile.starCount > 0 && tile.medianFwhm > maxFwhm) {
        maxFwhm = tile.medianFwhm;
      }
    }

    final validFwhm = tiles
        .where((tile) => tile.starCount > 0 && tile.medianFwhm > 0)
        .map((tile) => tile.medianFwhm)
        .toList(growable: false)
      ..sort();
    final low = validFwhm.isEmpty ? 0.0 : _percentile(validFwhm, 0.05);
    final high = validFwhm.isEmpty
        ? maxFwhm
        : _percentile(validFwhm, 0.95).clamp(low + 1e-6, double.infinity);

    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final tile in tiles) {
      final norm = tile.starCount <= 0 || high <= low
          ? 0.0
          : ((tile.medianFwhm - low) / (high - low)).clamp(0.0, 1.0);
      final fill = Paint()
        ..color = (tile.starCount <= 0
                ? const Color(0xFF4A5568)
                : Color.lerp(
                    const Color(0xFF0B6E4F),
                    const Color(0xFFC0392B),
                    norm,
                  )!)
            .withValues(alpha: tile.starCount > 0 ? 0.28 : 0.12)
        ..style = PaintingStyle.fill;

      final left = (tile.tileCol * tileW) * zoomLevel + imageOffset.dx;
      final top = (tile.tileRow * tileH) * zoomLevel + imageOffset.dy;
      final rect = Rect.fromLTWH(
        left,
        top,
        tileW * zoomLevel,
        tileH * zoomLevel,
      );

      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SciencePsfOverlayPainter oldDelegate) {
    return tiles != oldDelegate.tiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight;
  }

  double _percentile(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1.0 - t) + sortedValues[hi] * t;
  }
}

class ScienceResidualOverlayPainter extends CustomPainter {
  final List<AstrometryResidualVectorRow> vectors;
  final Offset imageOffset;
  final double zoomLevel;

  ScienceResidualOverlayPainter({
    required this.vectors,
    required this.imageOffset,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vectors.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..color = const Color(0xFFF1C40F).withValues(alpha: 0.75)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final headPaint = Paint()
      ..color = const Color(0xFFF39C12).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final magnitudes = vectors
        .map((vector) => vector.magnitudeArcsec)
        .where((value) => value.isFinite && value > 0)
        .toList(growable: false)
      ..sort();
    final p95Magnitude = magnitudes.isEmpty
        ? 1.0
        : magnitudes[((magnitudes.length - 1) * 0.95).floor()];
    final scaleArcsecToPixels = p95Magnitude <= 0
        ? 6.0
        : (22.0 / p95Magnitude).clamp(2.0, 40.0).toDouble();

    final maxVectors = math.min(350, vectors.length);
    for (var i = 0; i < maxVectors; i++) {
      final vector = vectors[i];
      final x1 = vector.x * zoomLevel + imageOffset.dx;
      final y1 = vector.y * zoomLevel + imageOffset.dy;
      final dx = vector.dxArcsec * zoomLevel * scaleArcsecToPixels;
      final dy = vector.dyArcsec * zoomLevel * scaleArcsecToPixels;
      final x2 = x1 + dx;
      final y2 = y1 + dy;

      if (x1 < -100 ||
          x1 > size.width + 100 ||
          y1 < -100 ||
          y1 > size.height + 100) {
        continue;
      }

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      canvas.drawCircle(Offset(x2, y2), 1.6, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScienceResidualOverlayPainter oldDelegate) {
    return vectors != oldDelegate.vectors ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel;
  }
}

class ScienceUniformityOverlayPainter extends CustomPainter {
  final List<ScienceTileMetricRow> tiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;
  final double opacity;

  ScienceUniformityOverlayPainter({
    required this.tiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) {
      return;
    }

    var maxRow = 0;
    var maxCol = 0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }

    final values = tiles
        .map((tile) => tile.value)
        .where((value) => value.isFinite && value >= 0.0)
        .toList(growable: false)
      ..sort();
    final low = values.isEmpty ? 0.0 : _percentile(values, 0.05);
    final high = values.isEmpty
        ? 1.0
        : _percentile(values, 0.95).clamp(low + 1e-6, double.infinity);

    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final tile in tiles) {
      final norm = high <= low
          ? 0.0
          : ((tile.value - low) / (high - low)).clamp(0.0, 1.0);
      final fill = Paint()
        ..color = Color.lerp(
          const Color(0xFF0B3D91),
          const Color(0xFFFF8C42),
          norm,
        )!
            .withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final left = (tile.tileCol * tileW) * zoomLevel + imageOffset.dx;
      final top = (tile.tileRow * tileH) * zoomLevel + imageOffset.dy;
      final rect = Rect.fromLTWH(
        left,
        top,
        tileW * zoomLevel,
        tileH * zoomLevel,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScienceUniformityOverlayPainter oldDelegate) {
    return tiles != oldDelegate.tiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        opacity != oldDelegate.opacity;
  }

  double _percentile(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1.0 - t) + sortedValues[hi] * t;
  }
}

class ScienceClipOverlayPainter extends CustomPainter {
  final List<ScienceTileMetricRow> highTiles;
  final List<ScienceTileMetricRow> lowTiles;
  final Offset imageOffset;
  final double zoomLevel;
  final double imageWidth;
  final double imageHeight;
  final double opacity;

  ScienceClipOverlayPainter({
    required this.highTiles,
    required this.lowTiles,
    required this.imageOffset,
    required this.zoomLevel,
    required this.imageWidth,
    required this.imageHeight,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (highTiles.isEmpty && lowTiles.isEmpty) {
      return;
    }
    var maxRow = 0;
    var maxCol = 0;
    for (final tile in highTiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    for (final tile in lowTiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    final rows = maxRow + 1;
    final cols = maxCol + 1;
    final tileW = imageWidth / cols;
    final tileH = imageHeight / rows;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final highMap = <(int, int), double>{};
    final lowMap = <(int, int), double>{};
    for (final tile in highTiles) {
      highMap[(tile.tileRow, tile.tileCol)] = tile.value;
    }
    for (final tile in lowTiles) {
      lowMap[(tile.tileRow, tile.tileCol)] = tile.value;
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final high = (highMap[(row, col)] ?? 0.0).clamp(0.0, 100.0);
        final low = (lowMap[(row, col)] ?? 0.0).clamp(0.0, 100.0);
        if (high <= 0 && low <= 0) {
          continue;
        }
        final alpha = (math.max(high, low) / 100.0).clamp(0.08, 1.0) * opacity;
        final fillColor = Color.lerp(
          const Color(0xFF3B82F6), // low clipping: blue
          const Color(0xFFEF4444), // high clipping: red
          high / math.max(1.0, high + low),
        )!
            .withValues(alpha: alpha);
        final fill = Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill;

        final left = (col * tileW) * zoomLevel + imageOffset.dx;
        final top = (row * tileH) * zoomLevel + imageOffset.dy;
        final rect = Rect.fromLTWH(
          left,
          top,
          tileW * zoomLevel,
          tileH * zoomLevel,
        );
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScienceClipOverlayPainter oldDelegate) {
    return highTiles != oldDelegate.highTiles ||
        lowTiles != oldDelegate.lowTiles ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        imageWidth != oldDelegate.imageWidth ||
        imageHeight != oldDelegate.imageHeight ||
        opacity != oldDelegate.opacity;
  }
}

class ProjectedMovingTrack {
  final double imageX;
  final double imageY;
  final double positionAngleDegrees;
  final double motionArcsecPerMinute;
  final double confidence;

  const ProjectedMovingTrack({
    required this.imageX,
    required this.imageY,
    required this.positionAngleDegrees,
    required this.motionArcsecPerMinute,
    required this.confidence,
  });
}

class ScienceMovingTrackOverlayPainter extends CustomPainter {
  final List<ProjectedMovingTrack> tracks;
  final Offset imageOffset;
  final double zoomLevel;

  ScienceMovingTrackOverlayPainter({
    required this.tracks,
    required this.imageOffset,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tracks.isEmpty) {
      return;
    }

    for (final track in tracks) {
      final x = track.imageX * zoomLevel + imageOffset.dx;
      final y = track.imageY * zoomLevel + imageOffset.dy;
      if (x < -120 ||
          x > size.width + 120 ||
          y < -120 ||
          y > size.height + 120) {
        continue;
      }

      final confidenceColor = Color.lerp(
        const Color(0xFFF59E0B),
        const Color(0xFF22C55E),
        track.confidence.clamp(0.0, 1.0),
      )!;

      final trailLength =
          (8.0 + track.motionArcsecPerMinute * 1.8).clamp(8.0, 44.0).toDouble();
      final paRad = track.positionAngleDegrees * math.pi / 180.0;
      final dx = math.sin(paRad) * trailLength;
      final dy = -math.cos(paRad) * trailLength;
      final start = Offset(x - dx * 0.45, y - dy * 0.45);
      final end = Offset(x + dx * 0.55, y + dy * 0.55);

      final linePaint = Paint()
        ..color = confidenceColor.withValues(alpha: 0.86)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final pointPaint = Paint()
        ..color = confidenceColor.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;

      canvas.drawLine(start, end, linePaint);
      canvas.drawCircle(end, 2.2, pointPaint);
      canvas.drawCircle(
        Offset(x, y),
        3.6,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(x, y),
        2.0,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScienceMovingTrackOverlayPainter oldDelegate) {
    return tracks != oldDelegate.tracks ||
        imageOffset != oldDelegate.imageOffset ||
        zoomLevel != oldDelegate.zoomLevel;
  }
}

/// Compass overlay showing N/E cardinal directions based on plate solve rotation.
///
/// Draws a semi-transparent circle with rotated N and E arrows in the
/// bottom-right corner. The rotation angle comes from WCS plate solve data,
/// representing the position angle of the image (North through East).
class CompassOverlayPainter extends CustomPainter {
  /// WCS rotation angle in degrees (position angle, North through East).
  final double rotationDegrees;

  /// Radius of the compass circle in logical pixels.
  final double radius;

  /// Margin from the corner of the canvas.
  final double margin;

  CompassOverlayPainter({
    required this.rotationDegrees,
    this.radius = 60.0,
    this.margin = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Position in bottom-right corner
    final centerX = size.width - margin - radius;
    final centerY = size.height - margin - radius;
    final center = Offset(centerX, centerY);

    // Semi-transparent background circle
    final bgPaint = Paint()
      ..color = const Color(0xAA000000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, borderPaint);

    // The plate solve rotation is the angle from image-up to celestial North,
    // measured East of North (counter-clockwise on-sky, but clockwise in
    // screen-Y-down coordinates). We negate so that the N arrow points in
    // the direction of North within the image.
    final rotRad = -rotationDegrees * (math.pi / 180.0);

    // Arrow length: slightly shorter than radius to leave room for labels
    final arrowLength = radius * 0.65;
    const arrowHeadSize = 8.0;

    // --- North arrow ---
    final nDx = math.sin(rotRad) * arrowLength;
    final nDy = -math.cos(rotRad) * arrowLength;
    final nTip = Offset(centerX + nDx, centerY + nDy);

    final nPaint = Paint()
      ..color = const Color(0xFFFF4444)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, nTip, nPaint);
    _drawArrowHead(canvas, center, nTip, arrowHeadSize, nPaint);

    // "N" label at tip
    _drawLabel(canvas, 'N', nTip, rotRad, radius, const Color(0xFFFF4444));

    // --- East arrow (perpendicular to North, 90 degrees clockwise on sky) ---
    final eRotRad = rotRad + (math.pi / 2.0);
    final eDx = math.sin(eRotRad) * arrowLength;
    final eDy = -math.cos(eRotRad) * arrowLength;
    final eTip = Offset(centerX + eDx, centerY + eDy);

    final ePaint = Paint()
      ..color = const Color(0xFF44AAFF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, eTip, ePaint);
    _drawArrowHead(canvas, center, eTip, arrowHeadSize, ePaint);

    // "E" label at tip
    _drawLabel(canvas, 'E', eTip, eRotRad, radius, const Color(0xFF44AAFF));
  }

  void _drawArrowHead(
      Canvas canvas, Offset from, Offset to, double headSize, Paint paint) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final angle = math.atan2(dy, dx);

    final arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(to.dx, to.dy);
    path.lineTo(
      to.dx - headSize * math.cos(angle - 0.45),
      to.dy - headSize * math.sin(angle - 0.45),
    );
    path.lineTo(
      to.dx - headSize * math.cos(angle + 0.45),
      to.dy - headSize * math.sin(angle + 0.45),
    );
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  void _drawLabel(Canvas canvas, String text, Offset tipPosition,
      double arrowAngleRad, double compassRadius, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        shadows: const [
          Shadow(blurRadius: 4, color: Color(0xFF000000), offset: Offset(0, 0)),
          Shadow(blurRadius: 2, color: Color(0xFF000000), offset: Offset(1, 1)),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Place label just beyond the arrow tip, pushed outward along the arrow direction
    const labelOffset = 10.0;
    final labelDx = math.sin(arrowAngleRad) * labelOffset;
    final labelDy = -math.cos(arrowAngleRad) * labelOffset;

    textPainter.paint(
      canvas,
      Offset(
        tipPosition.dx + labelDx - textPainter.width / 2,
        tipPosition.dy + labelDy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CompassOverlayPainter oldDelegate) {
    return oldDelegate.rotationDegrees != rotationDegrees ||
        oldDelegate.radius != radius ||
        oldDelegate.margin != margin;
  }
}

/// Scale bar overlay showing angular size reference based on plate solve pixel scale.
///
/// Draws a horizontal bar with tick marks and a label showing the angular extent
/// (e.g. "5'" or "1°"), positioned at the bottom-left of the canvas. The bar
/// length is chosen to be a "nice" angular value that fills roughly 15-25% of
/// the image width.
class ScaleBarPainter extends CustomPainter {
  /// Pixel scale from plate solve in arcseconds per pixel.
  final double pixelScaleArcsecPerPixel;

  /// Width of the image in pixels (at native resolution).
  final double imageWidthPixels;

  /// Current zoom level applied to the image.
  final double zoomLevel;

  /// Margin from the corner of the canvas.
  final double margin;

  ScaleBarPainter({
    required this.pixelScaleArcsecPerPixel,
    required this.imageWidthPixels,
    required this.zoomLevel,
    this.margin = 20.0,
  });

  // "Nice" angular values in arcseconds with their human-readable labels.
  static const List<(double arcsec, String label)> _niceScales = [
    (1.0, '1"'),
    (2.0, '2"'),
    (5.0, '5"'),
    (10.0, '10"'),
    (30.0, '30"'),
    (60.0, "1'"),
    (120.0, "2'"),
    (300.0, "5'"),
    (600.0, "10'"),
    (900.0, "15'"),
    (1800.0, "30'"),
    (3600.0, '1\u00B0'),
    (7200.0, '2\u00B0'),
    (18000.0, '5\u00B0'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelScaleArcsecPerPixel <= 0 || imageWidthPixels <= 0) return;

    // The viewport width of the image is imageWidthPixels * zoomLevel.
    // We want the bar to be roughly 15-25% of the viewport image width.
    final viewportImageWidth = imageWidthPixels * zoomLevel;
    final targetBarPixels = viewportImageWidth * 0.20;
    // Target angular size in arcseconds that would produce this bar length
    final targetArcsec = targetBarPixels * pixelScaleArcsecPerPixel / zoomLevel;

    // Find the "nice" scale closest to targetArcsec
    String bestLabel = _niceScales.first.$2;
    double bestArcsec = _niceScales.first.$1;
    double bestDiff = (targetArcsec - bestArcsec).abs();

    for (final (arcsec, label) in _niceScales) {
      final diff = (targetArcsec - arcsec).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestArcsec = arcsec;
        bestLabel = label;
      }
    }

    // Convert chosen angular size to viewport pixels
    final barLengthPixels = (bestArcsec / pixelScaleArcsecPerPixel) * zoomLevel;

    // Clamp to reasonable range to avoid tiny or huge bars
    if (barLengthPixels < 20 || barLengthPixels > size.width * 0.8) return;

    // Position at bottom-left
    final barY = size.height - margin - 12;
    final barX = margin;

    // Semi-transparent background behind the bar and label
    const bgPadding = 8.0;
    const tickHeight = 8.0;

    // Measure text first so we can size the background
    final textSpan = TextSpan(
      text: bestLabel,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        shadows: [
          Shadow(blurRadius: 4, color: Color(0xFF000000), offset: Offset(0, 0)),
          Shadow(blurRadius: 2, color: Color(0xFF000000), offset: Offset(1, 1)),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final bgWidth =
        math.max(barLengthPixels, textPainter.width) + bgPadding * 2;
    final bgHeight = tickHeight + 4 + textPainter.height + bgPadding * 2;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        barX - bgPadding,
        barY - tickHeight - bgPadding,
        bgWidth,
        bgHeight,
      ),
      const Radius.circular(4),
    );
    final bgPaint = Paint()
      ..color = const Color(0xAA000000)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bgRect, bgPaint);

    // Draw the horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(
      Offset(barX, barY),
      Offset(barX + barLengthPixels, barY),
      barPaint,
    );

    // Tick marks at each end
    canvas.drawLine(
      Offset(barX, barY - tickHeight),
      Offset(barX, barY),
      barPaint,
    );
    canvas.drawLine(
      Offset(barX + barLengthPixels, barY - tickHeight),
      Offset(barX + barLengthPixels, barY),
      barPaint,
    );

    // Label centered below the bar
    textPainter.paint(
      canvas,
      Offset(
        barX + (barLengthPixels - textPainter.width) / 2,
        barY + 4,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant ScaleBarPainter oldDelegate) {
    return oldDelegate.pixelScaleArcsecPerPixel != pixelScaleArcsecPerPixel ||
        oldDelegate.imageWidthPixels != imageWidthPixels ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.margin != margin;
  }
}

/// Celestial coordinate grid overlay that renders RA/Dec grid lines
/// projected onto the image using plate solve WCS data.
///
/// Grid spacing is automatically selected based on the field of view to
/// produce approximately 5-8 grid lines across the image. Lines of constant
/// RA appear as curves (due to gnomonic projection) and are labeled in
/// HH:MM format. Lines of constant Dec are labeled in +/-DD°MM' format.
class CelestialGridPainter extends CustomPainter {
  final PlateSolveData plateSolve;
  final double zoomLevel;
  final Offset imageOffset;

  CelestialGridPainter({
    required this.plateSolve,
    required this.zoomLevel,
    required this.imageOffset,
  });

  // Grid spacing candidates in degrees
  static const _wideSpacingsDeg = [30.0, 15.0, 10.0, 5.0, 2.0, 1.0, 0.5];
  // Narrow field spacings in degrees (arcminute-scale)
  static const _narrowSpacingsDeg = [
    0.5, // 30'
    10.0 / 60.0, // 10'
    5.0 / 60.0, // 5'
    2.0 / 60.0, // 2'
    1.0 / 60.0, // 1'
  ];

  static const _gridColor = Color(0x40008888);
  static const _labelColor = Color(0xA0CCDDDD);
  static const _labelBgColor = Color(0x60000000);
  static const _gridStrokeWidth = 0.8;
  static const _samplesPerLine = 60;

  @override
  void paint(Canvas canvas, Size size) {
    // Determine the visible sky range by transforming the 4 image corners
    // plus midpoints of each edge to handle curved projections
    final corners = <({double ra, double dec})>[];
    final samplePoints = [
      (0.0, 0.0),
      (plateSolve.imageWidth.toDouble(), 0.0),
      (plateSolve.imageWidth.toDouble(), plateSolve.imageHeight.toDouble()),
      (0.0, plateSolve.imageHeight.toDouble()),
      (plateSolve.imageWidth / 2.0, 0.0),
      (plateSolve.imageWidth.toDouble(), plateSolve.imageHeight / 2.0),
      (plateSolve.imageWidth / 2.0, plateSolve.imageHeight.toDouble()),
      (0.0, plateSolve.imageHeight / 2.0),
    ];
    for (final (px, py) in samplePoints) {
      corners.add(plateSolve.pixelToSky(px, py));
    }

    // Find Dec range (straightforward min/max)
    var minDec = corners[0].dec;
    var maxDec = corners[0].dec;
    for (final c in corners) {
      if (c.dec < minDec) minDec = c.dec;
      if (c.dec > maxDec) maxDec = c.dec;
    }

    // Find RA range handling wraparound at 0h/24h
    final raValues = corners.map((c) => c.ra).toList();
    final raRange = _computeRaRange(raValues);
    var minRa = raRange.min;
    var maxRa = raRange.max;

    // Add small padding to ensure edge grid lines are included
    final fovDeg = math.max(plateSolve.fieldWidth, plateSolve.fieldHeight);
    final padding = fovDeg * 0.05;
    minDec -= padding;
    maxDec += padding;
    minRa -= padding;
    maxRa += padding;

    // Clamp Dec to valid range
    minDec = minDec.clamp(-90.0, 90.0);
    maxDec = maxDec.clamp(-90.0, 90.0);

    // Select grid spacing based on FOV
    final spacingDeg = _selectSpacing(fovDeg);

    final linePaint = Paint()
      ..color = _gridColor
      ..strokeWidth = _gridStrokeWidth
      ..style = PaintingStyle.stroke;

    // Clip to canvas bounds
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Draw Dec lines (lines of constant declination)
    final firstDec = (minDec / spacingDeg).floor() * spacingDeg;
    for (var dec = firstDec; dec <= maxDec; dec += spacingDeg) {
      if (dec < -90.0 || dec > 90.0) continue;
      _drawDecLine(canvas, size, dec, minRa, maxRa, linePaint);
    }

    // Draw RA lines (lines of constant right ascension)
    // RA spacing: use same spacing but convert to RA hours-equivalent
    // For RA we use the same degree spacing
    final firstRa = (minRa / spacingDeg).floor() * spacingDeg;
    for (var ra = firstRa; ra <= maxRa; ra += spacingDeg) {
      // Normalize RA for display
      var raNorm = ra;
      while (raNorm < 0) raNorm += 360;
      while (raNorm >= 360) raNorm -= 360;
      _drawRaLine(canvas, size, ra, raNorm, minDec, maxDec, linePaint);
    }

    canvas.restore();
  }

  /// Draw a line of constant Dec across the visible RA range
  void _drawDecLine(
    Canvas canvas,
    Size size,
    double dec,
    double minRa,
    double maxRa,
    Paint paint,
  ) {
    final path = ui.Path();
    var started = false;
    Offset? firstVisiblePoint;

    for (var i = 0; i <= _samplesPerLine; i++) {
      final t = i / _samplesPerLine;
      final ra = minRa + t * (maxRa - minRa);

      // Normalize RA for skyToPixel
      var raNorm = ra;
      while (raNorm < 0) raNorm += 360;
      while (raNorm >= 360) raNorm -= 360;

      final pixel = plateSolve.skyToPixelUnclamped(raNorm, dec);
      if (pixel == null) {
        started = false;
        continue;
      }

      final screenX = pixel.x * zoomLevel + imageOffset.dx;
      final screenY = pixel.y * zoomLevel + imageOffset.dy;
      final point = Offset(screenX, screenY);

      if (!started) {
        path.moveTo(screenX, screenY);
        started = true;
        if (firstVisiblePoint == null) firstVisiblePoint = point;
      } else {
        path.lineTo(screenX, screenY);
      }
    }

    if (firstVisiblePoint != null) {
      canvas.drawPath(path, paint);

      // Label at the left edge of the line
      final label = _formatDec(dec);
      _drawLabel(canvas, size, firstVisiblePoint, label, alignment: _LabelEdge.left);
    }
  }

  /// Draw a line of constant RA across the visible Dec range
  void _drawRaLine(
    Canvas canvas,
    Size size,
    double ra,
    double raNorm,
    double minDec,
    double maxDec,
    Paint paint,
  ) {
    final path = ui.Path();
    var started = false;
    Offset? firstVisiblePoint;

    for (var i = 0; i <= _samplesPerLine; i++) {
      final t = i / _samplesPerLine;
      final dec = minDec + t * (maxDec - minDec);

      final pixel = plateSolve.skyToPixelUnclamped(raNorm, dec);
      if (pixel == null) {
        started = false;
        continue;
      }

      final screenX = pixel.x * zoomLevel + imageOffset.dx;
      final screenY = pixel.y * zoomLevel + imageOffset.dy;
      final point = Offset(screenX, screenY);

      if (!started) {
        path.moveTo(screenX, screenY);
        started = true;
        if (firstVisiblePoint == null) firstVisiblePoint = point;
      } else {
        path.lineTo(screenX, screenY);
      }
    }

    if (firstVisiblePoint != null) {
      canvas.drawPath(path, paint);

      // Label at the top edge of the line
      final label = _formatRa(raNorm);
      _drawLabel(canvas, size, firstVisiblePoint, label, alignment: _LabelEdge.top);
    }
  }

  /// Draw a text label with a semi-transparent background at a given position
  void _drawLabel(
    Canvas canvas,
    Size size,
    Offset position,
    String text, {
    required _LabelEdge alignment,
  }) {
    final textStyle = ui.TextStyle(
      color: _labelColor,
      fontSize: 9,
      fontFamily: 'monospace',
    );
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      maxLines: 1,
    ))
      ..pushStyle(textStyle)
      ..addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 80));

    final textWidth = paragraph.longestLine;
    final textHeight = paragraph.height;
    const padding = 2.0;

    // Position label near the edge
    double labelX;
    double labelY;

    switch (alignment) {
      case _LabelEdge.left:
        // Clamp to left edge, vertically at the point
        labelX = position.dx.clamp(2.0, size.width - textWidth - padding * 2);
        labelY = (position.dy - textHeight / 2).clamp(2.0, size.height - textHeight - padding * 2);
      case _LabelEdge.top:
        // Horizontally at the point, clamp to top edge
        labelX = (position.dx - textWidth / 2).clamp(2.0, size.width - textWidth - padding * 2);
        labelY = position.dy.clamp(2.0, size.height - textHeight - padding * 2);
    }

    // Draw background
    final bgRect = Rect.fromLTWH(
      labelX - padding,
      labelY - padding,
      textWidth + padding * 2,
      textHeight + padding * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2)),
      Paint()..color = _labelBgColor,
    );

    // Draw text
    canvas.drawParagraph(paragraph, Offset(labelX, labelY));
  }

  /// Select appropriate grid spacing for the given FOV
  double _selectSpacing(double fovDeg) {
    // Target 5-8 grid lines across the image
    const targetLines = 6.0;

    // For narrow fields (< 1 degree), use arcminute-scale spacings
    if (fovDeg < 1.0) {
      for (final spacing in _narrowSpacingsDeg) {
        final lines = fovDeg / spacing;
        if (lines >= 4 && lines <= 10) return spacing;
      }
      // Fallback: pick the spacing giving closest to target lines
      var bestSpacing = _narrowSpacingsDeg.last;
      var bestDiff = double.infinity;
      for (final spacing in _narrowSpacingsDeg) {
        final diff = ((fovDeg / spacing) - targetLines).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestSpacing = spacing;
        }
      }
      return bestSpacing;
    }

    // For wider fields, use degree-scale spacings
    for (final spacing in _wideSpacingsDeg) {
      final lines = fovDeg / spacing;
      if (lines >= 4 && lines <= 10) return spacing;
    }

    // Fallback: pick the spacing giving closest to target lines
    var bestSpacing = _wideSpacingsDeg.last;
    var bestDiff = double.infinity;
    for (final spacing in _wideSpacingsDeg) {
      final diff = ((fovDeg / spacing) - targetLines).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestSpacing = spacing;
      }
    }
    return bestSpacing;
  }

  /// Compute the RA range handling the 0h/24h wraparound.
  /// Returns (min, max) where max may exceed 360 if the range wraps.
  ({double min, double max}) _computeRaRange(List<double> raValues) {
    if (raValues.isEmpty) return (min: 0.0, max: 360.0);

    // Sort RA values
    final sorted = List<double>.from(raValues)..sort();

    // Find the largest gap between consecutive RA values
    var maxGap = 0.0;
    var gapEnd = 0;
    for (var i = 0; i < sorted.length; i++) {
      final next = (i + 1) % sorted.length;
      var gap = sorted[next] - sorted[i];
      if (next == 0) gap = (360.0 - sorted[i]) + sorted[0];
      if (gap > maxGap) {
        maxGap = gap;
        gapEnd = next;
      }
    }

    // The range starts at the end of the largest gap
    final minRa = sorted[gapEnd];
    final lastIdx = (gapEnd - 1 + sorted.length) % sorted.length;
    var maxRa = sorted[lastIdx];

    // If the range wraps around 0, adjust maxRa
    if (maxRa < minRa) {
      maxRa += 360.0;
    }

    return (min: minRa, max: maxRa);
  }

  /// Format RA (degrees) as HH:MM
  String _formatRa(double raDeg) {
    var ra = raDeg;
    while (ra < 0) ra += 360;
    while (ra >= 360) ra -= 360;
    final totalHours = ra / 15.0;
    final hours = totalHours.floor();
    final minutes = ((totalHours - hours) * 60).round();
    return '${hours.toString().padLeft(2, '0')}h${minutes.toString().padLeft(2, '0')}m';
  }

  /// Format Dec (degrees) as +/-DD°MM'
  String _formatDec(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '-';
    final absDec = decDeg.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).round();
    return "$sign${degrees.toString().padLeft(2, '0')}°${minutes.toString().padLeft(2, '0')}'";
  }

  @override
  bool shouldRepaint(covariant CelestialGridPainter oldDelegate) {
    return oldDelegate.plateSolve != plateSolve ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.imageOffset != imageOffset;
  }
}

enum _LabelEdge { left, top }
