// Tests for [AutoIntegrationService.maybeRunForSession] — the unattended
// "wake up to a finished image" hook fired at run completion.
//
// The flagship case here is the multi-filter regression (senior review blocker
// #6): a target with an accumulating master for ONE filter must not silently
// drop the subs of every other filter. The service must route each filter
// bucket independently (fold into its accumulating master when present, else
// batch-integrate) and report the total subs across all filters.
//
// Runs against an in-memory database for the DAO-backed providers; the two
// heavy orchestration services (accumulate + batch integrate) are faked so the
// routing decision is observable without native code.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/auto_integration_service.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Fake accumulation service that records every `addNight` it is asked to run
/// and echoes a result reflecting the folded sub count. All other members throw
/// (they are never reached on the auto-integration path under test).
class _FakeAccumulationService implements MasterAccumulationService {
  final List<({int masterId, List<DbCapturedImage> subs})> calls = [];

  @override
  Future<MasterAccumulateResult> addNight({
    required int masterId,
    required List<DbCapturedImage> subs,
    required String label,
    IntegrationSettings settings = IntegrationSettings.defaults,
    String? biasPath,
  }) async {
    calls.add((masterId: masterId, subs: subs));
    return MasterAccumulateResult(
      sidecarPath: '/sidecar_$masterId.nsmaster',
      masterPath: null,
      previewPath: null,
      frameCount: subs.length,
      totalIntegrationSec: subs.fold<double>(
          0, (a, s) => a + s.exposureDuration),
      width: 100,
      height: 80,
      channels: 1,
      framesAdded: subs.length,
      rejected: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Fake batch-integration service that records the subs it integrates and
/// produces one outcome per filter bucket (mirroring the real fan-out).
class _FakeIntegrationService implements PostSessionIntegrationService {
  final List<List<DbCapturedImage>> calls = [];

  @override
  Future<List<PostSessionIntegrationOutcome>> integrate({
    required List<DbCapturedImage> subs,
    required IntegrationSettings settings,
    required String Function(String filterBucket) outputFitsPathBuilder,
    int? targetId,
    String? targetName,
    String? biasPath,
    ResolvedCalibration? pinnedCalibration,
    bool generatePreview = true,
    double? hintRaHours,
    double? hintDecDegrees,
  }) async {
    calls.add(subs);
    // Group by trimmed filter, one outcome per bucket — the real service's
    // contract — so the caller's per-filter accounting is exercised honestly.
    final byBucket = <String, List<DbCapturedImage>>{};
    for (final s in subs) {
      final b = (s.filter ?? '').trim();
      byBucket.putIfAbsent(b.isEmpty ? '(none)' : b, () => []).add(s);
    }
    var id = 1000;
    return [
      for (final e in byBucket.entries)
        PostSessionIntegrationOutcome(
          masterId: id++,
          filter: e.key == '(none)' ? null : e.key,
          result: IntegrateSessionResult(
            masterFitsPath: outputFitsPathBuilder(e.key),
            previewPath: null,
            rejectionMapPath: null,
            framesIntegrated: e.value.length,
            framesRejected: 0,
            totalIntegrationSec:
                e.value.fold<double>(0, (a, s) => a + s.exposureDuration),
            rmsResidual: 0.0,
            width: 100,
            height: 80,
            channels: 1,
            perFrameStats: const [],
          ),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  late NightshadeDatabase db;
  late _FakeAccumulationService accumulate;
  late _FakeIntegrationService integrate;
  late ProviderContainer container;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    accumulate = _FakeAccumulationService();
    integrate = _FakeIntegrationService();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      masterAccumulationServiceProvider.overrideWithValue(accumulate),
      postSessionIntegrationServiceProvider.overrideWithValue(integrate),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> enableAutoIntegrate() async {
    await db.settingsDao.setSetting(kAutoIntegrateSettingKey, 'true');
  }

  Future<int> insertSession() {
    return db.into(db.imagingSessions).insert(
          ImagingSessionsCompanion.insert(startTime: DateTime.now()),
        );
  }

  Future<int> insertTarget(String name) {
    return db.into(db.targets).insert(
          TargetsCompanion.insert(name: name, ra: 1.0, dec: 2.0),
        );
  }

  Future<int> insertSub({
    required int sessionId,
    int? targetId,
    required String filter,
    bool accepted = true,
  }) {
    final stamp = DateTime.now().microsecondsSinceEpoch +
        filter.hashCode +
        (accepted ? 0 : 1);
    return db.into(db.capturedImages).insert(
          CapturedImagesCompanion.insert(
            filePath: '/l/${filter}_$stamp.fits',
            fileName: '${filter}_$stamp.fits',
            frameType: const Value('light'),
            exposureDuration: 120.0,
            capturedAt: DateTime.now(),
            sessionId: Value(sessionId),
            targetId: Value(targetId),
            gain: const Value(100),
            offset: const Value(10),
            binX: const Value(1),
            binY: const Value(1),
            filter: Value(filter),
            isAccepted: Value(accepted),
          ),
        );
  }

  Future<int> insertAccumulatingMaster({
    required int targetId,
    required String filter,
  }) {
    return IntegratedMastersDao(db).insertMaster(
      targetId: targetId,
      name: 'M-$filter',
      sidecarPath: '/sidecar_$filter.nsmaster',
      status: IntegratedMasterStatus.accumulating,
      accumulationMode: AccumulationMode.runningWeightedMean,
      filter: filter,
    );
  }

  test('disabled setting is a clean no-op', () async {
    final service = container.read(autoIntegrationServiceProvider);
    final result = await service.maybeRunForSession(1);
    expect(result.ran, isFalse);
    expect(accumulate.calls, isEmpty);
    expect(integrate.calls, isEmpty);
  });

  test(
      'REGRESSION #6: a multi-filter night with an accumulating master for ONE '
      'filter still integrates every other filter (no silent drop)', () async {
    await enableAutoIntegrate();
    final sessionId = await insertSession();
    final targetId = await insertTarget('M42');

    // Accumulating master exists for L only.
    final lMaster = await insertAccumulatingMaster(targetId: targetId, filter: 'L');

    // Night: 3×L (dominant, has a master), 2×Ha, 1×OIII (no masters).
    for (var i = 0; i < 3; i++) {
      await insertSub(sessionId: sessionId, targetId: targetId, filter: 'L');
    }
    for (var i = 0; i < 2; i++) {
      await insertSub(sessionId: sessionId, targetId: targetId, filter: 'Ha');
    }
    await insertSub(sessionId: sessionId, targetId: targetId, filter: 'OIII');

    final service = container.read(autoIntegrationServiceProvider);
    final result = await service.maybeRunForSession(sessionId);

    expect(result.ran, isTrue);

    // The 3 L subs were folded into the existing accumulating master.
    expect(accumulate.calls, hasLength(1));
    expect(accumulate.calls.single.masterId, lMaster);
    expect(accumulate.calls.single.subs, hasLength(3));

    // The non-dominant Ha + OIII subs were NOT dropped — they were batch
    // integrated (3 subs across two filter buckets).
    expect(integrate.calls, hasLength(1));
    final batched = integrate.calls.single;
    expect(batched, hasLength(3));
    expect(batched.map((s) => (s.filter ?? '').trim()).toSet(), {'Ha', 'OIII'});

    // The toast reports the TOTAL across all filters: 3 (folded) + 3 (batch).
    expect(result.message, contains('6 subs'));
  });

  test('no accumulating master anywhere → every filter is batch-integrated',
      () async {
    await enableAutoIntegrate();
    final sessionId = await insertSession();
    final targetId = await insertTarget('M42');

    for (var i = 0; i < 2; i++) {
      await insertSub(sessionId: sessionId, targetId: targetId, filter: 'L');
    }
    await insertSub(sessionId: sessionId, targetId: targetId, filter: 'Ha');

    final service = container.read(autoIntegrationServiceProvider);
    final result = await service.maybeRunForSession(sessionId);

    expect(result.ran, isTrue);
    expect(accumulate.calls, isEmpty);
    expect(integrate.calls, hasLength(1));
    // All three subs (both filters) reach the batch integrator.
    expect(integrate.calls.single, hasLength(3));
    expect(result.message, contains('3 subs'));
  });

  test('accumulating masters for EVERY filter fold all of them (no batch run)',
      () async {
    await enableAutoIntegrate();
    final sessionId = await insertSession();
    final targetId = await insertTarget('M42');
    final lMaster =
        await insertAccumulatingMaster(targetId: targetId, filter: 'L');
    final haMaster =
        await insertAccumulatingMaster(targetId: targetId, filter: 'Ha');

    for (var i = 0; i < 2; i++) {
      await insertSub(sessionId: sessionId, targetId: targetId, filter: 'L');
    }
    await insertSub(sessionId: sessionId, targetId: targetId, filter: 'Ha');

    final service = container.read(autoIntegrationServiceProvider);
    final result = await service.maybeRunForSession(sessionId);

    expect(result.ran, isTrue);
    // Two folds (one per filter), no batch run.
    expect(accumulate.calls, hasLength(2));
    expect(integrate.calls, isEmpty);
    final folded = {for (final c in accumulate.calls) c.masterId: c.subs.length};
    expect(folded[lMaster], 2);
    expect(folded[haMaster], 1);
    // Total reported across both folds.
    expect(result.message, contains('3 subs'));
  });

  test('whitespace-padded filter names fold into the same bucket (no drop)',
      () async {
    await enableAutoIntegrate();
    final sessionId = await insertSession();
    final targetId = await insertTarget('M42');
    final lMaster =
        await insertAccumulatingMaster(targetId: targetId, filter: 'L');

    // Two L subs, one with a trailing space — they must NOT fragment into a
    // separate bucket that gets routed differently.
    await insertSub(sessionId: sessionId, targetId: targetId, filter: 'L');
    await insertSub(sessionId: sessionId, targetId: targetId, filter: 'L ');

    final service = container.read(autoIntegrationServiceProvider);
    final result = await service.maybeRunForSession(sessionId);

    expect(result.ran, isTrue);
    // Both subs folded into the one L master; nothing spilled to a batch run.
    expect(accumulate.calls, hasLength(1));
    expect(accumulate.calls.single.masterId, lMaster);
    expect(accumulate.calls.single.subs, hasLength(2));
    expect(integrate.calls, isEmpty);
    expect(result.message, contains('2 subs'));
  });
}
