import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

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

  final a = math.sin(dDec / 2) * math.sin(dDec / 2) +
      math.cos(dec1Rad) * math.cos(dec2Rad) *
      math.sin(dRa / 2) * math.sin(dRa / 2);

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

bool _catalogTextMatches(String value, String rawQuery, String normalizedQuery) {
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
  essential(
    'Essential',
    'Basic catalog for visual observation',
    10,
    6.5,
    10.0,
  ),
  
  /// Standard package: ~30MB
  /// - Stars: magnitude < 8.0 (~40,000 stars)
  /// - DSOs: All NGC + IC objects magnitude < 12 (~8,000 objects)
  standard(
    'Standard',
    'Recommended for most users',
    30,
    8.0,
    12.0,
  ),
  
  /// Complete package: ~60MB
  /// - Stars: All HYG stars (~120,000 stars)
  /// - DSOs: All OpenNGC objects (~13,000 objects)
  complete(
    'Complete',
    'Full catalogs for advanced users',
    60,
    15.0,
    20.0,
  );
  
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
  description: 'Combined Hipparcos, Yale Bright Star, and Gliese catalogs with ~120,000 stars',
  version: '4.2',
  // Using /media/ URL for Git LFS files on Codeberg
  downloadUrl: 'https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v42.csv.gz',
  fileName: 'hyg_v42.csv',
);

/// OpenNGC Deep Sky Object catalog source
/// GitHub: https://github.com/mattiaverga/OpenNGC
const openNgcCatalog = CatalogSource(
  name: 'OpenNGC',
  description: 'Open source NGC/IC deep sky objects catalog with ~13,000 objects',
  version: '2023.12',
  downloadUrl: 'https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv',
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
    query = 'SELECT "RAJ2000", "DEJ2000", "Bmag", "zhelio", "PGC" FROM "VII/291/gladep"';
  } else {
    // Filtered by B-magnitude
    // Note: Bmag can be NULL for many entries, so we filter for non-null values
    query = 'SELECT "RAJ2000", "DEJ2000", "Bmag", "zhelio", "PGC" FROM "VII/291/gladep" '
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
  
  factory CatalogStatus.notInstalled() => const CatalogStatus(isInstalled: false);
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
  
  factory DownloadProgress.complete(String catalogName, int bytes) => DownloadProgress(
    catalogName: catalogName,
    progress: 1.0,
    bytesReceived: bytes,
    totalBytes: bytes,
    status: 'Complete',
    isComplete: true,
  );
  
  factory DownloadProgress.error(String catalogName, String error) => DownloadProgress(
    catalogName: catalogName,
    progress: 0,
    bytesReceived: 0,
    totalBytes: 0,
    status: 'Error',
    error: error,
  );
}

/// Manages astronomical catalog downloads, installation, and access
class CatalogManager {
  static CatalogManager? _instance;
  static CatalogManager get instance => _instance ??= CatalogManager._();
  
  CatalogManager._();
  
  String? _catalogDirectory;
  final _downloadController = StreamController<DownloadProgress>.broadcast();

  /// P1-12: lifecycle events for the unified catalog API used by the
  /// headless `/api/catalog/...` surface. Distinct from
  /// [downloadProgress] because the headless event stream wants
  /// structured per-name events (`CatalogDownloadStarted`,
  /// `CatalogVerified`, `CatalogUninstalled`, ...) that the legacy
  /// per-progress controller does not emit.
  final _eventController = StreamController<CatalogEvent>.broadcast();

  HygCatalogLoader? _starLoader;
  String? _starLoaderPath;
  OpenNgcCatalogLoader? _dsoLoader;
  String? _dsoLoaderPath;

  /// Stream of download progress updates
  Stream<DownloadProgress> get downloadProgress => _downloadController.stream;

  /// P1-12: stream of structured lifecycle events used by the headless
  /// API. Every catalog install, verify, uninstall, or reload publishes
  /// an event here so `HeadlessApiServer` can fan it out over the WS
  /// event stream.
  Stream<CatalogEvent> get events => _eventController.stream;
  
  /// Check if catalog manager has been initialized
  bool get isInitialized => _catalogDirectory != null;
  
  /// Set the catalog storage directory
  Future<void> initialize(String catalogDirectory) async {
    _catalogDirectory = catalogDirectory;
    _invalidateLocalCatalogLoaders();
    
    // Ensure directory exists
    final dir = Directory(catalogDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    developer.log(
        '[Catalog] initialized with directory: $catalogDirectory',
        name: 'CatalogManager',
        level: 800);
  }
  
  /// Get the catalog directory path
  String get catalogDirectory {
    if (_catalogDirectory == null) {
      throw StateError('CatalogManager not initialized. Call initialize() first.');
    }
    return _catalogDirectory!;
  }
  
  /// Check if star catalog is installed
  Future<CatalogStatus> getStarCatalogStatus() async {
    if (!isInitialized) return CatalogStatus.notInstalled();
    return _getCatalogStatus(hygStarCatalog.fileName, 'stars');
  }
  
  /// Check if DSO catalog is installed
  Future<CatalogStatus> getDsoCatalogStatus() async {
    if (!isInitialized) return CatalogStatus.notInstalled();
    return _getCatalogStatus(openNgcCatalog.fileName, 'dso');
  }
  
  Future<CatalogStatus> _getCatalogStatus(String fileName, String type) async {
    final filePath = path.join(catalogDirectory, fileName);
    final file = File(filePath);
    
    if (!await file.exists()) {
      return CatalogStatus.notInstalled();
    }
    
    // Read metadata file if it exists
    final metaPath = path.join(catalogDirectory, '${type}_metadata.json');
    final metaFile = File(metaPath);
    
    CatalogPackage? package;
    String? version;
    int? objectCount;
    DateTime? installedDate;
    
    if (await metaFile.exists()) {
      try {
        final metaJson = jsonDecode(await metaFile.readAsString());
        package = CatalogPackage.values.firstWhere(
          (p) => p.name == metaJson['package'],
          orElse: () => CatalogPackage.complete,
        );
        version = metaJson['version'];
        objectCount = metaJson['objectCount'];
        installedDate = DateTime.tryParse(metaJson['installedDate'] ?? '');
      } catch (e) {
        // Metadata corrupted or malformed - report as installed with defaults
        developer.log('[Catalog]: Failed to parse metadata: $e',
            name: 'CatalogManager', level: 900);
      }
    }
    
    return CatalogStatus(
      isInstalled: true,
      installedPath: filePath,
      installedDate: installedDate,
      installedPackage: package,
      objectCount: objectCount,
      version: version,
    );
  }
  
  /// Download and install star catalog
  Future<bool> downloadStarCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadCatalog(
      source: hygStarCatalog,
      type: 'stars',
      package: package,
      onProgress: onProgress,
    );
  }
  
