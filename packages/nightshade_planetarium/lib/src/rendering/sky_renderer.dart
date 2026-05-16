// ignore_for_file: unused_element, unused_field

import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../celestial_object.dart';
import '../coordinate_system.dart';
import '../catalogs/constellation_data.dart';
import '../catalogs/constellation_art.dart';
import '../catalogs/satellite_catalog.dart';
import '../catalogs/variable_star_catalog.dart';
import '../catalogs/minor_planet_catalog.dart';
import '../astronomy/astronomy_calculations.dart';
import '../astronomy/planetary_positions.dart';
import '../astronomy/milky_way_data.dart';
import 'render_quality.dart';
import 'star_psf_cache.dart';

/// Mount tracking status for rendering
enum MountRenderStatus {
  disconnected,
  parked,
  slewing,
  tracking,
  stopped,
}

/// Configuration for sky rendering
class SkyRenderConfig {
  final bool showStars;
  final bool showConstellationLines;
  final bool showConstellationLabels;
  final bool showConstellationBoundaries;
  final bool showDSOs;
  final bool showDSOLabels;
  final bool showCoordinateGrid;
  final bool showAltAzGrid;
  final bool showEquatorialGrid;
  final bool showEcliptic;
  final bool showGalacticPlane;
  final bool showHorizon;
  final bool showCardinalDirections;
  final bool showMilkyWay;
  final bool showMountPosition;
  final bool showSun;
  final bool showMoon;
  final bool showPlanets;
  final bool showGroundPlane;
  final bool showMeridian;
  final bool showSatellites;
  final bool showVariableStars;
  final bool showMinorPlanets;
  final bool showConstellationArt;
  final Color groundColorDark;
  final Color groundColorLight;
  final Color horizonGlowColor;
  final double starMagnitudeLimit;
  final double dsoMagnitudeLimit;
  final Color gridColor;
  final Color constellationLineColor;
  final Color constellationBoundaryColor;
  final Color eclipticColor;
  final Color galacticPlaneColor;
  final Color horizonColor;
  final Color mountPositionColor;

  const SkyRenderConfig({
    this.showStars = true,
    this.showConstellationLines = true,
    this.showConstellationLabels = true,
    this.showConstellationBoundaries = false,
    this.showDSOs = true,
    this.showDSOLabels = true,
    this.showCoordinateGrid = false,
    this.showAltAzGrid = false,
    this.showEquatorialGrid = false,
    this.showEcliptic = false,
    this.showGalacticPlane = false,
    this.showHorizon = true,
    this.showCardinalDirections = true,
    this.showMilkyWay = false,
    this.showMountPosition = true,
    this.showSun = true,
    this.showMoon = true,
    this.showPlanets = true,
    this.showGroundPlane = true,
    this.showMeridian = false,
    this.showSatellites = false,
    this.showVariableStars = false,
    this.showMinorPlanets = false,
    this.showConstellationArt = false,
    this.groundColorDark = const Color(0xFF0A0805),
    this.groundColorLight = const Color(0xFF1A1510),
    this.horizonGlowColor = const Color(0xFF2A2015),
    this.starMagnitudeLimit = 6.0,
    this.dsoMagnitudeLimit = 12.0,
    this.gridColor = const Color(0x33FFFFFF),
    this.constellationLineColor = const Color(0x40FFFFFF),
    this.constellationBoundaryColor = const Color(0x20FFFFFF),
    this.eclipticColor = const Color(0x40FFEB3B),
    this.galacticPlaneColor = const Color(0x4000BCD4),
    this.horizonColor = const Color(0x30FF8A65),
    this.mountPositionColor = const Color(0xFFE53935),
  });

  SkyRenderConfig copyWith({
    bool? showStars,
    bool? showConstellationLines,
    bool? showConstellationLabels,
    bool? showConstellationBoundaries,
    bool? showDSOs,
    bool? showDSOLabels,
    bool? showCoordinateGrid,
    bool? showAltAzGrid,
    bool? showEquatorialGrid,
    bool? showEcliptic,
    bool? showGalacticPlane,
    bool? showHorizon,
    bool? showCardinalDirections,
    bool? showMilkyWay,
    bool? showMountPosition,
    bool? showSun,
    bool? showMoon,
    bool? showPlanets,
    bool? showGroundPlane,
    bool? showMeridian,
    bool? showSatellites,
    bool? showVariableStars,
    bool? showMinorPlanets,
    bool? showConstellationArt,
    Color? groundColorDark,
    Color? groundColorLight,
    Color? horizonGlowColor,
    double? starMagnitudeLimit,
    double? dsoMagnitudeLimit,
    Color? gridColor,
    Color? constellationLineColor,
    Color? constellationBoundaryColor,
    Color? eclipticColor,
    Color? galacticPlaneColor,
    Color? horizonColor,
    Color? mountPositionColor,
  }) {
    return SkyRenderConfig(
      showStars: showStars ?? this.showStars,
      showConstellationLines:
          showConstellationLines ?? this.showConstellationLines,
      showConstellationLabels:
          showConstellationLabels ?? this.showConstellationLabels,
      showConstellationBoundaries:
          showConstellationBoundaries ?? this.showConstellationBoundaries,
      showDSOs: showDSOs ?? this.showDSOs,
      showDSOLabels: showDSOLabels ?? this.showDSOLabels,
      showCoordinateGrid: showCoordinateGrid ?? this.showCoordinateGrid,
      showAltAzGrid: showAltAzGrid ?? this.showAltAzGrid,
      showEquatorialGrid: showEquatorialGrid ?? this.showEquatorialGrid,
      showEcliptic: showEcliptic ?? this.showEcliptic,
      showGalacticPlane: showGalacticPlane ?? this.showGalacticPlane,
      showHorizon: showHorizon ?? this.showHorizon,
      showCardinalDirections:
          showCardinalDirections ?? this.showCardinalDirections,
      showMilkyWay: showMilkyWay ?? this.showMilkyWay,
      showMountPosition: showMountPosition ?? this.showMountPosition,
      showSun: showSun ?? this.showSun,
      showMoon: showMoon ?? this.showMoon,
      showPlanets: showPlanets ?? this.showPlanets,
      showGroundPlane: showGroundPlane ?? this.showGroundPlane,
      showMeridian: showMeridian ?? this.showMeridian,
      showSatellites: showSatellites ?? this.showSatellites,
      showVariableStars: showVariableStars ?? this.showVariableStars,
      showMinorPlanets: showMinorPlanets ?? this.showMinorPlanets,
      showConstellationArt:
          showConstellationArt ?? this.showConstellationArt,
      groundColorDark: groundColorDark ?? this.groundColorDark,
      groundColorLight: groundColorLight ?? this.groundColorLight,
      horizonGlowColor: horizonGlowColor ?? this.horizonGlowColor,
      starMagnitudeLimit: starMagnitudeLimit ?? this.starMagnitudeLimit,
      dsoMagnitudeLimit: dsoMagnitudeLimit ?? this.dsoMagnitudeLimit,
      gridColor: gridColor ?? this.gridColor,
      constellationLineColor:
          constellationLineColor ?? this.constellationLineColor,
      constellationBoundaryColor:
          constellationBoundaryColor ?? this.constellationBoundaryColor,
      eclipticColor: eclipticColor ?? this.eclipticColor,
      galacticPlaneColor: galacticPlaneColor ?? this.galacticPlaneColor,
      horizonColor: horizonColor ?? this.horizonColor,
      mountPositionColor: mountPositionColor ?? this.mountPositionColor,
    );
  }
}

/// Sky view projection type
enum SkyProjection {
  stereographic,
  orthographic,
  azimuthalEquidistant,
}

/// View state for sky rendering
class SkyViewState {
  final double centerRA; // hours
  final double centerDec; // degrees
  final double fieldOfView; // degrees
  final double rotation; // degrees
  final SkyProjection projection;

  const SkyViewState({
    this.centerRA = 0,
    this.centerDec = 0,
    this.fieldOfView = 90,
    this.rotation = 0,
    this.projection = SkyProjection.stereographic,
  });

  SkyViewState copyWith({
    double? centerRA,
    double? centerDec,
    double? fieldOfView,
    double? rotation,
    SkyProjection? projection,
  }) {
    return SkyViewState(
      centerRA: centerRA ?? this.centerRA,
      centerDec: centerDec ?? this.centerDec,
      fieldOfView: fieldOfView ?? this.fieldOfView,
      rotation: rotation ?? this.rotation,
      projection: projection ?? this.projection,
    );
  }
}

/// Precomputed atmospheric extinction lookup table.
///
/// 91 entries for altitudes 0-90 degrees. The extinction factor combines
/// dimming and reddening from atmospheric scattering. Below 30 degrees the
/// effect is significant; above 30 degrees the factor is 1.0 (no extinction).
///
/// The table is static since extinction depends only on altitude (geometric
/// airmass), not observer location. Uses linear interpolation for fractional
/// altitudes.
class AtmosphericExtinctionLUT {
  /// 91-entry LUT: index = integer altitude in degrees (0..90).
  /// Each entry is (brightnessFactor, redShift) where:
  ///   brightnessFactor: multiplier for star brightness [0.5..1.0]
  ///   redShift: Color.lerp amount toward warm horizon color [0.0..0.4]
  static final List<(double, double)> _lut = _buildLUT();

  static List<(double, double)> _buildLUT() {
    final table = List<(double, double)>.filled(91, (1.0, 0.0));
    for (int alt = 0; alt <= 90; alt++) {
      if (alt >= 30) {
        table[alt] = (1.0, 0.0);
      } else {
        // extinctionFactor ramps from 0.5 at 0 deg to 1.0 at 30 deg
        final extinctionFactor = (alt / 30.0).clamp(0.0, 1.0) * 0.5 + 0.5;
        final redShift = (1.0 - extinctionFactor) * 0.4;
        table[alt] = (extinctionFactor, redShift);
      }
    }
    return table;
  }

  /// Look up extinction for a given altitude in degrees.
  /// Returns (brightnessFactor, redShift).
  /// Uses linear interpolation between integer entries.
  static (double, double) lookup(double altitudeDeg) {
    if (altitudeDeg >= 30.0) return (1.0, 0.0);
    if (altitudeDeg <= 0.0) return _lut[0];

    final lower = altitudeDeg.floor();
    final upper = lower + 1;
    if (upper > 90) return _lut[90];

    final t = altitudeDeg - lower;
    final (bLow, rLow) = _lut[lower];
    final (bHigh, rHigh) = _lut[upper];
    return (
      bLow + (bHigh - bLow) * t,
      rLow + (rHigh - rLow) * t,
    );
  }
}

/// Tracks rendered label bounding boxes to avoid overlap.
///
/// Caches its spatial grid across frames when the view hasn't moved
/// significantly. Only rebuilds when view center moves >0.5 degrees
/// or zoom changes >5%.
class LabelLayoutManager {
  final List<Rect> _renderedLabels = [];
  final Map<int, List<Rect>> _grid = <int, List<Rect>>{};
  static const double _cellSize = 96.0;

  // Cache invalidation state
  double _cachedCenterRA = double.nan;
  double _cachedCenterDec = double.nan;
  double _cachedFOV = double.nan;
  bool _cacheValid = false;

  /// Clear the layout grid unconditionally.
  void clear() {
    _renderedLabels.clear();
    _grid.clear();
    _cacheValid = false;
  }

  /// Conditionally clear the layout grid based on view movement.
  /// Returns true if the cache was valid and reused, false if it was cleared.
  ///
  /// Only rebuilds when:
  /// - View center moves more than 0.5 degrees in RA or Dec
  /// - Zoom (FOV) changes more than 5%
  bool clearIfViewChanged(double centerRA, double centerDec, double fov) {
    if (_cacheValid) {
      final raDelta = (centerRA - _cachedCenterRA).abs();
      final decDelta = (centerDec - _cachedCenterDec).abs();
      final fovRatio = _cachedFOV > 0 ? (fov / _cachedFOV) : 0.0;

      // RA wraps at 24h, so check the shorter arc
      final raWrapped = raDelta > 12 ? 24 - raDelta : raDelta;
      // Convert RA hours to degrees for threshold comparison
      final raDeg = raWrapped * 15.0;

      if (raDeg < 0.5 && decDelta < 0.5 && fovRatio > 0.95 && fovRatio < 1.05) {
        // View hasn't moved enough - reuse cached grid
        return true;
      }
    }

    // Cache miss: rebuild
    _renderedLabels.clear();
    _grid.clear();
    _cachedCenterRA = centerRA;
    _cachedCenterDec = centerDec;
    _cachedFOV = fov;
    _cacheValid = true;
    return false;
  }

  int _cellKey(int x, int y) => Object.hash(x, y);

  Iterable<Rect> _nearbyRects(Rect rect) sync* {
    final minCellX = (rect.left / _cellSize).floor();
    final maxCellX = (rect.right / _cellSize).floor();
    final minCellY = (rect.top / _cellSize).floor();
    final maxCellY = (rect.bottom / _cellSize).floor();

    for (int x = minCellX - 1; x <= maxCellX + 1; x++) {
      for (int y = minCellY - 1; y <= maxCellY + 1; y++) {
        final bucket = _grid[_cellKey(x, y)];
        if (bucket == null) continue;
        yield* bucket;
      }
    }
  }

  void _register(Rect rect) {
    _renderedLabels.add(rect);

    final minCellX = (rect.left / _cellSize).floor();
    final maxCellX = (rect.right / _cellSize).floor();
    final minCellY = (rect.top / _cellSize).floor();
    final maxCellY = (rect.bottom / _cellSize).floor();

    for (int x = minCellX; x <= maxCellX; x++) {
      for (int y = minCellY; y <= maxCellY; y++) {
        _grid.putIfAbsent(_cellKey(x, y), () => <Rect>[]).add(rect);
      }
    }
  }

  /// Returns true if label can be placed without overlap
  bool canPlace(Rect labelRect) {
    final paddedRect = labelRect.inflate(2);
    for (final existing in _nearbyRects(paddedRect)) {
      if (paddedRect.overlaps(existing)) return false;
    }
    return true;
  }

  /// Try to find placement, returns offset or null
  Offset? findPlacement(Offset preferred, Size labelSize, Size canvasSize) {
    final offsets = [
      preferred,
      preferred + const Offset(0, -12), // Above
      preferred + const Offset(12, 0), // Right
      preferred + const Offset(-12, 0), // Left
      preferred + const Offset(0, 12), // Below
    ];

    for (final offset in offsets) {
      final rect = Rect.fromLTWH(
          offset.dx, offset.dy, labelSize.width, labelSize.height);
      if (canPlace(rect) && _isInBounds(rect, canvasSize)) {
        _register(rect);
        return offset;
      }
    }
    return null;
  }

  bool _isInBounds(Rect rect, Size canvasSize) {
    return rect.left >= 0 &&
        rect.top >= 0 &&
        rect.right <= canvasSize.width &&
        rect.bottom <= canvasSize.height;
  }
}

/// Static paint cache to avoid per-frame allocation of expensive Paint objects
/// Creating Paint objects, MaskFilters, and Shaders every frame causes significant
/// GC pressure and CPU overhead. This cache provides reusable instances.
class _PaintCache {
  // ===== Cached MaskFilters (expensive to create) =====
  static final Map<double, MaskFilter> _blurFilters = {};
  static const int _maxBlurFilterEntries = 64;

  // ===== Reusable Paint objects for common operations =====
  // These are created once and reused by updating their properties
  static final Paint _fillPaint = Paint();
  static final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _dimStarPaint = Paint()
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  static final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  static final Paint _constellationPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // Additional cached paints for various rendering operations
  static final Paint _horizonPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _eclipticPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _galacticPlanePaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _meridianPaint = Paint()
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _altAzPaint = Paint()
    ..strokeWidth = 0.5
    ..style = PaintingStyle.stroke;
  static final Paint _zenithCrossPaint = Paint()..strokeWidth = 1.0;
  static final Paint _groundPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _backgroundPaint = Paint();

  // Cached background gradient (only recreate when size changes)
  static Size? _lastBackgroundSize;
  static ui.Shader? _cachedDarkBackgroundShader;
  static ui.Shader? _cachedTwilightVerticalShader;
  static ui.Shader? _cachedTwilightRadialShader;
  static double? _lastSunAltitude;

  /// Get a fill paint with specified color (reuses single instance)
  static Paint getFillPaint(Color color) {
    _fillPaint.color = color;
    _fillPaint.shader = null;
    _fillPaint.maskFilter = null;
    return _fillPaint;
  }

  /// Get a stroke paint with specified color and width (reuses single instance)
  static Paint getStrokePaint(Color color, double strokeWidth) {
    _strokePaint.color = color;
    _strokePaint.strokeWidth = strokeWidth;
    _strokePaint.shader = null;
    _strokePaint.maskFilter = null;
    return _strokePaint;
  }

