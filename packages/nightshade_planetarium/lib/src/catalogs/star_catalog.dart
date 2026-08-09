import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../celestial_object.dart';
import '../coordinate_system.dart';
import 'catalog.dart';
import 'catalog_manager.dart';

/// Star catalog that loads from the HYG database file
///
/// The HYG database contains ~120,000 stars compiled from:
/// - Hipparcos Catalog (high precision astrometry)
/// - Yale Bright Star Catalog (bright stars with names)
/// - Gliese Catalog of Nearby Stars
class HygStarCatalog extends Catalog<Star> {
  final String? catalogPath;
  final double magnitudeLimit;

  List<Star>? _cachedStars;
  bool _isLoading = false;
  bool _usingFallback = false;

  /// Create a star catalog
  ///
  /// [catalogPath] - Path to the HYG CSV file, or null to use CatalogManager
  /// [magnitudeLimit] - Maximum magnitude to load (fainter stars have higher values)
  HygStarCatalog({this.catalogPath, this.magnitudeLimit = 15.0});

  @override
  String get name => 'HYG Database';

  /// Check if catalog data is available
  Future<bool> get isAvailable async {
    final path = catalogPath ?? CatalogManager.instance.starCatalogPath;
    return File(path).exists();
  }

  /// Get the number of loaded stars
  int get starCount => _cachedStars?.length ?? 0;

  /// Whether the last [loadObjects] served the built-in [_fallbackBrightStars]
  /// list because no catalog file was installed.
  ///
  /// That list is a handful of naked-eye stars — enough to prove the renderer
  /// works, nowhere near a usable sky — so the UI must say so rather than let
  /// it pass for the real catalog.
  bool get isUsingFallback => _usingFallback;

  /// Number of stars in the built-in fallback list.
  static int get fallbackStarCount => _fallbackBrightStars.length;

  @override
  Future<List<Star>> loadObjects() async {
    if (_cachedStars != null) return _cachedStars!;
    if (_isLoading) {
      // Wait for loading to complete
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _cachedStars ?? [];
    }

    _isLoading = true;

    try {
      final path = catalogPath ?? CatalogManager.instance.starCatalogPath;
      final file = File(path);

      if (!await file.exists()) {
        // Return fallback bright stars if catalog not installed
        _usingFallback = true;
        _cachedStars = _fallbackBrightStars;
        return _cachedStars!;
      }

      // Use compute to load in background isolate
      try {
        final stars = await compute(
          _loadStarsInIsolate,
          _LoadStarsArgs(path, magnitudeLimit),
        );
        _usingFallback = false;
        _cachedStars = stars;
        return stars;
      } catch (e) {
        developer.log(
          '[Catalog] Error loading stars in isolate: $e',
          name: 'StarCatalog',
          level: 1000,
          error: e,
        );
        return [];
      }
    } finally {
      _isLoading = false;
    }
  }

  static Future<List<Star>> _loadStarsInIsolate(_LoadStarsArgs args) async {
    final file = File(args.path);
    if (!file.existsSync()) return [];

    final rows = <_HygRow>[];
    final stream = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var isHeader = true;
    await for (final line in stream) {
      if (isHeader) {
        isHeader = false;
        continue;
      }

      try {
        final row = _parseHygLine(line);
        if (row != null && (row.star.magnitude ?? 99) <= args.magnitudeLimit) {
          rows.add(row);
        }
      } catch (e) {
        // Why: HYG CSV contains ~120k rows; a single malformed line (truncated
        // export, encoding glitch, unexpected NaN in a numeric column) must
        // not abort the whole load — the catalog is still useful with one
        // row missing. Log at FINE so a systemic format regression (e.g.
        // upstream column reorder) shows up without spamming the user.
        developer.log(
          'HYG line parse failed; skipping: $e',
          name: 'HygStarCatalog',
          level: 500,
        );
      }
    }

    _nameComponentStars(rows);
    final stars = [for (final row in rows) row.star];

    // Sort by magnitude (brightest first)
    stars.sort((a, b) => (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));

    return stars;
  }

  /// Name the unnamed secondary components of a multiple star after their
  /// primary ("Capella B") instead of letting them fall back to the raw
  /// catalogue id ("HYG118360").
  ///
  /// HYG carries each component of a multiple system as its own row, and a
  /// secondary usually has no HIP number, no proper name and no Bayer or
  /// Flamsteed designation — only `comp` (which component it is) and
  /// `comp_primary` (the id of the row it belongs to). Capella's Ab row is one
  /// of those, 9 arcsec from Capella itself, so the chart labels the pair
  /// "Capella" while the catalogue held an entry called "HYG118360" that search
  /// and the object panel would happily show.
  ///
  /// Only rows that HYG itself marks as components are touched, and only when
  /// the primary row carries a real name, so nothing is invented.
  static void _nameComponentStars(List<_HygRow> rows) {
    final wantedPrimaries = <int>{};
    for (final row in rows) {
      if (_isUnnamedComponent(row)) wantedPrimaries.add(row.compPrimary);
    }
    if (wantedPrimaries.isEmpty) return;

    final primaryNames = <int, String>{};
    for (final row in rows) {
      if (row.named && wantedPrimaries.contains(row.hygId)) {
        primaryNames[row.hygId] = row.star.name;
      }
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (!_isUnnamedComponent(row)) continue;
      final primaryName = primaryNames[row.compPrimary];
      if (primaryName == null) continue;
      final s = row.star;
      rows[i] = (
        star: Star(
          id: s.id,
          name: '$primaryName ${_componentLetter(row.comp)}',
          coordinates: s.coordinates,
          magnitude: s.magnitude,
          spectralType: s.spectralType,
          constellation: s.constellation,
          colorIndex: s.colorIndex,
          catalogIds: s.catalogIds,
        ),
        hygId: row.hygId,
        comp: row.comp,
        compPrimary: row.compPrimary,
        named: true,
      );
    }
  }

