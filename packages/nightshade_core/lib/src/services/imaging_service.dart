// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as path;
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart';
import '../providers/clock_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/imaging_provider.dart';
import '../providers/backend_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/session_provider.dart';
import '../providers/database_provider.dart';
import '../providers/ui_notification_provider.dart';
import '../backend/nightshade_backend.dart';
import '../database/database.dart' show CapturedImagesCompanion;
import 'calibration_service.dart';
import 'notification_service.dart';
import 'logging_service.dart';
import 'science/science_processing_service.dart';

/// Service for managing camera capture operations
class ImagingService {
  final Ref _ref;

  // Capture state
  bool _isCapturing = false;
  bool _cancelRequested = false;
  int _frameNumber = 0;
  static const _imageDownloadTimeout = Duration(seconds: 60);

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  ImagingService(this._ref);

  /// Start a single exposure capture
  Future<CapturedImageData?> captureImage({
    required ExposureSettings settings,
    String? targetName,
    int? frameNumber,
  }) async {
    if (_isCapturing) {
      throw Exception('Already capturing');
    }

    // Check camera connected
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw Exception('Camera not connected');
    }

    _isCapturing = true;
    _cancelRequested = false;
    _frameNumber = frameNumber ?? (_frameNumber + 1);

    final cameraNotifier = _ref.read(cameraStateProvider.notifier);
    final progressNotifier = _ref.read(exposureProgressProvider.notifier);

    try {
      // Get backend and camera ID
      final backend = _ref.read(backendProvider);
      final deviceId = cameraState.deviceId;

      if (deviceId == null) {
        throw Exception('Camera device ID not available');
      }

      // Apply readout mode before starting exposure
      // fastReadout: false = mode 0 (High Quality), true = mode 1 (Fast)
      final readoutModeIndex = settings.fastReadout ? 1 : 0;
      try {
        await backend.cameraSetReadoutMode(deviceId, readoutModeIndex);
      } catch (e) {
        // Log but don't fail - not all cameras support readout mode switching
        _logger.warning(
            'Failed to set readout mode (index=$readoutModeIndex): $e',
            source: 'ImagingService');
      }

      // Update state to exposing
      cameraNotifier.setExposing(true, progress: 0.0);
      progressNotifier.startExposure(settings.exposureTime, _frameNumber, null);

      // Set up event listener BEFORE starting exposure to avoid race condition
      // The exposure call blocks until complete, so events would be missed if
      // we set up the listener after the call returns
      final exposureCompleter = Completer<bool>();

      // Timeout margin: exposure time + 30 seconds for readout/download
      // Long exposures need more margin for sensor readout
      final timeoutDuration = Duration(
        milliseconds: (settings.exposureTime * 1000).toInt() + 30000,
      );

      // Listen for exposure events and complete when done
      final eventSubscription = backend.eventStream.listen((event) {
        if (event.category == EventCategory.imaging) {
          if (event.eventType == 'ExposureProgress') {
            final progress = event.data['progress'] as double? ?? 0.0;
            final remainingSecs = event.data['remainingSecs'] as double? ?? 0.0;
            final elapsed = settings.exposureTime - remainingSecs;

            cameraNotifier.setExposing(true, progress: progress);
            progressNotifier.updateProgress(
                elapsed, remainingSecs, progress * 100);
          } else if (event.eventType == 'ExposureComplete') {
            // Exposure is complete - signal the completer
            _logger.debug('ExposureComplete event received',
                source: 'ImagingService');
            if (!exposureCompleter.isCompleted) {
              exposureCompleter.complete(true);
            }
          } else if (event.eventType == 'ExposureCancelled') {
            // Exposure was cancelled
            if (!exposureCompleter.isCompleted) {
              exposureCompleter.complete(false);
            }
          } else if (event.eventType == 'ExposureFailed') {
            // Exposure failed
            if (!exposureCompleter.isCompleted) {
              final errorMsg =
                  event.data['error'] as String? ?? 'Unknown error';
              exposureCompleter
                  .completeError(Exception('Exposure failed: $errorMsg'));
            }
          }
        }
      });

      try {
        // Start the real exposure via backend with gain/offset from UI settings
        // This call may block until the exposure completes (depending on backend)
        // Events are published during the exposure, so the listener above catches them
        await backend.cameraStartExposure(
          deviceId: deviceId,
          exposureTime: settings.exposureTime,
          frameType: settings.frameType,
          gain: settings.gain,
          offset: settings.offset,
          binX: settings.binningX,
          binY: settings.binningY,
        );
        _logger.debug('cameraStartExposure returned', source: 'ImagingService');

        // Wait for exposure completion event OR timeout
        // The Completer is completed by the event listener above
        final completed = await exposureCompleter.future.timeout(
          timeoutDuration,
          onTimeout: () {
            // Timeout - exposure took too long, warn user but still try to retrieve image
            // Events may have been missed but image could still be available
            _logger.warning('Exposure timeout reached, checking for image...',
                source: 'ImagingService');
            _ref.read(uiNotificationProvider.notifier).showWarning(
                  'Exposure event not received in time - checking for image. Camera may be unresponsive.',
                  title: 'Exposure Timeout',
                );
            return true;
          },
        );

        // Check if cancelled
        if (!completed || _cancelRequested) {
          if (_cancelRequested) {
            await backend.cameraAbortExposure(deviceId);
          }
          cameraNotifier.setExposing(false);
          progressNotifier.reset();
          return null;
        }

        // Update to downloading state
        progressNotifier.startDownload();

        // Get the captured image from backend
        _logger.debug('Calling cameraGetLastImage...',
            source: 'ImagingService');
        final capturedImage =
            await backend.cameraGetLastImage(deviceId).timeout(
          _imageDownloadTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Timed out retrieving image from camera after '
              '${_imageDownloadTimeout.inSeconds}s',
            );
          },
        );
        _logger.debug(
            'cameraGetLastImage returned: ${capturedImage != null ? "${capturedImage.width}x${capturedImage.height}" : "null"}',
            source: 'ImagingService');

