import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import 'logging_service.dart';

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

final annotationServiceProvider = Provider<AnnotationService>((ref) {
  return AnnotationService(ref);
});

final currentAnnotationProvider = StateProvider<ImageAnnotation?>((ref) => null);

/// Status of the annotation processing pipeline
enum AnnotationStatus {
  idle,
  checkingCatalogs,
  plateSolving,
  searchingCatalogs,
  complete,
  error,
  catalogsNotInstalled,
  plateSolveFailed,
}

/// Current annotation processing state with status and message
class AnnotationState {
  final AnnotationStatus status;
  final String? message;
  final String? errorDetails;
  final int? objectsFound;

  const AnnotationState({
    this.status = AnnotationStatus.idle,
    this.message,
    this.errorDetails,
    this.objectsFound,
  });

  const AnnotationState.idle() : this();

  const AnnotationState.checking()
      : this(status: AnnotationStatus.checkingCatalogs, message: 'Checking catalogs...');

  const AnnotationState.plateSolving()
      : this(status: AnnotationStatus.plateSolving, message: 'Plate solving...');

  const AnnotationState.searching()
      : this(status: AnnotationStatus.searchingCatalogs, message: 'Searching catalogs...');

  AnnotationState.complete(int objects)
      : this(
          status: AnnotationStatus.complete,
          message: 'Found $objects objects',
          objectsFound: objects,
        );

  const AnnotationState.error(String error)
      : this(status: AnnotationStatus.error, message: 'Error', errorDetails: error);

  const AnnotationState.catalogsNotInstalled()
      : this(
          status: AnnotationStatus.catalogsNotInstalled,
          message: 'No catalogs installed',
        );

  const AnnotationState.plateSolveFailed(String reason)
      : this(
          status: AnnotationStatus.plateSolveFailed,
          message: 'Plate solve failed',
          errorDetails: reason,
        );

  bool get isProcessing =>
      status == AnnotationStatus.checkingCatalogs ||
      status == AnnotationStatus.plateSolving ||
      status == AnnotationStatus.searchingCatalogs;
}

/// Provider for current annotation processing state
final annotationStateProvider = StateProvider<AnnotationState>((ref) => const AnnotationState.idle());

/// Constants for SNR-based progressive annotation reveal
class _SnrAnnotationConstants {
  /// Base SNR value (minimum detectable) - objects only shown if SNR >= this
  static const double baseSnr = 3.0;

  /// Base magnitude limit when SNR is at baseSnr
  static const double baseMagnitude = 15.0;

  /// Maximum magnitude limit regardless of SNR
  static const double maxMagnitude = 20.0;

  /// Minimum SNR improvement ratio before re-annotating (20% improvement)
  static const double snrImprovementThreshold = 1.2;

  /// Minimum time between re-annotations (5 seconds)
  static const Duration reAnnotationDebounce = Duration(seconds: 5);

  /// Minimum SNR to even attempt annotation
  static const double minimumSnrThreshold = 2.0;
}

/// Service responsible for generating and managing image annotations
class AnnotationService {
  final Ref _ref;
  final CatalogManager _catalogManager;
  AnnotationCatalog? _annotationCatalog;
  String? _annotationCatalogPath;
  String? _dsoCatalogPath;

  // External providers
  final _simbadProvider = SimbadProvider();
  final _exoplanetProvider = ExoplanetProvider();
  final _gaiaProvider = GaiaProvider();

  // Keep track of processed images to avoid duplicates
  String? _lastProcessedImagePath;

  // SNR-based progressive annotation state
  double? _lastAnnotationSnr;
  DateTime? _lastAnnotationTime;
  double _currentSnrMagnitudeLimit = _SnrAnnotationConstants.baseMagnitude;
  PlateSolveData? _lastPlateSolve;
  final Set<String> _revealedObjectIds = {};

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  AnnotationService(this._ref, {CatalogManager? catalogManager})
      : _catalogManager = catalogManager ?? CatalogManager.instance {
    _initListener();
  }

  void _initListener() {
    // Listen to new images and trigger annotation processing
    _ref.listen<CapturedImageData?>(currentImageProvider, (previous, next) {
      if (next != null && next.filePath != null && next.filePath != _lastProcessedImagePath) {
        _lastProcessedImagePath = next.filePath;
        // Reset SNR tracking for new image
        _lastAnnotationSnr = null;
        _lastAnnotationTime = null;
        _currentSnrMagnitudeLimit = _SnrAnnotationConstants.baseMagnitude;
        _revealedObjectIds.clear();
        _processNewImage(next);
      }
    });

    // Listen to image stats for SNR-based progressive re-annotation
    _ref.listen<ImageStats?>(lastImageStatsProvider, (previous, next) {
      if (next?.snr != null && _lastPlateSolve != null) {
        _checkSnrForReAnnotation(next!.snr!);
      }
    });
  }

