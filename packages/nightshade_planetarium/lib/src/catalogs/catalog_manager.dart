import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
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
  HygCatalogLoader? _starLoader;
  String? _starLoaderPath;
  OpenNgcCatalogLoader? _dsoLoader;
  String? _dsoLoaderPath;
  
  /// Stream of download progress updates
  Stream<DownloadProgress> get downloadProgress => _downloadController.stream;
  
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
    
    debugPrint('[Catalog] initialized with directory: $catalogDirectory');
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
        debugPrint('[Catalog]: Failed to parse metadata: $e');
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
    debugPrint('[Catalog] Starting download of ${source.name} from ${source.downloadUrl}');
    
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
        debugPrint('[Catalog] Sending HTTP GET request to ${source.downloadUrl}');
        
        final request = http.Request('GET', Uri.parse(source.downloadUrl));
        final streamedResponse = await client.send(request);
        
        debugPrint('[Catalog] Response status: ${streamedResponse.statusCode}');
        
        if (streamedResponse.statusCode != 200) {
          final errorMsg = 'HTTP ${streamedResponse.statusCode}: Failed to download from ${source.downloadUrl}';
          debugPrint(errorMsg);
          final error = DownloadProgress.error(source.name, errorMsg);
          _downloadController.add(error);
          onProgress?.call(error);
          return false;
        }
        
        final contentLength = streamedResponse.contentLength ?? 0;
        final filePath = path.join(catalogDirectory, source.fileName);
        final file = File(filePath);
        final sink = file.openWrite();
        
        debugPrint('[Catalog] Writing to $filePath, expected size: $contentLength bytes');
        
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
          debugPrint('[Catalog] Decompressing gzip data...');
          try {
            finalBytes = Uint8List.fromList(
              gzip.decode(downloadedBytes)
            );
            debugPrint('[Catalog] Decompressed ${downloadedBytes.length} bytes to ${finalBytes.length} bytes');
          } catch (e) {
            debugPrint('[Catalog] Gzip decompression failed: $e');
            // Try to use the data as-is (maybe it wasn't actually gzipped)
            finalBytes = Uint8List.fromList(downloadedBytes);
          }
        } else {
          finalBytes = Uint8List.fromList(downloadedBytes);
        }
        
        // Write to file
        sink.add(finalBytes);
        await sink.close();
        
        debugPrint('[Catalog] Download complete: $bytesReceived bytes written to $filePath');
        
        // Verify file was written
        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }
        
        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }
        
        debugPrint('[Catalog] File verified: $fileSize bytes');
        
        // Count objects and save metadata
        final objectCount = await _countObjects(filePath);
        await _saveMetadata(type, source, package, objectCount);
        _invalidateLocalCatalogLoaders(
          stars: type == 'stars',
          dsos: type == 'dso',
        );
        
        debugPrint('[Catalog] Catalog saved with $objectCount objects');
        
        final complete = DownloadProgress.complete(source.name, bytesReceived);
        _downloadController.add(complete);
        onProgress?.call(complete);
        
        return true;
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      debugPrint(errorMsg);
      debugPrint('[Catalog] Stack trace: $stackTrace');
      
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
      debugPrint('[Catalog] Error counting objects: $e');
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
      debugPrint('[Catalog] Import error: $e');
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

    debugPrint('[Catalog] Starting download of ${source.name} (${package.displayName} tier)');
    debugPrint('[Catalog] VizieR TAP URL: $downloadUrl');

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
        debugPrint('[Catalog] Sending HTTP GET request to VizieR TAP...');

        final request = http.Request('GET', Uri.parse(downloadUrl));
        final streamedResponse = await client.send(request);

        debugPrint('[Catalog] Response status: ${streamedResponse.statusCode}');

        if (streamedResponse.statusCode != 200) {
          final errorMsg = 'HTTP ${streamedResponse.statusCode}: Failed to download from VizieR TAP';
          debugPrint(errorMsg);
          final error = DownloadProgress.error(source.name, errorMsg);
          _downloadController.add(error);
          onProgress?.call(error);
          return false;
        }

        final contentLength = streamedResponse.contentLength ?? 0;
        final filePath = path.join(catalogDirectory, source.fileName);
        final file = File(filePath);
        final sink = file.openWrite();

        debugPrint('[Catalog] Writing to $filePath, expected size: $contentLength bytes');

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

        debugPrint('[Catalog] Download complete: $bytesReceived bytes written to $filePath');

        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }

        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        debugPrint('[Catalog] File verified: $fileSize bytes');

        final objectCount = await _countObjects(filePath);
        await _saveAnnotationMetadata(source, package, objectCount);

        debugPrint('[Catalog] Annotation catalog saved with $objectCount objects');

        final complete = DownloadProgress.complete(source.name, bytesReceived);
        _downloadController.add(complete);
        onProgress?.call(complete);

        return true;
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      debugPrint(errorMsg);
      debugPrint('[Catalog] Stack trace: $stackTrace');

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
        debugPrint('[Catalog] Import source file not found: $sourcePath');
        return false;
      }

      final destPath = path.join(catalogDirectory, gladePlusCatalog.fileName);

      // Copy the file
      await sourceFile.copy(destPath);

      // Count objects and save metadata
      final objectCount = await _countObjects(destPath);
      await _saveAnnotationMetadata(gladePlusCatalog, package, objectCount);

      debugPrint('[Catalog] Annotation catalog imported: $objectCount objects from $sourcePath');
      return true;
    } catch (e) {
      debugPrint('[Catalog] Import annotation catalog error: $e');
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
    
    // Search DSO catalog if installed
    final dsoStatus = await getDsoCatalogStatus();
    if (dsoStatus.isInstalled) {
      try {
        final loader = _getDsoLoader(dsoStatus.installedPath!);
        final dsos = await loader.search(query);
        
        // Prioritize exact matches
        final exactMatches = dsos.where((d) => 
          d.name.toLowerCase() == q || 
          d.displayName.toLowerCase() == q
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
        debugPrint('[Catalog] DSO search error: $e');
      }
    }
    
    // Search Star catalog if installed
    final starStatus = await getStarCatalogStatus();
    if (starStatus.isInstalled) {
      try {
        final loader = _getStarLoader(starStatus.installedPath!);
        final stars = await loader.search(query);
        
        results.addAll(stars.take(20).map((s) => CatalogSearchResult(
          name: s.name,
          catalogId: s.catalogId,
          ra: s.ra,
          dec: s.dec,
          type: 'Star',
          magnitude: s.magnitude,
          constellation: s.constellation,
        )));
      } catch (e) {
        debugPrint('[Catalog] Star search error: $e');
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
      debugPrint('[Catalog] DSO searchNearby error: $e');
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
      debugPrint('[Catalog] Star searchNearby error: $e');
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    _downloadController.close();
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
      messier: parts.length > 23 && parts[23].isNotEmpty ? 'M${parts[23]}' : null,
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
      debugPrint('[Catalog] StarCatalogLoader: Skipped $malformedLines malformed lines');
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
    return all.where((s) {
      final name = s.name.toLowerCase();
      final catId = s.catalogId.toLowerCase();
      return name.contains(q) || catId.contains(q);
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
      debugPrint('[Catalog] DSOCatalogLoader: Skipped $malformedLines malformed lines');
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
    return all.where((d) {
      final name = d.name.toLowerCase();
      final displayName = d.displayName.toLowerCase();
      final common = d.commonNames?.toLowerCase() ?? '';
      return name.contains(q) || displayName.contains(q) || common.contains(q);
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