  static bool _isUnnamedComponent(_HygRow row) =>
      !row.named &&
      row.comp >= 2 &&
      row.compPrimary != 0 &&
      row.compPrimary != row.hygId;

  /// HYG's `comp` is 1-based, and component 1 is the primary — so component 2
  /// is the "B" of the system.
  static String _componentLetter(int comp) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final index = comp - 1;
    return index >= 0 && index < letters.length ? letters[index] : 'comp $comp';
  }

  /// Parse a line from the HYG CSV file
  /// HYG v3.8 format columns:
  /// 0:id, 1:hip, 2:hd, 3:hr, 4:gl, 5:bf, 6:proper, 7:ra, 8:dec, 9:dist,
  /// 10:pmra, 11:pmdec, 12:rv, 13:mag, 14:absmag, 15:spect, 16:ci,
  /// 17:x, 18:y, 19:z, 20:vx, 21:vy, 22:vz, 23:rarad, 24:decrad,
  /// 25:pmrarad, 26:pmdecrad, 27:bayer, 28:flam, 29:con, ...
  static _HygRow? _parseHygLine(String line) {
    final parts = _parseCsvLine(line);
    if (parts.length < 30) return null;

    final hygId = int.tryParse(parts[0]) ?? 0;

    // HYG row id 0 is the SUN, carried as a placeholder at RA 0h / Dec 0 with
    // magnitude -26.7 because the catalogue's cartesian coordinates are
    // heliocentric. It is not a sky position. Left in, it drew a huge blob
    // labelled "Sol" in the middle of Pisces, and — being by far the brightest
    // entry — it was the first result of every brightest-object-in-view query
    // that touched the RA 0h / Dec 0 region. The real Sun is drawn separately
    // from its computed ephemeris.
    if (hygId == 0) return null;

    final hipId = int.tryParse(parts[1]);
    final hdId = int.tryParse(parts[2]);
    final hrId = int.tryParse(parts[3]);
    final properName = parts.length > 6 ? parts[6] : '';
    final raHoursJ2000 = double.tryParse(parts[7]) ?? 0;
    final decJ2000 = double.tryParse(parts[8]) ?? 0;
    final pmra = double.tryParse(
      parts[10],
    ); // mas/yr on sky (includes cos(dec))
    final pmdec = double.tryParse(parts[11]); // mas/yr
    final magnitude = double.tryParse(parts[13]);
    final spectralType = parts.length > 15 ? parts[15] : null;
    final colorIndex = parts.length > 16 ? double.tryParse(parts[16]) : null;
    final bayerDesignation = parts.length > 27 ? parts[27] : null;
    final flamsteedNumber = parts.length > 28 ? parts[28] : null;
    final constellation = parts.length > 29 ? parts[29] : null;

    double raHours = raHoursJ2000;
    double dec = decJ2000;

    // Apply proper motion for stars with significant motion (>5 mas/yr).
    // Most stars have pmra/pmdec < 1 mas/yr where the correction over 26 years
    // is sub-arcsecond — completely invisible. Only ~2% of stars have motion
    // large enough to matter visually (>5 mas/yr = >0.13" over 26 years).
    // Skipping low-motion stars avoids floating point noise in the division
    // by cos(dec) that corrupts positions for the majority of the catalog.
    if (pmra != null && pmdec != null) {
      final pmTotal = pmra.abs() + pmdec.abs();
      if (pmTotal > 5.0) {
        // Only correct if total motion > 5 mas/yr
        final now = DateTime.now();
        final yearsSinceJ2000 =
            (now.year - 2000) + (now.month - 1) / 12.0 + (now.day - 1) / 365.25;

        // Convert mas/yr to degrees/yr: 1 mas = 1/3,600,000 degrees
        final pmraDegreesPerYear = pmra / 3600000.0;
        final pmdecDegreesPerYear = pmdec / 3600000.0;

        // pmra from HYG is "proper motion in RA * cos(dec)" (mas/yr),
        // so to get the actual RA change, divide by cos(dec).
        // Use dart:math cos() for accuracy.
        final cosDec = math
            .cos(decJ2000 * math.pi / 180.0)
            .abs()
            .clamp(0.01, 1.0);

        final raCorrectionHours =
            (pmraDegreesPerYear / cosDec) * yearsSinceJ2000 / 15.0;
        final decCorrectionDeg = pmdecDegreesPerYear * yearsSinceJ2000;

        // Safety clamp: no star moves more than 0.1h RA (~1.5°) or 1° Dec in 50 years
        raHours += raCorrectionHours.clamp(-0.1, 0.1);
        dec += decCorrectionDeg.clamp(-1.0, 1.0);

        // Normalize RA to [0, 24)
        if (raHours < 0) raHours += 24.0;
        if (raHours >= 24) raHours -= 24.0;

        // Clamp dec to [-90, 90]
        dec = dec.clamp(-90.0, 90.0);
      }
    }

    // Build the star ID (prefer HIP, then HD, then HYG)
    String id;
    if (hipId != null && hipId > 0) {
      id = 'HIP$hipId';
    } else if (hdId != null && hdId > 0) {
      id = 'HD$hdId';
    } else {
      id = 'HYG$hygId';
    }

    // Build the name (prefer proper name, then Bayer, then Flamsteed, then catalog ID)
    String starName = properName;
    if (starName.isEmpty &&
        bayerDesignation != null &&
        bayerDesignation.isNotEmpty) {
      starName =
          '$bayerDesignation ${_getConstellationGenitive(constellation ?? '')}';
    }
    if (starName.isEmpty &&
        flamsteedNumber != null &&
        flamsteedNumber.isNotEmpty) {
      starName =
          '$flamsteedNumber ${_getConstellationName(constellation ?? '')}';
    }
    // Whether the name above came from a real designation. When it did not,
    // [_nameComponentStars] gets a chance to derive one from the multiple-star
    // system this row belongs to before the raw id stands as the star's name.
    final named = starName.isNotEmpty;
    if (starName.isEmpty) {
      starName = id;
    }

    // Build alternate catalog IDs
    final catalogIds = <String>[];
    if (hipId != null && hipId > 0) catalogIds.add('HIP $hipId');
    if (hdId != null && hdId > 0) catalogIds.add('HD $hdId');
    if (hrId != null && hrId > 0) catalogIds.add('HR $hrId');

    // 30:comp (which component of a multiple system this row is, 1-based),
    // 31:comp_primary (id of the system's primary row).
    final comp = parts.length > 30 ? (int.tryParse(parts[30]) ?? 1) : 1;
    final compPrimary = parts.length > 31 ? (int.tryParse(parts[31]) ?? 0) : 0;

    return (
      star: Star(
        id: id,
        name: starName.trim(),
        coordinates: CelestialCoordinate(ra: raHours, dec: dec),
        magnitude: magnitude,
        spectralType: spectralType?.isNotEmpty == true ? spectralType : null,
        colorIndex: colorIndex,
        constellation: constellation?.isNotEmpty == true ? constellation : null,
        catalogIds: catalogIds,
      ),
      hygId: hygId,
      comp: comp,
      compPrimary: compPrimary,
      named: named,
    );
  }

  /// Parse a CSV line handling quoted fields
  static List<String> _parseCsvLine(String line) {
    final parts = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        parts.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    parts.add(current.toString().trim());
    return parts;
  }

  @override
  Future<Star?> findById(String id) async {
    final stars = await loadObjects();
    final normalizedId = id.toUpperCase().replaceAll(' ', '');

    return stars.where((s) {
      if (s.id.toUpperCase().replaceAll(' ', '') == normalizedId) return true;
      return s.catalogIds.any(
        (c) => c.toUpperCase().replaceAll(' ', '') == normalizedId,
      );
    }).firstOrNull;
  }

  @override
  Future<List<Star>> search(String query) async {
    final q = query.toLowerCase();
    final stars = await loadObjects();

    return stars
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.id.toLowerCase().contains(q) ||
              (s.constellation?.toLowerCase().contains(q) ?? false) ||
              s.catalogIds.any((c) => c.toLowerCase().contains(q)),
        )
        .toList();
  }

  /// Get stars by magnitude limit
  Future<List<Star>> getStarsByMagnitude(double maxMagnitude) async {
    final stars = await loadObjects();
    return stars.where((s) => (s.magnitude ?? 99) <= maxMagnitude).toList();
  }

  /// Get stars in a constellation
  Future<List<Star>> getStarsInConstellation(String constellation) async {
    final stars = await loadObjects();
    final conAbbr = _getConstellationAbbr(constellation);
    return stars
        .where(
          (s) =>
              s.constellation?.toLowerCase() == conAbbr.toLowerCase() ||
              s.constellation?.toLowerCase() == constellation.toLowerCase(),
        )
        .toList();
  }

  /// Get stars within [radiusDegrees] of [center] (cone search).
  ///
  /// [center] is a [CelestialCoordinate], so its RA is HOURS; the radius is
  /// degrees. Both sides of the comparison are taken to degrees, with the RA
  /// separation narrowed by cos(dec) and wrapped across 0h/24h, so the cone is
  /// a real angular cone rather than a rectangle in mixed units.
  Future<List<Star>> getStarsNear(
    CelestialCoordinate center,
    double radiusDegrees, {
    double? maxMagnitude,
  }) async {
    final stars = await loadObjects();
    final cosDec = math.cos(center.decRadians).abs().clamp(0.05, 1.0);
    final radiusSq = radiusDegrees * radiusDegrees;

    return stars.where((s) {
      if (maxMagnitude != null && (s.magnitude ?? 99) > maxMagnitude) {
        return false;
      }

      var dRaDeg = (s.coordinates.raDegrees - center.raDegrees).abs();
      if (dRaDeg > 180) dRaDeg = 360 - dRaDeg;
      final dxDeg = dRaDeg * cosDec;
      final dyDeg = s.coordinates.dec - center.dec;

      return dxDeg * dxDeg + dyDeg * dyDeg <= radiusSq;
    }).toList();
  }

  /// Clear the cache
  void clearCache() {
    _cachedStars = null;
  }

  /// Convert constellation name to genitive form (for Bayer designations)
  static String _getConstellationGenitive(String constellation) {
    return _constellationGenitives[constellation.toUpperCase()] ??
        constellation;
  }

  /// Get full constellation name from abbreviation
  static String _getConstellationName(String abbr) {
    return _constellationNames[abbr.toUpperCase()] ?? abbr;
  }

  /// Get constellation abbreviation from full name
  static String _getConstellationAbbr(String name) {
    final entry = _constellationNames.entries
        .where((e) => e.value.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    return entry?.key ?? name;
  }

  static const Map<String, String> _constellationGenitives = {
    'AND': 'Andromedae',
    'ANT': 'Antliae',
    'APS': 'Apodis',
    'AQR': 'Aquarii',
    'AQL': 'Aquilae',
    'ARA': 'Arae',
    'ARI': 'Arietis',
    'AUR': 'Aurigae',
    'BOO': 'Bootis',
    'CAE': 'Caeli',
    'CAM': 'Camelopardalis',
    'CNC': 'Cancri',
    'CVN': 'Canum Venaticorum',
    'CMA': 'Canis Majoris',
    'CMI': 'Canis Minoris',
    'CAP': 'Capricorni',
    'CAR': 'Carinae',
    'CAS': 'Cassiopeiae',
    'CEN': 'Centauri',
    'CEP': 'Cephei',
    'CET': 'Ceti',
    'CHA': 'Chamaeleontis',
    'CIR': 'Circini',
    'COL': 'Columbae',
    'COM': 'Comae Berenices',
    'CRA': 'Coronae Australis',
    'CRB': 'Coronae Borealis',
    'CRV': 'Corvi',
    'CRT': 'Crateris',
    'CRU': 'Crucis',
    'CYG': 'Cygni',
    'DEL': 'Delphini',
    'DOR': 'Doradus',
    'DRA': 'Draconis',
    'EQU': 'Equulei',
    'ERI': 'Eridani',
    'FOR': 'Fornacis',
    'GEM': 'Geminorum',
    'GRU': 'Gruis',
    'HER': 'Herculis',
    'HOR': 'Horologii',
    'HYA': 'Hydrae',
    'HYI': 'Hydri',
    'IND': 'Indi',
    'LAC': 'Lacertae',
    'LEO': 'Leonis',
    'LMI': 'Leonis Minoris',
    'LEP': 'Leporis',
    'LIB': 'Librae',
    'LUP': 'Lupi',
    'LYN': 'Lyncis',
    'LYR': 'Lyrae',
    'MEN': 'Mensae',
    'MIC': 'Microscopii',
    'MON': 'Monocerotis',
    'MUS': 'Muscae',
    'NOR': 'Normae',
    'OCT': 'Octantis',
    'OPH': 'Ophiuchi',
    'ORI': 'Orionis',
    'PAV': 'Pavonis',
    'PEG': 'Pegasi',
    'PER': 'Persei',
    'PHE': 'Phoenicis',
    'PIC': 'Pictoris',
    'PSC': 'Piscium',
    'PSA': 'Piscis Austrini',
    'PUP': 'Puppis',
    'PYX': 'Pyxidis',
    'RET': 'Reticuli',
    'SGE': 'Sagittae',
    'SGR': 'Sagittarii',
    'SCO': 'Scorpii',
    'SCL': 'Sculptoris',
    'SCT': 'Scuti',
    'SER': 'Serpentis',
    'SEX': 'Sextantis',
    'TAU': 'Tauri',
    'TEL': 'Telescopii',
    'TRA': 'Trianguli Australis',
    'TRI': 'Trianguli',
    'TUC': 'Tucanae',
    'UMA': 'Ursae Majoris',
    'UMI': 'Ursae Minoris',
    'VEL': 'Velorum',
    'VIR': 'Virginis',
    'VOL': 'Volantis',
    'VUL': 'Vulpeculae',
  };

  static const Map<String, String> _constellationNames = {
    'AND': 'Andromeda',
    'ANT': 'Antlia',
    'APS': 'Apus',
    'AQR': 'Aquarius',
    'AQL': 'Aquila',
    'ARA': 'Ara',
    'ARI': 'Aries',
    'AUR': 'Auriga',
    'BOO': 'Boötes',
    'CAE': 'Caelum',
    'CAM': 'Camelopardalis',
    'CNC': 'Cancer',
    'CVN': 'Canes Venatici',
    'CMA': 'Canis Major',
    'CMI': 'Canis Minor',
    'CAP': 'Capricornus',
    'CAR': 'Carina',
    'CAS': 'Cassiopeia',
    'CEN': 'Centaurus',
    'CEP': 'Cepheus',
    'CET': 'Cetus',
    'CHA': 'Chamaeleon',
    'CIR': 'Circinus',
    'COL': 'Columba',
    'COM': 'Coma Berenices',
    'CRA': 'Corona Australis',
    'CRB': 'Corona Borealis',
    'CRV': 'Corvus',
    'CRT': 'Crater',
    'CRU': 'Crux',
    'CYG': 'Cygnus',
    'DEL': 'Delphinus',
    'DOR': 'Dorado',
    'DRA': 'Draco',
    'EQU': 'Equuleus',
    'ERI': 'Eridanus',
    'FOR': 'Fornax',
    'GEM': 'Gemini',
    'GRU': 'Grus',
    'HER': 'Hercules',
    'HOR': 'Horologium',
    'HYA': 'Hydra',
    'HYI': 'Hydrus',
    'IND': 'Indus',
    'LAC': 'Lacerta',
    'LEO': 'Leo',
    'LMI': 'Leo Minor',
    'LEP': 'Lepus',
    'LIB': 'Libra',
    'LUP': 'Lupus',
    'LYN': 'Lynx',
    'LYR': 'Lyra',
    'MEN': 'Mensa',
    'MIC': 'Microscopium',
    'MON': 'Monoceros',
    'MUS': 'Musca',
    'NOR': 'Norma',
    'OCT': 'Octans',
    'OPH': 'Ophiuchus',
    'ORI': 'Orion',
    'PAV': 'Pavo',
    'PEG': 'Pegasus',
    'PER': 'Perseus',
    'PHE': 'Phoenix',
    'PIC': 'Pictor',
    'PSC': 'Pisces',
    'PSA': 'Piscis Austrinus',
    'PUP': 'Puppis',
    'PYX': 'Pyxis',
    'RET': 'Reticulum',
    'SGE': 'Sagitta',
    'SGR': 'Sagittarius',
    'SCO': 'Scorpius',
    'SCL': 'Sculptor',
    'SCT': 'Scutum',
    'SER': 'Serpens',
    'SEX': 'Sextans',
    'TAU': 'Taurus',
    'TEL': 'Telescopium',
    'TRA': 'Triangulum Australe',
    'TRI': 'Triangulum',
    'TUC': 'Tucana',
    'UMA': 'Ursa Major',
    'UMI': 'Ursa Minor',
    'VEL': 'Vela',
    'VIR': 'Virgo',
    'VOL': 'Volans',
    'VUL': 'Vulpecula',
  };

  /// Fallback bright stars when catalog is not installed
  /// Contains ~100 brightest/most important stars for basic functionality
  static final List<Star> _fallbackBrightStars = [
    // Magnitude < 0
    const Star(
      id: 'HIP32349',
      name: 'Sirius',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 101.286,
        decDegrees: -16.7161,
      ),
      magnitude: -1.46,
      spectralType: 'A1V',
      constellation: 'CMA',
    ),
    const Star(
      id: 'HIP30438',
      name: 'Canopus',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 95.985,
        decDegrees: -52.6957,
      ),
      magnitude: -0.72,
      spectralType: 'F0II',
      constellation: 'CAR',
    ),
    const Star(
      id: 'HIP71683',
      name: 'Rigil Kentaurus',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 219.899,
        decDegrees: -60.8354,
      ),
      magnitude: -0.29,
      spectralType: 'G2V',
      constellation: 'CEN',
    ),
    const Star(
      id: 'HIP69673',
      name: 'Arcturus',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 213.918,
        decDegrees: 19.1825,
      ),
      magnitude: -0.05,
      spectralType: 'K1.5III',
      constellation: 'BOO',
    ),

    // Magnitude 0-1
    const Star(
      id: 'HIP91262',
      name: 'Vega',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 279.234,
        decDegrees: 38.7837,
      ),
      magnitude: 0.03,
      spectralType: 'A0V',
      constellation: 'LYR',
    ),
    const Star(
      id: 'HIP24608',
      name: 'Capella',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 79.176,
        decDegrees: 45.9980,
      ),
      magnitude: 0.08,
      spectralType: 'G8III',
      constellation: 'AUR',
    ),
    const Star(
      id: 'HIP24436',
      name: 'Rigel',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 78.633,
        decDegrees: -8.2017,
      ),
      magnitude: 0.13,
      spectralType: 'B8Ia',
      constellation: 'ORI',
    ),
    const Star(
      id: 'HIP37279',
      name: 'Procyon',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 114.828,
        decDegrees: 5.2250,
      ),
      magnitude: 0.34,
      spectralType: 'F5IV',
      constellation: 'CMI',
    ),
    const Star(
      id: 'HIP27989',
      name: 'Betelgeuse',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 88.793,
        decDegrees: 7.4070,
      ),
      magnitude: 0.42,
      spectralType: 'M2Ib',
      constellation: 'ORI',
    ),
    const Star(
      id: 'HIP7588',
      name: 'Achernar',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 24.428,
        decDegrees: -57.2367,
      ),
      magnitude: 0.46,
      spectralType: 'B3V',
      constellation: 'ERI',
    ),
    const Star(
      id: 'HIP80763',
      name: 'Hadar',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 210.956,
        decDegrees: -60.3730,
      ),
      magnitude: 0.60,
      spectralType: 'B1III',
      constellation: 'CEN',
    ),
    const Star(
      id: 'HIP97649',
      name: 'Altair',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 297.696,
        decDegrees: 8.8683,
      ),
      magnitude: 0.77,
      spectralType: 'A7V',
      constellation: 'AQL',
    ),
    const Star(
      id: 'HIP60718',
      name: 'Acrux',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 186.650,
        decDegrees: -63.0990,
      ),
      magnitude: 0.76,
      spectralType: 'B0.5IV',
      constellation: 'CRU',
    ),
    const Star(
      id: 'HIP21421',
      name: 'Aldebaran',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 68.982,
        decDegrees: 16.5093,
      ),
      magnitude: 0.85,
      spectralType: 'K5III',
      constellation: 'TAU',
    ),
    const Star(
      id: 'HIP80763',
      name: 'Antares',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 247.352,
        decDegrees: -26.4320,
      ),
      magnitude: 1.06,
      spectralType: 'M1.5Ib',
      constellation: 'SCO',
    ),
    const Star(
      id: 'HIP65474',
      name: 'Spica',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 201.298,
        decDegrees: -11.1614,
      ),
      magnitude: 0.97,
      spectralType: 'B1V',
      constellation: 'VIR',
    ),
    const Star(
      id: 'HIP37826',
      name: 'Pollux',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 116.330,
        decDegrees: 28.0262,
      ),
      magnitude: 1.14,
      spectralType: 'K0III',
      constellation: 'GEM',
    ),
    const Star(
      id: 'HIP102098',
      name: 'Fomalhaut',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 344.412,
        decDegrees: -29.6223,
      ),
      magnitude: 1.16,
      spectralType: 'A3V',
      constellation: 'PSA',
    ),
    const Star(
      id: 'HIP102488',
      name: 'Deneb',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 310.358,
        decDegrees: 45.2803,
      ),
      magnitude: 1.25,
      spectralType: 'A2Ia',
      constellation: 'CYG',
    ),
    const Star(
      id: 'HIP62434',
      name: 'Mimosa',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 191.930,
        decDegrees: -59.6888,
      ),
      magnitude: 1.25,
      spectralType: 'B0.5IV',
      constellation: 'CRU',
    ),
    const Star(
      id: 'HIP54061',
      name: 'Regulus',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 152.093,
        decDegrees: 11.9672,
      ),
      magnitude: 1.40,
      spectralType: 'B8IV',
      constellation: 'LEO',
    ),
    const Star(
      id: 'HIP31592',
      name: 'Adhara',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 104.656,
        decDegrees: -28.9722,
      ),
      magnitude: 1.50,
      spectralType: 'B2II',
      constellation: 'CMA',
    ),
    const Star(
      id: 'HIP36850',
      name: 'Castor',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 113.650,
        decDegrees: 31.8884,
      ),
      magnitude: 1.58,
      spectralType: 'A1V',
      constellation: 'GEM',
    ),
    const Star(
      id: 'HIP78820',
      name: 'Shaula',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 263.402,
        decDegrees: -37.1038,
      ),
      magnitude: 1.63,
      spectralType: 'B2IV',
      constellation: 'SCO',
    ),
    const Star(
      id: 'HIP63003',
      name: 'Gacrux',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 187.791,
        decDegrees: -57.1132,
      ),
      magnitude: 1.64,
      spectralType: 'M3.5III',
      constellation: 'CRU',
    ),
    const Star(
      id: 'HIP41037',
      name: 'Miaplacidus',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 138.300,
        decDegrees: -69.7172,
      ),
      magnitude: 1.68,
      spectralType: 'A1III',
      constellation: 'CAR',
    ),
    const Star(
      id: 'HIP25336',
      name: 'Bellatrix',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 81.282,
        decDegrees: 6.3497,
      ),
      magnitude: 1.64,
      spectralType: 'B2III',
      constellation: 'ORI',
    ),
    const Star(
      id: 'HIP27366',
      name: 'Elnath',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 81.573,
        decDegrees: 28.6074,
      ),
      magnitude: 1.65,
      spectralType: 'B7III',
      constellation: 'TAU',
    ),
    const Star(
      id: 'HIP26311',
      name: 'Alnilam',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 84.054,
        decDegrees: -1.2019,
      ),
      magnitude: 1.70,
      spectralType: 'B0Ia',
      constellation: 'ORI',
    ),

    // Important navigation and constellation stars
    const Star(
      id: 'HIP11767',
      name: 'Polaris',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 37.953,
        decDegrees: 89.2641,
      ),
      magnitude: 1.98,
      spectralType: 'F7Ib',
      constellation: 'UMI',
    ),
    const Star(
      id: 'HIP26727',
      name: 'Alnitak',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 85.190,
        decDegrees: -1.9426,
      ),
      magnitude: 1.77,
      spectralType: 'O9.7Ib',
      constellation: 'ORI',
    ),
    const Star(
      id: 'HIP15863',
      name: 'Mirfak',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 51.081,
        decDegrees: 49.8612,
      ),
      magnitude: 1.79,
      spectralType: 'F5Ib',
      constellation: 'PER',
    ),
    const Star(
      id: 'HIP59774',
      name: 'Dubhe',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 165.932,
        decDegrees: 61.7510,
      ),
      magnitude: 1.79,
      spectralType: 'K0III',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP90185',
      name: 'Kaus Australis',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 276.044,
        decDegrees: -34.3847,
      ),
      magnitude: 1.80,
      spectralType: 'B9.5III',
      constellation: 'SGR',
    ),
    const Star(
      id: 'HIP65378',
      name: 'Alioth',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 193.506,
        decDegrees: 55.9598,
      ),
      magnitude: 1.77,
      spectralType: 'A0p',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP62956',
      name: 'Alkaid',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 206.885,
        decDegrees: 49.3133,
      ),
      magnitude: 1.86,
      spectralType: 'B3V',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP31681',
      name: 'Alhena',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 99.428,
        decDegrees: 16.3993,
      ),
      magnitude: 1.93,
      spectralType: 'A0IV',
      constellation: 'GEM',
    ),
    const Star(
      id: 'HIP82273',
      name: 'Atria',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 252.164,
        decDegrees: -69.0277,
      ),
      magnitude: 1.92,
      spectralType: 'K2IIb',
      constellation: 'TRA',
    ),
    const Star(
      id: 'HIP46390',
      name: 'Alphard',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 141.896,
        decDegrees: -8.6586,
      ),
      magnitude: 1.98,
      spectralType: 'K3III',
      constellation: 'HYA',
    ),
    const Star(
      id: 'HIP9884',
      name: 'Hamal',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 31.794,
        decDegrees: 23.4624,
      ),
      magnitude: 2.00,
      spectralType: 'K2III',
      constellation: 'ARI',
    ),
    const Star(
      id: 'HIP14135',
      name: 'Diphda',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 10.898,
        decDegrees: -17.9866,
      ),
      magnitude: 2.02,
      spectralType: 'K0III',
      constellation: 'CET',
    ),
    const Star(
      id: 'HIP89931',
      name: 'Nunki',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 283.816,
        decDegrees: -26.2967,
      ),
      magnitude: 2.02,
      spectralType: 'B2.5V',
      constellation: 'SGR',
    ),
    const Star(
      id: 'HIP677',
      name: 'Alpheratz',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 2.097,
        decDegrees: 29.0904,
      ),
      magnitude: 2.06,
      spectralType: 'B9p',
      constellation: 'AND',
    ),
    const Star(
      id: 'HIP1067',
      name: 'Mirach',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 17.432,
        decDegrees: 35.6206,
      ),
      magnitude: 2.06,
      spectralType: 'M0III',
      constellation: 'AND',
    ),
    const Star(
      id: 'HIP86032',
      name: 'Rasalhague',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 263.735,
        decDegrees: 12.5600,
      ),
      magnitude: 2.07,
      spectralType: 'A5III',
      constellation: 'OPH',
    ),
    const Star(
      id: 'HIP14576',
      name: 'Algol',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 47.046,
        decDegrees: 40.9557,
      ),
      magnitude: 2.12,
      spectralType: 'B8V',
      constellation: 'PER',
    ),
    const Star(
      id: 'HIP49669',
      name: 'Denebola',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 177.266,
        decDegrees: 14.5720,
      ),
      magnitude: 2.13,
      spectralType: 'A3V',
      constellation: 'LEO',
    ),
    const Star(
      id: 'HIP44816',
      name: 'Suhail',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 137.000,
        decDegrees: -43.4326,
      ),
      magnitude: 2.21,
      spectralType: 'K4Ib',
      constellation: 'VEL',
    ),
    const Star(
      id: 'HIP3419',
      name: 'Schedar',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 10.128,
        decDegrees: 56.5373,
      ),
      magnitude: 2.23,
      spectralType: 'K0II',
      constellation: 'CAS',
    ),
    const Star(
      id: 'HIP76267',
      name: 'Alphecca',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 233.673,
        decDegrees: 26.7147,
      ),
      magnitude: 2.23,
      spectralType: 'A0V',
      constellation: 'CRB',
    ),
    const Star(
      id: 'HIP87833',
      name: 'Eltanin',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 269.150,
        decDegrees: 51.4889,
      ),
      magnitude: 2.23,
      spectralType: 'K5III',
      constellation: 'DRA',
    ),
    const Star(
      id: 'HIP25930',
      name: 'Mintaka',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 83.002,
        decDegrees: -0.2991,
      ),
      magnitude: 2.23,
      spectralType: 'O9.5II',
      constellation: 'ORI',
    ),
    const Star(
      id: 'HIP5447',
      name: 'Almach',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 30.975,
        decDegrees: 42.3297,
      ),
      magnitude: 2.26,
      spectralType: 'K3II',
      constellation: 'AND',
    ),
    const Star(
      id: 'HIP39757',
      name: 'Naos',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 120.891,
        decDegrees: -40.0033,
      ),
      magnitude: 2.25,
      spectralType: 'O5If',
      constellation: 'PUP',
    ),
    const Star(
      id: 'HIP67301',
      name: 'Mizar',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 200.982,
        decDegrees: 54.9254,
      ),
      magnitude: 2.27,
      spectralType: 'A1V',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP4427',
      name: 'Caph',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 2.295,
        decDegrees: 59.1498,
      ),
      magnitude: 2.27,
      spectralType: 'F2III',
      constellation: 'CAS',
    ),
    const Star(
      id: 'HIP53910',
      name: 'Merak',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 165.459,
        decDegrees: 56.3824,
      ),
      magnitude: 2.37,
      spectralType: 'A1V',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP113368',
      name: 'Scheat',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 345.944,
        decDegrees: 28.0828,
      ),
      magnitude: 2.42,
      spectralType: 'M2.5II',
      constellation: 'PEG',
    ),
    const Star(
      id: 'HIP58001',
      name: 'Phecda',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 178.452,
        decDegrees: 53.6948,
      ),
      magnitude: 2.44,
      spectralType: 'A0V',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP105199',
      name: 'Alderamin',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 319.644,
        decDegrees: 62.5856,
      ),
      magnitude: 2.44,
      spectralType: 'A7IV',
      constellation: 'CEP',
    ),
    const Star(
      id: 'HIP8886',
      name: 'Navi',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 14.180,
        decDegrees: 60.7167,
      ),
      magnitude: 2.47,
      spectralType: 'B0IV',
      constellation: 'CAS',
    ),
    const Star(
      id: 'HIP113881',
      name: 'Markab',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 346.197,
        decDegrees: 15.2053,
      ),
      magnitude: 2.49,
      spectralType: 'A0IV',
      constellation: 'PEG',
    ),
    const Star(
      id: 'HIP8645',
      name: 'Menkar',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 45.573,
        decDegrees: 4.0897,
      ),
      magnitude: 2.53,
      spectralType: 'M1.5III',
      constellation: 'CET',
    ),
    const Star(
      id: 'HIP88635',
      name: 'Ascella',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 285.656,
        decDegrees: -29.8801,
      ),
      magnitude: 2.59,
      spectralType: 'A2IV',
      constellation: 'SGR',
    ),
    const Star(
      id: 'HIP61084',
      name: 'Gienah',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 183.951,
        decDegrees: -17.5419,
      ),
      magnitude: 2.59,
      spectralType: 'B8III',
      constellation: 'CRV',
    ),
    const Star(
      id: 'HIP8903',
      name: 'Sheratan',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 28.659,
        decDegrees: 20.8080,
      ),
      magnitude: 2.64,
      spectralType: 'A5V',
      constellation: 'ARI',
    ),
    const Star(
      id: 'HIP77070',
      name: 'Unukalhai',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 236.065,
        decDegrees: 6.4256,
      ),
      magnitude: 2.65,
      spectralType: 'K2III',
      constellation: 'SER',
    ),
    const Star(
      id: 'HIP746',
      name: 'Ruchbah',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 21.459,
        decDegrees: 60.2352,
      ),
      magnitude: 2.68,
      spectralType: 'A5IV',
      constellation: 'CAS',
    ),
    const Star(
      id: 'HIP59747',
      name: 'Imai',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 183.786,
        decDegrees: -58.7489,
      ),
      magnitude: 2.77,
      spectralType: 'B2IV',
      constellation: 'CRU',
    ),
    const Star(
      id: 'HIP84345',
      name: 'Kornephoros',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 247.557,
        decDegrees: 21.4897,
      ),
      magnitude: 2.77,
      spectralType: 'G7IIIa',
      constellation: 'HER',
    ),
    const Star(
      id: 'HIP83207',
      name: 'Rasalgethi',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 258.662,
        decDegrees: 14.3902,
      ),
      magnitude: 2.81,
      spectralType: 'M5Ib',
      constellation: 'HER',
    ),
    const Star(
      id: 'HIP112158',
      name: 'Algenib',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 3.302,
        decDegrees: 15.1836,
      ),
      magnitude: 2.83,
      spectralType: 'B2IV',
      constellation: 'PEG',
    ),
    const Star(
      id: 'HIP109074',
      name: 'Sadalsuud',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 322.890,
        decDegrees: -5.5712,
      ),
      magnitude: 2.91,
      spectralType: 'G0Ib',
      constellation: 'AQR',
    ),
    const Star(
      id: 'HIP109139',
      name: 'Sadalmelik',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 331.446,
        decDegrees: -0.3199,
      ),
      magnitude: 2.96,
      spectralType: 'G2Ib',
      constellation: 'AQR',
    ),
    const Star(
      id: 'HIP10826',
      name: 'Mira',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 34.838,
        decDegrees: -2.9776,
      ),
      magnitude: 3.04,
      spectralType: 'M7IIIe',
      constellation: 'CET',
    ),
    const Star(
      id: 'HIP107315',
      name: 'Albireo',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 292.680,
        decDegrees: 27.9597,
      ),
      magnitude: 3.18,
      spectralType: 'K3II',
      constellation: 'CYG',
    ),
    const Star(
      id: 'HIP59774',
      name: 'Megrez',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 183.857,
        decDegrees: 57.0326,
      ),
      magnitude: 3.31,
      spectralType: 'A3V',
      constellation: 'UMA',
    ),
    const Star(
      id: 'HIP6686',
      name: 'Segin',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 28.598,
        decDegrees: 63.6700,
      ),
      magnitude: 3.37,
      spectralType: 'B3III',
      constellation: 'CAS',
    ),
    const Star(
      id: 'HIP9487',
      name: 'Eta Piscium',
      coordinates: CelestialCoordinate.fromDegrees(
        raDegrees: 22.880,
        decDegrees: 15.3458,
      ),
      magnitude: 3.62,
      spectralType: 'G7III',
      constellation: 'PSC',
    ),
  ];
}

