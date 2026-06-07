import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/dark_library_dao.dart';
import 'package:nightshade_core/src/database/daos/flat_library_dao.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/integrated_masters_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/integrated_master.dart';
import 'package:nightshade_core/src/models/imaging/integration_settings.dart';
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
