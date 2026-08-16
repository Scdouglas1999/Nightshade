part of '../overlay_painters.dart';

/// Bottom space the viewport's corner readouts occupy, so the painters anchored
/// to the same corners can stay off them.
///
/// Each is the readout's 16px anchor plus its height plus a gap. The histogram
/// is a fixed 80px tall ([HistogramWidget]); the image-stats card is four
/// [StatLine]s inside 12px padding, which measures 110px at the shipped type
/// scale. Both are pinned by a layout test that measures the real widgets, so a
/// readout that grows fails that test rather than silently colliding again.
abstract final class PreviewReadoutInsets {
  static const double histogram = 16 + 80 + 8;
  static const double stats = 16 + 110 + 8;
}

class CompassOverlayPainter extends CustomPainter {
  /// WCS rotation angle in degrees (position angle, North through East).
  final double rotationDegrees;

  /// Radius of the compass circle in logical pixels.
  final double radius;

  /// Margin from the corner of the canvas.
  final double margin;

  /// Space to leave at the bottom of the canvas, when the corner it anchors to
  /// is already occupied. Defaults to [margin].
  final double? bottomMargin;

  CompassOverlayPainter({
    required this.rotationDegrees,
    this.radius = 60.0,
    this.margin = 20.0,
    this.bottomMargin,
  });

  /// The circle this painter will draw on a canvas of [size].
  ///
  /// Exposed so a layout test can prove the rose does not land under the
  /// bottom-right stats readout — a separately-anchored sibling in the same
  /// stack, which nothing else constrains it against.
  Rect boundsIn(Size size) {
    final center = _centerIn(size);
    return Rect.fromCircle(center: center, radius: radius);
  }

  Offset _centerIn(Size size) => Offset(
        size.width - margin - radius,
        size.height - (bottomMargin ?? margin) - radius,
      );

  @override
  void paint(Canvas canvas, Size size) {
    // Position in bottom-right corner
    final center = _centerIn(size);
    final centerX = center.dx;
    final centerY = center.dy;

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

    // North arrow
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

    // East arrow (perpendicular to north, 90 degrees clockwise on sky)
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
        fontSize: NightshadeTypography.fontSize13,
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
        oldDelegate.margin != margin ||
        oldDelegate.bottomMargin != bottomMargin;
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

  /// Space to leave at the bottom of the canvas, when the corner it anchors to
  /// is already occupied. Defaults to [margin].
  final double? bottomMargin;

  ScaleBarPainter({
    required this.pixelScaleArcsecPerPixel,
    required this.imageWidthPixels,
    required this.zoomLevel,
    this.margin = 20.0,
    this.bottomMargin,
  });

  /// Y of the bar itself on a canvas of [size]. The label sits below it and the
  /// background plate extends ~8px above; exposed so a layout test can prove the
  /// bar clears the bottom-left histogram card it shares the stack with.
  double barBaselineIn(Size size) =>
      size.height - (bottomMargin ?? margin) - 12;

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
    final barY = barBaselineIn(size);
    final barX = margin;

    // Semi-transparent background behind the bar and label
    const bgPadding = 8.0;
    const tickHeight = 8.0;

    // Measure text first so we can size the background
    final textSpan = TextSpan(
      text: bestLabel,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: NightshadeTypography.fontSize12,
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
      const Radius.circular(NightshadeTokens.radiusInline4),
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
        oldDelegate.margin != margin ||
        oldDelegate.bottomMargin != bottomMargin;
  }
}

/// Celestial coordinate grid overlay that renders RA/Dec grid lines
/// projected onto the image using plate solve WCS data.
///
/// Grid spacing is automatically selected based on the field of view to
/// produce approximately 5-8 grid lines across the image. Lines of constant
/// RA appear as curves (due to gnomonic projection) and are labeled in