/// Named star lookup utility
class NamedStars {
  static final HygStarCatalog _catalog = HygStarCatalog(magnitudeLimit: 6.0);
  static Map<String, Star>? _byName;

  static Future<void> _loadIfNeeded() async {
    if (_byName == null) {
      final stars = await _catalog.loadObjects();
      _byName = {
        for (final star in stars)
          if (star.name.isNotEmpty) star.name.toLowerCase(): star,
      };
    }
  }

  static Future<Star?> findByName(String name) async {
    await _loadIfNeeded();
    return _byName?[name.toLowerCase()];
  }

  static Future<List<String>> get allNames async {
    await _loadIfNeeded();
    return _byName?.keys.toList() ?? [];
  }
}

class _LoadStarsArgs {
  final String path;
  final double magnitudeLimit;

  _LoadStarsArgs(this.path, this.magnitudeLimit);
}

/// One parsed HYG row: the [Star] plus the multiple-star bookkeeping that
/// [HygStarCatalog._nameComponentStars] needs and [Star] has no field for.
///
/// [named] is false when the row carried no proper name, Bayer letter or
/// Flamsteed number, so the star's name is currently just its catalogue id.
typedef _HygRow = ({
  Star star,
  int hygId,
  int comp,
  int compPrimary,
  bool named,
});
