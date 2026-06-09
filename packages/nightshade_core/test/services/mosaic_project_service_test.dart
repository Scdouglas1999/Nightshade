// End-to-end guard for the Mosaic M2 [MosaicProjectService] — the durable spine
// that plans a mosaic into per-panel rows, integrates each panel's subs into a
// per-panel master, and stitches those masters into one mosaic master.
//
// Everything runs on an in-memory DB with the REAL v45 DAOs + the real
// [PostSessionIntegrationService], and a Fake [PostSessionSeam] standing in for
// the native FFI (integrate echoes a master per filter group; stitchMosaic
// records its request and echoes a canvas). This pins the three contracts the
// service owns:
//
//   * createProject persists the project + the right per-panel centers + count,
//     reusing MosaicService.generatePanels for the geometry (NOT re-derived).
//   * integratePanels links each panel's per-panel master and is fail-soft
//     per panel (a panel with no subs is left pending, the rest still link).
//   * stitchProject calls stitchMosaic with ALL panel master paths, persists the
//     stitched master as a new integrated_masters row, and links it onto the
//     project's output_master_id (status -> complete).

import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/dark_library_dao.dart';
import 'package:nightshade_core/src/database/daos/flat_library_dao.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/integrated_masters_dao.dart';
import 'package:nightshade_core/src/database/daos/mosaic_panels_dao.dart';
import 'package:nightshade_core/src/database/daos/mosaic_projects_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/integration_settings.dart';
import 'package:nightshade_core/src/models/imaging/mosaic_project.dart';
import 'package:nightshade_core/src/models/imaging/mosaic_stitch_result.dart';
import 'package:nightshade_core/src/services/dark_library_service.dart';
import 'package:nightshade_core/src/services/flat_library_service.dart';
import 'package:nightshade_core/src/services/mosaic_project_service.dart';
import 'package:nightshade_core/src/services/post_session_integration_service.dart';
import 'package:nightshade_core/src/services/post_session_seam.dart';

/// A scriptable [PostSessionSeam]: `integrateSession` echoes one accepted record
/// per light path (and stamps the master's solved WCS via the injected plate
/// solver path is N/A here — WCS is set straight onto the master row in the
/// stitch test), and `stitchMosaic` records its request + echoes a canvas. Only
/// the members the orchestration exercises are implemented.
class _FakeSeam implements PostSessionSeam {
  final List<Map<String, dynamic>> integrateCalls = [];
  final List<Map<String, dynamic>> stitchCalls = [];

  /// Optional scripted stitch result; when null the fake echoes the request.
  MosaicStitchResult? stitchResult;