        if (capturedImage == null) {
          throw Exception('Failed to retrieve captured image');
        }

        _logger.debug('Parsing timestamp: ${capturedImage.timestamp}',
            source: 'ImagingService');
        // Capture timestamp before any processing - use try-catch for robustness
        DateTime captureTimestamp;
        try {
          captureTimestamp = DateTime.parse(capturedImage.timestamp);
        } catch (e) {
          _logger.warning(
              'Failed to parse timestamp "${capturedImage.timestamp}": $e - using current time',
              source: 'ImagingService');
          // Why: when the bridge timestamp is unparseable we fall back to
          // the user-chosen clock so the recovered timestamp matches the
          // rest of the session's records (audit-handoff §2.1 WIRE-UP #9).
          captureTimestamp = _ref.read(clockProvider).now();
        }
        _logger.debug('Timestamp parsed: $captureTimestamp',
            source: 'ImagingService');

        // IMMEDIATELY create CapturedImageData and update providers
        // This ensures the UI shows the image even if file saving fails
        _logger.debug('Creating CapturedImageData...',
            source: 'ImagingService');
        CapturedImageData imageData;
        try {
          imageData = CapturedImageData(
            width: capturedImage.width,
            height: capturedImage.height,
            displayData: Uint8List.fromList(capturedImage.displayData),
            histogram: capturedImage.histogram,
            stats: ImageStats(
              min: capturedImage.stats.min,
              max: capturedImage.stats.max,
              mean: capturedImage.stats.mean,
              median: capturedImage.stats.median,
              stdDev: capturedImage.stats.stdDev,
              hfr: capturedImage.stats.hfr,
              fwhm: capturedImage.stats.hfr != null
                  ? capturedImage.stats.hfr! * 2.35 // FWHM ~ 2.35 * HFR
                  : null,
              starCount: capturedImage.stats.starCount > 0
                  ? capturedImage.stats.starCount
                  : null,
              background: capturedImage.stats.mean - capturedImage.stats.stdDev,
              noise: capturedImage.stats.stdDev,
              snr: capturedImage.stats.stdDev > 0
                  ? capturedImage.stats.mean / capturedImage.stats.stdDev
                  : 0.0,
            ),
            capturedAt: captureTimestamp,
            settings: settings,
            targetName: targetName,
            isColor: capturedImage.isColor, // Use isColor from backend
            filePath: null, // Will be updated after FITS save
          );
        } catch (e) {
          _logger.error('Error creating CapturedImageData: $e',
              source: 'ImagingService');
          rethrow; // This is a critical error, must propagate
        }

