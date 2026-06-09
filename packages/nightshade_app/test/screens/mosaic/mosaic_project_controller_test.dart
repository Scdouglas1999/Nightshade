// Controller tests for the Mosaic project review screen.
//
// Exercises the UI-side orchestration against an in-memory database with the
// REAL v45 DAOs, and a SPY [MosaicProjectService] (a subclass recording calls
// and returning canned outcomes) so the controller's two durable actions are
// pinned without the native stitcher / integration pipeline:
//
//   * load() reads the project + panels + per-panel masters + stitched output.
//   * integratePanels() drives the service then reloads.
//   * stitchProject() is GATED on >= 2 panels with masters — with fewer than two
//     it records an error WITHOUT touching the service; with two it drives it.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// A [MosaicProjectService] spy: it never calls the real integration / stitch
/// path, only records the calls and (for integrate) links a canned per-panel
/// master onto each panel so the controller's reload reflects "integrated".
class _SpyService extends MosaicProjectService {
  _SpyService({
    required this.panelsDao,
    required this.mastersDao,
    required this.projectsDao,
    required super.imagesDao,
    required super.integrationService,
    required super.seam,
  }) : super(
            projectsDao: projectsDao,
            panelsDao: panelsDao,
            mastersDao: mastersDao);

  final MosaicPanelsDao panelsDao;
  final IntegratedMastersDao mastersDao;
  final MosaicProjectsDao projectsDao;

  int integrateCalls = 0;
  int stitchCalls = 0;

  /// How many panels integrate should link a master onto (mirrors a partial
  /// capture: only the first [panelsToLink] panels produced subs).
  int panelsToLink = 0;

  @override
  Future<List<MosaicPanelIntegrationOutcome>> integratePanels(
    int projectId, {
    required IntegrationSettings settings,
    required String Function(MosaicProjectPanel panel) outputFitsPathBuilder,
  }) async {
    integrateCalls++;
    final panels = await panelsDao.getForProject(projectId);
    final outcomes = <MosaicPanelIntegrationOutcome>[];
    for (final panel in panels.take(panelsToLink)) {
      final masterId = await mastersDao.insertMaster(
        name: 'Panel ${panel.panelIndex} master',
        masterFitsPath: outputFitsPathBuilder(panel),
        previewPngPath: '${outputFitsPathBuilder(panel)}.png',
        status: IntegratedMasterStatus.finalized,
        accumulationMode: AccumulationMode.batch,
        width: 100,
        height: 80,
        frameCount: 5,
      );
      await panelsDao.setMaster(panel.id!, masterId);
      await panelsDao.incrementCaptured(panel.id!, delta: 5);
      outcomes.add(MosaicPanelIntegrationOutcome(
        panelId: panel.id!,
        panelIndex: panel.panelIndex,
        integratedMasterId: masterId,
        status: MosaicPanelStatus.integrated,
        subCount: 5,
      ));
    }
    return outcomes;
  }

  @override
  Future<MosaicStitchOutcome> stitchProject(
    int projectId, {
    required String outputDirectory,
    Map<String, dynamic>? stitchConfig,
  }) async {
    stitchCalls++;
    final masterId = await mastersDao.insertMaster(
      name: 'Mosaic master',
      masterFitsPath: '$outputDirectory/mosaic.fits',
      previewPngPath: '$outputDirectory/mosaic.png',
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      width: 200,
      height: 80,
      frameCount: panelsToLink,
    );
    await projectsDao.setOutputMaster(projectId, masterId);
    return MosaicStitchOutcome(
      outputMasterId: masterId,
      panelCount: panelsToLink,
      result: MosaicStitchResult(
        outputPath: '$outputDirectory/mosaic.fits',
        previewPath: '$outputDirectory/mosaic.png',
        outWidth: 200,
        outHeight: 80,
        overlapPairs: panelsToLink - 1,
        meanPanelGain: 1.0,
      ),
    );
  }
}

