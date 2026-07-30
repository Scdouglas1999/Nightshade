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
import '../backend/nightshade_exception.dart'
    show
        ConnectionException,
        DeviceBusyException,
        ImagingException,
        NightshadeException,
        ValidationException;
import 'capture_preview_loader.dart';
import '../database/database.dart' show CapturedImagesCompanion;
import '../database/daos/images_dao.dart' show ImagesDao;
import '../providers/thumbnail_sidecar_provider.dart';
import '../utils/utc_timestamp.dart';
import 'calibration_service.dart';
import 'notification_service.dart';
import 'logging_service.dart';
import 'science/science_processing_service.dart';
part 'imaging_service/file_paths.dart';
part 'imaging_service/persistence.dart';
part 'imaging_service/quality_processing.dart';

/// Service for managing camera capture operations
class ImagingService {
  final Ref _ref;
  final BackendNotifier _backendOwner;
  final LoggingService _logger;

  // Capture state
  bool _isCapturing = false;
  bool _cancelRequested = false;
  bool _retired = false;
  int _frameNumber = 0;

  // Pending exposure completer so cancelExposure() can interrupt an
  // in-flight exposure instead of only setting the loop-break flag: resolving
  // it false sends captureImage down its cancel branch, which aborts the
  // sensor. Cleared in captureImage's finally.
  Completer<bool>? _activeExposureCompleter;

  /// Backend/device captured at exposure admission. Abort must target this
  /// exact camera even if the active host or equipment selection changes while
  /// the driver call is blocked.
  NightshadeBackend? _activeCaptureBackend;
  String? _activeCaptureDeviceId;
  Future<void>? _activeAbortFuture;

  static const _imageDownloadTimeout = Duration(seconds: 60);

  ImagingService(this._ref)
    : _backendOwner = _ref.read(backendProvider.notifier),
      _logger = _ref.read(loggingServiceProvider);

  /// Start a single exposure capture
  Future<CapturedImageData?> captureImage({
    required ExposureSettings settings,
    String? targetName,
    int? frameNumber,
    // Thumbnail — producing-instruction provenance. When the
    // imaging service is called from a sequencer-tagged path (e.g.
    // future plugin-node captures), the caller can pass the node id
    // here so the persisted row is queryable by
    // [ImagesDao.watchImagesByProducingNode]. Ad-hoc captures from the
    // Imaging tab simply leave this `null`.
    String? producingNodeId,
    String? producingRunId,
  }) async {
    if (_isCapturing) {
      throw const DeviceBusyException(
        message: 'Already capturing',
        userMessage: 'A capture is already in progress',
        currentOperation: 'capture',
      );
    }

    // Check camera connected
    final cameraState = _ref.read(cameraStateProvider);
    if (cameraState.connectionState != DeviceConnectionState.connected) {
      throw const ConnectionException(
        message: 'Camera not connected',
        userMessage: 'The camera is not connected',
      );
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
        throw const ConnectionException(
          message: 'Camera device ID not available',
          userMessage: 'The camera device is not available',
        );
      }

      _activeCaptureBackend = backend;
      _activeCaptureDeviceId = deviceId;
      _activeAbortFuture = null;

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
      final int? readoutModeIndex = await _resolveReadoutModeIndex(
        deviceId,
        settings,
      );
      if (!_hasBackendAuthority(backend)) return null;
      if (readoutModeIndex != null) {
        // A reported readout-mode list means the setting is part of the
        // requested capture configuration. If the driver rejects it, abort the
        // exposure instead of producing a frame in an unknown mode while the
        // FITS metadata and UI still claim the user's selection.
        await backend.cameraSetReadoutMode(deviceId, readoutModeIndex);
        if (!_hasBackendAuthority(backend)) return null;
      }

      // Update state to exposing
      cameraNotifier.setExposing(true, progress: 0.0);
      progressNotifier.startExposure(settings.exposureTime, _frameNumber, null);

      // Set up event listener BEFORE starting exposure to avoid race condition
      // The exposure call blocks until complete, so events would be missed if
      // we set up the listener after the call returns
      final exposureCompleter = Completer<bool>();
      _activeExposureCompleter = exposureCompleter;

      // Timeout margin: exposure time + 30 seconds for readout/download
      // Long exposures need more margin for sensor readout
      final timeoutDuration = Duration(
        milliseconds: (settings.exposureTime * 1000).toInt() + 30000,
      );

      // Listen for exposure events and complete when done
      final eventSubscription = backend.eventStream.listen((event) {
        if (!_hasBackendAuthority(backend)) return;
        if (event.category == EventCategory.imaging) {
          if (event.eventType == 'ExposureProgress') {
            final progress = event.data['progress'] as double? ?? 0.0;
            final remainingSecs = event.data['remainingSecs'] as double? ?? 0.0;
            final elapsed = settings.exposureTime - remainingSecs;

            cameraNotifier.setExposing(true, progress: progress);
            progressNotifier.updateProgress(
              elapsed,
              remainingSecs,
              progress * 100,
            );
          } else if (event.eventType == 'ExposureComplete') {
            // Exposure is complete - signal the completer
            _logger.debug(
              'ExposureComplete event received',
              source: 'ImagingService',
            );
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
              exposureCompleter.completeError(
                Exception('Exposure failed: $errorMsg'),
              );
            }
          }
        }
      });

