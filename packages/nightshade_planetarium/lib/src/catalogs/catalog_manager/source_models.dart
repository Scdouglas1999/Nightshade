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

/// Compile-time default base URL for the immutable GitHub release that hosts
/// the bulk catalogs as integrity-verified assets. This is the PRIMARY source:
/// third-party upstreams (Codeberg, raw.githubusercontent) are only used as a
/// fallback when a release asset is unreachable.
///
/// Overridable two ways, so a self-hoster/fleet operator can repoint downloads
/// without waiting on a new upstream:
///   * at build time via `--dart-define=NIGHTSHADE_CATALOG_BASE_URL=<url>`, and
///   * at runtime via [CatalogManager.setCatalogBaseUrl] (persisted, no rebuild),
///     mirroring [DeepStarCatalogManager.getBaseUrl]/[setBaseUrl].
///
/// A GitHub release asset's full URL is `<base>/<CatalogSource.githubAssetName>`.
const String kCatalogReleaseBaseUrl = String.fromEnvironment(
  'NIGHTSHADE_CATALOG_BASE_URL',
  defaultValue:
      'https://github.com/Scdouglas1999/Nightshade/releases/download/catalogs-v1',
);

/// Catalog source information.
///
/// Downloads are resolved through an ordered candidate list (see
/// [catalogDownloadCandidates]): the GitHub release asset ([githubAssetName]
/// under [kCatalogReleaseBaseUrl] or a configured override) is tried FIRST,
/// then [downloadUrl] as the upstream fallback. Each candidate's AS-DOWNLOADED
/// bytes are checked against [sha256] before any decompression or parse.
class CatalogSource {
  final String name;
  final String description;
  final String version;

  /// Upstream FALLBACK download URL (the original third-party host). Used only
  /// when the GitHub release asset is unreachable. For gzipped sources this
  /// points at the compressed `.gz` file.
  final String downloadUrl;

  /// Local (materialized) file name under the catalog directory. For gzipped
  /// sources this is the DECOMPRESSED file, not the downloaded `.gz`.
  final String fileName;
  final String checksumUrl;

  /// File name of the immutable GitHub release asset that is the PRIMARY
  /// download source. The full primary URL is `<base>/<githubAssetName>` where
  /// `<base>` is the configured override or [kCatalogReleaseBaseUrl]. Empty
  /// when no release asset exists (e.g. the dynamically-built GLADE+ query).
  final String githubAssetName;

  /// Expected SHA-256 of the AS-DOWNLOADED bytes — the COMPRESSED payload for
  /// gzipped sources — verified before any gunzip/parse so a corrupt or wrong
  /// candidate is rejected and the next candidate is tried. Empty means no
  /// canonical hash is known (e.g. GLADE+) and the check is skipped.
  final String sha256;

  /// Whether the as-downloaded payload is gzip-compressed.
  final bool isGzipped;

  const CatalogSource({
    required this.name,
    required this.description,
    required this.version,
    required this.downloadUrl,
    required this.fileName,
    this.checksumUrl = '',
    this.githubAssetName = '',
    this.sha256 = '',
    this.isGzipped = false,
  });
}

/// HYG Star Database source.
///
/// PRIMARY: the immutable `hyg_v44.csv.gz` GitHub release asset.
/// FALLBACK: Codeberg Git-LFS `/media/` content URL (v44). NOTE: this MUST be
/// the `/media/` URL, not `/raw/` (which returns a 133-byte LFS pointer). The
/// old v42 `/raw`/`/media` URL is dead (upstream rolled to v44) and is gone.
const hygStarCatalog = CatalogSource(
  name: 'HYG Star Database',
  description:
      'Combined Hipparcos, Yale Bright Star, and Gliese catalogs with ~120,000 stars',
  version: '4.4',
  githubAssetName: 'hyg_v44.csv.gz',
  // SHA-256 of the AS-DOWNLOADED (gzipped) bytes.
  sha256: '00b349893b9a53106dd488d8371e8d2fa586043e500bb3cdb8bff3931682197d',
  // Upstream fallback: /media/ LFS-content URL for v44 on Codeberg.
  downloadUrl:
      'https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v44.csv.gz',
  fileName: 'hyg_v44.csv',
  isGzipped: true,
);

/// OpenNGC Deep Sky Object catalog source.
///
/// PRIMARY: the immutable `NGC.csv` GitHub release asset.
/// FALLBACK: mattiaverga/OpenNGC `master` on raw.githubusercontent.com.
const openNgcCatalog = CatalogSource(
  name: 'OpenNGC',
  description:
      'Open source NGC/IC deep sky objects catalog with ~13,000 objects',
  version: '2023.12',
  githubAssetName: 'NGC.csv',
  sha256: '840fe0c9ee1332e551b2e722a0e92726cd7b157914a3d2177602832aadd3aa9e',
  downloadUrl:
      'https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv',
  fileName: 'NGC.csv',
  isGzipped: false,
);

