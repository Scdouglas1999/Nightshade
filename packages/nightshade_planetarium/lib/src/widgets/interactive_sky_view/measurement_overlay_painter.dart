part of '../interactive_sky_view.dart';

/// Angular-measurement overlay: a ruler between two sky points showing their
/// great-circle separation and the position angle of the end point as seen
/// from the start (North-through-East convention).
///
/// The endpoints are stored as celestial coordinates so the ruler stays pinned
/// to the sky as the user pans or zooms — each paint re-projects them through
/// the same stereographic geometry the interaction layer uses, so the drawn
/// line always lands exactly where the user dragged.
///
/// This is a pure overlay painter. It is mounted on the animated overlay
/// RepaintBoundary, so drawing/clearing the ruler never repaints the expensive
/// static base layer.
class _MeasurementOverlayPainter extends CustomPainter {
  final SkyViewState viewState;
  final CelestialCoordinate start;
  final CelestialCoordinate end;

  /// Local sidereal time (hours) at the current epoch, required to project in
  /// the horizontal view frame. Null in the equatorial frame.
  final double? lstHours;

  /// Observer latitude (degrees), required for the horizontal-frame projection.
  final double latitude;

  static const Color _lineColor = Color(0xFF7DD3FC); // sky-300, schematic cyan
  static const double _deg2rad = math.pi / 180;
  static const double _rad2deg = 180 / math.pi;

  _MeasurementOverlayPainter({
    required this.viewState,
    required this.start,
    required this.end,
    required this.lstHours,
    required this.latitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (viewState.fieldOfView / 2);

    final p1 = _project(start, center, scale);
    final p2 = _project(end, center, scale);
    if (p1 == null || p2 == null) return;

    final separationDeg = AstronomyCalculations.angularSeparation(
      ra1Deg: start.ra * 15,
      dec1Deg: start.dec,
      ra2Deg: end.ra * 15,
      dec2Deg: end.dec,
    );
    final positionAngleDeg = AstronomyCalculations.positionAngle(
      ra1Deg: start.ra * 15,
      dec1Deg: start.dec,
      ra2Deg: end.ra * 15,
      dec2Deg: end.dec,
    );

    // Connecting line.
    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(p1, p2, linePaint);

    // End-point markers (small tick rings).
    final markerPaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(p1, 4, markerPaint);
    canvas.drawCircle(p2, 4, markerPaint);

    _paintReadout(
      canvas,
      size: size,
      anchor: p2,
      separationDeg: separationDeg,
      positionAngleDeg: positionAngleDeg,
    );
  }

  /// Project a celestial coordinate to the screen using the same stereographic
  /// geometry as the interaction layer's inverse map (see
  /// [_InteractiveSkyViewState._inverseStereographic]), so the ruler endpoints
  /// land exactly under the cursor in both view frames.
  Offset? _project(CelestialCoordinate coord, Offset center, double scale) {
    double lonDeg;
    double latDeg;
    double centerLonDeg;
    double centerLatDeg;

    if (viewState.viewMode == SkyViewMode.horizontal && lstHours != null) {
      final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
        raDeg: coord.ra * 15,
        decDeg: coord.dec,
        latitudeDeg: latitude,
        lstHours: lstHours!,
      );
      lonDeg = -az;
      latDeg = alt;
      centerLonDeg = -viewState.centerAz;
      centerLatDeg = viewState.centerAltitude;
    } else {
      lonDeg = coord.ra * 15;
      latDeg = coord.dec;
      centerLonDeg = viewState.centerRA * 15;
      centerLatDeg = viewState.centerDec;
    }

    final lon1 = centerLonDeg * _deg2rad;
    final lat1 = centerLatDeg * _deg2rad;
    final lon2 = lonDeg * _deg2rad;
    final lat2 = latDeg * _deg2rad;

    final cosc =
        math.sin(lat1) * math.sin(lat2) +
        math.cos(lat1) * math.cos(lat2) * math.cos(lon2 - lon1);

    // Behind the projection plane.
    if (cosc < 0.01) return null;

    final k = 2 / (1 + cosc);
    final x = k * math.cos(lat2) * math.sin(lon2 - lon1);
    final y =
        k *
        (math.cos(lat1) * math.sin(lat2) -
            math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1));

    final rotRad = viewState.rotation * _deg2rad;
    final xRot = x * math.cos(rotRad) - y * math.sin(rotRad);
    final yRot = x * math.sin(rotRad) + y * math.cos(rotRad);

    return Offset(
      center.dx - xRot * scale * _rad2deg,
      center.dy - yRot * scale * _rad2deg,
    );
  }

  void _paintReadout(
    Canvas canvas, {
    required Size size,
    required Offset anchor,
    required double separationDeg,
    required double positionAngleDeg,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            '${_formatSeparation(separationDeg)}\n'
            'PA ${positionAngleDeg.toStringAsFixed(1)}°',
        style: const TextStyle(
          color: _lineColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Place the readout offset from the end marker, then nudge it back inside
    // the canvas so a measurement near the right/bottom edge stays readable.
    const pad = 6.0;
    final boxWidth = textPainter.width + pad * 2;
    final boxHeight = textPainter.height + pad * 2;
    var origin = Offset(anchor.dx + 10, anchor.dy + 10);
    if (origin.dx - pad + boxWidth > size.width) {
      origin = Offset(size.width - boxWidth + pad, origin.dy);
    }
    if (origin.dx - pad < 0) {
      origin = Offset(pad, origin.dy);
    }
    if (origin.dy - pad + boxHeight > size.height) {
      origin = Offset(origin.dx, size.height - boxHeight + pad);
    }
    if (origin.dy - pad < 0) {
      origin = Offset(origin.dx, pad);
    }
    final bg = Rect.fromLTWH(
      origin.dx - pad,
      origin.dy - pad,
      boxWidth,
      boxHeight,
    );

    final bgPaint = Paint()..color = const Color(0xCC0B1622);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(4)),
      bgPaint,
    );
    final borderPaint = Paint()
      ..color = _lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(4)),
      borderPaint,
    );

    textPainter.paint(canvas, origin);
  }

  /// Format an angular separation with the most readable unit: degrees for
  /// wide spans, arcminutes for sub-degree, arcseconds for very tight pairs.
  static String _formatSeparation(double degrees) {
    if (degrees >= 1.0) {
      return '${degrees.toStringAsFixed(2)}°';
    }
    final arcmin = degrees * 60;
    if (arcmin >= 1.0) {
      return "${arcmin.toStringAsFixed(1)}'";
    }
    final arcsec = degrees * 3600;
    return '${arcsec.toStringAsFixed(1)}"';
  }

  @override
  bool shouldRepaint(covariant _MeasurementOverlayPainter oldDelegate) {
    return viewState != oldDelegate.viewState ||
        start != oldDelegate.start ||
        end != oldDelegate.end ||
        lstHours != oldDelegate.lstHours ||
        latitude != oldDelegate.latitude;
  }
}
