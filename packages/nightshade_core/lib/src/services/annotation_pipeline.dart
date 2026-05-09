part of 'annotation_service.dart';

// ==========================================================================
// Annotation pipeline: plate solve -> catalog search -> merge logic
// ==========================================================================

extension AnnotationPipeline on AnnotationService {
  /// Process a new image through the full annotation pipeline:
  /// plate solve -> catalog search -> object merge -> state update.
  Future<void> processNewImage(CapturedImageData image) async {
    if (image.filePath == null) {
      _logger.debug('Skipping annotation - no file path', source: 'Annotation');
      return;
    }

    // Check if auto-annotate is enabled
    final settings = _ref.read(annotationSettingsProvider).valueOrNull;
    if (settings != null && !settings.autoAnnotate) {
      _logger.debug('Auto-annotate disabled, skipping', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state =
          const AnnotationState.idle();
      return;
    }

    // Check if annotations are enabled at all
    if (settings != null && !settings.enabled) {
      _logger.debug('Annotations disabled, skipping', source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state =
          const AnnotationState.idle();
      return;
    }

    _logger.info('New image detected: ${image.filePath}', source: 'Annotation');

    try {
      // =====================================================================
      // PRE-FLIGHT CHECK 1: Verify CatalogManager is initialized
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state =
          const AnnotationState.checking();

      if (!_catalogManager.isInitialized) {
        _logger.warning(
            'CatalogManager not initialized - catalogs not available',
            source: 'Annotation');
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
      final annotationStatus =
          await _catalogManager.getAnnotationCatalogStatus();

      final hasDsoCatalog = dsoStatus.isInstalled;
      final hasStarCatalog = starStatus.isInstalled;
      final hasAnnotationCatalog = annotationStatus.isInstalled;

      if (!hasDsoCatalog && !hasStarCatalog && !hasAnnotationCatalog) {
        _logger.warning(
            'No catalogs installed - DSO: $hasDsoCatalog, Stars: $hasStarCatalog, Annotation: $hasAnnotationCatalog',
            source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            const AnnotationState.catalogsNotInstalled();
        return;
      }

      _logger.info(
          'Catalogs available - DSO: $hasDsoCatalog, Stars: $hasStarCatalog, Annotation: $hasAnnotationCatalog',
          source: 'Annotation');

      // =====================================================================
      // PRE-FLIGHT CHECK 3: Verify backend is available
      // =====================================================================
      final backend = _ref.read(backendProvider);
      if (backend is DisconnectedBackend) {
        _logger.error('Backend disconnected, cannot plate solve',
            source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            const AnnotationState.error('Backend not connected');
        return;
      }

      // =====================================================================
      // STEP 1: Plate Solve
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state =
          const AnnotationState.plateSolving();
      _logger.info('Starting plate solve for: ${image.filePath}',
          source: 'Annotation');

      // Try to get mount position hints for faster solving
      double? hintRa;
      double? hintDec;
      try {
        final mountState = _ref.read(mountStateProvider);
        if (mountState.ra != null && mountState.dec != null) {
          // Mount RA is typically tracked in hours; plate-solve hints expect degrees.
          hintRa = _normalizeRaHintDegrees(mountState.ra!);
          hintDec = mountState.dec;
          _logger.debug('Using mount position hints: RA=$hintRa, Dec=$hintDec',
              source: 'Annotation');
        }
      } catch (e) {
        // Mount state not available, continue without hints
        _logger.debug('Mount position hints not available',
            source: 'Annotation');
      }

      final result = await backend.plateSolve(
        imagePath: image.filePath!,
        ra: hintRa,
        dec: hintDec,
      );

      if (!result.success) {
        final detailedReason = _describePlateSolveFailure(result.error);
        _logger.warning('Plate solve failed: $detailedReason (raw: ${result.error})',
            source: 'Annotation');
        _ref.read(annotationStateProvider.notifier).state =
            AnnotationState.plateSolveFailed(detailedReason);
        return;
      }

      _logger.info(
          'Plate solve success: RA=${result.ra.toStringAsFixed(4)}, '
          'Dec=${result.dec.toStringAsFixed(4)}, '
          'Scale=${result.pixelScale.toStringAsFixed(2)}"/px, '
          'Rotation=${result.rotation.toStringAsFixed(1)} deg',
          source: 'Annotation');

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

      if (currentSnr != null &&
          currentSnr >= _SnrAnnotationConstants.minimumSnrThreshold) {
        initialMagnitudeLimit = calculateSnrBasedMagnitudeLimit(currentSnr);
        _lastAnnotationSnr = currentSnr;
        _peakAnnotationSnr = currentSnr;
        _logger.debug(
            'Initial SNR: ${currentSnr.toStringAsFixed(2)}, magnitude limit: ${initialMagnitudeLimit.toStringAsFixed(1)}',
            source: 'Annotation');
      } else {
        // If no SNR available or too low, use conservative base magnitude
        initialMagnitudeLimit = _SnrAnnotationConstants.baseMagnitude;
        _logger.debug(
            'SNR not available or too low, using base magnitude limit: ${initialMagnitudeLimit.toStringAsFixed(1)}',
            source: 'Annotation');
      }

      _currentSnrMagnitudeLimit = initialMagnitudeLimit;
      _lastAnnotationTime = DateTime.now();

      // =====================================================================
      // STEP 4: Search Catalogs
      // =====================================================================
      _ref.read(annotationStateProvider.notifier).state =
          const AnnotationState.searching();

      // Get annotation settings for filtering
      final includeStars =
          settings?.visibleTypes.contains(AnnotationObjectFilter.stars) ??
              false;
      final userMagnitudeCutoff = settings?.magnitudeCutoff ?? 15.0;

      // Use the minimum of SNR-based limit and user setting for initial search
      final effectiveMagnitudeLimit =
          math.min(initialMagnitudeLimit, userMagnitudeCutoff);

      _logger.debug(
          'Searching catalogs with magnitude cutoff: ${effectiveMagnitudeLimit.toStringAsFixed(1)} '
          '(SNR-based: ${initialMagnitudeLimit.toStringAsFixed(1)}, user: ${userMagnitudeCutoff.toStringAsFixed(1)}), '
          'include stars: $includeStars',
          source: 'Annotation');

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

      _logger.info(
          'Annotation complete: ${annotation.objects.length} objects found',
          source: 'Annotation');
    } catch (e, stackTrace) {
      _logger.error('Error processing image: $e\nStack trace: $stackTrace',
          source: 'Annotation');
      _ref.read(annotationStateProvider.notifier).state =
          AnnotationState.error(e.toString());
    }
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

    _logger.info('Found ${objects.length} objects in FOV',
        source: 'Annotation');

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
    final fovDiagonal = math.sqrt(
        plateSolve.fieldWidth * plateSolve.fieldWidth +
            plateSolve.fieldHeight * plateSolve.fieldHeight);
    final searchRadius = fovDiagonal / 2 * 1.1; // Add 10% margin

    _logger.debug(
        'Searching DSO catalog within $searchRadius degrees of RA=${plateSolve.ra}, Dec=${plateSolve.dec}, '
        'magnitude cutoff: ${effectiveMagnitudeCutoff.toStringAsFixed(1)}',
        source: 'Annotation');

    // =======================================================================
    // Query BOTH annotation catalog and DSO catalog, then merge results.
    // The annotation catalog (GLADE+/HyperLEDA/OpenNGC merged) has richer
    // data for galaxies, while the standalone DSO catalog may have objects
    // the annotation catalog misses (and vice-versa).
    // =======================================================================

    // Temporary map for deduplication: keyed by normalized name or position.
    final deduplicatedById = <String, CelestialObjectAnnotation>{};

    // 1) Query annotation catalog (GLADE+/OpenNGC merged)
    final annotationCatalog = await _loadAnnotationCatalog();
    if (annotationCatalog != null && annotationCatalog.isAvailable) {
      try {
        final objects = await annotationCatalog.searchNearby(
          ra: plateSolve.ra,
          dec: plateSolve.dec,
          radiusDegrees: searchRadius,
          maxMagnitude: effectiveMagnitudeCutoff,
        );

        _logger.debug(
            'Found ${objects.length} annotation objects in search area',
            source: 'Annotation');

        for (final obj in objects) {
          if (obj.majorAxis != null && obj.majorAxis! < minSize) {
            continue;
          }

          final pixelCoords = plateSolve.skyToPixel(obj.ra, obj.dec);
          if (pixelCoords == null) {
            continue;
          }

          if (pixelCoords.x < 0 ||
              pixelCoords.x >= plateSolve.imageWidth ||
              pixelCoords.y < 0 ||
              pixelCoords.y >= plateSolve.imageHeight) {
            continue;
          }

          final altName =
              obj.alternateNames.isNotEmpty ? obj.alternateNames.first : null;

          final annotation = CelestialObjectAnnotation(
            id: obj.id,
            name: obj.primaryName,
            type: _mapAnnotationObjectType(obj.type),
            ra: obj.ra,
            dec: obj.dec,
            x: pixelCoords.x,
            y: pixelCoords.y,
            catalogId: altName ?? obj.primaryName,
            commonName:
                altName != null && altName != obj.primaryName ? altName : null,
            magnitude: obj.magnitude,
            size: obj.majorAxis,
          );

          final dedupeKey = _deduplicationKey(annotation);
          deduplicatedById[dedupeKey] = annotation;
        }
      } catch (e) {
        _logger.error('Error querying annotation catalog: $e',
            source: 'Annotation');
      }
    }

    // 2) Query DSO catalog (always, for objects the annotation catalog may miss)
    try {
      final dsos = await _catalogManager.searchDsoNearby(
        ra: plateSolve.ra,
        dec: plateSolve.dec,
        radiusDegrees: searchRadius,
        maxMagnitude: effectiveMagnitudeCutoff,
      );

      _logger.debug('Found ${dsos.length} DSOs in search area',
          source: 'Annotation');

      for (final dso in dsos) {
        if (dso.majorAxis != null && dso.majorAxis! < minSize) {
          continue;
        }

        final pixelCoords = plateSolve.skyToPixel(dso.ra, dso.dec);
        if (pixelCoords == null) {
          continue;
        }

        if (pixelCoords.x < 0 ||
            pixelCoords.x >= plateSolve.imageWidth ||
            pixelCoords.y < 0 ||
            pixelCoords.y >= plateSolve.imageHeight) {
          continue;
        }

        final objectType = _inferObjectType(dso.type);

        final annotation = CelestialObjectAnnotation(
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
        );

        final dedupeKey = _deduplicationKey(annotation);
        if (!deduplicatedById.containsKey(dedupeKey)) {
          // Only add if not already present from annotation catalog
          deduplicatedById[dedupeKey] = annotation;
        } else {
          // Merge: keep the entry with more fields populated
          final existing = deduplicatedById[dedupeKey]!;
          deduplicatedById[dedupeKey] =
              _mergeAnnotationObjects(existing, annotation);
        }
      }
    } catch (e) {
      _logger.error('Error querying DSO catalog: $e', source: 'Annotation');
    }

    annotations.addAll(deduplicatedById.values);

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

        _logger.debug('Found ${stars.length} stars in search area',
            source: 'Annotation');

        for (final star in stars.take(100)) {
          final pixelCoords = plateSolve.skyToPixel(star.ra, star.dec);
          if (pixelCoords == null) continue;

          // Check if pixel coordinates are within image bounds
          if (pixelCoords.x < 0 ||
              pixelCoords.x >= plateSolve.imageWidth ||
              pixelCoords.y < 0 ||
              pixelCoords.y >= plateSolve.imageHeight) {
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

    _logger.debug('Total annotations: ${annotations.length}',
        source: 'Annotation');
    return annotations;
  }
}
