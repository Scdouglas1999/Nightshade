/// Wire-framing tests for [Phd2Client].
///
/// PHD2 speaks line-delimited JSON over TCP, and TCP gives no guarantee that a
/// line arrives in one read. These tests drive a real loopback socket and split
/// a single JSON frame across two segments, plus feed a multi-byte UTF-8
/// payload, so the client's receive path is exercised the way a real PHD2
/// `get_star_image` reply exercises it.

library;

import 'dart:convert';

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

  group('Phd2Client frame reassembly', () {
    test('an event split across two TCP segments is parsed', () async {
      final line = jsonEncode({
        'Event': 'GuideStep',
        'RADistanceRaw': 3.0,
        'DECDistanceRaw': 4.0,
        'SNR': 42.5,
        'StarMass': 12345.0,
      });
      final next = client.events.firstWhere((e) => e.event == 'GuideStep');

      final split = line.length ~/ 2;
      await server.sendChunk(line.substring(0, split));
      await server.sendChunk('${line.substring(split)}\r\n');

      await next.timeout(const Duration(seconds: 2));
      expect(client.snr, 42.5);
      expect(client.starMass, 12345.0);
    });

    test(
      'an RPC reply split across two TCP segments completes the request',
      () async {
        final pending = client.getAlgoParamNames(axis: 'x');
        // Request 1 is the connect handshake's get_app_state.
        await server.awaitRequests(2);
        final id = server.requests.last['id'];

        final line = jsonEncode({
          'jsonrpc': '2.0',
          'result': ['MinMove', 'Aggression'],
          'id': id,
        });
        final split = line.length ~/ 2;
        await server.sendChunk(line.substring(0, split));
        await server.sendChunk('${line.substring(split)}\r\n');

        expect(await pending.timeout(const Duration(seconds: 2)), [
          'MinMove',
          'Aggression',
        ]);
      },
    );

    test('a frame split mid multi-byte UTF-8 character survives', () async {
      // Split the payload between the two bytes of 'é' (0xC3 0xA9).
      final bytes = utf8.encode(
        '${jsonEncode({'Event': 'SettleDone', 'Error': 'étoile perdue'})}\r\n',
      );
      final marker = bytes.indexOf(0xC3);
      expect(marker, greaterThan(0), reason: 'fixture must contain é');

      final next = client.events.firstWhere((e) => e.event == 'SettleDone');
      await server.sendRawBytes(bytes.sublist(0, marker + 1));
      await server.sendRawBytes(bytes.sublist(marker + 1));

      final event = await next.timeout(const Duration(seconds: 2));
      expect(event.data['Error'], 'étoile perdue');
      expect(client.statusMessage, contains('étoile perdue'));
    });

    test('a whole-frame UTF-8 payload is decoded, not byte-widened', () async {
      final next = client.events.firstWhere((e) => e.event == 'SettleDone');
      server.sendJson({'Event': 'SettleDone', 'Error': 'étoile perdue'});

      final event = await next.timeout(const Duration(seconds: 2));
      expect(event.data['Error'], 'étoile perdue');
    });
  });
}
