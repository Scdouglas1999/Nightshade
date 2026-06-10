import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../../database/database.dart' as db;
import '../../database/daos/science_dao.dart';
import '../../providers/app_version_provider.dart';
import '../../providers/database_provider.dart';
import '../imaging_records_repository.dart';
import '../../providers/science_provider.dart';
import '../../providers/science_status_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/logging_service.dart';
import '../../models/science/science_models.dart';
import '../wcs/gnomonic_projection.dart';
import 'default_science_backend.dart';
import 'fits_header_writer.dart';
import 'photometric_transform_service.dart';
import 'science_backend.dart';
import 'frame_auto_grader.dart';
import 'science_status.dart';

part 'science_processing_service/private_helpers.dart';
part 'science_processing_service/provider.dart';

class ScienceProcessingService {
  final Ref _ref;
  int _adaptiveLiveGridRows = 12;
  int _adaptiveLiveGridCols = 16;
  int _liveBudgetBreachCount = 0;
  int _queueDepth = 0;

  /// Tail of the frame-processing chain. Captures fire
  /// [processCapturedFrame] unawaited, so with short exposures several
  /// frames can be in flight at once — but the status tracker keeps a
  /// single in-flight slot and the adaptive-grid state is per-service.
  /// Chaining each frame onto the previous one keeps the documented
  /// "one frame at a time" contract true regardless of capture cadence.
  Future<void> _processingTail = Future<void>.value();

  ScienceProcessingService(this._ref);

  ScienceDao get _scienceDao => _ref.read(scienceDaoProvider);
  ImagingRecordsRepository get _imagesRepo =>
      _ref.read(imagingRecordsRepositoryProvider);
  ScienceBackend get _scienceBackend => _ref.read(scienceBackendProvider);
  LoggingService get _logger => _ref.read(loggingServiceProvider);
  ScienceProcessingStatusTracker get _status =>
      _ref.read(scienceProcessingStatusTrackerProvider);

  Future<void> processCapturedFrame({
    required String imagePath,
    String? deviceId,
    int? capturedImageId,
    int? sessionId,
  }) {
    _queueDepth++;
    _status.enqueue();
    _logger.debug(
      'science.queue_depth=$_queueDepth',
      source: 'ScienceProcessingService',
    );

    final run = _processingTail.then(
      (_) => _processFrame(
        imagePath: imagePath,
        deviceId: deviceId,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
      ),
    );
    // _processFrame never throws (it catches and logs internally), but keep
    // the chain alive defensively so one broken link can't stall the queue.
    _processingTail = run.catchError((_) {});
    return run;
  }

