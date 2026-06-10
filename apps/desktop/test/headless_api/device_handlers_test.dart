import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/device_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  // Why these overrides:
  //   1. Every handler calls `_logInfo()`, which reads
  //      `loggingServiceProvider`. The production provider kicks off
  //      `unawaited(LoggingService.ensureInitialized())`, which invokes
  //      `getApplicationSupportDirectory()` (platform channel) and
  //      `bridge_api.apiInitWithLogging` (FFI cdylib). Both fail in a unit
  //      test. The async failure surfaces as an unhandled-error and the
  //      test runner attributes it to whichever test happens to still be
  //      in scope, producing a flaky `+N -1`.
  //   2. `handleFilterWheelGetPosition` reads `filterWheelStateProvider`,
  //      whose `FilterWheelStateNotifier` constructor calls
  //      `_ref.listen(activeEquipmentProfileProvider, ...)`. That chain
  //      mounts `equipmentProfilesNotifier` -> `databaseProvider`, and
  //      the default Drift `LazyDatabase` opens via
  //      `getApplicationDocumentsDirectory()` — another path_provider
  //      channel call that throws MissingPluginException in unit tests.
  //
  // Fix: install a TestWidgetsFlutterBinding (so plumbing exists), then
  // wire hermetic substitutes for both providers (in-memory DB +
  // no-FFI LoggingService). Together these eliminate every cross-test
  // microtask source identified above.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceHandlers', () {
    late Directory loggerTempDir;
    late LoggingService logger;
    late NightshadeDatabase db;
    late ProviderContainer container;
    late DeviceHandlers handlers;

    setUp(() async {
      loggerTempDir = await Directory.systemTemp.createTemp(
        'ns_device_handlers_test_',
      );
      logger = LoggingService(
        applicationSupportDirectoryProvider: () async => loggerTempDir,
        nativeInitWithLogging: ({logDirectory}) {},
        nativeInit: () {},
        currentLogFileProvider: () => null,
      );
      await logger.ensureInitialized();
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());

      container = ProviderContainer(
        overrides: [
          loggingServiceProvider.overrideWithValue(logger),
          databaseProvider.overrideWithValue(db),
        ],
      );
      handlers = DeviceHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await logger.dispose();
      await db.close();
      if (await loggerTempDir.exists()) {
        await loggerTempDir.delete(recursive: true);
      }
    });

    test(
      'camera expose malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleCameraExpose(
            Request(
              'POST',
              Uri.parse('http://localhost/api/camera/expose'),
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
      },
    );

    test('mount slew malformed payload returns JSON internal error', () async {
      final response = await translateHandlerErrors(
        handlers.handleMountSlew(
          Request(
            'POST',
            Uri.parse('http://localhost/api/mount/slew'),
            body: jsonEncode({'deviceId': 'mount-1'}),
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

    test('last image jpeg missing deviceId returns bad request', () async {
      final response = await translateHandlerErrors(
        handlers.handleCameraGetLastImageJpeg(
          Request(
            'GET',
            Uri.parse('http://localhost/api/camera/last-image/jpeg'),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test(
      'rotator halt malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleRotatorHalt(
            Request(
              'POST',
              Uri.parse('http://localhost/api/rotator/halt'),
              body: '{',
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

    test('filter wheel get position returns 200 with null fields when '
        'disconnected', () async {
      // Why: with no driver connected (the bare ProviderContainer state),
      // FilterWheelStateNotifier reports
      // (currentPosition=null, isMoving=false, filterNames=[]). The
      // handler should still respond 200 with `position: null,
      // name: null, isMoving: false` — disconnection is not an error,
      // it's a real state phones need to render.
      final response = await translateHandlerErrors(
        handlers.handleFilterWheelGetPosition(
          Request(
            'GET',
            Uri.parse('http://localhost/api/filter-wheel/position'),
          ),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['position'], isNull);
      expect(body['name'], isNull);
      expect(body['isMoving'], isFalse);
    });
  });
}
