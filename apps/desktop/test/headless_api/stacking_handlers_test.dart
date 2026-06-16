// Regression tests for the host-side live-stacking coordinator
// (StackingHandlers). The novel, bug-prone logic is the arm → reference →
// auto-feed sequence: a remote client arms the host with no reference frame,
// then the FIRST `ImageSaved` event becomes the reference (startFromFile) and
// every subsequent saved frame is added (addFrameFromFile). These tests pin
// that orchestration with a fake LiveStackingService so it can't regress.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/stacking_handlers.dart';
import 'package:shelf/shelf.dart';

/// Records what the coordinator asks the stacker to do, without touching FFI.
class _FakeStackingService extends LiveStackingService {
  _FakeStackingService(super.ref);

  final List<String> started = [];
  final List<String> added = [];
  int resets = 0;
  int stops = 0;
  bool _active = false;

  @override
  Future<LiveStackingStats> startFromFile({
    required String referenceImagePath,
    LiveStackingConfig config = const LiveStackingConfig(),
  }) async {
    started.add(referenceImagePath);
    _active = true;
    return LiveStackingStats(stackedFrameCount: 1, totalFramesAttempted: 1);
  }

  @override
  Future<LiveStackingResult> addFrameFromFile(String imagePath) async {
    added.add(imagePath);
    return LiveStackingResult(
      width: 2,
      height: 2,
      channels: 1,
      data: const [0, 0, 0, 0],
      stats: LiveStackingStats(
        stackedFrameCount: 1 + added.length,
        totalFramesAttempted: 1 + added.length,
      ),
    );
  }

  @override
  Future<void> reset() async {
    // Mirror the native engine: reset is invalid before the first frame
    // initializes the stacker.
    if (!_active) throw StateError('Live stacker not initialized');
    resets++;
  }

