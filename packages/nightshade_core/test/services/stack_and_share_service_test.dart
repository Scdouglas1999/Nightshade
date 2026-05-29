// Stack-and-Share Loop — tests for the orchestrator service (C6).
//
// The provider test (stack_and_share_provider_test.dart) substitutes a fake
// StackAndShareService, so the real run() body — the busy guard, the
// reference-first ordering, the per-frame accept/reject accounting, the
// calibration-on vs calibration-off path split, and the always-release
// `finally` — was previously never executed by any test. This file drives the
// REAL StackAndShareService end-to-end against:
//
//   * a fake [StackingEngineSeam] (injected directly) standing in for the
//     native stacker singleton + raw FITS / stretch bridge calls;
//   * a fake [LiveStackingService] (provider override) for the per-frame add +
//     final getCurrentResult calls;
//   * a fake [StackLightSelector] (provider override) producing a scripted
//     selection;
//   * a real in-memory database for the session lookup + result persistence.
//
// What it pins:
//   (a) LiveStackBusyException when the engine reports active;
//   (b) the reference frame is processed first, then the followers in order;
//   (c) framesRejected increments only when the engine's stacked count does
//       not advance for a follower;
//   (d) the engine is STOPPED (not reset) in the finally even when a mid-run
//       step throws — so a subsequent run is not blocked by a wedged singleton;
//   (e) calibration-off uses the file path (startFromFile / addFrameFromFile)
//       and calibration-on uses the data path (startFromData / addFrameFromData
//       fed by readLinearFrame).

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/database/daos/sessions_dao.dart';
import 'package:nightshade_core/src/database/daos/stacked_results_dao.dart';
import 'package:nightshade_core/src/models/imaging/stack_and_share_models.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/services/live_stacking_service.dart';
import 'package:nightshade_core/src/services/stack_and_share_service.dart';
import 'package:nightshade_core/src/services/stack_light_selector.dart';
import 'package:nightshade_core/src/services/stacking_engine_seam.dart';

/// A record of every call the orchestrator makes through the stacking seam, in
/// order, so tests can assert the path taken (file vs data) and that stop was
/// invoked.
class _FakeStackingEngine implements StackingEngineSeam {
  _FakeStackingEngine({this.active = false});

  /// What [isActive] returns (the busy guard reads this).
  bool active;

  /// Ordered log of seam interactions: `startFile:PATH`, `startData:WxH`,
  /// `read:PATH`, `stretch`, `stop`.
  final List<String> calls = <String>[];

  int stopCount = 0;

  @override
  bool isActive() => active;

  @override
  Future<LiveStackingStats> startFromFile({
    required String referenceImagePath,
    required LiveStackingConfig config,
  }) async {
    calls.add('startFile:$referenceImagePath');
    return const LiveStackingStats(stackedFrameCount: 1);
  }

  @override
  Future<LiveStackingStats> startFromData({
    required int width,
    required int height,
    required List<int> data,
    required LiveStackingConfig config,
  }) async {
    calls.add('startData:${width}x$height');
    return const LiveStackingStats(stackedFrameCount: 1);
  }

  @override
  Future<LinearFrameData> readLinearFrame(String filePath) async {
    calls.add('read:$filePath');
    // A tiny 2x2 frame of mid-range linear samples.
    return const LinearFrameData(
      width: 2,
      height: 2,
      linearData: [100.0, 200.0, 300.0, 400.0],
    );
  }

  @override
  Uint8List autoStretch({
    required int width,
    required int height,
    required List<int> data,
  }) {
    calls.add('stretch');
    return Uint8List(width * height * 4);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    calls.add('stop');
  }
}

/// A [LiveStackingService] stand-in that scripts the running stacked-frame
/// count per added follower, so the orchestrator's accept/reject accounting is
/// exercised deterministically. The reference is frame #1 (count 1); each
/// follower add returns the next scripted count.
class _FakeLiveStacking implements LiveStackingService {
  _FakeLiveStacking({
    required this.followerCounts,
    required this.finalResult,
  });

  /// Stacked-frame count returned for each follower add, in order. A value that
  /// does not advance past the previous count marks that follower rejected.
  final List<int> followerCounts;

  /// The integrated result returned by [getCurrentResult].
  final LiveStackingResult finalResult;

  /// Ordered log of the per-frame add calls.
  final List<String> addCalls = <String>[];

