/// Tests for [AlpacaClient] REST envelope parsing and error mapping.
///
/// [AlpacaClient] builds its own `http.Client` internally (no injectable seam),
/// so we stand up a tiny loopback [HttpServer] that speaks the ASCOM Alpaca
/// envelope (`Value` / `ErrorNumber` / `ErrorMessage`) and point a real
/// [AlpacaDevice] at it. We cover envelope unwrapping, Alpaca error mapping to
/// [AlpacaException], HTTP-status failures, and ClientTransactionID propagation.
///
/// Each test uses a unique device id because [AlpacaClient] shares circuit
/// breakers per device id through a process-wide registry.

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Records a single HTTP request the server saw.
class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final String body;
}

/// A loopback Alpaca server. Each inbound request is answered with the JSON
/// produced by [responder]; requests are recorded for assertions.
class _FakeAlpacaServer {
  _FakeAlpacaServer._(this._server);

  final HttpServer _server;
  final List<_RecordedRequest> requests = [];

  /// Returns a (statusCode, jsonBody) pair for a given request.
  late ({int status, Object? body}) Function(_RecordedRequest req) responder;

  static Future<_FakeAlpacaServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeAlpacaServer._(httpServer);
    server._listen();
    return server;
  }

  int get port => _server.port;
  String get host => _server.address.address;

  void _listen() {
    _server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final recorded = _RecordedRequest(
        request.method,
        request.uri.path,
        request.uri.queryParameters,
        body,
      );
      requests.add(recorded);
      final result = responder(recorded);
      request.response.statusCode = result.status;
      request.response.headers.contentType = ContentType.json;
      if (result.body != null) {
        request.response.write(jsonEncode(result.body));
      }
      await request.response.close();
    });
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late _FakeAlpacaServer server;
  int idCounter = 0;

  /// Build a client pointing at the fake server, with a unique device id so the
  /// shared circuit-breaker registry never carries state between tests.
  AlpacaClient buildClient({String deviceType = 'camera'}) {
    final device = AlpacaDevice(
      deviceName: 'Test',
      deviceType: deviceType,
      deviceNumber: ++idCounter,
      uniqueId: 'unit-test-$idCounter-${DateTime.now().microsecondsSinceEpoch}',
      server: AlpacaServer(host: server.host, port: server.port),
    );
    return AlpacaClient(device);
  }

  setUp(() async {
    server = await _FakeAlpacaServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  group('envelope parsing', () {
    test('GET unwraps Value from a success envelope', () async {
      server.responder = (_) => (
        status: 200,
        body: {
          'Value': true,
          'ErrorNumber': 0,
          'ErrorMessage': '',
          'ClientTransactionID': 1,
        },
      );
      final client = buildClient();
      final result = await client.get('connected');
      expect(result['Value'], true);
      client.dispose();
    });

    test('connected getter coerces the boolean Value', () async {
      server.responder = (_) =>
          (status: 200, body: {'Value': true, 'ErrorNumber': 0});
      final client = buildClient();
      expect(await client.connected, true);
      client.dispose();
    });

    test('numeric Value survives the envelope round-trip', () async {
      server.responder = (_) =>
          (status: 200, body: {'Value': -12.5, 'ErrorNumber': 0});
      final client = AlpacaCameraClient(
        AlpacaDevice(
          deviceName: 'Cam',
          deviceType: 'camera',
          deviceNumber: ++idCounter,
          uniqueId: 'cam-temp-$idCounter',
          server: AlpacaServer(host: server.host, port: server.port),
        ),
      );
      expect(await client.ccdTemperature, closeTo(-12.5, 1e-9));
      client.dispose();
    });
  });

  group('error mapping', () {
    test('non-zero ErrorNumber maps to AlpacaException', () async {
      server.responder = (_) => (
        status: 200,
        body: {
          'Value': null,
          'ErrorNumber': 1025,
          'ErrorMessage': 'Invalid value',
        },
      );
      final client = buildClient();
      await expectLater(
        client.get('gain'),
        throwsA(
          isA<AlpacaException>().having(
            (e) => e.message,
            'message',
            allOf(contains('1025'), contains('Invalid value')),
          ),
        ),
      );
      client.dispose();
    });

    test('HTTP non-200 maps to AlpacaException with status', () async {
      server.responder = (_) => (status: 500, body: null);
      final client = buildClient();
      await expectLater(
        client.get('connected'),
        throwsA(
          isA<AlpacaException>().having(
            (e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
      client.dispose();
    });
  });

  group('request construction', () {
    test(
      'GET includes ClientID and an incrementing ClientTransactionID',
      () async {
        server.responder = (_) =>
            (status: 200, body: {'Value': true, 'ErrorNumber': 0});
        final client = buildClient();
        await client.get('connected');
        await client.get('connected');

        final gets = server.requests.where((r) => r.method == 'GET').toList();
        expect(gets, hasLength(2));
        expect(gets[0].query['ClientID'], isNotNull);
        final txn0 = int.parse(gets[0].query['ClientTransactionID']!);
        final txn1 = int.parse(gets[1].query['ClientTransactionID']!);
        expect(txn1, txn0 + 1);
        client.dispose();
      },
    );

    test('GET path targets the device API base url', () async {
      server.responder = (_) =>
          (status: 200, body: {'Value': true, 'ErrorNumber': 0});
      final client = buildClient(deviceType: 'telescope');
      await client.get('tracking');
      final req = server.requests.single;
      expect(req.method, 'GET');
      expect(req.path, contains('/api/v1/telescope/'));
      expect(req.path, endsWith('/tracking'));
      client.dispose();
    });

    test('PUT sends form body with ClientID and the supplied params', () async {
      server.responder = (_) =>
          (status: 200, body: {'ErrorNumber': 0, 'ErrorMessage': ''});
      final client = buildClient();
      await client.put('connected', {'Connected': 'true'});
      final put = server.requests.firstWhere((r) => r.method == 'PUT');
      final form = Uri.splitQueryString(put.body);
      expect(form['Connected'], 'true');
      expect(form['ClientID'], isNotNull);
      expect(form['ClientTransactionID'], isNotNull);
      client.dispose();
    });
  });
}
