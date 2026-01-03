import 'dart:math' as math;
import '../celestial_object.dart';
import '../coordinate_system.dart';

/// Grid-based spatial index for fast viewport queries
///
/// Divides the celestial sphere into cells for efficient culling.
/// Instead of iterating through all 120k+ objects per frame,
/// we only query cells that overlap the current viewport.
class CelestialSpatialIndex<T extends CelestialObject> {
  /// Number of cells along the RA axis (0-24 hours)
  static const int raCells = 24;

  /// Number of cells along the Dec axis (-90 to +90 degrees)
  static const int decCells = 18;

  /// Grid storage: [raCell][decCell] -> list of objects
  final List<List<List<T>>> _grid;

  /// All objects stored in the index
  final List<T> _allObjects = [];

  CelestialSpatialIndex()
      : _grid = List.generate(
          raCells,
          (_) => List.generate(decCells, (_) => <T>[]),
        );

  /// Clear all objects from the index
  void clear() {
    for (var ra = 0; ra < raCells; ra++) {
      for (var dec = 0; dec < decCells; dec++) {
        _grid[ra][dec].clear();
      }
    }
    _allObjects.clear();
  }

  /// Add a single object to the index
  void add(T object) {
    final raCell = _raToCell(object.coordinates.ra);
    final decCell = _decToCell(object.coordinates.dec);
    _grid[raCell][decCell].add(object);
    _allObjects.add(object);
  }

  /// Add multiple objects to the index
  void addAll(List<T> objects) {
    for (final obj in objects) {
      final raCell = _raToCell(obj.coordinates.ra);
      final decCell = _decToCell(obj.coordinates.dec);
      _grid[raCell][decCell].add(obj);
    }
    _allObjects.addAll(objects);
  }

  /// Get all objects in the index
  List<T> get all => _allObjects;

  /// Get total number of indexed objects
  int get length => _allObjects.length;

  /// Query objects within a viewport defined by center and field of view
  ///
  /// [centerRA] - Right ascension of viewport center in hours (0-24)
  /// [centerDec] - Declination of viewport center in degrees (-90 to +90)
  /// [fovDegrees] - Field of view in degrees
  /// [maxResults] - Optional limit on number of results
  List<T> queryViewport(
    double centerRA,
    double centerDec,
    double fovDegrees, {
    int? maxResults,
  }) {
    // Calculate the RA and Dec ranges that might be visible
    // RA range depends on declination (wider near poles)
    final decRangeHalf = fovDegrees / 2;
    final minDec = (centerDec - decRangeHalf).clamp(-90.0, 90.0);
    final maxDec = (centerDec + decRangeHalf).clamp(-90.0, 90.0);

    // RA range expands near poles due to spherical geometry
    // At dec=90, all RA values are at the same point
    final cosDec = math.cos(centerDec.abs() * math.pi / 180);
    final raRangeHours =
        cosDec > 0.1 ? (fovDegrees / 15 / cosDec).clamp(0.0, 12.0) : 12.0;

    final minRA = centerRA - raRangeHours / 2;
    final maxRA = centerRA + raRangeHours / 2;

    final results = <T>[];

    // Calculate cell ranges
    final startDecCell = _decToCell(minDec);
    final endDecCell = _decToCell(maxDec);

    // Handle RA wraparound (e.g., viewport spanning 23h to 1h)
    void addFromRaRange(double raStart, double raEnd) {
      final startRaCell = _raToCell(raStart);
      final endRaCell = _raToCell(raEnd);

      for (var r = startRaCell; r <= endRaCell; r++) {
        final raIdx = r % raCells;
        for (var d = startDecCell; d <= endDecCell; d++) {
          if (maxResults != null && results.length >= maxResults) return;
          results.addAll(_grid[raIdx][d]);
        }
      }
    }

    if (maxRA > 24.0) {
      // Wraparound case: spans across 24h/0h boundary
      addFromRaRange(minRA, 24.0);
      addFromRaRange(0.0, maxRA - 24.0);
    } else if (minRA < 0.0) {
      // Wraparound case: spans across 0h boundary
      addFromRaRange(minRA + 24.0, 24.0);
      addFromRaRange(0.0, maxRA);
    } else {
      addFromRaRange(minRA, maxRA);
    }

    // Apply maxResults limit if specified
    if (maxResults != null && results.length > maxResults) {
      return results.sublist(0, maxResults);
    }

    return results;
  }