  /// Calculate magnitude limit based on current SNR
  /// Formula: magnitudeLimit = baseMagnitude + log2(currentSNR / baseSNR) * 1.5
  double _calculateSnrBasedMagnitudeLimit(double snr) {
    if (snr <= _SnrAnnotationConstants.baseSnr) {
      return _SnrAnnotationConstants.baseMagnitude;
    }

    final snrRatio = snr / _SnrAnnotationConstants.baseSnr;
    final magnitudeBoost = (math.log(snrRatio) / math.ln2) * 1.5;
    final limit = _SnrAnnotationConstants.baseMagnitude + magnitudeBoost;

    return limit.clamp(
      _SnrAnnotationConstants.baseMagnitude,
      _SnrAnnotationConstants.maxMagnitude,
    );
  }

  /// Check if SNR has improved enough to warrant re-annotation
  void _checkSnrForReAnnotation(double currentSnr) {
    // Skip if we're already processing
    final state = _ref.read(annotationStateProvider);
    if (state.isProcessing) return;

    // Skip if SNR is too low
    if (currentSnr < _SnrAnnotationConstants.minimumSnrThreshold) return;

    // Skip if we don't have a previous annotation to build upon
    final currentAnnotation = _ref.read(currentAnnotationProvider);
    if (currentAnnotation == null || _lastPlateSolve == null) return;

    // Check if enough time has passed since last annotation
    if (_lastAnnotationTime != null) {
      final elapsed = DateTime.now().difference(_lastAnnotationTime!);
      if (elapsed < _SnrAnnotationConstants.reAnnotationDebounce) return;
    }

    // Calculate new magnitude limit
    final newMagnitudeLimit = _calculateSnrBasedMagnitudeLimit(currentSnr);

    // Check if SNR improved significantly
    if (_lastAnnotationSnr != null) {
      final snrRatio = currentSnr / _lastAnnotationSnr!;
      if (snrRatio < _SnrAnnotationConstants.snrImprovementThreshold) return;

      // Also check if the new magnitude limit is actually higher
      if (newMagnitudeLimit <= _currentSnrMagnitudeLimit + 0.5) return;
    }

    // Trigger progressive re-annotation
    _logger.info('SNR improved from ${_lastAnnotationSnr?.toStringAsFixed(1) ?? "N/A"} to ${currentSnr.toStringAsFixed(1)}, '
        'updating magnitude limit from ${_currentSnrMagnitudeLimit.toStringAsFixed(1)} to ${newMagnitudeLimit.toStringAsFixed(1)}', source: 'Annotation');

    _progressiveReAnnotate(currentSnr, newMagnitudeLimit);
  }

