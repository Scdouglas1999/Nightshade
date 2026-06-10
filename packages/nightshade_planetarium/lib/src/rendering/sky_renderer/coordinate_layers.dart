// ignore_for_file: unused_element, unused_field

part of '../sky_renderer.dart';

extension _SkyCanvasPainterCoordinateLayers on SkyCanvasPainter {
  void _drawEquatorialGrid(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    // Use cached paint object instead of creating new one
    final paint = _PaintCache.getGridPaint(config.gridColor);

    final fov = viewState.fieldOfView;

    // Adaptive grid spacing based on FOV
    double raSpacing; // hours
    double decSpacing; // degrees
    double decStep; // interpolation step

    if (fov > 60) {
      raSpacing = 2.0; // Every 2 hours (30 deg)
      decSpacing = 30.0;
      decStep = 5.0;
    } else if (fov > 30) {
      raSpacing = 1.0; // Every hour (15 deg)
      decSpacing = 15.0;
      decStep = 3.0;
    } else if (fov > 10) {
      raSpacing = 0.5; // Every 30 min
      decSpacing = 10.0;
      decStep = 2.0;
    } else {
      raSpacing = 0.25; // Every 15 min
      decSpacing = 5.0;
      decStep = 1.0;
    }

    // Draw RA lines with adaptive spacing. Each sample point is cheaply culled
    // (dot product against the view center) BEFORE the projection trig, so a
    // narrow FOV only projects the small window that can be visible instead of
    // the whole 24h x 180deg grid.
    for (var ra = 0.0; ra < 24; ra += raSpacing) {
      final path = Path();
      var firstPoint = true;
      final raDeg = ra * 15;

      for (var dec = -90.0; dec <= 90; dec += decStep) {
        if (_cull!.isCulled(raDeg, dec)) {
          firstPoint = true;
          continue;
        }
        final offset = _celestialToScreen(
          CelestialCoordinate(ra: ra, dec: dec),
          center,
          scale,
        );

        if (offset != null && _isInView(offset, size)) {
          if (firstPoint) {
            path.moveTo(offset.dx, offset.dy);
            firstPoint = false;
          } else {
            path.lineTo(offset.dx, offset.dy);
          }
        } else {
          firstPoint = true;
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw Dec lines with adaptive spacing
    for (var dec = -90.0 + decSpacing; dec < 90; dec += decSpacing) {
      final path = Path();
      var firstPoint = true;

      final raStep = fov > 30 ? 0.5 : 0.25;
      for (var ra = 0.0; ra <= 24; ra += raStep) {
        if (_cull!.isCulled(ra * 15, dec)) {
          firstPoint = true;
          continue;
        }
        final offset = _celestialToScreen(
          CelestialCoordinate(ra: ra, dec: dec),
          center,
          scale,
        );

        if (offset != null && _isInView(offset, size)) {
          if (firstPoint) {
            path.moveTo(offset.dx, offset.dy);
            firstPoint = false;
          } else {
            path.lineTo(offset.dx, offset.dy);
          }
        } else {
          firstPoint = true;
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw grid labels at major intersections when zoomed out
    if (fov > 20) {
      _drawGridLabels(canvas, size, center, scale, raSpacing, decSpacing);
    }
  }

  void _drawGridLabels(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
    double raSpacing,
    double decSpacing,
  ) {
    final textStyle = TextStyle(
      color: config.gridColor.withValues(alpha: 0.7),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Draw RA labels along dec=0 (celestial equator)
    for (var ra = 0.0; ra < 24; ra += raSpacing * 2) {
      final offset = _celestialToScreen(
        CelestialCoordinate(ra: ra, dec: 0),
        center,
        scale,
      );

      if (offset != null && _isInView(offset, size)) {
        final hours = ra.floor();
        final minutes = ((ra - hours) * 60).round();
        final label = minutes == 0 ? '${hours}h' : '${hours}h${minutes}m';

        // Use cached TextPainter
        final textPainter = _TextCache.get(label, textStyle);
        textPainter.paint(canvas, offset + Offset(-textPainter.width / 2, 4));
      }
    }

    // Draw Dec labels along RA=0
    for (var dec = -60.0; dec <= 60; dec += decSpacing) {
      if (dec == 0) continue; // Skip equator label to avoid overlap

      final offset = _celestialToScreen(
        CelestialCoordinate(ra: 0, dec: dec),
        center,
        scale,
      );

      if (offset != null && _isInView(offset, size)) {
        final label = dec > 0 ? '+${dec.toInt()}°' : '${dec.toInt()}°';

        // Use cached TextPainter
        final textPainter = _TextCache.get(label, textStyle);
        textPainter.paint(canvas, offset + Offset(4, -textPainter.height / 2));
      }
    }
  }

  void _drawZenithMarker(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    // Calculate zenith position (altitude 90 degrees)
    final lst = AstronomyCalculations.localSiderealTime(
      observationTime,
      longitude,
    );
    final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
      altDeg: 90.0,
      azDeg: 0.0,
      latitudeDeg: latitude,
      lstHours: lst,
    );

    final zenithPos = _celestialToScreen(
      CelestialCoordinate(ra: ra / 15, dec: dec),
      center,
      scale,
    );
    if (zenithPos == null || !_isInView(zenithPos, size)) return;

    // Draw crosshair - use cached paint
    final paint = _PaintCache.getZenithCrossPaint(
      Colors.white.withValues(alpha: 0.4),
    );

    const length = 12.0;
    canvas.drawLine(
      zenithPos - const Offset(length, 0),
      zenithPos + const Offset(length, 0),
      paint,
    );
    canvas.drawLine(
      zenithPos - const Offset(0, length),
      zenithPos + const Offset(0, length),
      paint,
    );

    // Draw "Z" label - use cached TextPainter
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );
    final labelPaint = _TextCache.get('Z', textStyle);
    labelPaint.paint(
      canvas,
      zenithPos + Offset(length + 4, -labelPaint.height / 2),
    );
  }

  void _drawAltAzGrid(Canvas canvas, Size size, Offset center, double scale) {
    // Use cached paint instead of creating new one each frame
    final paint = _PaintCache.getAltAzPaint(
      config.gridColor.withValues(alpha: 0.3),
    );

    final lst = AstronomyCalculations.localSiderealTime(
      observationTime,
      longitude,
    );

    // Draw altitude circles
    for (var alt = 0; alt <= 90; alt += 30) {
      final path = Path();
      var firstPoint = true;

      for (var az = 0.0; az <= 360; az += 5) {
        // Convert alt/az to RA/Dec
        final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
          altDeg: alt.toDouble(),
          azDeg: az,
          latitudeDeg: latitude,
          lstHours: lst,
        );

        // Cull before projecting (ra is in degrees here).
        if (_cull!.isCulled(ra, dec)) {
          firstPoint = true;
          continue;
        }

        final offset = _celestialToScreen(
          CelestialCoordinate(ra: ra / 15, dec: dec),
          center,
          scale,
        );

        if (offset != null && _isInView(offset, size)) {
          if (firstPoint) {
            path.moveTo(offset.dx, offset.dy);
            firstPoint = false;
          } else {
            path.lineTo(offset.dx, offset.dy);
          }
        } else {
          firstPoint = true;
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  void _drawEcliptic(Canvas canvas, Size size, Offset center, double scale) {
    // Use cached paint instead of creating new one each frame
    final paint = _PaintCache.getEclipticPaint(config.eclipticColor);

    final path = Path();
    var firstPoint = true;

    // Draw ecliptic as a great circle
    for (var lon = 0.0; lon <= 360; lon += 2) {
      final (ra, dec) = AstronomyCalculations.eclipticToEquatorial(
        lonDeg: lon,
        latDeg: 0,
        obliquityDeg: 23.44,
      );

      if (_cull!.isCulled(ra, dec)) {
        firstPoint = true;
        continue;
      }

      final offset = _celestialToScreen(
        CelestialCoordinate(ra: ra / 15, dec: dec),
        center,
        scale,
      );

      if (offset != null && _isInView(offset, size)) {
        if (firstPoint) {
          path.moveTo(offset.dx, offset.dy);
          firstPoint = false;
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      } else {
        firstPoint = true;
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawGalacticPlane(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    final paint = _PaintCache.getGalacticPlanePaint(config.galacticPlaneColor);

    final path = Path();
    var firstPoint = true;

    // Draw galactic equator as a great circle at galactic latitude 0
    for (var lon = 0.0; lon <= 360; lon += 2) {
      final (ra, dec) = AstronomyCalculations.galacticToEquatorial(
        lonDeg: lon,
        latDeg: 0,
      );

      if (_cull!.isCulled(ra, dec)) {
        firstPoint = true;
        continue;
      }

      final offset = _celestialToScreen(
        CelestialCoordinate(ra: ra / 15, dec: dec),
        center,
        scale,
      );

      if (offset != null && _isInView(offset, size)) {
        if (firstPoint) {
          path.moveTo(offset.dx, offset.dy);
          firstPoint = false;
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      } else {
        firstPoint = true;
      }
    }

    canvas.drawPath(path, paint);

    // Draw "Galactic Equator" label at galactic center direction (l=0, b=0)
    final (labelRa, labelDec) = AstronomyCalculations.galacticToEquatorial(
      lonDeg: 0,
      latDeg: 0,
    );
    final labelOffset = _celestialToScreen(
      CelestialCoordinate(ra: labelRa / 15, dec: labelDec),
      center,
      scale,
    );
    if (labelOffset != null && _isInView(labelOffset, size)) {
      final textStyle = TextStyle(
        color: config.galacticPlaneColor.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
      final textPainter = _TextCache.get('Galactic Eq.', textStyle);

      final preferredPos =
          labelOffset + Offset(-textPainter.width / 2, -textPainter.height - 4);
      final labelPos = _labelManager.findPlacement(
        preferredPos,
        Size(textPainter.width, textPainter.height),
        size,
      );
      if (labelPos != null) {
        textPainter.paint(canvas, labelPos);
      }
    }
  }

  void _drawMeridianLine(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    if (!config.showMeridian) return;

    final lst = AstronomyCalculations.localSiderealTime(
      observationTime,
      longitude,
    );

    // Draw line from horizon to zenith along the meridian (azimuth 0/180)
    final path = Path();
    var firstPoint = true;

    for (var alt = 0.0; alt <= 90; alt += 2) {
      final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
        altDeg: alt,
        azDeg: 0.0, // North meridian
        latitudeDeg: latitude,
        lstHours: lst,
      );

      final pos = _celestialToScreen(
        CelestialCoordinate(ra: ra / 15, dec: dec),
        center,
        scale,
      );
      if (pos != null && _isInView(pos, size)) {
        if (firstPoint) {
          path.moveTo(pos.dx, pos.dy);
          firstPoint = false;
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      } else {
        firstPoint = true;
      }
    }

    // Also draw the south meridian
    firstPoint = true;
    for (var alt = 0.0; alt <= 90; alt += 2) {
      final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
        altDeg: alt,
        azDeg: 180.0, // South meridian
        latitudeDeg: latitude,
        lstHours: lst,
      );

      final pos = _celestialToScreen(
        CelestialCoordinate(ra: ra / 15, dec: dec),
        center,
        scale,
      );
      if (pos != null && _isInView(pos, size)) {
        if (firstPoint) {
          path.moveTo(pos.dx, pos.dy);
          firstPoint = false;
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      } else {
        firstPoint = true;
      }
    }

    // Use cached paint instead of creating new one each frame
    final paint = _PaintCache.getMeridianPaint(
      Colors.green.withValues(alpha: 0.4),
    );
    canvas.drawPath(path, paint);
  }
}
