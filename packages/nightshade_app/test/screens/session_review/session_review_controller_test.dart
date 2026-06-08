// Controller tests for the Session Review screen.
//
// Exercises the UI-side orchestration against an in-memory database and a fake
// post-session seam: sub loading, the bulk-cull predicate, accept/reject
// round-trip, and that a one-shot integrate persists an integrated_masters row.

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
      Map<String, dynamic> args) async {
    final lights = (args['lightPaths'] as List).cast<String>();
    final output = args['output'] as Map<String, dynamic>;
    return seam.IntegrateSessionResult(
      masterFitsPath: output['masterFitsPath'] as String,
      previewPath: output['previewPngPath'] as String?,
      rejectionMapPath: output['rejectionMapPath'] as String?,
      framesIntegrated: lights.length,
      framesRejected: 0,
      totalIntegrationSec: lights.length * 60.0,
      rmsResidual: 0.4,
      width: 100,
      height: 80,
      channels: 1,
      perFrameStats: [
        for (final p in lights)
          seam.PerFrameRecord(
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

  // --- Smart Morning Report seam surface (unused by these tests) ------------
  // These controller tests only exercise integrateSession; the remaining nine
  // PostSessionSeam members are stubbed to satisfy the interface.

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

  @override
  Future<String> combineChannels(Map<String, dynamic> args) async =>
      throw UnimplementedError();

  @override
  Stream<({String phase, double fraction})> integrationProgress() =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ProviderContainer container;
  late int sessionId;

  setUp(() async {
    db = mockDatabase();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      postSessionSeamProvider.overrideWithValue(_FakeSeam()),
    ]);

    final sessions = container.read(sessionsDaoProvider);
    final images = container.read(imagesDaoProvider);

    sessionId = await sessions.createSession(
      ImagingSessionsCompanion.insert(startTime: DateTime.now()),
    );

    Future<void> addSub(String name, {required double hfr, bool accepted = true}) {
      return images.createImage(
        CapturedImagesCompanion.insert(
          filePath: 'C:/subs/$name.fits',
          fileName: '$name.fits',
          sessionId: Value(sessionId),
          exposureDuration: 60,
          frameType: const Value('light'),
          filter: const Value('L'),
          hfr: Value(hfr),
          qualityScore: Value(100 - hfr * 10),
          isAccepted: Value(accepted),
          capturedAt: DateTime.now(),
        ),
      );
    }

    await addSub('a', hfr: 2.0);
    await addSub('b', hfr: 2.4);
    await addSub('c', hfr: 5.0); // worst — culled by HFR>3.5
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
    for (var i = 0; i < 50 && state().loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('loads the session subs and counts acceptance', () async {
    controller();
    await waitUntilLoaded();
    expect(state().lights.length, 3);
    expect(state().acceptedCount, 3);
  });

  test('bulkReject culls subs above the HFR threshold', () async {
    final c = controller();
    await waitUntilLoaded();
    final rejected = await c.bulkReject(hfrThreshold: 3.5);
    expect(rejected, 1);
    expect(state().acceptedCount, 2);
    expect(state().rejectedCount, 1);
  });

  test('setAccepted toggles a single sub', () async {
    final c = controller();
    await waitUntilLoaded();
    final id = state().lights.first.id;
    await c.setAccepted(id, false);
    expect(state().acceptedCount, 2);
    await c.setAccepted(id, true);
    expect(state().acceptedCount, 3);
  });

  test('integrate persists a master from the accepted subs', () async {
    final c = controller();
    await waitUntilLoaded();
    await c.bulkReject(hfrThreshold: 3.5); // drop the worst sub
    final outcome = await c.integrate();
    expect(outcome, isNotNull);
    expect(outcome!.result.framesIntegrated, 2);

    final masters = await container.read(integratedMastersDaoProvider).getAll();
    expect(masters, hasLength(1));
    expect(masters.first.frameCount, 2);
    expect(state().lastOutcome, isNotNull);
    expect(state().masters, hasLength(1));
  });
}
