import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/dark_library_dao.dart';
import 'package:nightshade_core/src/database/daos/flat_library_dao.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/integrated_masters_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/color_calibration_result.dart';
import 'package:nightshade_core/src/models/imaging/integrated_master.dart';
import 'package:nightshade_core/src/models/imaging/integration_curve.dart';
import 'package:nightshade_core/src/models/imaging/integration_settings.dart';
import 'package:nightshade_core/src/models/imaging/star_photometry.dart';
import 'package:nightshade_core/src/services/dark_library_service.dart';
import 'package:nightshade_core/src/services/flat_library_service.dart';
import 'package:nightshade_core/src/services/post_session_integration_service.dart';
import 'package:nightshade_core/src/services/post_session_seam.dart';

/// Records the args of every call and returns scriptable results, so the
/// orchestration services run end-to-end without native code.
class FakePostSessionSeam implements PostSessionSeam {
  final List<Map<String, dynamic>> integrateCalls = [];
  final List<Map<String, dynamic>> accumulateCalls = [];
  final List<Map<String, dynamic>> flatCalls = [];

  /// Optional override for the integrate result builder; defaults to echoing
  /// one accepted record per supplied light path.
  IntegrateSessionResult Function(Map<String, dynamic> args)? integrateBuilder;

  /// Scripted accumulate results keyed by op, popped in order.
  final Map<String, List<MasterAccumulateResult>> scriptedAccumulate = {};

  @override
  Future<IntegrateSessionResult> integrateSession(
      Map<String, dynamic> args) async {
    integrateCalls.add(args);
    if (integrateBuilder != null) return integrateBuilder!(args);
    final lights = (args['lightPaths'] as List).cast<String>();
    final output = args['output'] as Map<String, dynamic>;
    return IntegrateSessionResult(
      masterFitsPath: output['masterFitsPath'] as String,
      previewPath: output['previewPngPath'] as String?,
      rejectionMapPath: output['rejectionMapPath'] as String?,
      framesIntegrated: lights.length,
      framesRejected: 0,
      totalIntegrationSec: 0.0,
      rmsResidual: 0.42,
      width: 100,
      height: 80,
      channels: 1,
      perFrameStats: [
        for (final p in lights)
          PerFrameRecord(
            path: p,
            weight: 1.0,
            rmsResidualPx: 0.4,
            accepted: true,
            reason: null,
          ),
      ],
    );
  }

  @override
  Future<MasterAccumulateResult> masterAccumulate(
      Map<String, dynamic> args) async {
    accumulateCalls.add(args);
    final op = args['op'] as String;
    final queue = scriptedAccumulate[op];
    if (queue != null && queue.isNotEmpty) {
      return queue.removeAt(0);
    }
    // Reasonable default echo.
    final added = (args['lightPaths'] as List?)?.length ?? 0;
    return MasterAccumulateResult(
      sidecarPath: args['sidecarPath'] as String? ?? '',
      masterPath: args['masterFitsPath'] as String?,
      previewPath: args['previewPngPath'] as String?,
      frameCount: added,
      totalIntegrationSec: 0.0,
      width: 100,
      height: 80,
      channels: 1,
      framesAdded: added,
      rejected: 0,
    );
  }

  @override
  Future<BuildMasterFlatResult> buildMasterFlat(
      Map<String, dynamic> args) async {
    flatCalls.add(args);
    return BuildMasterFlatResult(
      outputPath: args['outputPath'] as String,
      frameCount: (args['flatPaths'] as List).length,
      inputMean: 30000.0,
      outputMean: 1.0,
      width: 100,
      height: 80,
      channels: 1,
      outputBitDepth: args['outputBitDepth'] as String? ?? 'f32',
    );
  }

  @override
  Future<SaveFitsMasterResult> saveFitsMaster(
      Map<String, dynamic> args) async {
    return SaveFitsMasterResult(
      outputPath: args['outputPath'] as String,
      width: args['width'] as int? ?? 0,
      height: args['height'] as int? ?? 0,
      channels: args['channels'] as int? ?? 1,
      pixelType: args['pixelType'] as String? ?? 'f32',
    );
  }

