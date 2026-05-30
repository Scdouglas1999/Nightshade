// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as path;
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart';
import '../providers/clock_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/equipment/device_capability_provider.dart';
import '../providers/imaging_provider.dart';
import '../providers/backend_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/session_provider.dart';
import '../providers/database_provider.dart';
import 'imaging_records_repository.dart';
import '../providers/ui_notification_provider.dart';
import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart';
import 'capture_preview_loader.dart';
import '../database/database.dart' show CapturedImagesCompanion;
import '../database/daos/images_dao.dart' show ImagesDao;
import '../providers/database_provider.dart' show imagesDaoProvider;
import '../providers/thumbnail_sidecar_provider.dart';
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
    // Wave 6 Thumbnails — producing-instruction provenance. When the
    // imaging service is called from a sequencer-tagged path (e.g.
    // future plugin-node captures), the caller can pass the node id
    // here so the persisted row is queryable by
    // [ImagesDao.watchImagesByProducingNode]. Ad-hoc captures from the
    // Imaging tab simply leave this `null`.
    String? producingNodeId,
    String? producingRunId,
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

      // Apply readout mode before starting exposure.
      //
      // C6/C9: honour the user's explicit `readoutModeIndex` choice from the
      // camera panel. The index is resolved against the camera's *actual*
      // reported readout-mode count so a middle mode on a >2-mode sensor
      // (e.g. index 2 of 4) is sent verbatim rather than being collapsed to
      // the legacy 0/1 binary. `resolveReadoutModeIndex` returns the explicit
      // index when set, otherwise maps the legacy `fastReadout` flag (slow ->
      // first mode, fast -> last mode) using the same mode count.
      //
      // When the camera reports no readout modes (unknown to the driver, or a
      // protocol that doesn't expose them) we fall back to the legacy
      // `fastReadout ? 1 : 0` mapping — the same behaviour the panel uses when
      // it hides the read-mode dropdown — rather than forcing index 0.
      final int? readoutModeIndex =
          await _resolveReadoutModeIndex(deviceId, settings);
      if (readoutModeIndex != null) {
        try {
          await backend.cameraSetReadoutMode(deviceId, readoutModeIndex);
        } catch (e) {
          // Log but don't fail - not all cameras support readout mode switching
          _logger.warning(
              'Failed to set readout mode (index=$readoutModeIndex): $e',
              source: 'ImagingService');
        }
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

        // Get the captured image from backend (remote uses JPEG wire format).
        _logger.debug(
            'Calling cameraGetLastImage (${backend is NetworkBackend ? 'remote/jpeg' : 'local'})...',
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
        late CapturedImageData imageData;
        try {
          imageData = capturedImageDataFromResult(
            capturedImage: capturedImage,
            settings: settings,
            capturedAt: captureTimestamp,
            targetName: targetName,
            previewSource: backend is NetworkBackend
                ? CapturePreviewSource.remote
                : CapturePreviewSource.local,
          );
        } catch (e) {
          _logger.error('Error creating CapturedImageData: $e',
              source: 'ImagingService');
          rethrow; // This is a critical error, must propagate
        }

        _logger.debug(
            'CapturedImageData created, publishing JPEG preview...',
            source: 'ImagingService');
        // JPEG/display buffer first; host raw loads in the background when remote.
        _ref.read(capturePreviewPublisherProvider).publish(
              _ref,
              imageData,
              deviceId,
            );
        _logger.debug('Preview published; raw may load in background.',
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
            // Wave 6 Thumbnails — when the caller tagged the capture
            // with a producing node id (sequencer-driven path), stamp
            // the row so the sequence-tree thumbnail strip can pick it
            // up via `watchImagesByProducingNode`. Best-effort: a
            // stamp failure must never fail the capture (the FITS is
            // already on disk; the breadcrumb is purely UI).
            if (producingNodeId != null && producingNodeId.isNotEmpty) {
              try {
                final records = _ref.read(imagingRecordsRepositoryProvider);
                await records.stampProducingNode(
                  imageId: dbImageId,
                  producingNodeId: producingNodeId,
                  producingRunId: producingRunId,
                );
              } catch (e) {
                _logger.warning(
                  'Wave 6 Thumbnails: stampProducingNode failed for '
                  'image $dbImageId (node $producingNodeId): $e',
                  source: 'ImagingService',
                );
              }
            }
          }

          imageData = imageData.copyWith(filePath: savedFilePath);
          final currentPreview = _ref.read(currentImageProvider);
          if (currentPreview != null &&
              currentPreview.capturedAt == imageData.capturedAt) {
            _ref.read(currentImageProvider.notifier).state =
                currentPreview.copyWith(filePath: savedFilePath);
          }
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
                    .read(imagingRecordsRepositoryProvider)
                    .updateImageFilePath(dbImageId, effectiveFilePath);
              }

              imageData = imageData.copyWith(filePath: effectiveFilePath);
              final currentPreview = _ref.read(currentImageProvider);
              if (currentPreview != null &&
                  currentPreview.capturedAt == imageData.capturedAt) {
                _ref.read(currentImageProvider.notifier).state =
                    currentPreview.copyWith(filePath: effectiveFilePath);
              }
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

  /// Resolve the concrete readout-mode index to send to the camera for
  /// [settings], using the camera's actual reported readout-mode count.
  ///
  /// Returns `null` when the camera exposes no readout modes (the driver
  /// doesn't report any, or the capability query failed). A null result means
  /// "don't issue a `cameraSetReadoutMode` call at all" — there's nothing to
  /// select against, and forcing index 0 could pick a different mode than the
  /// driver's own default. This mirrors the camera panel, which hides the
  /// read-mode dropdown entirely when `readoutModes` is empty.
  ///
  /// When the mode count is known, [ExposureSettings.resolveReadoutModeIndex]
  /// maps the user's explicit choice (or the legacy `fastReadout` flag) to a
  /// real index, clamped into `[0, modeCount - 1]` to defend against a stale
  /// persisted index pointing past a now-shorter list.
  Future<int?> _resolveReadoutModeIndex(
    String deviceId,
    ExposureSettings settings,
  ) async {
    final int modeCount = await _readoutModeCount(deviceId);
    if (modeCount <= 0) {
      return null;
    }
    return settings.resolveReadoutModeIndex(modeCount).clamp(0, modeCount - 1);
  }

  /// The number of readout modes the camera [deviceId] reports, or 0 when
  /// unknown. Reads the cached/awaited [equipmentCameraCapabilitiesProvider]
  /// for the device.
  ///
  /// A failed or null capability query yields 0 (treated as "unknown" by the
  /// caller) — never a fabricated count. Errors surface in the log rather than
  /// silently masquerading as a two-mode camera.
  Future<int> _readoutModeCount(String deviceId) async {
    if (deviceId.isEmpty) {
      return 0;
    }
    try {
      final caps =
          await _ref.read(equipmentCameraCapabilitiesProvider(deviceId).future);
      return caps?.readoutModes.length ?? 0;
    } catch (e) {
      _logger.warning(
        'Failed to read camera capabilities for readout-mode resolution '
        '($deviceId): $e — skipping explicit readout-mode set',
        source: 'ImagingService',
      );
      return 0;
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

  /// Generate file path for captured image.
  ///
  /// The user's [NamingPattern.pattern] is interpreted as a `/`-separated
  /// path *including the filename*: every segment before the final `/` is a
  /// subdirectory, and the final segment is the filename stem (the extension
  /// is appended from [NamingPattern.format]). The default pattern
  /// `$TARGET/$FRAMETYPE/$TARGET_$FILTER_$EXPTIME_$FRAMENUM` therefore yields
  /// e.g. `M31/Light/M31_L_120.0_0001.fits` under the configured base
  /// directory. This matches the convention implemented by the Rust
  /// `FilenameGenerator` in `native/nightshade_native/imaging/src/naming.rs`.
  ///
  /// All `$VARIABLE` tokens are validated against [_patternVariables]; any
  /// unknown token raises an [Exception] (CLAUDE.md "errors are a feature":
  /// silently leaving e.g. `$BANANA` in the filename would hide a typo in the
  /// user's pattern for weeks).
  ///
  /// Date/time substitutions (`$DATE`, `$TIME`, `$DATETIME`) use **UTC** so
  /// the path matches the FITS `DATE-OBS` keyword written by the Rust
  /// `FitsHeader::captureTimestamp` path (which also uses UTC). A 19:00 PST
  /// frame is grouped under the UTC date 03:00 the next morning — i.e. the
  /// folder name matches the timestamp embedded in the file.
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

    final substitutions = _buildPatternSubstitutions(
      exposureSettings: exposureSettings,
      targetName: targetName,
      frameNumber: frameNumber,
      timestamp: timestamp,
    );

    final fullPath = buildImageFilePath(
      pattern: namingPattern.pattern,
      basePath: basePath,
      extension: namingPattern.format.extension,
      substitutions: substitutions,
    );

    // Create directory if needed
    final directory = Directory(path.dirname(fullPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return _ensureUniqueFilePath(fullPath);
  }

  /// All naming-pattern variables this service recognises.
  ///
  /// Keep this in sync with [NamingPattern.availableVariables],
  /// `docs/features/settings.md`, and the documentation in
  /// `native/nightshade_native/imaging/src/naming.rs`. The settings UI
  /// surfaces a shorter subset (`$TARGET, $FILTER, $DATE, $SEQ, $EXPOSURE`),
  /// but the full set is honoured here so that patterns shared between the
  /// Dart and Rust capture paths behave identically.
  static const Set<String> _patternVariables = {
    r'$TARGET',
    r'$FILTER',
    r'$EXPTIME',
    r'$EXPOSURE', // alias documented in settings_screen subtitle + seed_data
    r'$DATE',
    r'$TIME',
    r'$DATETIME',
    r'$FRAMETYPE',
    r'$FRAMENUM',
    r'$SEQ', // alias documented in settings_screen subtitle + defaults
    r'$GAIN',
    r'$OFFSET',
    r'$TEMP',
    r'$BINNING',
    r'$CAMERA',
    r'$TELESCOPE',
    r'$SEQUENCE',
    r'$SESSION',
  };

  /// Build the substitution map used by [expandNamingPattern]. Pulled out of
  /// [_generateImageFilePath] so the provider-bound pieces (camera/mount
  /// name, sensor temperature) are read in one place. Delegates the pure
  /// timestamp/exposure formatting to [buildTimestampSubstitutions] so unit
  /// tests can exercise the date convention without a `ProviderContainer`.
  Map<String, String> _buildPatternSubstitutions({
    required ExposureSettings exposureSettings,
    String? targetName,
    required int frameNumber,
    required DateTime timestamp,
  }) {
    // $TEMP, $CAMERA, $TELESCOPE are best-effort: equipment may not be
    // connected when this runs (e.g. headless tests). Fall back to the
    // documented defaults from the Rust naming.rs so cross-language users see
    // consistent path strings.
    String camera = 'Camera';
    String tempStr = '0C';
    try {
      final cameraState = _ref.read(cameraStateProvider);
      if (cameraState.deviceName != null &&
          cameraState.deviceName!.isNotEmpty) {
        camera = cameraState.deviceName!;
      }
      final temp = cameraState.temperature;
      if (temp != null) {
        tempStr = '${temp.toStringAsFixed(0)}C';
      }
    } catch (_) {
      // Provider not available (e.g. minimal test container) — use defaults.
    }

    String telescope = 'Telescope';
    try {
      final mountState = _ref.read(mountStateProvider);
      if (mountState.deviceName != null && mountState.deviceName!.isNotEmpty) {
        telescope = mountState.deviceName!;
      }
    } catch (_) {
      // Provider not available — use default.
    }

    return buildTimestampSubstitutions(
      exposureSettings: exposureSettings,
      targetName: targetName,
      frameNumber: frameNumber,
      timestamp: timestamp,
      camera: camera,
      telescope: telescope,
      tempStr: tempStr,
    );
  }

  /// Regex that finds `$IDENT` tokens (uppercase letters only) in a pattern.
  /// Used by [expandNamingPattern] both to perform substitutions and to
  /// reject unknown variables.
  ///
  /// Underscore is intentionally **excluded** from the character class
  /// because the documented patterns use `_` as a literal separator between
  /// variables (e.g. `$TARGET_$FILTER_$FRAMENUM` ⇒ three tokens joined by
  /// underscores, not one nine-character token). Every variable name in
  /// [_patternVariables] is letters-only, so this is sufficient.
  static final RegExp _patternVarRegex = RegExp(r'\$[A-Z]+');

  /// Expand `$VARIABLE` tokens in [pattern] using [substitutions].
  ///
  /// Throws an [Exception] if [pattern] references any token that is not in
  /// [_patternVariables]. This is intentional: silently leaving an unknown
  /// `$BANANA` in the path produces malformed filenames that look like
  /// they "worked" but break downstream sorting/searching. See CLAUDE.md —
  /// "Errors are a feature".
  ///
  /// Exposed for unit testing of the pattern-expansion logic in isolation
  /// from the capture pipeline / provider graph.
  @visibleForTesting
  static String expandNamingPattern(
    String pattern,
    Map<String, String> substitutions,
  ) {
    // Find every $TOKEN in the pattern and validate it up-front so the user
    // gets ONE error listing all unknowns, not one error per failed capture.
    final unknown = <String>{};
    for (final match in _patternVarRegex.allMatches(pattern)) {
      final token = match.group(0)!;
      if (!_patternVariables.contains(token)) {
        unknown.add(token);
      }
    }
    if (unknown.isNotEmpty) {
      final sorted = unknown.toList()..sort();
      throw Exception(
        'Unknown naming-pattern variable(s) ${sorted.join(', ')} in '
        'pattern "$pattern". Supported variables: '
        '${(_patternVariables.toList()..sort()).join(', ')}.',
      );
    }

    // Replace using the regex so we don't get fooled by prefix overlaps
    // (e.g. `$EXPTIME` vs `$EXPOSURE`, `$FRAMENUM` vs `$FRAMETYPE`). The
    // previous chained-`replaceAll` implementation happened to work because
    // each variable name was a unique substring, but a regex-based pass is
    // robust to future additions.
    return pattern.replaceAllMapped(_patternVarRegex, (m) {
      final token = m.group(0)!;
      // Safe: we just validated every token above.
      return substitutions[token]!;
    });
  }

  /// Build the absolute file path for a captured image given the resolved
  /// pattern substitutions. Splits the expanded pattern on `/` so that all
  /// segments before the last become subdirectories under [basePath] and the
  /// last segment becomes the filename stem (extension appended).
  ///
  /// Exposed for unit testing — no filesystem or provider access happens
  /// inside this function.
  @visibleForTesting
  static String buildImageFilePath({
    required String pattern,
    required String basePath,
    required String extension,
    required Map<String, String> substitutions,
  }) {
    final expanded = expandNamingPattern(pattern, substitutions);

    // Split on '/' (the documented pattern separator). The last segment is
    // the filename stem; earlier segments are subdirectories. If the user's
    // pattern contains no '/' the entire pattern is the filename and the
    // capture lands directly in the base directory.
    final segments = expanded.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw Exception(
        'Naming pattern expanded to an empty path: "$pattern"',
      );
    }
    final fileNameStem = segments.removeLast();
    final fileName = '$fileNameStem.$extension';

    return path.joinAll([basePath, ...segments, fileName]);
  }

  /// Build the canonical substitution map for `$DATE`, `$TIME`, etc. given
  /// only the values that don't require provider access (camera state, mount
  /// state). Useful for unit tests that want to verify the UTC date/time
  /// conventions without spinning up a `ProviderContainer`. The full
  /// provider-aware map lives in [_buildPatternSubstitutions].
  @visibleForTesting
  static Map<String, String> buildTimestampSubstitutions({
    required ExposureSettings exposureSettings,
    String? targetName,
    required int frameNumber,
    required DateTime timestamp,
    String camera = 'Camera',
    String telescope = 'Telescope',
    String tempStr = '0C',
  }) {
    final utcTs = timestamp.toUtc();
    final iso = utcTs.toIso8601String();
    final dateStr = iso.substring(0, 10);
    final timeStr = iso.substring(11, 19).replaceAll(':', '-');
    final frameNumStr = frameNumber.toString().padLeft(4, '0');
    final exposureStr = exposureSettings.exposureTime.toStringAsFixed(1);

    return {
      r'$TARGET': targetName ?? 'Unknown',
      r'$FILTER': exposureSettings.filter ?? 'NoFilter',
      r'$EXPTIME': exposureStr,
      r'$EXPOSURE': exposureStr,
      r'$DATE': dateStr,
      r'$TIME': timeStr,
      r'$DATETIME': '${dateStr}_$timeStr',
      r'$FRAMETYPE': exposureSettings.frameType.name,
      r'$FRAMENUM': frameNumStr,
      r'$SEQ': frameNumStr,
      r'$GAIN': exposureSettings.gain.toString(),
      r'$OFFSET': exposureSettings.offset.toString(),
      r'$TEMP': tempStr,
      r'$BINNING': '${exposureSettings.binningX}x${exposureSettings.binningY}',
      r'$CAMERA': camera,
      r'$TELESCOPE': telescope,
      r'$SEQUENCE': targetName ?? 'Sequence',
      r'$SESSION': dateStr.replaceAll('-', ''),
    };
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
        final sidecarService =
            _ref.read(thumbnailSidecarServiceProvider);
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

/// Whether the currently displayed image has been auto-calibrated.
///
/// Derived from `currentImageProvider.filePath`: the calibration service
/// writes calibrated frames with a `_cal.fits` suffix, and the imaging
/// service swaps the file path on the captured image data once the
/// calibration step succeeds (see `ImagingService.captureImage` —
/// auto-calibration block). When calibration fails or isn't enabled the
/// path stays at the original `.fits`, so the badge reflects only
/// actually-calibrated frames — never a wishful "we tried" state. That
/// matches the project rule that errors must surface, not silently
/// downgrade to a misleading badge.
final currentImageIsCalibratedProvider = Provider<bool>((ref) {
  final image = ref.watch(currentImageProvider);
  final path = image?.filePath;
  if (path == null || path.isEmpty) {
    return false;
  }
  // The calibration service produces files ending in `_cal.fits` (or
  // `_cal.fit`). We match either casing on the suffix; the rest of the
  // pipeline normalises paths but the suffix itself is stable.
  final lower = path.toLowerCase();
  return lower.endsWith('_cal.fits') || lower.endsWith('_cal.fit');
});

/// Live preview histogram: uses host raw pixels when [CapturedImageData.hasRawReady],
/// otherwise the JPEG preview histogram bundled with the capture.
final previewDisplayHistogramProvider = Provider<List<int>?>((ref) {
  final image = ref.watch(currentImageProvider);
  if (image == null) {
    return null;
  }
  if (image.hasRawReady && image.rawU16 != null) {
    return histogram256FromRawU16(image.rawU16!);
  }
  return image.histogram;
});

/// Build 256-bin histogram from 16-bit mono raw (high byte per pixel).
List<int> histogram256FromRawU16(Uint16List raw) {
  final bins = List<int>.filled(256, 0);
  for (var i = 0; i < raw.length; i++) {
    bins[raw[i] >> 8]++;
  }
  return bins;
}

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
