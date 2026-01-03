import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'coordinate_system.dart';
import 'celestial_object.dart';
import 'catalogs/star_catalog.dart';
import 'catalogs/catalog.dart';
import 'catalogs/constellation_data.dart';

/// Interactive sky view widget
class SkyView extends StatefulWidget {
  final DateTime? observationTime;
  final double latitude;
  final double longitude;
  final SkyViewLayers layers;
  final ValueChanged<CelestialCoordinate>? onObjectSelected;

  const SkyView({
    super.key,
    this.observationTime,
    this.latitude = 51.5074,
    this.longitude = -0.1278,
    this.layers = const SkyViewLayers(),
    this.onObjectSelected,
  });

  @override
  State<SkyView> createState() => _SkyViewState();
}

class _SkyViewState extends State<SkyView> {
  double _azimuth = 0;
  double _altitude = 45;
  double _zoom = 1.0;

  // Catalog data
  final HygStarCatalog _starCatalog = HygStarCatalog(magnitudeLimit: 6.0);
  final OpenNgcDsoCatalog _dsoCatalog = OpenNgcDsoCatalog(magnitudeLimit: 12.0);
  List<Star>? _stars;
  List<DeepSkyObject>? _dsos;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  Future<void> _loadCatalogs() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // Load stars and DSOs asynchronously
      final stars = await _starCatalog.loadObjects();
      final dsos = await _dsoCatalog.loadObjects();

