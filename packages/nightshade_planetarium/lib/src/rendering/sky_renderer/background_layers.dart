// ignore_for_file: unused_element, unused_field

part of '../sky_renderer.dart';

extension _SkyCanvasPainterBackgroundLayers on SkyCanvasPainter {
  void _drawBackground(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Check if twilight gradient is enabled
    if (!qualityConfig.enableTwilightGradient) {
      // Simple dark gradient for performance mode - use cached shader
      final shader = _PaintCache.getDarkBackgroundShader(size);
      final paint = _PaintCache.getBackgroundPaint(shader);
      canvas.drawRect(rect, paint);
      return;
    }

    // Calculate sun altitude for twilight determination
    final sunAlt = AstronomyCalculations.sunAltitude(
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Use cached gradient if sun altitude hasn't changed significantly (2-degree bucket)
    if (_backgroundGradientCache.isValid(sunAlt, size)) {
      final paint = _PaintCache.getBackgroundPaint(
          _backgroundGradientCache.verticalShader!);
      canvas.drawRect(rect, paint);
      final radialPaint = _PaintCache.getBackgroundPaint(
          _backgroundGradientCache.radialShader!);
      canvas.drawRect(rect, radialPaint);
      return;
    }

    // Get twilight colors based on sun altitude
    final (zenithColor, horizonColor) = _getTwilightColors(sunAlt);

    // Create vertical gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [zenithColor, horizonColor],
      stops: const [0.0, 1.0],
    );
    final verticalShader = gradient.createShader(rect);

    // Add a subtle radial darkening toward center for depth
    final radialGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.5,
      colors: [
        Colors.transparent,
        zenithColor.withValues(alpha: 0.3),
      ],
    );
    final radialShader = radialGradient.createShader(rect);

    // Cache both shaders
    _backgroundGradientCache.store(verticalShader, radialShader, sunAlt, size);

