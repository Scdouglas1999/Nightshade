import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

/// HyperLEDA catalog data for deep galaxy annotation
/// Contains ~3 million galaxies down to magnitude 20+
class HyperLedaData {
  final int pgc; // PGC number (unique identifier)
  final String? name; // Primary name (NGC, IC, UGC, etc.)
  final double ra; // Right ascension in degrees
  final double dec; // Declination in degrees
  final double? magnitude; // B-magnitude (visual)
  final double? majorAxis; // Major axis in arcminutes
  final double? minorAxis; // Minor axis in arcminutes
  final double? positionAngle; // Position angle in degrees
  final String? morphology; // Morphological type (e.g., Sb, E, Irr)
  final double? redshift; // Heliocentric velocity / c
  final double? distance; // Distance in Mpc (if available)

  const HyperLedaData({
    required this.pgc,
    this.name,
    required this.ra,
    required this.dec,
    this.magnitude,
    this.majorAxis,
    this.minorAxis,
    this.positionAngle,
    this.morphology,
    this.redshift,
    this.distance,
  });

  /// Parse a line from the HyperLEDA CSV export
  /// Expected format: pgc,objname,al2000,de2000,bt,logd25,logr25,pa,t,v,modbest
  factory HyperLedaData.fromCsvLine(String line) {
    final parts = _parseCsvLine(line);
    if (parts.length < 11) {
      throw FormatException('Invalid HyperLEDA line: insufficient columns');
    }

    return HyperLedaData(
      pgc: int.tryParse(parts[0]) ?? 0,
      name: parts[1].isNotEmpty ? parts[1] : null,
      ra: double.tryParse(parts[2]) ?? 0.0,
      dec: double.tryParse(parts[3]) ?? 0.0,
      magnitude: double.tryParse(parts[4]),
      // logd25 is log10(D25) where D25 is major axis in 0.1 arcmin
      majorAxis: _parseLogD25(parts[5]),
      // logr25 is log10(D25/d25) - axis ratio
      minorAxis: _parseMinorAxis(parts[5], parts[6]),
      positionAngle: double.tryParse(parts[7]),
      morphology: _parseMorphology(parts[8]),
      redshift: _parseRedshift(parts[9]),
      distance: _parseDistance(parts[10]),
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

  static double? _parseLogD25(String value) {
    final logD25 = double.tryParse(value);
    if (logD25 == null) return null;
    // Convert from log10(D25 in 0.1 arcmin) to arcmin
    return math.pow(10, logD25) * 0.1;
  }

  static double? _parseMinorAxis(String logD25Str, String logR25Str) {
    final logD25 = double.tryParse(logD25Str);
    final logR25 = double.tryParse(logR25Str);
    if (logD25 == null) return null;
    final majorAxis = math.pow(10, logD25) * 0.1;
    if (logR25 == null) return majorAxis; // Assume circular if no ratio
    final ratio = math.pow(10, logR25);
    return majorAxis / ratio;
  }

  static String? _parseMorphology(String value) {
    final t = double.tryParse(value);
    if (t == null) return null;
    // Convert numerical T-type to string morphology
    if (t < -5) return 'cE'; // Compact elliptical
    if (t < -3) return 'E'; // Elliptical
    if (t < -1) return 'S0'; // Lenticular
    if (t < 1) return 'Sa'; // Early spiral
    if (t < 3) return 'Sb'; // Intermediate spiral
    if (t < 5) return 'Sc'; // Late spiral
    if (t < 7) return 'Sd'; // Very late spiral
    if (t < 9) return 'Sm'; // Magellanic spiral
    return 'Irr'; // Irregular
  }

  static double? _parseRedshift(String value) {
    final v = double.tryParse(value);
    if (v == null) return null;
    // Convert heliocentric velocity (km/s) to redshift
    return v / 299792.458;
  }

  static double? _parseDistance(String value) {
    final modBest = double.tryParse(value);
    if (modBest == null) return null;
    // Convert distance modulus to distance in Mpc
    // m - M = 5 * log10(d) - 5
    // d = 10^((m-M+5)/5) parsecs = 10^((m-M+5)/5) / 1e6 Mpc
    return math.pow(10, (modBest + 5) / 5) / 1e6;
  }

  /// Get the display name for this object
  String get displayName => name ?? 'PGC $pgc';

  /// Get the catalog ID
  String get catalogId => 'PGC$pgc';

  /// Get size string
  String? get sizeString {
    if (majorAxis == null) return null;
    if (minorAxis != null && minorAxis != majorAxis) {
      return "${majorAxis!.toStringAsFixed(1)}' × ${minorAxis!.toStringAsFixed(1)}'";
    }
    return "${majorAxis!.toStringAsFixed(1)}'";
  }

  /// Get distance string
  String? get distanceString {
    if (distance != null) {
      if (distance! < 1) {
        return '${(distance! * 1000).toStringAsFixed(0)} kpc';
      }
      return '${distance!.toStringAsFixed(1)} Mpc';
    }
    if (redshift != null) {
      // Hubble distance approximation: d = cz/H0 where H0 ≈ 70 km/s/Mpc
      final hubbleDistance = redshift! * 299792.458 / 70;
      return '~${hubbleDistance.toStringAsFixed(0)} Mpc';
    }
    return null;
  }
}

/// Spatial grid cell for efficient lookups
class _SpatialGridCell {
  final List<HyperLedaData> objects = [];
}

/// HyperLEDA catalog loader with spatial indexing for fast coordinate queries
class HyperLedaCatalogLoader {
  final String filePath;
  List<HyperLedaData>? _cachedData;

  // Spatial index: 1-degree grid cells
  Map<String, _SpatialGridCell>? _spatialIndex;
  static const double _gridSize = 1.0; // degrees

  HyperLedaCatalogLoader(this.filePath);

  /// Build spatial index key from RA/Dec
  String _gridKey(double ra, double dec) {
    final raCell = (ra / _gridSize).floor();
    final decCell = ((dec + 90) / _gridSize).floor(); // Shift Dec to positive range
    return '$raCell,$decCell';
  }

  /// Load all galaxies from the catalog
  Future<List<HyperLedaData>> loadAll() async {
    if (_cachedData != null) return _cachedData!;

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('HyperLEDA catalog not found', filePath);
    }

    final lines = await file.readAsLines();
    final galaxies = <HyperLedaData>[];
    _spatialIndex = {};

    // Skip header line
    for (var i = 1; i < lines.length; i++) {
      try {
        final galaxy = HyperLedaData.fromCsvLine(lines[i]);
        galaxies.add(galaxy);

        // Add to spatial index
        final key = _gridKey(galaxy.ra, galaxy.dec);
        _spatialIndex!.putIfAbsent(key, () => _SpatialGridCell()).objects.add(galaxy);
      } catch (e) {
        // Why: HyperLEDA catalog can have malformed rows from upstream
        // exports; a single bad line must not abort the load. Log at FINE
        // so a systemic format regression surfaces in the dev console.
        developer.log(
          'HyperLEDA line $i parse failed; skipping: $e',
          name: 'HyperLedaCatalog',
          level: 500,
        );
      }
    }

    _cachedData = galaxies;
    return galaxies;
  }

  /// Load galaxies up to a magnitude limit
  Future<List<HyperLedaData>> loadByMagnitude(double maxMagnitude) async {
    final all = await loadAll();
    return all.where((g) => (g.magnitude ?? 99) <= maxMagnitude).toList();
  }

  /// Search galaxies near a coordinate with radius in degrees
  Future<List<HyperLedaData>> searchNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    await loadAll(); // Ensure data is loaded

    if (_spatialIndex == null) return [];

    final results = <HyperLedaData>[];
    final radiusSq = radiusDegrees * radiusDegrees;

    // Calculate grid cells to search
    final minRa = ra - radiusDegrees;
    final maxRa = ra + radiusDegrees;
    final minDec = dec - radiusDegrees;
    final maxDec = dec + radiusDegrees;

    final minRaCell = (minRa / _gridSize).floor();
    final maxRaCell = (maxRa / _gridSize).floor();
    final minDecCell = ((minDec + 90) / _gridSize).floor();
    final maxDecCell = ((maxDec + 90) / _gridSize).floor();

    // Search relevant grid cells
    for (var raCell = minRaCell; raCell <= maxRaCell; raCell++) {
      for (var decCell = minDecCell; decCell <= maxDecCell; decCell++) {
        // Handle RA wraparound
        var normalizedRaCell = raCell;
        while (normalizedRaCell < 0) normalizedRaCell += 360;
        while (normalizedRaCell >= 360) normalizedRaCell -= 360;

        final key = '$normalizedRaCell,$decCell';
        final cell = _spatialIndex![key];
        if (cell == null) continue;

        for (final galaxy in cell.objects) {
          // Check magnitude filter
          if (maxMagnitude != null && (galaxy.magnitude ?? 99) > maxMagnitude) {
            continue;
          }

          // Calculate angular distance (simplified for small angles)
          final dRa = (galaxy.ra - ra) * math.cos(dec * math.pi / 180);
          final dDec = galaxy.dec - dec;
          final distSq = dRa * dRa + dDec * dDec;

          if (distSq <= radiusSq) {
            results.add(galaxy);
          }
        }
      }
    }

    // Sort by distance from center
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

  /// Search galaxies by name
  Future<List<HyperLedaData>> search(String query) async {
    final all = await loadAll();
    final q = query.toLowerCase();
    return all.where((g) {
      final name = g.displayName.toLowerCase();
      final pgc = g.catalogId.toLowerCase();
      return name.contains(q) || pgc.contains(q);
    }).toList();
  }

  /// Find a galaxy by PGC number
  Future<HyperLedaData?> findByPgc(int pgc) async {
    final all = await loadAll();
    return all.where((g) => g.pgc == pgc).firstOrNull;
  }

  /// Get galaxy count
  Future<int> get count async {
    final all = await loadAll();
    return all.length;
  }

  /// Clear cache
  void clearCache() {
    _cachedData = null;
    _spatialIndex = null;
  }
}
