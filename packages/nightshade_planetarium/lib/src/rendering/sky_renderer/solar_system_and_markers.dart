// ignore_for_file: unused_element, unused_field

part of '../sky_renderer.dart';

extension _SkyCanvasPainterSolarSystemAndMarkers on SkyCanvasPainter {
  void _drawCardinalDirections(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final directions = ['N', 'E', 'S', 'W'];
    final positions = [
      Offset(size.width / 2, 20),
      Offset(size.width - 20, size.height / 2),
      Offset(size.width / 2, size.height - 20),
      Offset(20, size.height / 2),
    ];

    for (var i = 0; i < 4; i++) {
      // Use cached TextPainter
      final textPainter = _TextCache.get(directions[i], textStyle);
      textPainter.paint(
        canvas,
        positions[i] - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawSelectionMarker(
    Canvas canvas,
    Offset center,
    double scale,
    CelestialCoordinate coord,
  ) {
    final offset = _celestialToScreen(coord, center, scale);
    if (offset == null) return;

    // Apply animation if enabled
    double pulseScale = 1.0;
    double glowOpacity = 0.3;
    if (qualityConfig.enableSelectionAnimation &&
        selectionAnimationPhase != null) {
      // Sinusoidal pulse between 1.0 and 1.1
      pulseScale = 1.0 + 0.1 * math.sin(selectionAnimationPhase! * 2 * math.pi);
      // Pulsing glow opacity
      glowOpacity =
          0.2 + 0.2 * math.sin(selectionAnimationPhase! * 2 * math.pi);
    }

    const baseColor = Color(0xFF00E676);

    // Draw animated glow behind the marker - use cached blur
    if (qualityConfig.enableSelectionAnimation && glowOpacity > 0) {
      if (qualityConfig.useBlurEffects) {
        final glowPaint = _PaintCache.getBlurPaint(
          12,
          baseColor,
          alpha: glowOpacity,
        );
        canvas.drawCircle(offset, 20 * pulseScale, glowPaint);
      } else {
        final glowPaint = Paint()
          ..color = baseColor.withValues(alpha: glowOpacity);
        canvas.drawCircle(offset, 20 * pulseScale, glowPaint);
      }
    }

    final paint = Paint()
      ..color = baseColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw crosshairs with pulse
    final circleRadius = 15 * pulseScale;
    final innerOffset = 20 * pulseScale;
    final outerOffset = 25 * pulseScale;

    canvas.drawCircle(offset, circleRadius, paint);
    canvas.drawLine(
      offset - Offset(outerOffset, 0),
      offset - Offset(innerOffset, 0),
      paint,
    );
    canvas.drawLine(
      offset + Offset(innerOffset, 0),
      offset + Offset(outerOffset, 0),
      paint,
    );
    canvas.drawLine(
      offset - Offset(0, outerOffset),
      offset - Offset(0, innerOffset),
      paint,
    );
    canvas.drawLine(
      offset + Offset(0, innerOffset),
      offset + Offset(0, outerOffset),
      paint,
    );
  }

  void _drawMountPositionMarker(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
    CelestialCoordinate coord,
    MountRenderStatus status,
  ) {
    final offset = _celestialToScreen(coord, center, scale);
    if (offset == null) return;

    // Color based on tracking status
    Color markerColor;
    switch (status) {
      case MountRenderStatus.tracking:
        markerColor = const Color(0xFF4CAF50); // Green for tracking
        break;
      case MountRenderStatus.slewing:
        markerColor = const Color(0xFFFF9800); // Orange for slewing
        break;
      case MountRenderStatus.parked:
        markerColor = const Color(0xFF9E9E9E); // Gray for parked
        break;
      case MountRenderStatus.stopped:
        markerColor = const Color(0xFFE53935); // Red for stopped
        break;
      case MountRenderStatus.disconnected:
        return; // Don't draw if disconnected
    }

    // Outer glow - use cached blur
    if (qualityConfig.useBlurEffects) {
      final glowPaint = _PaintCache.getBlurPaint(8, markerColor, alpha: 0.3);
      canvas.drawCircle(offset, 20, glowPaint);
    } else {
      final glowPaint = Paint()..color = markerColor.withValues(alpha: 0.3);
      canvas.drawCircle(offset, 20, glowPaint);
    }

    // Main crosshair with thicker lines
    final paint = Paint()
      ..color = markerColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Draw a distinctive mount marker (different from selection marker)
    // Outer circle
    canvas.drawCircle(offset, 18, paint);

    // Inner crosshair lines - extending to edge of circle
    paint.strokeWidth = 2;
    canvas.drawLine(
      offset - const Offset(30, 0),
      offset - const Offset(18, 0),
      paint,
    );
    canvas.drawLine(
      offset + const Offset(18, 0),
      offset + const Offset(30, 0),
      paint,
    );
    canvas.drawLine(
      offset - const Offset(0, 30),
      offset - const Offset(0, 18),
      paint,
    );
    canvas.drawLine(
      offset + const Offset(0, 18),
      offset + const Offset(0, 30),
      paint,
    );

    // Inner dot
    final dotPaint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offset, 3, dotPaint);

    // Draw status label below the marker
    final statusText = switch (status) {
      MountRenderStatus.tracking => 'TRACKING',
      MountRenderStatus.slewing => 'SLEWING',
      MountRenderStatus.parked => 'PARKED',
      MountRenderStatus.stopped => 'STOPPED',
      MountRenderStatus.disconnected => '',
    };

    if (statusText.isNotEmpty) {
      final textStyle = TextStyle(
        color: markerColor,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      );
      final textPainter = TextPainter(
        text: TextSpan(text: statusText, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      // Background for better readability
      final bgRect = Rect.fromCenter(
        center: offset + const Offset(0, 35),
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      );
      final bgPaint = Paint()..color = const Color(0xCC000000);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        bgPaint,
      );

      textPainter.paint(
        canvas,
        offset + Offset(-textPainter.width / 2, 35 - textPainter.height / 2),
      );
    }
  }

  void _drawSun(Canvas canvas, Size size, Offset center, double scale) {
    if (sunPosition == null) return;

    final (ra, dec) = sunPosition!;
    final coord = CelestialCoordinate(
      ra: ra / 15,
      dec: dec,
    ); // ra is in degrees, convert to hours
    final offset = _celestialToScreen(coord, center, scale);
    if (offset == null) return;

    const sunColor = Color(0xFFFFEB3B);

    // Outer glow
    _drawGlow(canvas, offset, 25, sunColor, 20.0, opacity: 0.25);

    // Mid glow
    _drawGlow(canvas, offset, 15, sunColor, 10.0, opacity: 0.5);

    // Sun disc (always drawn)
    final sunPaint = Paint()
      ..color = sunColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offset, 10, sunPaint);

    // Sun label
    const textStyle = TextStyle(
      color: sunColor,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      text: const TextSpan(text: 'SUN', style: textStyle),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset + Offset(-textPainter.width / 2, 18));
  }

  void _drawMoon(Canvas canvas, Size size, Offset center, double scale) {
    if (moonPosition == null) return;

    final (ra, dec, illumination) = moonPosition!;
    final coord = CelestialCoordinate(
      ra: ra / 15,
      dec: dec,
    ); // ra is in degrees, convert to hours
    final offset = _celestialToScreen(coord, center, scale);
    if (offset == null) return;

    // Moon apparent diameter ~31 arcminutes (0.517 degrees)
    // Scale with zoom so it appears correct relative to the sky
    const apparentSizeDeg = 31.0 / 60.0;
    final moonPixelRadius = (apparentSizeDeg / 2) * scale;
    final moonRadius = moonPixelRadius.clamp(8.0, 80.0);

    // Glow scaled to moon size
    final glowRadius = moonRadius * 1.6;
    if (qualityConfig.useBlurEffects) {
      final glowPaint = _PaintCache.getBlurPaint(
        moonRadius * 0.8,
        const Color(0xFFB0BEC5),
        alpha: 0.19,
      );
      canvas.drawCircle(offset, glowRadius, glowPaint);
    } else {
      final glowPaint = Paint()..color = const Color(0x30B0BEC5);
      canvas.drawCircle(offset, glowRadius, glowPaint);
    }

    // Moon base (dark side)
    final darkPaint = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(offset, moonRadius, darkPaint);

    // Phase rendering using terminator arc
    // illumination: 0 = new moon, 1 = full moon (fraction 0..1)
    final litPaint = Paint()
      ..color = const Color(0xFFECEFF1)
      ..style = PaintingStyle.fill;

    if (illumination > 0.01) {
      canvas.save();
      // Clip to moon disc using path for proper circular clip
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: offset, radius: moonRadius));
      canvas.clipPath(clipPath);

      if (illumination > 0.98) {
        // Full moon
        canvas.drawCircle(offset, moonRadius, litPaint);
      } else if (illumination >= 0.5) {
        // Gibbous: draw full lit, then dark terminator ellipse
        canvas.drawCircle(offset, moonRadius, litPaint);
        final terminatorWidth =
            moonRadius * 2 * math.cos(math.pi * (2 * illumination - 1));
        final darkTerminator = Paint()
          ..color = const Color(0xFF37474F)
          ..style = PaintingStyle.fill;
        canvas.drawOval(
          Rect.fromCenter(
            center: offset + Offset(moonRadius - terminatorWidth.abs() / 2, 0),
            width: terminatorWidth.abs(),
            height: moonRadius * 2,
          ),
          darkTerminator,
        );
      } else {
        // Crescent: draw lit terminator ellipse
        final terminatorWidth =
            moonRadius * 2 * math.cos(math.pi * (1 - 2 * illumination));
        canvas.drawOval(
          Rect.fromCenter(
            center: offset - Offset(moonRadius - terminatorWidth.abs() / 2, 0),
            width: terminatorWidth.abs(),
            height: moonRadius * 2,
          ),
          litPaint,
        );
      }
      canvas.restore();
    }

    // Moon outline
    final outlinePaint = Paint()
      ..color = const Color(0x60ECEFF1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = moonRadius > 20 ? 1.5 : 1.0;
    canvas.drawCircle(offset, moonRadius, outlinePaint);

    // Moon label with illumination %
    final illuminationPct = (illumination * 100).round();
    final labelStyle = TextStyle(
      color: const Color(0xFFB0BEC5),
      fontSize: moonRadius > 20 ? 11 : 10,
      fontWeight: FontWeight.w500,
    );
    final textPainter = _TextCache.get('MOON $illuminationPct%', labelStyle);
    final preferredPos =
        offset + Offset(-textPainter.width / 2, moonRadius + 6);
    final labelPos = _labelManager.findPlacement(
      preferredPos,
      Size(textPainter.width, textPainter.height),
      size,
    );
    if (labelPos != null) {
      textPainter.paint(canvas, labelPos);
    }
  }

  void _drawPlanets(Canvas canvas, Size size, Offset center, double scale) {
    for (final planet in planets) {
      // PlanetData has ra in hours and dec in degrees
      final coord = CelestialCoordinate(ra: planet.ra, dec: planet.dec);
      final offset = _celestialToScreen(coord, center, scale);
      if (offset == null) continue;

      // Convert int color to Color
      final planetColor = Color(planet.color);

      // Planet glow - use cached blur
      if (qualityConfig.useBlurEffects) {
        final glowPaint = _PaintCache.getBlurPaint(6, planetColor, alpha: 0.3);
        canvas.drawCircle(offset, 8, glowPaint);
      } else {
        final glowPaint = Paint()..color = planetColor.withValues(alpha: 0.3);
        canvas.drawCircle(offset, 8, glowPaint);
      }

      // Planet disc - size based on magnitude
      final radius = _magnitudeToRadius(planet.magnitude) * 1.5 + 2;
      final planetPaint = Paint()
        ..color = planetColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, radius, planetPaint);

      // Add planet-specific details in quality mode
      if (qualityConfig.enablePlanetDetails && radius > 3) {
        _drawPlanetDetails(canvas, offset, radius, planet.name, planetColor);
      }

      // Planet label with collision avoidance
      final fontSize = _getLabelFontSize(planet.magnitude, 'planet');
      final textStyle = TextStyle(
        color: planetColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w600, // Planets always prominent
      );
      final textPainter = TextPainter(
        text: TextSpan(text: planet.name.toUpperCase(), style: textStyle),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      // Find non-overlapping placement (preferred below planet)
      final preferredPos = offset + Offset(-textPainter.width / 2, radius + 4);
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

  /// Draw planet-specific details (Saturn rings, Jupiter bands)
  void _drawPlanetDetails(
    Canvas canvas,
    Offset center,
    double radius,
    String planetName,
    Color planetColor,
  ) {
    final name = planetName.toLowerCase();

    if (name == 'saturn') {
      _drawSaturnRings(canvas, center, radius, planetColor);
    } else if (name == 'jupiter') {
      _drawJupiterBands(canvas, center, radius, planetColor);
    } else if (name == 'mars') {
      _drawMarsPolarCap(canvas, center, radius);
    }
  }

  /// Draw Saturn's iconic ring system
  void _drawSaturnRings(
    Canvas canvas,
    Offset center,
    double radius,
    Color planetColor,
  ) {
    // Ring ellipse surrounding the planet
    final ringWidth = radius * 2.8;
    final ringHeight = radius * 0.8; // Tilted view

    // Outer ring (A ring)
    final outerRingPaint = Paint()
      ..color = const Color(0xFFD4C8A8).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.15;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: ringWidth, height: ringHeight),
      outerRingPaint,
    );

    // Inner ring (B ring - brighter)
    final innerRingPaint = Paint()
      ..color = const Color(0xFFE8DCC0).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.2;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: ringWidth * 0.75,
        height: ringHeight * 0.75,
      ),
      innerRingPaint,
    );