  /// Download and install DSO catalog
  Future<bool> downloadDsoCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadCatalog(
      source: openNgcCatalog,
      type: 'dso',
      package: package,
      onProgress: onProgress,
    );
  }
  
  Future<bool> _downloadCatalog({
    required CatalogSource source,
    required String type,
    required CatalogPackage package,
    void Function(DownloadProgress)? onProgress,
  }) async {
    developer.log(
        '[Catalog] Starting download of ${source.name} from ${source.downloadUrl}',
        name: 'CatalogManager',
        level: 800);
    
    final progress = DownloadProgress.starting(source.name);
    _downloadController.add(progress);
    onProgress?.call(progress);
    
    try {
      // Ensure catalog directory exists
      if (!isInitialized) {
        throw StateError('CatalogManager not initialized');
      }
      
      final dir = Directory(catalogDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // Use http package for better cross-platform compatibility
      final client = http.Client();
      
      try {
        developer.log(
            '[Catalog] Sending HTTP GET request to ${source.downloadUrl}',
            name: 'CatalogManager',
            level: 800);

        final request = http.Request('GET', Uri.parse(source.downloadUrl));
        final streamedResponse = await client.send(request);

        developer.log(
            '[Catalog] Response status: ${streamedResponse.statusCode}',
            name: 'CatalogManager',
            level: 800);

        if (streamedResponse.statusCode != 200) {
          final errorMsg = 'HTTP ${streamedResponse.statusCode}: Failed to download from ${source.downloadUrl}';
          developer.log(errorMsg, name: 'CatalogManager', level: 1000);
          final error = DownloadProgress.error(source.name, errorMsg);
          _downloadController.add(error);
          onProgress?.call(error);
          return false;
        }
        
        final contentLength = streamedResponse.contentLength ?? 0;
        final filePath = path.join(catalogDirectory, source.fileName);
        final file = File(filePath);
        final sink = file.openWrite();
        
        developer.log(
            '[Catalog] Writing to $filePath, expected size: $contentLength bytes',
            name: 'CatalogManager',
            level: 800);

        // Check if the download is gzip compressed
        final isGzipped = source.downloadUrl.endsWith('.gz');
        
        var bytesReceived = 0;
        final downloadedBytes = <int>[];
        
        await for (final chunk in streamedResponse.stream) {
          downloadedBytes.addAll(chunk);
          bytesReceived += chunk.length;
          
          final prog = DownloadProgress(
            catalogName: source.name,
            progress: contentLength > 0 ? bytesReceived / contentLength : 0,
            bytesReceived: bytesReceived,
            totalBytes: contentLength,
            status: 'Downloading... ${(bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB',
          );
          _downloadController.add(prog);
          onProgress?.call(prog);
        }
        
        // Decompress if needed
        Uint8List finalBytes;
        if (isGzipped) {
          developer.log('[Catalog] Decompressing gzip data...',
              name: 'CatalogManager', level: 800);
          try {
            finalBytes = Uint8List.fromList(
              gzip.decode(downloadedBytes)
            );
            developer.log(
                '[Catalog] Decompressed ${downloadedBytes.length} bytes to ${finalBytes.length} bytes',
                name: 'CatalogManager',
                level: 800);
          } catch (e) {
            developer.log('[Catalog] Gzip decompression failed: $e',
                name: 'CatalogManager', level: 900);
            // Try to use the data as-is (maybe it wasn't actually gzipped)
            finalBytes = Uint8List.fromList(downloadedBytes);
          }
        } else {
          finalBytes = Uint8List.fromList(downloadedBytes);
        }
        
        // Write to file
        sink.add(finalBytes);
        await sink.close();
        
        developer.log(
            '[Catalog] Download complete: $bytesReceived bytes written to $filePath',
            name: 'CatalogManager',
            level: 800);

        // Verify file was written
        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }

        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        developer.log('[Catalog] File verified: $fileSize bytes',
            name: 'CatalogManager', level: 800);

        // Count objects and save metadata
        final objectCount = await _countObjects(filePath);
        await _saveMetadata(type, source, package, objectCount);
        _invalidateLocalCatalogLoaders(
          stars: type == 'stars',
          dsos: type == 'dso',
        );

        developer.log('[Catalog] Catalog saved with $objectCount objects',
            name: 'CatalogManager', level: 800);
        
        final complete = DownloadProgress.complete(source.name, bytesReceived);
        _downloadController.add(complete);
        onProgress?.call(complete);
        
        return true;
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      developer.log(errorMsg,
          name: 'CatalogManager',
          level: 1000,
          error: e,
          stackTrace: stackTrace);

      final error = DownloadProgress.error(source.name, errorMsg);
      _downloadController.add(error);
      onProgress?.call(error);
      return false;
    }
  }

  Future<int> _countObjects(String filePath) async {
    try {
      final file = File(filePath);
      final lines = await file.readAsLines();
      // Subtract 1 for header row
      return lines.length - 1;
    } catch (e) {
      developer.log('[Catalog] Error counting objects: $e',
          name: 'CatalogManager', level: 900);
      return 0;
    }
  }
  
  Future<void> _saveMetadata(
    String type,
    CatalogSource source,
    CatalogPackage package,
    int objectCount,
  ) async {
    final metaPath = path.join(catalogDirectory, '${type}_metadata.json');
    final metaFile = File(metaPath);
    
    final metadata = {
      'source': source.name,
      'version': source.version,
      'package': package.name,
      'objectCount': objectCount,
      'installedDate': DateTime.now().toIso8601String(),
    };
    
    await metaFile.writeAsString(jsonEncode(metadata));
  }
  
  /// Import a catalog from a custom location
  Future<bool> importCatalog({
    required String sourcePath,
    required String type, // 'stars' or 'dso'
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return false;
      }
      
      final fileName = type == 'stars' ? hygStarCatalog.fileName : openNgcCatalog.fileName;
      final destPath = path.join(catalogDirectory, fileName);
      
      await sourceFile.copy(destPath);
      
      final objectCount = await _countObjects(destPath);
      final source = type == 'stars' ? hygStarCatalog : openNgcCatalog;
      await _saveMetadata(type, source, CatalogPackage.complete, objectCount);
      _invalidateLocalCatalogLoaders(
        stars: type == 'stars',
        dsos: type == 'dso',
      );
      
      return true;
    } catch (e) {
      developer.log('[Catalog] Import error: $e',
          name: 'CatalogManager', level: 1000);
      return false;
    }
  }
  
  /// Delete installed catalogs
  Future<void> deleteCatalogs() async {
    final files = [
      hygStarCatalog.fileName,
      openNgcCatalog.fileName,
      'stars_metadata.json',
      'dso_metadata.json',
    ];
    
    for (final fileName in files) {
      final file = File(path.join(catalogDirectory, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
    _invalidateLocalCatalogLoaders(stars: true, dsos: true);
  }
  
  /// Get the file path for the star catalog
  String get starCatalogPath => path.join(catalogDirectory, hygStarCatalog.fileName);

  /// Get the file path for the DSO catalog
  String get dsoCatalogPath => path.join(catalogDirectory, openNgcCatalog.fileName);

  /// Get the file path for the annotation catalog (GLADE+)
  String get annotationCatalogPath => path.join(catalogDirectory, gladePlusCatalog.fileName);

  // =========================================================================
  // ANNOTATION CATALOG (GLADE+) METHODS
  // =========================================================================

  /// Check if annotation catalog is installed
  Future<CatalogStatus> getAnnotationCatalogStatus() async {
    if (!isInitialized) return CatalogStatus.notInstalled();
    return _getCatalogStatus(gladePlusCatalog.fileName, 'annotation');
  }

  /// Download and install annotation catalog (GLADE+ via VizieR TAP)
  Future<bool> downloadAnnotationCatalog({
    AnnotationPackage package = AnnotationPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadAnnotationCatalog(
      source: gladePlusCatalog,
      package: package,
      onProgress: onProgress,
    );
  }

  Future<bool> _downloadAnnotationCatalog({
    required CatalogSource source,
    required AnnotationPackage package,
    void Function(DownloadProgress)? onProgress,
  }) async {
    // Build the VizieR TAP URL based on the selected package tier
    final downloadUrl = buildGladePlusUrl(package);

    developer.log(
        '[Catalog] Starting download of ${source.name} (${package.displayName} tier)',
        name: 'CatalogManager',
        level: 800);
    developer.log('[Catalog] VizieR TAP URL: $downloadUrl',
        name: 'CatalogManager', level: 800);

    final progress = DownloadProgress.starting(source.name);
    _downloadController.add(progress);
    onProgress?.call(progress);

    try {
      if (!isInitialized) {
        throw StateError('CatalogManager not initialized');
      }

      final dir = Directory(catalogDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final client = http.Client();

      try {
        developer.log('[Catalog] Sending HTTP GET request to VizieR TAP...',
            name: 'CatalogManager', level: 800);

        final request = http.Request('GET', Uri.parse(downloadUrl));
        final streamedResponse = await client.send(request);

        developer.log(
            '[Catalog] Response status: ${streamedResponse.statusCode}',
            name: 'CatalogManager',
            level: 800);

        if (streamedResponse.statusCode != 200) {
          final errorMsg = 'HTTP ${streamedResponse.statusCode}: Failed to download from VizieR TAP';
          developer.log(errorMsg, name: 'CatalogManager', level: 1000);
          final error = DownloadProgress.error(source.name, errorMsg);
          _downloadController.add(error);
          onProgress?.call(error);
          return false;
        }

        final contentLength = streamedResponse.contentLength ?? 0;
        final filePath = path.join(catalogDirectory, source.fileName);
        final file = File(filePath);
        final sink = file.openWrite();

        developer.log(
            '[Catalog] Writing to $filePath, expected size: $contentLength bytes',
            name: 'CatalogManager',
            level: 800);

        // VizieR TAP returns CSV directly (not gzipped)
        var bytesReceived = 0;
        final downloadedBytes = <int>[];

        await for (final chunk in streamedResponse.stream) {
          downloadedBytes.addAll(chunk);
          bytesReceived += chunk.length;

          final prog = DownloadProgress(
            catalogName: source.name,
            progress: contentLength > 0 ? bytesReceived / contentLength : 0,
            bytesReceived: bytesReceived,
            totalBytes: contentLength,
            status: 'Downloading... ${(bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB',
          );
          _downloadController.add(prog);
          onProgress?.call(prog);
        }

        // Write CSV data directly to file
        final finalBytes = Uint8List.fromList(downloadedBytes);
        sink.add(finalBytes);
        await sink.close();

        developer.log(
            '[Catalog] Download complete: $bytesReceived bytes written to $filePath',
            name: 'CatalogManager',
            level: 800);

        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }

        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        developer.log('[Catalog] File verified: $fileSize bytes',
            name: 'CatalogManager', level: 800);

        final objectCount = await _countObjects(filePath);
        await _saveAnnotationMetadata(source, package, objectCount);

        developer.log(
            '[Catalog] Annotation catalog saved with $objectCount objects',
            name: 'CatalogManager',
            level: 800);

        final complete = DownloadProgress.complete(source.name, bytesReceived);
        _downloadController.add(complete);
        onProgress?.call(complete);

        return true;
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      developer.log(errorMsg,
          name: 'CatalogManager',
          level: 1000,
          error: e,
          stackTrace: stackTrace);

      final error = DownloadProgress.error(source.name, errorMsg);
      _downloadController.add(error);
      onProgress?.call(error);
      return false;
    }
  }

  Future<void> _saveAnnotationMetadata(
    CatalogSource source,
    AnnotationPackage package,
    int objectCount,
  ) async {
    final metaPath = path.join(catalogDirectory, 'annotation_metadata.json');
    final metaFile = File(metaPath);

    final metadata = {
      'source': source.name,
      'version': source.version,
      'package': package.name,
      'magnitudeLimit': package.magnitudeLimit,
      'objectCount': objectCount,
      'installedDate': DateTime.now().toIso8601String(),
    };

    await metaFile.writeAsString(jsonEncode(metadata));
  }

  /// Import annotation catalog from a local file
  /// Accepts CSV files with galaxy data (e.g., from VizieR GLADE+ export)
  /// Expected format: CSV with columns for RA, Dec, magnitude, etc.
  Future<bool> importAnnotationCatalog({
    required String sourcePath,
    AnnotationPackage package = AnnotationPackage.standard,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        developer.log('[Catalog] Import source file not found: $sourcePath',
            name: 'CatalogManager', level: 900);
        return false;
      }

      final destPath = path.join(catalogDirectory, gladePlusCatalog.fileName);

      // Copy the file
      await sourceFile.copy(destPath);

      // Count objects and save metadata
      final objectCount = await _countObjects(destPath);
      await _saveAnnotationMetadata(gladePlusCatalog, package, objectCount);

      developer.log(
          '[Catalog] Annotation catalog imported: $objectCount objects from $sourcePath',
          name: 'CatalogManager',
          level: 800);
      return true;
    } catch (e) {
      developer.log('[Catalog] Import annotation catalog error: $e',
          name: 'CatalogManager', level: 1000);
      return false;
    }
  }

  /// Delete annotation catalog
  Future<void> deleteAnnotationCatalog() async {
    final files = [
      gladePlusCatalog.fileName,
      'annotation_metadata.json',
    ];

    for (final fileName in files) {
      final file = File(path.join(catalogDirectory, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Get installed annotation package info
  Future<AnnotationPackage?> getInstalledAnnotationPackage() async {
    final status = await getAnnotationCatalogStatus();
    return status.installedPackage != null
        ? AnnotationPackage.values.firstWhere(
            (p) => p.name == status.installedPackage!.name,
            orElse: () => AnnotationPackage.standard,
          )
        : null;
  }

  /// Search both star and DSO catalogs
  Future<List<CatalogSearchResult>> search(String query) async {
    if (!isInitialized) return [];
    
    final results = <CatalogSearchResult>[];
    final q = query.toLowerCase();
    final normalizedQuery = _normalizeCatalogSearchText(query);
    
    // Search DSO catalog if installed
    final dsoStatus = await getDsoCatalogStatus();
    if (dsoStatus.isInstalled) {
      try {
        final loader = _getDsoLoader(dsoStatus.installedPath!);
        final dsos = await loader.search(query);
        
        // Prioritize exact matches
        final exactMatches = dsos.where((d) => 
          _catalogTextEquals(d.name, q, normalizedQuery) ||
          _catalogTextEquals(d.displayName, q, normalizedQuery) ||
          (d.messier != null &&
              _catalogTextEquals(d.messier!, q, normalizedQuery)) ||
          (d.ngcId != null &&
              _catalogTextEquals(d.ngcId!, q, normalizedQuery))
        ).toList();
        
        final partialMatches = dsos.where((d) => 
          !exactMatches.contains(d)
        ).take(20).toList(); // Limit partials
        
        results.addAll(exactMatches.map((d) => CatalogSearchResult(
          name: d.displayName,
          catalogId: d.name, // NGC/IC ID
          ra: d.ra,
          dec: d.dec,
          type: d.typeDescription,
          magnitude: d.magnitude,
          constellation: d.constellation,
          size: d.sizeString,
        )));
        
        results.addAll(partialMatches.map((d) => CatalogSearchResult(
          name: d.displayName,
          catalogId: d.name,
          ra: d.ra,
          dec: d.dec,
          type: d.typeDescription,
          magnitude: d.magnitude,
          constellation: d.constellation,
          size: d.sizeString,
        )));
      } catch (e) {
        developer.log('[Catalog] DSO search error: $e',
            name: 'CatalogManager', level: 900);
      }
    }
    
    // Search Star catalog if installed
    final starStatus = await getStarCatalogStatus();
    if (starStatus.isInstalled) {
      try {
        final loader = _getStarLoader(starStatus.installedPath!);
        final stars = await loader.search(query);

        final exactMatches = stars.where((s) =>
          _catalogTextEquals(s.name, q, normalizedQuery) ||
          _catalogTextEquals(s.catalogId, q, normalizedQuery) ||
          (s.hipId != null &&
              _catalogTextEquals('HIP${s.hipId}', q, normalizedQuery)) ||
          (s.hdId != null &&
              _catalogTextEquals('HD${s.hdId}', q, normalizedQuery))
        ).toList();

        final partialMatches = stars.where((s) =>
          !exactMatches.contains(s)
        ).take(20).toList();

        results.addAll([...exactMatches, ...partialMatches].take(20).map((s) => CatalogSearchResult(
          name: s.name,
          catalogId: s.catalogId,
          ra: s.ra,
          dec: s.dec,
          type: 'Star',
          magnitude: s.magnitude,
          constellation: s.constellation,
        )));
      } catch (e) {
        developer.log('[Catalog] Star search error: $e',
            name: 'CatalogManager', level: 900);
      }
    }
    
    return results;
  }

  /// Search for DSOs near a given RA/Dec position
  /// Returns objects within radiusDegrees of the specified coordinates
  Future<List<OpenNgcData>> searchDsoNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    if (!isInitialized) return [];

    final dsoStatus = await getDsoCatalogStatus();
    if (!dsoStatus.isInstalled) return [];

    try {
      final loader = _getDsoLoader(dsoStatus.installedPath!);
      return await loader.searchNearby(
        ra: ra,
        dec: dec,
        radiusDegrees: radiusDegrees,
        maxMagnitude: maxMagnitude,
      );
    } catch (e) {
      developer.log('[Catalog] DSO searchNearby error: $e',
          name: 'CatalogManager', level: 900);
      return [];
    }
  }

  /// Search for stars near a given RA/Dec position
  /// Returns stars within radiusDegrees of the specified coordinates
  Future<List<HygStarData>> searchStarsNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    if (!isInitialized) return [];

    final starStatus = await getStarCatalogStatus();
    if (!starStatus.isInstalled) return [];

    try {
      final loader = _getStarLoader(starStatus.installedPath!);
      return await loader.searchNearby(
        ra: ra,
        dec: dec,
        radiusDegrees: radiusDegrees,
        maxMagnitude: maxMagnitude,
      );
    } catch (e) {
      developer.log('[Catalog] Star searchNearby error: $e',
          name: 'CatalogManager', level: 900);
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    _downloadController.close();
    _eventController.close();
  }

  // ===========================================================================
  // P1-12: Unified catalog API for the headless `/api/catalog/...` surface.
  //
  // The legacy per-type methods (`downloadStarCatalog`, `downloadDsoCatalog`,
  // `downloadAnnotationCatalog`) continue to power the desktop
  // `CatalogSettingsScreen`. The methods below are a thin coordinator on top
  // that exposes a single "name → result" surface so a REST client can talk
  // about "the catalog named `stars`" without caring about the underlying
  // source/file shape.
  // ===========================================================================

  /// Canonical list of catalogs the headless API knows how to manage.
  /// Keyed by the catalog `name` exposed on the wire (`stars`, `dso`,
  /// `annotation`).
  static const Map<String, CatalogDescriptor> knownCatalogs = {
    'stars': CatalogDescriptor(
      name: 'stars',
      displayName: 'HYG Star Database',
      description:
          'Combined Hipparcos, Yale Bright Star, and Gliese catalogs; ~120k stars.',
      fileName: 'hyg_v42.csv',
      metadataFileName: 'stars_metadata.json',
      version: '4.2',
      approximateSizeBytes: 35 * 1024 * 1024,
      downloadUrl:
          'https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v42.csv.gz',
      isGzipped: true,
      // Plate solving needs a star catalog; this is the minimum.
      requiredForPlateSolve: true,
    ),
    'dso': CatalogDescriptor(
      name: 'dso',
      displayName: 'OpenNGC Deep Sky Objects',
      description: 'NGC/IC deep sky objects with ~13k objects.',
      fileName: 'NGC.csv',
      metadataFileName: 'dso_metadata.json',
      version: '2023.12',
      approximateSizeBytes: 5 * 1024 * 1024,
      downloadUrl:
          'https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files/NGC.csv',
      isGzipped: false,
      requiredForPlateSolve: false,
    ),
    'annotation': CatalogDescriptor(
      name: 'annotation',
      displayName: 'GLADE+ Galaxy Catalog',
      description:
          'Galaxy List for the Advanced Detector Era (B-magnitude ≤ 17 tier).',
      fileName: 'glade_plus_galaxies.csv',
      metadataFileName: 'annotation_metadata.json',
      version: '2022',
      // GLADE+ standard tier ≈ 50 MB; complete is ~2 GB.
      approximateSizeBytes: 50 * 1024 * 1024,
      // Built dynamically via [buildGladePlusUrl] for the `standard` tier.
      downloadUrl: '',
      isGzipped: false,
      requiredForPlateSolve: false,
    ),
  };

  /// Returns the on-disk state for every known catalog.
  ///
  /// Used by `GET /api/catalog/status`. Catalogs that have never been
  /// downloaded show `status: missing`. Catalogs whose metadata file is
  /// missing or corrupted show `status: partial`. SHA-256 verification is
  /// NOT run here (it would scan multi-MB files on every status poll);
  /// callers that want a deep check use `POST /api/catalog/verify`.
  Future<List<InstalledCatalogStatus>> getInstalledStatuses() async {
    if (!isInitialized) {
      return knownCatalogs.values
          .map((d) => InstalledCatalogStatus(
                name: d.name,
                status: CatalogInstallStatus.missing,
              ))
          .toList(growable: false);
    }

    final results = <InstalledCatalogStatus>[];
    for (final descriptor in knownCatalogs.values) {
      results.add(await _statusFor(descriptor));
    }
    return results;
  }

  Future<InstalledCatalogStatus> _statusFor(
      CatalogDescriptor descriptor) async {
    final filePath = path.join(catalogDirectory, descriptor.fileName);
    final file = File(filePath);
    if (!await file.exists()) {
      return InstalledCatalogStatus(
        name: descriptor.name,
        status: CatalogInstallStatus.missing,
      );
    }

    int fileSize = 0;
    try {
      fileSize = await file.length();
    } on FileSystemException {
      return InstalledCatalogStatus(
        name: descriptor.name,
        status: CatalogInstallStatus.corrupted,
        errors: ['Failed to stat catalog file'],
      );
    }

    if (fileSize == 0) {
      return InstalledCatalogStatus(
        name: descriptor.name,
        sizeBytes: 0,
        fileCount: 1,
        status: CatalogInstallStatus.corrupted,
        errors: ['Catalog file is empty'],
      );
    }

    final metaPath =
        path.join(catalogDirectory, descriptor.metadataFileName);
    final metaFile = File(metaPath);
    String? version;
    DateTime? installedAt;
    DateTime? lastVerified;
    String? expectedHash;
    int? objectCount;
    if (await metaFile.exists()) {
      try {
        final raw = jsonDecode(await metaFile.readAsString());
        if (raw is Map<String, dynamic>) {
          version = raw['version'] as String?;
          installedAt =
              DateTime.tryParse(raw['installedDate']?.toString() ?? '');
          lastVerified =
              DateTime.tryParse(raw['lastVerified']?.toString() ?? '');
          expectedHash = raw['sha256'] as String?;
          objectCount = raw['objectCount'] is int
              ? raw['objectCount'] as int
              : (raw['objectCount'] as num?)?.toInt();
        }
      } catch (e) {
        developer.log(
          '[Catalog] _statusFor($descriptor): malformed metadata: $e',
          name: 'CatalogManager',
          level: 900,
        );
        return InstalledCatalogStatus(
          name: descriptor.name,
          sizeBytes: fileSize,
          fileCount: 1,
          status: CatalogInstallStatus.partial,
          errors: ['Metadata file is malformed'],
        );
      }
    }

    return InstalledCatalogStatus(
      name: descriptor.name,
      version: version ?? descriptor.version,
      sizeBytes: fileSize,
      fileCount: await metaFile.exists() ? 2 : 1,
      installedAt: installedAt,
      lastVerified: lastVerified,
      expectedHash: expectedHash,
      objectCount: objectCount,
      status: CatalogInstallStatus.installed,
    );
  }

  /// Lists the catalogs available for download.
  ///
  /// In the current implementation the manifest is the static
  /// [knownCatalogs] map; a future revision can swap this for a live
  /// fetch from a configured catalog manifest server. The method is
  /// declared async so the wire shape does not need to change when that
  /// happens.
  ///
  /// The returned `sha256` is omitted (null) when the descriptor does
  /// not have a known canonical hash. A future manifest server can
  /// publish per-version hashes; clients then call
  /// `POST /api/catalog/verify` after downloading to confirm.
  Future<List<AvailableCatalog>> listAvailable() async {
    return knownCatalogs.values
        .map((d) => AvailableCatalog(
              name: d.name,
              displayName: d.displayName,
              version: d.version,
              description: d.description,
              downloadUrl:
                  d.downloadUrl.isNotEmpty ? d.downloadUrl : null,
              sizeBytes: d.approximateSizeBytes,
              sha256: null,
              requiredForPlateSolve: d.requiredForPlateSolve,
            ))
        .toList(growable: false);
  }

  /// Download + install a catalog by name.
  ///
  /// `name` must be one of the keys in [knownCatalogs]. Throws
  /// [ArgumentError] otherwise.
  ///
  /// Implementation:
  ///   1. Stream the bytes into a temp file inside the catalog
  ///      directory (NOT into the final destination — a partial file
  ///      would otherwise overwrite a previously-working install).
  ///   2. Decompress when [CatalogDescriptor.isGzipped] is true.
  ///   3. Compute SHA-256 over the final (decompressed) bytes.
  ///   4. Atomically rename into place.
  ///   5. Write the metadata sidecar with the recorded hash.
  ///   6. Invalidate any cached loaders so subsequent searches pick up
  ///      the new file immediately.
  ///   7. Emit [CatalogEvent] start/progress/complete entries.
  ///
  /// [onProgress] is invoked with `(downloadedBytes, totalBytes)` —
  /// totalBytes may be -1 when the server does not send
  /// `Content-Length` (rare for our manifests but possible for VizieR
  /// TAP). [cancel], when supplied, is polled on every chunk; throws
  /// [CatalogCancelled] when the operator cancels mid-download.
  Future<CatalogInstallResult> downloadAndInstall(
    String name, {
    String? jobId,
    void Function(int downloaded, int total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final descriptor = knownCatalogs[name];
    if (descriptor == null) {
      throw ArgumentError.value(name, 'name', 'Unknown catalog name');
    }
    if (!isInitialized) {
      throw StateError('CatalogManager not initialized');
    }
    final downloadUrl = descriptor.downloadUrl.isNotEmpty
        ? descriptor.downloadUrl
        : (name == 'annotation'
            ? buildGladePlusUrl(AnnotationPackage.standard)
            : '');
    if (downloadUrl.isEmpty) {
      throw StateError('No download URL configured for catalog $name');
    }

    final dir = Directory(catalogDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final finalPath = path.join(catalogDirectory, descriptor.fileName);
    final tempPath =
        path.join(catalogDirectory, '.${descriptor.fileName}.partial');
    final metaPath =
        path.join(catalogDirectory, descriptor.metadataFileName);

    _eventController.add(CatalogEvent.downloadStarted(
      jobId: jobId,
      name: descriptor.name,
      downloadUrl: downloadUrl,
      totalBytes: descriptor.approximateSizeBytes,
    ));

    final client = http.Client();
    int totalBytes = -1;
    int downloadedBytes = 0;
    DateTime lastProgressEmit =
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw CatalogDownloadException(
          phase: 'http_send',
          message:
              'HTTP ${response.statusCode} downloading $name from $downloadUrl',
        );
      }
      totalBytes = response.contentLength ?? -1;

      // Stream into the temp file. We collect bytes for SHA when gzip is
      // off (so the on-disk file IS the hashed bytes); when gzip is on
      // we keep the compressed bytes in-memory because we need to
      // decompress before writing the final file anyway.
      final tempFile = File(tempPath);
      // Ensure no leftover partial from a prior failed run.
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      final compressedSink = descriptor.isGzipped ? null : tempFile.openWrite();
      final compressedBuffer = descriptor.isGzipped ? <int>[] : null;

      try {
        await for (final chunk in response.stream) {
          if (isCancelled != null && await isCancelled()) {
            throw const CatalogCancelled();
          }
          if (compressedSink != null) {
            compressedSink.add(chunk);
          } else {
            compressedBuffer!.addAll(chunk);
          }
          downloadedBytes += chunk.length;
          onProgress?.call(downloadedBytes, totalBytes);

          final now = DateTime.now();
          if (now.difference(lastProgressEmit).inMilliseconds >= 1000) {
            lastProgressEmit = now;
            _eventController.add(CatalogEvent.downloadProgress(
              jobId: jobId,
              name: descriptor.name,
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
            ));
          }
        }
      } finally {
        await compressedSink?.close();
      }

      // Decompression / final-file materialisation.
      Uint8List finalBytes;
      if (descriptor.isGzipped) {
        try {
          finalBytes = Uint8List.fromList(gzip.decode(compressedBuffer!));
        } catch (e) {
          throw CatalogDownloadException(
            phase: 'decompress',
            message: 'Failed to gunzip $name: $e',
          );
        }
        // Now write the decompressed payload to the temp file.
        await tempFile.writeAsBytes(finalBytes, flush: true);
      } else {
        finalBytes = await tempFile.readAsBytes();
      }

      if (finalBytes.isEmpty) {
        throw CatalogDownloadException(
          phase: 'verify',
          message: 'Downloaded $name is empty after decompression',
        );
      }

      // SHA-256 over the FINAL bytes (post-decompression). This is what
      // a subsequent `verify` call will re-compute. We record this in
      // the metadata sidecar so verify can compare against it.
      final actualHash = sha256.convert(finalBytes).toString();

      // Atomic rename.
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(finalPath);

      // Object count for the metadata sidecar.
      final objectCount = await _countObjects(finalPath);
      final installedAt = DateTime.now().toUtc();
      final metadata = <String, Object?>{
        'source': descriptor.displayName,
        'name': descriptor.name,
        'version': descriptor.version,
        'sha256': actualHash,
        'objectCount': objectCount,
        'sizeBytes': finalBytes.length,
        'installedDate': installedAt.toIso8601String(),
        'downloadUrl': downloadUrl,
        if (descriptor.name == 'annotation') 'package': 'standard',
      };
      await File(metaPath).writeAsString(jsonEncode(metadata));

      // Invalidate cached loaders so the next search picks up the new file.
      _invalidateLocalCatalogLoaders(
        stars: descriptor.name == 'stars',
        dsos: descriptor.name == 'dso',
      );

      _eventController.add(CatalogEvent.downloadComplete(
        jobId: jobId,
        name: descriptor.name,
        version: descriptor.version,
        sizeBytes: finalBytes.length,
        sha256: actualHash,
      ));

      return CatalogInstallResult(
        name: descriptor.name,
        sha256: actualHash,
        sizeBytes: finalBytes.length,
        objectCount: objectCount,
        version: descriptor.version,
        installedAt: installedAt,
      );
    } on CatalogCancelled {
      // Best-effort cleanup; not throwing here because the cancel itself
      // is the signal that should propagate.
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Cleanup failure is logged but does not mask the cancel.
          developer.log(
            '[Catalog] downloadAndInstall($name): failed to delete partial after cancel',
            name: 'CatalogManager',
            level: 900,
          );
        }
      }
      _eventController.add(CatalogEvent.downloadFailed(
        jobId: jobId,
        name: descriptor.name,
        error: 'cancelled',
        phase: 'cancelled',
      ));
      rethrow;
    } catch (e) {
      // Surface failure events before rethrowing so subscribers always
      // see a terminating event for the started download.
      _eventController.add(CatalogEvent.downloadFailed(
        jobId: jobId,
        name: descriptor.name,
        error: e.toString(),
        phase: e is CatalogDownloadException ? e.phase : 'unknown',
      ));
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Per CLAUDE.md "errors are a feature" — log loudly so the
          // operator can clean up manually if needed.
          developer.log(
            '[Catalog] downloadAndInstall($name): failed to delete partial after error',
            name: 'CatalogManager',
            level: 1000,
          );
        }
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Install a catalog from a pre-staged file on disk. Used by the
  /// `/api/catalog/upload` air-gap flow: the operator uploads a CSV
  /// (already-decompressed) and we move/copy it into the catalog
  /// directory with a recorded hash.
  ///
  /// [expectedSha256], when supplied, is compared against the actual
  /// SHA-256 of the source file before installation; mismatch throws
  /// [CatalogHashMismatchException] and the source file is NOT moved.
  Future<CatalogInstallResult> installFromFile({
    required String name,
    required File source,
    String? expectedSha256,
  }) async {
    final descriptor = knownCatalogs[name];
    if (descriptor == null) {
      throw ArgumentError.value(name, 'name', 'Unknown catalog name');
    }
    if (!isInitialized) {
      throw StateError('CatalogManager not initialized');
    }
    if (!await source.exists()) {
      throw FileSystemException('Source file does not exist', source.path);
    }
    final dir = Directory(catalogDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final sourceBytes = await source.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw const CatalogDownloadException(
        phase: 'install_from_file',
        message: 'Source file is empty',
      );
    }
    final actualHash = sha256.convert(sourceBytes).toString();
    if (expectedSha256 != null &&
        expectedSha256.toLowerCase() != actualHash.toLowerCase()) {
      throw CatalogHashMismatchException(
        expected: expectedSha256,
        actual: actualHash,
      );
    }

    final finalPath = path.join(catalogDirectory, descriptor.fileName);
    final metaPath =
        path.join(catalogDirectory, descriptor.metadataFileName);

    // Write to a temp file in the catalog directory then atomically
    // rename — same flow as downloadAndInstall.
    final tempPath =
        path.join(catalogDirectory, '.${descriptor.fileName}.upload');
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsBytes(sourceBytes, flush: true);

    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalPath);

    final objectCount = await _countObjects(finalPath);
    final installedAt = DateTime.now().toUtc();
    final metadata = <String, Object?>{
      'source': 'upload',
      'name': descriptor.name,
      'version': descriptor.version,
      'sha256': actualHash,
      'objectCount': objectCount,
      'sizeBytes': sourceBytes.length,
      'installedDate': installedAt.toIso8601String(),
    };
    await File(metaPath).writeAsString(jsonEncode(metadata));

    _invalidateLocalCatalogLoaders(
      stars: descriptor.name == 'stars',
      dsos: descriptor.name == 'dso',
    );

    _eventController.add(CatalogEvent.downloadComplete(
      jobId: null,
      name: descriptor.name,
      version: descriptor.version,
      sizeBytes: sourceBytes.length,
      sha256: actualHash,
    ));

    return CatalogInstallResult(
      name: descriptor.name,
      sha256: actualHash,
      sizeBytes: sourceBytes.length,
      objectCount: objectCount,
      version: descriptor.version,
      installedAt: installedAt,
    );
  }

  /// Uninstall a catalog by name. Deletes the data file + metadata
  /// sidecar. No-op when the catalog is not installed (returns false).
  Future<bool> uninstall(String name) async {
    final descriptor = knownCatalogs[name];
    if (descriptor == null) {
      throw ArgumentError.value(name, 'name', 'Unknown catalog name');
    }
    if (!isInitialized) {
      return false;
    }

    final dataFile = File(path.join(catalogDirectory, descriptor.fileName));
    final metaFile =
        File(path.join(catalogDirectory, descriptor.metadataFileName));
    var removedAnything = false;
    if (await dataFile.exists()) {
      await dataFile.delete();
      removedAnything = true;
    }
    if (await metaFile.exists()) {
      await metaFile.delete();
      removedAnything = true;
    }
    _invalidateLocalCatalogLoaders(
      stars: descriptor.name == 'stars',
      dsos: descriptor.name == 'dso',
    );

    if (removedAnything) {
      _eventController
          .add(CatalogEvent.uninstalled(name: descriptor.name));
    }
    return removedAnything;
  }

  /// Re-load any cached catalog loaders. Useful when files were
  /// modified out-of-band (e.g. operator manually copied a catalog into
  /// the directory). Synchronous side: drops the in-memory loaders so
  /// the next search re-parses the file from disk.
  Future<void> reload() async {
    _invalidateLocalCatalogLoaders(stars: true, dsos: true);
    _eventController.add(const CatalogEvent.reloaded());
  }

  /// Verify the SHA-256 of installed catalogs against the value
  /// recorded in their metadata sidecar.
  ///
  /// [name] selects a single catalog; null means "verify every
  /// installed catalog". A catalog that is not installed surfaces as
  /// `ok: false` with `error: 'not_installed'`.
  Future<Map<String, CatalogVerifyResult>> verify({String? name}) async {
    if (!isInitialized) {
      throw StateError('CatalogManager not initialized');
    }
    final targets = <CatalogDescriptor>[];
    if (name == null) {
      targets.addAll(knownCatalogs.values);
    } else {
      final descriptor = knownCatalogs[name];
      if (descriptor == null) {
        throw ArgumentError.value(name, 'name', 'Unknown catalog name');
      }
      targets.add(descriptor);
    }

    final results = <String, CatalogVerifyResult>{};
    for (final descriptor in targets) {
      results[descriptor.name] = await _verifyOne(descriptor);
    }
    return results;
  }

  Future<CatalogVerifyResult> _verifyOne(
      CatalogDescriptor descriptor) async {
    final dataFile =
        File(path.join(catalogDirectory, descriptor.fileName));
    if (!await dataFile.exists()) {
      const result = CatalogVerifyResult(
        ok: false,
        expectedHash: null,
        actualHash: null,
        errors: ['not_installed'],
      );
      _eventController.add(CatalogEvent.verified(
        name: descriptor.name,
        ok: false,
        errors: result.errors,
      ));
      return result;
    }

    String? expectedHash;
    final metaFile =
        File(path.join(catalogDirectory, descriptor.metadataFileName));
    if (await metaFile.exists()) {
      try {
        final raw = jsonDecode(await metaFile.readAsString());
        if (raw is Map<String, dynamic>) {
          expectedHash = raw['sha256'] as String?;
        }
      } catch (e) {
        developer.log(
          '[Catalog] _verifyOne(${descriptor.name}): malformed metadata: $e',
          name: 'CatalogManager',
          level: 900,
        );
      }
    }

    // Stream the file rather than reading it whole — catalog files are
    // multi-MB and verifying them all at once would spike memory.
    final digest = await sha256.bind(dataFile.openRead()).first;
    final actualHash = digest.toString();

    final ok = expectedHash != null &&
        expectedHash.toLowerCase() == actualHash.toLowerCase();
    final errors = <String>[];
    if (expectedHash == null) {
      errors.add('no_expected_hash');
    } else if (!ok) {
      errors.add('hash_mismatch');
    }

    // Update lastVerified in the metadata sidecar.
    if (await metaFile.exists()) {
      try {
        final raw = jsonDecode(await metaFile.readAsString());
        if (raw is Map<String, dynamic>) {
          raw['lastVerified'] = DateTime.now().toUtc().toIso8601String();
          await metaFile.writeAsString(jsonEncode(raw));
        }
      } catch (e) {
        developer.log(
          '[Catalog] _verifyOne(${descriptor.name}): failed to update lastVerified: $e',
          name: 'CatalogManager',
          level: 900,
        );
      }
    }

    final result = CatalogVerifyResult(
      ok: ok,
      expectedHash: expectedHash,
      actualHash: actualHash,
      errors: errors,
    );
    _eventController.add(CatalogEvent.verified(
      name: descriptor.name,
      ok: ok,
      errors: errors,
    ));
    return result;
  }

  HygCatalogLoader _getStarLoader(String path) {
    if (_starLoader == null || _starLoaderPath != path) {
      _starLoader = HygCatalogLoader(path);
      _starLoaderPath = path;
    }
    return _starLoader!;
  }

  OpenNgcCatalogLoader _getDsoLoader(String path) {
    if (_dsoLoader == null || _dsoLoaderPath != path) {
      _dsoLoader = OpenNgcCatalogLoader(path);
      _dsoLoaderPath = path;
    }
    return _dsoLoader!;
  }

  void _invalidateLocalCatalogLoaders({bool stars = true, bool dsos = true}) {
    if (stars) {
      _starLoader?.clearCache();
      _starLoader = null;
      _starLoaderPath = null;
    }
    if (dsos) {
      _dsoLoader?.clearCache();
      _dsoLoader = null;
      _dsoLoaderPath = null;
    }
  }
}

/// Unified search result from catalog manager
class CatalogSearchResult {
  final String name;
  final String catalogId;
  final double ra; // Degrees
  final double dec; // Degrees
  final String type;
  final double? magnitude;
  final String? constellation;
  final String? size;

  const CatalogSearchResult({
    required this.name,
    required this.catalogId,
    required this.ra,
    required this.dec,
    required this.type,
    this.magnitude,
    this.constellation,
    this.size,
  });
}

/// Parsed star data from HYG database
class HygStarData {
  final int id;
  final int? hipId;
  final int? hdId;
  final String? properName;
  final double ra; // Right ascension in degrees
  final double dec; // Declination in degrees
  final double? distance; // Distance in parsecs
  final double? magnitude; // Apparent visual magnitude
  final double? absoluteMagnitude;
  final String? spectralType;
  final String? constellation;
  final double? colorIndex; // B-V color index
  
  const HygStarData({
    required this.id,
    this.hipId,
    this.hdId,
    this.properName,
    required this.ra,
    required this.dec,
    this.distance,
    this.magnitude,
    this.absoluteMagnitude,
    this.spectralType,
    this.constellation,
    this.colorIndex,
  });
  
  /// Parse a line from the HYG CSV file
  /// Format: id,hip,hd,hr,gl,bf,proper,ra,dec,dist,pmra,pmdec,rv,mag,absmag,spect,ci,x,y,z,vx,vy,vz,rarad,decrad,pmrarad,pmdecrad,bayer,flam,con,comp,comp_primary,base,lum,var,var_min,var_max
  factory HygStarData.fromCsvLine(String line) {
    final parts = line.split(',');
    
    // Handle quoted fields
    final cleanParts = <String>[];
    var inQuotes = false;
    var current = '';
    
    for (final part in parts) {
      if (inQuotes) {
        current += ',$part';
        if (part.endsWith('"')) {
          cleanParts.add(current.substring(1, current.length - 1));
          inQuotes = false;
          current = '';
        }
      } else if (part.startsWith('"') && !part.endsWith('"')) {
        inQuotes = true;
        current = part;
      } else {
        cleanParts.add(part.replaceAll('"', ''));
      }
    }
    
    final p = cleanParts;
    
    return HygStarData(
      id: int.tryParse(p[0]) ?? 0,
      hipId: int.tryParse(p[1]),
      hdId: int.tryParse(p[2]),
      properName: p.length > 6 && p[6].isNotEmpty ? p[6] : null,
      ra: (double.tryParse(p[7]) ?? 0) * 15, // Convert from hours to degrees
      dec: double.tryParse(p[8]) ?? 0,
      distance: double.tryParse(p[9]),
      magnitude: double.tryParse(p[13]),
      absoluteMagnitude: double.tryParse(p[14]),
      spectralType: p.length > 15 && p[15].isNotEmpty ? p[15] : null,
      colorIndex: p.length > 16 ? double.tryParse(p[16]) : null,
      constellation: p.length > 29 && p[29].isNotEmpty ? p[29] : null,
    );
  }
  
  /// Get star name (proper name, or HIP/HD designation)
  String get name {
    if (properName != null && properName!.isNotEmpty) {
      return properName!;
    }
    if (hipId != null) {
      return 'HIP $hipId';
    }
    if (hdId != null) {
      return 'HD $hdId';
    }
    return 'Star $id';
  }
  
  /// Get catalog ID
  String get catalogId {
    if (hipId != null) {
      return 'HIP$hipId';
    }
    if (hdId != null) {
      return 'HD$hdId';
    }
    return 'HYG$id';
  }
}

/// Parsed deep sky object data from OpenNGC
class OpenNgcData {
  final String name; // NGC/IC designation
  final String type; // Object type code
  final double ra; // Right ascension in degrees
  final double dec; // Declination in degrees
  final double? magnitude; // Visual magnitude
  final double? majorAxis; // Major axis in arcminutes
  final double? minorAxis; // Minor axis in arcminutes
  final double? positionAngle; // Position angle in degrees
  final String? messier; // Messier designation
  final String? ngcId; // NGC ID if IC object
  final String? commonNames; // Common names
  final String constellation;
  final String? notes;
  
  const OpenNgcData({
    required this.name,
    required this.type,
    required this.ra,
    required this.dec,
    this.magnitude,
    this.majorAxis,
    this.minorAxis,
    this.positionAngle,
    this.messier,
    this.ngcId,
    this.commonNames,
    required this.constellation,
    this.notes,
  });
  
  /// Parse a line from the OpenNGC CSV file
  /// Format: Name;Type;RA;Dec;Const;MajAx;MinAx;PosAng;B-Mag;V-Mag;J-Mag;H-Mag;K-Mag;SurfBr;Hubble;Pax;Pm-RA;Pm-Dec;RadVel;Redshift;Cstar U-Mag;Cstar B-Mag;Cstar V-Mag;M;NGC;IC;Cstar Names;Identifiers;Common names;NED notes;OpenNGC notes;Sources
  /// Column indices:
  /// 0:Name, 1:Type, 2:RA, 3:Dec, 4:Const, 5:MajAx, 6:MinAx, 7:PosAng,
  /// 8:B-Mag, 9:V-Mag, 10:J-Mag, 11:H-Mag, 12:K-Mag, 13:SurfBr, 14:Hubble,
  /// 15:Pax, 16:Pm-RA, 17:Pm-Dec, 18:RadVel, 19:Redshift,
  /// 20:Cstar U-Mag, 21:Cstar B-Mag, 22:Cstar V-Mag,
  /// 23:M, 24:NGC, 25:IC, 26:Cstar Names, 27:Identifiers,
  /// 28:Common names, 29:NED notes, 30:OpenNGC notes, 31:Sources
  factory OpenNgcData.fromCsvLine(String line) {
    final parts = line.split(';');

    // Parse RA (format: HH:MM:SS.ss)
    double parseRa(String raStr) {
      if (raStr.isEmpty) return 0;
      try {
        final parts = raStr.split(':');
        if (parts.length == 3) {
          final h = double.parse(parts[0]);
          final m = double.parse(parts[1]);
          final s = double.parse(parts[2]);
          return (h + m / 60 + s / 3600) * 15; // Convert to degrees
        }
        // Fallback: try parsing as decimal degrees directly
        final val = double.tryParse(raStr);
        if (val != null) return val;
      } catch (e) {
        // Ignore error and return 0
      }
      return 0;
    }

    // Parse Dec (format: +/-DD:MM:SS.s)
    double parseDec(String decStr) {
      if (decStr.isEmpty) return 0;
      final sign = decStr.startsWith('-') ? -1 : 1;
      final clean = decStr.replaceAll('+', '').replaceAll('-', '');
      final parts = clean.split(':');
      if (parts.length != 3) return 0;
      final d = double.tryParse(parts[0]) ?? 0;
      final m = double.tryParse(parts[1]) ?? 0;
      final s = double.tryParse(parts[2]) ?? 0;
      return sign * (d + m / 60 + s / 3600);
    }

    return OpenNgcData(
      name: parts[0],
      type: parts[1],
      ra: parseRa(parts[2]),
      dec: parseDec(parts[3]),
      constellation: parts.length > 4 ? parts[4] : '',
      majorAxis: parts.length > 5 ? double.tryParse(parts[5]) : null,
      minorAxis: parts.length > 6 ? double.tryParse(parts[6]) : null,
      positionAngle: parts.length > 7 ? double.tryParse(parts[7]) : null,
      magnitude: parts.length > 9 ? double.tryParse(parts[9]) : null, // V-Mag
      messier: _parseMessier(parts.length > 23 ? parts[23] : ''),
      ngcId: parts.length > 24 && parts[24].isNotEmpty ? 'NGC ${parts[24]}' : null,
      commonNames: parts.length > 28 && parts[28].isNotEmpty ? parts[28] : null,
      notes: parts.length > 30 && parts[30].isNotEmpty ? parts[30] : null,
    );
  }
  
  /// Get the display name (Messier if available, then common name, then catalog ID)
  String get displayName {
    if (messier != null) return messier!;
    if (commonNames != null && commonNames!.isNotEmpty) {
      return commonNames!.split(',').first.trim();
    }
    return name;
  }

  static String? _parseMessier(String raw) {
    final messierNum = int.tryParse(raw.trim());
    if (messierNum == null || messierNum < 1 || messierNum > 110) {
      return null;
    }
    return 'M$messierNum';
  }
  
  /// Get object type description
  String get typeDescription {
    switch (type) {
      case '*': return 'Star';
      case '**': return 'Double Star';
      case '*Ass': return 'Association of Stars';
      case 'OCl': return 'Open Cluster';
      case 'GCl': return 'Globular Cluster';
      case 'Cl+N': return 'Cluster + Nebula';
      case 'G': return 'Galaxy';
      case 'GPair': return 'Galaxy Pair';
      case 'GTrpl': return 'Galaxy Triplet';
      case 'GGroup': return 'Galaxy Group';
      case 'PN': return 'Planetary Nebula';
      case 'HII': return 'HII Region';
      case 'DrkN': return 'Dark Nebula';
      case 'EmN': return 'Emission Nebula';
      case 'Neb': return 'Nebula';
      case 'RfN': return 'Reflection Nebula';
      case 'SNR': return 'Supernova Remnant';
      case 'Nova': return 'Nova';
      case 'NonEx': return 'Non-Existent';
      case 'Dup': return 'Duplicate Entry';
      case 'Other': return 'Other';
      default: return type;
    }
  }
  
  /// Get object size string
  String? get sizeString {
    if (majorAxis == null) return null;
    if (minorAxis != null && minorAxis != majorAxis) {
      return "${majorAxis!.toStringAsFixed(1)}' × ${minorAxis!.toStringAsFixed(1)}'";
    }
    return "${majorAxis!.toStringAsFixed(1)}'";
  }
}

/// Star catalog loader that reads from downloaded HYG database
class HygCatalogLoader {
  final String filePath;
  List<HygStarData>? _cachedData;
  
  HygCatalogLoader(this.filePath);
  
  /// Load all stars from the catalog
  Future<List<HygStarData>> loadAll() async {
    if (_cachedData != null) return _cachedData!;
    
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Star catalog not found', filePath);
    }
    
    final lines = await file.readAsLines();
    final stars = <HygStarData>[];
    var malformedLines = 0;

    // Skip header line
    for (var i = 1; i < lines.length; i++) {
      try {
        final star = HygStarData.fromCsvLine(lines[i]);
        stars.add(star);
      } catch (e) {
        // Skip malformed lines but count them
        malformedLines++;
      }
    }

    if (malformedLines > 0) {
      developer.log(
          '[Catalog] StarCatalogLoader: Skipped $malformedLines malformed lines',
          name: 'CatalogManager',
          level: 900);
    }

    _cachedData = stars;
    return stars;
  }
  
  /// Load stars up to a magnitude limit
  Future<List<HygStarData>> loadByMagnitude(double maxMagnitude) async {
    final all = await loadAll();
    return all.where((s) => (s.magnitude ?? 99) <= maxMagnitude).toList();
  }
  
  /// Search stars by name
  Future<List<HygStarData>> search(String query) async {
    final all = await loadAll();
    final q = query.toLowerCase();
    final normalizedQuery = _normalizeCatalogSearchText(query);
    return all.where((s) {
      return _catalogTextMatches(s.name, q, normalizedQuery) ||
          _catalogTextMatches(s.catalogId, q, normalizedQuery) ||
          (s.hipId != null &&
              _catalogTextMatches('HIP${s.hipId}', q, normalizedQuery)) ||
          (s.hdId != null &&
              _catalogTextMatches('HD${s.hdId}', q, normalizedQuery));
    }).toList();
  }
  
  /// Find a star by HIP ID
  Future<HygStarData?> findByHipId(int hipId) async {
    final all = await loadAll();
    return all.where((s) => s.hipId == hipId).firstOrNull;
  }
  
  /// Get star count
  Future<int> get count async {
    final all = await loadAll();
    return all.length;
  }

  /// Search for stars near a given RA/Dec position
  /// Returns stars within radiusDegrees of the specified coordinates
  Future<List<HygStarData>> searchNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    final all = await loadAll();

    return all.where((star) {
      // Apply magnitude filter first (cheaper check)
      if (maxMagnitude != null && (star.magnitude ?? 99) > maxMagnitude) {
        return false;
      }

      // Calculate angular distance
      final distance = _angularDistance(ra, dec, star.ra, star.dec);
      return distance <= radiusDegrees;
    }).toList()
      // Sort by magnitude (brightest first)
      ..sort((a, b) => (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));
  }

  /// Clear cache
  void clearCache() {
    _cachedData = null;
  }
}

// (End of HygCatalogLoader)
/// DSO catalog loader that reads from downloaded OpenNGC database
class OpenNgcCatalogLoader {
  final String filePath;
  List<OpenNgcData>? _cachedData;
  
  OpenNgcCatalogLoader(this.filePath);
  
  /// Load all DSOs from the catalog
  Future<List<OpenNgcData>> loadAll() async {
    if (_cachedData != null) return _cachedData!;
    
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('DSO catalog not found', filePath);
    }
    
    final lines = await file.readAsLines();
    final dsos = <OpenNgcData>[];
    var malformedLines = 0;

    // Skip header line
    for (var i = 1; i < lines.length; i++) {
      try {
        final dso = OpenNgcData.fromCsvLine(lines[i]);
        // Skip non-existent and duplicate entries
        if (dso.type != 'NonEx' && dso.type != 'Dup') {
          dsos.add(dso);
        }
      } catch (e) {
        // Skip malformed lines but count them
        malformedLines++;
      }
    }

    if (malformedLines > 0) {
      developer.log(
          '[Catalog] DSOCatalogLoader: Skipped $malformedLines malformed lines',
          name: 'CatalogManager',
          level: 900);
    }

    _cachedData = dsos;
    return dsos;
  }
  
  /// Load DSOs up to a magnitude limit
  Future<List<OpenNgcData>> loadByMagnitude(double maxMagnitude) async {
    final all = await loadAll();
    return all.where((d) => (d.magnitude ?? 99) <= maxMagnitude).toList();
  }
  
  /// Load only Messier objects
  Future<List<OpenNgcData>> loadMessier() async {
    final all = await loadAll();
    return all.where((d) => d.messier != null).toList();
  }
  
  /// Load DSOs by type
  Future<List<OpenNgcData>> loadByType(String type) async {
    final all = await loadAll();
    return all.where((d) => d.type == type).toList();
  }
  
  /// Search DSOs by name
  Future<List<OpenNgcData>> search(String query) async {
    final all = await loadAll();
    final q = query.toLowerCase();
    final normalizedQuery = _normalizeCatalogSearchText(query);
    return all.where((d) {
      return _catalogTextMatches(d.name, q, normalizedQuery) ||
          _catalogTextMatches(d.displayName, q, normalizedQuery) ||
          (d.messier != null &&
              _catalogTextMatches(d.messier!, q, normalizedQuery)) ||
          (d.ngcId != null &&
              _catalogTextMatches(d.ngcId!, q, normalizedQuery)) ||
          (d.commonNames != null &&
              _catalogTextMatches(d.commonNames!, q, normalizedQuery));
    }).toList();
  }
  
  /// Find a DSO by NGC/IC name
  Future<OpenNgcData?> findByName(String name) async {
    final all = await loadAll();
    final normalizedName = name.toUpperCase().replaceAll(' ', '');
    return all.where((d) => 
      d.name.toUpperCase().replaceAll(' ', '') == normalizedName
    ).firstOrNull;
  }
  
  /// Get DSO count
  Future<int> get count async {
    final all = await loadAll();
    return all.length;
  }

  /// Search for DSOs near a given RA/Dec position
  /// Returns objects within radiusDegrees of the specified coordinates
  Future<List<OpenNgcData>> searchNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) async {
    final all = await loadAll();

    return all.where((dso) {
      // Apply magnitude filter first (cheaper check)
      if (maxMagnitude != null && (dso.magnitude ?? 99) > maxMagnitude) {
        return false;
      }

      // Calculate angular distance
      final distance = _angularDistance(ra, dec, dso.ra, dso.dec);
      return distance <= radiusDegrees;
    }).toList()
      // Sort by magnitude (brightest first)
      ..sort((a, b) => (a.magnitude ?? 99).compareTo(b.magnitude ?? 99));
  }

  /// Clear cache
  void clearCache() {
    _cachedData = null;
  }
}

// =============================================================================
// P1-12: Types for the unified catalog API.
// =============================================================================

/// Static description of a catalog the headless API knows how to manage.
class CatalogDescriptor {
  final String name;
  final String displayName;
  final String description;
  final String fileName;
  final String metadataFileName;
  final String version;
  final int approximateSizeBytes;
  final String downloadUrl;
  final bool isGzipped;
  final bool requiredForPlateSolve;

  const CatalogDescriptor({
    required this.name,
    required this.displayName,
    required this.description,
    required this.fileName,
    required this.metadataFileName,
    required this.version,
    required this.approximateSizeBytes,
    required this.downloadUrl,
    required this.isGzipped,
    required this.requiredForPlateSolve,
  });
}

/// Status of one catalog on disk.
enum CatalogInstallStatus {
  installed,
  partial,
  corrupted,
  missing,
}

/// Detailed on-disk status of one catalog.
class InstalledCatalogStatus {
  final String name;
  final String? version;
  final int sizeBytes;
  final int fileCount;
  final DateTime? installedAt;
  final DateTime? lastVerified;
  final String? expectedHash;
  final String? actualHash;
  final int? objectCount;
  final CatalogInstallStatus status;
  final List<String>? errors;

  const InstalledCatalogStatus({
    required this.name,
    this.version,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.installedAt,
    this.lastVerified,
    this.expectedHash,
    this.actualHash,
    this.objectCount,
    required this.status,
    this.errors,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        if (version != null) 'version': version,
        'sizeBytes': sizeBytes,
        'fileCount': fileCount,
        if (installedAt != null) 'installedAt': installedAt!.toIso8601String(),
        if (lastVerified != null)
          'lastVerified': lastVerified!.toIso8601String(),
        if (expectedHash != null) 'expectedHash': expectedHash,
        if (actualHash != null) 'actualHash': actualHash,
        if (objectCount != null) 'objectCount': objectCount,
        'status': status.name,
        if (errors != null && errors!.isNotEmpty) 'errors': errors,
      };
}

/// Description of a catalog available for download.
class AvailableCatalog {
  final String name;
  final String displayName;
  final String version;
  final String description;
  final String? downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final bool requiredForPlateSolve;

  const AvailableCatalog({
    required this.name,
    required this.displayName,
    required this.version,
    required this.description,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.requiredForPlateSolve,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'displayName': displayName,
        'version': version,
        'description': description,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        if (sha256 != null) 'sha256': sha256,
        'requiredForPlateSolve': requiredForPlateSolve,
      };
}

/// Result of `downloadAndInstall` / `installFromFile`.
class CatalogInstallResult {
  final String name;
  final String sha256;
  final int sizeBytes;
  final int objectCount;
  final String version;
  final DateTime installedAt;

  const CatalogInstallResult({
    required this.name,
    required this.sha256,
    required this.sizeBytes,
    required this.objectCount,
    required this.version,
    required this.installedAt,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'sha256': sha256,
        'sizeBytes': sizeBytes,
        'objectCount': objectCount,
        'version': version,
        'installedAt': installedAt.toIso8601String(),
      };
}

/// Result of a single-catalog `verify` call.
class CatalogVerifyResult {
  final bool ok;
  final String? expectedHash;
  final String? actualHash;
  final List<String> errors;

  const CatalogVerifyResult({
    required this.ok,
    required this.expectedHash,
    required this.actualHash,
    required this.errors,
  });

  Map<String, Object?> toJson() => {
        'ok': ok,
        if (expectedHash != null) 'expectedHash': expectedHash,
        if (actualHash != null) 'actualHash': actualHash,
        if (errors.isNotEmpty) 'errors': errors,
      };
}

/// Structured lifecycle event emitted by [CatalogManager.events].
/// Consumed by the headless API server which fans these out to clients
/// as `NightshadeEvent`s in the `catalog` category.
class CatalogEvent {
  final String eventType;
  final Map<String, Object?> data;

  const CatalogEvent._(this.eventType, this.data);

  factory CatalogEvent.downloadStarted({
    String? jobId,
    required String name,
    required String downloadUrl,
    required int totalBytes,
  }) =>
      CatalogEvent._('CatalogDownloadStarted', {
        if (jobId != null) 'jobId': jobId,
        'name': name,
        'downloadUrl': downloadUrl,
        'totalBytes': totalBytes,
      });

  factory CatalogEvent.downloadProgress({
    String? jobId,
    required String name,
    required int downloadedBytes,
    required int totalBytes,
  }) =>
      CatalogEvent._('CatalogDownloadProgress', {
        if (jobId != null) 'jobId': jobId,
        'name': name,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        if (totalBytes > 0)
          'pct': (downloadedBytes / totalBytes).clamp(0.0, 1.0),
      });

  factory CatalogEvent.downloadComplete({
    String? jobId,
    required String name,
    required String version,
    required int sizeBytes,
    required String sha256,
  }) =>
      CatalogEvent._('CatalogDownloadComplete', {
        if (jobId != null) 'jobId': jobId,
        'name': name,
        'version': version,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      });

  factory CatalogEvent.downloadFailed({
    String? jobId,
    required String name,
    required String error,
    required String phase,
  }) =>
      CatalogEvent._('CatalogDownloadFailed', {
        if (jobId != null) 'jobId': jobId,
        'name': name,
        'error': error,
        'phase': phase,
      });

  factory CatalogEvent.verified({
    required String name,
    required bool ok,
    List<String>? errors,
  }) =>
      CatalogEvent._('CatalogVerified', {
        'name': name,
        'ok': ok,
        if (errors != null && errors.isNotEmpty) 'errors': errors,
      });

  factory CatalogEvent.uninstalled({required String name}) =>
      CatalogEvent._('CatalogUninstalled', {'name': name});

  const CatalogEvent.reloaded()
      : eventType = 'CatalogReloaded',
        data = const {};
}

/// Exception thrown by [CatalogManager.downloadAndInstall] when a
/// cancellation token requested abort.
class CatalogCancelled implements Exception {
  const CatalogCancelled();
  @override
  String toString() => 'CatalogCancelled';
}

/// Exception thrown when SHA-256 of an uploaded catalog does not match
/// the expected value.
class CatalogHashMismatchException implements Exception {
  final String expected;
  final String actual;
  const CatalogHashMismatchException({
    required this.expected,
    required this.actual,
  });
  @override
  String toString() =>
      'CatalogHashMismatchException(expected=$expected, actual=$actual)';
}

/// Exception raised by the catalog download path with a `phase` tag so
/// the API can surface "what was being attempted when this broke".
class CatalogDownloadException implements Exception {
  final String phase;
  final String message;
  const CatalogDownloadException({
    required this.phase,
    required this.message,
  });
  @override
  String toString() => 'CatalogDownloadException($phase): $message';
}