  int _followerIndex = 0;

  @override
  Future<LiveStackingResult> addFrameFromFile(String imagePath) async {
    addCalls.add('addFile:$imagePath');
    return _nextResult();
  }

  @override
  Future<LiveStackingResult> addFrameFromData({
    required int width,
    required int height,
    required List<int> data,
  }) async {
    addCalls.add('addData:${width}x$height');
    return _nextResult();
  }

  LiveStackingResult _nextResult() {
    final count = followerCounts[_followerIndex];
    _followerIndex++;
    return LiveStackingResult(
      width: finalResult.width,
      height: finalResult.height,
      data: finalResult.data,
      stats: LiveStackingStats(stackedFrameCount: count),
    );
  }

  @override
  Future<LiveStackingResult> getCurrentResult() async => finalResult;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used in this test');
}

/// A [StackLightSelector] stand-in returning a scripted selection.
class _FakeSelector implements StackLightSelector {
  _FakeSelector(this.summary);

  final StackSelectionSummary summary;

  @override
  Future<StackSelectionSummary> selectForSession({
    required int sessionId,
    required StackAndShareConfig config,
  }) async =>
      summary;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used in this test');
}

/// Build a selection with [followerCount] followers after a single reference.
/// Frame ids run 1..N; frame 1 is the reference. Paths are `/lights/N.fits`.
StackSelectionSummary _selection({
  required int followerCount,
  String filter = 'L',
  String targetName = 'M51',
}) {
  final frames = <StackedFrameSelection>[
    StackedFrameSelection(
      imageId: 1,
      filePath: '/lights/1.fits',
      filter: filter,
      isReference: true,
    ),
    for (var i = 2; i <= followerCount + 1; i++)
      StackedFrameSelection(
        imageId: i,
        filePath: '/lights/$i.fits',
        filter: filter,
      ),
  ];
  return StackSelectionSummary(
    selected: frames,
    referencePath: '/lights/1.fits',
    perFilterCounts: {filter: frames.length},
    totalIntegrationSecs: frames.length * 60.0,
    targetName: targetName,
  );
}