  /// Get the dim star paint (for batched point rendering)
  static Paint getDimStarPaint(Color color) {
    _dimStarPaint.color = color;
    return _dimStarPaint;
  }

  /// Get grid paint with specified color
  static Paint getGridPaint(Color color) {
    _gridPaint.color = color;
    return _gridPaint;
  }

  /// Get constellation line paint
  static Paint getConstellationPaint(Color color) {
    _constellationPaint.color = color;
    return _constellationPaint;
  }

  /// Get or create a cached MaskFilter for blur effects
  static MaskFilter getBlurFilter(double sigma) {
    final roundedSigma = (sigma * 2).round() / 2;
    var filter = _blurFilters[roundedSigma];
    if (filter == null) {
      if (_blurFilters.length >= _maxBlurFilterEntries) {
        _blurFilters.remove(_blurFilters.keys.first);
      }
      filter = MaskFilter.blur(BlurStyle.normal, roundedSigma);
      _blurFilters[roundedSigma] = filter;
    }
    return filter;
  }

  // Cached blur paints with various sigma values
  static final Map<double, Paint> _blurPaints = {};
  static const int _maxBlurPaintEntries = 64;

  /// Get or create a Paint with blur filter at the specified sigma
  /// This caches the Paint object with MaskFilter to avoid recreation
  static Paint getBlurPaint(double sigma, Color color, {double alpha = 1.0}) {
    // Round sigma to reduce cache size (blur differences < 0.5 are imperceptible)
    final roundedSigma = (sigma * 2).round() / 2;

    var paint = _blurPaints[roundedSigma];
    if (paint == null) {
      if (_blurPaints.length >= _maxBlurPaintEntries) {
        _blurPaints.remove(_blurPaints.keys.first);
      }
      paint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, roundedSigma);
      _blurPaints[roundedSigma] = paint;
    }
    // Update color (Paint objects can have color changed without recreation)
    paint.color = color.withValues(alpha: alpha);
    return paint;
  }

  /// Get horizon paint with specified color
  static Paint getHorizonPaint(Color color) {
    _horizonPaint.color = color;
    return _horizonPaint;
  }

  /// Get ecliptic paint with specified color
  static Paint getEclipticPaint(Color color) {
    _eclipticPaint.color = color;
    return _eclipticPaint;
  }

  /// Get galactic plane paint with specified color
  static Paint getGalacticPlanePaint(Color color) {
    _galacticPlanePaint.color = color;
    return _galacticPlanePaint;
  }

  /// Get meridian paint with specified color
  static Paint getMeridianPaint(Color color) {
    _meridianPaint.color = color;
    return _meridianPaint;
  }

  /// Get alt-az grid paint with specified color
  static Paint getAltAzPaint(Color color) {
    _altAzPaint.color = color;
    return _altAzPaint;
  }

  /// Get zenith cross paint with specified color
  static Paint getZenithCrossPaint(Color color) {
    _zenithCrossPaint.color = color;
    return _zenithCrossPaint;
  }

  /// Get ground plane paint with specified color
  static Paint getGroundPaint(Color color) {
    _groundPaint.color = color;
    _groundPaint.shader = null;
    return _groundPaint;
  }

  /// Get background paint with shader
  static Paint getBackgroundPaint(ui.Shader shader) {
    _backgroundPaint.shader = shader;
    return _backgroundPaint;
  }

  /// Get or create dark background shader (cached per size)
  static ui.Shader getDarkBackgroundShader(Size size) {
    if (_lastBackgroundSize != size || _cachedDarkBackgroundShader == null) {
      _cachedDarkBackgroundShader = const RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: [
          Color(0xFF0A0A1A),
          Color(0xFF050510),
          Color(0xFF020208),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      _lastBackgroundSize = size;
    }
    return _cachedDarkBackgroundShader!;
  }

  /// Clear caches (call when memory pressure is high)
  static void clearCaches() {
    _blurFilters.clear();
    _blurPaints.clear();
    _TextCache.clear();
    _ShaderCache.clear();
    _lastBackgroundSize = null;
    _cachedDarkBackgroundShader = null;
    _cachedTwilightVerticalShader = null;
    _cachedTwilightRadialShader = null;
    _lastSunAltitude = null;
    // Clear global rendering caches
    _constellationLineCache.clear();
    _milkyWayCache.clear();
    _backgroundGradientCache.clear();
    _starPsfShaderCache.clear();
  }
}

/// Cache for TextPainter objects to avoid expensive text layout every frame
/// TextPainter creation and layout() are CPU-intensive operations
class _TextCache {
  static final Map<String, TextPainter> _cache = {};
  static const int _maxCacheSize = 500;

  /// Get or create a TextPainter for the given text and style
  /// The TextPainter is cached and reused across frames
  static TextPainter get(String text, TextStyle style) {
    final key =
        '${text}_${style.fontSize}_${style.color?.toARGB32() ?? 0}_${style.fontWeight?.index ?? 0}';

    var painter = _cache[key];
    if (painter == null) {
      // Evict old entries if cache is full
      if (_cache.length >= _maxCacheSize) {
        // Remove oldest 100 entries
        final keysToRemove = _cache.keys.take(100).toList();
        for (final k in keysToRemove) {
          _cache[k]?.dispose();
          _cache.remove(k);
        }
      }

      painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: ui.TextDirection.ltr,
      );
      painter.layout();
      _cache[key] = painter;
    }
    return painter;
  }

  static void clear() {
    for (final painter in _cache.values) {
      painter.dispose();
    }
    _cache.clear();
  }
}

/// Cache for gradient shaders to avoid recreating them every frame
/// Shader creation involves GPU resource allocation
class _ShaderCache {
  static final Map<String, ui.Shader> _radialShaders = {};
  static final Map<String, ui.Shader> _linearShaders = {};
  static const int _maxCacheSize = 512;

  /// Get or create a radial gradient shader
  static ui.Shader getRadialShader(
    Offset center,
    double radius,
    List<Color> colors,
    List<double>? stops,
  ) {
    // Create a key based on the parameters (rounded for cache efficiency)
    final cx = (center.dx / 10).round() * 10;
    final cy = (center.dy / 10).round() * 10;
    final r = (radius / 5).round() * 5;
    final colorKey = colors.map((c) => c.toARGB32()).join('_');
    final key = 'r_${cx}_${cy}_${r}_$colorKey';

    var shader = _radialShaders[key];
    if (shader == null) {
      if (_radialShaders.length >= _maxCacheSize) {
        _radialShaders.clear(); // Simple eviction
      }
      shader = RadialGradient(colors: colors, stops: stops).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
      _radialShaders[key] = shader;
    }
    return shader;
  }

  static void clear() {
    _radialShaders.clear();
    _linearShaders.clear();
  }
}

final StarPsfShaderCache _starPsfShaderCache = StarPsfShaderCache();

/// Cached constellation line rendering.
/// Since constellation lines don't change unless the view moves significantly,
/// we record them into a ui.Picture and replay it each frame.
/// Cache invalidates when view center moves >0.5 degrees or zoom changes >5%.
class _ConstellationLineCache {
  ui.Picture? _picture;
  double _cachedCenterRA = double.nan;
  double _cachedCenterDec = double.nan;
  double _cachedFOV = double.nan;
  Size _cachedSize = Size.zero;
  int _cachedConstellationCount = 0;

  bool isValid(double centerRA, double centerDec, double fov, Size size,
      int constellationCount) {
    if (_picture == null) return false;
    if (size != _cachedSize) return false;
    if (constellationCount != _cachedConstellationCount) return false;

    final raDelta = (centerRA - _cachedCenterRA).abs();
    final decDelta = (centerDec - _cachedCenterDec).abs();
    final fovRatio = _cachedFOV > 0 ? (fov / _cachedFOV) : 0.0;

    // RA wraps at 24h
    final raWrapped = raDelta > 12 ? 24 - raDelta : raDelta;
    final raDeg = raWrapped * 15.0;

    return raDeg < 0.5 && decDelta < 0.5 && fovRatio > 0.95 && fovRatio < 1.05;
  }

  void store(ui.Picture picture, double centerRA, double centerDec, double fov,
      Size size, int constellationCount) {
    _picture?.dispose();
    _picture = picture;
    _cachedCenterRA = centerRA;
    _cachedCenterDec = centerDec;
    _cachedFOV = fov;
    _cachedSize = size;
    _cachedConstellationCount = constellationCount;
  }

  ui.Picture? get picture => _picture;

  void clear() {
    _picture?.dispose();
    _picture = null;
  }
}

/// Cached Milky Way rendering using the same view-invalidation strategy.
class _MilkyWayCache {
  ui.Picture? _picture;
  double _cachedCenterRA = double.nan;
  double _cachedCenterDec = double.nan;
  double _cachedFOV = double.nan;
  Size _cachedSize = Size.zero;

  bool isValid(double centerRA, double centerDec, double fov, Size size) {
    if (_picture == null) return false;
    if (size != _cachedSize) return false;

    final raDelta = (centerRA - _cachedCenterRA).abs();
    final decDelta = (centerDec - _cachedCenterDec).abs();
    final fovRatio = _cachedFOV > 0 ? (fov / _cachedFOV) : 0.0;

    final raWrapped = raDelta > 12 ? 24 - raDelta : raDelta;
    final raDeg = raWrapped * 15.0;

    return raDeg < 0.5 && decDelta < 0.5 && fovRatio > 0.95 && fovRatio < 1.05;
  }

  void store(ui.Picture picture, double centerRA, double centerDec, double fov,
      Size size) {
    _picture?.dispose();
    _picture = picture;
    _cachedCenterRA = centerRA;
    _cachedCenterDec = centerDec;
    _cachedFOV = fov;
    _cachedSize = size;
  }

  ui.Picture? get picture => _picture;

  void clear() {
    _picture?.dispose();
    _picture = null;
  }
}

// Global caches (persist across painter instances since they're recreated each frame)
final _constellationLineCache = _ConstellationLineCache();
final _milkyWayCache = _MilkyWayCache();

/// Cached background gradient shader keyed by sun altitude bucket.
/// The twilight gradient only changes meaningfully when the sun moves ~2 degrees.
class _BackgroundGradientCache {
  ui.Shader? _verticalShader;
  ui.Shader? _radialShader;
  int _sunAltBucket = -999;
  Size _size = Size.zero;

  /// Check if cache is valid for the given sun altitude and size.
  /// Sun altitude is bucketed to nearest 2 degrees.
  bool isValid(double sunAlt, Size size) {
    final bucket = (sunAlt / 2).round();
    return _verticalShader != null &&
        _radialShader != null &&
        bucket == _sunAltBucket &&
        size == _size;
  }

  void store(ui.Shader vertical, ui.Shader radial, double sunAlt, Size size) {
    _verticalShader = vertical;
    _radialShader = radial;
    _sunAltBucket = (sunAlt / 2).round();
    _size = size;
  }

  ui.Shader? get verticalShader => _verticalShader;
  ui.Shader? get radialShader => _radialShader;

  void clear() {
    _verticalShader = null;
    _radialShader = null;
    _sunAltBucket = -999;
  }
}

final _backgroundGradientCache = _BackgroundGradientCache();

/// Enhanced sky rendering painter
class SkyCanvasPainter extends CustomPainter {
  final SkyViewState viewState;
  final SkyRenderConfig config;
  final RenderQualityConfig qualityConfig;
  final List<Star> stars;
  final List<DeepSkyObject> dsos;
  final List<ConstellationData> constellations;
  final DateTime observationTime;
  final double latitude;
  final double longitude;
  final CelestialCoordinate? selectedObject;
  final CelestialCoordinate? highlightedObject;
  final CelestialCoordinate? mountPosition;
  final MountRenderStatus mountStatus;
  final (double ra, double dec)? sunPosition;
  final (double ra, double dec, double illumination)? moonPosition;
  final List<PlanetData> planets;
  final List<SatelliteData> satellites;
  final List<VariableStarData> variableStars;
  final List<MinorBodyData> minorPlanets;
  final List<MilkyWayPoint>? milkyWayPoints;

  /// Animation phase for star twinkle (0.0 - 1.0, cycles)
  final double? animationPhase;

  /// Animation phase for selection pulse (0.0 - 1.0, cycles)
  final double? selectionAnimationPhase;

  /// Animation phase for star pop-in (0.0 - 1.0)
  final double? popinAnimationPhase;

  /// Animation phase for DSO pop-in (0.0 - 1.0)
  final double? dsoPopinAnimationPhase;

  /// Current pan delta for parallax effect (pixels)
  final Offset? parallaxPanDelta;

  /// Density hotspots for crowded regions (ra, dec, visibleCount, hiddenCount)
  final List<(double, double, int, int)> densityHotspots;

  /// Set of catalog IDs or object names that have been observed.
  /// When non-empty, a small "observed" indicator is drawn on matching DSOs.
  final Set<String> observedObjectIds;

  /// Set of catalog IDs or object names that are in user observing lists.
  /// When non-empty, a small bookmark marker is drawn on matching DSOs.
  final Set<String> listedObjectIds;

  /// Bortle dark-sky scale (1-9). Controls light pollution dome intensity.
  /// 1 = pristine dark sky, 9 = inner-city.
  final int bortleClass;

  /// Custom horizon altitude at each azimuth (degrees). 360 entries for
  /// each degree of azimuth, or null to use a flat 0 deg horizon.
  /// When provided, the ground plane and obstruction dimming use this profile.
  final List<double>? horizonAltitudes;

  static const double _deg2rad = math.pi / 180;
  static const double _rad2deg = 180 / math.pi;

  /// Label layout manager to avoid overlapping labels
  final LabelLayoutManager _labelManager = LabelLayoutManager();

  SkyCanvasPainter({
    required this.viewState,
    required this.config,
    this.qualityConfig = const RenderQualityConfig.balanced(),
    required this.stars,
    required this.dsos,
    required this.constellations,
    required this.observationTime,
    required this.latitude,
    required this.longitude,
    this.selectedObject,
    this.highlightedObject,
    this.mountPosition,
    this.mountStatus = MountRenderStatus.disconnected,
    this.sunPosition,
    this.moonPosition,
    this.planets = const [],
    this.satellites = const [],
    this.variableStars = const [],
    this.minorPlanets = const [],
    this.milkyWayPoints,
    this.animationPhase,
    this.selectionAnimationPhase,
    this.popinAnimationPhase,
    this.dsoPopinAnimationPhase,
    this.parallaxPanDelta,
    this.densityHotspots = const [],
    this.observedObjectIds = const {},
    this.listedObjectIds = const {},
    this.bortleClass = 5,
    this.horizonAltitudes,
  });

  // Frame time monitoring: rolling average to detect sustained budget overruns.
  // Static so it persists across painter instances (CustomPainter is recreated each frame).
  static final List<double> _paintTimings = [];
  static const int _maxPaintTimingSamples = 60;
  static int _overBudgetCount = 0;
  static const double _frameBudgetMs = 16.0; // 60fps target
  static DateTime _lastWarningTime = DateTime(2000);

  // Frame timing diagnostic: log a per-section breakdown once after the first
  // 60 frames so the developer can see exactly where time is spent.
  static bool _hasLoggedTimingBreakdown = false;

