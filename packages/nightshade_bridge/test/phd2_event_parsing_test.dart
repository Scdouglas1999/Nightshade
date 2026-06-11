/// Behavioral tests for [Phd2Client] event parsing and the guiding-state machine.
///
/// The client is driven against a real loopback [FakePhd2Server] (no hardware,
/// no external network). We register a canned `get_app_state` response so the
/// `connect()` handshake resolves, then push PHD2 event lines and assert the
/// resulting [Phd2State] transitions, derived statistics, and event stream.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/src/phd2_client.dart';

import 'fakes/fake_phd2_server.dart';

void main() {
  late FakePhd2Server server;
  late Phd2Client client;

  setUp(() async {
    server = await FakePhd2Server.start();
    // The connect handshake issues `get_app_state`; answer it so connect()
    // resolves without waiting on the 30s RPC timeout.
    server.respondTo('get_app_state', 'Stopped');
    client = Phd2Client(host: server.host, port: server.port);
    // Never auto-reconnect in unit tests.
    client.setAutoReconnect(false);
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  /// Push a PHD2 event line and wait for the client to emit the matching
  /// [Phd2Event] on its broadcast stream, returning that event.
  Future<Phd2Event> pushEvent(Map<String, dynamic> json) async {
    final next = client.events.firstWhere((e) => e.event == json['Event']);
    server.sendJson(json);
    return next.timeout(const Duration(seconds: 2));
  }

  group('Phd2Client connection handshake', () {
    test('connect transitions to connected and applies app state', () async {
      final states = <Phd2ConnectionState>[];
      final sub = client.connectionStateStream.listen(states.add);

      await client.connect();

      expect(client.isConnected, true);
      expect(client.connectionState, Phd2ConnectionState.connected);
      expect(states, contains(Phd2ConnectionState.connecting));
      expect(states, contains(Phd2ConnectionState.connected));
      // get_app_state response ('Stopped') was applied.
      expect(client.state, Phd2State.stopped);
      await sub.cancel();
    });

    test('connect is idempotent while already connected', () async {
      await client.connect();
      final before = server.requests.length;
      await client.connect();
      // No new handshake request issued on the second call.
      expect(server.requests.length, before);
    });
  });

  group('Phd2Client event -> state machine', () {
    setUp(() async {
      await client.connect();
    });

    test('StarSelected -> selected', () async {
      await pushEvent({'Event': 'StarSelected'});
      expect(client.state, Phd2State.selected);
      expect(client.statusMessage, contains('selected'));
    });

    test('GuidingStarted -> guiding', () async {
      await pushEvent({'Event': 'GuidingStarted'});
      expect(client.state, Phd2State.guiding);
    });

    test('Settling -> settling then SettleDone(success) -> guiding', () async {
      await pushEvent({'Event': 'Settling'});
      expect(client.state, Phd2State.settling);

      await pushEvent({'Event': 'SettleDone', 'Status': 0});
      expect(client.state, Phd2State.guiding);
      expect(client.statusMessage, contains('Settled'));
    });

    test('SettleDone with error keeps failure message', () async {
      await pushEvent({'Event': 'Settling'});
      await pushEvent({'Event': 'SettleDone', 'Error': 'star lost'});
      expect(client.statusMessage, contains('Settle failed'));
      expect(client.statusMessage, contains('star lost'));
    });

    test('StarLost -> lostLock', () async {
      await pushEvent({'Event': 'GuidingStarted'});
      await pushEvent({'Event': 'StarLost'});
      expect(client.state, Phd2State.lostLock);
      expect(client.statusMessage, contains('lost'));
    });

    test('Paused -> paused then Resumed -> guiding', () async {
      await pushEvent({'Event': 'Paused'});
      expect(client.state, Phd2State.paused);
      await pushEvent({'Event': 'Resumed'});
      expect(client.state, Phd2State.guiding);
    });

    test('LoopingExposures -> looping', () async {
      await pushEvent({'Event': 'LoopingExposures'});
      expect(client.state, Phd2State.looping);
    });

    test('AppState event maps Calibrating', () async {
      await pushEvent({'Event': 'AppState', 'State': 'Calibrating'});
      expect(client.state, Phd2State.calibrating);
    });

    test('GuidingStopped resets state and RMS statistics', () async {
      // Feed some guide steps so RMS is non-zero.
      await pushEvent({
        'Event': 'GuideStep',
        'RADistanceRaw': 1.0,
        'DECDistanceRaw': 1.0,
        'SNR': 20.0,
        'StarMass': 5000.0,
      });
      expect(client.rmsTotal, greaterThan(0));

      await pushEvent({'Event': 'GuidingStopped'});
      expect(client.state, Phd2State.stopped);
      expect(client.rmsRa, 0);
      expect(client.rmsDec, 0);
      expect(client.rmsTotal, 0);
    });
  });

  group('Phd2Client GuideStep statistics', () {
    setUp(() async {
      await client.connect();
    });

    test('parses SNR and star mass from a guide step', () async {
      await pushEvent({
        'Event': 'GuideStep',
        'RADistanceRaw': 0.5,
        'DECDistanceRaw': 0.3,
        'SNR': 42.5,
        'StarMass': 12345.0,
      });
      expect(client.snr, 42.5);
      expect(client.starMass, 12345.0);
    });

    test('computes total RMS as pythagorean combination of axes', () async {
      // Single step: per-axis RMS equals the raw distance magnitude, so
      // total = sqrt(ra^2 + dec^2).
      await pushEvent({
        'Event': 'GuideStep',
        'RADistanceRaw': 3.0,
        'DECDistanceRaw': 4.0,
        'SNR': 10.0,
        'StarMass': 1000.0,
      });
      expect(client.rmsRa, closeTo(3.0, 1e-9));
      expect(client.rmsDec, closeTo(4.0, 1e-9));
      expect(client.rmsTotal, closeTo(5.0, 1e-9));
    });

    test('falls back to AvgDist for total RMS with a small window', () async {
      await pushEvent({
        'Event': 'GuideStep',
        'RADistanceRaw': 1.0,
        'DECDistanceRaw': 1.0,
        'SNR': 10.0,
        'StarMass': 1000.0,
        'AvgDist': 0.77,
      });
      // Fewer than 10 samples -> PHD2's AvgDist is preferred for total RMS.
      expect(client.rmsTotal, closeTo(0.77, 1e-9));
    });
  });

  group('Phd2Client malformed input resilience', () {
    setUp(() async {
      await client.connect();
    });

    test('malformed JSON line does not crash the client', () async {
      server.sendLine('{ this is not json ]');
      // Client must still process a subsequent valid event.
      await pushEvent({'Event': 'GuidingStarted'});
      expect(client.isConnected, true);
      expect(client.state, Phd2State.guiding);
    });

    test('non-object JSON line is ignored', () async {
      server.sendLine('[1, 2, 3]');
      await pushEvent({'Event': 'StarSelected'});
      expect(client.state, Phd2State.selected);
    });

    test('event without an Event field is ignored without error', () async {
      server.sendLine('{"Timestamp": 123.4}');
      await pushEvent({'Event': 'GuidingStarted'});
      expect(client.state, Phd2State.guiding);
    });

    test('two events arriving in one packet are both processed', () async {
      // Send two complete lines in a single write.
      server.sendLine('{"Event":"StarSelected"}');
      await pushEvent({'Event': 'GuidingStarted'});
      expect(client.state, Phd2State.guiding);
    });
  });
}
