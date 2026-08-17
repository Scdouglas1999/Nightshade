// The durable half of the post-session integration.
//
// The pass integrates FIRST and enqueues its Darkroom job SECOND, so nothing
// in `darkroom_jobs` covers the integrate itself. A kill there used to leave
// no row, no note and no log — while a truncated master sat on disk looking
// finished. These tests pin the marker that ends that silence: written before
// the first sub is read, naming the files about to be written, and cleared on
// every ending the service can actually reach.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/auto_integration_service.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Batch-integration stub that reports what the marker said WHILE it ran.
class _ObservingIntegrationService implements PostSessionIntegrationService {
  _ObservingIntegrationService(this._markerDir, {this.failWith});

  final Directory _markerDir;

  /// When set, the integrate throws — a failure the service catches and
  /// reports, which is NOT an interruption.
  final Object? failWith;

  InterruptedIntegration? markerDuringRun;
  final List<String> pathsWritten = [];

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
    String? runId,
  }) async {
    markerDuringRun = await readIntegrationMarker(_markerDir);

    final byBucket = <String, List<DbCapturedImage>>{};
    for (final sub in subs) {
      final trimmed = (sub.filter ?? '').trim();
      byBucket
          .putIfAbsent(
            trimmed.isEmpty
                ? PostSessionIntegrationService.noFilterBucket
                : trimmed,
            () => [],
          )
          .add(sub);
    }

    final failure = failWith;
    if (failure != null) throw failure;

    var id = 1000;
    return [
      for (final entry in byBucket.entries)
        () {
          final path = outputFitsPathBuilder(entry.key);
          pathsWritten.add(path);
          return PostSessionIntegrationOutcome(
            masterId: id++,
            filter: entry.key == PostSessionIntegrationService.noFilterBucket
                ? null
                : entry.key,
            result: IntegrateSessionResult(
              masterFitsPath: path,
              previewPath: null,
              rejectionMapPath: null,
              framesIntegrated: entry.value.length,
              framesRejected: 0,
              totalIntegrationSec: entry.value.length * 120.0,
              rmsResidual: 0.0,
              width: 10,
              height: 10,
              channels: 1,
              perFrameStats: const [],
            ),
          );
        }(),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Accumulation stub that reports what the marker said WHILE it folded.
class _ObservingAccumulationService implements MasterAccumulationService {
  _ObservingAccumulationService(this._markerDir);

  final Directory _markerDir;
  final List<int> foldedInto = [];
  InterruptedIntegration? markerDuringRun;

  @override
  Future<MasterAccumulateResult> addNight({
    required int masterId,
    required List<DbCapturedImage> subs,
    required String label,
    IntegrationSettings settings = IntegrationSettings.defaults,
    String? biasPath,
    String? runId,
  }) async {
    markerDuringRun = await readIntegrationMarker(_markerDir);
    foldedInto.add(masterId);
    return MasterAccumulateResult(
      sidecarPath: '/sidecar_$masterId.nsmaster',
      masterPath: null,
      previewPath: null,
      frameCount: subs.length,
      totalIntegrationSec: subs.length * 120.0,
      width: 10,
      height: 10,
      channels: 1,
      framesAdded: subs.length,
      rejected: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  late NightshadeDatabase db;
  late Directory markerDir;
  late Directory outDir;
  late PushNotificationService push;
  late StreamSubscription<PushNotification> pushSubscription;

  setUp(() async {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    markerDir = await Directory.systemTemp.createTemp('ns_marker_');
    outDir = await Directory.systemTemp.createTemp('ns_out_');
    push = PushNotificationService();
    pushSubscription = push.notifications.listen((_) {});
    await db.settingsDao.setSetting(kAutoIntegrateSettingKey, 'true');
    await db.settingsDao.setSetting(kDarkroomAutoDraftSettingKey, 'false');
    await db.settingsDao.setImageOutputDirectory(outDir.path);
  });

  tearDown(() async {
    await pushSubscription.cancel();
    await db.close();
    if (await markerDir.exists()) await markerDir.delete(recursive: true);
    if (await outDir.exists()) await outDir.delete(recursive: true);
  });

  ProviderContainer containerFor(
    PostSessionIntegrationService integrate, {
    Directory? marker,
  }) {
    return ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        postSessionIntegrationServiceProvider.overrideWithValue(integrate),
        pushNotificationServiceProvider.overrideWithValue(push),
        integrationMarkerDirectoryProvider.overrideWith((ref) async => marker),
      ],
    );
  }

  Future<int> seedNight({String filter = 'L'}) async {
    final sessionId = await db
        .into(db.imagingSessions)
        .insert(ImagingSessionsCompanion.insert(startTime: DateTime.now()));
    final targetId = await db
        .into(db.targets)
        .insert(TargetsCompanion.insert(name: 'M31', ra: 1.0, dec: 2.0));
    for (var i = 0; i < 3; i++) {
      await db.into(db.capturedImages).insert(
            CapturedImagesCompanion.insert(
              filePath: '/l/$filter$i.fits',
              fileName: '$filter$i.fits',
              frameType: const Value('light'),
              exposureDuration: 120.0,
              capturedAt: DateTime.now(),
              sessionId: Value(sessionId),
              targetId: Value(targetId),
              filter: Value(filter),
              isAccepted: const Value(true),
            ),
          );
    }
    return sessionId;
  }

  test('the marker is in place while the integration runs', () async {
    final sessionId = await seedNight();
    final integrate = _ObservingIntegrationService(markerDir);
    final container = containerFor(integrate, marker: markerDir);
    addTearDown(container.dispose);

    final result = await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(result.ran, isTrue);
    final marker = integrate.markerDuringRun;
    expect(
      marker,
      isNotNull,
      reason: 'a kill during the integrate must leave a record behind',
    );
    expect(marker!.sessionId, sessionId);
    expect(marker.targetName, 'M31');
    expect(
      marker.intendedMasterPaths,
      integrate.pathsWritten,
      reason: 'the marker must name the files that were actually going to be '
          'written — a predicted path that never matches names no orphan',
    );
  });

  test('a finished run leaves no marker behind', () async {
    final sessionId = await seedNight();
    final container = containerFor(
      _ObservingIntegrationService(markerDir),
      marker: markerDir,
    );
    addTearDown(container.dispose);

    await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(await integrationMarkerFile(markerDir).exists(), isFalse);
  });

  test('a reported failure is not an interruption', () async {
    final sessionId = await seedNight();
    final container = containerFor(
      _ObservingIntegrationService(
        markerDir,
        failWith: StateError('the stacker refused'),
      ),
      marker: markerDir,
    );
    addTearDown(container.dispose);

    final result = await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(result.failed, isTrue);
    expect(
      await integrationMarkerFile(markerDir).exists(),
      isFalse,
      reason: 'the operator already has the error; a marker left here would '
          'announce it again at the next launch as a crash that never happened',
    );
  });

  test('a night with nothing to integrate leaves no marker', () async {
    final sessionId = await db
        .into(db.imagingSessions)
        .insert(ImagingSessionsCompanion.insert(startTime: DateTime.now()));
    final container = containerFor(
      _ObservingIntegrationService(markerDir),
      marker: markerDir,
    );
    addTearDown(container.dispose);

    final result = await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(result.ran, isFalse);
    expect(await integrationMarkerFile(markerDir).exists(), isFalse);
  });

  test('the fold phase is covered too, with no orphan to name', () async {
    final sessionId = await seedNight();
    final targetId = (await TargetsDao(db).getAllTargets()).single.id;
    final masterId = await IntegratedMastersDao(db).insertMaster(
      targetId: targetId,
      name: 'M31 L (growing)',
      sidecarPath: '${outDir.path}/m31_l.nsmaster',
      status: IntegratedMasterStatus.accumulating,
      accumulationMode: AccumulationMode.runningWeightedMean,
      filter: 'L',
    );

    final accumulate = _ObservingAccumulationService(markerDir);
    final integrate = _ObservingIntegrationService(markerDir);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        masterAccumulationServiceProvider.overrideWithValue(accumulate),
        postSessionIntegrationServiceProvider.overrideWithValue(integrate),
        pushNotificationServiceProvider.overrideWithValue(push),
        integrationMarkerDirectoryProvider.overrideWith(
          (ref) async => markerDir,
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(result.ran, isTrue);
    expect(accumulate.foldedInto, [masterId]);
    final marker = accumulate.markerDuringRun;
    expect(
      marker,
      isNotNull,
      reason: 'a kill during addNight strands the night just as completely',
    );
    expect(marker!.sessionId, sessionId);
    expect(
      marker.intendedMasterPaths,
      isEmpty,
      reason:
          'a fold grows a master that already exists — naming it as an orphan '
          'would tell the operator to delete their multi-night stack',
    );
    expect(await integrationMarkerFile(markerDir).exists(), isFalse);
  });

  test('an unplaceable marker does not stop the night integrating', () async {
    final sessionId = await seedNight();
    final integrate = _ObservingIntegrationService(markerDir);
    final container = containerFor(integrate, marker: null);
    addTearDown(container.dispose);

    final result = await container
        .read(autoIntegrationServiceProvider)
        .maybeRunForSession(sessionId);

    expect(
      result.ran,
      isTrue,
      reason: 'a diagnostic file must never cost a real master',
    );
    expect(integrate.pathsWritten, hasLength(1));
    expect(integrate.markerDuringRun, isNull);
  });
}