  // --- Smart Morning Report finishing seam (scriptable) ---------------------

  /// Scripted [analyzeNight] result; defaults to an empty curve.
  IntegrationCurve analyzeResult = IntegrationCurve.empty;

  /// Records every [analyzeNight] invocation's inputs.
  final List<
      ({
        List<Map<String, dynamic>> qualities,
        List<double> weights,
        List<double> exposuresS,
      })> analyzeCalls = [];

  /// Records the args of every optional finishing-step call, keyed by step name.
  final Map<String, List<Map<String, dynamic>>> finishingCalls = {
    'extractBackground': [],
    'reduceStarsPreview': [],
    'deconvolvePreview': [],
    'colorCalibrate': [],
  };

  /// Scripted [detectStarsPhotometry] result; defaults to an empty result.
  StarPhotometryResult photometryResult = StarPhotometryResult.empty;

  /// Scripted [colorCalibrate] result; defaults to an identity calibration that
  /// echoes the requested output path.
  ColorCalibrationResult? colorResult;

  /// Synthetic progress events the fake [integrationProgress] stream replays.
  List<({String phase, double fraction})> progressEvents = const [];

  @override
  Future<IntegrationCurve> analyzeNight({
    required List<Map<String, dynamic>> qualities,
    required List<double> weights,
    required List<double> exposuresS,
    double? aggressiveness,
    int? minKeep,
  }) async {
    analyzeCalls.add((
      qualities: qualities,
      weights: weights,
      exposuresS: exposuresS,
    ));
    return analyzeResult;
  }

  @override
  Future<StarPhotometryResult> detectStarsPhotometry({
    required String inputFits,
    int? maxStars,
    int? aperture,
  }) async =>
      photometryResult;

  @override
  Future<ColorCalibrationResult> colorCalibrate({
    required String inputFits,
    required String outputFits,
    required int channels,
    double? whiteRefBv,
    required List<Map<String, dynamic>> matchedStars,
  }) async {
    finishingCalls['colorCalibrate']!.add(<String, dynamic>{
      'inputFits': inputFits,
      'outputFits': outputFits,
      'channels': channels,
    });
    return colorResult ??
        ColorCalibrationResult(
          outputPath: outputFits,
          channelScale: List<double>.filled(channels, 1.0),
          matched: matchedStars.length,
          residual: 0.0,
        );
  }

  @override
  Future<String> extractBackground(Map<String, dynamic> args) async {
    finishingCalls['extractBackground']!.add(args);
    return args['outputFits'] as String? ?? args['outputPath'] as String? ?? '';
  }

  @override
  Future<String> deconvolvePreview(Map<String, dynamic> args) async {
    finishingCalls['deconvolvePreview']!.add(args);
    return args['outputFits'] as String? ?? args['outputPath'] as String? ?? '';
  }

  @override
  Future<String> reduceStarsPreview(Map<String, dynamic> args) async {
    finishingCalls['reduceStarsPreview']!.add(args);
    return args['outputFits'] as String? ?? args['outputPath'] as String? ?? '';
  }

  @override
  Future<Map<String, dynamic>> drizzleIntegrate(
          Map<String, dynamic> args) async =>
      {'outputPath': args['outputFits'] as String? ?? ''};

  @override
  Future<String> combineChannels(Map<String, dynamic> args) async =>
      args['outputFits'] as String? ?? args['outputPath'] as String? ?? '';

  @override
  Stream<({String phase, double fraction})> integrationProgress() =>
      Stream.fromIterable(progressEvents);
}