    final paint = _PaintCache.getBackgroundPaint(verticalShader);
    canvas.drawRect(rect, paint);
    final radialPaint = _PaintCache.getBackgroundPaint(radialShader);
    canvas.drawRect(rect, radialPaint);
  }

  /// Get twilight colors based on sun altitude
  /// Returns (zenithColor, horizonColor) for gradient
  (Color, Color) _getTwilightColors(double sunAltitude) {
    // Astronomical twilight: sun below -18°
    // Nautical twilight: sun between -18° and -12°
    // Civil twilight: sun between -12° and -6°
    // Golden hour: sun between -6° and 0°
    // Day: sun above 0°

    if (sunAltitude <= -18) {
      // Full night - dark blue-black gradient
      return (
        const Color(0xFF0A0A1A), // Zenith: very dark blue
        const Color(0xFF0D0D20), // Horizon: slightly lighter dark blue
      );
    } else if (sunAltitude <= -12) {
      // Nautical twilight - deep blues
      final t = (sunAltitude + 18) / 6; // 0 at -18, 1 at -12
      return (
        Color.lerp(const Color(0xFF0A0A1A), const Color(0xFF0F1028), t)!,
        Color.lerp(const Color(0xFF0D0D20), const Color(0xFF1A1A38), t)!,
      );
    } else if (sunAltitude <= -6) {
      // Civil twilight - navy to deep purple/blue
      final t = (sunAltitude + 12) / 6; // 0 at -12, 1 at -6
      return (
        Color.lerp(const Color(0xFF0F1028), const Color(0xFF1A1A40), t)!,
        Color.lerp(const Color(0xFF1A1A38), const Color(0xFF2D2040), t)!,
      );
    } else if (sunAltitude <= 0) {
      // Golden hour - purple/blue to orange/pink at horizon
      final t = (sunAltitude + 6) / 6; // 0 at -6, 1 at 0
      return (
        Color.lerp(const Color(0xFF1A1A40), const Color(0xFF252050), t)!,
        Color.lerp(const Color(0xFF2D2040), const Color(0xFF4A3048), t)!,
      );
    } else if (sunAltitude <= 6) {
      // Just after sunrise/before sunset - warm colors
      final t = (sunAltitude / 6).clamp(0.0, 1.0); // 0 at 0, 1 at 6
      return (
        Color.lerp(const Color(0xFF252050), const Color(0xFF354080), t)!,
        Color.lerp(const Color(0xFF4A3048), const Color(0xFF705040), t)!,
      );
    } else {
      // Full day - light blue sky (though planetarium usually used at night)
      return (
        const Color(0xFF4060A0), // Zenith: medium blue
        const Color(0xFF8090B0), // Horizon: lighter blue
      );
    }
  }

  // Logical→texel downscale factor for the Milky Way offscreen. The band is a
  // soft diffuse glow, so rasterizing its costly Gaussian blur at half linear
  // resolution (quarter the pixels, half the sigma) and bilinear-upscaling on
  // draw is perceptually indistinguishable from a full-resolution blur at a
  // fraction of the fill-rate cost. This is the dominant per-frame render cost
  // during pan/zoom, where the pose cache misses every frame.
  static const double _milkyWayDownscale = 0.5;

  void _drawMilkyWay(Canvas canvas, Size size, Offset center, double scale) {
    if (milkyWayPoints == null) return;

    final dst = Rect.fromLTWH(0, 0, size.width, size.height);

    // Reuse the cached half-res band image while the view is effectively still.
    if (_milkyWayCache.isValid(
        viewState.centerRA, viewState.centerDec, viewState.fieldOfView, size)) {
      _blitMilkyWay(canvas, _milkyWayCache.image!, dst);
      return;
    }

    // Cache miss: rasterize the band into a half-resolution offscreen image.
    // Half-resolution means every geometric quantity (projected position, point
    // radius, blur sigma) is scaled by [_milkyWayDownscale] so that, once the
    // image is upscaled 1/_milkyWayDownscale on draw, the on-screen size, blur
    // extent and coverage match the original full-resolution band.
    const ds = _milkyWayDownscale;
    final texW = (size.width * ds).ceil();
    final texH = (size.height * ds).ceil();
    if (texW <= 0 || texH <= 0) return;

    final fovFactor = viewState.fieldOfView / 60;
    final blurRadius = (8 * fovFactor).clamp(4.0, 20.0);
    final pointRadius = (3 * fovFactor).clamp(2.0, 8.0);

    // Milky Way color - subtle blue-white glow
    const baseColor = Color(0xFF8090A8);

    // Batch Milky Way points into Float32List groups by intensity bucket to
    // minimize draw calls. Positions are projected at full screen scale (so the
    // in-view test matches the visible canvas) then scaled into texel space.
    final glowPoints = <double>[];
    final corePoints = <double>[];

    for (final point in milkyWayPoints!) {
      final offset = _celestialToScreen(point.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      glowPoints.add(offset.dx * ds);
      glowPoints.add(offset.dy * ds);

      if (point.intensity > 0.5) {
        corePoints.add(offset.dx * ds);
        corePoints.add(offset.dy * ds);
      }
    }

    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    // Draw all glow points as a single batch (sigma + size scaled to texel space)
    if (glowPoints.isNotEmpty) {
      final glowPaint =
          _PaintCache.getBlurPaint(blurRadius * ds, baseColor, alpha: 0.12);
      glowPaint.strokeWidth = pointRadius * 4 * ds;
      glowPaint.strokeCap = StrokeCap.round;
      recordCanvas.drawRawPoints(
          ui.PointMode.points, Float32List.fromList(glowPoints), glowPaint);
    }

    // Draw brighter core points as a second batch
    if (corePoints.isNotEmpty) {
      final corePaint =
          _PaintCache.getBlurPaint(blurRadius * 0.5 * ds, baseColor, alpha: 0.18);
      corePaint.strokeWidth = pointRadius * 2 * ds;
      corePaint.strokeCap = StrokeCap.round;
      recordCanvas.drawRawPoints(
          ui.PointMode.points, Float32List.fromList(corePoints), corePaint);
    }

    // Rasterize synchronously so the image is usable this frame (matches the
    // sprite-atlas bake strategy), cache it, and blit upscaled.
    final image = recorder.endRecording().toImageSync(texW, texH);
    _milkyWayCache.store(image, viewState.centerRA, viewState.centerDec,
        viewState.fieldOfView, size);

    _blitMilkyWay(canvas, image, dst);
  }

  /// Bilinear-upscale the half-res Milky Way [image] to fill [dst].
  void _blitMilkyWay(Canvas canvas, ui.Image image, Rect dst) {
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}