  @override
  void paint(Canvas canvas, Size size) {
    final paintStopwatch = Stopwatch()..start();

    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (viewState.fieldOfView / 2);

    // Use cached label layout if view hasn't moved significantly.
    // When the cache is valid (view moved <0.5 deg, zoom changed <5%),
    // we skip clearing and reuse the prior frame's placement grid.
    // This means labels placed in the previous frame block the same
    // positions, providing stable labels that don't flicker between frames.
    _labelManager.clearIfViewChanged(
      viewState.centerRA, viewState.centerDec, viewState.fieldOfView,
    );

    // Per-section timing for diagnostic breakdown (collected once, then printed)
    final doTiming = !_hasLoggedTimingBreakdown && _paintTimings.length >= 59;
    final sw = doTiming ? (Stopwatch()..start()) : null;
    int bgUs = 0, mwUs = 0, gridUs = 0, overlayUs = 0, constUs = 0;
    int starUs = 0, dsoUs = 0, solarUs = 0, labelUs = 0, markerUs = 0;

    // Draw background gradient
    _drawBackground(canvas, size);
    if (doTiming) { bgUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw Milky Way (before everything else as background glow)
    if (config.showMilkyWay &&
        milkyWayPoints != null &&
        milkyWayPoints!.isNotEmpty) {
      _drawMilkyWay(canvas, size, center, scale);
    }
    if (doTiming) { mwUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw coordinate grids
    if (config.showCoordinateGrid) {
      if (config.showEquatorialGrid) {
        _drawEquatorialGrid(canvas, size, center, scale);
      }
      if (config.showAltAzGrid) {
        _drawAltAzGrid(canvas, size, center, scale);
      }
      // Draw zenith marker when grid is shown
      _drawZenithMarker(canvas, size, center, scale);
    }
    if (doTiming) { gridUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw ecliptic
    if (config.showEcliptic) {
      _drawEcliptic(canvas, size, center, scale);
    }

    // Draw galactic plane
    if (config.showGalacticPlane) {
      _drawGalacticPlane(canvas, size, center, scale);
    }

    // Draw meridian line
    if (config.showMeridian) {
      _drawMeridianLine(canvas, size, center, scale);
    }

    // Draw ground plane (gradient transition from sky to ground)
    if (config.showGroundPlane) {
      _drawGroundPlane(canvas, size, center, scale);
    }

    // Draw horizon
    if (config.showHorizon) {
      _drawHorizon(canvas, size, center, scale);
      // Draw horizon glow effect
      if (qualityConfig.enableHorizonGlow) {
        _drawHorizonGlow(canvas, size, center, scale);
      }
    }

    // Draw light pollution dome effect (quality mode only)
    if (qualityConfig.enableLightPollution) {
      _drawLightPollutionDome(canvas, size, center, scale);
    }
    if (doTiming) { overlayUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw constellation boundaries (behind lines)
    if (config.showConstellationBoundaries) {
      _drawConstellationBoundaries(canvas, size, center, scale);
    }

    // Draw constellation lines
    if (config.showConstellationLines) {
      _drawConstellationLines(canvas, size, center, scale);
    }

    // Draw constellation art overlays (only in balanced/quality tiers)
    if (config.showConstellationArt &&
        (qualityConfig.quality == RenderQuality.balanced ||
         qualityConfig.quality == RenderQuality.quality)) {
      _drawConstellationArt(canvas, size, center, scale);
    }
    if (doTiming) { constUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw stars
    if (config.showStars) {
      _drawStars(canvas, size, center, scale);
    }
    if (doTiming) { starUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw DSOs
    if (config.showDSOs) {
      _drawDSOs(canvas, size, center, scale);
    }

    // Density hotspot indicators removed — they add visual clutter
    // (circles with "+63" labels etc.) without meaningful benefit.
    // Users can simply zoom in to discover more objects.
    if (doTiming) { dsoUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw Sun
    if (config.showSun && sunPosition != null) {
      _drawSun(canvas, size, center, scale);
    }

    // Draw Moon
    if (config.showMoon && moonPosition != null) {
      _drawMoon(canvas, size, center, scale);
    }

    // Draw planets
    if (config.showPlanets && planets.isNotEmpty) {
      _drawPlanets(canvas, size, center, scale);
    }

    // Draw satellites
    if (config.showSatellites && satellites.isNotEmpty) {
      _drawSatellites(canvas, size, center, scale);
    }

    // Draw variable stars
    if (config.showVariableStars && variableStars.isNotEmpty) {
      _drawVariableStars(canvas, size, center, scale);
    }

    // Draw minor planets (asteroids and comets)
    if (config.showMinorPlanets && minorPlanets.isNotEmpty) {
      _drawMinorPlanets(canvas, size, center, scale);
    }
    if (doTiming) { solarUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw constellation labels
    if (config.showConstellationLabels) {
      _drawConstellationLabels(canvas, size, center, scale);
    }

    // Draw cardinal directions
    if (config.showCardinalDirections) {
      _drawCardinalDirections(canvas, size);
    }
    if (doTiming) { labelUs = sw!.elapsedMicroseconds; sw.reset(); sw.start(); }

    // Draw mount position marker
    if (config.showMountPosition &&
        mountPosition != null &&
        mountStatus != MountRenderStatus.disconnected) {
      _drawMountPositionMarker(
          canvas, size, center, scale, mountPosition!, mountStatus);
    }

    // Draw selected object marker
    if (selectedObject != null) {
      _drawSelectionMarker(canvas, center, scale, selectedObject!);
    }
    if (doTiming) { markerUs = sw!.elapsedMicroseconds; sw.stop(); }

    // Print per-section timing breakdown once after 60 frames for diagnostics
    if (doTiming) {
      _hasLoggedTimingBreakdown = true;
      final totalUs = bgUs + mwUs + gridUs + overlayUs + constUs + starUs + dsoUs + solarUs + labelUs + markerUs;
      developer.log(
        'SkyCanvasPainter TIMING BREAKDOWN (frame 60, ${(totalUs / 1000.0).toStringAsFixed(1)}ms total):\n'
        '  Background:     ${(bgUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Milky Way:      ${(mwUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Grids:          ${(gridUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Overlays:       ${(overlayUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Constellations: ${(constUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Stars (${stars.length}): ${(starUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  DSOs (${dsos.length}):  ${(dsoUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Solar system:   ${(solarUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Labels:         ${(labelUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Markers:        ${(markerUs / 1000.0).toStringAsFixed(2)}ms\n'
        '  Quality: ${qualityConfig.quality.name}',
        name: 'SkyCanvasPainter',
        level: 500,
      );
    }

    // Record paint() frame time and warn if consistently over budget
    paintStopwatch.stop();
    final paintMs = paintStopwatch.elapsedMicroseconds / 1000.0;
    _paintTimings.add(paintMs);
    if (_paintTimings.length > _maxPaintTimingSamples) {
      _paintTimings.removeAt(0);
    }

    if (paintMs > _frameBudgetMs) {
      _overBudgetCount++;
    } else if (_overBudgetCount > 0) {
      _overBudgetCount--;
    }

    // Log warning if 10+ of last 60 frames exceeded the 16ms budget
    // Throttle to at most once per 5 seconds to avoid log spam
    if (_overBudgetCount >= 10 && _paintTimings.length >= 20) {
      final now = DateTime.now();
      if (now.difference(_lastWarningTime).inSeconds >= 5) {
        _lastWarningTime = now;
        final avgMs = _paintTimings.reduce((a, b) => a + b) / _paintTimings.length;
        developer.log(
          'SkyCanvasPainter: paint() averaging ${avgMs.toStringAsFixed(1)}ms '
          '(budget: ${_frameBudgetMs}ms). '
          '$_overBudgetCount of last ${_paintTimings.length} frames over budget. '
          'Quality: ${qualityConfig.quality.name}, '
          'Stars: ${stars.length}, DSOs: ${dsos.length}. '
          'Consider lowering render quality.',
          name: 'SkyCanvasPainter',
          level: 900,
        );
      }
    }
  }

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
      final paint =
          _PaintCache.getBackgroundPaint(_backgroundGradientCache.verticalShader!);
      canvas.drawRect(rect, paint);
      final radialPaint =
          _PaintCache.getBackgroundPaint(_backgroundGradientCache.radialShader!);
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

  void _drawMilkyWay(Canvas canvas, Size size, Offset center, double scale) {
    if (milkyWayPoints == null) return;

    // Check if we can reuse a cached Milky Way Picture.
    // The Milky Way is fixed on the sky, so it only needs redrawing when the view moves.
    if (_milkyWayCache.isValid(
        viewState.centerRA, viewState.centerDec, viewState.fieldOfView, size)) {
      canvas.drawPicture(_milkyWayCache.picture!);
      return;
    }

    // Cache miss: record Milky Way into a Picture
    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    // Calculate appropriate blur and point size based on FOV
    final fovFactor = viewState.fieldOfView / 60;
    final blurRadius = (8 * fovFactor).clamp(4.0, 20.0);
    final pointRadius = (3 * fovFactor).clamp(2.0, 8.0);

    // Milky Way color - subtle blue-white glow
    const baseColor = Color(0xFF8090A8);

    // Batch Milky Way points into Float32List groups by intensity bucket
    // to minimize draw calls
    final glowPoints = <double>[];
    final corePoints = <double>[];

    for (final point in milkyWayPoints!) {
      final offset = _celestialToScreen(point.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      glowPoints.add(offset.dx);
      glowPoints.add(offset.dy);

      if (point.intensity > 0.5) {
        corePoints.add(offset.dx);
        corePoints.add(offset.dy);
      }
    }

    // Draw all glow points as a single batch
    if (glowPoints.isNotEmpty) {
      final glowPaint =
          _PaintCache.getBlurPaint(blurRadius, baseColor, alpha: 0.12);
      glowPaint.strokeWidth = pointRadius * 4;
      glowPaint.strokeCap = StrokeCap.round;
      recordCanvas.drawRawPoints(ui.PointMode.points,
          Float32List.fromList(glowPoints), glowPaint);
    }

    // Draw brighter core points as a second batch
    if (corePoints.isNotEmpty) {
      final corePaint = _PaintCache.getBlurPaint(blurRadius * 0.5, baseColor,
          alpha: 0.18);
      corePaint.strokeWidth = pointRadius * 2;
      corePaint.strokeCap = StrokeCap.round;
      recordCanvas.drawRawPoints(ui.PointMode.points,
          Float32List.fromList(corePoints), corePaint);
    }

    final picture = recorder.endRecording();
    _milkyWayCache.store(picture, viewState.centerRA, viewState.centerDec,
        viewState.fieldOfView, size);

    canvas.drawPicture(picture);
  }

  void _drawEquatorialGrid(
      Canvas canvas, Size size, Offset center, double scale) {
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

    // Draw RA lines with adaptive spacing
    for (var ra = 0.0; ra < 24; ra += raSpacing) {
      final path = Path();
      var firstPoint = true;

      for (var dec = -90.0; dec <= 90; dec += decStep) {
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

  void _drawGridLabels(Canvas canvas, Size size, Offset center, double scale,
      double raSpacing, double decSpacing) {
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
        textPainter.paint(
          canvas,
          offset + Offset(-textPainter.width / 2, 4),
        );
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
        textPainter.paint(
          canvas,
          offset + Offset(4, -textPainter.height / 2),
        );
      }
    }
  }

  void _drawZenithMarker(
      Canvas canvas, Size size, Offset center, double scale) {
    // Calculate zenith position (altitude 90 degrees)
    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);
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
    final paint =
        _PaintCache.getZenithCrossPaint(Colors.white.withValues(alpha: 0.4));

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
    final paint =
        _PaintCache.getAltAzPaint(config.gridColor.withValues(alpha: 0.3));

    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

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
      Canvas canvas, Size size, Offset center, double scale) {
    final paint =
        _PaintCache.getGalacticPlanePaint(config.galacticPlaneColor);

    final path = Path();
    var firstPoint = true;

    // Draw galactic equator as a great circle at galactic latitude 0
    for (var lon = 0.0; lon <= 360; lon += 2) {
      final (ra, dec) = AstronomyCalculations.galacticToEquatorial(
        lonDeg: lon,
        latDeg: 0,
      );

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
      Canvas canvas, Size size, Offset center, double scale) {
    if (!config.showMeridian) return;

    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

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
          CelestialCoordinate(ra: ra / 15, dec: dec), center, scale);
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
          CelestialCoordinate(ra: ra / 15, dec: dec), center, scale);
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
    final paint =
        _PaintCache.getMeridianPaint(Colors.green.withValues(alpha: 0.4));
    canvas.drawPath(path, paint);
  }

  void _drawHorizon(Canvas canvas, Size size, Offset center, double scale) {
    // For flat horizons the ground-plane gradient transition IS the horizon
    // indicator -- drawing an explicit stroke line creates a hard visible edge
    // that looks unnatural.  Only draw a faint line for custom horizon profiles
    // (terrain outlines) where the irregular shape needs a subtle guide.

    if (horizonAltitudes == null || horizonAltitudes!.isEmpty) {
      // Flat horizon: no stroke line.  The ground-plane blend handles it.
      return;
    }

    // Custom horizon profile: draw as a very subtle polyline following the
    // terrain so the user can see where trees/buildings clip the sky.
    final paint = _PaintCache.getHorizonPaint(
      config.horizonColor.withValues(alpha: (config.horizonColor.a * 0.4).clamp(0.0, 1.0)),
    );

    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

    final path = Path();
    var firstPoint = true;
    final step = 5.0; // 5-degree azimuth steps for smooth line

    for (var az = 0.0; az <= 360.0; az += step) {
      final azIdx = az.round() % 360;
      final horizonAlt = (azIdx < horizonAltitudes!.length)
          ? horizonAltitudes![azIdx]
          : 0.0;

      final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
        altDeg: horizonAlt,
        azDeg: az,
        latitudeDeg: latitude,
        lstHours: lst,
      );

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

  /// Draw ground plane below the horizon with gradient.
  /// When a custom horizon profile is set, fills below the profile curve.
  /// Uses simple linear approximation based on view altitude for flat horizons.
  ///
  /// The ground plane starts fully transparent well above the horizon and
  /// gradually fades to opaque ground color below, so the transition from
  /// sky to ground is seamless -- no visible horizon line or hard edge.
  void _drawGroundPlane(Canvas canvas, Size size, Offset center, double scale) {
    if (!config.showGroundPlane) return;

    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

    if (horizonAltitudes != null && horizonAltitudes!.isNotEmpty) {
      // Custom horizon: fill below the profile as a polygon
      _drawCustomHorizonGroundPlane(canvas, size, center, scale, lst);
      return;
    }

    // Flat horizon: original fast path
    final (_, centerAlt) = AstronomyCalculations.equatorialToHorizontal(
      raDeg: viewState.centerRA * 15,
      decDeg: viewState.centerDec,
      latitudeDeg: latitude,
      lstHours: lst,
    );

    final fovHalf = viewState.fieldOfView / 2;
    final horizonY = size.height / 2 * (1 + centerAlt / fovHalf);

    if (horizonY >= size.height) return;

    if (horizonY <= 0) {
      final paint = _PaintCache.getGroundPaint(config.groundColorDark);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      return;
    }

    // Compute the sky's horizon color so the ground blend starts from the
    // same hue that the sky gradient ends at -- no color discontinuity.
    final sunAlt = AstronomyCalculations.sunAltitude(
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );
    final (_, skyHorizonColor) = _getTwilightColors(sunAlt);

    // Use a generous blend zone (20% of screen height) so the transition
    // is a wide, imperceptible fade rather than a narrow band.
    final blendZone = (size.height * 0.20).clamp(30.0, 180.0);
    final groundTop = horizonY - blendZone;
    final groundRect = Rect.fromLTRB(0, groundTop, size.width, size.height);

    // The fraction of the gradient rect height where the actual horizon sits.
    final totalHeight = size.height - groundTop;
    final horizonFraction = (horizonY - groundTop) / totalHeight;

    if (qualityConfig.groundPlaneDetail <= 0.0) {
      // Low-detail mode: simple transparent-to-opaque fade using ground color.
      // Still uses the wide blend zone for a smooth edge.
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          config.groundColorDark.withValues(alpha: 0.0),
          config.groundColorDark.withValues(alpha: 0.5),
          config.groundColorDark,
        ],
        stops: [
          0.0,
          horizonFraction,
          (horizonFraction + 0.15).clamp(0.0, 1.0),
        ],
      );
      final paint = Paint()..shader = gradient.createShader(groundRect);
      canvas.drawRect(groundRect, paint);
    } else {
      // High-detail mode: blend from sky horizon color through a warm
      // intermediate to the dark ground.  The top of the gradient is fully
      // transparent sky-horizon color, becoming opaque at the horizon, then
      // transitioning through the ground palette below.
      //
      // Build a smooth multi-stop gradient:
      //   0.0               : fully transparent (sky shows through)
      //   horizonFraction/2 : very faint tint of sky-horizon color
      //   horizonFraction   : sky-horizon color at moderate opacity (the "seam")
      //   below horizon     : blends to ground colors
      final midBlend = (horizonFraction * 0.5).clamp(0.0, 1.0);
      final belowHorizon1 =
          (horizonFraction + (1.0 - horizonFraction) * 0.25).clamp(0.0, 1.0);
      final belowHorizon2 =
          (horizonFraction + (1.0 - horizonFraction) * 0.55).clamp(0.0, 1.0);

      // Blend sky-horizon color toward the ground-light color for the seam
      // so there is never a jarring hue shift.
      final seamColor =
          Color.lerp(skyHorizonColor, config.groundColorLight, 0.35)!;

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          skyHorizonColor.withValues(alpha: 0.0),
          skyHorizonColor.withValues(alpha: 0.10),
          seamColor.withValues(alpha: 0.55),
          config.groundColorLight,
          config.groundColorDark,
        ],
        stops: [
          0.0,
          midBlend,
          horizonFraction,
          belowHorizon1,
          belowHorizon2,
        ],
      );

      final paint = Paint()..shader = gradient.createShader(groundRect);
      canvas.drawRect(groundRect, paint);

      // No stroke line at the horizon -- the gradient transition IS the
      // horizon.  A visible line looks artificial.
    }
  }

  /// Draw ground plane following custom horizon profile.
  /// Builds a filled polygon from horizon profile points down to screen bottom.
  /// Uses the same sky-matching gradient approach as the flat horizon path
  /// so the ground blends seamlessly with the sky.
  void _drawCustomHorizonGroundPlane(
      Canvas canvas, Size size, Offset center, double scale, double lst) {
    final path = Path();
    final step = 5.0;

    // Collect screen positions along the custom horizon
    final horizonPoints = <Offset>[];

    for (var az = 0.0; az <= 360.0; az += step) {
      final azIdx = az.round() % 360;
      final horizonAlt = (azIdx < horizonAltitudes!.length)
          ? horizonAltitudes![azIdx]
          : 0.0;

      final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
        altDeg: horizonAlt,
        azDeg: az,
        latitudeDeg: latitude,
        lstHours: lst,
      );

      final offset = _celestialToScreen(
        CelestialCoordinate(ra: ra / 15, dec: dec),
        center,
        scale,
      );

      if (offset != null) {
        // Clamp x to screen bounds for the fill
        final clampedX = offset.dx.clamp(-100.0, size.width + 100.0);
        final clampedY = offset.dy.clamp(-100.0, size.height + 200.0);
        horizonPoints.add(Offset(clampedX, clampedY));
      }
    }

    if (horizonPoints.isEmpty) {
      // If no horizon points are visible, check if we're looking entirely below
      final (_, centerAlt) = AstronomyCalculations.equatorialToHorizontal(
        raDeg: viewState.centerRA * 15,
        decDeg: viewState.centerDec,
        latitudeDeg: latitude,
        lstHours: lst,
      );
      if (centerAlt < 0) {
        // Looking below horizon, fill entire screen
        final paint = _PaintCache.getGroundPaint(config.groundColorDark);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      }
      return;
    }

    // Build fill polygon: horizon points, then close down to screen bottom
    path.moveTo(horizonPoints.first.dx, horizonPoints.first.dy);
    for (var i = 1; i < horizonPoints.length; i++) {
      path.lineTo(horizonPoints[i].dx, horizonPoints[i].dy);
    }
    // Close down to bottom-right, then bottom-left
    path.lineTo(size.width + 100, size.height + 100);
    path.lineTo(-100, size.height + 100);
    path.close();

    // Compute the sky's horizon color for seamless blending
    final sunAlt = AstronomyCalculations.sunAltitude(
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );
    final (_, skyHorizonColor) = _getTwilightColors(sunAlt);

    // Draw the fill
    if (qualityConfig.groundPlaneDetail <= 0.0) {
      // Low-detail: use a simple gradient that still fades smoothly
      var topY = size.height;
      for (final pt in horizonPoints) {
        if (pt.dy < topY) topY = pt.dy;
      }
      final blendZone = (size.height * 0.20).clamp(30.0, 180.0);
      final gradientTop = topY - blendZone;
      final groundRect =
          Rect.fromLTRB(0, gradientTop, size.width, size.height);
      final horizonFraction =
          (topY - gradientTop) / (size.height - gradientTop);

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          config.groundColorDark.withValues(alpha: 0.0),
          config.groundColorDark.withValues(alpha: 0.5),
          config.groundColorDark,
        ],
        stops: [
          0.0,
          horizonFraction,
          (horizonFraction + 0.15).clamp(0.0, 1.0),
        ],
      );

      final paint = Paint()..shader = gradient.createShader(groundRect);
      canvas.drawPath(path, paint);
    } else {
      // High-detail: match the sky horizon color and fade smoothly.
      var topY = size.height;
      for (final pt in horizonPoints) {
        if (pt.dy < topY) topY = pt.dy;
      }
      final blendZone = (size.height * 0.20).clamp(30.0, 180.0);
      final gradientTop = topY - blendZone;

      final groundRect =
          Rect.fromLTRB(0, gradientTop, size.width, size.height);
      final totalHeight = size.height - gradientTop;
      final horizonFraction = (topY - gradientTop) / totalHeight;

      final midBlend = (horizonFraction * 0.5).clamp(0.0, 1.0);
      final belowHorizon1 =
          (horizonFraction + (1.0 - horizonFraction) * 0.25).clamp(0.0, 1.0);
      final belowHorizon2 =
          (horizonFraction + (1.0 - horizonFraction) * 0.55).clamp(0.0, 1.0);

      final seamColor =
          Color.lerp(skyHorizonColor, config.groundColorLight, 0.35)!;

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          skyHorizonColor.withValues(alpha: 0.0),
          skyHorizonColor.withValues(alpha: 0.10),
          seamColor.withValues(alpha: 0.55),
          config.groundColorLight,
          config.groundColorDark,
        ],
        stops: [
          0.0,
          midBlend,
          horizonFraction,
          belowHorizon1,
          belowHorizon2,
        ],
      );

      final paint = Paint()..shader = gradient.createShader(groundRect);
      canvas.drawPath(path, paint);

      // No glow stroke line -- the gradient handles the transition.
    }
  }