        _logger.debug(
            'CapturedImageData created, updating providers IMMEDIATELY...',
            source: 'ImagingService');
        // Update providers FIRST to show image in UI
        _ref.read(currentImageProvider.notifier).state = imageData;
        _ref.read(lastImageStatsProvider.notifier).state = imageData.stats;
        _logger.debug('Providers updated! Image should now be visible.',
            source: 'ImagingService');

        // Now save FITS file and persist to database (non-critical operations)
        String? savedFilePath;
        String? effectiveFilePath;
        int? dbImageId;
        bool isTempFile = false;

        try {
          // Get app settings for file path
          final appSettingsAsync = _ref.read(appSettingsProvider);
          final appSettings = appSettingsAsync.valueOrNull;

          if (appSettings != null && appSettings.imageOutputPath.isNotEmpty) {
            // Generate file path using naming pattern
            savedFilePath = await _generateImageFilePath(
              appSettings: appSettings,
              exposureSettings: settings,
              targetName: targetName,
              frameNumber: _frameNumber,
              timestamp: captureTimestamp,
            );
          } else {
            // No output path configured - save to temp directory for annotation/plate solving
            // This ensures live annotation can still work even without a configured save location
            final tempDir = Directory.systemTemp;
            final nightshadeTemp =
                Directory(path.join(tempDir.path, 'nightshade_captures'));
            if (!await nightshadeTemp.exists()) {
              await nightshadeTemp.create(recursive: true);
            }
            // Why: temp capture filenames should reflect the operator's
            // chosen clock so two parallel sessions (one local TZ, one
            // observatory TZ) don't collide on the same epoch millis.
            final timestamp =
                _ref.read(clockProvider).now().millisecondsSinceEpoch;
            savedFilePath =
                path.join(nightshadeTemp.path, 'capture_$timestamp.fits');
            isTempFile = true;
            _logger.debug(
                'No output path configured, saving to temp: $savedFilePath',
                source: 'ImagingService');
          }

          // Call native FITS save API
          // Note: This uses the raw data still in memory on the Rust side
          await _saveFitsFile(
            deviceId: deviceId,
            filePath: savedFilePath,
            width: capturedImage.width,
            height: capturedImage.height,
            capturedImage: capturedImage,
            exposureSettings: settings,
            appSettings: appSettings,
            targetName: targetName,
            timestamp: captureTimestamp,
          );

          // Insert into database only for permanent saves (not temp files)
          // When !isTempFile, appSettings is guaranteed non-null (we checked it above)
          if (!isTempFile && appSettings != null) {
            dbImageId = await _saveToDatabase(
              filePath: savedFilePath,
              capturedImage: capturedImage,
              exposureSettings: settings,
              appSettings: appSettings,
              targetName: targetName,
              timestamp: captureTimestamp,
            );
          }

          // Update imageData with file path (create new instance since it's immutable)
          imageData = CapturedImageData(
            width: imageData.width,
            height: imageData.height,
            displayData: imageData.displayData,
            histogram: imageData.histogram,
            stats: imageData.stats,
            capturedAt: imageData.capturedAt,
            settings: imageData.settings,
            targetName: imageData.targetName,
            isColor: imageData.isColor,
            filePath: savedFilePath,
          );
          // Update provider with file path
          _ref.read(currentImageProvider.notifier).state = imageData;
          effectiveFilePath = savedFilePath;
        } catch (e) {
          // Log error but don't fail the capture - image is already displayed!
          _logger.error('Error saving image: $e', source: 'ImagingService');

          // Notify user of save failure via notification service
          final notificationService = _ref.read(notificationServiceProvider);
          await notificationService.notifyError(
            errorTitle: 'Image Save Failed',
            errorMessage:
                'Failed to save FITS file${savedFilePath != null ? ' to $savedFilePath' : ''}: ${e.toString()}',
            source: 'Imaging Service',
          );
        }

        _logger.debug('FITS save complete.', source: 'ImagingService');

