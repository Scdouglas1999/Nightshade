/// Tests for [Phd2Client] JSON-RPC request/response correlation.
///
/// Drives the client against a loopback [FakePhd2Server], verifying that:
///   - public command methods serialize the expected method + params,
///   - responses are correlated back to the awaiting future by `id`,
///   - RPC error responses surface as exceptions,
///   - response payloads are coerced into the right return types.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/src/phd2_client.dart';

import 'fakes/fake_phd2_server.dart';

void main() {
  late FakePhd2Server server;
  late Phd2Client client;

  setUp(() async {
    server = await FakePhd2Server.start();
    server.respondTo('get_app_state', 'Stopped');
    client = Phd2Client(host: server.host, port: server.port);
    client.setAutoReconnect(false);
    await client.connect();
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  /// The most recent request whose method matches [method].
  Map<String, dynamic> lastRequestFor(String method) =>
      server.requests.lastWhere((r) => r['method'] == method);

  group('request serialization', () {
    test('startGuiding sends guide with settle params', () async {
      server.respondTo('guide', 0);
      await client.startGuiding(settlePixels: 2.0, settleTime: 8.0);
      final req = lastRequestFor('guide');
      final params = req['params'] as Map<String, dynamic>;
      final settle = params['settle'] as Map<String, dynamic>;
      expect(settle['pixels'], 2.0);
      expect(settle['time'], 8.0);
      expect(params['recalibrate'], false);
    });

    test('pauseGuiding sends positional [true, "full"]', () async {
      server.respondTo('set_paused', 0);
      await client.pauseGuiding();
      final req = lastRequestFor('set_paused');
      expect(req['params'], [true, 'full']);
    });

    test('setExposure converts seconds to milliseconds', () async {
      server.respondTo('set_exposure', 0);
      await client.setExposure(2.5);
      final req = lastRequestFor('set_exposure');
      expect(req['params'], [2500]);
    });

    test('setLockPosition sends positional [x, y, exact]', () async {
      server.respondTo('set_lock_position', 0);
      await client.setLockPosition(x: 100.0, y: 200.0, exact: true);
      final req = lastRequestFor('set_lock_position');
      expect(req['params'], [100.0, 200.0, true]);
    });

    test('setAlgoParam sends named axis/name/value', () async {
      server.respondTo('set_algo_param', 0);
      await client.setAlgoParam(axis: 'x', name: 'MinMove', value: 0.15);
      final req = lastRequestFor('set_algo_param');
      expect(req['params'], {'axis': 'x', 'name': 'MinMove', 'value': 0.15});
    });
  });

  group('response correlation and coercion', () {
    test('getPixelScale returns the numeric result', () async {
      server.respondTo('get_pixel_scale', 1.23);
      expect(await client.getPixelScale(), closeTo(1.23, 1e-9));
    });

    test('getExposure converts ms result to seconds', () async {
      server.respondTo('get_exposure', 3000);
      expect(await client.getExposure(), closeTo(3.0, 1e-9));
    });

    test('getLockPosition parses [x, y] array', () async {
      server.respondTo('get_lock_position', [12.0, 34.0]);
      final pos = await client.getLockPosition();
      expect(pos.$1, 12.0);
      expect(pos.$2, 34.0);
    });

    test('findStar parses returned coordinate pair', () async {
      server.respondTo('find_star', [50.5, 60.5]);
      final pos = await client.findStar();
      expect(pos.$1, 50.5);
      expect(pos.$2, 60.5);
    });

    test('getAlgoParamNames casts list of strings', () async {
      server.respondTo('get_algo_param_names', ['MinMove', 'Aggressiveness']);
      expect(await client.getAlgoParamNames(axis: 'x'), [
        'MinMove',
        'Aggressiveness',
      ]);
    });

    test('getCalibrationData returns map or null', () async {
      server.respondTo('get_calibration_data', {'calibrated': true});
      final data = await client.getCalibrationData();
      expect(data, isNotNull);
      expect(data!['calibrated'], true);
    });

    test('concurrent requests correlate by id, not arrival order', () async {
      server.respondTo('get_pixel_scale', 2.0);
      server.respondTo('get_exposure', 5000);
      // Issue both before awaiting either.
      final scaleFuture = client.getPixelScale();
      final exposureFuture = client.getExposure();
      final scale = await scaleFuture;
      final exposure = await exposureFuture;
      expect(scale, 2.0);
      expect(exposure, 5.0);
    });
  });

  group('error handling', () {
    test('RPC error response throws', () async {
      // No canned result for this method; reply with an explicit JSON-RPC
      // error once the request lands.
      final future = client.getPixelScale();
      await server.awaitRequests(server.requests.length + 1);
      final req = lastRequestFor('get_pixel_scale');
      server.sendError(req['id'] as Object, 1, 'unavailable');
      await expectLater(future, throwsA(isA<Exception>()));
    });

    test('isCameraConnected swallows errors and returns false', () async {
      final future = client.isCameraConnected();
      await server.awaitRequests(server.requests.length + 1);
      final req = lastRequestFor('get_connected');
      server.sendError(req['id'] as Object, 2, 'no camera');
      expect(await future, false);
    });

    test('getLockPosition throws on malformed (non-array) result', () async {
      server.respondTo('get_lock_position', 'oops');
      await expectLater(client.getLockPosition(), throwsA(isA<StateError>()));
    });
  });
}