LiveStackingResult _integrated({int stackedFrameCount = 3}) => LiveStackingResult(
      width: 2,
      height: 2,
      data: const [10, 20, 30, 40],
      stats: LiveStackingStats(
        stackedFrameCount: stackedFrameCount,
        avgAlignmentResidual: 0.37,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late int sessionId;

  setUp(() async {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    // Seed a session so getSessionById resolves. No targetId is set: a real
    // target row would need a foreign-key parent, and the orchestrator only
    // reads `session.targetId` straight through onto the result — the display
    // target *name* comes from the selector, which we fake.
    sessionId = await SessionsDao(db).startSession();
  });

  tearDown(() async {
    await db.close();
  });

  /// Build a provider container wiring the real DB, a fake selector, a fake
  /// live-stacking service, and (optionally) overriding the calibration /
  /// dark-library providers. Returns the container; the caller constructs the
  /// service with the injected [engine].
  ProviderContainer container({
    required StackSelectionSummary selection,
    required LiveStackingService liveStacking,
    List<Override> extra = const [],
  }) {
    return ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      stackLightSelectorProvider.overrideWithValue(_FakeSelector(selection)),
      liveStackingServiceProvider.overrideWithValue(liveStacking),
      ...extra,
    ]);
  }

  group('busy guard', () {
    test('throws LiveStackBusyException when the engine reports active',
        () async {
      final engine = _FakeStackingEngine(active: true);
      final c = container(
        selection: _selection(followerCount: 2),
        liveStacking: _FakeLiveStacking(
          followerCounts: const [2, 3],
          finalResult: _integrated(),
        ),
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      await expectLater(
        service.run(
          sessionId: sessionId,
          config: const StackAndShareConfig(applyCalibration: false),
        ),
        throwsA(isA<LiveStackBusyException>()),
      );
      // The guard fires before any engine work and before any stop — we must
      // not touch a singleton owned by the live session we refused to clobber.
      expect(engine.calls, isEmpty);
      expect(engine.stopCount, 0);
    });
  });

  group('happy path (calibration off → file path)', () {
    test('processes the reference first, then followers in order, and stops',
        () async {
      final engine = _FakeStackingEngine();
      final live = _FakeLiveStacking(
        followerCounts: const [2, 3], // both followers accepted
        finalResult: _integrated(stackedFrameCount: 3),
      );
      final c = container(
        selection: _selection(followerCount: 2),
        liveStacking: live,
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      final progress = <StackAndShareProgress>[];
      final result = await service.run(
        sessionId: sessionId,
        config: const StackAndShareConfig(
          applyCalibration: false,
          autoStretch: true,
        ),
        onProgress: progress.add,
      );

      // (b) The reference (frame 1) starts the stack via the FILE path, then
      // the two followers (frames 2, 3) are added via the file path in order,
      // then the engine is stopped.
      expect(engine.calls, [
        'startFile:/lights/1.fits',
        'stretch',
        'stop',
      ]);
      expect(live.addCalls, [
        'addFile:/lights/2.fits',
        'addFile:/lights/3.fits',
      ]);

      // (d) Stop — not reset — was invoked exactly once so a later run is not
      // blocked by a wedged singleton.
      expect(engine.stopCount, 1);

      // Result provenance: target resolved from the seeded session, integration
      // from the selection, alignment residual + stacked count from the engine.
      expect(result.id, isNotNull);
      expect(result.targetId, isNull); // session was seeded with no target
      expect(result.targetName, 'M51'); // resolved by the selector
      expect(result.framesStacked, 3);
      expect(result.framesAttempted, 3);
      expect(result.integrationSecs, 180);
      expect(result.avgAlignmentResidual, closeTo(0.37, 1e-9));
      expect(result.filter, 'L');

      // The persisted row carries the same data, and the retained buffers are
      // exposed for the export step.
      final stored =
          await c.read(stackedResultsDaoProvider).getResultById(result.id!);
      expect(stored, isNotNull);
      expect(service.lastRawResult, isNotNull);
      expect(service.lastRawResult!.data, Uint16List.fromList([10, 20, 30, 40]));
      expect(service.lastRgbaResult, isNotNull); // auto-stretch ran

      // The terminal progress event is the success phase.
      expect(progress.last.phase, StackAndSharePhase.complete);
    });

    test('auto-stretch off leaves the RGBA buffer unset', () async {
      final engine = _FakeStackingEngine();
      final c = container(
        selection: _selection(followerCount: 1),
        liveStacking: _FakeLiveStacking(
          followerCounts: const [2],
          finalResult: _integrated(stackedFrameCount: 2),
        ),
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      await service.run(
        sessionId: sessionId,
        config: const StackAndShareConfig(
          applyCalibration: false,
          autoStretch: false,
        ),
      );

      expect(engine.calls, isNot(contains('stretch')));
      expect(service.lastRawResult, isNotNull);
      expect(service.lastRgbaResult, isNull);
    });
  });

  group('frame rejection accounting (c)', () {
    test('framesRejected increments only when the stacked count does not advance',
        () async {
      final engine = _FakeStackingEngine();
      // Reference = count 1. Follower #2 advances to 2 (accepted). Follower #3
      // stays at 2 (rejected — alignment/pixel rejection). Follower #4 advances
      // to 3 (accepted).
      final live = _FakeLiveStacking(
        followerCounts: const [2, 2, 3],
        finalResult: _integrated(stackedFrameCount: 3),
      );
      final c = container(
        selection: _selection(followerCount: 3),
        liveStacking: live,
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      final progress = <StackAndShareProgress>[];
      await service.run(
        sessionId: sessionId,
        config: const StackAndShareConfig(applyCalibration: false),
        onProgress: progress.add,
      );

      // Exactly one follower was rejected.
      final terminalStacking = progress.lastWhere(
        (p) => p.phase == StackAndSharePhase.stacking,
      );
      expect(terminalStacking.framesRejected, 1);
      expect(terminalStacking.framesProcessed, 4); // reference + 3 followers
    });
  });

  group('release on failure (d)', () {
    test('stops the engine even when a mid-run step throws, and surfaces the '
        'original error', () async {
      // getCurrentResult throws after the frames are stacked: the finally must
      // still stop the engine, and the original error must propagate (not be
      // masked by the stop).
      final engine = _FakeStackingEngine();
      final live = _ThrowingLiveStacking(
        followerCounts: const [2],
        error: StateError('integration blew up'),
      );
      final c = container(
        selection: _selection(followerCount: 1),
        liveStacking: live,
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      final progress = <StackAndShareProgress>[];
      await expectLater(
        service.run(
          sessionId: sessionId,
          config: const StackAndShareConfig(applyCalibration: false),
          onProgress: progress.add,
        ),
        throwsA(isA<StateError>()),
      );

      // The engine was stopped despite the failure.
      expect(engine.stopCount, 1);
      expect(engine.calls.last, 'stop');
      // The terminal progress event is the error phase, and retained buffers
      // are cleared so a failed run never exposes stale output.
      expect(progress.last.phase, StackAndSharePhase.error);
      expect(service.lastRawResult, isNull);
      expect(service.lastRgbaResult, isNull);
    });

    test('a subsequent run succeeds because stop released the singleton',
        () async {
      // First run fails; because the finally called stop (not reset), the
      // engine reports inactive again and a second run passes the busy guard.
      final engine = _FakeStackingEngine();
      final failing = _ThrowingLiveStacking(
        followerCounts: const [2],
        error: StateError('first run failed'),
      );
      final c1 = container(
        selection: _selection(followerCount: 1),
        liveStacking: failing,
      );
      addTearDown(c1.dispose);
      final s1 = StackAndShareService(c1.read(_refProvider), engine: engine);
      await expectLater(
        s1.run(
          sessionId: sessionId,
          config: const StackAndShareConfig(applyCalibration: false),
        ),
        throwsA(isA<StateError>()),
      );

      // The fake engine's `active` flag was never flipped true by our fake (a
      // real stop sets the native guard to None), so a fresh service still sees
      // it inactive and runs to completion.
      expect(engine.isActive(), isFalse);

      final live2 = _FakeLiveStacking(
        followerCounts: const [2],
        finalResult: _integrated(stackedFrameCount: 2),
      );
      final c2 = container(
        selection: _selection(followerCount: 1),
        liveStacking: live2,
      );
      addTearDown(c2.dispose);
      final s2 = StackAndShareService(c2.read(_refProvider), engine: engine);
      final result = await s2.run(
        sessionId: sessionId,
        config: const StackAndShareConfig(applyCalibration: false),
      );
      expect(result.id, isNotNull);
      // Two runs → two stops.
      expect(engine.stopCount, 2);
    });
  });

  group('calibration path split (e)', () {
    test('calibration on uses the data path (readLinearFrame + startData)',
        () async {
      final engine = _FakeStackingEngine();
      final live = _FakeLiveStacking(
        followerCounts: const [2],
        finalResult: _integrated(stackedFrameCount: 2),
      );
      // No dark/flat/bias is configured (the real in-memory DB has no
      // calibration settings), and the selection's image ids have no captured-
      // images rows, so the dark match resolves to none and `calibrateData`
      // becomes a pure pass-through. That still proves the DATA path is taken:
      // each frame's linear pixels are read and fed via startData / addData.
      final c = container(
        selection: _selection(followerCount: 1),
        liveStacking: live,
      );
      addTearDown(c.dispose);
      final service = StackAndShareService(c.read(_refProvider), engine: engine);

      await service.run(
        sessionId: sessionId,
        config: const StackAndShareConfig(
          applyCalibration: true,
          autoStretch: false,
        ),
      );

      // The reference is read + started via the DATA path, and the follower is
      // read + added via the DATA path. No file-path calls.
      expect(engine.calls, contains('read:/lights/1.fits'));
      expect(engine.calls, contains('startData:2x2'));
      expect(engine.calls.any((c) => c.startsWith('startFile')), isFalse);
      expect(live.addCalls, contains('addData:2x2'));
      expect(live.addCalls.any((c) => c.startsWith('addFile')), isFalse);
      expect(engine.stopCount, 1);
    });
  });
}

/// A [LiveStackingService] fake whose [getCurrentResult] throws, used to prove
/// the finally still releases the engine on a mid-run failure.
class _ThrowingLiveStacking extends _FakeLiveStacking {
  _ThrowingLiveStacking({
    required super.followerCounts,
    required this.error,
  }) : super(finalResult: _integrated());

  final Object error;

  @override
  Future<LiveStackingResult> getCurrentResult() async => throw error;
}

/// Exposes the enclosing container's [Ref] so services that take a `Ref` can be
/// constructed against the test overrides.
final _refProvider = Provider<Ref>((ref) => ref);