        // Auto-calibration: apply dark/flat/bias correction if enabled
        // Only calibrate light frames - darks, flats, and biases should not be calibrated
        if (savedFilePath != null &&
            savedFilePath.isNotEmpty &&
            !isTempFile &&
            settings.frameType == FrameType.light) {
          try {
            final calSettings = _ref.read(calibrationSettingsProvider);
            if (calSettings.autoCalibrate) {
              _logger.info('Auto-calibrating: $savedFilePath',
                  source: 'ImagingService');
              final calibrationService = _ref.read(calibrationServiceProvider);
              final calResult = await calibrationService.calibrateFile(
                lightPath: savedFilePath,
                settings: calSettings,
                exposureTime: settings.exposureTime,
                gain: settings.gain,
                offset: settings.offset,
                binX: settings.binningX,
                binY: settings.binningY,
                sensorTemperature: cameraState.temperature,
              );
              _logger.info(
                  'Calibration complete: dark=${calResult.darkApplied}, '
                  'flat=${calResult.flatApplied}, bias=${calResult.biasApplied} '
                  '-> ${calResult.outputPath}',
                  source: 'ImagingService');
              effectiveFilePath = calResult.outputPath;

              if (dbImageId != null && effectiveFilePath != savedFilePath) {
                await _ref
                    .read(imagesDaoProvider)
                    .updateImageFilePath(dbImageId, effectiveFilePath);
              }

              imageData = CapturedImageData(
                width: imageData.width,
                height: imageData.height,
                displayData: imageData.displayData,
                histogram: imageData.histogram,
                stats: imageData.stats,
                capturedAt: imageData.capturedAt,
                settings: imageData.settings,
                targetName: imageData.targetName,
                isColor: imageData.isColor,
                filePath: effectiveFilePath,
              );
              _ref.read(currentImageProvider.notifier).state = imageData;
            }
          } catch (e) {
            // Calibration failure should not prevent the capture from succeeding.
            // Log and notify the user, but do not lose the uncalibrated image.
            _logger.error('Auto-calibration failed: $e',
                source: 'ImagingService');
            final notificationService = _ref.read(notificationServiceProvider);
            await notificationService.notifyError(
              errorTitle: 'Auto-Calibration Failed',
              errorMessage:
                  'Failed to calibrate $savedFilePath: ${e.toString()}',
              source: 'Calibration',
            );
          }
        }

        final processedFilePath = effectiveFilePath ?? savedFilePath;
        if (processedFilePath != null && processedFilePath.isNotEmpty) {
          final sessionState = _ref.read(sessionStateProvider);
          // Science processing is informational-only and runs in background.
          unawaited(
            _ref.read(scienceProcessingServiceProvider).processCapturedFrame(
                  imagePath: processedFilePath,
                  deviceId: deviceId,
                  capturedImageId: dbImageId,
                  sessionId: sessionState.dbSessionId,
                ),
          );
        }

        // Store as session image
        try {
          _ref.read(sessionImagesProvider.notifier).addImage(
                CapturedImage(
                  id: dbImageId?.toString() ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                  filePath: processedFilePath ?? '',
                  capturedAt: imageData.capturedAt,
                  settings: settings,
                  stats: imageData.stats,
                  targetName: targetName,
                ),
              );
        } catch (e) {
          _logger.warning('Error adding to session images: $e',
              source: 'ImagingService');
          // Non-critical, continue
        }

