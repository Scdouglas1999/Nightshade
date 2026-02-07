import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/science_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/science/science_models.dart'
    as science;

void main() {
  late NightshadeDatabase database;
  late ScienceDao dao;

  setUp(() {
    database = NightshadeDatabase.forTesting(NativeDatabase.memory());
    dao = ScienceDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> createSession({String? name}) {
    return database.into(database.imagingSessions).insert(
          ImagingSessionsCompanion.insert(
            name: Value(name),
            startTime: DateTime.now(),
          ),
        );
  }

  test('upserts and watches science session config', () async {
    final sessionId = await createSession(name: 'Config test');
    await dao.upsertSessionConfig(
      science.ScienceSessionConfig(
        sessionId: sessionId,
        photometryEnabled: true,
        transparencyEnabled: false,
        psfGridRows: 5,
        psfGridCols: 7,
      ),
    );

    final row = await dao.watchSessionConfig(sessionId).first;
    expect(row, isNotNull);
    expect(row!.sessionId, sessionId);
    expect(row.photometryEnabled, isTrue);
    expect(row.transparencyEnabled, isFalse);
    expect(row.psfGridRows, 5);
    expect(row.psfGridCols, 7);
  });

  test('stores calibrations and returns recent calibrations', () async {
    final sessionId = await createSession(name: 'Calibration test');
    final now = DateTime.now();
    await dao.insertFrameCalibration(
      FramePhotometricCalibrationCompanion.insert(
        sessionId: Value(sessionId),
        isCalibrated: const Value(true),
        zeroPoint: const Value(20.5),
        limitingMag3Sigma: const Value(18.8),
        limitingMag5Sigma: const Value(18.1),
        matchedStarCount: const Value(123),
        calibrationRms: const Value(0.09),
        catalogSource: const Value('auto'),
        solverId: const Value('ASTAP'),
        timestamp: Value(now),
      ),
    );

    await dao.insertFrameCalibration(
      FramePhotometricCalibrationCompanion.insert(
        sessionId: Value(sessionId),
        isCalibrated: const Value(true),
        zeroPoint: const Value(20.1),
        limitingMag3Sigma: const Value(18.4),
        limitingMag5Sigma: const Value(17.7),
        matchedStarCount: const Value(90),
        calibrationRms: const Value(0.12),
        catalogSource: const Value('auto'),
        solverId: const Value('ASTAP'),
        timestamp: Value(now.add(const Duration(seconds: 1))),
      ),
    );

    final rows = await dao.getRecentCalibrations(sessionId, limit: 2);
    expect(rows, hasLength(2));
    expect(rows.first.zeroPoint, closeTo(20.1, 1e-6));
    expect(rows.last.zeroPoint, closeTo(20.5, 1e-6));
  });

  test('stores photometry and streams sorted light curve', () async {
    final sessionId = await createSession(name: 'Photometry test');
    final t0 = DateTime.now();
    await dao.insertPhotometryMeasurements([
      PhotometryMeasurementsCompanion.insert(
        sessionId: Value(sessionId),
        objectId: 'target_primary',
        role: const Value('target'),
        x: 10,
        y: 10,
        flux: 1200,
        differentialMagnitude: const Value(-0.02),
        snr: const Value(25),
        uncertainty: const Value(0.01),
        timestamp: Value(t0),
      ),
      PhotometryMeasurementsCompanion.insert(
        sessionId: Value(sessionId),
        objectId: 'target_primary',
        role: const Value('target'),
        x: 11,
        y: 10,
        flux: 1180,
        differentialMagnitude: const Value(0.01),
        snr: const Value(24),
        uncertainty: const Value(0.01),
        timestamp: Value(t0.add(const Duration(seconds: 2))),
      ),
    ]);

    final lightCurve =
        await dao.watchLightCurve(sessionId, 'target_primary').first;
    expect(lightCurve, hasLength(2));
    expect(
        lightCurve.first.timestamp.isBefore(lightCurve.last.timestamp), isTrue);
    expect(lightCurve.first.flux, closeTo(1200, 1e-6));
  });

  test('replaces and streams frame quality metrics by image', () async {
    final sessionId = await createSession(name: 'Frame quality test');
    final imageId = await database.into(database.capturedImages).insert(
          CapturedImagesCompanion.insert(
            filePath: 'test_frame.fits',
            fileName: 'test_frame.fits',
            exposureDuration: 120.0,
            capturedAt: DateTime.now(),
            frameType: const Value('light'),
            sessionId: Value(sessionId),
          ),
        );

    await dao.replaceFrameQualityMetricsForImage(
      imageId,
      ScienceFrameQualityMetricsCompanion.insert(
        capturedImageId: Value(imageId),
        sessionId: Value(sessionId),
        timestamp: Value(DateTime.now()),
        median: const Value(500.0),
        mean: const Value(540.0),
        stdDev: const Value(20.0),
        mad: const Value(14.0),
        background: const Value(480.0),
        noise: const Value(19.0),
        snr: const Value(28.0),
        dynamicRangeP1P99: const Value(2200.0),
        lowClipPercent: const Value(0.4),
        highClipPercent: const Value(0.2),
        uniformityCv: const Value(0.08),
        gradientX: const Value(1.4),
        gradientY: const Value(-0.8),
        processingTier: const Value('live'),
        processingMs: const Value(92),
      ),
    );

    final rows = await dao.watchFrameQualityMetricsForSession(sessionId).first;
    expect(rows, hasLength(1));
    expect(rows.first.snr, closeTo(28.0, 1e-6));
    expect(rows.first.processingTier, 'live');
  });

  test('replaces tile metrics by image and streams by session', () async {
    final sessionId = await createSession(name: 'Tile metrics test');
    final imageId = await database.into(database.capturedImages).insert(
          CapturedImagesCompanion.insert(
            filePath: 'test_tiles.fits',
            fileName: 'test_tiles.fits',
            exposureDuration: 180.0,
            capturedAt: DateTime.now(),
            frameType: const Value('light'),
            sessionId: Value(sessionId),
          ),
        );

    await dao.replaceTileMetricsForImage(
      imageId,
      [
        ScienceTileMetricsCompanion.insert(
          capturedImageId: Value(imageId),
          sessionId: Value(sessionId),
          timestamp: Value(DateTime.now()),
          layerType: 'uniformity',
          tileRow: 0,
          tileCol: 0,
          sampleCount: const Value(1024),
          value: const Value(0.11),
          p05: const Value(420),
          p50: const Value(510),
          p95: const Value(640),
          auxValue: const Value(2.4),
        ),
        ScienceTileMetricsCompanion.insert(
          capturedImageId: Value(imageId),
          sessionId: Value(sessionId),
          timestamp: Value(DateTime.now()),
          layerType: 'clip_high',
          tileRow: 0,
          tileCol: 0,
          sampleCount: const Value(1024),
          value: const Value(0.6),
          p05: const Value(0.6),
          p50: const Value(0.6),
          p95: const Value(0.6),
          auxValue: const Value(6),
        ),
      ],
    );

    final rows = await dao.watchTileMetricsForSession(sessionId).first;
    expect(rows.length, 2);
    expect(rows.first.capturedImageId, imageId);
  });
}