  /// Query objects within a cone search (centered at coordinates with radius)
  ///
  /// More accurate than queryViewport but slightly slower
  List<T> queryCone(
    CelestialCoordinate center,
    double radiusDegrees, {
    int? maxResults,
  }) {
    // First get candidates from spatial index
    final candidates = queryViewport(
      center.ra,
      center.dec,
      radiusDegrees * 2,
      maxResults: maxResults != null ? maxResults * 2 : null,
    );

    // Filter by actual angular distance
    final results = <T>[];
    for (final obj in candidates) {
      if (maxResults != null && results.length >= maxResults) break;
      final distance = _angularDistance(center, obj.coordinates);
      if (distance <= radiusDegrees) {
        results.add(obj);
      }
    }

    return results;
  }

  /// Query objects within a magnitude range
  List<T> queryByMagnitude(double maxMagnitude, {int? maxResults}) {
    final results = <T>[];
    for (final obj in _allObjects) {
      if (maxResults != null && results.length >= maxResults) break;
      final mag = obj.magnitude;
      if (mag != null && mag <= maxMagnitude) {
        results.add(obj);
      }
    }
    return results;
  }

  /// Convert RA (hours, 0-24) to cell index
  int _raToCell(double ra) {
    final normalizedRA = ra < 0 ? ra + 24 : (ra >= 24 ? ra - 24 : ra);
    return (normalizedRA / 24 * raCells).floor().clamp(0, raCells - 1);
  }

  /// Convert Dec (degrees, -90 to +90) to cell index
  int _decToCell(double dec) {
    return ((dec + 90) / 180 * decCells).floor().clamp(0, decCells - 1);
  }

  /// Calculate angular distance between two celestial coordinates in degrees
  double _angularDistance(CelestialCoordinate a, CelestialCoordinate b) {
    final ra1 = a.ra * 15 * math.pi / 180; // Convert hours to radians
    final dec1 = a.dec * math.pi / 180;
    final ra2 = b.ra * 15 * math.pi / 180;
    final dec2 = b.dec * math.pi / 180;

    final cosSep = math.sin(dec1) * math.sin(dec2) +
        math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);

    return math.acos(cosSep.clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

/// Specialized spatial index for stars with magnitude-based filtering
class StarSpatialIndex extends CelestialSpatialIndex<Star> {
  /// Query stars within viewport, filtered by magnitude
  List<Star> queryViewportFiltered(
    double centerRA,
    double centerDec,
    double fovDegrees, {
    required double maxMagnitude,
    int? maxResults,
  }) {
    final candidates = queryViewport(centerRA, centerDec, fovDegrees);

    final results = <Star>[];
    for (final star in candidates) {
      if (maxResults != null && results.length >= maxResults) break;
      final mag = star.magnitude ?? 99;
      if (mag <= maxMagnitude) {
        results.add(star);
      }
    }

    // Sort by magnitude (brightest first) for consistent rendering
    results.sort((a, b) => (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));

    return results;
  }
}

/// Specialized spatial index for DSOs with magnitude and size filtering
class DsoSpatialIndex extends CelestialSpatialIndex<DeepSkyObject> {
  /// Query DSOs within viewport, filtered by magnitude
  List<DeepSkyObject> queryViewportFiltered(
    double centerRA,
    double centerDec,
    double fovDegrees, {
    required double maxMagnitude,
    int? maxResults,
  }) {
    final candidates = queryViewport(centerRA, centerDec, fovDegrees);

    final results = <DeepSkyObject>[];
    for (final dso in candidates) {
      if (maxResults != null && results.length >= maxResults) break;
      final mag = dso.magnitude ?? 99;
      if (mag <= maxMagnitude) {
        results.add(dso);
      }
    }

    // Sort by magnitude (brightest first)
    results.sort((a, b) => (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));

    return results;
  }

  /// Query DSOs by type
  List<DeepSkyObject> queryByType(DsoType type, {int? maxResults}) {
    final results = <DeepSkyObject>[];
    for (final dso in all) {
      if (maxResults != null && results.length >= maxResults) break;
      if (dso.type == type) {
        results.add(dso);
      }
    }
    return results;
  }
}
