import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

/// GLADE+ catalog data for deep galaxy annotation
/// Columns: RAJ2000, DEJ2000, Bmag, zhelio, PGC
class GladePlusData {
  final int pgc;
  final double ra; // degrees
  final double dec; // degrees
  final double? magnitude; // B magnitude
  final double? redshift; // derived from zhelio
  final double? distance; // Mpc (approximate, from zhelio)

  const GladePlusData({
    required this.pgc,
    required this.ra,
    required this.dec,
    this.magnitude,
    this.redshift,
    this.distance,
  });

  factory GladePlusData.fromCsvLine(String line) {
    final parts = _parseCsvLine(line);
    if (parts.length < 5) {
      throw const FormatException('Invalid GLADE+ line: insufficient columns');
    }

    final ra = double.tryParse(parts[0]) ?? 0.0;
    final dec = double.tryParse(parts[1]) ?? 0.0;
    final magnitude = double.tryParse(parts[2]);
    final velocity = double.tryParse(parts[3]);
    final redshift = _parseRedshift(velocity);
    final distance = _parseDistanceMpc(velocity);

    return GladePlusData(
      pgc: int.tryParse(parts[4]) ?? 0,
      ra: ra,
      dec: dec,
      magnitude: magnitude,
      redshift: redshift,
      distance: distance,
    );
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var inQuotes = false;
    var current = StringBuffer();

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  static double? _parseRedshift(double? velocity) {
    if (velocity == null) return null;
    return velocity / 299792.458;
  }

  static double? _parseDistanceMpc(double? velocity) {
    if (velocity == null) return null;
    // Hubble distance approximation with H0 ≈ 70 km/s/Mpc
    return velocity / 70.0;
  }

  String get displayName => 'PGC $pgc';
}

class _SpatialGridCell {
  final List<GladePlusData> objects = [];
}

/// GLADE+ catalog loader with spatial indexing for fast coordinate queries
class GladePlusCatalogLoader {
  final String filePath;
  List<GladePlusData>? _cachedData;

  Map<String, _SpatialGridCell>? _spatialIndex;
  static const double _gridSize = 1.0; // degrees

  GladePlusCatalogLoader(this.filePath);

  String _gridKey(double ra, double dec) {
    final raCell = (ra / _gridSize).floor();
    final decCell = ((dec + 90) / _gridSize).floor();
    return '$raCell,$decCell';
  }

  Future<List<GladePlusData>> loadAll() async {
    if (_cachedData != null) return _cachedData!;

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('GLADE+ catalog not found', filePath);
    }

    final lines = await file.readAsLines();
    final galaxies = <GladePlusData>[];
    _spatialIndex = {};

    for (var i = 1; i < lines.length; i++) {
      try {
        final galaxy = GladePlusData.fromCsvLine(lines[i]);
        galaxies.add(galaxy);

        final key = _gridKey(galaxy.ra, galaxy.dec);
        _spatialIndex!.putIfAbsent(key, () => _SpatialGridCell()).objects.add(galaxy);
      } catch (e) {
        // Why: GLADE+ catalog has ~22M entries; a single malformed line must
        // not abort the load. The rest of the catalog remains usable. Log
        // at FINE so a systemic format regression is visible.
        developer.log(
          'GLADE+ line $i parse failed; skipping: $e',
          name: 'GladePlusCatalog',
          level: 500,
        );
      }
    }

    _cachedData = galaxies;
    return galaxies;
  }

  Future<List<GladePlusData>> searchNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    await loadAll();

    if (_spatialIndex == null) return [];

    final results = <GladePlusData>[];
    final radiusSq = radiusDegrees * radiusDegrees;

    final minRa = ra - radiusDegrees;
    final maxRa = ra + radiusDegrees;
    final minDec = dec - radiusDegrees;
    final maxDec = dec + radiusDegrees;

    final minRaCell = (minRa / _gridSize).floor();
    final maxRaCell = (maxRa / _gridSize).floor();
    final minDecCell = ((minDec + 90) / _gridSize).floor();
    final maxDecCell = ((maxDec + 90) / _gridSize).floor();

    for (var raCell = minRaCell; raCell <= maxRaCell; raCell++) {
      for (var decCell = minDecCell; decCell <= maxDecCell; decCell++) {
        var normalizedRaCell = raCell;
        while (normalizedRaCell < 0) normalizedRaCell += 360;
        while (normalizedRaCell >= 360) normalizedRaCell -= 360;

        final key = '$normalizedRaCell,$decCell';
        final cell = _spatialIndex![key];
        if (cell == null) continue;

        for (final galaxy in cell.objects) {
          if (maxMagnitude != null &&
              (galaxy.magnitude ?? 99) > maxMagnitude) {
            continue;
          }

          final dRa = (galaxy.ra - ra) * math.cos(dec * math.pi / 180);
          final dDec = galaxy.dec - dec;
          final distSq = dRa * dRa + dDec * dDec;

          if (distSq <= radiusSq) {
            results.add(galaxy);
          }
        }
      }
    }

    results.sort((a, b) {
      final dRaA = (a.ra - ra) * math.cos(dec * math.pi / 180);
      final dDecA = a.dec - dec;
      final distA = dRaA * dRaA + dDecA * dDecA;

      final dRaB = (b.ra - ra) * math.cos(dec * math.pi / 180);
      final dDecB = b.dec - dec;
      final distB = dRaB * dRaB + dDecB * dDecB;

      return distA.compareTo(distB);
    });

    return results;
  }

  void clearCache() {
    _cachedData = null;
    _spatialIndex = null;
  }
}