void main() {
  late NightshadeDatabase db;
  late MosaicProjectsDao projectsDao;
  late MosaicPanelsDao panelsDao;
  late IntegratedMastersDao mastersDao;
  late _SpyService spy;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    projectsDao = MosaicProjectsDao(db);
    panelsDao = MosaicPanelsDao(db);
    mastersDao = IntegratedMastersDao(db);
    // The spy never reaches imagesDao / integration / seam, but the super ctor
    // requires them — hand it the real DAO-backed instances.
    spy = _SpyService(
      panelsDao: panelsDao,
      mastersDao: mastersDao,
      projectsDao: projectsDao,
      imagesDao: ImagesDao(db),
      integrationService: PostSessionIntegrationService(
        mastersDao: mastersDao,
        darkLibrary: DarkLibraryService(DarkLibraryDao(db)),
        flatLibrary: FlatLibraryService(
          dao: FlatLibraryDao(db),
          seam: _noopSeam(),
        ),
        seam: _noopSeam(),
      ),
      seam: _noopSeam(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// Seed a project with [panelCount] pending panels, returning the project id.
  Future<int> seedProject({int rows = 1, int cols = 3}) async {
    final projectId = await projectsDao.create(
      name: 'Veil $cols x $rows',
      rows: rows,
      cols: cols,
    );
    for (var i = 0; i < rows * cols; i++) {
      await panelsDao.upsert(
        projectId: projectId,
        panelIndex: i,
        centerRa: 20.0 + i * 0.01,
        centerDec: 30.0,
      );
    }
    return projectId;
  }

  MosaicProjectController makeController(int projectId) {
    return MosaicProjectController(
      projectId: projectId,
      projectsDao: projectsDao,
      panelsDao: panelsDao,
      mastersDao: mastersDao,
      service: spy,
      panelOutputPathBuilder: (panel) =>
          '/tmp/mosaic/${panel.projectId}/panel_${panel.panelIndex}.fits',
      stitchOutputDirectory: (project) => '/tmp/mosaic/${project.id}',
    );
  }

  /// Pump until the controller's load future has resolved.
  Future<void> waitForLoad(MosaicProjectController c) async {
    for (var i = 0; i < 20 && c.state.isLoading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('load resolves project + panels from the DAOs', () async {
    final projectId = await seedProject(cols: 3);
    final c = makeController(projectId);
    await waitForLoad(c);

    expect(c.state.project, isNotNull);
    expect(c.state.project!.cols, 3);
    expect(c.state.panels, hasLength(3));
    expect(c.state.panelsWithMasters, 0);
    expect(c.state.canStitch, isFalse);
    expect(c.state.isComplete, isFalse);
    c.dispose();
  });

  test('integratePanels calls the service and reloads with linked masters',
      () async {
    final projectId = await seedProject(cols: 3);
    spy.panelsToLink = 3;
    final c = makeController(projectId);
    await waitForLoad(c);

    await c.integratePanels();

    expect(spy.integrateCalls, 1);
    expect(c.state.panelsWithMasters, 3);
    // Each integrated panel resolved its per-panel master for a thumbnail.
    expect(c.state.panelMasters, hasLength(3));
    expect(c.state.canStitch, isTrue);
    expect(c.state.isIntegrating, isFalse);
    expect(c.state.error, isNull);
    c.dispose();
  });

  test('stitchProject is GATED on < 2 masters — service is not called',
      () async {
    final projectId = await seedProject(cols: 3);
    // Link only ONE panel: below the >= 2 stitch threshold.
    spy.panelsToLink = 1;
    final c = makeController(projectId);
    await waitForLoad(c);
    await c.integratePanels();
    expect(c.state.panelsWithMasters, 1);
    expect(c.state.canStitch, isFalse);

    await c.stitchProject();

    // The doomed FFI round-trip was never made; a clear error is surfaced.
    expect(spy.stitchCalls, 0);
    expect(c.state.error, isNotNull);
    expect(c.state.error, contains('at least 2'));
    expect(c.state.isComplete, isFalse);
    c.dispose();
  });

  test('stitchProject calls the service once >= 2 panels have masters',
      () async {
    final projectId = await seedProject(cols: 3);
    spy.panelsToLink = 2;
    final c = makeController(projectId);
    await waitForLoad(c);
    await c.integratePanels();
    expect(c.state.canStitch, isTrue);

    await c.stitchProject();

    expect(spy.stitchCalls, 1);
    expect(c.state.isComplete, isTrue);
    expect(c.state.stitchedMaster, isNotNull);
    expect(c.state.project!.status, MosaicProjectStatus.complete);
    expect(c.state.isStitching, isFalse);
    expect(c.state.error, isNull);
    c.dispose();
  });
}

/// A throwaway [PostSessionSeam] for wiring the unused integration service in
/// the spy's super ctor — the controller never reaches it.
PostSessionSeam _noopSeam() => _NoopSeam();

class _NoopSeam implements PostSessionSeam {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used in test');
}