      try {
        if (_cancelRequested) {
          return null;
        }
        // Start the real exposure via backend with gain/offset from UI settings
        // This call may block until the exposure completes (depending on backend)
        // Events are published during the exposure, so the listener above catches them
        final exposureStartedAt = DateTime.now();
        await backend.cameraStartExposure(
          deviceId: deviceId,
          exposureTime: settings.exposureTime,
          frameType: settings.frameType,
          gain: settings.gain,
          offset: settings.offset,
          binX: settings.binningX,
          binY: settings.binningY,
        );
        if (!_hasBackendAuthority(backend)) return null;
        _logger.debug('cameraStartExposure returned', source: 'ImagingService');

        // Wait for exposure completion event OR timeout
        // The Completer is completed by the event listener above
        var exposureTimedOut = false;
        final completed = await exposureCompleter.future.timeout(
          timeoutDuration,
          onTimeout: () {
            // Timeout - exposure took too long, warn user but still try to retrieve image
            // Events may have been missed but image could still be available
            exposureTimedOut = true;
            _logger.warning(
              'Exposure timeout reached, checking for image...',
              source: 'ImagingService',
            );
            _ref
                .read(uiNotificationProvider.notifier)
                .showWarning(
                  'Exposure event not received in time - checking for image. Camera may be unresponsive.',
                  title: 'Exposure Timeout',
                );
            return true;
          },
        );
        if (!_hasBackendAuthority(backend)) return null;

        // Check if cancelled
        if (!completed || _cancelRequested) {
          if (_cancelRequested) {
            await _abortActiveExposure();
          }
          if (_hasBackendAuthority(backend)) {
            cameraNotifier.setExposing(false);
            progressNotifier.reset();
          }
          return null;
        }

        if (exposureTimedOut) {
          // The camera may genuinely still be mid-exposure (the event was
          // not merely lost). Abort it so the NEXT frame cannot collide
          // with a stuck one — aborting an already-complete exposure is a
          // harmless no-op on every backend.
          try {
            await backend.cameraAbortExposure(deviceId);
          } catch (e) {
            _logger.warning(
              'Abort after exposure timeout failed (camera may be disconnected): $e',
              source: 'ImagingService',
            );
          }
        }

        // Update to downloading state
        progressNotifier.startDownload();

        // Get the captured image from backend (remote uses JPEG wire format).
        _logger.debug(
          'Calling cameraGetLastImage (${backend is NetworkBackend ? 'remote/jpeg' : 'local'})...',
          source: 'ImagingService',
        );
        final capturedImage = await backend
            .cameraGetLastImage(deviceId)
            .timeout(
              _imageDownloadTimeout,
              onTimeout: () {
                throw TimeoutException(
                  'Timed out retrieving image from camera after '
                  '${_imageDownloadTimeout.inSeconds}s',
                );
              },
            );
        if (!_hasBackendAuthority(backend)) return null;
        _logger.debug(
          'cameraGetLastImage returned: ${capturedImage != null ? "${capturedImage.width}x${capturedImage.height}" : "null"}',
          source: 'ImagingService',
        );

        if (capturedImage == null) {
          throw const ImagingException(
            message: 'Failed to retrieve captured image',
            userMessage: 'Could not retrieve the captured image',
          );
        }

        _logger.debug(
          'Parsing timestamp: ${capturedImage.timestamp}',
          source: 'ImagingService',
        );
        // Capture timestamp before any processing - use try-catch for robustness
        DateTime captureTimestamp;
        try {
          captureTimestamp = parseUtcTimestamp(capturedImage.timestamp);
        } catch (e) {
          _logger.warning(
            'Failed to parse timestamp "${capturedImage.timestamp}": $e - using current time',
            source: 'ImagingService',
          );
          // Why: when the bridge timestamp is unparseable we fall back to
          // the user-chosen clock so the recovered timestamp matches the
          // rest of the session's records
          captureTimestamp = _ref.read(clockProvider).now();
        }
        _logger.debug(
          'Timestamp parsed: $captureTimestamp',
          source: 'ImagingService',
        );

        if (exposureTimedOut &&
            captureTimestamp.isBefore(
              exposureStartedAt.subtract(const Duration(seconds: 5)),
            )) {
          // After a timeout, the "last image" can be the PREVIOUS frame
          // still sitting in the camera buffer. Saving it would silently
          // duplicate an old exposure under new metadata — fail loudly
          // instead so the user/sequencer knows this frame was lost.
          throw ImagingException(
            message:
                'Exposure timed out and the camera returned a stale image '
                '(captured ${captureTimestamp.toIso8601String()}, exposure '
                'started ${exposureStartedAt.toIso8601String()}). Frame discarded.',
            userMessage: 'Exposure timed out; the frame was discarded',
          );
        }

        // IMMEDIATELY create CapturedImageData and update providers
        // This ensures the UI shows the image even if file saving fails
        _logger.debug(
          'Creating CapturedImageData...',
          source: 'ImagingService',
        );
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
          _logger.error(
            'Error creating CapturedImageData: $e',
            source: 'ImagingService',
          );
          rethrow; // This is a critical error, must propagate
        }

