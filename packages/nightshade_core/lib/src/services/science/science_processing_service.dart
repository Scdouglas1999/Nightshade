import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../../database/database.dart' as db;
import '../../database/daos/science_dao.dart';
import '../../providers/database_provider.dart';
import '../imaging_records_repository.dart';
import '../../providers/science_provider.dart';
import '../../providers/science_status_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/logging_service.dart';
import '../../models/science/science_models.dart';
import 'default_science_backend.dart';
import 'fits_header_writer.dart';
import 'photometric_transform_service.dart';
import 'science_backend.dart';
import 'frame_auto_grader.dart';
import 'science_status.dart';

class ScienceProcessingService {
  final Ref _ref;
  int _adaptiveLiveGridRows = 12;
  int _adaptiveLiveGridCols = 16;
  int _liveBudgetBreachCount = 0;
  int _queueDepth = 0;

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
  }) async {
    _queueDepth++;
    _status.enqueue();
    _logger.debug('science.queue_depth=$_queueDepth',
        source: 'ScienceProcessingService');

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
          wcs == null
              ? ScienceStageOutcome.noData
              : ScienceStageOutcome.ok,
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
              note: 'ZP ${calibration.zeroPoint?.toStringAsFixed(2) ?? "—"}, '
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
        final recentRows =
            await _scienceDao.getRecentCalibrations(sessionId, limit: 20);
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
            note: '${psfMap.tiles.length} tiles, '
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
          final residualMap =
              await _scienceBackend.computeAstrometricResiduals(
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
                    recommendationCode:
                        drift.Value(residualMap.suggestionCode),
                    timestamp: drift.Value(frameContext.capturedAt),
                  ),
                )
                .toList(growable: false);
            await _scienceDao.replaceResidualVectorsForImage(
                capturedImageId, rows);
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
              .catchError(
                (_) => const SciencePhotometrySelection(),
              );
          final photometryResult = await _computeAndStorePhotometry(
            imagePath: imagePath,
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            wcs: wcs,
            selection: photometrySelection,
            frameTimestamp: frameContext.capturedAt,
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
          final recentPaths = recent
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
                    timestamp: drift.Value(frameContext.capturedAt),
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
      final rejected =
          await _ref.read(frameAutoGraderProvider).gradeCapturedFrame(
                image: fresh,
              );
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

  /// Build tag stamped into the FITS header. Keep this small (≤ 60 chars)
  /// so it fits a single 80-char value card with room for a comment.
  static const String _nightshadeBuildTag = 'Nightshade 2.5.0';

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
        updates.add(FitsKeywordWrite.floating(
          'MAGZP',
          calibration.zeroPoint!,
          comment: 'Photometric zero point [mag]',
        ));
      }
      if (calibration.calibrationRms.isFinite) {
        updates.add(FitsKeywordWrite.floating(
          'MAGZPERR',
          calibration.calibrationRms,
          comment: 'MAGZP 1-sigma uncertainty [mag]',
        ));
      }
      updates.add(FitsKeywordWrite.string(
        'MAGZPSRC',
        calibration.catalogSource.name.toUpperCase(),
        comment: 'Catalog used for MAGZP',
      ));
      updates.add(FitsKeywordWrite.integer(
        'MAGZPNST',
        calibration.matchedStarCount,
        comment: 'Stars matched in MAGZP fit',
      ));
      if (calibration.limitingMag5Sigma != null &&
          calibration.limitingMag5Sigma!.isFinite) {
        updates.add(FitsKeywordWrite.floating(
          'MAGLIM5',
          calibration.limitingMag5Sigma!,
          comment: 'Limiting mag at 5-sigma',
        ));
      }
    }
    if (transparency != null && transparency.transparencyPercent.isFinite) {
      updates.add(FitsKeywordWrite.floating(
        'TRANSPAR',
        transparency.transparencyPercent,
        comment: 'Atmospheric transparency [percent]',
      ));
      if (transparency.extinctionCoefficient.isFinite) {
        updates.add(FitsKeywordWrite.floating(
          'EXTINCT',
          transparency.extinctionCoefficient,
          comment: 'Extinction coeff [mag/airmass]',
        ));
      }
    }
    if (updates.isEmpty) {
      return const <FitsKeywordWrite>[];
    }
    // Always stamp the producing tool so downstream observers can tell
    // which Nightshade build emitted these values.
    updates.add(FitsKeywordWrite.string(
      'NSHA_VER',
      buildTag,
      comment: 'Nightshade build that stamped MAGZP*/TRANSPAR',
    ));
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

  Future<void> _processImmediateQualityLane({
    required String imagePath,
    required String? deviceId,
    required int? capturedImageId,
    required int? sessionId,
    required DateTime timestamp,
  }) async {
    final laneStopwatch = Stopwatch()..start();
    final prefs = await _ref
        .read(scienceVisualizationPrefsProvider.future)
        .catchError((_) => const ScienceVisualizationPrefs());

    if (_adaptiveLiveGridRows <= 0) {
      _adaptiveLiveGridRows = prefs.liveGridRows;
    }
    if (_adaptiveLiveGridCols <= 0) {
      _adaptiveLiveGridCols = prefs.liveGridCols;
    }

    const lowClipAdu = 16;
    const highClipAdu = 65520;
    (ScienceFrameQualityMetrics, List<ScienceTileMetric>) products;

    try {
      if (deviceId != null && deviceId.isNotEmpty) {
        products = await _scienceBackend.computeLastCaptureQualityMaps(
          deviceId: deviceId,
          gridRows: _adaptiveLiveGridRows,
          gridCols: _adaptiveLiveGridCols,
          lowClipAdu: lowClipAdu,
          highClipAdu: highClipAdu,
          timestamp: timestamp,
          capturedImageId: capturedImageId,
          sessionId: sessionId,
        );
      } else {
        throw StateError('No device ID available for live quality maps');
      }
    } catch (error, stack) {
      _logger.warning(
        'Live quality-map lane failed for $imagePath; falling back to FITS lane: $error\n$stack',
        source: 'ScienceProcessingService',
      );
      products = await _scienceBackend.computeFitsQualityMaps(
        filePath: imagePath,
        gridRows: prefs.analysisGridRows,
        gridCols: prefs.analysisGridCols,
        lowClipAdu: lowClipAdu,
        highClipAdu: highClipAdu,
        timestamp: timestamp,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
      );
    }

    final frameMetrics = products.$1.copyWith(
      processingMs: laneStopwatch.elapsedMilliseconds,
    );
    final tileMetrics = products.$2;
    final frameCompanion = db.ScienceFrameQualityMetricsCompanion.insert(
      capturedImageId: drift.Value(capturedImageId),
      sessionId: drift.Value(sessionId),
      timestamp: drift.Value(frameMetrics.timestamp),
      median: drift.Value(frameMetrics.median),
      mean: drift.Value(frameMetrics.mean),
      stdDev: drift.Value(frameMetrics.stdDev),
      mad: drift.Value(frameMetrics.mad),
      background: drift.Value(frameMetrics.background),
      noise: drift.Value(frameMetrics.noise),
      snr: drift.Value(frameMetrics.snr),
      dynamicRangeP1P99: drift.Value(frameMetrics.dynamicRangeP1P99),
      lowClipPercent: drift.Value(frameMetrics.lowClipPercent),
      highClipPercent: drift.Value(frameMetrics.highClipPercent),
      uniformityCv: drift.Value(frameMetrics.uniformityCv),
      gradientX: drift.Value(frameMetrics.gradientX),
      gradientY: drift.Value(frameMetrics.gradientY),
      processingTier: drift.Value(frameMetrics.processingTier),
      processingMs: drift.Value(frameMetrics.processingMs),
    );

    final tileCompanions = tileMetrics
        .map(
          (tile) => db.ScienceTileMetricsCompanion.insert(
            capturedImageId: drift.Value(tile.capturedImageId),
            sessionId: drift.Value(tile.sessionId),
            timestamp: drift.Value(tile.timestamp),
            layerType: tile.layerType.dbValue,
            tileRow: tile.tileRow,
            tileCol: tile.tileCol,
            sampleCount: drift.Value(tile.sampleCount),
            value: drift.Value(tile.value),
            p05: drift.Value(tile.p05),
            p50: drift.Value(tile.p50),
            p95: drift.Value(tile.p95),
            auxValue: drift.Value(tile.auxValue),
          ),
        )
        .toList(growable: false);

    if (capturedImageId != null) {
      await _scienceDao.replaceFrameQualityMetricsForImage(
        capturedImageId,
        frameCompanion,
      );
      await _scienceDao.replaceTileMetricsForImage(
          capturedImageId, tileCompanions);
    } else {
      await _scienceDao.insertFrameQualityMetrics(frameCompanion);
      await _scienceDao.insertTileMetrics(tileCompanions);
    }

    final liveMs = laneStopwatch.elapsedMilliseconds;
    _logger.debug('science.live_ms=$liveMs',
        source: 'ScienceProcessingService');
    if (liveMs > 150) {
      _liveBudgetBreachCount++;
      if (_liveBudgetBreachCount >= 3) {
        _adaptiveLiveGridRows =
            math.max(6, (_adaptiveLiveGridRows * 0.8).floor());
        _adaptiveLiveGridCols =
            math.max(8, (_adaptiveLiveGridCols * 0.8).floor());
        _liveBudgetBreachCount = 0;
      }
    } else {
      _liveBudgetBreachCount = math.max(0, _liveBudgetBreachCount - 1);
    }
  }

  /// Computes and persists photometry rows for the frame. Returns the number
  /// of [PhotometryMeasurements] rows actually written, or `0` when the frame
  /// produced no measurements (too few stars, comparison set unusable, etc.).
  /// Callers use the count for status-pipeline reporting.
  Future<int> _computeAndStorePhotometry({
    required String imagePath,
    required int? capturedImageId,
    required int? sessionId,
    required WcsSolution? wcs,
    required SciencePhotometrySelection selection,
    required DateTime frameTimestamp,
    String? filterName,
    double? airmass,
  }) async {
    final stars = await _scienceBackend.measureStars(
      imagePath,
      const PhotometryOptions(minSnr: 4.0),
    );

    if (stars.length < 3) {
      return 0;
    }

    final sortedByFlux = stars.toList(growable: false)
      ..sort((a, b) => b.flux.compareTo(a.flux));
    final available = sortedByFlux.toList(growable: true);

    StarMeasurement? target;
    String targetObjectId = 'target_primary';
    final comparisonObjects = <({String objectId, StarMeasurement star})>[];

    if (selection.differentialEnabled &&
        selection.target != null &&
        wcs != null) {
      try {
        final fits = await apiReadFitsFile(filePath: imagePath);
        final targetPixel = _skyToPixel(
          wcs: wcs,
          raDegrees: selection.target!.raDegrees,
          decDegrees: selection.target!.decDegrees,
          imageWidth: fits.width.toDouble(),
          imageHeight: fits.height.toDouble(),
        );
        if (targetPixel != null) {
          final matchedTarget = _findNearestStar(
            available,
            x: targetPixel.x,
            y: targetPixel.y,
            maxDistancePixels: 20.0,
          );
          if (matchedTarget != null) {
            target = matchedTarget;
            targetObjectId = selection.target!.objectId;
            available.remove(matchedTarget);
          }
        }

        for (final anchor in selection.comparisons) {
          final anchorPixel = _skyToPixel(
            wcs: wcs,
            raDegrees: anchor.raDegrees,
            decDegrees: anchor.decDegrees,
            imageWidth: fits.width.toDouble(),
            imageHeight: fits.height.toDouble(),
          );
          if (anchorPixel == null) {
            continue;
          }
          final matched = _findNearestStar(
            available,
            x: anchorPixel.x,
            y: anchorPixel.y,
            maxDistancePixels: 20.0,
          );
          if (matched == null) {
            continue;
          }
          comparisonObjects.add((objectId: anchor.objectId, star: matched));
          available.remove(matched);
          if (comparisonObjects.length >= 8) {
            break;
          }
        }
      } catch (error, stack) {
        _logger.warning(
          'Failed to resolve configured photometry anchors for $imagePath: $error\n$stack',
          source: 'ScienceProcessingService',
        );
      }
    }

    if (target == null) {
      target = sortedByFlux.first;
      available.remove(target);
    }

    if (comparisonObjects.length < 2) {
      final fallback = available.take(4).toList(growable: false);
      for (var index = 0; index < fallback.length; index++) {
        comparisonObjects.add(
          (objectId: 'comparison_${index + 1}', star: fallback[index]),
        );
      }
    }

    if (comparisonObjects.length < 2) {
      return 0;
    }

    final comparisonFluxes = comparisonObjects
        .map((entry) => entry.star.flux)
        .toList(growable: false)
      ..sort();
    final medianComparisonFlux = _median(comparisonFluxes);
    final madComparisonFlux = _mad(comparisonFluxes, medianComparisonFlux);
    final robustSigma =
        (1.4826 * madComparisonFlux).clamp(0.0, double.infinity);

    final inliers = <({String objectId, StarMeasurement star})>[];
    final outlierObjectIds = <String>{};
    for (final entry in comparisonObjects) {
      if (robustSigma <= 0.0) {
        inliers.add(entry);
        continue;
      }
      final deviation = (entry.star.flux - medianComparisonFlux).abs();
      if (deviation <= 3.0 * robustSigma) {
        inliers.add(entry);
      } else {
        outlierObjectIds.add(entry.objectId);
      }
    }

    final effectiveComparisons =
        inliers.length >= 2 ? inliers : comparisonObjects;
    final weightedFluxTuple = _weightedComparisonFlux(effectiveComparisons);
    final comparisonFlux = weightedFluxTuple.$1;
    final comparisonFluxUncertainty = weightedFluxTuple.$2;
    if (comparisonFlux <= 0 || !comparisonFlux.isFinite) {
      return 0;
    }

    final targetFlux = target.flux.clamp(1e-6, double.infinity);
    final targetSnr =
        target.snr.isFinite ? target.snr.clamp(1.0, 1e6).toDouble() : 1.0;
    final targetFluxSigma = targetFlux / targetSnr;

    final differentialMag = -2.5 *
        math.log((targetFlux / comparisonFlux).clamp(1e-6, double.infinity)) /
        math.ln10;
    final fractionalVariance = math.pow(targetFluxSigma / targetFlux, 2) +
        math.pow(
            comparisonFluxUncertainty /
                comparisonFlux.clamp(1e-6, double.infinity),
            2);
    final uncertainty = 1.0857 *
        math.sqrt(fractionalVariance.isFinite ? fractionalVariance : 0.0);

    // Try to apply photometric transform for absolute magnitude
    PhotometricTransformCoefficients? transform;
    if (filterName != null && filterName.isNotEmpty) {
      try {
        final transformService = _ref.read(photometricTransformServiceProvider);
        transform = await transformService.getTransformForFilter(filterName);
      } catch (error) {
        _logger.debug(
          'No photometric transform available for filter $filterName: $error',
          source: 'ScienceProcessingService',
        );
      }
    }

    double? targetStandardMag;
    if (transform != null && airmass != null && airmass > 0) {
      final instMag = -2.5 *
          math.log(targetFlux.clamp(1e-30, double.infinity)) /
          math.ln10;
      // Use color index 0.0 as default when unknown — the color term
      // contribution is typically small for broadband filters.
      targetStandardMag = transform.applyTransform(
        instrumentalMag: instMag,
        airmass: airmass,
        colorIndex: 0.0,
      );
      if (!targetStandardMag.isFinite) {
        targetStandardMag = null;
      }
    }

    final entries = <db.PhotometryMeasurementsCompanion>[
      db.PhotometryMeasurementsCompanion.insert(
        capturedImageId: drift.Value(capturedImageId),
        sessionId: drift.Value(sessionId),
        objectId: targetObjectId,
        role: const drift.Value('target'),
        x: target.x,
        y: target.y,
        flux: targetFlux,
        differentialMagnitude: drift.Value(differentialMag),
        standardMagnitude: drift.Value(targetStandardMag),
        snr: drift.Value(target.snr),
        uncertainty: drift.Value(uncertainty),
        timestamp: drift.Value(frameTimestamp),
      ),
    ];

    for (var index = 0; index < comparisonObjects.length; index++) {
      final objectId = comparisonObjects[index].objectId;
      final star = comparisonObjects[index].star;

      double? compStandardMag;
      if (transform != null && airmass != null && airmass > 0) {
        final compFlux = star.flux.clamp(1e-6, double.infinity);
        final compInstMag = -2.5 *
            math.log(compFlux.clamp(1e-30, double.infinity)) /
            math.ln10;
        compStandardMag = transform.applyTransform(
          instrumentalMag: compInstMag,
          airmass: airmass,
          colorIndex: 0.0,
        );
        if (!compStandardMag.isFinite) {
          compStandardMag = null;
        }
      }

      entries.add(
        db.PhotometryMeasurementsCompanion.insert(
          capturedImageId: drift.Value(capturedImageId),
          sessionId: drift.Value(sessionId),
          objectId: objectId,
          role: const drift.Value('comparison'),
          x: star.x,
          y: star.y,
          flux: star.flux,
          differentialMagnitude: const drift.Value<double?>(null),
          standardMagnitude: drift.Value(compStandardMag),
          snr: drift.Value(star.snr),
          uncertainty: drift.Value<double?>(
            star.flux /
                (star.snr.isFinite ? star.snr.clamp(1.0, 1e6).toDouble() : 1.0),
          ),
          isOutlier: drift.Value(outlierObjectIds.contains(objectId)),
          timestamp: drift.Value(frameTimestamp),
        ),
      );
    }

    if (capturedImageId != null) {
      await _scienceDao.replacePhotometryMeasurementsForImage(
        capturedImageId,
        entries,
      );
    } else {
      await _scienceDao.insertPhotometryMeasurements(entries);
    }
    return entries.length;
  }

  ({double x, double y})? _skyToPixel({
    required WcsSolution wcs,
    required double raDegrees,
    required double decDegrees,
    required double imageWidth,
    required double imageHeight,
  }) {
    final raRad = raDegrees * math.pi / 180.0;
    final decRad = decDegrees * math.pi / 180.0;
    final centerRaRad = (wcs.raHours * 15.0) * math.pi / 180.0;
    final centerDecRad = wcs.decDegrees * math.pi / 180.0;

    final dRa = _normalizeRadians(raRad - centerRaRad);
    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCenterDec = math.cos(centerDecRad);
    final sinCenterDec = math.sin(centerDecRad);

    final denominator =
        sinCenterDec * sinDec + cosCenterDec * cosDec * math.cos(dRa);
    if (denominator <= 0.0) {
      return null;
    }

    final xi = cosDec * math.sin(dRa) / denominator;
    final eta =
        (cosCenterDec * sinDec - sinCenterDec * cosDec * math.cos(dRa)) /
            denominator;

    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;

    final rotRad = wcs.rotationDegrees * math.pi / 180.0;
    final cosRot = math.cos(rotRad);
    final sinRot = math.sin(rotRad);
    final xiRot = xiDeg * cosRot - etaDeg * sinRot;
    final etaRot = xiDeg * sinRot + etaDeg * cosRot;

    final x =
        (xiRot * 3600.0 / wcs.pixelScaleArcsecPerPixel) + imageWidth / 2.0;
    final y =
        imageHeight / 2.0 - (etaRot * 3600.0 / wcs.pixelScaleArcsecPerPixel);
    if (!x.isFinite || !y.isFinite) {
      return null;
    }
    return (x: x, y: y);
  }

  StarMeasurement? _findNearestStar(
    List<StarMeasurement> stars, {
    required double x,
    required double y,
    required double maxDistancePixels,
  }) {
    StarMeasurement? best;
    var bestDistance = maxDistancePixels;
    for (final star in stars) {
      final dx = star.x - x;
      final dy = star.y - y;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = star;
      }
    }
    return best;
  }

  (double, double) _weightedComparisonFlux(
      List<({String objectId, StarMeasurement star})> comparisons) {
    if (comparisons.isEmpty) {
      return (0.0, 0.0);
    }

    var weightedSum = 0.0;
    var weightSum = 0.0;
    for (final entry in comparisons) {
      final star = entry.star;
      final flux = star.flux.clamp(1e-6, double.infinity);
      final safeSnr =
          star.snr.isFinite ? star.snr.clamp(1.0, 1e6).toDouble() : 1.0;
      final sigma = flux / safeSnr;
      final variance = math.max(1e-12, sigma * sigma);
      final weight = 1.0 / variance;
      weightedSum += flux * weight;
      weightSum += weight;
    }

    if (weightSum <= 0.0) {
      return (0.0, 0.0);
    }

    final flux = weightedSum / weightSum;
    final sigma = math.sqrt(1.0 / weightSum);
    return (flux, sigma);
  }

  double _normalizeRadians(double value) {
    var wrapped = value;
    while (wrapped > math.pi) {
      wrapped -= 2.0 * math.pi;
    }
    while (wrapped < -math.pi) {
      wrapped += 2.0 * math.pi;
    }
    return wrapped;
  }

  double _median(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    final sorted = values.toList(growable: false)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }

  double _mad(List<double> values, double median) {
    if (values.isEmpty) {
      return 0.0;
    }
    final deviations =
        values.map((value) => (value - median).abs()).toList(growable: false);
    return _median(deviations);
  }

  Future<WcsSolution?> _resolveWcsSolution({
    required String imagePath,
    required int? capturedImageId,
    db.CapturedImage? capturedImage,
  }) async {
    final image = capturedImageId == null
        ? null
        : (capturedImage ?? await _imagesRepo.getImageById(capturedImageId));
    if (image != null &&
        image.isPlateSolved &&
        image.solvedRa != null &&
        image.solvedDec != null) {
      final pixelScale = image.solvedPixelScale ?? 1.5;
      var fieldWidth = 1.0;
      var fieldHeight = 1.0;
      try {
        final fits = await apiReadFitsFile(filePath: imagePath);
        fieldWidth =
            (fits.width * pixelScale / 3600.0).clamp(0.05, 40.0).toDouble();
        fieldHeight =
            (fits.height * pixelScale / 3600.0).clamp(0.05, 40.0).toDouble();
      } catch (error, stack) {
        _logger.warning(
          'Unable to derive field size from FITS for stored WCS ($imagePath): $error\n$stack',
          source: 'ScienceProcessingService',
        );
      }
      return WcsSolution(
        raHours: image.solvedRa!,
        decDegrees: image.solvedDec!,
        pixelScaleArcsecPerPixel: pixelScale,
        rotationDegrees: image.solvedRotation ?? 0.0,
        fieldWidthDegrees: fieldWidth,
        fieldHeightDegrees: fieldHeight,
        solverId: 'stored',
      );
    }

    final solved = await _scienceBackend.solveForScience(
      imagePath,
      const SolveOptions(),
    );

    if (solved != null && capturedImageId != null) {
      await _imagesRepo.updatePlateSolveResult(
        capturedImageId,
        solvedRa: solved.raHours,
        solvedDec: solved.decDegrees,
        solvedRotation: solved.rotationDegrees,
        solvedPixelScale: solved.pixelScaleArcsecPerPixel,
      );
    }

    return solved;
  }

  Future<ScienceFrameContext> _buildFrameContext({
    required String imagePath,
    required int? capturedImageId,
    required int? sessionId,
    required db.CapturedImage? capturedImage,
    required WcsSolution? wcs,
  }) async {
    FitsReadResult? fits;
    try {
      fits = await apiReadFitsFile(filePath: imagePath);
    } catch (error, stack) {
      _logger.warning(
        'FITS metadata read failed for $imagePath. Continuing only with trusted DB metadata: $error\n$stack',
        source: 'ScienceProcessingService',
      );
    }

    final fitsCapturedAt =
        fits?.dateObs == null ? null : DateTime.tryParse(fits!.dateObs!);
    final capturedAt = capturedImage?.capturedAt ?? fitsCapturedAt;
    if (capturedAt == null) {
      throw StateError(
        'Capture timestamp unavailable for $imagePath. Need captured image metadata or FITS DATE-OBS.',
      );
    }

    final exposureRaw = capturedImage?.exposureDuration ?? fits?.exposureTime;
    if (exposureRaw == null || !exposureRaw.isFinite || exposureRaw <= 0.0) {
      throw StateError(
        'Exposure duration unavailable for $imagePath. Need captured image metadata or FITS exposure time.',
      );
    }
    final exposureSeconds = exposureRaw.clamp(0.001, 1e6).toDouble();
    final filterName = capturedImage?.filter ?? fits?.filter;
    final width = fits?.width ?? 0;
    final height = fits?.height ?? 0;

    double? airmass;
    if (capturedImage != null) {
      airmass = await _airmassForCapturedImage(
        image: capturedImage,
        timestamp: capturedAt,
      );
    } else if (wcs != null) {
      airmass = await _airmassFromWcs(
        wcs: wcs,
        timestamp: capturedAt,
      );
    }

    return ScienceFrameContext(
      capturedImageId: capturedImageId,
      sessionId: sessionId,
      capturedAt: capturedAt,
      exposureSeconds: exposureSeconds,
      filterName: filterName,
      airmass: airmass,
      imageWidth: width,
      imageHeight: height,
    );
  }

  Future<DateTime> _resolveFrameTimestamp({
    required String imagePath,
    required db.CapturedImage? capturedImage,
  }) async {
    if (capturedImage?.capturedAt case final ts?) {
      return ts;
    }

    try {
      return await File(imagePath).lastModified();
    } catch (error, stack) {
      _logger.warning(
        'Failed to resolve frame timestamp from metadata for $imagePath: $error\n$stack',
        source: 'ScienceProcessingService',
      );
      throw StateError(
        'Frame timestamp is unavailable for $imagePath. Capture metadata is required.',
      );
    }
  }

  Future<double?> _airmassFromWcs({
    required WcsSolution wcs,
    required DateTime timestamp,
  }) async {
    return _airmassFromCoordinates(
      raHours: wcs.raHours,
      decDegrees: wcs.decDegrees,
      timestamp: timestamp,
      sourceLabel: 'WCS',
    );
  }

  Future<double?> _airmassFromCoordinates({
    required double raHours,
    required double decDegrees,
    required DateTime timestamp,
    required String sourceLabel,
  }) async {
    final settings = _ref.read(appSettingsProvider).valueOrNull;
    if (settings == null ||
        settings.latitude == 0.0 && settings.longitude == 0.0) {
      return null;
    }
    try {
      final altitude = apiCalculateAltitude(
        raHours: raHours,
        decDegrees: decDegrees,
        latitude: settings.latitude,
        longitude: settings.longitude,
        timeUnixMillis: timestamp.toUtc().millisecondsSinceEpoch,
      );
      return _airmassFromAltitude(altitude);
    } catch (error, stack) {
      _logger.warning(
        'Airmass calculation failed ($sourceLabel RA=$raHours, Dec=$decDegrees, lat=${settings.latitude}, lon=${settings.longitude}, ts=${timestamp.toUtc().toIso8601String()}): $error\n$stack',
        source: 'ScienceProcessingService',
      );
      return null;
    }
  }

  Future<double?> _airmassForCapturedImage({
    required db.CapturedImage image,
    required DateTime timestamp,
  }) async {
    if (image.mountAltitude != null) {
      return _airmassFromAltitude(image.mountAltitude!);
    }
    if (image.solvedRa != null && image.solvedDec != null) {
      return _airmassFromCoordinates(
        raHours: image.solvedRa!,
        decDegrees: image.solvedDec!,
        timestamp: timestamp,
        sourceLabel: 'Stored solved coordinates',
      );
    }
    return null;
  }

  double? _airmassFromAltitude(double altitudeDegrees) {
    if (!altitudeDegrees.isFinite || altitudeDegrees <= 0.0) {
      return null;
    }
    final altitude = altitudeDegrees.clamp(0.01, 89.9999);
    final zenithDistance = 90.0 - altitude;
    final cosZ = math.cos(zenithDistance * math.pi / 180.0);
    if (cosZ <= 0) {
      return null;
    }
    final kastenYoung = 1.0 /
        (math.sin(altitude * math.pi / 180.0) +
            0.50572 * math.pow(altitude + 6.07995, -1.6364));
    if (!kastenYoung.isFinite) {
      return 1.0 / cosZ;
    }
    return kastenYoung.clamp(1.0, 8.0).toDouble();
  }

  PhotometricCatalogSource _catalogFromName(String source) {
    for (final catalog in PhotometricCatalogSource.values) {
      if (catalog.name == source) {
        return catalog;
      }
    }
    return PhotometricCatalogSource.auto;
  }

  double _metricValue(List<LineRatioMetric> metrics, String label) {
    for (final metric in metrics) {
      if (metric.label == label) {
        return metric.value;
      }
    }
    return 0.0;
  }
}

final scienceProcessingServiceProvider =
    Provider<ScienceProcessingService>((ref) {
  return ScienceProcessingService(ref);
});