  /// Draw light pollution dome effect (quality mode only)
  /// Creates a warm orange-white wash near the horizon that fades toward zenith.
  /// Uses a smooth vertical gradient instead of discrete stroke bands so
  /// there are no visible banding artifacts near the horizon.
  /// Intensity and extent are scaled by Bortle class (1-9):
  ///   Bortle 1-2: virtually no dome
  ///   Bortle 4-5: moderate suburban glow
  ///   Bortle 8-9: heavy urban wash extending high overhead
  void _drawLightPollutionDome(
      Canvas canvas, Size size, Offset center, double scale) {
    // Bortle 1-2 produces negligible light pollution
    if (bortleClass <= 2) return;

    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

    // Get the altitude of the view center
    final (_, centerAlt) = AstronomyCalculations.equatorialToHorizontal(
      raDeg: viewState.centerRA * 15,
      decDeg: viewState.centerDec,
      latitudeDeg: latitude,
      lstHours: lst,
    );

    final fovHalf = viewState.fieldOfView / 2;

    // Scale factor based on Bortle class (0.0 at Bortle 2, 1.0 at Bortle 9)
    final bortleScale = (bortleClass - 2).clamp(0, 7) / 7.0;

    // Light pollution color - warm orange-white, shifts more orange at higher Bortle
    final pollutionColor = Color.lerp(
      const Color(0xFFFFF5E0), // subtle warm white (suburban)
      const Color(0xFFFFCC80), // stronger orange (urban)
      bortleScale,
    )!;

    // The dome extends from the horizon up to maxAlt degrees
    final maxAlt = 20.0 + bortleScale * 40.0; // 20-60 degrees

    // Calculate screen Y for the horizon (alt = 0) and the top of the dome
    final horizonFraction = (centerAlt / fovHalf).clamp(-1.5, 1.5);
    final horizonY = size.height / 2 + (horizonFraction * size.height / 2);
    final topFraction =
        ((centerAlt - maxAlt) / fovHalf).clamp(-1.5, 1.5);
    final domeTopY = size.height / 2 + (topFraction * size.height / 2);

    // Skip if entirely off screen
    if (horizonY < -50 && domeTopY < -50) return;
    if (horizonY > size.height + 50 && domeTopY > size.height + 50) return;

    final domeRect = Rect.fromLTRB(0, domeTopY, size.width, horizonY);
    if (domeRect.height <= 0) return;

    // Base opacity scales with Bortle: 0.03 at Bortle 3 up to 0.18 at Bortle 9
    final baseOpacity = 0.03 + bortleScale * 0.15;

    // Use a smooth multi-stop gradient from top (transparent) to horizon
    // (peak opacity). The falloff is quadratic, approximated by 4 stops.
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        pollutionColor.withValues(alpha: 0.0),
        pollutionColor.withValues(alpha: baseOpacity * 0.04),
        pollutionColor.withValues(alpha: baseOpacity * 0.20),
        pollutionColor.withValues(alpha: baseOpacity * 0.55),
        pollutionColor.withValues(alpha: baseOpacity),
      ],
      stops: const [0.0, 0.3, 0.55, 0.80, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(domeRect);
    if (qualityConfig.useBlurEffects) {
      paint.maskFilter = _PaintCache.getBlurFilter(10);
    }
    canvas.drawRect(domeRect, paint);
  }