  @override
  Future<void> stop() async {
    if (!_active) throw StateError('Live stacker not initialized');
    stops++;
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get frameCount => _active ? 1 + added.length : 0;

  @override
  Future<LiveStackingStats> getStats() async {
    if (!_active) throw StateError('Live stacker not initialized');
    return LiveStackingStats(stackedFrameCount: 1 + added.length);
  }

  @override
  Future<LiveStackingResult> getCurrentResult() async => LiveStackingResult(
    width: 2,
    height: 2,
    channels: 1,
    data: const [10, 20, 30, 40],
    stats: LiveStackingStats(stackedFrameCount: 1 + added.length),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LoggingService logger;
  late ProviderContainer container;
  late _FakeStackingService fake;
  late StackingHandlers handlers;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_stacking_test_');
    logger = LoggingService(
      applicationSupportDirectoryProvider: () async => tempDir,
      nativeInitWithLogging: ({logDirectory}) {},
      nativeInit: () {},
      currentLogFileProvider: () => null,
    );
    await logger.ensureInitialized();
    container = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(logger),
        liveStackingServiceProvider.overrideWith(
          (ref) => fake = _FakeStackingService(ref),
        ),
      ],
    );
    // Force creation so `fake` is assigned before the tests use it.
    container.read(liveStackingServiceProvider);
    handlers = StackingHandlers(container);
  });

  tearDown(() async {
    container.dispose();
    await logger.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Request post(String path, [Object? body]) => Request(
    'POST',
    Uri.parse('http://localhost$path'),
    body: body == null ? null : jsonEncode(body),
  );

  test('arm → first saved frame is the reference, rest are added', () async {
    final startResp = await handlers.handleStart(post('/api/stacking/start'));
    expect(startResp.statusCode, 200);
    expect(jsonDecode(await startResp.readAsString())['status'], 'armed');
    expect(fake.started, isEmpty, reason: 'arming must not start the stacker');

    await handlers.onImageSaved('/host/frame_0001.fits');
    await handlers.onImageSaved('/host/frame_0002.fits');
    await handlers.onImageSaved('/host/frame_0003.fits');

    expect(fake.started, [
      '/host/frame_0001.fits',
    ], reason: 'first saved frame becomes the reference');
    expect(fake.added, [
      '/host/frame_0002.fits',
      '/host/frame_0003.fits',
    ], reason: 'subsequent frames are added, not re-referenced');
  });

  test('no auto-feed before arming or after stop', () async {
    // Not armed yet → ignored.
    await handlers.onImageSaved('/host/ignored.fits');
    expect(fake.started, isEmpty);
    expect(fake.added, isEmpty);

    await handlers.handleStart(post('/api/stacking/start'));
    await handlers.onImageSaved('/host/ref.fits');
    expect(fake.started, ['/host/ref.fits']);

    final stopResp = await handlers.handleStop(post('/api/stacking/stop'));
    expect(stopResp.statusCode, 200);
    expect(fake.stops, 1);

    // After stop, further saved frames are ignored.
    await handlers.onImageSaved('/host/after_stop.fits');
    expect(fake.added, isEmpty);
  });

  test('stop while armed-but-not-started does not touch the engine', () async {
    // Regression for the live-smoke 500: arming without a reference frame never
    // initializes the native stacker, so stop must not call into it. It should
    // just disarm cleanly.
    await handlers.handleStart(post('/api/stacking/start'));

    // stats while armed-but-not-started must report zeroes, not 500.
    final statsResp = await handlers.handleStats(
      Request('GET', Uri.parse('http://localhost/api/stacking/stats')),
    );
    expect(statsResp.statusCode, 200);
    final statsBody = jsonDecode(await statsResp.readAsString()) as Map;
    expect((statsBody['stats'] as Map)['stackedFrameCount'], 0);

    final resp = await handlers.handleStop(post('/api/stacking/stop'));
    expect(resp.statusCode, 200);
    expect(
      fake.stops,
      0,
      reason: 'engine.stop must not run when never started',
    );

    // Same guard on reset: armed-but-not-started must not call into the engine.
    // (handleStart itself resets internally, so measure the delta across the
    // explicit reset call rather than an absolute count.)
    await handlers.handleStart(post('/api/stacking/start'));
    final resetsBefore = fake.resets;
    final resetResp = await handlers.handleReset(post('/api/stacking/reset'));
    expect(resetResp.statusCode, 200);
    expect(
      fake.resets,
      resetsBefore,
      reason: 'engine.reset must not run when never started',
    );
    await handlers.handleStop(post('/api/stacking/stop'));

    final status =
        jsonDecode(
              await (await handlers.handleStatus(
                Request(
                  'GET',
                  Uri.parse('http://localhost/api/stacking/status'),
                ),
              )).readAsString(),
            )
            as Map<String, dynamic>;
    expect(status['armed'], false);
  });

  test('explicit referencePath starts immediately', () async {
    final resp = await handlers.handleStart(
      post('/api/stacking/start', {'referencePath': '/host/ref.fits'}),
    );
    expect(resp.statusCode, 200);
    expect(jsonDecode(await resp.readAsString())['status'], 'started');
    expect(fake.started, ['/host/ref.fits']);
  });

  test('status + preview reflect the live stack', () async {
    await handlers.handleStart(post('/api/stacking/start'));
    await handlers.onImageSaved('/host/ref.fits');
    await handlers.onImageSaved('/host/f2.fits');

    final status =
        jsonDecode(
              await (await handlers.handleStatus(
                Request(
                  'GET',
                  Uri.parse('http://localhost/api/stacking/status'),
                ),
              )).readAsString(),
            )
            as Map<String, dynamic>;
    expect(status['active'], true);
    expect(status['armed'], true);
    expect(status['started'], true);

    final preview = await handlers.handlePreview(
      Request('GET', Uri.parse('http://localhost/api/stacking/preview')),
    );
    expect(preview.statusCode, 200);
    expect(preview.headers['x-stack-width'], '2');
    expect(preview.headers['x-stack-height'], '2');
    expect(preview.headers['x-stack-endian'], 'little');
    final bytes = await preview.read().expand((c) => c).toList();
    // 4 u16 samples (10,20,30,40) little-endian = 8 bytes.
    expect(bytes.length, 8);
    expect(bytes.sublist(0, 2), [10, 0]); // 10 as LE u16
  });
}
