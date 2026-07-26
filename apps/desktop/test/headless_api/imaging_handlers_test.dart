import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/imaging_handlers.dart';
import 'package:nightshade_desktop/headless_api/job_manager.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('ImagingHandlers', () {
    late ProviderContainer container;
    late ImagingHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = ImagingHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('star crops missing device ID returns JSON bad request', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetStarCrops(
          Request('GET', Uri.parse('http://localhost/api/imaging/star-crops')),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], "Missing 'deviceId' query parameter");
    });

    test(
      'star crops validates maxCrops and trims deviceId before backend work',
      () async {
        final backend = _StarCropBackend();
        final local = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _TestBackendNotifier(ref, backend),
            ),
          ],
        );
        addTearDown(local.dispose);
        final localHandlers = ImagingHandlers(local);

        for (final raw in ['abc', '0', '-1', '201', '1.5']) {
          final response = await translateHandlerErrors(
            localHandlers.handleGetStarCrops(
              Request(
                'GET',
                Uri.parse(
                  'http://localhost/api/imaging/star-crops?deviceId=cam-1'
                  '&maxCrops=${Uri.encodeQueryComponent(raw)}',
                ),
              ),
            ),
          );
          expect(response.statusCode, HttpStatus.badRequest, reason: raw);
        }
        expect(backend.calls, 0);

        final blank = await translateHandlerErrors(
          localHandlers.handleGetStarCrops(
            Request(
              'GET',
              Uri.parse(
                'http://localhost/api/imaging/star-crops?deviceId=%20%20',
              ),
            ),
          ),
        );
        expect(blank.statusCode, HttpStatus.badRequest);
        expect(backend.calls, 0);

        final valid = await translateHandlerErrors(
          localHandlers.handleGetStarCrops(
            Request(
              'GET',
              Uri.parse(
                'http://localhost/api/imaging/star-crops'
                '?deviceId=%20cam-1%20&maxCrops=200',
              ),
            ),
          ),
        );
        expect(valid.statusCode, HttpStatus.ok);
        expect(backend.calls, 1);
        expect(backend.deviceId, 'cam-1');
        expect(backend.maxCrops, 200);
      },
    );

    test('plate solve malformed payload returns JSON internal error', () async {
      final response = await translateHandlerErrors(
        handlers.handlePlateSolve(
          Request(
            'POST',
            Uri.parse('http://localhost/api/plate-solve'),
            body: jsonEncode({}),
          ),
        ),
      );

      expect(
        response.statusCode,
        anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
      );
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test(
      'raw image invalid backend call returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleGetLastRawImageData(
            Request(
              'GET',
              Uri.parse('http://localhost/api/imaging/raw?deviceId=camera-1'),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );

    test('raw image serializes every pixel as little-endian u16', () async {
      final backend = _RawImageBackend([0, 1, 255, 256, 0x1234, 0xffff]);
      final local = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(local.dispose);
      final response = await ImagingHandlers(local).handleGetLastRawImageData(
        Request(
          'GET',
          Uri.parse('http://localhost/api/imaging/raw-data?deviceId=camera-1'),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/octet-stream');
      expect(response.headers['content-length'], '12');
      expect(await response.read().expand((chunk) => chunk).toList(), [
        0x00,
        0x00,
        0x01,
        0x00,
        0xff,
        0x00,
        0x00,
        0x01,
        0x34,
        0x12,
        0xff,
        0xff,
      ]);
      expect(backend.deviceId, 'camera-1');
    });

    test('save from capture creates host parent directories first', () async {
      final backend = _SaveFitsBackend();
      final root = await Directory.systemTemp.createTemp(
        'nightshade-save-fits-',
      );
      addTearDown(() => root.delete(recursive: true));
      final local = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref, backend),
          ),
          appSettingsProvider.overrideWith(
            () => _TestSettingsWithOutputPath(root.path),
          ),
        ],
      );
      addTearDown(local.dispose);
      await local.read(appSettingsProvider.future);
      final localHandlers = ImagingHandlers(local);
      final filePath = '${root.path}/2026-07-13/L/flat-1.fits';

      final response = await translateHandlerErrors(
        localHandlers.handleSaveFitsFromLastCapture(
          Request(
            'POST',
            Uri.parse('http://localhost/api/imaging/save-fits-from-capture'),
            body: jsonEncode({
              'deviceId': 'camera-1',
              'filePath': filePath,
              'headerData': {
                'frameType': 'FLAT',
                'filter': 'L',
                'exposureTime': 1.5,
                'captureTimestamp': '2026-07-13T01:00:00Z',
              },
            }),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(backend.filePath, filePath);
      expect(backend.parentExistedAtSave, isTrue);
    });

    test('save from capture rejects paths outside configured roots', () async {
      final backend = _SaveFitsBackend();
      final allowedRoot = await Directory.systemTemp.createTemp(
        'nightshade-save-fits-allowed-',
      );
      final outsideRoot = await Directory.systemTemp.createTemp(
        'nightshade-save-fits-outside-',
      );
      addTearDown(() => allowedRoot.delete(recursive: true));
      addTearDown(() => outsideRoot.delete(recursive: true));
      final local = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref, backend),
          ),
          appSettingsProvider.overrideWith(
            () => _TestSettingsWithOutputPath(allowedRoot.path),
          ),
        ],
      );
      addTearDown(local.dispose);
      await local.read(appSettingsProvider.future);
      final localHandlers = ImagingHandlers(local);
      final outsideParent = Directory('${outsideRoot.path}/unexpected');
      final filePath = '${outsideParent.path}/flat-1.fits';

      final response = await translateHandlerErrors(
        localHandlers.handleSaveFitsFromLastCapture(
          Request(
            'POST',
            Uri.parse('http://localhost/api/imaging/save-fits-from-capture'),
            body: jsonEncode({
              'deviceId': 'camera-1',
              'filePath': filePath,
              'headerData': {
                'frameType': 'FLAT',
                'exposureTime': 1.5,
                'captureTimestamp': '2026-07-13T01:00:00Z',
              },
            }),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.forbidden);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'path_not_allowed');
      expect(backend.calls, 0);
      expect(await outsideParent.exists(), isFalse);
    });

    test('cancelled plate solve stays running until host work exits', () async {
      final backend = _PendingPlateSolveBackend();
      final jobContainer = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref, backend),
          ),
          appSettingsProvider.overrideWith(_TestSettings.new),
        ],
      );
      addTearDown(jobContainer.dispose);
      final jobs = JobManager(emitEvent: (_) {});
      addTearDown(jobs.dispose);
      final jobHandlers = ImagingHandlers(jobContainer, jobManager: jobs);

      final response = await jobHandlers.handlePlateSolve(
        Request(
          'POST',
          Uri.parse('http://localhost/api/plate-solve'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'imagePath': '/tmp/pending.fits'}),
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      final jobId = body['jobId'] as String;
      await _pumpUntil(() => jobs.get(jobId)?.state == JobState.running);

      jobs.cancel(jobId);
      await Future<void>.delayed(Duration.zero);

      expect(backend.started, isTrue);
      expect(jobs.get(jobId)?.state, JobState.running);
    });
  });
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _PendingPlateSolveBackend extends DisconnectedBackend {
  final Completer<PlateSolveResult> pending = Completer<PlateSolveResult>();
  bool started = false;

  @override
  Future<PlateSolverDetection> detectPlateSolvers() async {
    return const PlateSolverDetection(
      astapPath: '/tmp/astap',
      catalogPath: '/tmp/catalog',
    );
  }

  @override
  Future<PlateSolverPreference> getPlateSolverConfig() async {
    return const PlateSolverPreference(choice: PlateSolverChoice.astap);
  }

  @override
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
    int? timeoutSeconds,
  }) {
    started = true;
    return pending.future;
  }
}

class _StarCropBackend extends DisconnectedBackend {
  int calls = 0;
  String? deviceId;
  int? maxCrops;

  @override
  Future<List<StarCrop>> getStarCropsFromLastImage(
    String deviceId, {
    int maxCrops = 5,
  }) async {
    calls++;
    this.deviceId = deviceId;
    this.maxCrops = maxCrops;
    return const [];
  }
}

class _RawImageBackend extends DisconnectedBackend {
  _RawImageBackend(this.pixels);

  final List<int> pixels;
  String? deviceId;

  @override
  Future<List<int>> getLastRawImageData(String deviceId) async {
    this.deviceId = deviceId;
    return pixels;
  }
}

class _SaveFitsBackend extends DisconnectedBackend {
  String? filePath;
  bool parentExistedAtSave = false;
  int calls = 0;

  @override
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  }) async {
    calls++;
    this.filePath = filePath;
    parentExistedAtSave = File(filePath).parent.existsSync();
  }
}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

class _TestSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState();
}

class _TestSettingsWithOutputPath extends AppSettingsNotifier {
  _TestSettingsWithOutputPath(this.outputPath);

  final String outputPath;

  @override
  Future<AppSettingsState> build() async =>
      AppSettingsState(imageOutputPath: outputPath);
}