  /// Draw a subtle atmospheric glow above the horizon.
  /// Instead of discrete stroke bands (which can create visible banding), this
  /// uses a single vertical gradient rect that fades smoothly from the horizon
  /// upward, simulating the natural sky-brightening near the horizon.
  void _drawHorizonGlow(Canvas canvas, Size size, Offset center, double scale) {
    final lst =
        AstronomyCalculations.localSiderealTime(observationTime, longitude);

    // Get the altitude of the view center
    final (_, centerAlt) = AstronomyCalculations.equatorialToHorizontal(
      raDeg: viewState.centerRA * 15,
      decDeg: viewState.centerDec,
      latitudeDeg: latitude,
      lstHours: lst,
    );

    final fovHalf = viewState.fieldOfView / 2;

    // Calculate sun altitude to determine glow color
    final sunAlt = AstronomyCalculations.sunAltitude(
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Determine glow color based on twilight state
    Color glowColor;
    if (sunAlt <= -18) {
      glowColor = const Color(0xFF1A2030);
    } else if (sunAlt <= -6) {
      final t = ((sunAlt + 18) / 12).clamp(0.0, 1.0);
      glowColor =
          Color.lerp(const Color(0xFF1A2030), const Color(0xFF3A2840), t)!;
    } else if (sunAlt <= 0) {
      final t = ((sunAlt + 6) / 6).clamp(0.0, 1.0);
      glowColor =
          Color.lerp(const Color(0xFF3A2840), const Color(0xFF604030), t)!;
    } else {
      glowColor = const Color(0xFF706050);
    }

    // Calculate screen Y for altitude 0 (horizon) and the glow extent
    // (approximately 20 degrees above horizon).
    final glowExtentDeg = 20.0;
    final horizonFraction = (centerAlt / fovHalf).clamp(-1.5, 1.5);
    final horizonY = size.height / 2 + (horizonFraction * size.height / 2);
    final topFraction =
        ((centerAlt - glowExtentDeg) / fovHalf).clamp(-1.5, 1.5);
    final glowTopY = size.height / 2 + (topFraction * size.height / 2);

    // Both off screen? Nothing to draw.
    if (horizonY < -50 && glowTopY < -50) return;
    if (horizonY > size.height + 50 && glowTopY > size.height + 50) return;

    // Draw a single gradient rect from the glow top down to the horizon.
    // The gradient goes from fully transparent at the top to the peak glow
    // opacity at the horizon, with a smooth curve via multiple stops.
    final glowRect =
        Rect.fromLTRB(0, glowTopY, size.width, horizonY);

    if (glowRect.height <= 0) return;

    final peakOpacity = sunAlt <= -18 ? 0.06 : (sunAlt <= 0 ? 0.10 : 0.12);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        glowColor.withValues(alpha: 0.0),
        glowColor.withValues(alpha: peakOpacity * 0.15),
        glowColor.withValues(alpha: peakOpacity * 0.45),
        glowColor.withValues(alpha: peakOpacity),
      ],
      stops: const [0.0, 0.4, 0.75, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(glowRect);
    if (qualityConfig.useBlurEffects) {
      // Apply a soft blur so the glow is diffuse, not sharp-edged.
      paint.maskFilter = _PaintCache.getBlurFilter(12);
    }
    canvas.drawRect(glowRect, paint);
  }

  void _drawConstellationBoundaries(
      Canvas canvas, Size size, Offset center, double scale) {
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
          CelestialCoordinate(ra: v0.ra, dec: v0.dec), center, scale);
        final end = _celestialToScreen(
          CelestialCoordinate(ra: v1.ra, dec: v1.dec), center, scale);

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
          path.moveTo(
            start.dx + unitDx * dist,
            start.dy + unitDy * dist,
          );
          path.lineTo(
            start.dx + unitDx * segEnd,
            start.dy + unitDy * segEnd,
          );
          dist += dashLength + gapLength;
        }
      }
    }

    canvas.drawPath(path, boundaryPaint);
  }

  void _drawConstellationLines(
      Canvas canvas, Size size, Offset center, double scale) {
    // Check if we can reuse a cached Picture of constellation lines.
    // Constellation lines are static relative to the sky — they only change
    // when the view moves, so caching saves redrawing hundreds of line segments.
    if (_constellationLineCache.isValid(
        viewState.centerRA, viewState.centerDec, viewState.fieldOfView, size,
        constellations.length)) {
      canvas.drawPicture(_constellationLineCache.picture!);
      return;
    }

    // Cache miss: record constellation lines into a Picture
    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final paint =
        _PaintCache.getConstellationPaint(config.constellationLineColor);

    // Batch all lines into a single Path for better performance
    final path = Path();

    for (final constellation in constellations) {
      for (final line in constellation.lines) {
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
    _constellationLineCache.store(picture, viewState.centerRA,
        viewState.centerDec, viewState.fieldOfView, size, constellations.length);

    // Draw the picture to the real canvas
    canvas.drawPicture(picture);
  }

  void _drawConstellationLabels(
      Canvas canvas, Size size, Offset center, double scale) {
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    for (final constellation in constellations) {
      final offset = _celestialToScreen(constellation.center, center, scale);

      if (offset != null && _isInView(offset, size)) {
        // Use cached TextPainter for constellation labels
        final textPainter =
            _TextCache.get(constellation.name.toUpperCase(), textStyle);
        textPainter.paint(
          canvas,
          offset - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  /// Cached constellation art figures (loaded once)
  static final List<ConstellationArtData> _constellationArtFigures =
      ConstellationArt.all;

  void _drawConstellationArt(
      Canvas canvas, Size size, Offset center, double scale) {
    // Gold/amber fill with 20% opacity
    final fillPaint = Paint()
      ..color = const Color(0x33DAA520) // goldenrod at ~20% opacity
      ..style = PaintingStyle.fill;

    // Slightly brighter stroke for figure outlines
    final strokePaint = Paint()
      ..color = const Color(0x28DAA520) // goldenrod at ~16% opacity
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final figure in _constellationArtFigures) {
      // Quick visibility check: find the constellation data to get its center
      final constellationData = constellations
          .where((c) => c.abbreviation == figure.abbreviation)
          .firstOrNull;
      if (constellationData == null) continue;

      final centerOffset =
          _celestialToScreen(constellationData.center, center, scale);
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
              path.quadraticBezierTo(
                  ctrlPt.dx, ctrlPt.dy, endPt.dx, endPt.dy);
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

  void _drawStars(Canvas canvas, Size size, Offset center, double scale) {
    // Ultra-minimal mode: ALL stars as raw points, no circles, no PSF
    if (qualityConfig.quality == RenderQuality.minimal) {
      _drawStarsMinimal(canvas, size, center, scale);
      return;
    }

    // Respect quality config limits. The star list is already pre-filtered by
    // the dynamic magnitude provider (fovFilteredStarsProvider) based on FOV,
    // so we only apply the quality config's render count cap here. We use the
    // quality config's magnitude limit as an additional safeguard rather than
    // the static SkyRenderConfig.starMagnitudeLimit, which is a UI default
    // that doesn't account for zoom level.
    final maxStars = qualityConfig.maxStarsToRender;
    final magLimit = qualityConfig.starMagnitudeLimit;

    // Twinkle animation enabled in quality mode
    final doTwinkle =
        qualityConfig.animateStarTwinkle && animationPhase != null;

    // Pre-calculate LST for atmospheric extinction (computed once, not per-star)
    final doExtinction = qualityConfig.enableAtmosphericExtinction;
    final lst = doExtinction
        ? AstronomyCalculations.localSiderealTime(observationTime, longitude)
        : 0.0;

    // Parallax effect: offset dim stars during pan for depth illusion
    final doParallax = qualityConfig.enableParallax &&
        parallaxPanDelta != null &&
        parallaxPanDelta!.distance > 0.5;

    // PERFORMANCE OPTIMIZATION: Batch stars into groups by rendering style
    // instead of creating new shaders for every star

    // Group 1: Dim stars (mag >= 3) - draw as simple points in batches by color
    // Group 2: Medium stars (1.5 <= mag < 3) - draw as circles with pre-cached paints
    // Group 3: Bright stars (mag < 1.5) - draw with glow effects (limited count)

    final dimStarPoints = <Offset>[];
    final dimStarColors = <Color>[];

    final mediumStars = <(
      Offset,
      double,
      Color,
      double
    )>[]; // offset, radius, color, brightness
    final brightStars = <(
      Offset,
      double,
      Color,
      double,
      double,
      Star
    )>[]; // offset, radius, color, brightness, magnitude, star

    var starsProcessed = 0;

    for (final star in stars) {
      if (starsProcessed >= maxStars) break;
      if ((star.magnitude ?? 99) > magLimit) continue;

      var offset = _celestialToScreen(star.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      final magnitude = star.magnitude ?? 5.0;

      // Apply parallax offset to dim stars (mag > 4)
      if (doParallax && magnitude > 4.0) {
        final parallaxFactor = ((magnitude - 4.0) / 6.0).clamp(0.0, 1.0) * 0.02;
        offset = Offset(
          offset.dx + parallaxPanDelta!.dx * parallaxFactor,
          offset.dy + parallaxPanDelta!.dy * parallaxFactor,
        );
      }

      var radius = _magnitudeToRadius(magnitude);
      var brightness = _magnitudeToBrightness(magnitude);

      // Apply twinkle effect for brighter stars (mag < 4)
      if (doTwinkle && magnitude < 4.0) {
        final starPhase =
            (star.coordinates.ra * 1000 + star.coordinates.dec * 100) % 1.0;
        final twinklePhase = (animationPhase! + starPhase) % 1.0;
        final twinkleFactor = magnitude < 2.0 ? 0.15 : 0.08;
        final twinkleValue =
            math.sin(twinklePhase * 2 * math.pi) * twinkleFactor;
        brightness = (brightness + twinkleValue).clamp(0.0, 1.0);
        if (magnitude < 1.5) {
          radius *= 1.0 + twinkleValue * 0.3;
        }
      }

      // Star color
      var color = _spectralTypeToColor(star.spectralType ?? 'G');
      color = _getEnhancedStarColor(color, magnitude);

      // Atmospheric extinction for bright stars only - uses precomputed LUT
      if (doExtinction && magnitude < 3.0) {
        final (alt, _) = AstronomyCalculations.equatorialToHorizontal(
          raDeg: star.coordinates.raDegrees,
          decDeg: star.coordinates.dec,
          latitudeDeg: latitude,
          lstHours: lst,
        );
        if (alt < 30) {
          final (extinctionFactor, redShift) =
              AtmosphericExtinctionLUT.lookup(alt);
          brightness *= extinctionFactor;
          color = Color.lerp(color, const Color(0xFFFFAA88), redShift)!;
        }
      }

      // Sort into batches by magnitude
      if (magnitude >= 3.0) {
        // Dim stars: batch as points
        dimStarPoints.add(offset);
        dimStarColors.add(color.withValues(alpha: brightness));
      } else if (magnitude >= 1.5) {
        // Medium stars: simple circles
        mediumStars.add((offset, radius, color, brightness));
      } else {
        // Bright stars: full PSF with glow (expensive, but few of these)
        brightStars.add((offset, radius, color, brightness, magnitude, star));
      }

      starsProcessed++;
    }

    // BATCH RENDER: Dim stars as points (single draw call)
    // Using cached paint object to avoid allocation
    if (dimStarPoints.isNotEmpty) {
      final dimPaint =
          _PaintCache.getDimStarPaint(Colors.white.withValues(alpha: 0.7));
      canvas.drawPoints(ui.PointMode.points, dimStarPoints, dimPaint);
    }

    // BATCH RENDER: Medium stars as raw points (single draw call)
    // Instead of ~800 individual drawCircle calls, batch all medium star
    // offsets into a Float32List and draw with a single drawRawPoints call.
    // Group by approximate color bucket for fewer draw calls.
    if (mediumStars.isNotEmpty) {
      // Bucket medium stars by rounded color for batching
      final colorBuckets = <int, List<(Offset, double)>>{};
      for (final (offset, radius, color, brightness) in mediumStars) {
        // Quantize color to reduce bucket count (round alpha to nearest 0.1)
        final quantizedAlpha = (brightness * 10).round() / 10.0;
        final bucketColor = color.withValues(alpha: quantizedAlpha);
        final key = bucketColor.toARGB32();
        (colorBuckets[key] ??= []).add((offset, radius));
      }

      // Reuse a single Paint object for all buckets to avoid GC pressure
      final bucketPaint = Paint()..strokeCap = StrokeCap.round;

      for (final entry in colorBuckets.entries) {
        final offsets = entry.value;
        final bucketColor = Color(entry.key);

        // Calculate average radius for this bucket to set stroke width
        var totalRadius = 0.0;
        for (final (_, radius) in offsets) {
          totalRadius += radius;
        }
        final avgRadius = totalRadius / offsets.length;

        // Build Float32List of x,y pairs for drawRawPoints
        final points = Float32List(offsets.length * 2);
        for (var i = 0; i < offsets.length; i++) {
          points[i * 2] = offsets[i].$1.dx;
          points[i * 2 + 1] = offsets[i].$1.dy;
        }

        bucketPaint
          ..color = bucketColor
          ..strokeWidth = avgRadius * 2;
        canvas.drawRawPoints(ui.PointMode.points, points, bucketPaint);
      }
    }

    // INDIVIDUAL RENDER: Bright stars with full PSF (few of these, worth the cost)
    for (final (offset, radius, color, brightness, magnitude, star)
        in brightStars) {
      _drawStarPSF(canvas, offset, radius, color, brightness, magnitude);

      // Draw star name for bright stars using cached TextPainter
      if (magnitude < 2.0 && star.name.isNotEmpty) {
        final fontSize = _getLabelFontSize(magnitude, 'star');
        final fontWeight = _getLabelFontWeight(magnitude);
        final textStyle = TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
        // Use cached TextPainter instead of creating new one
        final textPainter = _TextCache.get(star.name, textStyle);

        final preferredPos =
            offset + Offset(radius + 3, -textPainter.height / 2);
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

  /// Ultra-minimal star rendering: all stars as raw points in a single draw call.
  /// No circles, no PSF, no glow. Designed for Raspberry Pi at 30fps.
  void _drawStarsMinimal(Canvas canvas, Size size, Offset center, double scale) {
    final maxStars = qualityConfig.maxStarsToRender;
    final magLimit = qualityConfig.starMagnitudeLimit;

    // Collect all visible star positions into a single Float32List
    final points = <double>[];
    var starsProcessed = 0;

    for (final star in stars) {
      if (starsProcessed >= maxStars) break;
      if ((star.magnitude ?? 99) > magLimit) continue;

      final offset = _celestialToScreen(star.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      points.add(offset.dx);
      points.add(offset.dy);
      starsProcessed++;
    }

    if (points.isEmpty) return;

    // Single draw call for ALL stars as points
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(
        ui.PointMode.points, Float32List.fromList(points), paint);

    // Draw labels for only the very brightest stars (mag < 1.0) even in minimal mode
    for (final star in stars) {
      final mag = star.magnitude ?? 99.0;
      if (mag >= 1.0 || star.name.isEmpty) continue;

      final offset = _celestialToScreen(star.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      final textStyle = TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 9,
        fontWeight: FontWeight.w500,
      );
      final textPainter = _TextCache.get(star.name, textStyle);
      textPainter.paint(canvas, offset + Offset(4, -textPainter.height / 2));
    }
  }

  /// Draw a star using quality-appropriate point spread function
  void _drawStarPSF(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double brightness,
    double magnitude,
  ) {
    final psfQuality = qualityConfig.starPsfQuality;

    if (psfQuality <= 0.0) {
      // Performance mode: simple filled circle
      final paint = Paint()..color = color.withValues(alpha: brightness);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final brightnessFilter = brightness >= 0.999
        ? null
        : ColorFilter.mode(
            Color.fromRGBO(255, 255, 255, brightness),
            BlendMode.modulate,
          );
    final paint = Paint()..colorFilter = brightnessFilter;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Draw outer glow for very bright stars only (mag < 1.5 in balanced, < 2.5 in quality)
    final glowMagLimit = psfQuality >= 1.0 ? 2.5 : 1.5;
    if (magnitude < glowMagLimit) {
      if (psfQuality >= 0.5) {
        // Balanced/Quality: radial gradient glow
        final glowRadius = radius * (3 + (1 - magnitude / 2.5));
        paint.shader = _starPsfShaderCache.getShader(
          type: StarPsfShaderType.glow,
          radius: glowRadius,
          color: color,
        );
        canvas.drawCircle(Offset.zero, glowRadius, paint);
      }

      // Draw diffraction spikes for very bright stars
      if (magnitude < 1.0 && psfQuality >= 1.0) {
        _drawDiffractionSpikes(canvas, Offset.zero, radius, color, brightness,
            magnitude: magnitude);
        // Add faint 45-degree secondary spikes for mag < 0
        if (magnitude < 0) {
          _drawSecondarySpikes(
            canvas,
            Offset.zero,
            radius * 0.6,
            color,
            brightness * 0.4,
            magnitude: magnitude,
          );
        }
      }
    }

    if (psfQuality >= 1.0) {
      // Quality mode: 3-ring Airy disk approximation
      // Outer ring (faint)
      final outerRadius = radius * 2.5;
      paint.shader = _starPsfShaderCache.getShader(
        type: StarPsfShaderType.outerRing,
        radius: outerRadius,
        color: color,
      );
      canvas.drawCircle(Offset.zero, outerRadius, paint);

      // Middle ring
      final midRadius = radius * 1.5;
      paint.shader = _starPsfShaderCache.getShader(
        type: StarPsfShaderType.midRing,
        radius: midRadius,
        color: color,
      );
      canvas.drawCircle(Offset.zero, midRadius, paint);

      // Core (bright center)
      paint.shader = _starPsfShaderCache.getShader(
        type: StarPsfShaderType.core,
        radius: radius,
        color: color,
      );
      canvas.drawCircle(Offset.zero, radius, paint);
    } else {
      // Balanced mode: 2-ring radial gradient
      paint.shader = _starPsfShaderCache.getShader(
        type: StarPsfShaderType.balanced,
        radius: radius * 1.5,
        color: color,
      );
      canvas.drawCircle(Offset.zero, radius * 1.5, paint);
    }

    canvas.restore();
  }

  /// Draw secondary 45-degree diffraction spikes for very bright stars.
  /// Uses cached gradient shaders to avoid per-frame shader creation.
  void _drawSecondarySpikes(Canvas canvas, Offset center, double starRadius,
      Color color, double brightness, {double magnitude = -1.0}) {
    final spikeLength = starRadius * 5;
    final paint = Paint()
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Draw 4 spikes at 45-degree angles with cached shaders
    for (final angle in [45.0, 135.0, 225.0, 315.0]) {
      final rad = angle * _deg2rad;
      final endX = center.dx + math.cos(rad) * spikeLength;
      final endY = center.dy + math.sin(rad) * spikeLength;

      paint.shader = _starPsfShaderCache.getSpikeShader(
        center: center,
        end: Offset(endX, endY),
        color: color,
        brightness: brightness * 0.4,
        magnitude: magnitude,
        angle: angle,
      );

      canvas.drawLine(center, Offset(endX, endY), paint);
    }
  }

  /// Draw 4-pointed diffraction spikes for very bright stars.
  /// Uses cached gradient shaders keyed by magnitude bucket + direction
  /// to avoid recreating 4-8 shaders per bright star per frame.
  void _drawDiffractionSpikes(Canvas canvas, Offset center, double starRadius,
      Color color, double brightness, {double magnitude = 0.0}) {
    final spikeLength = starRadius * 5;
    final paint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw 4 spikes (horizontal and vertical) with cached shaders
    for (final angle in [0.0, 90.0, 180.0, 270.0]) {
      final rad = angle * _deg2rad;
      final endX = center.dx + math.cos(rad) * spikeLength;
      final endY = center.dy + math.sin(rad) * spikeLength;

      paint.shader = _starPsfShaderCache.getSpikeShader(
        center: center,
        end: Offset(endX, endY),
        color: color,
        brightness: brightness * 0.4,
        magnitude: magnitude,
        angle: angle,
      );

      canvas.drawLine(center, Offset(endX, endY), paint);
    }
  }

  /// Calculate surface brightness for a DSO.
  /// SB = mag + 2.5 * log10(area_arcsec2)
  double? _surfaceBrightness(DeepSkyObject dso) {
    final mag = dso.magnitude;
    final majorAxis = dso.sizeArcMin;
    if (mag == null || majorAxis == null || majorAxis <= 0) return null;
    final minorAxis = dso.minorAxisArcMin ?? majorAxis;
    final areaArcmin2 = math.pi * (majorAxis / 2) * (minorAxis / 2);
    final areaArcsec2 = areaArcmin2 * 3600;
    if (areaArcsec2 <= 0) return null;
    return mag + 2.5 * (math.log(areaArcsec2) / math.ln10);
  }

  /// Map surface brightness to opacity multiplier.
  double _surfaceBrightnessOpacity(double? sb) {
    if (sb == null) return 0.7;
    if (sb <= 22.0) return 1.0;
    if (sb >= 26.5) return 0.15;
    return 1.0 - (sb - 22.0) / (26.5 - 22.0) * 0.85;
  }

  void _drawDSOs(Canvas canvas, Size size, Offset center, double scale) {
    // Respect quality config limits. DSO list is pre-filtered by the dynamic
    // magnitude provider (fovFilteredDsosProvider), so we use the quality
    // config's limit as a safeguard rather than the static SkyRenderConfig default.
    var dsosDrawn = 0;
    final maxDsos = qualityConfig.maxDsosToRender;
    final magLimit = qualityConfig.dsoMagnitudeLimit;

    // Calculate pop-in animation values
    // Phase goes from 0 to 1; use easeOutCubic for smooth deceleration
    final popinPhase = dsoPopinAnimationPhase ?? 1.0;
    final easedPhase =
        Curves.easeOutCubic.transform(popinPhase.clamp(0.0, 1.0));
    // Scale from 80% to 100%
    final popinScale = 0.8 + 0.2 * easedPhase;
    // Alpha from 0 to 1
    final popinAlpha = easedPhase;

    // Reusable paint for all DSO shapes (avoids per-DSO allocation)
    final shapePaint = Paint();

    // Unified rendering: every DSO gets a visible type-specific shape.
    // No "simplified" batched-points path — all DSOs are drawn as recognizable
    // shapes (ellipses, rounded rects, circles) with a single draw call each.
    // This is fast (one drawOval/drawCircle/drawRRect per DSO) AND visible.
    for (final dso in dsos) {
      if (dsosDrawn >= maxDsos) break;
      final dsoMag = dso.magnitude ?? 99.0;
      if (dsoMag > magLimit) continue;

      final offset = _celestialToScreen(dso.coordinates, center, scale);
      if (offset == null || !_isInView(offset, size)) continue;

      final dsoSize = (dso.sizeArcMin ?? 5) / 60 * scale;
      // Minimum 6px radius so every DSO is visible. Brighter = bigger.
      // Magnitude scaling: mag 0 -> 20px, mag 6 -> 14px, mag 10 -> 10px, mag 14 -> 6px
      final magSizeBonus = ((14.0 - dsoMag) / 14.0 * 14.0).clamp(0.0, 14.0);
      final displaySize = dsoSize.clamp(6.0 + magSizeBonus, 40.0);

      // Surface brightness opacity scaling
      final sb = _surfaceBrightness(dso);
      final sbOpacity = _surfaceBrightnessOpacity(sb);

      // Effective alpha (include pop-in if animating)
      final effectiveAlpha = (dsoPopinAnimationPhase != null && dsoPopinAnimationPhase! < 1.0)
          ? popinAlpha * sbOpacity
          : sbOpacity;

      // Apply pop-in scale animation if active
      final animating = dsoPopinAnimationPhase != null && dsoPopinAnimationPhase! < 1.0;
      if (animating) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.scale(popinScale);
        canvas.translate(-offset.dx, -offset.dy);
      }

      // Draw the DSO shape — simple filled shapes, no gradients, no blur.
      // One draw call per DSO. Color by type.
      _drawDsoSimpleShape(canvas, offset, displaySize, dso, effectiveAlpha, shapePaint);

      // Draw label. For bright DSOs (mag < 10), ALWAYS show the label so users
      // can find imaging targets. For fainter DSOs, show labels when zoomed in
      // enough that the object is > 10px on screen.
      if (config.showDSOLabels) {
        final showLabel = dsoMag < 10.0 || displaySize > 10.0;
        if (showLabel) {
          final labelText = _dsoLabelText(dso);
          final fontSize = _getLabelFontSize(dsoMag, 'dso');
          final fontWeight = _getLabelFontWeight(dsoMag);
          final labelAlpha = dsoMag < 10.0
              ? 0.85 * effectiveAlpha  // Bright DSOs get prominent labels
              : 0.6 * effectiveAlpha;  // Fainter DSOs get subtler labels
          final textStyle = TextStyle(
            color: _dsoTypeColor(dso.type).withValues(alpha: labelAlpha),
            fontSize: fontSize,
            fontWeight: fontWeight,
          );
          final textPainter = _TextCache.get(labelText, textStyle);

          // Find non-overlapping placement
          final preferredPos =
              offset + Offset(displaySize / 2 + 3, -textPainter.height / 2);
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

      if (animating) {
        canvas.restore();
      }

      // Draw observed marker if this DSO has been logged
      if (observedObjectIds.isNotEmpty && _isDsoObserved(dso)) {
        _drawObservedMarker(canvas, offset, displaySize);
      }

      // Draw listed marker if this DSO is in an observing list
      if (listedObjectIds.isNotEmpty && _isDsoListed(dso)) {
        _drawListedMarker(canvas, offset, displaySize);
      }

      dsosDrawn++;
    }
  }

  /// Build label text for a DSO. Uses common name for bright objects,
  /// otherwise catalog designation.
  /// Examples: "M31 - Andromeda Galaxy", "NGC 7000 - North America Nebula", "IC 1396"
  String _dsoLabelText(DeepSkyObject dso) {
    // Primary designation: prefer Messier, then NGC/IC, then raw name
    String designation;
    final messier = dso.messierNumber;
    if (messier != null) {
      designation = messier;
    } else {
      final ngcIc = dso.ngcIcDesignation;
      designation = ngcIc ?? dso.name;
    }

    // Append common name if available and different from designation
    if (dso.commonNames != null && dso.commonNames!.isNotEmpty) {
      final firstName = dso.commonNames!.split(',').first.trim();
      if (firstName.isNotEmpty && firstName != designation) {
        return '$designation - $firstName';
      }
    }

    return designation;
  }

  /// Draw a simple, efficient shape for a DSO based on its type.
  /// No gradients, no blur, no canvas.save/restore for rotation.
  /// Just solid-color filled shapes — one or two draw calls per DSO.
  void _drawDsoSimpleShape(Canvas canvas, Offset center, double displaySize,
      DeepSkyObject dso, double alpha, Paint paint) {
    final typeColor = _dsoTypeColor(dso.type);
    final radius = displaySize / 2;

    switch (dso.type) {
      // --- Galaxies: filled ellipse using axis ratio and position angle ---
      case DsoType.galaxy:
      case DsoType.galaxyPair:
      case DsoType.galaxyTriplet:
      case DsoType.galaxyGroup:
        final axisRatio = (dso.sizeArcMin != null &&
                dso.minorAxisArcMin != null &&
                dso.sizeArcMin! > 0)
            ? (dso.minorAxisArcMin! / dso.sizeArcMin!).clamp(0.2, 1.0)
            : 0.5; // Default to slightly elongated for galaxies
        final paRad = (dso.positionAngle ?? 0) * _deg2rad;

        // Filled ellipse body (50% alpha)
        paint
          ..color = typeColor.withValues(alpha: 0.5 * alpha)
          ..style = PaintingStyle.fill;

        if (paRad.abs() > 0.05) {
          // Rotated ellipse: use save/restore only when position angle is nonzero
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(-paRad);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero,
                width: displaySize,
                height: displaySize * axisRatio),
            paint,
          );
          // Bright core dot
          paint.color = Colors.white.withValues(alpha: 0.7 * alpha);
          canvas.drawCircle(Offset.zero, radius * 0.2, paint);
          canvas.restore();
        } else {
          // Axis-aligned ellipse: no save/restore needed
          canvas.drawOval(
            Rect.fromCenter(
                center: center,
                width: displaySize,
                height: displaySize * axisRatio),
            paint,
          );
          // Bright core dot
          paint.color = Colors.white.withValues(alpha: 0.7 * alpha);
          canvas.drawCircle(center, radius * 0.2, paint);
        }
        break;

      // --- Nebulae: filled rounded rectangle, colored reddish-pink ---
      case DsoType.nebula:
      case DsoType.emissionNebula:
      case DsoType.reflectionNebula:
      case DsoType.hiiRegion:
      case DsoType.clusterWithNebulosity:
      case DsoType.darkNebula:
        Color nebulaColor;
        if (dso.type == DsoType.emissionNebula || dso.type == DsoType.hiiRegion) {
          nebulaColor = const Color(0xFFFF1744); // Pink/red for emission
        } else if (dso.type == DsoType.reflectionNebula) {
          nebulaColor = const Color(0xFF448AFF); // Blue for reflection
        } else if (dso.type == DsoType.darkNebula) {
          nebulaColor = const Color(0xFF78909C); // Blue-grey for dark nebulae
        } else {
          nebulaColor = typeColor; // Default nebula pink
        }

        // Filled rounded rect
        paint
          ..color = nebulaColor.withValues(alpha: 0.5 * alpha)
          ..style = PaintingStyle.fill;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: displaySize * 1.2, height: displaySize),
          Radius.circular(radius * 0.3),
        );
        canvas.drawRRect(rrect, paint);
        break;

      // --- Planetary nebulae: double circle (ring + central dot), cyan/teal ---
      case DsoType.planetaryNebula:
        // Outer ring
        paint
          ..color = const Color(0xFF26A69A).withValues(alpha: 0.6 * alpha) // Teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, radius * 0.15);
        canvas.drawCircle(center, radius * 0.8, paint);

        // Inner ring (fainter)
        paint
          ..color = const Color(0xFF26A69A).withValues(alpha: 0.3 * alpha)
          ..strokeWidth = math.max(1.0, radius * 0.1);
        canvas.drawCircle(center, radius * 0.5, paint);

        // Central star dot
        paint
          ..color = Colors.white.withValues(alpha: 0.8 * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, math.max(1.5, radius * 0.12), paint);
        break;

      // --- Open clusters: circle with a few scattered dots inside, yellow ---
      case DsoType.openCluster:
      case DsoType.asterism:
      case DsoType.starCloud:
        // Boundary circle (dashed look via thin stroke)
        paint
          ..color = typeColor.withValues(alpha: 0.3 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(center, radius, paint);

        // Scatter a few star-like dots inside
        paint.style = PaintingStyle.fill;
        final rng = math.Random(center.dx.toInt() ^ center.dy.toInt());
        final dotCount = math.min(7, math.max(3, (radius / 2).round()));
        for (var i = 0; i < dotCount; i++) {
          final angle = rng.nextDouble() * 2 * math.pi;
          final dist = rng.nextDouble() * radius * 0.7;
          final dotCenter = Offset(
            center.dx + math.cos(angle) * dist,
            center.dy + math.sin(angle) * dist,
          );
          paint.color = Colors.white.withValues(
              alpha: (0.5 + rng.nextDouble() * 0.4) * alpha);
          canvas.drawCircle(dotCenter, math.max(1.0, radius * 0.08), paint);
        }
        break;

      // --- Globular clusters: filled circle with bright center, orange ---
      case DsoType.globularCluster:
        // Outer halo
        paint
          ..color = typeColor.withValues(alpha: 0.25 * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, radius, paint);

        // Dense core
        paint.color = typeColor.withValues(alpha: 0.5 * alpha);
        canvas.drawCircle(center, radius * 0.5, paint);

        // Bright center
        paint.color = Colors.white.withValues(alpha: 0.7 * alpha);
        canvas.drawCircle(center, radius * 0.15, paint);

        // Cross-hair to distinguish from open cluster
        paint
          ..color = typeColor.withValues(alpha: 0.4 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawLine(
          Offset(center.dx - radius, center.dy),
          Offset(center.dx + radius, center.dy),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx, center.dy - radius),
          Offset(center.dx, center.dy + radius),
          paint,
        );
        break;

      // --- Supernova remnants: small starburst, red ---
      case DsoType.supernova:
      case DsoType.nova:
        // Bright core
        paint
          ..color = Colors.white.withValues(alpha: 0.9 * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, radius * 0.25, paint);

        // 4 spikes
        paint
          ..color = typeColor.withValues(alpha: 0.7 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (var angle = 0.0; angle < math.pi * 2; angle += math.pi / 2) {
          final dx = math.cos(angle) * radius * 0.8;
          final dy = math.sin(angle) * radius * 0.8;
          canvas.drawLine(center, Offset(center.dx + dx, center.dy + dy), paint);
        }
        break;

      // --- Fallback: simple filled circle ---
      default:
        paint
          ..color = typeColor.withValues(alpha: 0.5 * alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, radius, paint);
        break;
    }
  }

  /// Check if a DSO matches any listed catalog ID or object name.
  bool _isDsoListed(DeepSkyObject dso) {
    if (listedObjectIds.contains(dso.id)) return true;
    if (listedObjectIds.contains(dso.name)) return true;
    if (dso.isMessier) {
      final messier = dso.messierNumber;
      if (messier != null && listedObjectIds.contains(messier)) return true;
    }
    final ngcIc = dso.ngcIcDesignation;
    if (ngcIc != null && listedObjectIds.contains(ngcIc)) return true;
    return false;
  }

  /// Draw a small amber bookmark marker at the top-right of a DSO.
  void _drawListedMarker(Canvas canvas, Offset dsoCenter, double dsoSize) {
    final markerSize = math.max(4.0, dsoSize * 0.3);
    final markerPos = dsoCenter + Offset(dsoSize / 2 + markerSize * 0.5, -dsoSize / 2 - markerSize * 0.5);

    final fillPaint = Paint()
      ..color = const Color(0xFFFFA726).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Draw a small bookmark shape
    final bookmarkPath = Path()
      ..moveTo(markerPos.dx - markerSize * 0.4, markerPos.dy - markerSize * 0.5)
      ..lineTo(markerPos.dx + markerSize * 0.4, markerPos.dy - markerSize * 0.5)
      ..lineTo(markerPos.dx + markerSize * 0.4, markerPos.dy + markerSize * 0.4)
      ..lineTo(markerPos.dx, markerPos.dy + markerSize * 0.15)
      ..lineTo(markerPos.dx - markerSize * 0.4, markerPos.dy + markerSize * 0.4)
      ..close();

    canvas.drawPath(bookmarkPath, fillPaint);
    canvas.drawPath(bookmarkPath, borderPaint);
  }

  /// Check if a DSO matches any observed catalog ID or object name.
  bool _isDsoObserved(DeepSkyObject dso) {
    if (observedObjectIds.contains(dso.id)) return true;
    if (observedObjectIds.contains(dso.name)) return true;
    if (dso.isMessier) {
      final messier = dso.messierNumber;
      if (messier != null && observedObjectIds.contains(messier)) return true;
    }
    final ngcIc = dso.ngcIcDesignation;
    if (ngcIc != null && observedObjectIds.contains(ngcIc)) return true;
    return false;
  }

  /// Draw a small green "observed" indicator at the bottom-right of a DSO.
  void _drawObservedMarker(Canvas canvas, Offset dsoCenter, double dsoSize) {
    final markerRadius = math.max(3.0, dsoSize * 0.25);
    final markerPos = dsoCenter + Offset(dsoSize / 2 + markerRadius, dsoSize / 2);

    final fillPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(markerPos, markerRadius, fillPaint);
    canvas.drawCircle(markerPos, markerRadius, borderPaint);

    if (markerRadius >= 3.5) {
      final checkPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final checkPath = Path()
        ..moveTo(markerPos.dx - markerRadius * 0.35, markerPos.dy)
        ..lineTo(markerPos.dx - markerRadius * 0.05, markerPos.dy + markerRadius * 0.3)
        ..lineTo(markerPos.dx + markerRadius * 0.35, markerPos.dy - markerRadius * 0.3);
      canvas.drawPath(checkPath, checkPaint);
    }
  }

  /// Draw visual density indicators for crowded regions when zoomed out.
  /// Shows subtle glowing circles with count labels to indicate "zoom in to reveal more".
  void _drawDensityIndicators(
      Canvas canvas, Size size, Offset center, double scale) {
    for (final hotspot in densityHotspots) {
      final (ra, dec, visibleCount, hiddenCount) = hotspot;
      final coord = CelestialCoordinate(ra: ra, dec: dec);
      final offset = _celestialToScreen(coord, center, scale);

      if (offset == null || !_isInView(offset, size)) continue;

      // Calculate indicator size based on hidden count
      // More hidden objects = larger indicator
      final indicatorRadius = 15.0 + (hiddenCount / 100).clamp(0.0, 15.0);

      // Draw subtle blue glow
      const indicatorColor = Color(0xFF64B5F6); // Light blue

      // Outer glow - use cached blur paint
      if (qualityConfig.useBlurEffects) {
        final glowPaint = _PaintCache.getBlurPaint(
            indicatorRadius * 0.8, indicatorColor,
            alpha: 0.15);
        canvas.drawCircle(offset, indicatorRadius * 1.5, glowPaint);
      }

      // Inner glow ring
      final ringPaint = Paint()
        ..color = indicatorColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      if (qualityConfig.useBlurEffects) {
        ringPaint.maskFilter = _PaintCache.getBlurFilter(3);
      }
      canvas.drawCircle(offset, indicatorRadius, ringPaint);

      // Draw count label for regions with many hidden objects
      if (hiddenCount > 50) {
        final textStyle = TextStyle(
          color: indicatorColor.withValues(alpha: 0.8),
          fontSize: 9,
          fontWeight: FontWeight.w500,
        );
        // Use cached TextPainter
        final textPainter = _TextCache.get('+$hiddenCount', textStyle);

        // Draw small background for readability - use cached paint
        final bgRect = Rect.fromCenter(
          center: offset + Offset(0, indicatorRadius + 10),
          width: textPainter.width + 6,
          height: textPainter.height + 2,
        );
        final bgPaint = _PaintCache.getFillPaint(const Color(0xAA000000));
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
          bgPaint,
        );

        textPainter.paint(
          canvas,
          offset +
              Offset(-textPainter.width / 2,
                  indicatorRadius + 10 - textPainter.height / 2),
        );
      }
    }
  }

  /// Draw DSO symbol with custom alpha for pop-in animation
  void _drawDSOSymbolWithAlpha(
      Canvas canvas, Offset center, double size, DsoType type, double alpha,
      {DeepSkyObject? dso}) {
    final baseColor = _dsoTypeColor(type);
    final adjustedColor = baseColor.withValues(alpha: baseColor.a * alpha);

    switch (type) {
      case DsoType.galaxy:
      case DsoType.galaxyPair:
      case DsoType.galaxyTriplet:
        _drawGalaxyWithAlpha(canvas, center, size, adjustedColor, alpha,
            dso: dso);
        break;

      case DsoType.nebula:
      case DsoType.emissionNebula:
      case DsoType.reflectionNebula:
      case DsoType.hiiRegion:
        // Apply elongation for nebulae with axis ratio < 0.8
        if (dso != null &&
            dso.sizeArcMin != null &&
            dso.minorAxisArcMin != null &&
            dso.sizeArcMin! > 0) {
          final nebulaRatio =
              (dso.minorAxisArcMin! / dso.sizeArcMin!).clamp(0.3, 1.0);
          if (nebulaRatio < 0.8) {
            final paRad = (dso.positionAngle ?? 0) * _deg2rad;
            canvas.save();
            canvas.translate(center.dx, center.dy);
            canvas.rotate(-paRad);
            canvas.scale(1.0, nebulaRatio);
            _drawNebulaWithAlpha(canvas, Offset.zero,
                size / math.sqrt(nebulaRatio), adjustedColor, type, alpha);
            canvas.restore();
            break;
          }
        }
        _drawNebulaWithAlpha(canvas, center, size, adjustedColor, type, alpha);
        break;

      case DsoType.planetaryNebula:
        _drawPlanetaryNebulaWithAlpha(
            canvas, center, size, adjustedColor, alpha);
        break;

      case DsoType.openCluster:
        _drawOpenClusterWithAlpha(canvas, center, size, adjustedColor, alpha);
        break;

      case DsoType.globularCluster:
        _drawGlobularClusterWithAlpha(
            canvas, center, size, adjustedColor, alpha);
        break;

      case DsoType.supernova:
        _drawSupernovaWithAlpha(canvas, center, size, adjustedColor, alpha);
        break;

      default:
        // Fallback to simple circle
        final paint = Paint()
          ..color = adjustedColor.withValues(alpha: 0.6 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, size / 2, paint);
    }
  }

  void _drawGalaxyWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha,
      {DeepSkyObject? dso}) {
    // Calculate axis ratio and position angle for elongated rendering
    final majorAxis = dso?.sizeArcMin;
    final minorAxis = dso?.minorAxisArcMin;
    final posAngleDeg = dso?.positionAngle;

    final axisRatio = (majorAxis != null && minorAxis != null && majorAxis > 0)
        ? (minorAxis / majorAxis).clamp(0.2, 1.0)
        : 0.6;

    final paRad = (posAngleDeg ?? 0) * _deg2rad;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-paRad);

    final localCenter = Offset.zero;

    // Outer glow - elongated
    _drawOvalGlow(canvas, localCenter, size * 2.5, size * 2.5 * axisRatio,
        color, 8.0,
        opacity: 0.15 * alpha);

    // Middle layer
    _drawOvalGlow(canvas, localCenter, size * 1.8, size * 1.8 * axisRatio,
        color, 4.0,
        opacity: 0.4 * alpha);

    // Spiral arm hints for larger galaxies in quality mode
    if (qualityConfig.enableEnhancedDsoSymbols && size > 10) {
      _drawSpiralArmsWithAlpha(canvas, localCenter, size, color, alpha);
    }

    // Bright core
    final coreRatio = axisRatio < 0.4 ? axisRatio * 1.5 : axisRatio;
    _drawOvalGlow(canvas, localCenter, size * 0.8, size * 0.8 * coreRatio,
        color, 2.0,
        opacity: 0.8 * alpha);

    // Central bright spot
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 * alpha);
    canvas.drawCircle(localCenter, size * 0.15, centerPaint);

    canvas.restore();
  }

  void _drawSpiralArmsWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha) {
    final armPaint = Paint()
      ..color = color.withValues(alpha: 0.15 * alpha)
      ..strokeWidth = size * 0.06
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (qualityConfig.useBlurEffects) {
      armPaint.maskFilter = _PaintCache.getBlurFilter(3);
    }

    for (final startAngle in [0.0, math.pi]) {
      final path = Path();
      var firstPoint = true;

      for (var t = 0.0; t <= 1.8; t += 0.08) {
        final r = size * 0.15 * math.exp(0.5 * t);
        final angle = startAngle + t * 2.5;
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle) * 0.5;

        if (firstPoint) {
          path.moveTo(x, y);
          firstPoint = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, armPaint);
    }
  }

  void _drawNebulaWithAlpha(Canvas canvas, Offset center, double size,
      Color color, DsoType type, double alpha) {
    final random = math.Random(center.dx.toInt() + center.dy.toInt());

    Color nebulaColor = color;
    if (type == DsoType.emissionNebula || type == DsoType.hiiRegion) {
      nebulaColor = Color.fromRGBO(255, 23, 68, alpha); // Pink/red for emission
    } else if (type == DsoType.reflectionNebula) {
      nebulaColor = Color.fromRGBO(68, 138, 255, alpha); // Blue for reflection
    }

    // Reuse a single Paint for all puffs
    final paint = Paint();

    // Draw multiple overlapping circles for wispy effect
    for (var i = 0; i < 5; i++) {
      final offsetX = (random.nextDouble() - 0.5) * size * 0.5;
      final offsetY = (random.nextDouble() - 0.5) * size * 0.5;
      final circleSize = size * (0.4 + random.nextDouble() * 0.4);

      paint.color = nebulaColor.withValues(
          alpha: (0.15 + random.nextDouble() * 0.1) * alpha);

      if (qualityConfig.useBlurEffects) {
        paint.maskFilter = _PaintCache.getBlurFilter(circleSize * 0.4);
      }

      canvas.drawCircle(
        Offset(center.dx + offsetX, center.dy + offsetY),
        circleSize,
        paint,
      );
    }
  }

  void _drawPlanetaryNebulaWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha) {
    // Outer ring
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.5 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.15;

    if (qualityConfig.useBlurEffects) {
      ringPaint.maskFilter = _PaintCache.getBlurFilter(size * 0.1);
    }

    canvas.drawCircle(center, size * 0.4, ringPaint);

    // Central star
    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 * alpha);
    canvas.drawCircle(center, size * 0.1, starPaint);
  }

  void _drawOpenClusterWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha) {
    final random = math.Random(center.dx.toInt() + center.dy.toInt());

    // Reuse a single paint for all stars
    final paint = Paint();

    // Draw scattered small stars
    for (var i = 0; i < 8; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final dist = random.nextDouble() * size * 0.4;
      final starSize = 1.0 + random.nextDouble() * 1.5;

      final starCenter = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );

      paint.color = Colors.white
          .withValues(alpha: (0.6 + random.nextDouble() * 0.4) * alpha);
      canvas.drawCircle(starCenter, starSize, paint);
    }

    // Faint boundary circle
    paint
      ..color = color.withValues(alpha: 0.2 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, size * 0.5, paint);
  }

  void _drawGlobularClusterWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha) {
    // Dense core glow - use cached blur
    if (qualityConfig.useBlurEffects) {
      final corePaint =
          _PaintCache.getBlurPaint(size * 0.3, color, alpha: 0.6 * alpha);
      canvas.drawCircle(center, size * 0.3, corePaint);
    } else {
      final corePaint = Paint()..color = color.withValues(alpha: 0.6 * alpha);
      canvas.drawCircle(center, size * 0.3, corePaint);
    }

    // Outer halo - use cached blur
    if (qualityConfig.useBlurEffects) {
      final haloPaint =
          _PaintCache.getBlurPaint(size * 0.5, color, alpha: 0.2 * alpha);
      canvas.drawCircle(center, size * 0.5, haloPaint);
    } else {
      final haloPaint = Paint()..color = color.withValues(alpha: 0.2 * alpha);
      canvas.drawCircle(center, size * 0.5, haloPaint);
    }

    // Bright center point
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * alpha);
    canvas.drawCircle(center, size * 0.1, centerPaint);
  }

  void _drawSupernovaWithAlpha(
      Canvas canvas, Offset center, double size, Color color, double alpha) {
    // Bright central point
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * alpha);
    canvas.drawCircle(center, size * 0.2, centerPaint);

    // Diffraction spikes
    final spikePaint = Paint()
      ..color = color.withValues(alpha: 0.7 * alpha)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var angle = 0.0; angle < math.pi * 2; angle += math.pi / 2) {
      final dx = math.cos(angle) * size * 0.6;
      final dy = math.sin(angle) * size * 0.6;
      canvas.drawLine(
        Offset(center.dx - dx * 0.3, center.dy - dy * 0.3),
        Offset(center.dx + dx, center.dy + dy),
        spikePaint,
      );
    }

    // Glow - use cached blur
    if (qualityConfig.useBlurEffects) {
      final glowPaint =
          _PaintCache.getBlurPaint(size * 0.4, color, alpha: 0.3 * alpha);
      canvas.drawCircle(center, size * 0.4, glowPaint);
    } else {
      final glowPaint = Paint()..color = color.withValues(alpha: 0.3 * alpha);
      canvas.drawCircle(center, size * 0.4, glowPaint);
    }
  }

  void _drawDSOSymbol(Canvas canvas, Offset center, double size, DsoType type,
      {double sbOpacity = 1.0, DeepSkyObject? dso}) {
    final baseColor = _dsoTypeColor(type)
        .withValues(alpha: _dsoTypeColor(type).a * sbOpacity);

    switch (type) {
      case DsoType.galaxy:
      case DsoType.galaxyPair:
      case DsoType.galaxyTriplet:
        _drawGalaxy(canvas, center, size, baseColor, dso: dso);
        break;

      case DsoType.nebula:
      case DsoType.emissionNebula:
      case DsoType.reflectionNebula:
      case DsoType.hiiRegion:
        // Apply elongation for nebulae with axis ratio < 0.8
        if (dso != null &&
            dso.sizeArcMin != null &&
            dso.minorAxisArcMin != null &&
            dso.sizeArcMin! > 0) {
          final nebulaRatio =
              (dso.minorAxisArcMin! / dso.sizeArcMin!).clamp(0.3, 1.0);
          if (nebulaRatio < 0.8) {
            final paRad = (dso.positionAngle ?? 0) * _deg2rad;
            canvas.save();
            canvas.translate(center.dx, center.dy);
            canvas.rotate(-paRad);
            canvas.scale(1.0, nebulaRatio);
            _drawNebula(canvas, Offset.zero,
                size / math.sqrt(nebulaRatio), baseColor, type);
            canvas.restore();
            break;
          }
        }
        _drawNebula(canvas, center, size, baseColor, type);
        break;

      case DsoType.planetaryNebula:
        _drawPlanetaryNebula(canvas, center, size, baseColor);
        break;

      case DsoType.openCluster:
        _drawOpenCluster(canvas, center, size, baseColor);
        break;

      case DsoType.globularCluster:
        _drawGlobularCluster(canvas, center, size, baseColor);
        break;

      case DsoType.supernova:
        _drawSupernova(canvas, center, size, baseColor);
        break;

      default:
        // Fallback to simple circle
        final paint = Paint()
          ..color = baseColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, size / 2, paint);
    }
  }

  void _drawGalaxy(Canvas canvas, Offset center, double size, Color color,
      {DeepSkyObject? dso}) {
    // Calculate axis ratio and position angle for elongated rendering
    final majorAxis = dso?.sizeArcMin;
    final minorAxis = dso?.minorAxisArcMin;
    final posAngleDeg = dso?.positionAngle;

    // Axis ratio: 1.0 = circular, < 1.0 = elongated
    final axisRatio = (majorAxis != null && minorAxis != null && majorAxis > 0)
        ? (minorAxis / majorAxis).clamp(0.2, 1.0)
        : 0.6; // Default elliptical ratio for galaxies

    // Position angle in radians (measured N through E)
    final paRad = (posAngleDeg ?? 0) * _deg2rad;

    // Apply rotation for position angle
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-paRad); // Negative because canvas Y is flipped

    final localCenter = Offset.zero;

    // Outer glow - elongated ellipse
    _drawOvalGlow(canvas, localCenter, size * 2.5, size * 2.5 * axisRatio,
        color, 8.0,
        opacity: 0.15);

    // Middle layer
    _drawOvalGlow(canvas, localCenter, size * 1.8, size * 1.8 * axisRatio,
        color, 4.0,
        opacity: 0.4);

    // Spiral arm hints for larger galaxies in quality mode
    if (qualityConfig.enableEnhancedDsoSymbols && size > 10) {
      _drawSpiralArms(canvas, localCenter, size, color);
    }

    // Bright core - more elongated core for edge-on galaxies
    final coreRatio = axisRatio < 0.4 ? axisRatio * 1.5 : axisRatio;
    _drawOvalGlow(canvas, localCenter, size * 0.8, size * 0.8 * coreRatio,
        color, 2.0,
        opacity: 0.8);

    // Central bright spot
    final centerPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(localCenter, size * 0.15, centerPaint);

    canvas.restore();
  }

  /// Draw subtle spiral arm hints for galaxies
  void _drawSpiralArms(Canvas canvas, Offset center, double size, Color color) {
    final armPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = size * 0.06
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Apply cached blur if available
    if (qualityConfig.useBlurEffects) {
      armPaint.maskFilter = _PaintCache.getBlurFilter(3);
    }

    // Draw 2 logarithmic spiral arms
    for (final startAngle in [0.0, math.pi]) {
      final path = Path();
      var firstPoint = true;

      for (var t = 0.0; t <= 1.8; t += 0.08) {
        // Logarithmic spiral: r = a * e^(b*theta)
        final r = size * 0.15 * math.exp(0.5 * t);
        final angle = startAngle + t * 2.5;
        final x = center.dx + r * math.cos(angle);
        final y =
            center.dy + r * math.sin(angle) * 0.5; // Squash for inclination

        if (firstPoint) {
          path.moveTo(x, y);
          firstPoint = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, armPaint);
    }
  }

  void _drawNebula(
      Canvas canvas, Offset center, double size, Color color, DsoType type) {
    // Create wispy cloud effect with multiple overlapping circles
    final random = math.Random(center.dx.toInt() + center.dy.toInt());

    // Adjust color based on nebula type
    Color nebulaColor = color;
    if (type == DsoType.emissionNebula || type == DsoType.hiiRegion) {
      nebulaColor = const Color(0xFFFF1744); // Pink/red for emission
    } else if (type == DsoType.reflectionNebula) {
      nebulaColor = const Color(0xFF448AFF); // Blue for reflection
    }

    final enhanced = qualityConfig.enableEnhancedDsoSymbols && size > 6;
    final puffCount = enhanced ? 12 : 8;

    // Reuse a single Paint for all puffs to avoid per-puff allocation
    final puffPaint = Paint();
    final useBlur = qualityConfig.useBlurEffects;
    if (useBlur) {
      puffPaint.maskFilter = _PaintCache.getBlurFilter(6);
    }

    // Draw multiple cloud puffs
    for (var i = 0; i < puffCount; i++) {
      final angle = (i / puffCount) * 2 * math.pi + random.nextDouble() * 0.5;
      final distance = size * (0.3 + random.nextDouble() * 0.4);
      final puffCenter = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      // Varying puff sizes for more organic look
      final puffSize = size * (0.3 + random.nextDouble() * 0.4);

      puffPaint.color =
          nebulaColor.withValues(alpha: 0.15 + random.nextDouble() * 0.15);
      canvas.drawCircle(puffCenter, puffSize, puffPaint);
    }

    // Enhanced mode: add wispy tendrils using bezier curves
    if (enhanced) {
      _drawNebulaTendrils(canvas, center, size, nebulaColor, random);
    }

    // Central brighter region -- reuse puffPaint
    puffPaint.color = nebulaColor.withValues(alpha: 0.4);
    if (useBlur) {
      puffPaint.maskFilter = _PaintCache.getBlurFilter(4);
    }
    canvas.drawCircle(center, size * 0.5, puffPaint);

    // Bright embedded stars for larger nebulae
    if (enhanced && size > 12) {
      puffPaint.maskFilter = null; // No blur for point stars
      for (var i = 0; i < 3; i++) {
        final starAngle = random.nextDouble() * 2 * math.pi;
        final starDist = size * 0.3 * random.nextDouble();
        final starPos = Offset(
          center.dx + math.cos(starAngle) * starDist,
          center.dy + math.sin(starAngle) * starDist,
        );
        puffPaint.color =
            Colors.white.withValues(alpha: 0.7 + random.nextDouble() * 0.3);
        canvas.drawCircle(starPos, 1.0 + random.nextDouble(), puffPaint);
      }
    }
  }

  /// Draw wispy tendrils extending from nebula using bezier curves
  void _drawNebulaTendrils(Canvas canvas, Offset center, double size,
      Color color, math.Random random) {
    final tendrilPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = size * 0.08
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (qualityConfig.useBlurEffects) {
      tendrilPaint.maskFilter = _PaintCache.getBlurFilter(4);
    }

    // Draw 4-6 wispy tendrils
    final tendrilCount = 4 + random.nextInt(3);
    for (var i = 0; i < tendrilCount; i++) {
      final baseAngle =
          (i / tendrilCount) * 2 * math.pi + random.nextDouble() * 0.3;

      final path = Path();
      path.moveTo(
        center.dx + math.cos(baseAngle) * size * 0.3,
        center.dy + math.sin(baseAngle) * size * 0.3,
      );

      // Control points for bezier curve
      final cp1Distance = size * (0.5 + random.nextDouble() * 0.3);
      final cp1Angle = baseAngle + (random.nextDouble() - 0.5) * 0.8;
      final cp1 = Offset(
        center.dx + math.cos(cp1Angle) * cp1Distance,
        center.dy + math.sin(cp1Angle) * cp1Distance,
      );

      final endDistance = size * (0.8 + random.nextDouble() * 0.4);
      final endAngle = baseAngle + (random.nextDouble() - 0.5) * 0.5;
      final endPoint = Offset(
        center.dx + math.cos(endAngle) * endDistance,
        center.dy + math.sin(endAngle) * endDistance,
      );

      path.quadraticBezierTo(cp1.dx, cp1.dy, endPoint.dx, endPoint.dy);
      canvas.drawPath(path, tendrilPaint);
    }
  }

  void _drawPlanetaryNebula(
      Canvas canvas, Offset center, double size, Color color) {
    // Green ring (OIII emission)
    const ringColor = Color(0xFF00E676);
    final enhanced = qualityConfig.enableEnhancedDsoSymbols && size > 8;

    // Outer glow/shell - use cached blur
    final outerGlowPaint = Paint()..color = ringColor.withValues(alpha: 0.2);
    if (qualityConfig.useBlurEffects) {
      outerGlowPaint.maskFilter = _PaintCache.getBlurFilter(8);
    }
    canvas.drawCircle(center, size * 0.9, outerGlowPaint);

    // Enhanced mode: bipolar lobes for larger planetary nebulae
    if (enhanced) {
      _drawBipolarLobes(canvas, center, size, ringColor);
    }

    // Outer ring - use cached blur
    final outerRingPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (qualityConfig.useBlurEffects) {
      outerRingPaint.maskFilter = _PaintCache.getBlurFilter(3);
    }
    canvas.drawCircle(center, size * 0.7, outerRingPaint);

    // Inner ring (main structure) - use cached blur
    final innerRingPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (qualityConfig.useBlurEffects) {
      innerRingPaint.maskFilter = _PaintCache.getBlurFilter(2);
    }
    canvas.drawCircle(center, size * 0.45, innerRingPaint);

    // Enhanced: inner shell fill - use cached blur
    if (enhanced) {
      final innerFillPaint = Paint()..color = ringColor.withValues(alpha: 0.15);
      if (qualityConfig.useBlurEffects) {
        innerFillPaint.maskFilter = _PaintCache.getBlurFilter(2);
      }
      canvas.drawCircle(center, size * 0.4, innerFillPaint);
    }

    // Central star with diffraction pattern for quality mode
    if (qualityConfig.starPsfQuality >= 1.0 && size > 10) {
      // Draw small diffraction spikes for central star
      _drawDiffractionSpikes(canvas, center, 2.0, Colors.white, 0.8);
    }

    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    if (qualityConfig.useBlurEffects) {
      starPaint.maskFilter = _PaintCache.getBlurFilter(1);
    }
    canvas.drawCircle(center, 2, starPaint);
  }

  /// Draw bipolar lobes for planetary nebulae
  void _drawBipolarLobes(
      Canvas canvas, Offset center, double size, Color color) {
    final lobePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    if (qualityConfig.useBlurEffects) {
      lobePaint.maskFilter = _PaintCache.getBlurFilter(4);
    }

    // Draw two elongated lobes (top and bottom)
    final lobeWidth = size * 0.4;
    final lobeHeight = size * 0.8;

    // Top lobe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - size * 0.35),
        width: lobeWidth,
        height: lobeHeight,
      ),
      lobePaint,
    );

    // Bottom lobe
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + size * 0.35),
        width: lobeWidth,
        height: lobeHeight,
      ),
      lobePaint,
    );
  }

  void _drawOpenCluster(
      Canvas canvas, Offset center, double size, Color color) {
    // Draw scattered star points
    final random = math.Random(center.dx.toInt() + center.dy.toInt());
    final starCount = (size / 2).clamp(5, 15).toInt();

    // Reuse paints across all stars to avoid per-star allocation
    final glowPaint = qualityConfig.useBlurEffects
        ? _PaintCache.getBlurPaint(2, color, alpha: 0.4)
        : (Paint()..color = color.withValues(alpha: 0.4));
    final starPaint = Paint()..color = color.withValues(alpha: 0.9);

    for (var i = 0; i < starCount; i++) {
      final angle = random.nextDouble() * 2 * math.pi;
      final distance = random.nextDouble() * size * 0.6;
      final starPos = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );

      final starSize = 1.0 + random.nextDouble() * 1.5;
      canvas.drawCircle(starPos, starSize * 2, glowPaint);
      canvas.drawCircle(starPos, starSize, starPaint);
    }
  }

  void _drawGlobularCluster(
      Canvas canvas, Offset center, double size, Color color) {
    // Dense core with radial falloff
    final random = math.Random(center.dx.toInt() + center.dy.toInt());

    // Outer halo
    _drawGlow(canvas, center, size, color, 8.0, opacity: 0.15);

    // Middle region
    _drawGlow(canvas, center, size * 0.6, color, 4.0, opacity: 0.4);

    // Dense core
    _drawGlow(canvas, center, size * 0.3, color, 2.0, opacity: 0.7);

    // Add some individual star sparkles (always drawn)
    final sparklePaint = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * math.pi;
      final distance = size * (0.2 + random.nextDouble() * 0.3);
      final starPos = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      canvas.drawCircle(starPos, 0.8, sparklePaint);
    }
  }

  void _drawSupernova(Canvas canvas, Offset center, double size, Color color) {
    // Bright starburst with glow
    const brightColor = Color(0xFFFFFFFF);

    // Outer glow - use cached blur
    if (qualityConfig.useBlurEffects) {
      final glowPaint = _PaintCache.getBlurPaint(8, color, alpha: 0.3);
      canvas.drawCircle(center, size * 1.5, glowPaint);
    } else {
      final glowPaint = Paint()..color = color.withValues(alpha: 0.3);
      canvas.drawCircle(center, size * 1.5, glowPaint);
    }

    // Inner glow - use cached blur
    if (qualityConfig.useBlurEffects) {
      final innerGlowPaint =
          _PaintCache.getBlurPaint(4, brightColor, alpha: 0.5);
      canvas.drawCircle(center, size * 0.8, innerGlowPaint);
    } else {
      final innerGlowPaint = Paint()
        ..color = brightColor.withValues(alpha: 0.5);
      canvas.drawCircle(center, size * 0.8, innerGlowPaint);
    }

    // Rays - use cached blur filter
    final rayPaint = Paint()
      ..color = brightColor.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    if (qualityConfig.useBlurEffects) {
      rayPaint.maskFilter = _PaintCache.getBlurFilter(2);
    }

    for (var i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * math.pi;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle) * size, math.sin(angle) * size),
        rayPaint,
      );
    }

    // Central bright core
    final corePaint = Paint()..color = brightColor;
    canvas.drawCircle(center, 3, corePaint);
  }

  Color _dsoTypeColor(DsoType type) {
    switch (type) {
      case DsoType.galaxy:
        return const Color(0xFF64B5F6); // Blue
      case DsoType.nebula:
        return const Color(0xFFE91E63); // Pink
      case DsoType.planetaryNebula:
        return const Color(0xFF4CAF50); // Green
      case DsoType.openCluster:
        return const Color(0xFFFFEB3B); // Yellow
      case DsoType.globularCluster:
        return const Color(0xFFFF9800); // Orange
      case DsoType.supernova:
        return const Color(0xFFF44336); // Red
      default:
        return const Color(0xFFFFFFFF); // White
    }
  }

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
      Canvas canvas, Offset center, double scale, CelestialCoordinate coord) {
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
        final glowPaint =
            _PaintCache.getBlurPaint(12, baseColor, alpha: glowOpacity);
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
        offset - const Offset(30, 0), offset - const Offset(18, 0), paint);
    canvas.drawLine(
        offset + const Offset(18, 0), offset + const Offset(30, 0), paint);
    canvas.drawLine(
        offset - const Offset(0, 30), offset - const Offset(0, 18), paint);
    canvas.drawLine(
        offset + const Offset(0, 18), offset + const Offset(0, 30), paint);

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
        ra: ra / 15, dec: dec); // ra is in degrees, convert to hours
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
    textPainter.paint(
      canvas,
      offset + Offset(-textPainter.width / 2, 18),
    );
  }

  void _drawMoon(Canvas canvas, Size size, Offset center, double scale) {
    if (moonPosition == null) return;

    final (ra, dec, illumination) = moonPosition!;
    final coord = CelestialCoordinate(
        ra: ra / 15, dec: dec); // ra is in degrees, convert to hours
    final offset = _celestialToScreen(coord, center, scale);
    if (offset == null) return;

    // Moon apparent diameter ~31 arcminutes (0.517 degrees)
    // Scale with zoom so it appears correct relative to the sky
    final apparentSizeDeg = 31.0 / 60.0;
    final moonPixelRadius = (apparentSizeDeg / 2) * scale;
    final moonRadius = moonPixelRadius.clamp(8.0, 80.0);

    // Glow scaled to moon size
    final glowRadius = moonRadius * 1.6;
    if (qualityConfig.useBlurEffects) {
      final glowPaint = _PaintCache.getBlurPaint(
          moonRadius * 0.8, const Color(0xFFB0BEC5),
          alpha: 0.19);
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
            center:
                offset - Offset(moonRadius - terminatorWidth.abs() / 2, 0),
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
    final textPainter =
        _TextCache.get('MOON $illuminationPct%', labelStyle);
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
  void _drawPlanetDetails(Canvas canvas, Offset center, double radius,
      String planetName, Color planetColor) {
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
      Canvas canvas, Offset center, double radius, Color planetColor) {
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
          center: center, width: ringWidth * 0.75, height: ringHeight * 0.75),
      innerRingPaint,
    );

    // Cassini Division (dark gap)
    final divisionPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05;
    canvas.drawOval(
      Rect.fromCenter(
          center: center, width: ringWidth * 0.82, height: ringHeight * 0.82),
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
      Canvas canvas, Offset center, double radius, Color planetColor) {
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

        final preferredPos = offset + Offset(-textPainter.width / 2, dotRadius + 4);
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
  void _drawVariableStars(Canvas canvas, Size size, Offset center, double scale) {
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
          preferredPos, Size(tp.width, tp.height), size);
        if (labelPos != null) {
          tp.paint(canvas, labelPos);
        }
      }
    }
  }

  /// Draw minor planets (asteroids as diamonds, comets with fuzzy tail).
  void _drawMinorPlanets(Canvas canvas, Size size, Offset center, double scale) {
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
          canvas.drawCircle(offset, comaRadius + 2,
              Paint()..color = cometColor.withValues(alpha: 0.2));
        }
        canvas.drawCircle(offset, comaRadius * 0.6,
            Paint()..color = cometColor.withValues(alpha: isBright ? 0.8 : 0.5));

        // Tail (anti-sunward, simplified as upper-right)
        final tailLen = isBright ? 18.0 : 10.0;
        final tailEnd = Offset(offset.dx + tailLen * 0.7, offset.dy - tailLen * 0.7);
        canvas.drawLine(offset, tailEnd, Paint()
          ..shader = ui.Gradient.linear(offset, tailEnd,
              [cometColor.withValues(alpha: 0.4), cometColor.withValues(alpha: 0.0)])
          ..strokeWidth = isBright ? 3.0 : 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
        // Dust tail
        final dustEnd = Offset(offset.dx + tailLen * 0.5, offset.dy - tailLen * 0.9);
        canvas.drawLine(offset, dustEnd, Paint()
          ..shader = ui.Gradient.linear(offset, dustEnd,
              [cometColor.withValues(alpha: 0.2), cometColor.withValues(alpha: 0.0)])
          ..strokeWidth = isBright ? 5.0 : 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

        if (body.visualMag < 10.0) {
          _drawMinorPlanetLabel(canvas, offset, body.name, comaRadius + 5, size, cometColor);
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
        canvas.drawPath(path, Paint()
          ..color = asteroidColor.withValues(alpha: isBright ? 0.9 : 0.6));
        canvas.drawPath(path, Paint()
          ..color = asteroidColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);

        if (body.visualMag < 9.0) {
          _drawMinorPlanetLabel(canvas, offset, body.name, ds + 4, size, asteroidColor);
        }
      }
    }
  }

  void _drawMinorPlanetLabel(Canvas canvas, Offset offset, String name,
      double yOffset, Size size, Color color) {
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
        preferredPos, Size(tp.width, tp.height), size);
    if (labelPos != null) {
      tp.paint(canvas, labelPos);
    }
  }

  Offset? _celestialToScreen(
      CelestialCoordinate coord, Offset center, double scale) {
    // Convert RA from hours to degrees
    final raDeg = coord.ra * 15;
    final decDeg = coord.dec;

    // Calculate angular distance from view center
    final centerRaDeg = viewState.centerRA * 15;
    final centerDecDeg = viewState.centerDec;

    // Gnomonic/stereographic projection
    final ra1 = centerRaDeg * _deg2rad;
    final dec1 = centerDecDeg * _deg2rad;
    final ra2 = raDeg * _deg2rad;
    final dec2 = decDeg * _deg2rad;

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
    final rotRad = viewState.rotation * _deg2rad;
    final xRot = x * math.cos(rotRad) - y * math.sin(rotRad);
    final yRot = x * math.sin(rotRad) + y * math.cos(rotRad);

    // Scale and center
    return Offset(
      center.dx - xRot * scale * _rad2deg,
      center.dy - yRot * scale * _rad2deg,
    );
  }

  bool _isInView(Offset offset, Size size) {
    return offset.dx >= -50 &&
        offset.dx <= size.width + 50 &&
        offset.dy >= -50 &&
        offset.dy <= size.height + 50;
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

    _glowShaderPaint.shader = shader;
    canvas.drawCircle(center, radius, _glowShaderPaint);
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
    _glowShaderPaint.shader = shader;
    canvas.drawOval(rect, _glowShaderPaint);
  }

  // Reusable paint for glow shader rendering to avoid per-call allocation
  static final Paint _glowShaderPaint = Paint();

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

  @override
  bool shouldRepaint(covariant SkyCanvasPainter oldDelegate) {
    // Primary triggers - always repaint for these
    if (viewState != oldDelegate.viewState ||
        config != oldDelegate.config ||
        qualityConfig != oldDelegate.qualityConfig ||
        selectedObject != oldDelegate.selectedObject ||
        highlightedObject != oldDelegate.highlightedObject) {
      return true;
    }

    // Mount status change always triggers repaint
    if (mountStatus != oldDelegate.mountStatus) {
      return true;
    }

    // Mount position - only repaint if moved significantly (>0.05 degrees = ~3 arcmin)
    if (mountPosition != oldDelegate.mountPosition) {
      if (mountPosition == null || oldDelegate.mountPosition == null) {
        return true;
      }
      final raDiff = (mountPosition!.ra - oldDelegate.mountPosition!.ra).abs();
      final decDiff =
          (mountPosition!.dec - oldDelegate.mountPosition!.dec).abs();
      if (raDiff > 0.05 / 15 || decDiff > 0.05) {
        return true;
      }
    }

    // Observation time - only check minute changes for horizon/alt-az grid
    // (stars/DSOs don't move visibly in a minute, but horizon does)
    if (config.showHorizon || config.showAltAzGrid) {
      if (observationTime.minute != oldDelegate.observationTime.minute) {
        return true;
      }
    }

    // Sun/Moon/Planets - these move slowly, check if data actually changed
    if (sunPosition != oldDelegate.sunPosition ||
        moonPosition != oldDelegate.moonPosition ||
        planets.length != oldDelegate.planets.length) {
      return true;
    }

    // Satellites update every 2 seconds from the position notifier.
    // Only repaint when the satellite data actually changes (length or positions).
    if (satellites.length != oldDelegate.satellites.length) {
      return true;
    }
    if (config.showSatellites && satellites.isNotEmpty && oldDelegate.satellites.isNotEmpty) {
      // Check if any satellite position has actually moved (data identity check)
      // The satellite list is recreated by the notifier each update, so if the
      // list reference changed, the data is new. Use identity check.
      if (!identical(satellites, oldDelegate.satellites)) {
        return true;
      }
    }

    // Variable stars / minor planets change
    if (variableStars.length != oldDelegate.variableStars.length) {
      return true;
    }
    if (config.showVariableStars != oldDelegate.config.showVariableStars) {
      return true;
    }
    if (minorPlanets.length != oldDelegate.minorPlanets.length) {
      return true;
    }
    if (config.showMinorPlanets != oldDelegate.config.showMinorPlanets) {
      return true;
    }
    // Minor planets update every 30s; repaint if data changed
    if (config.showMinorPlanets && minorPlanets.isNotEmpty) {
      for (int i = 0; i < minorPlanets.length && i < oldDelegate.minorPlanets.length; i++) {
        if ((minorPlanets[i].ra - oldDelegate.minorPlanets[i].ra).abs() > 0.001 ||
            (minorPlanets[i].dec - oldDelegate.minorPlanets[i].dec).abs() > 0.01) {
          return true;
        }
      }
    }

    // Milky way data change
    if (milkyWayPoints != oldDelegate.milkyWayPoints) {
      return true;
    }

    // Animation phases - repaint when animations are active.
    // Twinkle phase changes continuously at 60Hz but the visual effect is subtle,
    // so quantize to ~20Hz (steps of 0.05) to reduce unnecessary repaints.
    if (animationPhase != null || oldDelegate.animationPhase != null) {
      final cur = animationPhase ?? -1.0;
      final old = oldDelegate.animationPhase ?? -1.0;
      // Quantize to 20 steps per cycle (50ms intervals on a 3s animation)
      if ((cur * 20).floor() != (old * 20).floor()) {
        return true;
      }
    }
    // Selection and pop-in are transient and short-lived, repaint every change
    if (selectionAnimationPhase != oldDelegate.selectionAnimationPhase) {
      return true;
    }
    if (popinAnimationPhase != oldDelegate.popinAnimationPhase) {
      return true;
    }
    if (dsoPopinAnimationPhase != oldDelegate.dsoPopinAnimationPhase) {
      return true;
    }
    if (parallaxPanDelta != oldDelegate.parallaxPanDelta) {
      return true;
    }

    // Density hotspots change
    if (densityHotspots.length != oldDelegate.densityHotspots.length) {
      return true;
    }

    // Observed object IDs change
    if (observedObjectIds.length != oldDelegate.observedObjectIds.length ||
        !observedObjectIds.containsAll(oldDelegate.observedObjectIds)) {
      return true;
    }

    // Listed object IDs change
    if (listedObjectIds.length != oldDelegate.listedObjectIds.length ||
        !listedObjectIds.containsAll(oldDelegate.listedObjectIds)) {
      return true;
    }

    // Bortle class change affects light pollution dome
    if (bortleClass != oldDelegate.bortleClass) {
      return true;
    }

    // Horizon profile change affects ground plane and horizon line
    if (horizonAltitudes != oldDelegate.horizonAltitudes) {
      return true;
    }

    return false;
  }
}
