import 'dart:io';
import 'dart:convert';
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
  
  /// Create a star catalog
  /// 
  /// [catalogPath] - Path to the HYG CSV file, or null to use CatalogManager
  /// [magnitudeLimit] - Maximum magnitude to load (fainter stars have higher values)
  HygStarCatalog({
    this.catalogPath,
    this.magnitudeLimit = 15.0,
  });
  
  @override
  String get name => 'HYG Database';
  
  /// Check if catalog data is available
  Future<bool> get isAvailable async {
    final path = catalogPath ?? CatalogManager.instance.starCatalogPath;
    return File(path).exists();
  }
  
  /// Get the number of loaded stars
  int get starCount => _cachedStars?.length ?? 0;
  
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
        _cachedStars = _fallbackBrightStars;
        return _cachedStars!;
      }
      
      // Use compute to load in background isolate
      try {
        final stars = await compute(_loadStarsInIsolate, _LoadStarsArgs(path, magnitudeLimit));
        _cachedStars = stars;
        return stars;
      } catch (e) {
        print('Error loading stars in isolate: $e');
        return [];
      }
    } finally {
      _isLoading = false;
    }
  }

  static Future<List<Star>> _loadStarsInIsolate(_LoadStarsArgs args) async {
    final file = File(args.path);
    if (!file.existsSync()) return [];
    
    final stars = <Star>[];
    final stream = file.openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
        
    var isHeader = true;
    await for (final line in stream) {
      if (isHeader) {
        isHeader = false;
        continue;
      }
      
      try {
        final star = _parseHygLine(line);
        if (star != null && (star.magnitude ?? 99) <= args.magnitudeLimit) {
          stars.add(star);
        }
      } catch (_) {
        // Skip malformed lines
      }
    }
    
    // Sort by magnitude (brightest first)
    stars.sort((a, b) => 
      (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));
      
    return stars;
  }
  
  /// Parse a line from the HYG CSV file
  /// HYG v3.8 format columns:
  /// 0:id, 1:hip, 2:hd, 3:hr, 4:gl, 5:bf, 6:proper, 7:ra, 8:dec, 9:dist,
  /// 10:pmra, 11:pmdec, 12:rv, 13:mag, 14:absmag, 15:spect, 16:ci,
  /// 17:x, 18:y, 19:z, 20:vx, 21:vy, 22:vz, 23:rarad, 24:decrad,
  /// 25:pmrarad, 26:pmdecrad, 27:bayer, 28:flam, 29:con, ...
  static Star? _parseHygLine(String line) {
    final parts = _parseCsvLine(line);
    if (parts.length < 30) return null;
    
    final hygId = int.tryParse(parts[0]) ?? 0;
    final hipId = int.tryParse(parts[1]);
    final hdId = int.tryParse(parts[2]);
    final hrId = int.tryParse(parts[3]);
    final properName = parts.length > 6 ? parts[6] : '';
    final raHours = double.tryParse(parts[7]) ?? 0;
    final dec = double.tryParse(parts[8]) ?? 0;
    final magnitude = double.tryParse(parts[13]);
    final spectralType = parts.length > 15 ? parts[15] : null;
    final colorIndex = parts.length > 16 ? double.tryParse(parts[16]) : null;
    final bayerDesignation = parts.length > 27 ? parts[27] : null;
    final flamsteedNumber = parts.length > 28 ? parts[28] : null;
    final constellation = parts.length > 29 ? parts[29] : null;
    
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
    if (starName.isEmpty && bayerDesignation != null && bayerDesignation.isNotEmpty) {
      starName = '$bayerDesignation ${_getConstellationGenitive(constellation ?? '')}';
    }
    if (starName.isEmpty && flamsteedNumber != null && flamsteedNumber.isNotEmpty) {
      starName = '$flamsteedNumber ${_getConstellationName(constellation ?? '')}';
    }
    if (starName.isEmpty) {
      starName = id;
    }
    
    // Build alternate catalog IDs
    final catalogIds = <String>[];
    if (hipId != null && hipId > 0) catalogIds.add('HIP $hipId');
    if (hdId != null && hdId > 0) catalogIds.add('HD $hdId');
    if (hrId != null && hrId > 0) catalogIds.add('HR $hrId');
    
    return Star(
      id: id,
      name: starName.trim(),
      coordinates: CelestialCoordinate(
        ra: raHours * 15, // Convert hours to degrees
        dec: dec,
      ),
      magnitude: magnitude,
      spectralType: spectralType?.isNotEmpty == true ? spectralType : null,
      colorIndex: colorIndex,
      constellation: constellation?.isNotEmpty == true ? constellation : null,
      catalogIds: catalogIds,
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
      return s.catalogIds.any((c) => 
        c.toUpperCase().replaceAll(' ', '') == normalizedId);
    }).firstOrNull;
  }
  
  @override
  Future<List<Star>> search(String query) async {
    final q = query.toLowerCase();
    final stars = await loadObjects();
    
    return stars.where((s) => 
      s.name.toLowerCase().contains(q) ||
      s.id.toLowerCase().contains(q) ||
      (s.constellation?.toLowerCase().contains(q) ?? false) ||
      s.catalogIds.any((c) => c.toLowerCase().contains(q))
    ).toList();
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
    return stars.where((s) => 
      s.constellation?.toLowerCase() == conAbbr.toLowerCase() ||
      s.constellation?.toLowerCase() == constellation.toLowerCase()
    ).toList();
  }
  
  /// Get stars near a position (cone search)
  Future<List<Star>> getStarsNear(
    CelestialCoordinate center,
    double radiusDegrees, {
    double? maxMagnitude,
  }) async {
    final stars = await loadObjects();
    
    return stars.where((s) {
      if (maxMagnitude != null && (s.magnitude ?? 99) > maxMagnitude) {
        return false;
      }
      
      // Simple angular distance (good enough for small radii)
      final dRa = (s.coordinates.ra - center.ra).abs();
      final dDec = (s.coordinates.dec - center.dec).abs();
      final approxDist = dRa * dRa + dDec * dDec;
      
      return approxDist <= radiusDegrees * radiusDegrees;
    }).toList();
  }
  
  /// Clear the cache
  void clearCache() {
    _cachedStars = null;
  }
  
  /// Convert constellation name to genitive form (for Bayer designations)
  static String _getConstellationGenitive(String constellation) {
    return _constellationGenitives[constellation.toUpperCase()] ?? constellation;
  }
  
  /// Get full constellation name from abbreviation
  static String _getConstellationName(String abbr) {
    return _constellationNames[abbr.toUpperCase()] ?? abbr;
  }
  
  /// Get constellation abbreviation from full name
  static String _getConstellationAbbr(String name) {
    final entry = _constellationNames.entries.where(
      (e) => e.value.toLowerCase() == name.toLowerCase()
    ).firstOrNull;
    return entry?.key ?? name;
  }
  
  static const Map<String, String> _constellationGenitives = {
    'AND': 'Andromedae', 'ANT': 'Antliae', 'APS': 'Apodis', 'AQR': 'Aquarii',
    'AQL': 'Aquilae', 'ARA': 'Arae', 'ARI': 'Arietis', 'AUR': 'Aurigae',
    'BOO': 'Bootis', 'CAE': 'Caeli', 'CAM': 'Camelopardalis', 'CNC': 'Cancri',
    'CVN': 'Canum Venaticorum', 'CMA': 'Canis Majoris', 'CMI': 'Canis Minoris',
    'CAP': 'Capricorni', 'CAR': 'Carinae', 'CAS': 'Cassiopeiae', 'CEN': 'Centauri',
    'CEP': 'Cephei', 'CET': 'Ceti', 'CHA': 'Chamaeleontis', 'CIR': 'Circini',
    'COL': 'Columbae', 'COM': 'Comae Berenices', 'CRA': 'Coronae Australis',
    'CRB': 'Coronae Borealis', 'CRV': 'Corvi', 'CRT': 'Crateris', 'CRU': 'Crucis',
    'CYG': 'Cygni', 'DEL': 'Delphini', 'DOR': 'Doradus', 'DRA': 'Draconis',
    'EQU': 'Equulei', 'ERI': 'Eridani', 'FOR': 'Fornacis', 'GEM': 'Geminorum',
    'GRU': 'Gruis', 'HER': 'Herculis', 'HOR': 'Horologii', 'HYA': 'Hydrae',
    'HYI': 'Hydri', 'IND': 'Indi', 'LAC': 'Lacertae', 'LEO': 'Leonis',
    'LMI': 'Leonis Minoris', 'LEP': 'Leporis', 'LIB': 'Librae', 'LUP': 'Lupi',
    'LYN': 'Lyncis', 'LYR': 'Lyrae', 'MEN': 'Mensae', 'MIC': 'Microscopii',
    'MON': 'Monocerotis', 'MUS': 'Muscae', 'NOR': 'Normae', 'OCT': 'Octantis',
    'OPH': 'Ophiuchi', 'ORI': 'Orionis', 'PAV': 'Pavonis', 'PEG': 'Pegasi',
    'PER': 'Persei', 'PHE': 'Phoenicis', 'PIC': 'Pictoris', 'PSC': 'Piscium',
    'PSA': 'Piscis Austrini', 'PUP': 'Puppis', 'PYX': 'Pyxidis', 'RET': 'Reticuli',
    'SGE': 'Sagittae', 'SGR': 'Sagittarii', 'SCO': 'Scorpii', 'SCL': 'Sculptoris',
    'SCT': 'Scuti', 'SER': 'Serpentis', 'SEX': 'Sextantis', 'TAU': 'Tauri',
    'TEL': 'Telescopii', 'TRA': 'Trianguli Australis', 'TRI': 'Trianguli',
    'TUC': 'Tucanae', 'UMA': 'Ursae Majoris', 'UMI': 'Ursae Minoris',
    'VEL': 'Velorum', 'VIR': 'Virginis', 'VOL': 'Volantis', 'VUL': 'Vulpeculae',
  };
  
  static const Map<String, String> _constellationNames = {
    'AND': 'Andromeda', 'ANT': 'Antlia', 'APS': 'Apus', 'AQR': 'Aquarius',
    'AQL': 'Aquila', 'ARA': 'Ara', 'ARI': 'Aries', 'AUR': 'Auriga',
    'BOO': 'Boötes', 'CAE': 'Caelum', 'CAM': 'Camelopardalis', 'CNC': 'Cancer',
    'CVN': 'Canes Venatici', 'CMA': 'Canis Major', 'CMI': 'Canis Minor',
    'CAP': 'Capricornus', 'CAR': 'Carina', 'CAS': 'Cassiopeia', 'CEN': 'Centaurus',
    'CEP': 'Cepheus', 'CET': 'Cetus', 'CHA': 'Chamaeleon', 'CIR': 'Circinus',
    'COL': 'Columba', 'COM': 'Coma Berenices', 'CRA': 'Corona Australis',
    'CRB': 'Corona Borealis', 'CRV': 'Corvus', 'CRT': 'Crater', 'CRU': 'Crux',
    'CYG': 'Cygnus', 'DEL': 'Delphinus', 'DOR': 'Dorado', 'DRA': 'Draco',
    'EQU': 'Equuleus', 'ERI': 'Eridanus', 'FOR': 'Fornax', 'GEM': 'Gemini',
    'GRU': 'Grus', 'HER': 'Hercules', 'HOR': 'Horologium', 'HYA': 'Hydra',
    'HYI': 'Hydrus', 'IND': 'Indus', 'LAC': 'Lacerta', 'LEO': 'Leo',
    'LMI': 'Leo Minor', 'LEP': 'Lepus', 'LIB': 'Libra', 'LUP': 'Lupus',
    'LYN': 'Lynx', 'LYR': 'Lyra', 'MEN': 'Mensa', 'MIC': 'Microscopium',
    'MON': 'Monoceros', 'MUS': 'Musca', 'NOR': 'Norma', 'OCT': 'Octans',
    'OPH': 'Ophiuchus', 'ORI': 'Orion', 'PAV': 'Pavo', 'PEG': 'Pegasus',
    'PER': 'Perseus', 'PHE': 'Phoenix', 'PIC': 'Pictor', 'PSC': 'Pisces',
    'PSA': 'Piscis Austrinus', 'PUP': 'Puppis', 'PYX': 'Pyxis', 'RET': 'Reticulum',
    'SGE': 'Sagitta', 'SGR': 'Sagittarius', 'SCO': 'Scorpius', 'SCL': 'Sculptor',
    'SCT': 'Scutum', 'SER': 'Serpens', 'SEX': 'Sextans', 'TAU': 'Taurus',
    'TEL': 'Telescopium', 'TRA': 'Triangulum Australe', 'TRI': 'Triangulum',
    'TUC': 'Tucana', 'UMA': 'Ursa Major', 'UMI': 'Ursa Minor',
    'VEL': 'Vela', 'VIR': 'Virgo', 'VOL': 'Volans', 'VUL': 'Vulpecula',
  };
  
  /// Fallback bright stars when catalog is not installed
  /// Contains ~100 brightest/most important stars for basic functionality
  static final List<Star> _fallbackBrightStars = [
    // Magnitude < 0
    Star(id: 'HIP32349', name: 'Sirius', coordinates: CelestialCoordinate(ra: 101.286, dec: -16.7161), magnitude: -1.46, spectralType: 'A1V', constellation: 'CMA'),
    Star(id: 'HIP30438', name: 'Canopus', coordinates: CelestialCoordinate(ra: 95.985, dec: -52.6957), magnitude: -0.72, spectralType: 'F0II', constellation: 'CAR'),
    Star(id: 'HIP71683', name: 'Rigil Kentaurus', coordinates: CelestialCoordinate(ra: 219.899, dec: -60.8354), magnitude: -0.29, spectralType: 'G2V', constellation: 'CEN'),
    Star(id: 'HIP69673', name: 'Arcturus', coordinates: CelestialCoordinate(ra: 213.918, dec: 19.1825), magnitude: -0.05, spectralType: 'K1.5III', constellation: 'BOO'),
    
    // Magnitude 0-1
    Star(id: 'HIP91262', name: 'Vega', coordinates: CelestialCoordinate(ra: 279.234, dec: 38.7837), magnitude: 0.03, spectralType: 'A0V', constellation: 'LYR'),
    Star(id: 'HIP24608', name: 'Capella', coordinates: CelestialCoordinate(ra: 79.176, dec: 45.9980), magnitude: 0.08, spectralType: 'G8III', constellation: 'AUR'),
    Star(id: 'HIP24436', name: 'Rigel', coordinates: CelestialCoordinate(ra: 78.633, dec: -8.2017), magnitude: 0.13, spectralType: 'B8Ia', constellation: 'ORI'),
    Star(id: 'HIP37279', name: 'Procyon', coordinates: CelestialCoordinate(ra: 114.828, dec: 5.2250), magnitude: 0.34, spectralType: 'F5IV', constellation: 'CMI'),
    Star(id: 'HIP27989', name: 'Betelgeuse', coordinates: CelestialCoordinate(ra: 88.793, dec: 7.4070), magnitude: 0.42, spectralType: 'M2Ib', constellation: 'ORI'),
    Star(id: 'HIP7588', name: 'Achernar', coordinates: CelestialCoordinate(ra: 24.428, dec: -57.2367), magnitude: 0.46, spectralType: 'B3V', constellation: 'ERI'),
    Star(id: 'HIP80763', name: 'Hadar', coordinates: CelestialCoordinate(ra: 210.956, dec: -60.3730), magnitude: 0.60, spectralType: 'B1III', constellation: 'CEN'),
    Star(id: 'HIP97649', name: 'Altair', coordinates: CelestialCoordinate(ra: 297.696, dec: 8.8683), magnitude: 0.77, spectralType: 'A7V', constellation: 'AQL'),
    Star(id: 'HIP60718', name: 'Acrux', coordinates: CelestialCoordinate(ra: 186.650, dec: -63.0990), magnitude: 0.76, spectralType: 'B0.5IV', constellation: 'CRU'),
    Star(id: 'HIP21421', name: 'Aldebaran', coordinates: CelestialCoordinate(ra: 68.982, dec: 16.5093), magnitude: 0.85, spectralType: 'K5III', constellation: 'TAU'),
    Star(id: 'HIP80763', name: 'Antares', coordinates: CelestialCoordinate(ra: 247.352, dec: -26.4320), magnitude: 1.06, spectralType: 'M1.5Ib', constellation: 'SCO'),
    Star(id: 'HIP65474', name: 'Spica', coordinates: CelestialCoordinate(ra: 201.298, dec: -11.1614), magnitude: 0.97, spectralType: 'B1V', constellation: 'VIR'),
    Star(id: 'HIP37826', name: 'Pollux', coordinates: CelestialCoordinate(ra: 116.330, dec: 28.0262), magnitude: 1.14, spectralType: 'K0III', constellation: 'GEM'),
    Star(id: 'HIP102098', name: 'Fomalhaut', coordinates: CelestialCoordinate(ra: 344.412, dec: -29.6223), magnitude: 1.16, spectralType: 'A3V', constellation: 'PSA'),
    Star(id: 'HIP102488', name: 'Deneb', coordinates: CelestialCoordinate(ra: 310.358, dec: 45.2803), magnitude: 1.25, spectralType: 'A2Ia', constellation: 'CYG'),
    Star(id: 'HIP62434', name: 'Mimosa', coordinates: CelestialCoordinate(ra: 191.930, dec: -59.6888), magnitude: 1.25, spectralType: 'B0.5IV', constellation: 'CRU'),
    Star(id: 'HIP54061', name: 'Regulus', coordinates: CelestialCoordinate(ra: 152.093, dec: 11.9672), magnitude: 1.40, spectralType: 'B8IV', constellation: 'LEO'),
    Star(id: 'HIP31592', name: 'Adhara', coordinates: CelestialCoordinate(ra: 104.656, dec: -28.9722), magnitude: 1.50, spectralType: 'B2II', constellation: 'CMA'),
    Star(id: 'HIP36850', name: 'Castor', coordinates: CelestialCoordinate(ra: 113.650, dec: 31.8884), magnitude: 1.58, spectralType: 'A1V', constellation: 'GEM'),
    Star(id: 'HIP78820', name: 'Shaula', coordinates: CelestialCoordinate(ra: 263.402, dec: -37.1038), magnitude: 1.63, spectralType: 'B2IV', constellation: 'SCO'),
    Star(id: 'HIP63003', name: 'Gacrux', coordinates: CelestialCoordinate(ra: 187.791, dec: -57.1132), magnitude: 1.64, spectralType: 'M3.5III', constellation: 'CRU'),
    Star(id: 'HIP41037', name: 'Miaplacidus', coordinates: CelestialCoordinate(ra: 138.300, dec: -69.7172), magnitude: 1.68, spectralType: 'A1III', constellation: 'CAR'),
    Star(id: 'HIP25336', name: 'Bellatrix', coordinates: CelestialCoordinate(ra: 81.282, dec: 6.3497), magnitude: 1.64, spectralType: 'B2III', constellation: 'ORI'),
    Star(id: 'HIP27366', name: 'Elnath', coordinates: CelestialCoordinate(ra: 81.573, dec: 28.6074), magnitude: 1.65, spectralType: 'B7III', constellation: 'TAU'),
    Star(id: 'HIP26311', name: 'Alnilam', coordinates: CelestialCoordinate(ra: 84.054, dec: -1.2019), magnitude: 1.70, spectralType: 'B0Ia', constellation: 'ORI'),
    
    // Important navigation and constellation stars
    Star(id: 'HIP11767', name: 'Polaris', coordinates: CelestialCoordinate(ra: 37.953, dec: 89.2641), magnitude: 1.98, spectralType: 'F7Ib', constellation: 'UMI'),
    Star(id: 'HIP26727', name: 'Alnitak', coordinates: CelestialCoordinate(ra: 85.190, dec: -1.9426), magnitude: 1.77, spectralType: 'O9.7Ib', constellation: 'ORI'),
    Star(id: 'HIP15863', name: 'Mirfak', coordinates: CelestialCoordinate(ra: 51.081, dec: 49.8612), magnitude: 1.79, spectralType: 'F5Ib', constellation: 'PER'),
    Star(id: 'HIP59774', name: 'Dubhe', coordinates: CelestialCoordinate(ra: 165.932, dec: 61.7510), magnitude: 1.79, spectralType: 'K0III', constellation: 'UMA'),
    Star(id: 'HIP90185', name: 'Kaus Australis', coordinates: CelestialCoordinate(ra: 276.044, dec: -34.3847), magnitude: 1.80, spectralType: 'B9.5III', constellation: 'SGR'),
    Star(id: 'HIP65378', name: 'Alioth', coordinates: CelestialCoordinate(ra: 193.506, dec: 55.9598), magnitude: 1.77, spectralType: 'A0p', constellation: 'UMA'),
    Star(id: 'HIP62956', name: 'Alkaid', coordinates: CelestialCoordinate(ra: 206.885, dec: 49.3133), magnitude: 1.86, spectralType: 'B3V', constellation: 'UMA'),
    Star(id: 'HIP31681', name: 'Alhena', coordinates: CelestialCoordinate(ra: 99.428, dec: 16.3993), magnitude: 1.93, spectralType: 'A0IV', constellation: 'GEM'),
    Star(id: 'HIP82273', name: 'Atria', coordinates: CelestialCoordinate(ra: 252.164, dec: -69.0277), magnitude: 1.92, spectralType: 'K2IIb', constellation: 'TRA'),
    Star(id: 'HIP46390', name: 'Alphard', coordinates: CelestialCoordinate(ra: 141.896, dec: -8.6586), magnitude: 1.98, spectralType: 'K3III', constellation: 'HYA'),
    Star(id: 'HIP9884', name: 'Hamal', coordinates: CelestialCoordinate(ra: 31.794, dec: 23.4624), magnitude: 2.00, spectralType: 'K2III', constellation: 'ARI'),
    Star(id: 'HIP14135', name: 'Diphda', coordinates: CelestialCoordinate(ra: 10.898, dec: -17.9866), magnitude: 2.02, spectralType: 'K0III', constellation: 'CET'),
    Star(id: 'HIP89931', name: 'Nunki', coordinates: CelestialCoordinate(ra: 283.816, dec: -26.2967), magnitude: 2.02, spectralType: 'B2.5V', constellation: 'SGR'),
    Star(id: 'HIP677', name: 'Alpheratz', coordinates: CelestialCoordinate(ra: 2.097, dec: 29.0904), magnitude: 2.06, spectralType: 'B9p', constellation: 'AND'),
    Star(id: 'HIP1067', name: 'Mirach', coordinates: CelestialCoordinate(ra: 17.432, dec: 35.6206), magnitude: 2.06, spectralType: 'M0III', constellation: 'AND'),
    Star(id: 'HIP86032', name: 'Rasalhague', coordinates: CelestialCoordinate(ra: 263.735, dec: 12.5600), magnitude: 2.07, spectralType: 'A5III', constellation: 'OPH'),
    Star(id: 'HIP14576', name: 'Algol', coordinates: CelestialCoordinate(ra: 47.046, dec: 40.9557), magnitude: 2.12, spectralType: 'B8V', constellation: 'PER'),
    Star(id: 'HIP49669', name: 'Denebola', coordinates: CelestialCoordinate(ra: 177.266, dec: 14.5720), magnitude: 2.13, spectralType: 'A3V', constellation: 'LEO'),
    Star(id: 'HIP44816', name: 'Suhail', coordinates: CelestialCoordinate(ra: 137.000, dec: -43.4326), magnitude: 2.21, spectralType: 'K4Ib', constellation: 'VEL'),
    Star(id: 'HIP3419', name: 'Schedar', coordinates: CelestialCoordinate(ra: 10.128, dec: 56.5373), magnitude: 2.23, spectralType: 'K0II', constellation: 'CAS'),
    Star(id: 'HIP76267', name: 'Alphecca', coordinates: CelestialCoordinate(ra: 233.673, dec: 26.7147), magnitude: 2.23, spectralType: 'A0V', constellation: 'CRB'),
    Star(id: 'HIP87833', name: 'Eltanin', coordinates: CelestialCoordinate(ra: 269.150, dec: 51.4889), magnitude: 2.23, spectralType: 'K5III', constellation: 'DRA'),
    Star(id: 'HIP25930', name: 'Mintaka', coordinates: CelestialCoordinate(ra: 83.002, dec: -0.2991), magnitude: 2.23, spectralType: 'O9.5II', constellation: 'ORI'),
    Star(id: 'HIP5447', name: 'Almach', coordinates: CelestialCoordinate(ra: 30.975, dec: 42.3297), magnitude: 2.26, spectralType: 'K3II', constellation: 'AND'),
    Star(id: 'HIP39757', name: 'Naos', coordinates: CelestialCoordinate(ra: 120.891, dec: -40.0033), magnitude: 2.25, spectralType: 'O5If', constellation: 'PUP'),
    Star(id: 'HIP67301', name: 'Mizar', coordinates: CelestialCoordinate(ra: 200.982, dec: 54.9254), magnitude: 2.27, spectralType: 'A1V', constellation: 'UMA'),
    Star(id: 'HIP4427', name: 'Caph', coordinates: CelestialCoordinate(ra: 2.295, dec: 59.1498), magnitude: 2.27, spectralType: 'F2III', constellation: 'CAS'),
    Star(id: 'HIP53910', name: 'Merak', coordinates: CelestialCoordinate(ra: 165.459, dec: 56.3824), magnitude: 2.37, spectralType: 'A1V', constellation: 'UMA'),
    Star(id: 'HIP113368', name: 'Scheat', coordinates: CelestialCoordinate(ra: 345.944, dec: 28.0828), magnitude: 2.42, spectralType: 'M2.5II', constellation: 'PEG'),
    Star(id: 'HIP58001', name: 'Phecda', coordinates: CelestialCoordinate(ra: 178.452, dec: 53.6948), magnitude: 2.44, spectralType: 'A0V', constellation: 'UMA'),
    Star(id: 'HIP105199', name: 'Alderamin', coordinates: CelestialCoordinate(ra: 319.644, dec: 62.5856), magnitude: 2.44, spectralType: 'A7IV', constellation: 'CEP'),
    Star(id: 'HIP8886', name: 'Navi', coordinates: CelestialCoordinate(ra: 14.180, dec: 60.7167), magnitude: 2.47, spectralType: 'B0IV', constellation: 'CAS'),
    Star(id: 'HIP113881', name: 'Markab', coordinates: CelestialCoordinate(ra: 346.197, dec: 15.2053), magnitude: 2.49, spectralType: 'A0IV', constellation: 'PEG'),
    Star(id: 'HIP8645', name: 'Menkar', coordinates: CelestialCoordinate(ra: 45.573, dec: 4.0897), magnitude: 2.53, spectralType: 'M1.5III', constellation: 'CET'),
    Star(id: 'HIP88635', name: 'Ascella', coordinates: CelestialCoordinate(ra: 285.656, dec: -29.8801), magnitude: 2.59, spectralType: 'A2IV', constellation: 'SGR'),
    Star(id: 'HIP61084', name: 'Gienah', coordinates: CelestialCoordinate(ra: 183.951, dec: -17.5419), magnitude: 2.59, spectralType: 'B8III', constellation: 'CRV'),
    Star(id: 'HIP8903', name: 'Sheratan', coordinates: CelestialCoordinate(ra: 28.659, dec: 20.8080), magnitude: 2.64, spectralType: 'A5V', constellation: 'ARI'),
    Star(id: 'HIP77070', name: 'Unukalhai', coordinates: CelestialCoordinate(ra: 236.065, dec: 6.4256), magnitude: 2.65, spectralType: 'K2III', constellation: 'SER'),
    Star(id: 'HIP746', name: 'Ruchbah', coordinates: CelestialCoordinate(ra: 21.459, dec: 60.2352), magnitude: 2.68, spectralType: 'A5IV', constellation: 'CAS'),
    Star(id: 'HIP59747', name: 'Imai', coordinates: CelestialCoordinate(ra: 183.786, dec: -58.7489), magnitude: 2.77, spectralType: 'B2IV', constellation: 'CRU'),
    Star(id: 'HIP84345', name: 'Kornephoros', coordinates: CelestialCoordinate(ra: 247.557, dec: 21.4897), magnitude: 2.77, spectralType: 'G7IIIa', constellation: 'HER'),
    Star(id: 'HIP83207', name: 'Rasalgethi', coordinates: CelestialCoordinate(ra: 258.662, dec: 14.3902), magnitude: 2.81, spectralType: 'M5Ib', constellation: 'HER'),
    Star(id: 'HIP112158', name: 'Algenib', coordinates: CelestialCoordinate(ra: 3.302, dec: 15.1836), magnitude: 2.83, spectralType: 'B2IV', constellation: 'PEG'),
    Star(id: 'HIP109074', name: 'Sadalsuud', coordinates: CelestialCoordinate(ra: 322.890, dec: -5.5712), magnitude: 2.91, spectralType: 'G0Ib', constellation: 'AQR'),
    Star(id: 'HIP109139', name: 'Sadalmelik', coordinates: CelestialCoordinate(ra: 331.446, dec: -0.3199), magnitude: 2.96, spectralType: 'G2Ib', constellation: 'AQR'),
    Star(id: 'HIP10826', name: 'Mira', coordinates: CelestialCoordinate(ra: 34.838, dec: -2.9776), magnitude: 3.04, spectralType: 'M7IIIe', constellation: 'CET'),
    Star(id: 'HIP107315', name: 'Albireo', coordinates: CelestialCoordinate(ra: 292.680, dec: 27.9597), magnitude: 3.18, spectralType: 'K3II', constellation: 'CYG'),
    Star(id: 'HIP59774', name: 'Megrez', coordinates: CelestialCoordinate(ra: 183.857, dec: 57.0326), magnitude: 3.31, spectralType: 'A3V', constellation: 'UMA'),
    Star(id: 'HIP6686', name: 'Segin', coordinates: CelestialCoordinate(ra: 28.598, dec: 63.6700), magnitude: 3.37, spectralType: 'B3III', constellation: 'CAS'),
    Star(id: 'HIP9487', name: 'Eta Piscium', coordinates: CelestialCoordinate(ra: 22.880, dec: 15.3458), magnitude: 3.62, spectralType: 'G7III', constellation: 'PSC'),
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
