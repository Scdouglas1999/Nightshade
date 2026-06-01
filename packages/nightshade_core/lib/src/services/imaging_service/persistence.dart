part of '../imaging_service.dart';

extension _ImagingServicePersistence on ImagingService {
  Future<void> _saveFitsFile({
    required String deviceId,
    required String filePath,
    required int width,
    required int height,
    required CapturedImageResult capturedImage,
    required ExposureSettings exposureSettings,
    AppSettingsState? appSettings,
    String? targetName,
    required DateTime timestamp,
  }) async {
    final backend = _ref.read(backendProvider);

    // Get equipment states for header metadata
    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final profilesDao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await profilesDao.getActiveProfile();

    // Build FITS header with complete metadata
    final header = FitsWriteHeader(
      objectName: targetName,
      exposureTime: exposureSettings.exposureTime,
      captureTimestamp:
          timestamp.toUtc().toIso8601String(), // Use UTC for FITS standard
      frameType: exposureSettings
          .frameType.displayName, // Use display name for FITS standard
      filter: exposureSettings.filter,
      gain: exposureSettings.gain,
      offset: exposureSettings.offset,
      ccdTemp: cameraState.temperature,
      ra: mountState.ra,
      dec: mountState.dec,
      altitude: mountState.altitude,
      telescope:
          activeProfile?.name, // Use profile name as telescope identifier
      instrument: cameraState.deviceName, // Use connected camera name
      observer: null, // Observer name not currently stored in settings
      binX: exposureSettings.binningX,
      binY: exposureSettings.binningY,
      focalLength: activeProfile?.focalLength,
      aperture: activeProfile?.aperture,
      pixelSizeX: null, // Pixel size not stored in profile yet
      pixelSizeY: null, // Pixel size not stored in profile yet
      siteLatitude: appSettings != null && appSettings.latitude != 0.0
          ? appSettings.latitude
          : null,
      siteLongitude: appSettings != null && appSettings.longitude != 0.0
          ? appSettings.longitude
          : null,
      siteElevation: appSettings != null && appSettings.elevation != 0.0
          ? appSettings.elevation
          : null,
    );

    // Use the optimized API that saves directly from Rust-side stored image data
    // This avoids the expensive raw data roundtrip (Rust -> Dart -> Rust)
    await backend.saveFitsFromLastCapture(
      deviceId: deviceId,
      filePath: filePath,
      headerData: header,
    );
  }

  /// Save image metadata to database
  Future<int> _saveToDatabase({
    required String filePath,
    required CapturedImageResult capturedImage,
    required ExposureSettings exposureSettings,
    required AppSettingsState appSettings,
    String? targetName,
    required DateTime timestamp,
  }) async {
    final records = _ref.read(imagingRecordsRepositoryProvider);

    // Get current session ID if available
    final sessionState = _ref.read(sessionStateProvider);
    final sessionId = sessionState.dbSessionId;

    // Get equipment states
    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);
    final guiderState = _ref.read(guiderStateProvider);

    // Calculate quality score using Rust implementation
    final qualityScore = _calculateQualityScore(
      hfr: capturedImage.stats.hfr,
      starCount: capturedImage.stats.starCount,
      mean: capturedImage.stats.mean,
      stdDev: capturedImage.stats.stdDev,
    );

    // P0-5 #2 — stat the on-disk file BEFORE inserting so the row carries
    // a real byte count. The caller's _saveFitsFile() finishes writing
    // the FITS synchronously before we get here, so the file is on disk.
    // If the stat fails (permissions, race with external deletion), the
    // row goes in with NULL size — the size is auxiliary metadata, the
    // row itself must be written so the capture is recorded.
    int? fileSize;
    try {
      fileSize = await File(filePath).length();
    } catch (e) {
      _logger.warning(
        'Failed to stat captured FITS for size: $filePath ($e) — '
        'row will be inserted with NULL file_size',
        source: 'ImagingService',
      );
    }

    // Create image record with complete metadata
    final companion = CapturedImagesCompanion(
      filePath: drift.Value(filePath),
      fileName: drift.Value(path.basename(filePath)),
      fileFormat: const drift.Value('fits'),
      fileSize: drift.Value(fileSize),
      sessionId: drift.Value(sessionId),
      targetId: const drift.Value(null), // Link to target if available
      frameType: drift.Value(exposureSettings.frameType.name),
      exposureDuration: drift.Value(exposureSettings.exposureTime),
      gain: drift.Value(exposureSettings.gain),
      offset: drift.Value(exposureSettings.offset),
      binX: drift.Value(exposureSettings.binningX),
      binY: drift.Value(exposureSettings.binningY),
      filter: drift.Value(exposureSettings.filter),
      sensorTemp: drift.Value(cameraState.temperature),
      coolerPower: drift.Value(cameraState.coolerPower),
      hfr: drift.Value(capturedImage.stats.hfr),
      starCount: drift.Value(capturedImage.stats.starCount.toInt()),
      background: drift.Value(capturedImage.stats.mean),
      noise: drift.Value(capturedImage.stats.stdDev),
      qualityScore: drift.Value(qualityScore),
      guidingRmsRa: drift.Value(guiderState.rmsRa),
      guidingRmsDec: drift.Value(guiderState.rmsDec),
      guidingRmsTotal: drift.Value(guiderState.rmsTotal),
      mountRa: drift.Value(mountState.ra),
      mountDec: drift.Value(mountState.dec),
      mountAltitude: drift.Value(mountState.altitude),
      mountAzimuth: drift.Value(mountState.azimuth),
      pierSide: const drift.Value(null),
      focuserPosition: drift.Value(focuserState.position),
      focuserTemp: drift.Value(focuserState.temperature),
      rotatorAngle: drift.Value(rotatorState.position),
      isPlateSolved: const drift.Value(false),
      solvedRa: const drift.Value(null),
      solvedDec: const drift.Value(null),
      solvedRotation: const drift.Value(null),
      solvedPixelScale: const drift.Value(null),
      capturedAt: drift.Value(timestamp),
      isAccepted: const drift.Value(true),
      rejectionReason: const drift.Value(null),
    );

    final imageId = await records.createImage(companion);

    // P1-13: schedule fire-and-forget sidecar generation for ad-hoc
    // captures (the sequencer-driven path goes through
    // `insertSequenceFrame` which schedules its own sidecar). Local-only:
    // the remote-companion case is handled by the host's headless server
    // when it processes the `POST /api/images` request (see
    // `session_handlers.dart::handleCreateImage`). We probe `_imagesDao`
    // indirectly via the provider — when running against a remote
    // backend the provider still points at the local (empty) DB, but the
    // sidecar service is a no-op on an unreachable path so the
    // ergonomics are the same.
    if (!records.isRemote && filePath.isNotEmpty) {
      try {
        final sidecarService = _ref.read(thumbnailSidecarServiceProvider);
        final ImagesDao imagesDao = _ref.read(imagesDaoProvider);
        sidecarService.scheduleSidecarWrite(
          imageId: imageId,
          fitsPath: filePath,
          imagesDao: imagesDao,
        );
      } catch (e) {
        _logger.warning(
          'Failed to schedule sidecar for image $imageId ($filePath): $e',
          source: 'ImagingService',
        );
      }
    }

    return imageId;
  }
}