        // Reset state BEFORE returning so UI updates immediately
        // Don't rely only on finally block since eventSubscription.cancel() may hang
        _logger.debug('Resetting capture state before return...',
            source: 'ImagingService');
        _isCapturing = false;
        cameraNotifier.setExposing(false);
        progressNotifier.reset();
        _logger.debug('State reset, returning imageData from captureImage',
            source: 'ImagingService');
        return imageData;
      } finally {
        _logger.debug('Inner finally: cancelling event subscription',
            source: 'ImagingService');
        // Add timeout to prevent hanging
        try {
          await eventSubscription.cancel().timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              _logger.warning('eventSubscription.cancel() timed out',
                  source: 'ImagingService');
            },
          );
        } catch (e) {
          _logger.warning('Error cancelling event subscription: $e',
              source: 'ImagingService');
        }
        _logger.debug('Inner finally complete', source: 'ImagingService');
      }
    } finally {
      // This is a safety net - state should already be reset above
      // but ensure it happens even on exceptions
      _logger.debug('Outer finally: ensuring state is reset',
          source: 'ImagingService');
      _isCapturing = false;
      cameraNotifier.setExposing(false);
      progressNotifier.reset();
      _logger.debug('captureImage complete!', source: 'ImagingService');
    }
  }

  /// Start looping capture
  ///
  /// Includes a circuit breaker: after [maxConsecutiveErrors] consecutive
  /// failures the loop aborts to avoid hammering a broken device endlessly.
  Future<void> startLoopCapture({
    required ExposureSettings settings,
    String? targetName,
    int? maxFrames,
    int maxConsecutiveErrors = 10,
    void Function(CapturedImageData)? onImageCaptured,
    void Function(String)? onError,
  }) async {
    int frameNum = 0;
    int consecutiveErrors = 0;

    while (!_cancelRequested && (maxFrames == null || frameNum < maxFrames)) {
      frameNum++;
      try {
        final image = await captureImage(
          settings: settings,
          targetName: targetName,
          frameNumber: frameNum,
        );

        if (image != null) {
          consecutiveErrors = 0;
          onImageCaptured?.call(image);
        }
      } catch (e) {
        consecutiveErrors++;
        onError?.call(e.toString());

        if (consecutiveErrors >= maxConsecutiveErrors) {
          final msg =
              'Loop capture aborted after $consecutiveErrors consecutive errors. '
              'Last error: $e';
          _logger.error(msg, source: 'ImagingService');
          onError?.call(msg);
          break;
        }
      }

      // Small delay between frames
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Cancel the current exposure
  void cancelExposure() {
    _cancelRequested = true;
  }

  /// Check if currently capturing
  bool get isCapturing => _isCapturing;

  /// Reset frame counter
  void resetFrameCounter() {
    _frameNumber = 0;
  }

  /// Generate file path for captured image
  Future<String> _generateImageFilePath({
    required AppSettingsState appSettings,
    required ExposureSettings exposureSettings,
    String? targetName,
    required int frameNumber,
    required DateTime timestamp,
  }) async {
    final basePath = appSettings.imageOutputPath;
    if (basePath.isEmpty) {
      throw Exception('Image output path not configured');
    }

    // Get naming pattern from imaging provider
    final namingPattern = _ref.read(namingPatternProvider);

    // Build subdirectory path based on pattern
    String pattern = namingPattern.pattern;

    // Replace pattern variables
    final target = targetName ?? 'Unknown';
    final filter = exposureSettings.filter ?? 'NoFilter';
    final frameType = exposureSettings.frameType.name;
    final expTime = exposureSettings.exposureTime.toStringAsFixed(1);
    final dateStr = timestamp.toIso8601String().substring(0, 10); // YYYY-MM-DD
    final timeStr = timestamp
        .toIso8601String()
        .substring(11, 19)
        .replaceAll(':', '-'); // HH-MM-SS

    pattern = pattern
        .replaceAll(r'$TARGET', target)
        .replaceAll(r'$FILTER', filter)
        .replaceAll(r'$FRAMETYPE', frameType)
        .replaceAll(r'$EXPTIME', expTime)
        .replaceAll(r'$DATE', dateStr)
        .replaceAll(r'$TIME', timeStr)
        .replaceAll(r'$DATETIME', '${dateStr}_$timeStr')
        .replaceAll(r'$FRAMENUM', frameNumber.toString().padLeft(4, '0'))
        .replaceAll(r'$GAIN', exposureSettings.gain.toString())
        .replaceAll(r'$OFFSET', exposureSettings.offset.toString())
        .replaceAll(r'$BINNING',
            '${exposureSettings.binningX}x${exposureSettings.binningY}');

    // Build full path
    final fileName =
        '${target}_${filter}_${frameNumber.toString().padLeft(4, '0')}.${namingPattern.format.extension}';
    final fullPath = path.join(basePath, pattern, fileName);

    // Create directory if needed
    final directory = Directory(path.dirname(fullPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return _ensureUniqueFilePath(fullPath);
  }

  Future<String> _ensureUniqueFilePath(String desiredPath) async {
    var candidate = desiredPath;
    var suffix = 1;

    while (await File(candidate).exists()) {
      final directory = path.dirname(desiredPath);
      final baseName = path.basenameWithoutExtension(desiredPath);
      final extension = path.extension(desiredPath);
      candidate = path.join(
        directory,
        '${baseName}_${suffix.toString().padLeft(3, '0')}$extension',
      );
      suffix++;
    }

    return candidate;
  }

  /// Save FITS file via Rust backend
  ///
  /// Uses the optimized saveFitsFromLastCapture API which reads raw image data
  /// directly from Rust-side storage, avoiding expensive FFI data transfers.
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
    final db = _ref.read(databaseProvider);
    final imagesDao = db.imagesDao;

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

    // Create image record with complete metadata
    final companion = CapturedImagesCompanion(
      filePath: drift.Value(filePath),
      fileName: drift.Value(path.basename(filePath)),
      fileFormat: const drift.Value('fits'),
      fileSize: const drift.Value(null), // Will be updated after file is written
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

    return await imagesDao.createImage(companion);
  }

  /// Calculate image quality score (0-100)
  /// Mirrors the Rust implementation in imaging/fits.rs
  double _calculateQualityScore({
    required double? hfr,
    required int? starCount,
    required double mean,
    required double stdDev,
  }) {
    double score = 0.0;
    double weightSum = 0.0;

    // HFR component (40% weight)
    // Excellent: < 2.0, Good: 2-3, Fair: 3-5, Poor: > 5
    if (hfr != null && hfr > 0.0) {
      final hfrScore = hfr < 2.0
          ? 100.0
          : hfr < 3.0
              ? 100.0 - (hfr - 2.0) * 25.0
              : hfr < 5.0
                  ? 75.0 - (hfr - 3.0) * 25.0
                  : math.max(0.0, 25.0 - math.min(5.0, hfr - 5.0) * 5.0);
      score += hfrScore * 0.4;
      weightSum += 0.4;
    }

    // Star count component (30% weight)
    // Excellent: > 100, Good: 50-100, Fair: 20-50, Poor: < 20
    if (starCount != null) {
      final starScore = starCount >= 100
          ? 100.0
          : starCount >= 50
              ? 66.0 + (starCount - 50) / 50.0 * 34.0
              : starCount >= 20
                  ? 33.0 + (starCount - 20) / 30.0 * 33.0
                  : math.max(0.0, starCount / 20.0 * 33.0);
      score += starScore * 0.3;
      weightSum += 0.3;
    }

    // Background uniformity component (30% weight)
    // Lower noise is better - check coefficient of variation
    if (mean > 0.0) {
      final cv = stdDev / mean; // Coefficient of variation
      final uniformityScore = cv < 0.1
          ? 100.0
          : cv < 0.3
              ? 100.0 - (cv - 0.1) * 333.0
              : math.max(0.0, 33.0 - math.min(0.33, cv - 0.3) * 100.0);
      score += uniformityScore * 0.3;
      weightSum += 0.3;
    }

    if (weightSum <= 0.0) {
      return 0.0;
    }

    var normalizedScore = (score / weightSum).clamp(0.0, 100.0);

    // Apply an additional global penalty for severe focus issues.
    // Extremely high HFR should meaningfully reduce overall quality even when
    // star count/background metrics look strong.
    if (hfr != null && hfr > 5.0) {
      final hfrExcess = math.min(15.0, hfr - 5.0);
      final penaltyFactor = 1.0 - (hfrExcess / 15.0) * 0.25;
      normalizedScore *= penaltyFactor;
    }

    return normalizedScore.clamp(0.0, 100.0);
  }

  /// Generate a simulated star field image
  CapturedImageData _generateSimulatedImage({
    required int width,
    required int height,
    required ExposureSettings settings,
    String? targetName,
  }) {
    final pixelCount = width * height;
    final grayData = Uint8List(pixelCount);
    final histogram = List<int>.filled(256, 0);

    // Random number generator
    int seed = DateTime.now().microsecondsSinceEpoch;
    int random() {
      seed = ((seed * 1103515245 + 12345) & 0x7fffffff);
      return seed;
    }

    double randomDouble() => random() / 0x7fffffff;
    int randomRange(int min, int max) => min + (random() % (max - min));

    // Background level based on gain and exposure
    final gain = settings.gain;
    final exposureTime = settings.exposureTime;
    final baseBackground =
        (30 + gain * 0.2 + exposureTime * 2).round().clamp(20, 100);
    final noiseLevel = (10 + gain * 0.1).round().clamp(5, 30);

    // Fill with background + noise
    for (int i = 0; i < pixelCount; i++) {
      final noise = (randomDouble() * noiseLevel).round() - noiseLevel ~/ 2;
      grayData[i] = (baseBackground + noise).clamp(0, 255);
    }

    // Add stars
    final numStars = (50 + exposureTime * 30).round().clamp(30, 300);
    int starCount = 0;
    double totalHfr = 0;
    double totalFwhm = 0;

    for (int s = 0; s < numStars; s++) {
      final x = randomRange(5, width - 5);
      final y = randomRange(5, height - 5);
      final brightness = randomRange(150, 255);
      final size = 1.0 + randomDouble() * 2.5;

      // Draw Gaussian star profile
      final radius = (size * 3).ceil();
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final px = x + dx;
          final py = y + dy;

          if (px >= 0 && px < width && py >= 0 && py < height) {
            final distSq = dx * dx + dy * dy;
            final sigmaSq = size * size;
            final intensity = brightness * math.exp(-distSq / (2 * sigmaSq));

            final idx = py * width + px;
            grayData[idx] = (grayData[idx] + intensity.round()).clamp(0, 255);
          }
        }
      }

      starCount++;
      totalHfr += size * 0.8;
      totalFwhm += size * 2.35; // FWHM ≈ 2.35 * sigma for Gaussian
    }

    // Add hot pixels
    for (int i = 0; i < 15; i++) {
      final idx = randomRange(0, pixelCount);
      grayData[idx] = randomRange(200, 255);
    }

    // Calculate histogram from grayscale data (before RGBA conversion)
    for (int i = 0; i < pixelCount; i++) {
      histogram[grayData[i]]++;
    }

    // Calculate stats from grayscale data
    double sum = 0;
    int min = 255;
    int max = 0;

    for (int i = 0; i < pixelCount; i++) {
      final val = grayData[i];
      sum += val;
      if (val < min) min = val;
      if (val > max) max = val;
    }

    final mean = sum / pixelCount;
    final avgHfr = starCount > 0 ? totalHfr / starCount : 0.0;
    final avgFwhm = starCount > 0 ? totalFwhm / starCount : 0.0;

    // Calculate standard deviation
    double varianceSum = 0;
    for (int i = 0; i < pixelCount; i++) {
      final diff = grayData[i] - mean;
      varianceSum += diff * diff;
    }
    final stdDev = math.sqrt(varianceSum / pixelCount);

    // Calculate median
    int cumulative = 0;
    double median = 128;
    for (int i = 0; i < 256; i++) {
      cumulative += histogram[i];
      if (cumulative >= pixelCount / 2) {
        median = i.toDouble();
        break;
      }
    }

    // Convert grayscale to RGBA for display
    final displayData = Uint8List(pixelCount * 4);
    for (int i = 0; i < pixelCount; i++) {
      final gray = grayData[i];
      final d = i * 4;
      displayData[d] = gray;
      displayData[d + 1] = gray;
      displayData[d + 2] = gray;
      displayData[d + 3] = 255;
    }

    return CapturedImageData(
      width: width,
      height: height,
      displayData: displayData,
      histogram: histogram,
      stats: ImageStats(
        min: min.toDouble(),
        max: max.toDouble(),
        mean: mean,
        median: median,
        stdDev: stdDev,
        hfr: avgHfr + (randomDouble() - 0.5) * 0.3,
        fwhm: avgFwhm + (randomDouble() - 0.5) * 0.5,
        starCount: starCount,
        background: baseBackground.toDouble(),
        noise: noiseLevel.toDouble(),
        snr: mean / stdDev,
      ),
      capturedAt: DateTime.now(),
      settings: settings,
      targetName: targetName,
    );
  }
}

/// Provider for the imaging service
final imagingServiceProvider = Provider<ImagingService>((ref) {
  return ImagingService(ref);
});

/// Provider for the current displayed image
final currentImageProvider = StateProvider<CapturedImageData?>((ref) => null);

/// Provider for exposure progress
final exposureProgressProvider =
    StateNotifierProvider<ExposureProgressNotifier, ExposureProgress>((ref) {
  return ExposureProgressNotifier();
});

/// Exposure progress notifier
class ExposureProgressNotifier extends StateNotifier<ExposureProgress> {
  ExposureProgressNotifier() : super(ExposureProgress.idle());

  void startExposure(double totalTime, int frameNumber, int? totalFrames) {
    state = ExposureProgress(
      elapsed: 0,
      remaining: totalTime,
      percent: 0,
      frameNumber: frameNumber,
      totalFrames: totalFrames,
      isDownloading: false,
    );
  }

  void updateProgress(double elapsed, double remaining, double percent) {
    state = ExposureProgress(
      elapsed: elapsed,
      remaining: remaining,
      percent: percent,
      frameNumber: state.frameNumber,
      totalFrames: state.totalFrames,
      isDownloading: false,
    );
  }

  void startDownload() {
    state = ExposureProgress(
      elapsed: state.elapsed,
      remaining: 0,
      percent: 100,
      frameNumber: state.frameNumber,
      totalFrames: state.totalFrames,
      isDownloading: true,
    );
  }

  void reset() {
    state = ExposureProgress.idle();
  }
}