        _logger.debug(
          'CapturedImageData created, publishing JPEG preview...',
          source: 'ImagingService',
        );
        // JPEG/display buffer first; host raw loads in the background when remote.
        if (!_hasBackendAuthority(backend)) return null;
        _ref
            .read(capturePreviewPublisherProvider)
            .publish(_ref, imageData, deviceId);
        _logger.debug(
          'Preview published; raw may load in background.',
          source: 'ImagingService',
        );

        // Persisting the FITS is part of capture success. A preview in memory
        // is useful for diagnosis, but it is not an astrophotography frame the
        // user can integrate later. File-write failure therefore fails the
        // capture and stops loop callers instead of silently losing images.
        // Database indexing remains best-effort once the FITS is safely on
        // disk.
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
            if (!_hasBackendAuthority(backend)) return null;
          } else {
            // No output path configured - save to temp directory for annotation/plate solving
            // This ensures live annotation can still work even without a configured save location
            final tempDir = Directory.systemTemp;
            final nightshadeTemp = Directory(
              path.join(tempDir.path, 'nightshade_captures'),
            );
            if (!await nightshadeTemp.exists()) {
              await nightshadeTemp.create(recursive: true);
            }
            if (!_hasBackendAuthority(backend)) return null;
            // Why: temp capture filenames should reflect the operator's
            // chosen clock so two parallel sessions (one local TZ, one
            // observatory TZ) don't collide on the same epoch millis.
            final timestamp = _ref
                .read(clockProvider)
                .now()
                .millisecondsSinceEpoch;
            savedFilePath = path.join(
              nightshadeTemp.path,
              'capture_$timestamp.fits',
            );
            isTempFile = true;
            _logger.debug(
              'No output path configured, saving to temp: $savedFilePath',
              source: 'ImagingService',
            );
          }

          // Call native FITS save API
          // Note: This uses the raw data still in memory on the Rust side
          await _saveFitsFile(
            backend: backend,
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
          if (!_hasBackendAuthority(backend)) return null;

          imageData = imageData.copyWith(filePath: savedFilePath);
          final currentPreview = _ref.read(currentImageProvider);
          if (currentPreview != null &&
              currentPreview.capturedAt == imageData.capturedAt) {
            _ref.read(currentImageProvider.notifier).state = currentPreview
                .copyWith(filePath: savedFilePath);
          }
          effectiveFilePath = savedFilePath;

          // Insert into the database only for permanent saves. The FITS has
          // already been written, so an indexing failure must not misreport
          // the physical image as lost or discard its usable file path.
          if (!isTempFile && appSettings != null) {
            try {
              dbImageId = await _saveToDatabase(
                backend: backend,
                filePath: savedFilePath,
                capturedImage: capturedImage,
                exposureSettings: settings,
                appSettings: appSettings,
                targetName: targetName,
                timestamp: captureTimestamp,
              );
              if (!_hasBackendAuthority(backend)) return null;
              // Thumbnail provenance is UI-only and remains best-effort.
              if (dbImageId != null &&
                  producingNodeId != null &&
                  producingNodeId.isNotEmpty) {
                try {
                  final records = _ref.read(imagingRecordsRepositoryProvider);
                  await records.stampProducingNode(
                    imageId: dbImageId,
                    producingNodeId: producingNodeId,
                    producingRunId: producingRunId,
                  );
                } catch (e) {
                  if (!_hasBackendAuthority(backend)) return null;
                  _logger.warning(
                    'Thumbnail: stampProducingNode failed for '
                    'image $dbImageId (node $producingNodeId): $e',
                    source: 'ImagingService',
                  );
                }
              }
            } catch (e) {
              if (!_hasBackendAuthority(backend)) return null;
              _logger.error(
                'FITS saved but database indexing failed for '
                '$savedFilePath: $e',
                source: 'ImagingService',
              );
              try {
                await _ref
                    .read(notificationServiceProvider)
                    .notifyError(
                      errorTitle: 'Image Indexing Failed',
                      errorMessage:
                          'The FITS file was saved to $savedFilePath, but it could '
                          'not be added to the image library: $e',
                      source: 'Imaging Service',
                    );
              } catch (notificationError) {
                if (!_hasBackendAuthority(backend)) return null;
                _logger.warning(
                  'Failed to send image-indexing notification: '
                  '$notificationError',
                  source: 'ImagingService',
                );
              }
              if (!_hasBackendAuthority(backend)) return null;
            }
          }
        } catch (e) {
          if (!_hasBackendAuthority(backend)) return null;
          _logger.error('Error saving image: $e', source: 'ImagingService');

          try {
            await _ref
                .read(notificationServiceProvider)
                .notifyError(
                  errorTitle: 'Image Save Failed',
                  errorMessage:
                      'Failed to save FITS file${savedFilePath != null ? ' to $savedFilePath' : ''}: $e',
                  source: 'Imaging Service',
                );
          } catch (notificationError) {
            if (!_hasBackendAuthority(backend)) return null;
            _logger.warning(
              'Failed to send image-save notification: $notificationError',
              source: 'ImagingService',
            );
          }
          if (!_hasBackendAuthority(backend)) return null;

          throw ImagingException(
            message:
                'Captured frame could not be saved${savedFilePath != null ? ' to $savedFilePath' : ''}: $e',
            userMessage:
                'The captured frame could not be saved. Check the output '
                'folder and available disk space before retrying.',
            deviceId: deviceId,
          );
        }

        _logger.debug('FITS save complete.', source: 'ImagingService');

        // Auto-calibration: apply dark/flat/bias correction if enabled
        // Only calibrate light frames - darks, flats, and biases should not be calibrated
        if (savedFilePath.isNotEmpty &&
            !isTempFile &&
            settings.frameType == FrameType.light) {
          try {
            final calSettings = _ref.read(calibrationSettingsProvider);
            if (calSettings.autoCalibrate) {
              _logger.info(
                'Auto-calibrating: $savedFilePath',
                source: 'ImagingService',
              );
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
              if (!_hasBackendAuthority(backend)) return null;
              _logger.info(
                'Calibration complete: dark=${calResult.darkApplied}, '
                'flat=${calResult.flatApplied}, bias=${calResult.biasApplied} '
                '-> ${calResult.outputPath}',
                source: 'ImagingService',
              );
              effectiveFilePath = calResult.outputPath;

              if (dbImageId != null && effectiveFilePath != savedFilePath) {
                await _ref
                    .read(imagingRecordsRepositoryProvider)
                    .updateImageFilePath(dbImageId, effectiveFilePath);
                if (!_hasBackendAuthority(backend)) return null;
              }

              imageData = imageData.copyWith(filePath: effectiveFilePath);
              final currentPreview = _ref.read(currentImageProvider);
              if (currentPreview != null &&
                  currentPreview.capturedAt == imageData.capturedAt) {
                _ref.read(currentImageProvider.notifier).state = currentPreview
                    .copyWith(filePath: effectiveFilePath);
              }
            }
          } catch (e) {
            if (!_hasBackendAuthority(backend)) return null;
            // Calibration failure should not prevent the capture from succeeding.
            // Log and notify the user, but do not lose the uncalibrated image.
            _logger.error(
              'Auto-calibration failed: $e',
              source: 'ImagingService',
            );
            final notificationService = _ref.read(notificationServiceProvider);
            await notificationService.notifyError(
              errorTitle: 'Auto-Calibration Failed',
              errorMessage:
                  'Failed to calibrate $savedFilePath: ${e.toString()}',
              source: 'Calibration',
            );
            if (!_hasBackendAuthority(backend)) return null;
          }
        }

        final processedFilePath = effectiveFilePath ?? savedFilePath;
        if (!_hasBackendAuthority(backend)) return null;
        if (processedFilePath.isNotEmpty) {
          final sessionState = _ref.read(sessionStateProvider);
          // Science processing is informational-only and runs in background.
          unawaited(
            _ref
                .read(scienceProcessingServiceProvider)
                .processCapturedFrame(
                  imagePath: processedFilePath,
                  deviceId: deviceId,
                  capturedImageId: dbImageId,
                  sessionId: sessionState.dbSessionId,
                ),
          );
        }

        // Store as session image
        try {
          _ref
              .read(sessionImagesProvider.notifier)
              .addImage(
                CapturedImage(
                  id:
                      dbImageId?.toString() ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                  filePath: processedFilePath,
                  capturedAt: imageData.capturedAt,
                  settings: settings,
                  stats: imageData.stats,
                  targetName: targetName,
                ),
              );
        } catch (e) {
          _logger.warning(
            'Error adding to session images: $e',
            source: 'ImagingService',
          );
          // Non-critical, continue
        }

        // Reset state BEFORE returning so UI updates immediately
        // Don't rely only on finally block since eventSubscription.cancel() may hang
        _logger.debug(
          'Resetting capture state before return...',
          source: 'ImagingService',
        );
        _isCapturing = false;
        if (_hasBackendAuthority(backend)) {
          cameraNotifier.setExposing(false);
          progressNotifier.reset();
        }
        _logger.debug(
          'State reset, returning imageData from captureImage',
          source: 'ImagingService',
        );
        return imageData;
      } finally {
        _logger.debug(
          'Inner finally: cancelling event subscription',
          source: 'ImagingService',
        );
        // Add timeout to prevent hanging
        try {
          await eventSubscription.cancel().timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              _logger.warning(
                'eventSubscription.cancel() timed out',
                source: 'ImagingService',
              );
            },
          );
        } catch (e) {
          _logger.warning(
            'Error cancelling event subscription: $e',
            source: 'ImagingService',
          );
        }
        _logger.debug('Inner finally complete', source: 'ImagingService');
      }
    } finally {
      // This is a safety net - state should already be reset above
      // but ensure it happens even on exceptions
      _logger.debug(
        'Outer finally: ensuring state is reset',
        source: 'ImagingService',
      );
      _isCapturing = false;
      _activeExposureCompleter = null;
      final backend = _activeCaptureBackend;
      final hasAuthority = backend != null && _hasBackendAuthority(backend);
      _activeCaptureBackend = null;
      _activeCaptureDeviceId = null;
      _activeAbortFuture = null;
      if (hasAuthority) {
        cameraNotifier.setExposing(false);
        progressNotifier.reset();
      }
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
  /// real index. A stale persisted index is rejected: silently clamping it can
  /// select an unrelated mode after a camera/driver/profile change.
  Future<int?> _resolveReadoutModeIndex(
    String deviceId,
    ExposureSettings settings,
  ) async {
    final int modeCount = await _readoutModeCount(deviceId);
    if (modeCount <= 0) {
      return null;
    }
    final resolved = settings.resolveReadoutModeIndex(modeCount);
    if (resolved < 0 || resolved >= modeCount) {
      throw ValidationException(
        message:
            'Readout mode index $resolved is unavailable on camera $deviceId '
            '(reported modes: $modeCount)',
        userMessage:
            'The saved readout mode is no longer available. Select a readout '
            'mode for this camera and try again.',
      );
    }
    return resolved;
  }

  /// The number of readout modes the camera [deviceId] reports, or 0 when
  /// unknown. Reads the cached/awaited [equipmentCameraCapabilitiesProvider]
  /// for the device.
  ///
  /// A null capability result yields 0 (treated as "unsupported/unknown" by the
  /// caller). Query failures propagate so authentication, transport, and driver
  /// faults cannot silently skip an explicitly requested capture setting.
  Future<int> _readoutModeCount(String deviceId) async {
    if (deviceId.isEmpty) {
      return 0;
    }
    final caps = await _ref.read(
      equipmentCameraCapabilitiesProvider(deviceId).future,
    );
    return caps?.readoutModes.length ?? 0;
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

        // A non-recoverable structured error (notably a FITS write failure)
        // must stop immediately. Retrying ten more exposures would only lose
        // more frames to the same full/unwritable destination.
        if (e is NightshadeException && !e.isRecoverable) {
          _logger.error(
            'Loop capture stopped after non-recoverable error: $e',
            source: 'ImagingService',
          );
          break;
        }

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
    // Interrupt an in-flight single capture. Setting the flag alone only
    // breaks a loop between frames; a lone exposure blocks waiting on this
    // completer, so resolve it false — captureImage's cancel branch then
    // aborts the sensor exactly once.
    final completer = _activeExposureCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }

    // cameraStartExposure is blocking on several native drivers and on the
    // remote host route. Waiting for captureImage to reach its completer branch
    // would therefore send Abort only after the exposure had already ended.
    // Dispatch against the backend/device captured at admission immediately.
    final abort = _abortActiveExposure();
    unawaited(
      abort.catchError((Object error, StackTrace stackTrace) {
        _logger.warning(
          'Immediate camera abort failed: $error\n$stackTrace',
          source: 'ImagingService',
        );
      }),
    );
  }

  /// Retire this service when its backend dependency changes. The old
  /// instance may still have asynchronous driver work unwinding, but it must
  /// never publish into the replacement host's provider graph.
  void retire() {
    if (_retired) return;
    _retired = true;
    _cancelRequested = true;

    final completer = _activeExposureCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }

    unawaited(_abortActiveExposure().catchError((_) {}));
  }

  bool _hasBackendAuthority(NightshadeBackend backend) =>
      !_retired && _backendOwner.isCurrentBackend(backend);

  Future<void> _abortActiveExposure() {
    final existing = _activeAbortFuture;
    if (existing != null) return existing;

    final backend = _activeCaptureBackend;
    final deviceId = _activeCaptureDeviceId;
    if (backend == null || deviceId == null) return Future<void>.value();

    final operation = Future<void>.sync(
      () => backend.cameraAbortExposure(deviceId),
    );
    _activeAbortFuture = operation;
    return operation;
  }

  /// Check if currently capturing
  bool get isCapturing => _isCapturing;

  /// Reset frame counter
  void resetFrameCounter() {
    _frameNumber = 0;
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

  static final RegExp _unsafePathComponentChars = RegExp(
    r'[<>:"/\\|?*\x00-\x1F]',
  );

  /// Make equipment- and target-derived values safe as one filename segment.
  /// User-entered names are data, never path syntax: a target named `M31/Ha`
  /// must not create a surprise directory, and `../` must never escape the
  /// configured output root.
  static String _sanitizePathComponent(String value) {
    var sanitized = value.replaceAll(_unsafePathComponentChars, '_').trim();
    sanitized = sanitized.replaceFirst(RegExp(r'^[. _]+'), '');
    sanitized = sanitized.replaceAll(RegExp(r'[. ]+$'), '');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return '_';
    }
    return sanitized;
  }

  /// Expand `$VARIABLE` tokens in [pattern] using [substitutions].
  ///
  /// Throws an [Exception] if [pattern] references any token that is not in
  /// [_patternVariables]. This is intentional: silently leaving an unknown
  /// `$BANANA` in the path produces malformed filenames that look like
  /// they "worked" but break downstream sorting/searching.
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
      throw ValidationException(
        message:
            'Unknown naming-pattern variable(s) ${sorted.join(', ')} in '
            'pattern "$pattern". Supported variables: '
            '${(_patternVariables.toList()..sort()).join(', ')}.',
        userMessage: 'The naming pattern contains unknown variables',
      );
    }

    // Replace using the regex so we don't get fooled by prefix overlaps
    // (e.g. `$EXPTIME` vs `$EXPOSURE`, `$FRAMENUM` vs `$FRAMETYPE`). The
    // previous chained-`replaceAll` implementation happened to work because
    // each variable name was a unique substring, but a regex-based pass is
    // robust to future additions.
    final expanded = pattern.replaceAllMapped(_patternVarRegex, (m) {
      final token = m.group(0)!;
      // Safe: we just validated every token above.
      return _sanitizePathComponent(substitutions[token]!);
    });
    if (expanded.contains(r'$')) {
      throw ValidationException(
        message: 'Unrecognized variable syntax in naming pattern "$pattern".',
        userMessage: 'The naming pattern contains an invalid variable',
      );
    }
    return expanded;
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
    if (pattern.trim().isEmpty ||
        path.isAbsolute(pattern) ||
        pattern.startsWith('/') ||
        pattern.startsWith(r'\')) {
      throw ValidationException(
        message: 'Naming pattern must be a non-empty relative path: "$pattern"',
        userMessage: 'The naming pattern must be a relative path',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(extension)) {
      throw ValidationException(
        message: 'Invalid capture file extension: "$extension"',
        userMessage: 'The capture file extension is invalid',
      );
    }

    final expanded = expandNamingPattern(pattern, substitutions);

    // Split on '/' (the documented pattern separator). The last segment is
    // the filename stem; earlier segments are subdirectories. If the user's
    // pattern contains no '/' the entire pattern is the filename and the
    // capture lands directly in the base directory.
    final segments = expanded.split('/');
    if (segments.isEmpty) {
      throw ValidationException(
        message: 'Naming pattern expanded to an empty path: "$pattern"',
        userMessage: 'The naming pattern produced an empty file path',
      );
    }
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(r'\') ||
          _unsafePathComponentChars.hasMatch(segment)) {
        throw ValidationException(
          message:
              'Unsafe path segment "$segment" in naming pattern "$pattern"',
          userMessage: 'The naming pattern contains an unsafe path segment',
        );
      }
    }
    final fileNameStem = segments.removeLast();
    final fileName = '$fileNameStem.$extension';
    final normalizedBase = path.normalize(path.absolute(basePath));
    final candidate = path.normalize(
      path.joinAll([normalizedBase, ...segments, fileName]),
    );
    if (!path.isWithin(normalizedBase, candidate)) {
      throw ValidationException(
        message: 'Capture path escaped output directory: "$candidate"',
        userMessage: 'The naming pattern points outside the output folder',
      );
    }
    return candidate;
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
}

/// Provider for the imaging service
final imagingServiceProvider = Provider<ImagingService>((ref) {
  // Capture is backend-owned. Rebuild the service when the active host
  // changes so callers can use service identity as an authority boundary.
  ref.watch(backendProvider);
  final service = ImagingService(ref);
  ref.onDispose(service.retire);
  return service;
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
