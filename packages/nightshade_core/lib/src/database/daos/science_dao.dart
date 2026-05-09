import 'package:drift/drift.dart';

import '../../models/science/science_models.dart' as science;
import '../database.dart';
import '../tables/science.dart';

part 'science_dao.g.dart';

@DriftAccessor(tables: [
  ScienceSessionConfig,
  PhotometryMeasurements,
  FramePhotometricCalibration,
  TransparencySamples,
  PsfFieldTiles,
  ScienceFrameQualityMetrics,
  ScienceTileMetrics,
  AstrometryResidualVectors,
  MovingObjectCandidates,
  LineRatioProducts,
  PhotometricTransforms,
])
class ScienceDao extends DatabaseAccessor<NightshadeDatabase>
    with _$ScienceDaoMixin {
  ScienceDao(NightshadeDatabase db) : super(db);

  Future<void> upsertSessionConfig(science.ScienceSessionConfig config) async {
    if (config.sessionId == null) {
      return;
    }

    await transaction(() async {
      final existing = await (select(scienceSessionConfig)
            ..where((tbl) => tbl.sessionId.equals(config.sessionId!)))
          .getSingleOrNull();

      final companion = ScienceSessionConfigCompanion(
        sessionId: Value(config.sessionId),
        photometryEnabled: Value(config.photometryEnabled),
        calibrationEnabled: Value(config.calibrationEnabled),
        transparencyEnabled: Value(config.transparencyEnabled),
        psfMapEnabled: Value(config.psfMapEnabled),
        residualsEnabled: Value(config.residualsEnabled),
        movingObjectsEnabled: Value(config.movingObjectsEnabled),
        narrowbandEnabled: Value(config.narrowbandEnabled),
        psfGridRows: Value(config.psfGridRows),
        psfGridCols: Value(config.psfGridCols),
        transparencyAlertThreshold: Value(config.transparencyAlertThreshold),
        updatedAt: Value(DateTime.now()),
      );

      if (existing == null) {
        await into(scienceSessionConfig).insert(companion);
      } else {
        await (update(scienceSessionConfig)
              ..where((tbl) => tbl.id.equals(existing.id)))
            .write(companion);
      }
    });
  }

  Stream<ScienceSessionConfigRow?> watchSessionConfig(int sessionId) {
    return (select(scienceSessionConfig)
          ..where((tbl) => tbl.sessionId.equals(sessionId)))
        .watchSingleOrNull();
  }

  Future<void> insertPhotometryMeasurements(
      List<PhotometryMeasurementsCompanion> entries) async {
    if (entries.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(photometryMeasurements, entries);
    });
  }

  Future<void> replacePhotometryMeasurementsForImage(
    int capturedImageId,
    List<PhotometryMeasurementsCompanion> entries,
  ) async {
    await (delete(photometryMeasurements)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    if (entries.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(photometryMeasurements, entries);
    });
  }

  Stream<List<PhotometryMeasurementRow>> watchLightCurve(
      int sessionId, String objectId) {
    return (select(photometryMeasurements)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) & tbl.objectId.equals(objectId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Stream<List<PhotometryMeasurementRow>> watchPhotometryForSession(
      int sessionId) {
    return (select(photometryMeasurements)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Future<List<PhotometryMeasurementRow>> getPhotometryForSession(
      int sessionId) {
    return (select(photometryMeasurements)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Future<void> insertFrameCalibration(
      FramePhotometricCalibrationCompanion calibration) {
    return into(framePhotometricCalibration).insert(calibration);
  }

  Future<void> replaceFrameCalibrationForImage(
    int capturedImageId,
    FramePhotometricCalibrationCompanion calibration,
  ) async {
    await (delete(framePhotometricCalibration)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    await into(framePhotometricCalibration).insert(calibration);
  }

  Stream<List<FramePhotometricCalibrationRow>> watchCalibrationsForSession(
      int sessionId) {
    return (select(framePhotometricCalibration)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Future<List<FramePhotometricCalibrationRow>> getCalibrationsForSession(
      int sessionId) {
    return (select(framePhotometricCalibration)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Future<List<FramePhotometricCalibrationRow>> getRecentCalibrations(
    int sessionId, {
    int limit = 20,
  }) {
    return (select(framePhotometricCalibration)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) & tbl.isCalibrated.equals(true))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .get();
  }

  Future<void> insertTransparencySample(TransparencySamplesCompanion sample) {
    return into(transparencySamples).insert(sample);
  }

  Future<void> replaceTransparencySampleForImage(
    int capturedImageId,
    TransparencySamplesCompanion sample,
  ) async {
    await (delete(transparencySamples)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    await into(transparencySamples).insert(sample);
  }

  Stream<List<TransparencySampleRow>> watchTransparencyForSession(
      int sessionId) {
    return (select(transparencySamples)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Future<List<TransparencySampleRow>> getTransparencyForSession(
      int sessionId) {
    return (select(transparencySamples)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Future<void> replacePsfTilesForImage(
    int capturedImageId,
    List<PsfFieldTilesCompanion> tiles,
  ) async {
    await (delete(psfFieldTiles)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    if (tiles.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(psfFieldTiles, tiles);
    });
  }

  Stream<List<PsfFieldTileRow>> watchPsfTilesForSession(int sessionId) {
    return (select(psfFieldTiles)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ]))
        .watch();
  }

  Future<List<PsfFieldTileRow>> getPsfTilesForSession(int sessionId) {
    return (select(psfFieldTiles)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ]))
        .get();
  }

  Future<void> insertFrameQualityMetrics(
      ScienceFrameQualityMetricsCompanion metrics) {
    return into(scienceFrameQualityMetrics).insert(metrics);
  }

  Future<void> replaceFrameQualityMetricsForImage(
    int capturedImageId,
    ScienceFrameQualityMetricsCompanion metrics,
  ) async {
    await (delete(scienceFrameQualityMetrics)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    await into(scienceFrameQualityMetrics).insert(metrics);
  }

  Stream<List<ScienceFrameQualityMetricsRow>>
      watchFrameQualityMetricsForSession(int sessionId) {
    return (select(scienceFrameQualityMetrics)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Future<List<ScienceFrameQualityMetricsRow>>
      getFrameQualityMetricsForSession(int sessionId) {
    return (select(scienceFrameQualityMetrics)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Stream<ScienceFrameQualityMetricsRow?> watchFrameQualityMetricsForImage(
      int capturedImageId) {
    return (select(scienceFrameQualityMetrics)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<void> replaceTileMetricsForImage(
    int capturedImageId,
    List<ScienceTileMetricsCompanion> tiles,
  ) async {
    await (delete(scienceTileMetrics)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    if (tiles.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(scienceTileMetrics, tiles);
    });
  }

  Future<void> insertTileMetrics(
      List<ScienceTileMetricsCompanion> tiles) async {
    if (tiles.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(scienceTileMetrics, tiles);
    });
  }

  Future<void> replaceTileMetricsForImageLayer(
    int capturedImageId,
    String layerType,
    List<ScienceTileMetricsCompanion> tiles,
  ) async {
    await (delete(scienceTileMetrics)
          ..where((tbl) =>
              tbl.capturedImageId.equals(capturedImageId) &
              tbl.layerType.equals(layerType)))
        .go();
    if (tiles.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(scienceTileMetrics, tiles);
    });
  }

  Stream<List<ScienceTileMetricRow>> watchTileMetricsForSession(int sessionId) {
    return (select(scienceTileMetrics)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ]))
        .watch();
  }

  Future<List<ScienceTileMetricRow>> getTileMetricsForSession(int sessionId) {
    return (select(scienceTileMetrics)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ]))
        .get();
  }

  Stream<List<ScienceTileMetricRow>> watchTileMetricsForSessionLayer(
    int sessionId,
    String layerType,
  ) {
    return (select(scienceTileMetrics)
          ..where((tbl) =>
              tbl.sessionId.equals(sessionId) & tbl.layerType.equals(layerType))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ]))
        .watch();
  }

  Future<void> replaceResidualVectorsForImage(
    int capturedImageId,
    List<AstrometryResidualVectorsCompanion> vectors,
  ) async {
    await (delete(astrometryResidualVectors)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    if (vectors.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(astrometryResidualVectors, vectors);
    });
  }

  Stream<List<AstrometryResidualVectorRow>> watchResidualsForSession(
      int sessionId) {
    return (select(astrometryResidualVectors)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .watch();
  }

  Future<List<AstrometryResidualVectorRow>> getResidualsForSession(
      int sessionId) {
    return (select(astrometryResidualVectors)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Future<void> insertMovingObjectCandidates(
      List<MovingObjectCandidatesCompanion> candidates) async {
    if (candidates.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(movingObjectCandidates, candidates);
    });
  }

  Future<void> replaceMovingObjectCandidatesForImage(
    int capturedImageId,
    List<MovingObjectCandidatesCompanion> candidates,
  ) async {
    await (delete(movingObjectCandidates)
          ..where((tbl) => tbl.capturedImageId.equals(capturedImageId)))
        .go();
    if (candidates.isEmpty) {
      return;
    }
    await batch((batch) {
      batch.insertAll(movingObjectCandidates, candidates);
    });
  }

  Stream<List<MovingObjectCandidateRow>> watchMovingObjectsForSession(
      int sessionId) {
    return (select(movingObjectCandidates)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.confidence)]))
        .watch();
  }

  Future<List<MovingObjectCandidateRow>> getMovingObjectsForSession(
      int sessionId) {
    return (select(movingObjectCandidates)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.confidence)]))
        .get();
  }

  /// Get all moving object candidates matching a candidateId across all
  /// sessions. Used for multi-night linking -- finding the same object
  /// across different imaging nights for MPC reporting.
  Future<List<MovingObjectCandidateRow>> getMovingObjectsByCandidateId(
      String candidateId) async {
    return (select(movingObjectCandidates)
          ..where((tbl) => tbl.candidateId.equals(candidateId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  /// Get all moving object candidates across all sessions, ordered by
  /// timestamp. Used for MPC export multi-night linking.
  Future<List<MovingObjectCandidateRow>> getAllMovingObjectCandidates() async {
    return (select(movingObjectCandidates)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]))
        .get();
  }

  Future<void> insertLineRatioProduct(LineRatioProductsCompanion product) {
    return into(lineRatioProducts).insert(product);
  }

  Stream<List<LineRatioProductRow>> watchLineRatiosForSession(int sessionId) {
    return (select(lineRatioProducts)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .watch();
  }

  Future<List<LineRatioProductRow>> getLineRatiosForSession(int sessionId) {
    return (select(lineRatioProducts)
          ..where((tbl) => tbl.sessionId.equals(sessionId))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
  }

  // =========================================================================
  // Standalone (sessionless) queries — for snapshots taken outside sequences
  // =========================================================================

  Stream<List<FramePhotometricCalibrationRow>>
      watchSessionlessCalibrationsRecent({int limit = 50}) {
    return (select(framePhotometricCalibration)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .watch();
  }

  Stream<List<TransparencySampleRow>> watchSessionlessTransparencyRecent(
      {int limit = 50}) {
    return (select(transparencySamples)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .watch();
  }

  Stream<List<PsfFieldTileRow>> watchSessionlessPsfTilesRecent(
      {int limit = 500}) {
    return (select(psfFieldTiles)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ])
          ..limit(limit))
        .watch();
  }

  Stream<List<ScienceFrameQualityMetricsRow>>
      watchSessionlessFrameQualityMetricsRecent({int limit = 50}) {
    return (select(scienceFrameQualityMetrics)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .watch();
  }

  Stream<List<ScienceTileMetricRow>> watchSessionlessTileMetricsRecent(
      {int limit = 500}) {
    return (select(scienceTileMetrics)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.timestamp),
            (tbl) => OrderingTerm.asc(tbl.tileRow),
            (tbl) => OrderingTerm.asc(tbl.tileCol),
          ])
          ..limit(limit))
        .watch();
  }

  Stream<List<AstrometryResidualVectorRow>> watchSessionlessResidualsRecent(
      {int limit = 200}) {
    return (select(astrometryResidualVectors)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .watch();
  }

  Stream<List<MovingObjectCandidateRow>> watchSessionlessMovingObjectsRecent(
      {int limit = 50}) {
    return (select(movingObjectCandidates)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.confidence)])
          ..limit(limit))
        .watch();
  }

  Stream<List<PhotometryMeasurementRow>> watchSessionlessPhotometryRecent(
      {int limit = 200}) {
    return (select(photometryMeasurements)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)])
          ..limit(limit))
        .watch();
  }

  Stream<List<LineRatioProductRow>> watchSessionlessLineRatiosRecent(
      {int limit = 10}) {
    return (select(lineRatioProducts)
          ..where((tbl) => tbl.sessionId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])
          ..limit(limit))
        .watch();
  }

  /// Returns true if any sessionless science data exists (for showing the
  /// standalone tab even when no sequence session is available).
  Future<bool> hasSessionlessScienceData() async {
    final countExp = scienceFrameQualityMetrics.id.count();
    final query = selectOnly(scienceFrameQualityMetrics)
      ..addColumns([countExp])
      ..where(scienceFrameQualityMetrics.sessionId.isNull());
    final result = await query.getSingle();
    return (result.read(countExp) ?? 0) > 0;
  }

  // =========================================================================
  // Photometric Transform Coefficients
  // =========================================================================

  Future<int> insertPhotometricTransform(
      PhotometricTransformsCompanion transform) {
    return into(photometricTransforms).insert(transform);
  }

  Future<void> deletePhotometricTransform(int id) {
    return (delete(photometricTransforms)..where((tbl) => tbl.id.equals(id)))
        .go();
  }

  Stream<List<PhotometricTransformRow>> watchAllTransforms() {
    return (select(photometricTransforms)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.dateComputed)]))
        .watch();
  }

  Future<List<PhotometricTransformRow>> getAllTransforms() {
    return (select(photometricTransforms)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.dateComputed)]))
        .get();
  }

  Future<PhotometricTransformRow?> getTransformForFilter(
    String filterName, {
    int? equipmentProfileId,
  }) {
    final query = select(photometricTransforms)
      ..where((tbl) => tbl.filterName.equals(filterName))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.dateComputed)])
      ..limit(1);
    if (equipmentProfileId != null) {
      query.where(
        (tbl) =>
            tbl.equipmentProfileId.equals(equipmentProfileId) |
            tbl.equipmentProfileId.isNull(),
      );
    }
    return query.getSingleOrNull();
  }

  Stream<List<PhotometricTransformRow>> watchTransformsForProfile(
      int? equipmentProfileId) {
    if (equipmentProfileId == null) {
      return (select(photometricTransforms)
            ..where((tbl) => tbl.equipmentProfileId.isNull())
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.dateComputed)]))
          .watch();
    }
    return (select(photometricTransforms)
          ..where((tbl) =>
              tbl.equipmentProfileId.equals(equipmentProfileId) |
              tbl.equipmentProfileId.isNull())
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.dateComputed)]))
        .watch();
  }
}