      if (mounted) {
        setState(() {
          _stars = stars;
          _dsos = dsos;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading catalogs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _azimuth += details.delta.dx * 0.5;
          _altitude = (_altitude - details.delta.dy * 0.5).clamp(-90, 90);
        });
      },
      onScaleUpdate: (details) {
        setState(() {
          _zoom = (_zoom * details.scale).clamp(0.5, 10.0);
        });
      },
      child: CustomPaint(
        painter: _SkyPainter(
          azimuth: _azimuth,
          altitude: _altitude,
          zoom: _zoom,
          layers: widget.layers,
          latitude: widget.latitude,
          longitude: widget.longitude,
          observationTime: widget.observationTime ?? DateTime.now(),
          stars: _stars,
          dsos: _dsos,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Sky view layers configuration
class SkyViewLayers {
  final bool showStars;
  final bool showDSOs;
  final bool showConstellations;
  final bool showGrid;
  final bool showHorizon;
  final bool showFOV;

  const SkyViewLayers({
    this.showStars = true,
    this.showDSOs = true,
    this.showConstellations = true,
    this.showGrid = true,
    this.showHorizon = false,
    this.showFOV = true,
  });
}

class _SkyPainter extends CustomPainter {
  final double azimuth;
  final double altitude;
  final double zoom;
  final SkyViewLayers layers;
  final double latitude;
  final double longitude;
  final DateTime observationTime;
  final List<Star>? stars;
  final List<DeepSkyObject>? dsos;

  _SkyPainter({
    required this.azimuth,
    required this.altitude,
    required this.zoom,
    required this.layers,
    required this.latitude,
    required this.longitude,
    required this.observationTime,
    this.stars,
    this.dsos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A1A),
    );

    // Draw grid if enabled
    if (layers.showGrid) {
      _drawGrid(canvas, size, center);
    }

    // Draw constellation lines first (behind stars)
    if (layers.showConstellations) {
      _drawConstellations(canvas, size, center);
    }

    // Draw DSOs
    if (layers.showDSOs && dsos != null) {
      _drawDSOs(canvas, size, center);
    }

    // Draw stars on top
    if (layers.showStars && stars != null) {
      _drawStars(canvas, size, center);
    }
  }
  
  void _drawGrid(Canvas canvas, Size size, Offset center) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 0.5;

    // Draw altitude circles
    for (var alt = 0; alt <= 90; alt += 30) {
      final radius = (90 - alt) / 90 * (size.shortestSide / 2) * zoom;
      canvas.drawCircle(center, radius, paint..style = PaintingStyle.stroke);
    }

    // Draw azimuth lines
    for (var az = 0; az < 360; az += 30) {
      final rad = (az - azimuth) * math.pi / 180;
      final dx = size.shortestSide / 2 * zoom;
      canvas.drawLine(
        center,
        center + Offset(dx * -math.sin(rad), dx * -math.cos(rad)),
        paint,
      );
    }
  }
  
  void _drawStars(Canvas canvas, Size size, Offset center) {
    if (stars == null || stars!.isEmpty) return;

    // Draw each star using real catalog data
    for (final star in stars!) {
      // Convert RA/Dec to Alt/Az for observer's location and time
      final horizontal = star.coordinates.toHorizontal(
        latitude: latitude,
        longitude: longitude,
        time: observationTime,
      );

      // Skip stars below horizon
      if (!horizontal.isAboveHorizon) continue;

      // Project Alt/Az to screen coordinates
      final screenPos = _projectToScreen(
        horizontal.altitude,
        horizontal.azimuth,
        size,
        center,
      );

      // Skip if outside visible area
      if (screenPos == null) continue;

      // Calculate star size based on magnitude
      // Brighter stars (lower magnitude) = larger size
      final magnitude = star.magnitude ?? 6.0;
      final brightness = (6.5 - magnitude).clamp(0.0, 6.0);
      final radius = (brightness * 0.8 + 0.5) * zoom.clamp(0.5, 2.0);

      // Skip very faint stars when zoomed out
      if (radius < 0.3) continue;

      // Get star color based on color index
      final colorValue = star.getStarColor();
      final color = Color(colorValue);

      // Draw the star with slight glow for bright stars
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPos, radius, paint);

      // Add glow for very bright stars
      if (magnitude < 2.0) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(screenPos, radius * 2.5, glowPaint);
      }
    }
  }
  
  void _drawConstellations(Canvas canvas, Size size, Offset center) {
    final paint = Paint()
      ..color = const Color(0x44888888)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final constellation in Constellations.all) {
      for (final line in constellation.lines) {
        // Convert start and end positions to horizontal coordinates
        final startHorizontal = line.start.toHorizontal(
          latitude: latitude,
          longitude: longitude,
          time: observationTime,
        );
        final endHorizontal = line.end.toHorizontal(
          latitude: latitude,
          longitude: longitude,
          time: observationTime,
        );

        // Skip lines where either end is below horizon
        if (!startHorizontal.isAboveHorizon || !endHorizontal.isAboveHorizon) {
          continue;
        }

        // Project to screen coordinates
        final startPos = _projectToScreen(
          startHorizontal.altitude,
          startHorizontal.azimuth,
          size,
          center,
        );
        final endPos = _projectToScreen(
          endHorizontal.altitude,
          endHorizontal.azimuth,
          size,
          center,
        );

        if (startPos != null && endPos != null) {
          canvas.drawLine(startPos, endPos, paint);
        }
      }
    }
  }

  void _drawDSOs(Canvas canvas, Size size, Offset center) {
    if (dsos == null || dsos!.isEmpty) return;

    // Only draw brighter DSOs to avoid clutter
    final visibleDsos = dsos!.where((dso) =>
      (dso.magnitude ?? 99) < 10.0
    ).toList();

    for (final dso in visibleDsos) {
      // Convert to horizontal coordinates
      final horizontal = dso.coordinates.toHorizontal(
        latitude: latitude,
        longitude: longitude,
        time: observationTime,
      );

      // Skip if below horizon
      if (!horizontal.isAboveHorizon) continue;

      // Project to screen
      final screenPos = _projectToScreen(
        horizontal.altitude,
        horizontal.azimuth,
        size,
        center,
      );

      if (screenPos == null) continue;

      // Draw DSO symbol based on type
      _drawDsoSymbol(canvas, screenPos, dso);
    }
  }

  void _drawDsoSymbol(Canvas canvas, Offset position, DeepSkyObject dso) {
    final paint = Paint()
      ..color = const Color(0xAA88CCFF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final size = 6.0 * zoom.clamp(0.5, 2.0);

    if (dso.type.isGalaxy) {
      // Galaxy: ellipse
      canvas.drawOval(
        Rect.fromCenter(center: position, width: size * 2, height: size),
        paint,
      );
    } else if (dso.type.isNebula) {
      // Nebula: square
      canvas.drawRect(
        Rect.fromCenter(center: position, width: size * 1.5, height: size * 1.5),
        paint,
      );
    } else if (dso.type.isCluster) {
      // Cluster: circle with dots
      canvas.drawCircle(position, size, paint);
      // Draw a few dots inside
      final dotPaint = Paint()
        ..color = const Color(0xAA88CCFF)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2;
        final dotPos = Offset(
          position.dx + math.cos(angle) * size * 0.4,
          position.dy + math.sin(angle) * size * 0.4,
        );
        canvas.drawCircle(dotPos, 0.8, dotPaint);
      }
    } else {
      // Default: circle
      canvas.drawCircle(position, size, paint);
    }
  }

  /// Project altitude/azimuth coordinates to screen position
  /// Returns null if the position is outside the visible area
  Offset? _projectToScreen(
    double altitude,
    double azimuth,
    Size size,
    Offset center,
  ) {
    // Adjust azimuth by view rotation
    final adjustedAz = (azimuth - this.azimuth) % 360;

    // Calculate angular distance from view center
    final viewAltRad = this.altitude * math.pi / 180;
    final altRad = altitude * math.pi / 180;
    final azDiffRad = adjustedAz * math.pi / 180;

    // Stereographic projection
    // Calculate angular separation
    final cosDist = math.sin(viewAltRad) * math.sin(altRad) +
        math.cos(viewAltRad) * math.cos(altRad) * math.cos(azDiffRad);

    // Skip if behind viewer (angular distance > 90 degrees)
    if (cosDist < 0) return null;

    final angularDist = math.acos(cosDist.clamp(-1.0, 1.0));

    // Calculate position angle on screen
    final sinAzDiff = math.sin(azDiffRad);
    final cosAzDiff = math.cos(azDiffRad);
    final y = math.cos(altRad) * sinAzDiff;
    final x = math.cos(viewAltRad) * math.sin(altRad) -
        math.sin(viewAltRad) * math.cos(altRad) * cosAzDiff;
    final posAngle = math.atan2(y, x);

    // Project to screen using stereographic projection
    final scale = size.shortestSide / 2 * zoom;
    final radius = scale * math.tan(angularDist / 2);

    final screenX = center.dx + radius * math.cos(posAngle);
    final screenY = center.dy - radius * math.sin(posAngle);

    // Check if within canvas bounds (with margin)
    if (screenX < -50 || screenX > size.width + 50 ||
        screenY < -50 || screenY > size.height + 50) {
      return null;
    }

    return Offset(screenX, screenY);
  }

  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) {
    return azimuth != oldDelegate.azimuth ||
           altitude != oldDelegate.altitude ||
           zoom != oldDelegate.zoom ||
           stars != oldDelegate.stars ||
           dsos != oldDelegate.dsos;
  }
}





