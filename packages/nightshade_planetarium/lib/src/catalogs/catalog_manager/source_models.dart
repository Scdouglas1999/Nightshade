part of '../catalog_manager.dart';

// For gzip decompression

/// Calculate angular distance between two points on a sphere (in degrees)
/// Uses the Haversine formula for better numerical stability
double _angularDistance(double ra1, double dec1, double ra2, double dec2) {
  // Convert to radians
  final ra1Rad = ra1 * math.pi / 180.0;
  final dec1Rad = dec1 * math.pi / 180.0;
  final ra2Rad = ra2 * math.pi / 180.0;
  final dec2Rad = dec2 * math.pi / 180.0;

  // Haversine formula
  final dRa = ra2Rad - ra1Rad;
  final dDec = dec2Rad - dec1Rad;

  final a =
      math.sin(dDec / 2) * math.sin(dDec / 2) +
      math.cos(dec1Rad) *
          math.cos(dec2Rad) *
          math.sin(dRa / 2) *
          math.sin(dRa / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  // Return distance in degrees
  return c * 180.0 / math.pi;
}

String _normalizeCatalogSearchText(String value) {
  final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return compact.replaceFirstMapped(
    RegExp(r'^(m|ngc|ic|hip|hd|hyg)0*(\d+)$'),
    (match) => '${match.group(1)}${int.parse(match.group(2)!)}',
  );
}

bool _catalogTextMatches(
  String value,
  String rawQuery,
  String normalizedQuery,
) {
  final rawValue = value.toLowerCase();
  if (rawValue.contains(rawQuery)) return true;
  final normalizedValue = _normalizeCatalogSearchText(value);
  return normalizedQuery.isNotEmpty &&
      (normalizedValue.contains(normalizedQuery) ||
          normalizedQuery.contains(normalizedValue));
}

bool _catalogTextEquals(String value, String rawQuery, String normalizedQuery) {
  return value.toLowerCase() == rawQuery ||
      _normalizeCatalogSearchText(value) == normalizedQuery;
}

/// Available catalog packages with different size/detail levels
enum CatalogPackage {
  /// Essential package: ~10MB
  /// - Stars: magnitude < 6.5 (~9,000 stars)
  /// - DSOs: Messier + NGC objects magnitude < 10 (~2,000 objects)
  essential('Essential', 'Basic catalog for visual observation', 10, 6.5, 10.0),

  /// Standard package: ~30MB
  /// - Stars: magnitude < 8.0 (~40,000 stars)
  /// - DSOs: All NGC + IC objects magnitude < 12 (~8,000 objects)
  standard('Standard', 'Recommended for most users', 30, 8.0, 12.0),

  /// Complete package: ~60MB
  /// - Stars: All HYG stars (~120,000 stars)
  /// - DSOs: All OpenNGC objects (~13,000 objects)
  complete('Complete', 'Full catalogs for advanced users', 60, 15.0, 20.0);

  final String displayName;
  final String description;
  final int approximateSizeMB;
  final double starMagnitudeLimit;
  final double dsoMagnitudeLimit;

  const CatalogPackage(
    this.displayName,
    this.description,
    this.approximateSizeMB,
    this.starMagnitudeLimit,
    this.dsoMagnitudeLimit,
  );
}

/// Catalog source information
class CatalogSource {
  final String name;
  final String description;
  final String version;
  final String downloadUrl;
  final String fileName;
  final String checksumUrl;

  const CatalogSource({
    required this.name,
    required this.description,
    required this.version,
    required this.downloadUrl,
    required this.fileName,
    this.checksumUrl = '',
  });
}

/// HYG Star Database source
/// Hosted at Codeberg: https://codeberg.org/astronexus/hyg
/// Using v4.2 (current version with LFS storage)
const hygStarCatalog = CatalogSource(
  name: 'HYG Star Database',
  description:
      'Combined Hipparcos, Yale Bright Star, and Gliese catalogs with ~120,000 stars',
  version: '4.2',
  // Using /media/ URL for Git LFS files on Codeberg
  downloadUrl:
      'https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v42.csv.gz',
  fileName: 'hyg_v42.csv',
);

/// OpenNGC Deep Sky Object catalog source
/// GitHub: https://github.com/mattiaverga/OpenNGC
const openNgcCatalog = CatalogSource(
  name: 'OpenNGC',
  description:
      'Open source NGC/IC deep sky objects catalog with ~13,000 objects',
  version: '2023.12',
  downloadUrl:
      'https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv',
  fileName: 'NGC.csv',
);

/// Available annotation catalog packages for deep image annotation
/// Uses GLADE+ (Galaxy List for the Advanced Detector Era) via VizieR TAP
enum AnnotationPackage {
  /// Essential package: ~5MB
  /// - Galaxies: B-magnitude ≤ 14 (~50,000 galaxies)
  /// - Good for bright object annotation
  essential(
    'Essential',
    'Bright galaxies (B ≤ 14) for basic annotation',
    5,
    14.0,
  ),

  /// Standard package: ~50MB
  /// - Galaxies: B-magnitude ≤ 17 (~500,000 galaxies)
  /// - Recommended for most astrophotographers
  standard(
    'Standard',
    'Recommended for most astrophotographers (B ≤ 17)',
    50,
    17.0,
  ),

  /// Complete package: ~2GB
  /// - All 22.5M galaxies in GLADE+
  /// - Full deep annotation capability
  complete(
    'Complete',
    'Full GLADE+ catalog - 22.5M galaxies',
    2000,
    99.0, // No magnitude limit
  );

  final String displayName;
  final String description;
  final int approximateSizeMB;
  final double magnitudeLimit;

  const AnnotationPackage(
    this.displayName,
    this.description,
    this.approximateSizeMB,
    this.magnitudeLimit,
  );
}

/// GLADE+ Galaxy Database source
/// Source: https://glade.elte.hu/ via VizieR TAP (VII/291/gladep)
/// Galaxy List for the Advanced Detector Era - 22.5 million galaxies
const gladePlusCatalog = CatalogSource(
  name: 'GLADE+ Galaxy Catalog',
  description: 'Galaxy List for the Advanced Detector Era - 22.5M galaxies',
  version: '2022',
  // URL is constructed dynamically based on selected tier via VizieR TAP
  downloadUrl: '', // Built dynamically using _buildGladePlusUrl()
  fileName: 'glade_plus_galaxies.csv',
);

/// Whether automatic download is available for annotation catalog
/// GLADE+ is always available via VizieR TAP
bool get isAnnotationDownloadAvailable => true;

/// Build VizieR TAP URL for GLADE+ catalog with magnitude filtering
String buildGladePlusUrl(AnnotationPackage package) {
  String query;
  if (package == AnnotationPackage.complete) {
    // Full catalog - no magnitude filter
    // Note: VizieR requires double quotes around column names
    query =
        'SELECT "RAJ2000", "DEJ2000", "Bmag", "zhelio", "PGC" FROM "VII/291/gladep"';
  } else {
    // Filtered by B-magnitude
    // Note: Bmag can be NULL for many entries, so we filter for non-null values
    query =
        'SELECT "RAJ2000", "DEJ2000", "Bmag", "zhelio", "PGC" FROM "VII/291/gladep" '
        'WHERE "Bmag" IS NOT NULL AND "Bmag" <= ${package.magnitudeLimit}';
  }
  return 'https://tapvizier.cds.unistra.fr/TAPVizieR/tap/sync'
      '?REQUEST=doQuery&LANG=ADQL&FORMAT=csv&QUERY=${Uri.encodeComponent(query)}';
}

/// Catalog installation status
class CatalogStatus {
  final bool isInstalled;
  final String? installedPath;
  final DateTime? installedDate;
  final CatalogPackage? installedPackage;
  final int? objectCount;
  final String? version;

  const CatalogStatus({
    required this.isInstalled,
    this.installedPath,
    this.installedDate,
    this.installedPackage,
    this.objectCount,
    this.version,
  });

  factory CatalogStatus.notInstalled() =>
      const CatalogStatus(isInstalled: false);
}

/// Download progress information
class DownloadProgress {
  final String catalogName;
  final double progress; // 0.0 to 1.0
  final int bytesReceived;
  final int totalBytes;
  final String status;
  final bool isComplete;
  final String? error;

  const DownloadProgress({
    required this.catalogName,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
    required this.status,
    this.isComplete = false,
    this.error,
  });

  factory DownloadProgress.starting(String catalogName) => DownloadProgress(
    catalogName: catalogName,
    progress: 0,
    bytesReceived: 0,
    totalBytes: 0,
    status: 'Starting download...',
  );

  factory DownloadProgress.complete(String catalogName, int bytes) =>
      DownloadProgress(
        catalogName: catalogName,
        progress: 1.0,
        bytesReceived: bytes,
        totalBytes: bytes,
        status: 'Complete',
        isComplete: true,
      );

  factory DownloadProgress.error(String catalogName, String error) =>
      DownloadProgress(
        catalogName: catalogName,
        progress: 0,
        bytesReceived: 0,
        totalBytes: 0,
        status: 'Error',
        error: error,
      );
}