  @override
  Future<IntegrateSessionResult> integrateSession(
      Map<String, dynamic> args) async {
    integrateCalls.add(args);
    final lights = (args['lightPaths'] as List).cast<String>();
    final output = args['output'] as Map<String, dynamic>;
    return IntegrateSessionResult(
      masterFitsPath: output['masterFitsPath'] as String,
      previewPath: output['previewPngPath'] as String?,
      rejectionMapPath: output['rejectionMapPath'] as String?,
      framesIntegrated: lights.length,
      framesRejected: 0,
      totalIntegrationSec: 120.0 * lights.length,
      rmsResidual: 0.4,
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
  Future<MosaicStitchResult> stitchMosaic(Map<String, dynamic> args) async {
    stitchCalls.add(args);
    if (stitchResult != null) return stitchResult!;
    final output = (args['output'] as Map).cast<String, dynamic>();
    final panels = (args['panels'] as List).length;
    return MosaicStitchResult(
      outputPath: output['mosaicFitsPath'] as String,
      coveragePath: output['coverageFitsPath'] as String?,
      previewPath: output['previewPngPath'] as String?,
      outWidth: 100 * panels,
      outHeight: 80,
      overlapPairs: panels - 1,
      meanPanelGain: 1.0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  late NightshadeDatabase db;
  late ImagesDao imagesDao;
  late IntegratedMastersDao mastersDao;
  late MosaicProjectsDao projectsDao;
  late MosaicPanelsDao panelsDao;
  late _FakeSeam seam;
  late PostSessionIntegrationService integration;
  late MosaicProjectService service;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    imagesDao = db.imagesDao;
    mastersDao = IntegratedMastersDao(db);
    projectsDao = MosaicProjectsDao(db);
    panelsDao = MosaicPanelsDao(db);
    seam = _FakeSeam();
    integration = PostSessionIntegrationService(
      mastersDao: mastersDao,
      darkLibrary: DarkLibraryService(DarkLibraryDao(db)),
      flatLibrary: FlatLibraryService(dao: FlatLibraryDao(db), seam: seam),
      seam: seam,
    );
    service = MosaicProjectService(
      projectsDao: projectsDao,
      panelsDao: panelsDao,
      imagesDao: imagesDao,
      mastersDao: mastersDao,
      integrationService: integration,
      seam: seam,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedTarget(String name) {
    return db.customInsert(
      'INSERT INTO targets (name, ra, dec) VALUES (?, ?, ?)',
      variables: [
        Variable<String>(name),
        const Variable<double>(0.7),
        const Variable<double>(41.0),
      ],
    );
  }

  Future<void> seedSub({
    required int targetId,
    required String path,
    bool accepted = true,
    String filter = 'L',
  }) async {
    await db.into(db.capturedImages).insert(
          CapturedImagesCompanion.insert(
            filePath: path,
            fileName: path.split('/').last,
            frameType: const Value('light'),
            exposureDuration: 120.0,
            capturedAt: DateTime(2026, 6, 7, 22),
            targetId: Value(targetId),
            gain: const Value(100),
            offset: const Value(10),
            binX: const Value(1),
            binY: const Value(1),
            filter: Value(filter),
            sensorTemp: const Value(-10.0),
            hfr: const Value(2.0),
            qualityScore: const Value(80.0),
            isAccepted: Value(accepted),
          ),
        );
  }

  group('createProject', () {
    test('persists the project + per-panel rows with generated centers',
        () async {
      final regionTarget = await seedTarget('Andromeda');
      final projectId = await service.createProject(
        name: 'M31 2x3',
        rows: 2,
        cols: 3,
        centerRa: 0.7,
        centerDec: 41.0,
        targetId: regionTarget,
        overlapPct: 20.0,
        positionAngleDeg: 0.0,
        // 1 deg x 0.75 deg rig FOV.
        fovWidthDeg: 1.0,
        fovHeightDeg: 0.75,
      );

      final project = await projectsDao.getById(projectId);
      expect(project, isNotNull);
      expect(project!.name, 'M31 2x3');
      expect(project.rows, 2);
      expect(project.cols, 3);
      expect(project.totalPanels, 6);
      expect(project.overlapPct, closeTo(20.0, 1e-9));
      expect(project.targetId, regionTarget);
      expect(project.status, MosaicProjectStatus.planning);

      final panels = await panelsDao.getForProject(projectId);
      expect(panels, hasLength(6));
      // 0-based, row-major, contiguous.
      expect(panels.map((p) => p.panelIndex).toList(), [0, 1, 2, 3, 4, 5]);
      // Panels inherit the project target by default (so campaigns/goals attach).
      expect(panels.every((p) => p.targetId == regionTarget), isTrue);
      // All pending, zero captured at creation.
      expect(panels.every((p) => p.status == MosaicPanelStatus.pending), isTrue);
      expect(panels.every((p) => p.capturedCount == 0), isTrue);

      // The centers are the EXISTING geometry's output (cos(dec) RA compression
      // spreads RA more than the bare FOV at dec=41). The grid is symmetric
      // about the project center, so the row-0 cols straddle 0.7h and the dec
      // band splits +/- around 41.0.
      final byIndex = {for (final p in panels) p.panelIndex: p};
      // Middle column of each row sits on the center RA.
      expect(byIndex[1]!.centerRa, closeTo(0.7, 1e-6));
      expect(byIndex[4]!.centerRa, closeTo(0.7, 1e-6));
      // Two rows split symmetrically in dec about 41.0.
      expect(byIndex[1]!.centerDec + byIndex[4]!.centerDec,
          closeTo(2 * 41.0, 1e-6));
      // Columns within a row are ordered low->high RA and distinct.
      expect(byIndex[0]!.centerRa, lessThan(byIndex[1]!.centerRa));
      expect(byIndex[1]!.centerRa, lessThan(byIndex[2]!.centerRa));
    });

    test('derives panel arcmin from explicit dims and rejects a bad grid',
        () async {
      final id = await service.createProject(
        name: 'tiny',
        rows: 1,
        cols: 2,
        centerRa: 12.0,
        centerDec: 0.0,
        panelWidthArcmin: 30.0,
        panelHeightArcmin: 20.0,
      );
      expect(await panelsDao.getForProject(id), hasLength(2));

      await expectLater(
        service.createProject(
          name: 'bad',
          rows: 0,
          cols: 2,
          centerRa: 1,
          centerDec: 1,
          panelWidthArcmin: 30,
          panelHeightArcmin: 20,
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.createProject(
          name: 'no-dims',
          rows: 1,
          cols: 2,
          centerRa: 1,
          centerDec: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('integratePanels', () {
    test('links a per-panel master for each panel that has accepted subs',
        () async {
      // Two panel targets, each with their own subs.
      final p0Target = await seedTarget('Mosaic Panel 1');
      final p1Target = await seedTarget('Mosaic Panel 2');
      await seedSub(targetId: p0Target, path: '/p0/a.fits');
      await seedSub(targetId: p0Target, path: '/p0/b.fits');
      await seedSub(targetId: p1Target, path: '/p1/a.fits');
      // A rejected sub on panel 1 must not be folded.
      await seedSub(targetId: p1Target, path: '/p1/reject.fits', accepted: false);

      final projectId = await service.createProject(
        name: 'Pair',
        rows: 1,
        cols: 2,
        centerRa: 0.7,
        centerDec: 41.0,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        // Give each panel its own capture target.
        panelTargetId: (i) => i == 0 ? p0Target : p1Target,
      );

      final outcomes = await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      expect(outcomes, hasLength(2));
      expect(outcomes.every((o) => o.integrated), isTrue);
      // Panel 0 folded its two accepted subs; panel 1 folded one (reject skipped).
      expect(outcomes[0].subCount, 2);
      expect(outcomes[1].subCount, 1);

      // Two integrate calls (one per panel), each with that panel's subs + the
      // panel's own output path.
      expect(seam.integrateCalls, hasLength(2));
      expect(
          (seam.integrateCalls[0]['lightPaths'] as List).cast<String>(),
          containsAll(['/p0/a.fits', '/p0/b.fits']));
      expect(
          (seam.integrateCalls[1]['lightPaths'] as List).cast<String>(),
          ['/p1/a.fits']);

      // Each panel row now carries its per-panel master + integrated status.
      final panels = await panelsDao.getForProject(projectId);
      expect(panels.every((p) => p.integratedMasterId != null), isTrue);
      expect(
          panels.every((p) => p.status == MosaicPanelStatus.integrated), isTrue);
      // The master rows exist and point at the right FITS. Subs are filter 'L',
      // so the per-filter master gets the bucket-suffixed path (the bug was
      // every per-filter master sharing the bare base path and clobbering each
      // other on disk).
      final m0 = await mastersDao.getById(panels[0].integratedMasterId!);
      expect(m0!.masterFitsPath, '/out/panel_0_L.fits');

      // The project moved into the integrating phase.
      final project = await projectsDao.getById(projectId);
      expect(project!.status, MosaicProjectStatus.integrating);
    });

    test('is fail-soft per panel: a panel with no subs stays pending', () async {
      final p0Target = await seedTarget('Has Subs');
      final p1Target = await seedTarget('No Subs');
      await seedSub(targetId: p0Target, path: '/p0/a.fits');

      final projectId = await service.createProject(
        name: 'Half',
        rows: 1,
        cols: 2,
        centerRa: 0.7,
        centerDec: 41.0,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (i) => i == 0 ? p0Target : p1Target,
      );

      final outcomes = await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      // Panel 0 integrated; panel 1 (no subs) is left pending, not failed, and
      // did not abort the run.
      expect(outcomes[0].integrated, isTrue);
      expect(outcomes[0].status, MosaicPanelStatus.integrated);
      expect(outcomes[1].integrated, isFalse);
      expect(outcomes[1].status, MosaicPanelStatus.pending);
      // Only one integrate call was issued (the empty panel was skipped).
      expect(seam.integrateCalls, hasLength(1));

      final panels = await panelsDao.getForProject(projectId);
      expect(panels[0].integratedMasterId, isNotNull);
      expect(panels[1].integratedMasterId, isNull);
    });

    test(
        'a multi-filter panel writes one distinct master FITS per filter '
        '(no on-disk clobber) and links luminance as the representative',
        () async {
      // One panel captured in L + R + G + B. The bug: every per-filter master
      // was handed the SAME base path, so each filter overwrote the previous
      // filter's FITS/PNG/rejmap on disk, and the panel linked outcomes.first
      // (iteration order), not a meaningful representative.
      final panelTarget = await seedTarget('LRGB Panel');
      // Give R two subs so it is the highest-frame-count group — proving the
      // representative pick is NOT "most frames" when luminance is present.
      await seedSub(targetId: panelTarget, path: '/lrgb/r1.fits', filter: 'R');
      await seedSub(targetId: panelTarget, path: '/lrgb/r2.fits', filter: 'R');
      await seedSub(targetId: panelTarget, path: '/lrgb/g1.fits', filter: 'G');
      await seedSub(targetId: panelTarget, path: '/lrgb/b1.fits', filter: 'B');
      await seedSub(targetId: panelTarget, path: '/lrgb/l1.fits', filter: 'L');

      final projectId = await service.createProject(
        name: 'LRGB',
        rows: 1,
        cols: 1,
        centerRa: 0.7,
        centerDec: 41.0,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (_) => panelTarget,
      );

      final outcomes = await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      // One panel outcome; it folded ALL five accepted subs across filters.
      expect(outcomes, hasLength(1));
      expect(outcomes.single.subCount, 5);
      expect(outcomes.single.status, MosaicPanelStatus.integrated);

      // Four integrate calls (one per filter), each writing a DISTINCT master
      // FITS path so no filter clobbers another's pixels on disk. The
      // luminance group keeps deriving its preview/rejmap from its own base.
      expect(seam.integrateCalls, hasLength(4));
      final masterPaths = seam.integrateCalls
          .map((c) => (c['output'] as Map)['masterFitsPath'] as String)
          .toList();
      expect(masterPaths.toSet(), hasLength(4),
          reason: 'each per-filter master must get a distinct FITS path');
      expect(
        masterPaths.toSet(),
        {
          '/out/panel_0_R.fits',
          '/out/panel_0_G.fits',
          '/out/panel_0_B.fits',
          '/out/panel_0_L.fits',
        },
      );

      // The persisted master rows are also distinct files (no duplicate rows
      // all pointing at one path), one per filter.
      final allMasters = await mastersDao.getAll();
      final lrgbMasters = allMasters
          .where((m) => m.masterFitsPath?.startsWith('/out/panel_0') ?? false)
          .toList();
      expect(lrgbMasters, hasLength(4));
      expect(
        lrgbMasters.map((m) => m.masterFitsPath).toSet(),
        hasLength(4),
        reason: 'four filters must yield four on-disk FITS, not one clobbered',
      );

      // The panel links the LUMINANCE master as its representative — even
      // though R has the most frames and L was not the first filter group.
      final panels = await panelsDao.getForProject(projectId);
      final linked = await mastersDao.getById(panels.single.integratedMasterId!);
      expect(linked!.masterFitsPath, '/out/panel_0_L.fits');
      expect(linked.filter, 'L');
    });

    test(
        'a multi-filter panel with no luminance links the highest-frame-count '
        'master as the representative', () async {
      // R(3) + G(1) + B(1), no L. The representative must be the deepest group
      // (R), not whichever filter happened to be the first sub captured.
      final panelTarget = await seedTarget('RGB Panel');
      await seedSub(targetId: panelTarget, path: '/rgb/g1.fits', filter: 'G');
      await seedSub(targetId: panelTarget, path: '/rgb/b1.fits', filter: 'B');
      await seedSub(targetId: panelTarget, path: '/rgb/r1.fits', filter: 'R');
      await seedSub(targetId: panelTarget, path: '/rgb/r2.fits', filter: 'R');
      await seedSub(targetId: panelTarget, path: '/rgb/r3.fits', filter: 'R');

      final projectId = await service.createProject(
        name: 'RGB',
        rows: 1,
        cols: 1,
        centerRa: 0.7,
        centerDec: 41.0,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (_) => panelTarget,
      );

      await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      final panels = await panelsDao.getForProject(projectId);
      final linked = await mastersDao.getById(panels.single.integratedMasterId!);
      // R has 3 frames vs 1 each for G/B, so R is the representative.
      expect(linked!.filter, 'R');
      expect(linked.masterFitsPath, '/out/panel_0_R.fits');
    });

    test(
        'an unfiltered panel keeps the bare base FITS path (no bucket suffix)',
        () async {
      // Subs captured WITHOUT a filter recorded fall in the noFilterBucket and
      // must keep the bare base path — there is nothing to disambiguate, and a
      // `_(none)` suffix would be ugly noise. (A NAMED single filter like 'L'
      // is still suffixed; that is covered by the LRGB/RGB tests above.)
      final panelTarget = await seedTarget('Mono Panel');
      await seedSub(targetId: panelTarget, path: '/mono/a.fits', filter: '');
      await seedSub(targetId: panelTarget, path: '/mono/b.fits', filter: '');

      final projectId = await service.createProject(
        name: 'Mono',
        rows: 1,
        cols: 1,
        centerRa: 0.7,
        centerDec: 41.0,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (_) => panelTarget,
      );

      await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      expect(seam.integrateCalls, hasLength(1));
      expect(
        (seam.integrateCalls.single['output'] as Map)['masterFitsPath'],
        '/out/panel_0.fits',
      );
      final panels = await panelsDao.getForProject(projectId);
      final linked = await mastersDao.getById(panels.single.integratedMasterId!);
      expect(linked!.masterFitsPath, '/out/panel_0.fits');
    });
  });

  group('stitchProject', () {
    /// Build a 1x2 project, integrate both panels, then return the project id.
    Future<int> integratedPair() async {
      final p0Target = await seedTarget('Stitch Panel 1');
      final p1Target = await seedTarget('Stitch Panel 2');
      await seedSub(targetId: p0Target, path: '/p0/a.fits');
      await seedSub(targetId: p1Target, path: '/p1/a.fits');

      final projectId = await service.createProject(
        name: 'Veil 1x2',
        rows: 1,
        cols: 2,
        centerRa: 20.85,
        centerDec: 30.7,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (i) => i == 0 ? p0Target : p1Target,
      );
      await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );
      return projectId;
    }

    test('stitches all panel masters and persists + links the mosaic master',
        () async {
      final projectId = await integratedPair();

      final outcome = await service.stitchProject(
        projectId,
        outputDirectory: '/projects/veil',
        stitchConfig: const {'normalize': true, 'blend': 'feather'},
      );

      // The seam received ONE stitch call carrying BOTH panel FITS paths.
      expect(seam.stitchCalls, hasLength(1));
      final call = seam.stitchCalls.single;
      final panelPaths = (call['panels'] as List)
          .map((p) => (p as Map)['fitsPath'] as String)
          .toList();
      // Panels were captured in 'L', so their representative masters carry the
      // bucket-suffixed FITS paths.
      expect(panelPaths,
          containsAll(['/out/panel_0_L.fits', '/out/panel_1_L.fits']));
      expect(call['config'], {'normalize': true, 'blend': 'feather'});
      // Output paths land under the project folder, slugged from the name.
      final output = call['output'] as Map;
      expect(output['mosaicFitsPath'], '/projects/veil/Veil_1x2_mosaic.fits');
      expect(output['coverageFitsPath'],
          '/projects/veil/Veil_1x2_mosaic_coverage.fits');
      expect(output['previewPngPath'], '/projects/veil/Veil_1x2_mosaic.png');

      // The stitched master is a NEW integrated_masters row, finalized/batch.
      expect(outcome.panelCount, 2);
      final master = await mastersDao.getById(outcome.outputMasterId);
      expect(master, isNotNull);
      expect(master!.name, 'Veil 1x2 · Mosaic');
      expect(master.masterFitsPath, '/projects/veil/Veil_1x2_mosaic.fits');
      expect(master.previewPngPath, '/projects/veil/Veil_1x2_mosaic.png');
      // Canvas geometry came from the stitch result (100 * 2 panels wide).
      expect(master.width, 200);
      expect(master.height, 80);
      final stats = jsonDecode(master.statsJson) as Map<String, dynamic>;
      expect(stats['panelCount'], 2);
      expect(stats['overlapPairs'], 1);

      // The project is complete and linked to the mosaic master.
      final project = await projectsDao.getById(projectId);
      expect(project!.status, MosaicProjectStatus.complete);
      expect(project.outputMasterId, outcome.outputMasterId);
      expect(project.isComplete, isTrue);
    });

    test('passes each panel master\'s persisted WCS into the stitch request',
        () async {
      final projectId = await integratedPair();
      // Stamp a WCS onto each panel's master (the v44 columns the per-panel
      // integration would have plate-solved).
      final panels = await panelsDao.getForProject(projectId);
      await mastersDao.updateWcs(
        panels[0].integratedMasterId!,
        crval1: 312.0,
        crval2: 30.7,
        crpix1: 50,
        crpix2: 40,
        cd1_1: -0.0011,
        cd1_2: 0.0,
        cd2_1: 0.0,
        cd2_2: 0.0011,
      );
      // Leave panel 1 without a WCS (the native side reads its FITS header).

      await service.stitchProject(projectId, outputDirectory: '/p/veil');

      final call = seam.stitchCalls.single;
      final p0 = (call['panels'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .firstWhere((p) => p['fitsPath'] == '/out/panel_0_L.fits');
      final p1 = (call['panels'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .firstWhere((p) => p['fitsPath'] == '/out/panel_1_L.fits');
      expect(p0['wcs'], isNotNull);
      expect((p0['wcs'] as Map)['cd1_1'], -0.0011);
      expect((p0['wcs'] as Map)['crval1'], 312.0);
      // No persisted WCS -> no wcs block (native parses the header).
      expect(p1.containsKey('wcs'), isFalse);
    });

    test('requires >= 2 panels with masters else a clear error', () async {
      // Build a project but integrate only one panel (the other has no subs).
      final p0Target = await seedTarget('Only One');
      await seedSub(targetId: p0Target, path: '/p0/a.fits');
      final projectId = await service.createProject(
        name: 'Lonely',
        rows: 1,
        cols: 2,
        centerRa: 1,
        centerDec: 1,
        panelWidthArcmin: 30,
        panelHeightArcmin: 20,
        panelTargetId: (i) => i == 0 ? p0Target : null,
      );
      await service.integratePanels(
        projectId,
        settings: IntegrationSettings.defaults,
        outputFitsPathBuilder: (panel) =>
            '/out/panel_${panel.panelIndex}.fits',
      );

      await expectLater(
        service.stitchProject(projectId, outputDirectory: '/p'),
        throwsA(isA<StateError>()),
      );
      // No stitch was attempted, and the project was NOT marked complete.
      expect(seam.stitchCalls, isEmpty);
      final project = await projectsDao.getById(projectId);
      expect(project!.status, isNot(MosaicProjectStatus.complete));
      expect(project.outputMasterId, isNull);
    });
  });
}