    // Cassini Division (dark gap)
    final divisionPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: ringWidth * 0.82,
        height: ringHeight * 0.82,
      ),
      divisionPaint,
    );

    // Redraw planet disc on top of back-side ring portion
    final planetPaint = Paint()
      ..color = planetColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, planetPaint);
  }

  /// Draw Jupiter's cloud bands
  void _drawJupiterBands(
    Canvas canvas,
    Offset center,
    double radius,
    Color planetColor,
  ) {
    // Subtle horizontal bands
    final bandPaint = Paint()
      ..color = const Color(0xFF8B6914).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.15;

    // Draw 3 bands at different latitudes
    for (final offset in [-0.5, 0.0, 0.5]) {
      final bandY = center.dy + radius * offset * 0.7;
      final bandWidth = radius * math.sqrt(1 - offset * offset * 0.5);

      canvas.drawLine(
        Offset(center.dx - bandWidth, bandY),
        Offset(center.dx + bandWidth, bandY),
        bandPaint,
      );
    }

    // Great Red Spot hint for larger renderings
    if (radius > 5) {
      final spotPaint = Paint()
        ..color = const Color(0xFFB86B4A).withValues(alpha: 0.4);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + radius * 0.3, center.dy + radius * 0.25),
          width: radius * 0.4,
          height: radius * 0.25,
        ),
        spotPaint,
      );
    }
  }

  /// Draw Mars polar ice cap hint
  void _drawMarsPolarCap(Canvas canvas, Offset center, double radius) {
    // Small white cap at the top
    final capPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);

    final capPath = Path();
    capPath.moveTo(center.dx - radius * 0.4, center.dy - radius * 0.7);
    capPath.quadraticBezierTo(
      center.dx,
      center.dy - radius * 1.1,
      center.dx + radius * 0.4,
      center.dy - radius * 0.7,
    );
    capPath.close();

    canvas.drawPath(capPath, capPaint);
  }

  /// Draw satellites as bright moving dots with labels.
  void _drawSatellites(Canvas canvas, Size size, Offset center, double scale) {
    const satelliteColor = Color(0xFFFFD740); // Amber/gold
    const eclipsedColor = Color(0x80FF6E40); // Dim orange for eclipsed

    for (final sat in satellites) {
      final coord = CelestialCoordinate(ra: sat.ra, dec: sat.dec);
      final offset = _celestialToScreen(coord, center, scale);
      if (offset == null) continue;
      if (!_isInView(offset, size)) continue;

      final color = sat.isEclipsed ? eclipsedColor : satelliteColor;
      final isIss = sat.name.contains('ISS') || sat.name.contains('ZARYA');
      final dotRadius = isIss ? 4.0 : 2.5;

      // Glow for illuminated satellites
      if (!sat.isEclipsed) {
        if (qualityConfig.useBlurEffects) {
          final glowPaint = _PaintCache.getBlurPaint(4, color, alpha: 0.4);
          canvas.drawCircle(offset, dotRadius + 3, glowPaint);
        } else {
          final glowPaint = Paint()..color = color.withValues(alpha: 0.3);
          canvas.drawCircle(offset, dotRadius + 3, glowPaint);
        }
      }

      // Main dot
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, dotRadius, dotPaint);

      // Cross-hair for ISS
      if (isIss && !sat.isEclipsed) {
        final crossPaint = Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;
        const crossSize = 8.0;
        canvas.drawLine(
          Offset(offset.dx - crossSize, offset.dy),
          Offset(offset.dx + crossSize, offset.dy),
          crossPaint,
        );
        canvas.drawLine(
          Offset(offset.dx, offset.dy - crossSize),
          Offset(offset.dx, offset.dy + crossSize),
          crossPaint,
        );
      }

      // Label for ISS and bright satellites above horizon
      if ((isIss || sat.elevation > 20) && !sat.isEclipsed) {
        final labelText = isIss ? 'ISS' : sat.name;
        final truncatedLabel = labelText.length > 16
            ? '${labelText.substring(0, 14)}..'
            : labelText;
        final textStyle = TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: isIss ? 11.0 : 9.0,
          fontWeight: isIss ? FontWeight.w600 : FontWeight.w400,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: truncatedLabel, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final preferredPos =
            offset + Offset(-textPainter.width / 2, dotRadius + 4);
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
  }

  /// Draw variable stars with distinctive double-ring markers.
  void _drawVariableStars(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    const varColor = Color(0xFF40C4FF); // Light blue for variable markers

    for (final vs in variableStars) {
      final coord = vs.coordinates;
      final offset = _celestialToScreen(coord, center, scale);
      if (offset == null) continue;
      if (!_isInView(offset, size)) continue;

      final estMag = vs.estimateMagnitude(observationTime);
      final magRange = vs.magMin - vs.magMax;
      final brightnessFraction = magRange > 0
          ? ((vs.magMin - estMag) / magRange).clamp(0.0, 1.0)
          : 0.5;

      // Outer ring (fixed size, bigger for brighter stars)
      final outerRadius = 5.0 + (8.0 - vs.magMax).clamp(0.0, 4.0);
      final outerPaint = Paint()
        ..color = varColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(offset, outerRadius, outerPaint);

      // Inner circle pulses based on current brightness
      final innerRadius = outerRadius * (0.3 + 0.5 * brightnessFraction);
      final innerPaint = Paint()
        ..color = varColor.withValues(alpha: 0.3 + 0.5 * brightnessFraction)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, innerRadius, innerPaint);

      // Second outer ring
      final outerRing2Paint = Paint()
        ..color = varColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(offset, outerRadius + 2.5, outerRing2Paint);

      // Label for bright variables (magMax < 5)
      if (vs.magMax < 5.0) {
        final labelText = vs.name.length > 14
            ? '${vs.name.substring(0, 12)}..'
            : vs.name;
        final textStyle = TextStyle(
          color: varColor.withValues(alpha: 0.85),
          fontSize: 9.0,
          fontWeight: FontWeight.w400,
        );
        final tp = TextPainter(
          text: TextSpan(text: labelText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final preferredPos = offset + Offset(-tp.width / 2, outerRadius + 5);
        final labelPos = _labelManager.findPlacement(
          preferredPos,
          Size(tp.width, tp.height),
          size,
        );
        if (labelPos != null) {
          tp.paint(canvas, labelPos);
        }
      }
    }
  }

  /// Draw minor planets (asteroids as diamonds, comets with fuzzy tail).
  void _drawMinorPlanets(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    const asteroidColor = Color(0xFFBCAAA4);
    const cometColor = Color(0xFF81D4FA);

    for (final body in minorPlanets) {
      if (body.visualMag > 14.0) continue;

      final coord = body.coordinates;
      final offset = _celestialToScreen(coord, center, scale);
      if (offset == null) continue;
      if (!_isInView(offset, size)) continue;

      final isBright = body.visualMag < 10.0;

      if (body.isComet) {
        // --- Comet: fuzzy coma + tail ---
        final comaRadius = isBright ? 5.0 : 3.0;
        if (qualityConfig.useBlurEffects) {
          final comaPaint = _PaintCache.getBlurPaint(3, cometColor, alpha: 0.3);
          canvas.drawCircle(offset, comaRadius + 2, comaPaint);
        } else {
          canvas.drawCircle(
            offset,
            comaRadius + 2,
            Paint()..color = cometColor.withValues(alpha: 0.2),
          );
        }
        canvas.drawCircle(
          offset,
          comaRadius * 0.6,
          Paint()..color = cometColor.withValues(alpha: isBright ? 0.8 : 0.5),
        );

        // Tail (anti-sunward, simplified as upper-right)
        final tailLen = isBright ? 18.0 : 10.0;
        final tailEnd = Offset(
          offset.dx + tailLen * 0.7,
          offset.dy - tailLen * 0.7,
        );
        canvas.drawLine(
          offset,
          tailEnd,
          Paint()
            ..shader = ui.Gradient.linear(offset, tailEnd, [
              cometColor.withValues(alpha: 0.4),
              cometColor.withValues(alpha: 0.0),
            ])
            ..strokeWidth = isBright ? 3.0 : 2.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
        // Dust tail
        final dustEnd = Offset(
          offset.dx + tailLen * 0.5,
          offset.dy - tailLen * 0.9,
        );
        canvas.drawLine(
          offset,
          dustEnd,
          Paint()
            ..shader = ui.Gradient.linear(offset, dustEnd, [
              cometColor.withValues(alpha: 0.2),
              cometColor.withValues(alpha: 0.0),
            ])
            ..strokeWidth = isBright ? 5.0 : 3.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );

        if (body.visualMag < 10.0) {
          _drawMinorPlanetLabel(
            canvas,
            offset,
            body.name,
            comaRadius + 5,
            size,
            cometColor,
          );
        }
      } else {
        // --- Asteroid: diamond shape ---
        final ds = isBright ? 4.0 : 2.5;
        final path = Path()
          ..moveTo(offset.dx, offset.dy - ds)
          ..lineTo(offset.dx + ds, offset.dy)
          ..lineTo(offset.dx, offset.dy + ds)
          ..lineTo(offset.dx - ds, offset.dy)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = asteroidColor.withValues(alpha: isBright ? 0.9 : 0.6),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = asteroidColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );

        if (body.visualMag < 9.0) {
          _drawMinorPlanetLabel(
            canvas,
            offset,
            body.name,
            ds + 4,
            size,
            asteroidColor,
          );
        }
      }
    }
  }

  void _drawMinorPlanetLabel(
    Canvas canvas,
    Offset offset,
    String name,
    double yOffset,
    Size size,
    Color color,
  ) {
    final labelText = name.length > 14 ? '${name.substring(0, 12)}..' : name;
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 9.0),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final preferredPos = offset + Offset(-tp.width / 2, yOffset);
    final labelPos = _labelManager.findPlacement(
      preferredPos,
      Size(tp.width, tp.height),
      size,
    );
    if (labelPos != null) {
      tp.paint(canvas, labelPos);
    }
  }
}
