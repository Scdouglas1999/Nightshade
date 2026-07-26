// Controller tests for the Smart Morning Report data backbone added to
// [SessionReviewController]: the smart-data load (Night Doctor report), the
// view-mode toggle, the curve-linked cull guard, and the narrowband channel
// projection. Runs against an in-memory database and a fake post-session seam
// (its progress stream is empty, exercising the progress binding harmlessly).

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/session_review_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/services/post_session_seam.dart' as seam;

import '../../harness/mock_database.dart';

class _FakeSeam implements PostSessionSeam {
  @override
  Future<seam.IntegrateSessionResult> integrateSession(
          Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<seam.MasterAccumulateResult> masterAccumulate(
          Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<seam.BuildMasterFlatResult> buildMasterFlat(
          Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<seam.SaveFitsMasterResult> saveFitsMaster(
          Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<IntegrationCurve> analyzeNight({
    required List<Map<String, dynamic>> qualities,
    required List<double> weights,
    required List<double> exposuresS,
    double? aggressiveness,
    int? minKeep,
  }) async =>
      throw UnimplementedError();

  @override
  Future<StarPhotometryResult> detectStarsPhotometry({
    required String inputFits,
    int? maxStars,
    int? aperture,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ColorCalibrationResult> colorCalibrate({
    required String inputFits,
    required String outputFits,
    required int channels,
    double? whiteRefBv,
    required List<Map<String, dynamic>> matchedStars,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> extractBackground(Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<String> deconvolvePreview(Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<String> reduceStarsPreview(Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> drizzleIntegrate(
          Map<String, dynamic> args) async =>
      throw UnimplementedError();

  /// Records the combine request so the test can assert the controller wired
  /// the palette + inputs correctly; returns a synthetic composite path.
  Map<String, dynamic>? lastCombineArgs;

  @override
  Future<String> combineChannels(Map<String, dynamic> args) async {
    lastCombineArgs = args;
    return args['output'] as String;
  }

  @override
  Future<MosaicStitchResult> stitchMosaic(Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Stream<({String phase, double fraction})> integrationProgress() =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ProviderContainer container;
  late _FakeSeam fakeSeam;
  late int sessionId;

  setUp(() async {
    db = mockDatabase();
    fakeSeam = _FakeSeam();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      postSessionSeamProvider.overrideWithValue(fakeSeam),
    ]);

    final sessions = container.read(sessionsDaoProvider);
    final images = container.read(imagesDaoProvider);

    sessionId = await sessions.createSession(
      ImagingSessionsCompanion.insert(startTime: DateTime.now()),
    );

    for (var i = 0; i < 4; i++) {
      await images.createImage(
        CapturedImagesCompanion.insert(
          filePath: 'C:/subs/s$i.fits',
          fileName: 's$i.fits',
          sessionId: Value(sessionId),
          exposureDuration: 60,
          frameType: const Value('light'),
          filter: const Value('L'),
          hfr: Value(2.0 + i * 0.1),
          isAccepted: const Value(true),
          capturedAt: DateTime.now().add(Duration(minutes: i)),
        ),
      );
    }
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  SessionReviewController controller() => container.read(
        sessionReviewControllerProvider(SessionReviewScope.session(sessionId))
            .notifier,
      );

  SessionReviewState state() => container.read(
        sessionReviewControllerProvider(SessionReviewScope.session(sessionId)),
      );

  Future<void> waitUntilLoaded() async {
    for (var i = 0;
        i < 50 && (state().loading || state().loadingSmartData);
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('loadSmartData populates a night report and settles loading flag',
      () async {
    controller();
    await waitUntilLoaded();
    // A clean four-sub session yields a neutral (non-null) Night Doctor report.
    expect(state().nightReport, isNotNull);
    expect(state().nightReport!.score, inInclusiveRange(0, 100));
    expect(state().loadingSmartData, isFalse);
    // No master in scope → no improvement curve / growth / annotations.
    expect(state().improvementCurve, isNull);
    expect(state().growthPoints, isEmpty);
    expect(state().bestNight, isNull);
    expect(state().annotationLayer, isNull);
  });

  test('default view mode is narrative and setViewMode toggles it', () async {
    final c = controller();
    await waitUntilLoaded();
    expect(state().viewMode, SessionReviewViewMode.narrative);
    c.setViewMode();
    expect(state().viewMode, SessionReviewViewMode.workbench);
    c.setViewMode(SessionReviewViewMode.narrative);
    expect(state().viewMode, SessionReviewViewMode.narrative);
  });

  test('cullToRecommended is a no-op with no improvement curve loaded',
      () async {
    final c = controller();
    await waitUntilLoaded();
    expect(state().improvementCurve, isNull);
    final result = await c.cullToRecommended();
    expect(result.outcome, CullOutcome.staleCurve);
    expect(result.rejected, 0);
    expect(state().acceptedCount, 4);
  });

  test('narrowbandChannels lists only narrowband-filtered masters', () async {
    controller();
    await waitUntilLoaded();
    // A luminance-only session exposes no narrowband channels.
    expect(state().narrowbandChannels, isEmpty);
  });

  /// Insert a finalized master carrying an improvement curve whose recommendation
  /// keeps [keepN] of the population [populationPaths], so the controller picks
  /// it up as the reviewed master and loads the curve + population.
  Future<void> seedMasterWithCurve({
    required int keepN,
    required List<int> keptIndices,
    required List<String> populationPaths,
  }) async {
    final masters = container.read(integratedMastersDaoProvider);
    final id = await masters.insertMaster(
      targetId: null,
      name: 'Test master',
      masterFitsPath: '/tmp/m.fits',
      previewPngPath: null,
      sidecarPath: null,
      rejectionMapPath: null,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: 1,
      width: 100,
      height: 100,
      frameCount: populationPaths.length,
      totalIntegrationSeconds: populationPaths.length * 60.0,
      filter: 'L',
      settingsJson: '{}',
      statsJson: '{}',
    );
    final curve = IntegrationCurve(
      points: const [],
      recommendation: SubsetRecommendation(
        keepN: keepN,
        keptIndices: keptIndices,
        predictedSnrGainPct: 3.0,
        reason: 'test',
      ),
    );
    final stored = curve.toJson()..['population'] = populationPaths;
    await masters.updateSmartFields(id,
        improvementCurveJson: jsonEncode(stored));
  }

  test(
      'cullToRecommended maps keptIndices through the population paths and '
      'rejects exactly the non-kept subs', () async {
    // Population in capture order = the four accepted subs; keep the first two.
    await seedMasterWithCurve(
      keepN: 2,
      keptIndices: const [0, 1],
      populationPaths: const [
        'C:/subs/s0.fits',
        'C:/subs/s1.fits',
        'C:/subs/s2.fits',
        'C:/subs/s3.fits',
      ],
    );
    final c = controller();
    await waitUntilLoaded();
    expect(state().improvementCurve, isNotNull);
    expect(state().improvementCurvePopulation, hasLength(4));

    final result = await c.cullToRecommended();
    expect(result.outcome, CullOutcome.culled);
    expect(result.rejected, 2);

    // s0/s1 stay accepted; s2/s3 (outside keptIndices) are now rejected.
    final accepted = state().acceptedLights.map((s) => s.filePath).toSet();
    expect(accepted, {'C:/subs/s0.fits', 'C:/subs/s1.fits'});

    // The cull fires an unawaited loadSmartData() to re-derive the backbone;
    // let it settle so it doesn't run after tearDown disposes the container.
    await waitUntilLoaded();
  });

  test(
      'cullToRecommended is a no-op when the curve population no longer matches '
      'the live accepted subs (stale curve never rejects arbitrary subs)',
      () async {
    // The population references a sub path that is NOT among the live subs, so
    // the index space no longer maps — the cull must bail without rejecting.
    await seedMasterWithCurve(
      keepN: 2,
      keptIndices: const [0, 1],
      populationPaths: const [
        'C:/subs/s0.fits',
        'C:/subs/s1.fits',
        'C:/subs/GHOST.fits',
        'C:/subs/s3.fits',
      ],
    );
    final c = controller();
    await waitUntilLoaded();

    final result = await c.cullToRecommended();
    expect(result.outcome, CullOutcome.staleCurve);
    expect(result.rejected, 0);
    expect(state().acceptedCount, 4);
  });

  test('cullToRecommended is a no-op when the curve carried no population',
      () async {
    final masters = container.read(integratedMastersDaoProvider);
    final id = await masters.insertMaster(
      targetId: null,
      name: 'No-pop master',
      masterFitsPath: '/tmp/m2.fits',
      previewPngPath: null,
      sidecarPath: null,
      rejectionMapPath: null,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: 1,
      width: 100,
      height: 100,
      frameCount: 4,
      totalIntegrationSeconds: 240,
      filter: 'L',
      settingsJson: '{}',
      statsJson: '{}',
    );
    // Legacy-style curve JSON with NO population sibling key.
    const curve = IntegrationCurve(
      points: [],
      recommendation: SubsetRecommendation(
        keepN: 2,
        keptIndices: [0, 1],
        predictedSnrGainPct: 3.0,
        reason: 'test',
      ),
    );
    await masters.updateSmartFields(id,
        improvementCurveJson: jsonEncode(curve.toJson()));

    final c = controller();
    await waitUntilLoaded();
    expect(state().improvementCurve, isNotNull);
    expect(state().improvementCurvePopulation, isEmpty);

    final result = await c.cullToRecommended();
    expect(result.outcome, CullOutcome.staleCurve);
    expect(result.rejected, 0);
    expect(state().acceptedCount, 4);
  });

  test('runNarrowband errors when fewer than two channels are available',
      () async {
    final c = controller();
    await waitUntilLoaded();
    final out = await c.runNarrowband('sho', const []);
    expect(out, isNull);
    expect(state().error, isNotNull);
    expect(fakeSeam.lastCombineArgs, isNull);
  });
}
