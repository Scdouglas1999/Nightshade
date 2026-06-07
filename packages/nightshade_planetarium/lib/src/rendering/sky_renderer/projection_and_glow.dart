// ignore_for_file: unused_element, unused_field

part of '../sky_renderer.dart';

extension _SkyCanvasPainterProjectionAndGlow on SkyCanvasPainter {
  /// Local sidereal time (hours) for this paint, computed once and memoized.
  ///
  /// Only used by the [SkyViewMode.horizontal] projection path, where every
  /// object's RA/Dec must be rotated into the local horizontal frame. Cached so
  /// the per-object alt/az conversion in a wide-field paint doesn't recompute
  /// sidereal time thousands of times.
  double get _lstHours {
    final cached = SkyCanvasPainter._lstCacheValue;
    if (cached != null &&
        SkyCanvasPainter._lstCacheTime == observationTime &&
        SkyCanvasPainter._lstCacheLon == longitude) {
      return cached;
    }
    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);
    SkyCanvasPainter._lstCacheValue = lst;
    SkyCanvasPainter._lstCacheTime = observationTime;
    SkyCanvasPainter._lstCacheLon = longitude;
    return lst;
  }

  Offset? _celestialToScreen(
      CelestialCoordinate coord, Offset center, double scale) {
    if (viewState.viewMode == SkyViewMode.horizontal) {
      final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
        raDeg: coord.ra * 15,
        decDeg: coord.dec,
        latitudeDeg: latitude,
        lstHours: _lstHours,
      );
      return _horizontalToScreen(alt, az, center, scale);
    }

    // Convert RA from hours to degrees
    final raDeg = coord.ra * 15;
    final decDeg = coord.dec;

    // Calculate angular distance from view center
    final centerRaDeg = viewState.centerRA * 15;
    final centerDecDeg = viewState.centerDec;

    return _projectAroundCenter(
      lonDeg: raDeg,
      latDeg: decDeg,
      centerLonDeg: centerRaDeg,
      centerLatDeg: centerDecDeg,
      center: center,
      scale: scale,
    );
  }

  /// Project a horizontal coordinate (alt/az, degrees) to the screen in the
  /// [SkyViewMode.horizontal] frame.
  ///
  /// Azimuth plays the role of longitude and altitude the role of latitude in
  /// the shared spherical projector, so the same stereographic / orthographic /
  /// equidistant maths is reused. Azimuth is negated so that East (increasing
  /// azimuth) maps to the right of the screen — the natural "looking outward"
  /// orientation an observer expects — while altitude increases upward.
  Offset? _horizontalToScreen(
      double altDeg, double azDeg, Offset center, double scale) {
    return _projectAroundCenter(
      lonDeg: -azDeg,
      latDeg: altDeg,
      centerLonDeg: -viewState.centerAz,
      centerLatDeg: viewState.centerAltitude,
      center: center,
      scale: scale,
    );
  }

  /// Shared spherical-to-screen projector used by both view modes.
  ///
  /// Maps a sphere point ([lonDeg], [latDeg]) relative to the projection center
  /// ([centerLonDeg], [centerLatDeg]) through the configured [SkyProjection],
  /// then applies the view rotation, scale and screen centering. Both the
  /// equatorial (RA/Dec) and horizontal (Az/Alt) paths feed this with their own
  /// longitude/latitude pair so the projection geometry lives in exactly one
  /// place.
  Offset? _projectAroundCenter({
    required double lonDeg,
    required double latDeg,
    required double centerLonDeg,
    required double centerLatDeg,
    required Offset center,
    required double scale,
  }) {
    final ra1 = centerLonDeg * SkyCanvasPainter._deg2rad;
    final dec1 = centerLatDeg * SkyCanvasPainter._deg2rad;
    final ra2 = lonDeg * SkyCanvasPainter._deg2rad;
    final dec2 = latDeg * SkyCanvasPainter._deg2rad;

    final cosc = math.sin(dec1) * math.sin(dec2) +
        math.cos(dec1) * math.cos(dec2) * math.cos(ra2 - ra1);

    // Object is behind the projection plane
    if (cosc < 0.01) return null;

    double x, y;

    switch (viewState.projection) {
      case SkyProjection.stereographic:
        final k = 2 / (1 + cosc);
        x = k * math.cos(dec2) * math.sin(ra2 - ra1);
        y = k *
            (math.cos(dec1) * math.sin(dec2) -
                math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1));
        break;

      case SkyProjection.orthographic:
        x = math.cos(dec2) * math.sin(ra2 - ra1);
        y = math.cos(dec1) * math.sin(dec2) -
            math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1);
        break;

      case SkyProjection.azimuthalEquidistant:
        final c = math.acos(cosc);
        if (c < 0.0001) {
          x = 0;
          y = 0;
        } else {
          final k = c / math.sin(c);
          x = k * math.cos(dec2) * math.sin(ra2 - ra1);
          y = k *
              (math.cos(dec1) * math.sin(dec2) -
                  math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1));
        }
        break;
    }

    // Apply rotation
    final rotRad = viewState.rotation * SkyCanvasPainter._deg2rad;
    final xRot = x * math.cos(rotRad) - y * math.sin(rotRad);
    final yRot = x * math.sin(rotRad) + y * math.cos(rotRad);

    // Scale and center
    return Offset(
      center.dx - xRot * scale * SkyCanvasPainter._rad2deg,
      center.dy - yRot * scale * SkyCanvasPainter._rad2deg,
    );
  }

  bool _isInView(Offset offset, Size size) {
    return offset.dx >= -50 &&
        offset.dx <= size.width + 50 &&
        offset.dy >= -50 &&
        offset.dy <= size.height + 50;
  }

  /// Project a catalog object (Star/DSO/etc.) to screen, culling BEFORE the
  /// projection trig and memoizing the result for the current pose.
  ///
  /// [key] is the object itself; the catalog instances are stable across frames
  /// so the cached offset can be reused at the same pose. Returns null when the
  /// object is culled or projects behind the plane.
  ///
  /// The cull test uses the per-paint [_CullContext] dot product, which is far
  /// cheaper than a full projection followed by an `_isInView` rejection.
  Offset? _projectObjectCulled(
      Object key, double raDeg, double decDeg, Offset center, double scale) {
    final cache = SkyCanvasPainter._projectionCache;
    if (cache.contains(key)) {
      return cache.get(key);
    }
    // Cheap cull before the expensive projection.
    if (_cull!.isCulled(raDeg, decDeg)) {
      cache.put(key, null);
      return null;
    }
    final offset = _celestialToScreen(
      CelestialCoordinate(ra: raDeg / 15, dec: decDeg),
      center,
      scale,
    );
    cache.put(key, offset);
    return offset;
  }

  /// Enhanced magnitude-to-size scaling - brighter stars "pop" more
  /// Uses tiered scaling with FOV consideration for realistic star appearance
  double _magnitudeToRadius(double magnitude, {double? fov}) {
    final effectiveFov = fov ?? viewState.fieldOfView;

    double baseRadius;
    if (magnitude < 0) {
      // Very bright stars (Sirius, Canopus) - exponential boost
      baseRadius = 6.0 + (0 - magnitude) * 2.5;
    } else if (magnitude < 2) {
      // Bright stars - significant boost
      baseRadius = 3.0 + (2 - magnitude) * 1.5;
    } else if (magnitude < 4) {
      // Medium stars - moderate scaling
      baseRadius = 1.5 + (4 - magnitude) * 0.75;
    } else {
      // Faint stars - small but visible
      baseRadius = math.max(0.5, (6.5 - magnitude) * 0.3);
    }

    // Scale with zoom (stars appear larger when zoomed in)
    final zoomFactor = (90 / effectiveFov).clamp(0.8, 2.0);
    return (baseRadius * zoomFactor).clamp(0.5, 25.0);
  }

  double _magnitudeToBrightness(double mag) {
    // Brighter stars are more opaque
    return math.min(1.0, math.max(0.3, (7 - mag) / 6));
  }

  /// Get font size based on magnitude and object type for label hierarchy
  double _getLabelFontSize(double magnitude, String objectType) {
    if (objectType == 'planet') return 12.0;

    if (magnitude < 0) return 12.0; // Very bright
    if (magnitude < 2) return 11.0; // Bright
    if (magnitude < 4) return 10.0; // Medium
    return 9.0; // Faint
  }

  /// Get font weight based on magnitude for label hierarchy
  FontWeight _getLabelFontWeight(double magnitude) {
    if (magnitude < 1) return FontWeight.w600;
    if (magnitude < 3) return FontWeight.w500;
    return FontWeight.w400;
  }

  Color _spectralTypeToColor(String spectralType) {
    if (spectralType.isEmpty) return Colors.white;

    switch (spectralType[0].toUpperCase()) {
      case 'O':
        return const Color(0xFF9BB0FF); // Blue
      case 'B':
        return const Color(0xFFAABFFF); // Blue-white
      case 'A':
        return const Color(0xFFCAD7FF); // White
      case 'F':
        return const Color(0xFFF8F7FF); // Yellow-white
      case 'G':
        return const Color(0xFFFFF4E8); // Yellow
      case 'K':
        return const Color(0xFFFFD2A1); // Orange
      case 'M':
        return const Color(0xFFFFCC6F); // Red-orange
      default:
        return Colors.white;
    }
  }

  /// Boost color saturation for bright stars (mag < 2)
  /// Makes prominent stars more visually distinctive with richer colors
  Color _getEnhancedStarColor(Color baseColor, double magnitude) {
    if (magnitude < 2) {
      final hsl = HSLColor.fromColor(baseColor);
      // Boost saturation more for brighter stars
      final boostFactor = ((2 - magnitude) / 4).clamp(0.0, 0.5);
      final boostedSaturation = (hsl.saturation + boostFactor).clamp(0.0, 1.0);

      return hsl
          .withSaturation(boostedSaturation)
          .withLightness((hsl.lightness * 1.1).clamp(0.0, 1.0))
          .toColor();
    }
    return baseColor;
  }

  // ============ Gradient-based glow helpers ============
  // These replace expensive MaskFilter.blur with radial gradients
  // for better performance on low-powered devices.

  /// Draw a circular glow using radial gradient (faster than blur)
  void _drawGlowCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    double innerOpacity = 0.6,
    double midOpacity = 0.2,
  }) {
    if (!qualityConfig.useGlowEffects) return;

    // Use _ShaderCache to avoid creating a new RadialGradient.createShader()
    // every call. Previously this created ~600+ uncached shaders per frame
    // for galaxy rendering alone.
    final shader = _ShaderCache.getRadialShader(
      center,
      radius,
      [
        color.withValues(alpha: innerOpacity),
        color.withValues(alpha: midOpacity),
        color.withValues(alpha: 0.0),
      ],
      const [0.0, 0.5, 1.0],
    );

    SkyCanvasPainter._glowShaderPaint.shader = shader;
    canvas.drawCircle(center, radius, SkyCanvasPainter._glowShaderPaint);
  }

  /// Draw an oval glow using radial gradient.
  /// Uses cached shaders via _ShaderCache to avoid per-frame GPU allocation.
  void _drawGlowOval(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    Color color, {
    double innerOpacity = 0.6,
    double midOpacity = 0.2,
  }) {
    if (!qualityConfig.useGlowEffects) return;

    // Use _ShaderCache to avoid creating a new RadialGradient.createShader()
    // every call. The cache rounds center/radius for higher hit rate.
    final effectiveRadius = math.max(width, height) / 2;
    final shader = _ShaderCache.getRadialShader(
      center,
      effectiveRadius,
      [
        color.withValues(alpha: innerOpacity),
        color.withValues(alpha: midOpacity),
        color.withValues(alpha: 0.0),
      ],
      const [0.0, 0.5, 1.0],
    );

    final rect = Rect.fromCenter(center: center, width: width, height: height);
    SkyCanvasPainter._glowShaderPaint.shader = shader;
    canvas.drawOval(rect, SkyCanvasPainter._glowShaderPaint);
  }

  /// Draw a glow effect - uses blur if available, gradient otherwise
  /// PERFORMANCE: Uses cached blur paint to avoid per-frame MaskFilter allocation
  void _drawGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double blurSigma, {
    double opacity = 0.3,
  }) {
    if (qualityConfig.useBlurEffects) {
      // High quality: use cached blur paint
      final glowPaint =
          _PaintCache.getBlurPaint(blurSigma, color, alpha: opacity);
      canvas.drawCircle(center, radius, glowPaint);
    } else if (qualityConfig.useGlowEffects) {
      // Balanced: use gradient
      _drawGlowCircle(
        canvas,
        center,
        radius + blurSigma * 2,
        color,
        innerOpacity: opacity * 1.5,
        midOpacity: opacity * 0.5,
      );
    }
    // Performance mode: skip glow entirely
  }

  /// Draw an oval glow effect - uses blur if available, gradient otherwise
  /// PERFORMANCE: Uses cached blur paint to avoid per-frame MaskFilter allocation
  void _drawOvalGlow(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    Color color,
    double blurSigma, {
    double opacity = 0.3,
  }) {
    if (qualityConfig.useBlurEffects) {
      // Use cached blur paint
      final glowPaint =
          _PaintCache.getBlurPaint(blurSigma, color, alpha: opacity);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: width, height: height),
        glowPaint,
      );
    } else if (qualityConfig.useGlowEffects) {
      _drawGlowOval(
        canvas,
        center,
        width + blurSigma * 2,
        height + blurSigma * 2,
        color,
        innerOpacity: opacity * 1.5,
        midOpacity: opacity * 0.5,
      );
    }
  }
}
