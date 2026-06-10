// ignore_for_file: unused_element, unused_field

part of '../sky_renderer.dart';

extension _SkyCanvasPainterConstellationLayers on SkyCanvasPainter {
  void _drawConstellationBoundaries(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    final boundaryPaint = Paint()
      ..color = config.constellationBoundaryColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final boundaries = ConstellationBoundaries.all;
    final path = Path();

    for (final entry in boundaries.entries) {
      final vertices = entry.value;
      if (vertices.length < 3) continue;

      for (var i = 0; i < vertices.length; i++) {
        final v0 = vertices[i];
        final v1 = vertices[(i + 1) % vertices.length];

        final start = _celestialToScreen(
          CelestialCoordinate(ra: v0.ra, dec: v0.dec),
          center,
          scale,
        );
        final end = _celestialToScreen(
          CelestialCoordinate(ra: v1.ra, dec: v1.dec),
          center,
          scale,
        );

        if (start == null || end == null) continue;
        if (!_isInView(start, size) && !_isInView(end, size)) continue;

        // Draw dashed line segments
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = math.sqrt(dx * dx + dy * dy);
        if (length < 1) continue;

        const dashLength = 4.0;
        const gapLength = 4.0;
        final unitDx = dx / length;
        final unitDy = dy / length;

        var dist = 0.0;
        while (dist < length) {
          final segEnd = math.min(dist + dashLength, length);
          path.moveTo(start.dx + unitDx * dist, start.dy + unitDy * dist);
          path.lineTo(start.dx + unitDx * segEnd, start.dy + unitDy * segEnd);
          dist += dashLength + gapLength;
        }
      }
    }

    canvas.drawPath(path, boundaryPaint);
  }

  void _drawConstellationLines(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    // Check if we can reuse a cached Picture of constellation lines.
    // Constellation lines are static relative to the sky — they only change
    // when the view moves, so caching saves redrawing hundreds of line segments.
    if (_constellationLineCache.isValid(
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      size,
      constellations.length,
    )) {
      canvas.drawPicture(_constellationLineCache.picture!);
      return;
    }

    // Cache miss: record constellation lines into a Picture
    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final paint = _PaintCache.getConstellationPaint(
      config.constellationLineColor,
    );

    // Batch all lines into a single Path for better performance
    final path = Path();

    for (final constellation in constellations) {
      for (final line in constellation.lines) {
        // Cull a segment only when BOTH endpoints are outside the cull cone;
        // a segment with one endpoint inside can still cross the viewport.
        if (_cull!.isCulled(line.start.raDegrees, line.start.dec) &&
            _cull!.isCulled(line.end.raDegrees, line.end.dec)) {
          continue;
        }
        final start = _celestialToScreen(line.start, center, scale);
        final end = _celestialToScreen(line.end, center, scale);

        if (start != null && end != null) {
          if (_isInView(start, size) || _isInView(end, size)) {
            path.moveTo(start.dx, start.dy);
            path.lineTo(end.dx, end.dy);
          }
        }
      }
    }

    // Single draw call for all constellation lines
    recordCanvas.drawPath(path, paint);

    final picture = recorder.endRecording();
    _constellationLineCache.store(
      picture,
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      size,
      constellations.length,
    );

    // Draw the picture to the real canvas
    canvas.drawPicture(picture);
  }

  void _drawConstellationLabels(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    for (final constellation in constellations) {
      final offset = _celestialToScreen(constellation.center, center, scale);

      if (offset != null && _isInView(offset, size)) {
        // Use cached TextPainter for constellation labels
        final textPainter = _TextCache.get(
          constellation.name.toUpperCase(),
          textStyle,
        );
        textPainter.paint(
          canvas,
          offset - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  void _drawConstellationArt(
    Canvas canvas,
    Size size,
    Offset center,
    double scale,
  ) {
    // Gold/amber fill with 20% opacity
    final fillPaint = Paint()
      ..color =
          const Color(0x33DAA520) // goldenrod at ~20% opacity
      ..style = PaintingStyle.fill;

    // Slightly brighter stroke for figure outlines
    final strokePaint = Paint()
      ..color =
          const Color(0x28DAA520) // goldenrod at ~16% opacity
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final figure in SkyCanvasPainter._constellationArtFigures) {
      // Quick visibility check: find the constellation data to get its center
      final constellationData = constellations
          .where((c) => c.abbreviation == figure.abbreviation)
          .firstOrNull;
      if (constellationData == null) continue;

      final centerOffset = _celestialToScreen(
        constellationData.center,
        center,
        scale,
      );
      if (centerOffset == null) continue;

      // Skip if constellation center is far off-screen (generous margin for large figures)
      if (centerOffset.dx < -size.width ||
          centerOffset.dx > size.width * 2 ||
          centerOffset.dy < -size.height ||
          centerOffset.dy > size.height * 2) {
        continue;
      }

      // Build the Canvas path from the art segments
      final path = Path();
      bool hasVisiblePoint = false;

      for (final segment in figure.segments) {
        switch (segment) {
          case ArtMoveTo(:final point):
            final screenPt = _celestialToScreen(point, center, scale);
            if (screenPt != null) {
              path.moveTo(screenPt.dx, screenPt.dy);
              if (_isInView(screenPt, size)) hasVisiblePoint = true;
            }
          case ArtLineTo(:final point):
            final screenPt = _celestialToScreen(point, center, scale);
            if (screenPt != null) {
              path.lineTo(screenPt.dx, screenPt.dy);
              if (_isInView(screenPt, size)) hasVisiblePoint = true;
            }
          case ArtQuadTo(:final control, :final point):
            final ctrlPt = _celestialToScreen(control, center, scale);
            final endPt = _celestialToScreen(point, center, scale);
            if (ctrlPt != null && endPt != null) {
              path.quadraticBezierTo(ctrlPt.dx, ctrlPt.dy, endPt.dx, endPt.dy);
              if (_isInView(endPt, size)) hasVisiblePoint = true;
            } else if (endPt != null) {
              // Fallback to lineTo if control point is behind projection
              path.lineTo(endPt.dx, endPt.dy);
              if (_isInView(endPt, size)) hasVisiblePoint = true;
            }
          case ArtClose():
            path.close();
        }
      }

      // Only draw if at least one point is visible on screen
      if (hasVisiblePoint) {
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }
    }
  }
}