  /// Re-annotate with a higher magnitude limit, keeping existing objects
  Future<void> _progressiveReAnnotate(double currentSnr, double newMagnitudeLimit) async {
    final currentAnnotation = _ref.read(currentAnnotationProvider);
    if (currentAnnotation == null || _lastPlateSolve == null) return;

    try {
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.searching();

      final settings = _ref.read(annotationSettingsProvider).valueOrNull;
      final includeStars = settings?.visibleTypes.contains(AnnotationObjectFilter.stars) ?? false;

      // Search for additional objects with the new, higher magnitude limit
      final additionalObjects = await findObjectsInFov(
        plateSolve: _lastPlateSolve!,
        includeStars: includeStars,
        minMagnitude: newMagnitudeLimit,
        snrBasedMagnitudeCutoff: newMagnitudeLimit,
      );

      // Filter to only new objects (not already revealed)
      final newObjects = additionalObjects.where((obj) => !_revealedObjectIds.contains(obj.id)).toList();

      if (newObjects.isEmpty) {
        _logger.debug('No new objects found at magnitude ${newMagnitudeLimit.toStringAsFixed(1)}', source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            AnnotationState.complete(currentAnnotation.objects.length);
        return;
      }

      // Add new object IDs to revealed set
      for (final obj in newObjects) {
        _revealedObjectIds.add(obj.id);
      }

      _logger.info('Found ${newObjects.length} new objects (total: ${_revealedObjectIds.length})', source: 'Annotation');

      // Merge new objects with existing annotation
      final mergedObjects = [...currentAnnotation.objects, ...newObjects];

      final updatedAnnotation = currentAnnotation.copyWith(
        objects: mergedObjects,
        timestamp: DateTime.now(),
      );

      // Update state
      _lastAnnotationSnr = currentSnr;
      _lastAnnotationTime = DateTime.now();
      _currentSnrMagnitudeLimit = newMagnitudeLimit;

      _ref.read(currentAnnotationProvider.notifier).state = updatedAnnotation;
      _ref.read(annotationStateProvider.notifier).state =
          AnnotationState.complete(updatedAnnotation.objects.length);

    } catch (e) {
      _logger.error('Error during progressive re-annotation: $e', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state =
          AnnotationState.error(e.toString());
    }
  }

  Future<AnnotationCatalog?> _loadAnnotationCatalog() async {
    final annotationStatus = await _catalogManager.getAnnotationCatalogStatus();
    if (!annotationStatus.isInstalled || annotationStatus.installedPath == null) {
      return null;
    }

    final dsoStatus = await _catalogManager.getDsoCatalogStatus();
    final annotationPath = annotationStatus.installedPath!;
    final dsoPath = dsoStatus.installedPath;

    if (_annotationCatalog != null &&
        _annotationCatalogPath == annotationPath &&
        _dsoCatalogPath == dsoPath) {
      return _annotationCatalog;
    }

    final gladeLoader = GladePlusCatalogLoader(annotationPath);
    final ngcLoader = dsoPath != null ? OpenNgcCatalogLoader(dsoPath) : null;

    _annotationCatalog = AnnotationCatalog(
      ngcLoader: ngcLoader,
      gladeLoader: gladeLoader,
    );
    _annotationCatalogPath = annotationPath;
    _dsoCatalogPath = dsoPath;

    return _annotationCatalog;
  }

  ObjectType _mapAnnotationObjectType(AnnotationObjectType type) {
    switch (type) {
      case AnnotationObjectType.galaxy:
        return ObjectType.galaxy;
      case AnnotationObjectType.nebula:
      case AnnotationObjectType.emissionNebula:
      case AnnotationObjectType.reflectionNebula:
      case AnnotationObjectType.darkNebula:
      case AnnotationObjectType.hiiRegion:
        return ObjectType.nebula;
      case AnnotationObjectType.planetaryNebula:
        return ObjectType.planetaryNebula;
      case AnnotationObjectType.openCluster:
      case AnnotationObjectType.globularCluster:
      case AnnotationObjectType.starCluster:
        return ObjectType.starCluster;
      case AnnotationObjectType.doubleStar:
        return ObjectType.doubleStar;
      case AnnotationObjectType.asterism:
        return ObjectType.asterism;
      case AnnotationObjectType.supernovaRemnant:
      case AnnotationObjectType.other:
        return ObjectType.unknown;
    }
  }

  Future<void> _processNewImage(CapturedImageData image) async {
    if (image.filePath == null) {
      _logger.debug('Skipping annotation - no file path', source: 'Annotation');
      return;
    }

    // Check if auto-annotate is enabled
    final settings = _ref.read(annotationSettingsProvider).valueOrNull;
    if (settings != null && !settings.autoAnnotate) {
      _logger.debug('Auto-annotate disabled, skipping', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.idle();
      return;
    }

    // Check if annotations are enabled at all
    if (settings != null && !settings.enabled) {
      _logger.debug('Annotations disabled, skipping', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.idle();
      return;
    }

    _logger.info('New image detected: ${image.filePath}', source: 'Annotation');

    try {
      // =====================================================================
      // PRE-FLIGHT CHECK 1: Verify CatalogManager is initialized
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.checking();

      if (!_catalogManager.isInitialized) {
        _logger.warning('CatalogManager not initialized - catalogs not available', source: 'Annotation');
        // CatalogManager should be initialized by the app on startup
        // If not initialized here, it means catalogs haven't been set up
        _ref.read(annotationStateProvider.notifier).state =
            const AnnotationState.catalogsNotInstalled();
        return;
      }

      // =====================================================================
      // PRE-FLIGHT CHECK 2: Verify at least one catalog is installed
      // =====================================================================
      final dsoStatus = await _catalogManager.getDsoCatalogStatus();
      final starStatus = await _catalogManager.getStarCatalogStatus();
      final annotationStatus = await _catalogManager.getAnnotationCatalogStatus();

      final hasDsoCatalog = dsoStatus.isInstalled;
      final hasStarCatalog = starStatus.isInstalled;
      final hasAnnotationCatalog = annotationStatus.isInstalled;

      if (!hasDsoCatalog && !hasStarCatalog && !hasAnnotationCatalog) {
        _logger.warning('No catalogs installed - DSO: $hasDsoCatalog, Stars: $hasStarCatalog, Annotation: $hasAnnotationCatalog', source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            const AnnotationState.catalogsNotInstalled();
        return;
      }

      _logger.info('Catalogs available - DSO: $hasDsoCatalog, Stars: $hasStarCatalog, Annotation: $hasAnnotationCatalog', source: 'Annotation');

      // =====================================================================
      // PRE-FLIGHT CHECK 3: Verify backend is available
      // =====================================================================
      final backend = _ref.read(backendProvider);
      if (backend is DisconnectedBackend) {
        _logger.error('Backend disconnected, cannot plate solve', source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            const AnnotationState.error('Backend not connected');
        return;
      }

      // =====================================================================
      // STEP 1: Plate Solve
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.plateSolving();
      _logger.info('Starting plate solve for: ${image.filePath}', source: 'Annotation');

      // Try to get mount position hints for faster solving
      double? hintRa;
      double? hintDec;
      try {
        final mountState = _ref.read(mountStateProvider);
        if (mountState.ra != null && mountState.dec != null) {
          // Mount RA is typically tracked in hours; plate-solve hints expect degrees.
          hintRa = _normalizeRaHintDegrees(mountState.ra!);
          hintDec = mountState.dec;
          _logger.debug('Using mount position hints: RA=$hintRa, Dec=$hintDec', source: 'Annotation');
        }
      } catch (e) {
        // Mount state not available, continue without hints
        _logger.debug('Mount position hints not available', source: 'Annotation');
      }

      final result = await backend.plateSolve(
        imagePath: image.filePath!,
        ra: hintRa,
        dec: hintDec,
      );

      if (!result.success) {
        _logger.warning('Plate solve failed: ${result.error}', source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            AnnotationState.plateSolveFailed(result.error ?? 'Unknown error');
        return;
      }

      _logger.info('Plate solve success: RA=${result.ra.toStringAsFixed(4)}, '
          'Dec=${result.dec.toStringAsFixed(4)}, '
          'Scale=${result.pixelScale.toStringAsFixed(2)}"/px, '
          'Rotation=${result.rotation.toStringAsFixed(1)} deg', source: 'Annotation');

      // =====================================================================
      // STEP 2: Create PlateSolveData
      // =====================================================================
      final plateSolveData = PlateSolveData(
        ra: result.ra,
        dec: result.dec,
        pixelScale: result.pixelScale,
        rotation: result.rotation,
        fieldWidth: result.fieldWidth,
        fieldHeight: result.fieldHeight,
        imageWidth: image.width,
        imageHeight: image.height,
      );

      // Store plate solve for progressive re-annotation
      _lastPlateSolve = plateSolveData;

      // =====================================================================
      // STEP 3: Calculate initial SNR-based magnitude limit
      // =====================================================================
      final currentSnr = image.stats.snr;
      double initialMagnitudeLimit;

      if (currentSnr != null && currentSnr >= _SnrAnnotationConstants.minimumSnrThreshold) {
        initialMagnitudeLimit = _calculateSnrBasedMagnitudeLimit(currentSnr);
        _lastAnnotationSnr = currentSnr;
        _logger.debug('Initial SNR: ${currentSnr.toStringAsFixed(2)}, magnitude limit: ${initialMagnitudeLimit.toStringAsFixed(1)}', source: 'Annotation');
      } else {
        // If no SNR available or too low, use conservative base magnitude
        initialMagnitudeLimit = _SnrAnnotationConstants.baseMagnitude;
        _logger.debug('SNR not available or too low, using base magnitude limit: ${initialMagnitudeLimit.toStringAsFixed(1)}', source: 'Annotation');
      }

      _currentSnrMagnitudeLimit = initialMagnitudeLimit;
      _lastAnnotationTime = DateTime.now();

      // =====================================================================
      // STEP 4: Search Catalogs
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state = const AnnotationState.searching();

      // Get annotation settings for filtering
      final includeStars = settings?.visibleTypes.contains(AnnotationObjectFilter.stars) ?? false;
      final userMagnitudeCutoff = settings?.magnitudeCutoff ?? 15.0;

      // Use the minimum of SNR-based limit and user setting for initial search
      final effectiveMagnitudeLimit = math.min(initialMagnitudeLimit, userMagnitudeCutoff);

      _logger.debug('Searching catalogs with magnitude cutoff: ${effectiveMagnitudeLimit.toStringAsFixed(1)} '
          '(SNR-based: ${initialMagnitudeLimit.toStringAsFixed(1)}, user: ${userMagnitudeCutoff.toStringAsFixed(1)}), '
          'include stars: $includeStars', source: 'Annotation');

      final annotation = await annotateImage(
        imagePath: image.filePath!,
        plateSolve: plateSolveData,
        includeStars: includeStars && hasStarCatalog,
        minMagnitude: effectiveMagnitudeLimit,
        snrBasedMagnitudeCutoff: effectiveMagnitudeLimit,
      );

      // Track revealed object IDs for progressive updates
      for (final obj in annotation.objects) {
        _revealedObjectIds.add(obj.id);
      }

      // =====================================================================
      // STEP 5: Update providers with result
      // =====================================================================
      _ref.read(currentAnnotationProvider.notifier).state = annotation;
      _ref.read(annotationStateProvider.notifier).state =
          AnnotationState.complete(annotation.objects.length);

      _logger.info('Annotation complete: ${annotation.objects.length} objects found', source: 'Annotation');

    } catch (e, stackTrace) {
      _logger.error('Error processing image: $e\nStack trace: $stackTrace', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state =
          AnnotationState.error(e.toString());
    }
  }

  Stream<ImageAnnotation> get annotationStream => 
      _ref.read(currentAnnotationProvider.notifier).stream.where((a) => a != null).cast<ImageAnnotation>();

  /// Identify an object at specific pixel coordinates
  Future<CelestialObjectAnnotation?> identifyAtPixel({
    required PlateSolveData plateSolve,
    required double x,
    required double y,
    double? searchRadiusArcsec,
  }) async {
    // Convert pixels to RA/Dec
    final coords = plateSolve.pixelToSky(x, y);
    
    _logger.debug('Identifying object at $x, $y -> RA: ${coords.ra}, Dec: ${coords.dec}', source: 'Annotation');
    
    // Search for object at these coordinates
    final settings = _ref.read(annotationSettingsProvider).valueOrNull;
    final effectiveRadiusArcsec = (searchRadiusArcsec ??
            settings?.clickSearchRadiusArcsec ??
            const AnnotationSettings().clickSearchRadiusArcsec)
        .clamp(1.0, 600.0);

    final details = await getObjectDetails(
      ra: coords.ra,
      dec: coords.dec,
      radiusArcmin: effectiveRadiusArcsec / 60.0,
    );
    
    if (details == null) return null;
    
    // Convert to annotation format
    final objectType = _inferObjectType(details.objectClass);
    final name = details.catalogIds?['Name'] ?? 
                 (details.catalogIds?['NGC'] != null ? 'NGC ${details.catalogIds!['NGC']}' : null) ??
                 (details.catalogIds?['M'] != null ? 'M ${details.catalogIds!['M']}' : null) ??
                 details.simbadId ?? 'Unknown Object';
                 
    return CelestialObjectAnnotation(
      id: 'identified_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: objectType,
      ra: coords.ra,
      dec: coords.dec,
      x: x,
      y: y,
      catalogId: details.catalogIds?.entries.firstOrNull?.value,
      detailedData: details,
    );
  }

  /// Generate annotations for an image given its plate solve result
  ///
  /// [snrBasedMagnitudeCutoff] - Optional magnitude cutoff based on current SNR.
  /// If provided, this is used for progressive annotation reveal.
  Future<ImageAnnotation> annotateImage({
    required String imagePath,
    required PlateSolveData plateSolve,
    bool includeStars = true,
    double minMagnitude = 15.0,
    double minSize = 0.5,
    double? snrBasedMagnitudeCutoff,
  }) async {
    _logger.info('Starting annotation for $imagePath', source: 'Annotation');

    final objects = await findObjectsInFov(
      plateSolve: plateSolve,
      includeStars: includeStars,
      minMagnitude: minMagnitude,
      minSize: minSize,
      snrBasedMagnitudeCutoff: snrBasedMagnitudeCutoff,
    );

    _logger.info('Found ${objects.length} objects in FOV', source: 'Annotation');

    return ImageAnnotation(
      imagePath: imagePath,
      timestamp: DateTime.now(),
      plateSolve: plateSolve,
      objects: objects,
    );
  }

  /// Find all catalog objects within the field of view
  ///
  /// [snrBasedMagnitudeCutoff] - Optional magnitude cutoff based on current SNR.
  /// If provided, this takes precedence over [minMagnitude] for filtering objects.
  Future<List<CelestialObjectAnnotation>> findObjectsInFov({
    required PlateSolveData plateSolve,
    bool includeStars = false,
    double minMagnitude = 15.0,
    double minSize = 0.5,
    double? snrBasedMagnitudeCutoff,
   }) async {
    final annotations = <CelestialObjectAnnotation>[];

    // Use SNR-based cutoff if provided, otherwise use minMagnitude
    final effectiveMagnitudeCutoff = snrBasedMagnitudeCutoff ?? minMagnitude;

    // Calculate search radius (diagonal of FOV)
    final fovDiagonal = math.sqrt(plateSolve.fieldWidth * plateSolve.fieldWidth +
            plateSolve.fieldHeight * plateSolve.fieldHeight);
    final searchRadius = fovDiagonal / 2 * 1.1; // Add 10% margin

    _logger.debug('Searching DSO catalog within $searchRadius degrees of RA=${plateSolve.ra}, Dec=${plateSolve.dec}, '
        'magnitude cutoff: ${effectiveMagnitudeCutoff.toStringAsFixed(1)}', source: 'Annotation');

    final annotationCatalog = await _loadAnnotationCatalog();
    if (annotationCatalog != null && annotationCatalog.isAvailable) {
      try {
        final objects = await annotationCatalog.searchNearby(
          ra: plateSolve.ra,
          dec: plateSolve.dec,
          radiusDegrees: searchRadius,
          maxMagnitude: effectiveMagnitudeCutoff,
        );

        _logger.debug('Found ${objects.length} annotation objects in search area', source: 'Annotation');

        for (final obj in objects) {
          if (obj.majorAxis != null && obj.majorAxis! < minSize) {
            continue;
          }

          final pixelCoords = plateSolve.skyToPixel(obj.ra, obj.dec);
          if (pixelCoords == null) {
            continue;
          }

          if (pixelCoords.x < 0 || pixelCoords.x >= plateSolve.imageWidth ||
              pixelCoords.y < 0 || pixelCoords.y >= plateSolve.imageHeight) {
            continue;
          }

          final altName = obj.alternateNames.isNotEmpty ? obj.alternateNames.first : null;

          annotations.add(CelestialObjectAnnotation(
            id: obj.id,
            name: obj.primaryName,
            type: _mapAnnotationObjectType(obj.type),
            ra: obj.ra,
            dec: obj.dec,
            x: pixelCoords.x,
            y: pixelCoords.y,
            catalogId: altName ?? obj.primaryName,
            commonName: altName != null && altName != obj.primaryName ? altName : null,
            magnitude: obj.magnitude,
            size: obj.majorAxis,
          ));
        }
      } catch (e) {
        _logger.error('Error querying annotation catalog: $e', source: 'Annotation');
      }
    } else {
      // Query DSO catalog
      try {
        final dsos = await _catalogManager.searchDsoNearby(
          ra: plateSolve.ra,
          dec: plateSolve.dec,
          radiusDegrees: searchRadius,
          maxMagnitude: effectiveMagnitudeCutoff,
        );

        _logger.debug('Found ${dsos.length} DSOs in search area', source: 'Annotation');

        for (final dso in dsos) {
          // Filter by size (skip very small objects)
          if (dso.majorAxis != null && dso.majorAxis! < minSize) {
            continue;
          }

          // Convert RA/Dec to pixel coordinates
          final pixelCoords = plateSolve.skyToPixel(dso.ra, dso.dec);
          if (pixelCoords == null) {
            continue;
          }

          // Check if pixel coordinates are within image bounds
          if (pixelCoords.x < 0 || pixelCoords.x >= plateSolve.imageWidth ||
              pixelCoords.y < 0 || pixelCoords.y >= plateSolve.imageHeight) {
            continue;
          }

          final objectType = _inferObjectType(dso.type);

          annotations.add(CelestialObjectAnnotation(
            id: 'dso_${dso.name}',
            name: dso.displayName,
            type: objectType,
            ra: dso.ra,
            dec: dso.dec,
            x: pixelCoords.x,
            y: pixelCoords.y,
            catalogId: dso.name,
            magnitude: dso.magnitude,
            size: dso.majorAxis,
          ));
        }
      } catch (e) {
        _logger.error('Error querying DSO catalog: $e', source: 'Annotation');
      }
    }

    // Optionally include bright stars
    if (includeStars) {
      try {
        // For stars, apply the SNR-based cutoff more aggressively
        final starMagnitudeCutoff = effectiveMagnitudeCutoff.clamp(0.0, 10.0);
        final stars = await _catalogManager.searchStarsNearby(
          ra: plateSolve.ra,
          dec: plateSolve.dec,
          radiusDegrees: searchRadius,
          maxMagnitude: starMagnitudeCutoff,
        );

        _logger.debug('Found ${stars.length} stars in search area', source: 'Annotation');

        for (final star in stars.take(100)) {
          final pixelCoords = plateSolve.skyToPixel(star.ra, star.dec);
          if (pixelCoords == null) continue;

          // Check if pixel coordinates are within image bounds
          if (pixelCoords.x < 0 || pixelCoords.x >= plateSolve.imageWidth ||
              pixelCoords.y < 0 || pixelCoords.y >= plateSolve.imageHeight) {
            continue;
          }

          annotations.add(CelestialObjectAnnotation(
            id: 'star_${star.id}',
            name: star.properName ?? star.catalogId,
            type: ObjectType.star,
            ra: star.ra,
            dec: star.dec,
            x: pixelCoords.x,
            y: pixelCoords.y,
            catalogId: star.catalogId,
            magnitude: star.magnitude,
          ));
        }
      } catch (e) {
        _logger.error('Error querying star catalog: $e', source: 'Annotation');
      }
    }

    _logger.debug('Total annotations: ${annotations.length}', source: 'Annotation');
    return annotations;
  }

  /// Get detailed information about an object at given coordinates
  Future<ObjectData?> getObjectDetails({
    required double ra,
    required double dec,
    double radiusArcmin = 1.0,
  }) async {
    ObjectData? result;

    // 1. Check local DSO catalog first (fast)
    final radiusDeg = radiusArcmin / 60.0;
    try {
      final dsos = await _catalogManager.searchDsoNearby(
        ra: ra,
        dec: dec,
        radiusDegrees: radiusDeg,
      );

      if (dsos.isNotEmpty) {
        // Find the closest object
        final closest = dsos.reduce((a, b) {
          final distA = _angularDistance(ra, dec, a.ra, a.dec);
          final distB = _angularDistance(ra, dec, b.ra, b.dec);
          return distA < distB ? a : b;
        });

        result = ObjectData(
          description: closest.typeDescription,
          objectClass: closest.typeDescription,
          catalogIds: {
            'Name': closest.displayName,
            if (closest.messier != null) 'M': closest.messier!.replaceAll('M', ''),
            if (closest.name.startsWith('NGC')) 'NGC': closest.name.replaceAll('NGC', '').trim(),
            if (closest.name.startsWith('IC')) 'IC': closest.name.replaceAll('IC', '').trim(),
          },
          lastUpdated: DateTime.now(),
          dataSource: 'Local Catalog',
        );

        _logger.debug('Found in local DSO catalog: ${closest.displayName}', source: 'Annotation');
      }
    } catch (e) {
      _logger.error('Error searching local DSO catalog: $e', source: 'Annotation');
    }

    // Also check local star catalog
    if (result == null) {
      try {
        final stars = await _catalogManager.searchStarsNearby(
          ra: ra,
          dec: dec,
          radiusDegrees: radiusDeg,
        );

        if (stars.isNotEmpty) {
          // Find the closest star
          final closest = stars.reduce((a, b) {
            final distA = _angularDistance(ra, dec, a.ra, a.dec);
            final distB = _angularDistance(ra, dec, b.ra, b.dec);
            return distA < distB ? a : b;
          });

          result = ObjectData(
            description: 'Star',
            objectClass: 'Star',
            spectralType: _parseSpectralType(closest.spectralType),
            distance: closest.distance,
            catalogIds: {
              'Name': closest.name,
              if (closest.hipId != null) 'HIP': closest.hipId.toString(),
              if (closest.hdId != null) 'HD': closest.hdId.toString(),
            },
            lastUpdated: DateTime.now(),
            dataSource: 'Local Catalog',
          );

          _logger.debug('Found in local star catalog: ${closest.name}', source: 'Annotation');
        }
      } catch (e) {
        _logger.error('Error searching local star catalog: $e', source: 'Annotation');
      }
    }

    // 2. Query SIMBAD for identification and basic data
    try {
      final simbadData = await _simbadProvider.queryByCoordinates(ra, dec, radiusArcmin: radiusArcmin);
      if (simbadData != null) {
        // Merge with local data or use as base
        result = _mergeObjectData(result, simbadData);
      }
    } catch (e) {
      _logger.warning('SIMBAD query failed: $e', source: 'Annotation');
    }

    // 3. Query Gaia for stellar properties (if it looks like a star)
    if (result?.objectClass?.toLowerCase().contains('star') == true || result == null) {
      try {
        final gaiaData = await _gaiaProvider.queryByCoordinates(ra, dec);
        if (gaiaData != null) {
          result = _mergeObjectData(result, gaiaData);
        }
      } catch (e) {
        _logger.warning('Gaia query failed: $e', source: 'Annotation');
      }
    }

    // 4. Check for Exoplanets (if it's a star)
    if (result != null && result.catalogIds != null) {
      // Try to find a name to query
      final name = result.catalogIds?['Name'] ?? 
                   (result.catalogIds?['HD'] != null ? 'HD ${result.catalogIds!['HD']}' : null) ??
                   result.simbadId;
                   
      if (name != null) {
        try {
          final planets = await _exoplanetProvider.queryByStarName(name);
          if (planets.isNotEmpty) {
            result = result.copyWith(exoplanets: planets);
          }
        } catch (e) {
          _logger.warning('Exoplanet query failed: $e', source: 'Annotation');
        }
      }
    }

    return result;
  }

  ObjectData _mergeObjectData(ObjectData? base, ObjectData new_) {
    if (base == null) return new_;
    
    return base.copyWith(
      description: base.description ?? new_.description,
      objectClass: base.objectClass ?? new_.objectClass,
      spectralType: base.spectralType ?? new_.spectralType,
      temperature: base.temperature ?? new_.temperature,
      mass: base.mass ?? new_.mass,
      radius: base.radius ?? new_.radius,
      luminosity: base.luminosity ?? new_.luminosity,
      distance: base.distance ?? new_.distance,
      parallax: base.parallax ?? new_.parallax,
      properMotion: base.properMotion ?? new_.properMotion,
      surfaceBrightness: base.surfaceBrightness ?? new_.surfaceBrightness,
      redshift: base.redshift ?? new_.redshift,
      morphology: base.morphology ?? new_.morphology,
      simbadId: base.simbadId ?? new_.simbadId,
      wikipediaUrl: base.wikipediaUrl ?? new_.wikipediaUrl,
      // Merge maps
      catalogIds: {
        ...?base.catalogIds,
        ...?new_.catalogIds,
      },
      dataSource: '${base.dataSource}, ${new_.dataSource}',
    );
  }

  ObjectType _inferObjectType(String? catalogType) {
    if (catalogType == null) return ObjectType.unknown;
    final lower = catalogType.toLowerCase();
    if (lower.contains('galaxy') || lower.contains('gx')) return ObjectType.galaxy;
    if (lower.contains('nebula') && lower.contains('planetary')) return ObjectType.planetaryNebula;
    if (lower.contains('nebula') || lower.contains('neb')) return ObjectType.nebula;
    if (lower.contains('cluster') && lower.contains('open')) return ObjectType.starCluster;
    if (lower.contains('cluster') && lower.contains('globular')) return ObjectType.starCluster;
    if (lower.contains('cluster')) return ObjectType.starCluster;
    if (lower.contains('double') || lower.contains('multiple')) return ObjectType.doubleStar;
    if (lower.contains('asterism')) return ObjectType.asterism;
    return ObjectType.unknown;
  }

  /// Parse spectral type from string to SpectralClass enum
  SpectralClass? _parseSpectralType(String? spectralType) {
    if (spectralType == null || spectralType.isEmpty) return null;

    final firstChar = spectralType[0].toLowerCase();
    switch (firstChar) {
      case 'o':
        return SpectralClass.o;
      case 'b':
        return SpectralClass.b;
      case 'a':
        return SpectralClass.a;
      case 'f':
        return SpectralClass.f;
      case 'g':
        return SpectralClass.g;
      case 'k':
        return SpectralClass.k;
      case 'm':
        return SpectralClass.m;
      default:
        return SpectralClass.unknown;
    }
  }

  double _normalizeRaHintDegrees(double raValue) {
    // Heuristic: treat values in [0, 24] as hours; otherwise assume degrees.
    final degrees = (raValue >= 0.0 && raValue <= 24.0)
        ? raValue * 15.0
        : raValue;
    return ((degrees % 360.0) + 360.0) % 360.0;
  }
}
