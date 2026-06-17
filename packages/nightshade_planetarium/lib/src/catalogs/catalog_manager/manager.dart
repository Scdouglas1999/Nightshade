part of '../catalog_manager.dart';

/// Manages astronomical catalog downloads, installation, and access
class CatalogManager {
  static CatalogManager? _instance;
  static CatalogManager get instance => _instance ??= CatalogManager._();

  CatalogManager._();

  String? _catalogDirectory;
  final _downloadController = StreamController<DownloadProgress>.broadcast();

  /// In-flight legacy downloads keyed by catalog key (`stars`, `dso`,
  /// `annotation`). Kept on the singleton so download state outlives any
  /// individual widget: a settings screen can be disposed and recreated while
  /// a download runs, and read [activeDownloads] on rebuild to restore the
  /// live progress bar instead of looking idle.
  final Map<String, DownloadProgress> _activeDownloads = {};

  /// Lifecycle events for the unified catalog API used by the
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

  /// Snapshot of legacy downloads currently in flight, keyed by catalog key
  /// (`stars`, `dso`, `annotation`). A UI subscribing to [downloadProgress]
  /// should seed itself from this on first build so progress survives
  /// navigation away from and back to the catalog screen.
  Map<String, DownloadProgress> get activeDownloads =>
      Map.unmodifiable(_activeDownloads);

  /// Whether a download for [catalogKey] is currently in flight.
  bool isDownloading(String catalogKey) =>
      _activeDownloads.containsKey(catalogKey);

  /// Publish a progress update: update the in-flight registry, fan it out on
  /// [downloadProgress], and invoke the caller's [onProgress] callback. The
  /// single choke point that keeps the registry and the stream in lockstep.
  void _emitProgress(
    DownloadProgress progress,
    void Function(DownloadProgress)? onProgress,
  ) {
    final key = progress.catalogKey;
    if (key != null) {
      if (progress.isTerminal) {
        _activeDownloads.remove(key);
      } else {
        _activeDownloads[key] = progress;
      }
    }
    if (!_downloadController.isClosed) {
      _downloadController.add(progress);
    }
    onProgress?.call(progress);
  }

  /// Stream of structured lifecycle events used by the headless
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
      level: 800,
    );
  }

  /// Get the catalog directory path
  String get catalogDirectory {
    if (_catalogDirectory == null) {
      throw StateError(
        'CatalogManager not initialized. Call initialize() first.',
      );
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

    // A zero-byte file is the fingerprint of an interrupted or failed
    // download (a half-written catalog), not a usable install. Report it as
    // not installed so the UI offers a re-download instead of a broken
    // "Installed" badge.
    final fileSize = await file.length();
    if (fileSize == 0) {
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
        developer.log(
          '[Catalog]: Failed to parse metadata: $e',
          name: 'CatalogManager',
          level: 900,
        );
      }
    }

    return CatalogStatus(
      isInstalled: true,
      installedPath: filePath,
      installedDate: installedDate,
      installedPackage: package,
      objectCount: objectCount,
      version: version,
      fileSizeBytes: fileSize,
    );
  }

  /// Get the file path for the star catalog
  String get starCatalogPath =>
      path.join(catalogDirectory, hygStarCatalog.fileName);

  /// Get the file path for the DSO catalog
  String get dsoCatalogPath =>
      path.join(catalogDirectory, openNgcCatalog.fileName);

  /// Get the file path for the annotation catalog (GLADE+)
  String get annotationCatalogPath =>
      path.join(catalogDirectory, gladePlusCatalog.fileName);

  /// Dispose resources
  void dispose() {
    _downloadController.close();
    _eventController.close();
  }

  // ===========================================================================
  // Unified catalog API for the headless `/api/catalog/...` surface.
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

  /// Search both star and DSO catalogs.
  Future<List<CatalogSearchResult>> search(String query) =>
      _searchCatalogs(query);

  /// Search for DSOs near a given RA/Dec position.
  Future<List<OpenNgcData>> searchDsoNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) => _searchDsoCatalogNearby(
    ra: ra,
    dec: dec,
    radiusDegrees: radiusDegrees,
    maxMagnitude: maxMagnitude,
  );

  /// Search for stars near a given RA/Dec position.
  Future<List<HygStarData>> searchStarsNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
  }) => _searchStarCatalogNearby(
    ra: ra,
    dec: dec,
    radiusDegrees: radiusDegrees,
    maxMagnitude: maxMagnitude,
  );

  /// Download and install the star catalog.
  Future<bool> downloadStarCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) => _downloadStarCatalog(
    package: package,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// Download and install the DSO catalog.
  Future<bool> downloadDsoCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) => _downloadDsoCatalog(
    package: package,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// Import a star or DSO catalog from a custom location.
  Future<bool> importCatalog({
    required String sourcePath,
    required String type,
  }) => _importCatalog(sourcePath: sourcePath, type: type);

  /// Delete installed star and DSO catalogs.
  Future<void> deleteCatalogs() => _deleteCatalogs();

  /// Check if the annotation catalog is installed.
  Future<CatalogStatus> getAnnotationCatalogStatus() =>
      _getAnnotationCatalogStatus();

  /// Download and install the annotation catalog.
  Future<bool> downloadAnnotationCatalog({
    AnnotationPackage package = AnnotationPackage.standard,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) => _downloadAnnotationCatalogEntry(
    package: package,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// Import the annotation catalog from a local file.
  Future<bool> importAnnotationCatalog({
    required String sourcePath,
    AnnotationPackage package = AnnotationPackage.standard,
  }) => _importAnnotationCatalog(sourcePath: sourcePath, package: package);

  /// Delete the annotation catalog.
  Future<void> deleteAnnotationCatalog() => _deleteAnnotationCatalog();

  /// Get installed annotation package info.
  Future<AnnotationPackage?> getInstalledAnnotationPackage() =>
      _getInstalledAnnotationPackage();

  /// Returns the on-disk state for every known catalog.
  Future<List<InstalledCatalogStatus>> getInstalledStatuses() =>
      _getInstalledCatalogStatuses();

  /// Lists the catalogs available for download.
  Future<List<AvailableCatalog>> listAvailable() => _listAvailableCatalogs();

  /// Download and install a catalog by name.
  Future<CatalogInstallResult> downloadAndInstall(
    String name, {
    String? jobId,
    void Function(int downloaded, int total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) => _downloadAndInstallCatalog(
    name,
    jobId: jobId,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// Install a catalog from a pre-staged file on disk.
  Future<CatalogInstallResult> installFromFile({
    required String name,
    required File source,
    String? expectedSha256,
  }) => _installCatalogFromFile(
    name: name,
    source: source,
    expectedSha256: expectedSha256,
  );

  /// Uninstall a catalog by name.
  Future<bool> uninstall(String name) => _uninstallCatalog(name);

  /// Re-load any cached catalog loaders.
  Future<void> reload() => _reloadCatalogs();

  /// Verify installed catalogs against their metadata hashes.
  Future<Map<String, CatalogVerifyResult>> verify({String? name}) =>
      _verifyCatalogs(name: name);
}