/// Ordered list of URLs to try when downloading a catalog: the GitHub release
/// asset FIRST (built from [baseUrl] + [githubAssetName]), then the upstream
/// [upstreamUrl] fallback. [baseUrl] is the resolved release base (a persisted
/// override, or [kCatalogReleaseBaseUrl]).
///
/// Empty entries and duplicates are dropped, so a source with no release asset
/// (e.g. the dynamically-built GLADE+ query) collapses to just its upstream.
List<String> catalogDownloadCandidates({
  required String githubAssetName,
  required String upstreamUrl,
  required String baseUrl,
}) {
  final candidates = <String>[];
  final base = baseUrl.trim();
  final asset = githubAssetName.trim();
  if (asset.isNotEmpty && base.isNotEmpty) {
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    candidates.add('$normalized/$asset');
  }
  final upstream = upstreamUrl.trim();
  if (upstream.isNotEmpty && !candidates.contains(upstream)) {
    candidates.add(upstream);
  }
  return candidates;
}

/// [catalogDownloadCandidates] for a [CatalogSource].
List<String> resolveCatalogDownloadCandidates(
  CatalogSource source, {
  required String baseUrl,
}) => catalogDownloadCandidates(
  githubAssetName: source.githubAssetName,
  upstreamUrl: source.downloadUrl,
  baseUrl: baseUrl,
);

/// Whether [actualSha256] satisfies a catalog's [expectedSha256]
/// (case-insensitive). An empty [expectedSha256] means "no canonical hash
/// known" (e.g. GLADE+) and always matches.
bool catalogSha256Matches(String expectedSha256, String actualSha256) {
  final expected = expectedSha256.trim();
  if (expected.isEmpty) return true;
  return actualSha256.toLowerCase() == expected.toLowerCase();
}

/// Whether [bytes] (the AS-DOWNLOADED payload) satisfy a catalog's
/// [expectedSha256]. Used by the download path to reject a candidate whose
/// bytes don't match BEFORE any decompression/parse.
bool catalogBytesMatchSha256(String expectedSha256, List<int> bytes) {
  final expected = expectedSha256.trim();
  if (expected.isEmpty) return true;
  return catalogSha256Matches(expected, sha256.convert(bytes).toString());
}

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

  /// Size of the installed catalog file on disk, in bytes. Null when not
  /// installed or unknown.
  final int? fileSizeBytes;

  const CatalogStatus({
    required this.isInstalled,
    this.installedPath,
    this.installedDate,
    this.installedPackage,
    this.objectCount,
    this.version,
    this.fileSizeBytes,
  });

  factory CatalogStatus.notInstalled() =>
      const CatalogStatus(isInstalled: false);
}

/// Download progress information
class DownloadProgress {
  final String catalogName;

  /// Stable identity of the catalog being downloaded (`stars`, `dso`,
  /// `annotation`). Lets a UI attribute progress to a specific card and lets
  /// [CatalogManager.activeDownloads] key in-flight downloads, where
  /// [catalogName] is only a human-facing label.
  final String? catalogKey;
  final double progress; // 0.0 to 1.0
  final int bytesReceived;
  final int totalBytes;
  final String status;
  final bool isComplete;

  /// True when the download was deliberately cancelled by the user (as opposed
  /// to failing). Terminal, but not an error — the UI should treat it quietly.
  final bool cancelled;
  final String? error;

  const DownloadProgress({
    required this.catalogName,
    this.catalogKey,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
    required this.status,
    this.isComplete = false,
    this.cancelled = false,
    this.error,
  });

  /// Whether this update is a terminal one (success, cancellation, or failure)
  /// — i.e. the download is no longer in flight.
  bool get isTerminal => isComplete || cancelled || error != null;

  factory DownloadProgress.starting(String catalogName, {String? catalogKey}) =>
      DownloadProgress(
        catalogName: catalogName,
        catalogKey: catalogKey,
        progress: 0,
        bytesReceived: 0,
        totalBytes: 0,
        status: 'Starting download...',
      );

  factory DownloadProgress.complete(
    String catalogName,
    int bytes, {
    String? catalogKey,
  }) => DownloadProgress(
    catalogName: catalogName,
    catalogKey: catalogKey,
    progress: 1.0,
    bytesReceived: bytes,
    totalBytes: bytes,
    status: 'Complete',
    isComplete: true,
  );

  factory DownloadProgress.cancelled(
    String catalogName, {
    String? catalogKey,
  }) => DownloadProgress(
    catalogName: catalogName,
    catalogKey: catalogKey,
    progress: 0,
    bytesReceived: 0,
    totalBytes: 0,
    status: 'Cancelled',
    cancelled: true,
  );

  factory DownloadProgress.error(
    String catalogName,
    String error, {
    String? catalogKey,
  }) => DownloadProgress(
    catalogName: catalogName,
    catalogKey: catalogKey,
    progress: 0,
    bytesReceived: 0,
    totalBytes: 0,
    status: 'Error',
    error: error,
  );
}