void main() {
  late NightshadeDatabase db;
  late ImagesDao imagesDao;
  late IntegratedMastersDao mastersDao;
  late FlatLibraryDao flatDao;
  late DarkLibraryService darkLibrary;
  late FlatLibraryService flatLibrary;
  late FakePostSessionSeam seam;
  late PostSessionIntegrationService service;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    imagesDao = db.imagesDao;
    mastersDao = IntegratedMastersDao(db);
    flatDao = FlatLibraryDao(db);
    darkLibrary = DarkLibraryService(DarkLibraryDao(db));
    seam = FakePostSessionSeam();
    flatLibrary = FlatLibraryService(dao: flatDao, seam: seam);
    service = PostSessionIntegrationService(
      mastersDao: mastersDao,
      darkLibrary: darkLibrary,
      flatLibrary: flatLibrary,
      seam: seam,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<CapturedImage> insertSub({
    required String path,
    String? filter,
    double quality = 80.0,
    double hfr = 2.0,
    int gain = 100,
    DateTime? capturedAt,
  }) async {
    final id = await db.into(db.capturedImages).insert(
          CapturedImagesCompanion.insert(
            filePath: path,
            fileName: path.split('/').last,
            frameType: const Value('light'),
            exposureDuration: 120.0,
            capturedAt: capturedAt ?? DateTime(2026, 6, 7, 22),
            gain: Value(gain),
            offset: const Value(10),
            binX: const Value(1),
            binY: const Value(1),
            filter: Value(filter),
            sensorTemp: const Value(-10.0),
            hfr: Value(hfr),
            qualityScore: Value(quality),
            isAccepted: const Value(true),
          ),
        );
    return (await imagesDao.getImageById(id))!;
  }

  test('integrate persists a finalized master + fold records per sub', () async {
    final subs = [
      await insertSub(path: '/lights/a.fits', filter: 'L', quality: 90),
      await insertSub(path: '/lights/b.fits', filter: 'L', quality: 70),
      await insertSub(path: '/lights/c.fits', filter: 'L', quality: 60),
    ];

    final outcomes = await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      targetId: null,
      targetName: 'M51',
      outputFitsPathBuilder: (bucket) => '/out/master_$bucket.fits',
    );

    expect(outcomes, hasLength(1));
    final outcome = outcomes.single;
    expect(outcome.filter, 'L');
    expect(outcome.result.framesIntegrated, 3);

    // The seam received one integrate call with the right shape.
    expect(seam.integrateCalls, hasLength(1));
    final args = seam.integrateCalls.single;
    expect((args['lightPaths'] as List).cast<String>(),
        containsAll(['/lights/a.fits', '/lights/b.fits', '/lights/c.fits']));
    // Highest-quality sub (a, q=90) becomes the explicit reference.
    expect(args['reference'], '/lights/a.fits');
    expect((args['settings'] as Map).containsKey('align'), isTrue);

    // Master row persisted, finalized, batch mode.
    final master = await mastersDao.getById(outcome.masterId);
    expect(master, isNotNull);
    expect(master!.status, IntegratedMasterStatus.finalized);
    expect(master.accumulationMode, AccumulationMode.batch);
    expect(master.filter, 'L');
    expect(master.frameCount, 3);
    expect(master.name, 'M51 · L');
    expect(master.masterFitsPath, '/out/master_L.fits');

    // One fold record per sub.
    final folded = await mastersDao.getFoldedImageIds(outcome.masterId);
    expect(folded, subs.map((s) => s.id).toSet());
  });

  test('integrate makes one master per filter group', () async {
    final subs = [
      await insertSub(path: '/l/a.fits', filter: 'Ha'),
      await insertSub(path: '/l/b.fits', filter: 'OIII'),
      await insertSub(path: '/l/c.fits', filter: 'Ha'),
    ];

    final outcomes = await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      outputFitsPathBuilder: (bucket) => '/out/$bucket.fits',
    );

    final byFilter = {for (final o in outcomes) o.filter: o};
    expect(byFilter.keys.toSet(), {'Ha', 'OIII'});
    expect(byFilter['Ha']!.result.framesIntegrated, 2);
    expect(byFilter['OIII']!.result.framesIntegrated, 1);
    expect(seam.integrateCalls, hasLength(2));
  });

  test('resolved calibration feeds matched dark + flat paths to the seam',
      () async {
    // Register a matching master dark and master flat.
    await darkLibrary.createMasterDarkEntryForTest(db);
    await flatDao.addEntry(
      filePath: '/cal/master_flat_L.fits',
      filter: 'L',
      gain: 100,
      offset: 10,
      binX: 1,
      binY: 1,
      temperature: -10.0,
    );

    final subs = [await insertSub(path: '/l/a.fits', filter: 'L')];
    await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      outputFitsPathBuilder: (bucket) => '/out/$bucket.fits',
    );

    final calibration =
        seam.integrateCalls.single['calibration'] as Map<String, dynamic>;
    expect(calibration['flat'], '/cal/master_flat_L.fits');
    expect(calibration['dark'], '/cal/master_dark.fits');
    expect(calibration['cosmeticCorrection'], isTrue);
  });

  test('empty subs is a hard error, not a silent no-op', () async {
    expect(
      () => service.integrate(
        subs: const [],
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (_) => '/out/x.fits',
      ),
      throwsArgumentError,
    );
  });

  test('rejection map / preview paths are derived from the master path',
      () async {
    final subs = [await insertSub(path: '/l/a.fits', filter: 'L')];
    await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      outputFitsPathBuilder: (_) => '/out/master.fits',
    );
    final output =
        seam.integrateCalls.single['output'] as Map<String, dynamic>;
    expect(output['masterFitsPath'], '/out/master.fits');
    expect(output['previewPngPath'], '/out/master.png');
    expect(output['rejectionMapPath'], '/out/master_rejmap.fits');
  });

  // --- Smart Morning Report extensions --------------------------------------

  /// An integrate builder that echoes the lights and stamps each accepted
  /// per-frame record with synthetic per-sub science metrics.
  void scriptMetrics() {
    seam.integrateBuilder = (args) {
      final lights = (args['lightPaths'] as List).cast<String>();
      final output = args['output'] as Map<String, dynamic>;
      return IntegrateSessionResult(
        masterFitsPath: output['masterFitsPath'] as String,
        previewPath: output['previewPngPath'] as String?,
        rejectionMapPath: output['rejectionMapPath'] as String?,
        framesIntegrated: lights.length,
        framesRejected: 0,
        totalIntegrationSec: 120.0 * lights.length,
        rmsResidual: 0.42,
        width: 100,
        height: 80,
        channels: 1,
        perFrameStats: [
          for (var i = 0; i < lights.length; i++)
            PerFrameRecord(
              path: lights[i],
              weight: 1.0,
              rmsResidualPx: 0.4,
              accepted: true,
              reason: null,
              snr: 40.0 + i,
              fwhm: 2.5 + i * 0.1,
              eccentricity: 0.3,
            ),
        ],
      );
    };
  }

  test('per-sub snr/fwhm/eccentricity are persisted on the fold records',
      () async {
    scriptMetrics();
    final subs = [
      await insertSub(path: '/l/a.fits', filter: 'L'),
      await insertSub(path: '/l/b.fits', filter: 'L'),
    ];

    final outcomes = await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      outputFitsPathBuilder: (_) => '/out/master.fits',
    );
    final masterId = outcomes.single.masterId;

    // Read the v42 per-sub columns straight from integrated_master_frames.
    final rows = await db.customSelect(
      'SELECT image_id, snr, fwhm, eccentricity FROM integrated_master_frames '
      'WHERE master_id = ? ORDER BY image_id ASC',
      variables: [Variable<int>(masterId)],
    ).get();
    expect(rows, hasLength(2));
    final byImage = {
      for (final r in rows)
        r.read<int>('image_id'): (
          snr: r.readNullable<double>('snr'),
          fwhm: r.readNullable<double>('fwhm'),
          ecc: r.readNullable<double>('eccentricity'),
        )
    };
    expect(byImage[subs[0].id]!.snr, 40.0);
    expect(byImage[subs[0].id]!.fwhm, 2.5);
    expect(byImage[subs[0].id]!.ecc, 0.3);
    expect(byImage[subs[1].id]!.snr, 41.0);
  });

  test(
      'analyzeNight is invoked and improvement_curve_json + target fields stored',
      () async {
    scriptMetrics();
    seam.analyzeResult = const IntegrationCurve(
      points: [
        IntegrationCurvePoint(
            n: 1, snr: 40.0, fwhm: 2.5, cumulativeIntegrationS: 120.0),
        IntegrationCurvePoint(
            n: 2, snr: 56.0, fwhm: 2.55, cumulativeIntegrationS: 240.0),
      ],
      recommendation: SubsetRecommendation(
        keepN: 2,
        keptIndices: [0, 1],
        predictedSnrGainPct: 0.0,
        reason: 'keep all',
      ),
    );

    final subs = [
      await insertSub(path: '/l/a.fits', filter: 'L'),
      await insertSub(path: '/l/b.fits', filter: 'L'),
    ];
    final outcomes = await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults,
      outputFitsPathBuilder: (_) => '/out/master.fits',
    );
    final masterId = outcomes.single.masterId;

    // analyzeNight saw one call carrying the per-sub qualities + weights.
    expect(seam.analyzeCalls, hasLength(1));
    final call = seam.analyzeCalls.single;
    expect(call.qualities, hasLength(2));
    expect(call.qualities.first['snr'], 40.0);
    expect(call.weights, [1.0, 1.0]);

    // The curve + full-night anchor landed in the v42 smart columns.
    final row = (await db.customSelect(
      'SELECT improvement_curve_json, target_snr, target_integration_s '
      'FROM integrated_masters WHERE id = ?',
      variables: [Variable<int>(masterId)],
    ).get())
        .single;
    final curveJson = row.read<String>('improvement_curve_json');
    final decoded =
        IntegrationCurve.fromJson(jsonDecode(curveJson) as Map<String, dynamic>);
    expect(decoded.points, hasLength(2));
    expect(decoded.recommendation.keepN, 2);
    // target_snr / target_integration_s anchor to the full-night curve point.
    expect(row.read<double>('target_snr'), 56.0);
    expect(row.read<double>('target_integration_s'), 240.0);
  });

  test('optional finishing steps are gated by the settings knobs', () async {
    scriptMetrics();
    final subs = [await insertSub(path: '/l/a.fits', filter: 'L')];

    // All optional knobs OFF: no finishing call fires.
    await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults.copyWith(
        extractBackground: false,
        colorCalibrate: false,
        reduceStars: false,
        deconvolve: false,
      ),
      outputFitsPathBuilder: (_) => '/out/off.fits',
    );
    expect(seam.finishingCalls['extractBackground'], isEmpty);
    expect(seam.finishingCalls['reduceStarsPreview'], isEmpty);
    expect(seam.finishingCalls['deconvolvePreview'], isEmpty);

    // Knobs ON: background + star-reduction + deconvolution each fire once
    // against the master FITS. Colour calibration stays skipped (no
    // ColorCalibrationService wired), so its seam method is never called.
    final outcomes = await service.integrate(
      subs: subs,
      settings: IntegrationSettings.defaults.copyWith(
        extractBackground: true,
        colorCalibrate: true,
        reduceStars: true,
        deconvolve: true,
      ),
      outputFitsPathBuilder: (_) => '/out/on.fits',
    );
    expect(seam.finishingCalls['extractBackground'], hasLength(1));
    expect(seam.finishingCalls['extractBackground']!.single['inputFits'],
        '/out/on.fits');
    expect(seam.finishingCalls['reduceStarsPreview'], hasLength(1));
    expect(seam.finishingCalls['deconvolvePreview'], hasLength(1));
    expect(seam.finishingCalls['colorCalibrate'], isEmpty);

    // background_extracted flips to 1 once extraction ran.
    final bgx = (await db.customSelect(
      'SELECT background_extracted FROM integrated_masters WHERE id = ?',
      variables: [Variable<int>(outcomes.single.masterId)],
    ).get())
        .single;
    expect(bgx.read<int>('background_extracted'), 1);
  });
}

/// Test-only helper to seed a matching master-dark library entry.
extension on DarkLibraryService {
  Future<void> createMasterDarkEntryForTest(NightshadeDatabase db) async {
    await DarkLibraryDao(db).addEntry(
      DarkLibraryCompanion.insert(
        filePath: '/cal/master_dark.fits',
        exposureTime: 120.0,
        frameType: const Value('dark'),
        temperature: const Value(-10.0),
        gain: const Value(100),
        offset: const Value(10),
        binX: const Value(1),
        binY: const Value(1),
        masterDarkPath: const Value('/cal/master_dark.fits'),
        masterFrameCount: const Value(20),
      ),
    );
  }
}