  Future<void> _processFrame({
    required String imagePath,
    String? deviceId,
    int? capturedImageId,
    int? sessionId,
  }) async {
    bool frameBegun = false;
    // Snapshots gathered during processing and consumed by the FITS
    // writeback stage at the end. They stay local so a partial pipeline
    // (e.g. calibration succeeds, transparency fails) still gets the
    // succeeded fields written back.
    FramePhotometricCalibration? writebackCalibration;
    TransparencySample? writebackTransparency;
    try {
      db.CapturedImage? capturedImage;
      if (capturedImageId != null) {
        capturedImage = await _imagesRepo.getImageById(capturedImageId);
        final frameType = capturedImage?.frameType.toLowerCase();
        // Science products in v1 are computed for light frames only.
        if (frameType != null && frameType != 'light') {
          _status.dequeue();
          return;
        }
      }

      _status.beginFrame(
        imagePath: imagePath,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
      );
      frameBegun = true;

      final globalSettings = await _ref.read(scienceSettingsProvider.future);
      final sessionConfig = sessionId == null
          ? const ScienceSessionConfig()
          : await _ref
                    .read(scienceSessionConfigProvider(sessionId).future)
                    .catchError((_) => null) ??
                const ScienceSessionConfig();
      final frameTimestamp = await _resolveFrameTimestamp(
        imagePath: imagePath,
        capturedImage: capturedImage,
      );

      if (globalSettings.frameQualityMapsEnabled) {
        final sw = _status.beginStage(ScienceStage.frameQuality);
        try {
          await _processImmediateQualityLane(
            imagePath: imagePath,
            deviceId: deviceId,
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: frameTimestamp,
          );
          _status.endStage(
            ScienceStage.frameQuality,
            ScienceStageOutcome.ok,
            stopwatch: sw,
          );
        } catch (error) {
          _status.endStage(
            ScienceStage.frameQuality,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.frameQuality,
          note: 'Frame quality maps disabled',
        );
      }

      final solveSw = _status.beginStage(ScienceStage.plateSolve);
      WcsSolution? wcs;
      try {
        wcs = await _resolveWcsSolution(
          imagePath: imagePath,
          capturedImageId: capturedImageId,
          capturedImage: capturedImage,
        );
        _status.endStage(
          ScienceStage.plateSolve,
          wcs == null ? ScienceStageOutcome.noData : ScienceStageOutcome.ok,
          stopwatch: solveSw,
          note: wcs == null ? 'No WCS available for this frame' : null,
        );
      } catch (error) {
        _status.endStage(
          ScienceStage.plateSolve,
          ScienceStageOutcome.failed,
          stopwatch: solveSw,
          note: error.toString(),
        );
        rethrow;
      }
      final frameContext = await _buildFrameContext(
        imagePath: imagePath,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
        capturedImage: capturedImage,
        wcs: wcs,
      );

      if (globalSettings.photometricCalibrationEnabled &&
          sessionConfig.calibrationEnabled &&
          wcs != null) {
        final sw = _status.beginStage(ScienceStage.calibration);
        try {
          final calibration = await _scienceBackend.calibrateFramePhotometry(
            imagePath,
            wcs,
            PhotometricCatalogSource.auto,
            frameContext,
          );
          if (calibration != null) {
            final calibrationRow =
                db.FramePhotometricCalibrationCompanion.insert(
                  capturedImageId: drift.Value(capturedImageId),
                  sessionId: drift.Value(sessionId),
                  isCalibrated: drift.Value(calibration.isCalibrated),
                  zeroPoint: drift.Value(calibration.zeroPoint),
                  limitingMag3Sigma: drift.Value(calibration.limitingMag3Sigma),
                  limitingMag5Sigma: drift.Value(calibration.limitingMag5Sigma),
                  matchedStarCount: drift.Value(calibration.matchedStarCount),
                  calibrationRms: drift.Value(calibration.calibrationRms),
                  catalogSource: drift.Value(calibration.catalogSource.name),
                  solverId: drift.Value(calibration.solverId),
                  timestamp: drift.Value(frameContext.capturedAt),
                );
            if (capturedImageId != null) {
              await _scienceDao.replaceFrameCalibrationForImage(
                capturedImageId,
                calibrationRow,
              );
            } else {
              await _scienceDao.insertFrameCalibration(calibrationRow);
            }
            // Remember for the writeback pass — only the scientific fields
            // we want to stamp; the row identity is not needed.
            writebackCalibration = calibration;
            _status.endStage(
              ScienceStage.calibration,
              ScienceStageOutcome.ok,
              stopwatch: sw,
              note:
                  'ZP ${calibration.zeroPoint?.toStringAsFixed(2) ?? "—"}, '
                  '${calibration.matchedStarCount} stars',
            );
          } else {
            _status.endStage(
              ScienceStage.calibration,
              ScienceStageOutcome.noData,
              stopwatch: sw,
              note: 'Too few catalog matches for a reliable fit',
            );
          }
        } catch (error) {
          _status.endStage(
            ScienceStage.calibration,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.calibration,
          note: wcs == null
              ? 'No plate solve — calibration skipped'
              : 'Calibration disabled in settings',
        );
      }

      if (globalSettings.transparencyEnabled &&
          sessionConfig.transparencyEnabled &&
          sessionId != null) {
        final transparencySw = _status.beginStage(ScienceStage.transparency);
        try {
          final recentRows = await _scienceDao.getRecentCalibrations(
            sessionId,
            limit: 20,
          );
          final recent = <FramePhotometricCalibration>[];
          for (final row in recentRows) {
            db.CapturedImage? rowImage;
            if (row.capturedImageId != null) {
              rowImage = await _imagesRepo.getImageById(row.capturedImageId!);
            }
            final airmass = rowImage == null
                ? null
                : await _airmassForCapturedImage(
                    image: rowImage,
                    timestamp: row.timestamp,
                  );
            final exposureSeconds = rowImage?.exposureDuration;
            if (exposureSeconds == null ||
                !exposureSeconds.isFinite ||
                exposureSeconds <= 0) {
              _logger.warning(
                'Transparency sample skipped for calibration ${row.id}: missing or invalid exposure metadata.',
                source: 'ScienceProcessingService',
              );
              continue;
            }
            recent.add(
              FramePhotometricCalibration(
                capturedImageId: row.capturedImageId,
                sessionId: row.sessionId,
                timestamp: row.timestamp,
                airmass: airmass,
                exposureSeconds: exposureSeconds.clamp(0.001, 1e6).toDouble(),
                isCalibrated: row.isCalibrated,
                zeroPoint: row.zeroPoint,
                limitingMag3Sigma: row.limitingMag3Sigma,
                limitingMag5Sigma: row.limitingMag5Sigma,
                matchedStarCount: row.matchedStarCount,
                calibrationRms: row.calibrationRms,
                solverId: row.solverId,
                catalogSource: _catalogFromName(row.catalogSource),
              ),
            );
          }

          final sample = await _scienceBackend.estimateTransparency(
            recent,
            const TransparencyOptions(rollingWindowSize: 12),
          );

          if (sample != null) {
            final sampleRow = db.TransparencySamplesCompanion.insert(
              capturedImageId: drift.Value(capturedImageId),
              sessionId: drift.Value(sessionId),
              transparencyPercent: sample.transparencyPercent,
              extinctionCoefficient: drift.Value(sample.extinctionCoefficient),
              qualityBucket: drift.Value(sample.qualityBucket),
              confidence: drift.Value(sample.confidence),
              timestamp: drift.Value(frameContext.capturedAt),
            );
            if (capturedImageId != null) {
              await _scienceDao.replaceTransparencySampleForImage(
                capturedImageId,
                sampleRow,
              );
            } else {
              await _scienceDao.insertTransparencySample(sampleRow);
            }
            writebackTransparency = sample;
            _status.endStage(
              ScienceStage.transparency,
              ScienceStageOutcome.ok,
              stopwatch: transparencySw,
              note:
                  '${sample.transparencyPercent.toStringAsFixed(1)}% (${sample.qualityBucket})',
            );
          } else {
            _status.endStage(
              ScienceStage.transparency,
              ScienceStageOutcome.noData,
              stopwatch: transparencySw,
              note:
                  'Need more calibrated frames before a transparency sample stabilises',
            );
          }
        } catch (error) {
          _status.endStage(
            ScienceStage.transparency,
            ScienceStageOutcome.failed,
            stopwatch: transparencySw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.transparency,
          note: sessionId == null
              ? 'Transparency requires an active session'
              : 'Transparency disabled in settings',
        );
      }

      if (globalSettings.psfMapEnabled && sessionConfig.psfMapEnabled) {
        final sw = _status.beginStage(ScienceStage.psfMap);
        try {
          final psfMap = await _scienceBackend.buildPsfFieldMap(
            imagePath,
            wcs,
            PsfMapOptions(
              gridRows: sessionConfig.psfGridRows,
              gridCols: sessionConfig.psfGridCols,
            ),
          );

          if (capturedImageId != null) {
            final rows = psfMap.tiles
                .map(
                  (tile) => db.PsfFieldTilesCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    tileRow: tile.row,
                    tileCol: tile.col,
                    starCount: drift.Value(tile.starCount),
                    medianFwhm: drift.Value(tile.medianFwhm),
                    medianHfr: drift.Value(tile.medianHfr),
                    medianEccentricity: drift.Value(tile.medianEccentricity),
                    roundness: drift.Value(tile.roundness),
                    timestamp: drift.Value(frameContext.capturedAt),
                  ),
                )
                .toList(growable: false);
            await _scienceDao.replacePsfTilesForImage(capturedImageId, rows);

            final fwhmTiles = psfMap.tiles
                .map(
                  (tile) => db.ScienceTileMetricsCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    timestamp: drift.Value(frameContext.capturedAt),
                    layerType: ScienceLayerType.fwhm.dbValue,
                    tileRow: tile.row,
                    tileCol: tile.col,
                    sampleCount: drift.Value(tile.starCount),
                    value: drift.Value(tile.medianFwhm),
                    p05: drift.Value(tile.medianFwhm),
                    p50: drift.Value(tile.medianFwhm),
                    p95: drift.Value(tile.medianFwhm),
                    auxValue: drift.Value(tile.roundness),
                  ),
                )
                .toList(growable: false);
            final hfrTiles = psfMap.tiles
                .map(
                  (tile) => db.ScienceTileMetricsCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    timestamp: drift.Value(frameContext.capturedAt),
                    layerType: ScienceLayerType.hfr.dbValue,
                    tileRow: tile.row,
                    tileCol: tile.col,
                    sampleCount: drift.Value(tile.starCount),
                    value: drift.Value(tile.medianHfr),
                    p05: drift.Value(tile.medianHfr),
                    p50: drift.Value(tile.medianHfr),
                    p95: drift.Value(tile.medianHfr),
                    auxValue: drift.Value(tile.roundness),
                  ),
                )
                .toList(growable: false);
            final eccTiles = psfMap.tiles
                .map(
                  (tile) => db.ScienceTileMetricsCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    timestamp: drift.Value(frameContext.capturedAt),
                    layerType: ScienceLayerType.eccentricity.dbValue,
                    tileRow: tile.row,
                    tileCol: tile.col,
                    sampleCount: drift.Value(tile.starCount),
                    value: drift.Value(tile.medianEccentricity),
                    p05: drift.Value(tile.medianEccentricity),
                    p50: drift.Value(tile.medianEccentricity),
                    p95: drift.Value(tile.medianEccentricity),
                    auxValue: drift.Value(tile.roundness),
                  ),
                )
                .toList(growable: false);

            await _scienceDao.replaceTileMetricsForImageLayer(
              capturedImageId,
              ScienceLayerType.fwhm.dbValue,
              fwhmTiles,
            );
            await _scienceDao.replaceTileMetricsForImageLayer(
              capturedImageId,
              ScienceLayerType.hfr.dbValue,
              hfrTiles,
            );
            await _scienceDao.replaceTileMetricsForImageLayer(
              capturedImageId,
              ScienceLayerType.eccentricity.dbValue,
              eccTiles,
            );
            _status.endStage(
              ScienceStage.psfMap,
              ScienceStageOutcome.ok,
              stopwatch: sw,
              note:
                  '${psfMap.tiles.length} tiles, '
                  '${sessionConfig.psfGridRows}×${sessionConfig.psfGridCols} grid',
            );
          } else {
            _status.endStage(
              ScienceStage.psfMap,
              ScienceStageOutcome.noData,
              stopwatch: sw,
              note: 'Sessionless capture — PSF map needs a captured-image id',
            );
          }
        } catch (error) {
          _status.endStage(
            ScienceStage.psfMap,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.psfMap,
          note: 'PSF map disabled in settings',
        );
      }

      if (globalSettings.astrometricResidualsEnabled &&
          sessionConfig.residualsEnabled &&
          wcs != null &&
          capturedImageId != null) {
        final sw = _status.beginStage(ScienceStage.residuals);
        try {
          final residualMap = await _scienceBackend.computeAstrometricResiduals(
            imagePath,
            wcs,
            const AstrometryOptions(sampleCount: 180),
          );
          if (residualMap != null) {
            final rows = residualMap.vectors
                .map(
                  (vector) => db.AstrometryResidualVectorsCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    x: vector.x,
                    y: vector.y,
                    dxArcsec: vector.dxArcsec,
                    dyArcsec: vector.dyArcsec,
                    magnitudeArcsec: vector.magnitudeArcsec,
                    recommendationCode: drift.Value(residualMap.suggestionCode),
                    timestamp: drift.Value(frameContext.capturedAt),
                  ),
                )
                .toList(growable: false);
            await _scienceDao.replaceResidualVectorsForImage(
              capturedImageId,
              rows,
            );
            _status.endStage(
              ScienceStage.residuals,
              ScienceStageOutcome.ok,
              stopwatch: sw,
              note: '${rows.length} residual vectors',
            );
          } else {
            _status.endStage(
              ScienceStage.residuals,
              ScienceStageOutcome.noData,
              stopwatch: sw,
              note: 'Solver did not provide residual vectors',
            );
          }
        } catch (error) {
          _status.endStage(
            ScienceStage.residuals,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.residuals,
          note: wcs == null
              ? 'Residuals need a plate solve'
              : capturedImageId == null
              ? 'Residuals need a captured-image id'
              : 'Residuals disabled in settings',
        );
      }

      if (globalSettings.photometryEnabled && sessionConfig.photometryEnabled) {
        final sw = _status.beginStage(ScienceStage.photometry);
        try {
          final photometrySelection = await _ref
              .read(sciencePhotometrySelectionProvider.future)
              .catchError((_) => const SciencePhotometrySelection());
          final photometryResult = await _computeAndStorePhotometry(
            imagePath: imagePath,
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            wcs: wcs,
            selection: photometrySelection,
            frameTimestamp: frameContext.capturedAt,
            exposureSeconds: frameContext.exposureSeconds,
            filterName: frameContext.filterName,
            airmass: frameContext.airmass,
          );
          _status.endStage(
            ScienceStage.photometry,
            photometryResult == 0
                ? ScienceStageOutcome.noData
                : ScienceStageOutcome.ok,
            stopwatch: sw,
            note: photometryResult == 0
                ? 'No target/comparison anchors matched in field'
                : '$photometryResult measurement(s)',
          );
        } catch (error) {
          _status.endStage(
            ScienceStage.photometry,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.photometry,
          note: 'Photometry disabled in settings',
        );
      }

      if (globalSettings.movingObjectsEnabled &&
          sessionConfig.movingObjectsEnabled &&
          wcs != null &&
          sessionId != null) {
        final sw = _status.beginStage(ScienceStage.movingObjects);
        try {
          final recent = await _imagesRepo.getRecentImagesForSession(
            sessionId,
            limit: 5,
          );
          final recentPaths =
              recent
                  .where((image) => image.filePath.isNotEmpty)
                  .toList(growable: false)
                ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
          final paths = recentPaths
              .map((image) => image.filePath)
              .toList(growable: false);

          if (paths.length >= 2) {
            final candidates = await _scienceBackend.detectMovingObjects(
              paths,
              wcs,
              const MovingObjectOptions(),
            );

            final rows = candidates
                .map(
                  (candidate) => db.MovingObjectCandidatesCompanion.insert(
                    capturedImageId: drift.Value(capturedImageId),
                    sessionId: drift.Value(sessionId),
                    candidateId: candidate.candidateId,
                    raDegrees: candidate.raDegrees,
                    decDegrees: candidate.decDegrees,
                    motionArcsecPerMinute: candidate.motionArcsecPerMinute,
                    positionAngleDegrees: candidate.positionAngleDegrees,
                    confidence: candidate.confidence,
                    isKnownObject: drift.Value(candidate.isKnownObject),
                    objectName: drift.Value(candidate.objectName),
                    source: const drift.Value('local'),
                    // The candidate's RA/Dec is a mid-stack position; store
                    // its true astrometric epoch so MPC export lines pair
                    // position and time correctly for fast movers.
                    timestamp: drift.Value(
                      candidate.epochUtc ?? frameContext.capturedAt,
                    ),
                  ),
                )
                .toList(growable: false);

            if (capturedImageId != null) {
              await _scienceDao.replaceMovingObjectCandidatesForImage(
                capturedImageId,
                rows,
              );
            } else {
              await _scienceDao.insertMovingObjectCandidates(rows);
            }
            _status.endStage(
              ScienceStage.movingObjects,
              candidates.isEmpty
                  ? ScienceStageOutcome.noData
                  : ScienceStageOutcome.ok,
              stopwatch: sw,
              note: candidates.isEmpty
                  ? 'No candidates passed motion checks'
                  : '${candidates.length} candidate(s)',
            );
          } else {
            _status.endStage(
              ScienceStage.movingObjects,
              ScienceStageOutcome.noData,
              stopwatch: sw,
              note: 'Need 2+ recent frames; have ${paths.length}',
            );
          }
        } catch (error) {
          _status.endStage(
            ScienceStage.movingObjects,
            ScienceStageOutcome.failed,
            stopwatch: sw,
            note: error.toString(),
          );
          rethrow;
        }
      } else {
        _status.skipStage(
          ScienceStage.movingObjects,
          note: wcs == null
              ? 'Moving objects need a plate solve'
              : sessionId == null
              ? 'Moving objects require an active session'
              : 'Moving objects disabled in settings',
        );
      }

      await _runFitsHeaderWriteback(
        imagePath: imagePath,
        capturedImage: capturedImage,
        globalSettings: globalSettings,
        calibration: writebackCalibration,
        transparency: writebackTransparency,
      );

      if (capturedImageId != null) {
        await _runAutoGrade(capturedImageId: capturedImageId);
      }
    } catch (error, stack) {
      _logger.error(
        'Science frame processing failed for $imagePath: $error\n$stack',
        source: 'ScienceProcessingService',
      );
    } finally {
      _queueDepth = math.max(0, _queueDepth - 1);
      if (frameBegun) {
        _status.endFrame();
      }
    }
  }

  /// Stamp the science measurements gathered for this frame back into the
  /// captured FITS file's header so external pipelines can use them. This
  /// is a no-op when:
  ///   * the user has disabled writeback in settings,
  ///   * the file isn't a FITS (.fits/.fts/.fit) on disk,
  ///   * no science fields were produced (calibration + transparency both
  ///     came back empty).
  ///
  /// Errors here are logged but never rethrown — a failed writeback must
  /// not retroactively fail a capture that has already been recorded.
  Future<void> _runAutoGrade({required int capturedImageId}) async {
    final settings = await _ref.read(scienceSettingsProvider.future);
    if (!settings.autoFrameGradingEnabled) {
      _status.skipStage(
        ScienceStage.autoGrade,
        note: 'Auto frame grading disabled in settings',
      );
      return;
    }

    final sw = _status.beginStage(ScienceStage.autoGrade);
    try {
      final fresh = await _imagesRepo.getImageById(capturedImageId);
      if (fresh == null) {
        _status.skipStage(
          ScienceStage.autoGrade,
          note: 'Captured image row not found',
        );
        return;
      }
      final rejected = await _ref
          .read(frameAutoGraderProvider)
          .gradeCapturedFrame(image: fresh);
      if (rejected == null) {
        _status.skipStage(ScienceStage.autoGrade, note: 'Not a light frame');
      } else if (rejected) {
        _status.endStage(
          ScienceStage.autoGrade,
          ScienceStageOutcome.ok,
          stopwatch: sw,
          note: 'Frame rejected by quality thresholds',
        );
      } else {
        _status.endStage(
          ScienceStage.autoGrade,
          ScienceStageOutcome.ok,
          stopwatch: sw,
          note: 'Frame passed quality thresholds',
        );
      }
    } catch (error) {
      _status.endStage(
        ScienceStage.autoGrade,
        ScienceStageOutcome.failed,
        stopwatch: sw,
        note: error.toString(),
      );
    }
  }

  Future<void> _runFitsHeaderWriteback({
    required String imagePath,
    required db.CapturedImage? capturedImage,
    required ScienceSettings globalSettings,
    required FramePhotometricCalibration? calibration,
    required TransparencySample? transparency,
  }) async {
    if (!globalSettings.fitsHeaderWritebackEnabled) {
      _status.skipStage(
        ScienceStage.fitsWriteback,
        note: 'FITS header writeback disabled in settings',
      );
      return;
    }
    final lower = imagePath.toLowerCase();
    if (!(lower.endsWith('.fits') ||
        lower.endsWith('.fts') ||
        lower.endsWith('.fit'))) {
      _status.skipStage(
        ScienceStage.fitsWriteback,
        note: 'Not a FITS file — writeback skipped',
      );
      return;
    }
    final updates = buildScienceWritebackKeywords(
      calibration: calibration,
      transparency: transparency,
      buildTag: _ref.read(appVersionLabelProvider),
    );
    if (updates.isEmpty) {
      _status.skipStage(
        ScienceStage.fitsWriteback,
        note: 'No science fields produced for this frame',
      );
      return;
    }

    final sw = _status.beginStage(ScienceStage.fitsWriteback);
    try {
      final writer = FitsHeaderWriter();
      final result = await writer.updateKeywords(imagePath, updates);
      final summary = StringBuffer()
        ..write('${result.keywordsUpdated} updated, ')
        ..write('${result.keywordsInjected} injected');
      if (result.headerGrew) {
        summary.write(' (header grew to ${result.headerBlocks} blocks)');
      }
      _status.endStage(
        ScienceStage.fitsWriteback,
        ScienceStageOutcome.ok,
        stopwatch: sw,
        note: summary.toString(),
      );
    } catch (error, stack) {
      _logger.warning(
        'FITS writeback failed for $imagePath: $error\n$stack',
        source: 'ScienceProcessingService',
      );
      _status.endStage(
        ScienceStage.fitsWriteback,
        ScienceStageOutcome.failed,
        stopwatch: sw,
        note: error.toString(),
      );
    }
  }

  /// Fallback build tag stamped into the FITS header when the caller does
  /// not resolve a concrete version (pure-function tests). Keep this small
  /// (≤ 60 chars) so it fits a single 80-char value card with room for a
  /// comment. Production calls pass `nightshadeBuildLabel(ref)` instead so
  /// the stamped tag always tracks version.yaml.
  static const String _nightshadeBuildTag = 'Nightshade';

  /// Build the FITS keyword update set the science pipeline writes back
  /// for a finished frame, given the photometric calibration and
  /// transparency sample produced for that frame.
  ///
  /// Exposed as a pure function so the e2e contract — *what science fields
  /// end up in the FITS header* — can be tested in isolation from the
  /// service, Riverpod, the database, and the native bridge. The returned
  /// list is empty when nothing useful was produced (no calibration AND no
  /// transparency), so callers can short-circuit the writeback in that
  /// case. When *any* keyword is produced the list always ends with a
  /// `NSHA_VER` tag so downstream tools can attribute provenance.
  static List<FitsKeywordWrite> buildScienceWritebackKeywords({
    required FramePhotometricCalibration? calibration,
    required TransparencySample? transparency,
    String buildTag = _nightshadeBuildTag,
  }) {
    final updates = <FitsKeywordWrite>[];
    if (calibration != null) {
      if (calibration.zeroPoint != null && calibration.zeroPoint!.isFinite) {
        updates.add(
          FitsKeywordWrite.floating(
            'MAGZP',
            calibration.zeroPoint!,
            comment: 'Photometric zero point [mag]',
          ),
        );
      }
      if (calibration.calibrationRms.isFinite) {
        updates.add(
          FitsKeywordWrite.floating(
            'MAGZPERR',
            calibration.calibrationRms,
            comment: 'MAGZP 1-sigma uncertainty [mag]',
          ),
        );
      }
      updates.add(
        FitsKeywordWrite.string(
          'MAGZPSRC',
          calibration.catalogSource.name.toUpperCase(),
          comment: 'Catalog used for MAGZP',
        ),
      );
      updates.add(
        FitsKeywordWrite.integer(
          'MAGZPNST',
          calibration.matchedStarCount,
          comment: 'Stars matched in MAGZP fit',
        ),
      );
      if (calibration.limitingMag5Sigma != null &&
          calibration.limitingMag5Sigma!.isFinite) {
        updates.add(
          FitsKeywordWrite.floating(
            'MAGLIM5',
            calibration.limitingMag5Sigma!,
            comment: 'Limiting mag at 5-sigma',
          ),
        );
      }
    }
    if (transparency != null && transparency.transparencyPercent.isFinite) {
      updates.add(
        FitsKeywordWrite.floating(
          'TRANSPAR',
          transparency.transparencyPercent,
          comment: 'Atmospheric transparency [percent]',
        ),
      );
      // EXTINCT carries physical units (mag/airmass), so it is only
      // stamped when the value came from a real ZP-vs-airmass regression.
      // The warm-up fallback stores a baseline ZP depression in plain
      // magnitudes — writing that under this keyword would hand external
      // pipelines a number with the wrong units.
      if (transparency.extinctionFromAirmassFit &&
          transparency.extinctionCoefficient.isFinite) {
        updates.add(
          FitsKeywordWrite.floating(
            'EXTINCT',
            transparency.extinctionCoefficient,
            comment: 'Extinction coeff [mag/airmass]',
          ),
        );
      }
    }
    if (updates.isEmpty) {
      return const <FitsKeywordWrite>[];
    }
    // Always stamp the producing tool so downstream observers can tell
    // which Nightshade build emitted these values.
    updates.add(
      FitsKeywordWrite.string(
        'NSHA_VER',
        buildTag,
        comment: 'Nightshade build that stamped MAGZP*/TRANSPAR',
      ),
    );
    return updates;
  }

  Future<void> generateLineRatios({
    required int sessionId,
    required NarrowbandSet set,
    int? hAlphaImageId,
    int? oiiiImageId,
    int? siiImageId,
  }) async {
    final product = await _scienceBackend.computeLineRatios(
      set,
      const LineRatioOptions(),
    );

    final ratioSiiHa = _metricValue(product.metrics, 'SII/Ha');
    final ratioOiiiHa = _metricValue(product.metrics, 'OIII/Ha');
    final ratioSiiOiii = _metricValue(product.metrics, 'SII/OIII');

    await _scienceDao.insertLineRatioProduct(
      db.LineRatioProductsCompanion.insert(
        sessionId: drift.Value(sessionId),
        hAlphaImageId: drift.Value(hAlphaImageId),
        oiiiImageId: drift.Value(oiiiImageId),
        siiImageId: drift.Value(siiImageId),
        ratioSiiHa: drift.Value(ratioSiiHa),
        ratioOiiiHa: drift.Value(ratioOiiiHa),
        ratioSiiOiii: drift.Value(ratioSiiOiii),
        createdAt: drift.Value(product.createdAt),
      ),
    );
  }
}
