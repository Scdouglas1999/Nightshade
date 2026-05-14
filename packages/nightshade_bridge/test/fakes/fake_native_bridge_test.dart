// Smoke tests for FakeNativeBridge itself. The point is to lock in the four
// behavior contracts the harness depends on:
//   1. Permissive defaults for unconfigured calls
//   2. Canned responses via setResponse
//   3. Error injection via setError
//   4. Broadcast event injection + sequencer filtering
//   5. Call recording for assertions in widget tests
//
// Widget-test coverage of real screens lives in CQ-W5-WIDGET-TESTS-*.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_bridge/src/bridge_stub.dart' as bridge_stub;

import 'fake_native_bridge.dart';

void main() {
  late FakeNativeBridge fake;

  setUp(() {
    fake = FakeNativeBridge();
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('default behavior', () {
    test('discoverDevices returns empty list when nothing configured',
        () async {
      final result = await fake.discoverDevices(DeviceType.camera);
      expect(result, isEmpty);
    });

    test('getCameraStatus returns a disconnected default', () async {
      final status = await fake.getCameraStatus('cam-1');
      expect(status.connected, isFalse);
      expect(status.state, CameraState.idle);
    });

    test('getMountStatus returns a parked, disconnected default', () async {
      final status = await fake.getMountStatus('mount-1');
      expect(status.connected, isFalse);
      expect(status.parked, isTrue);
    });

    test('getConnectedDevices defaults to empty', () async {
      expect(await fake.getConnectedDevices(), isEmpty);
    });

    test('isDeviceConnected defaults to false', () async {
      expect(await fake.isDeviceConnected(DeviceType.camera, 'x'), isFalse);
    });

    test('isNativeAvailable defaults to true (matches loaded bridge)', () {
      expect(fake.isNativeAvailable, isTrue);
    });

    test('void methods complete normally without throwing', () async {
      // Smoke-test a few representative void methods.
      await fake.startExposure(
        deviceId: 'cam',
        durationSecs: 1.0,
        gain: 100,
        offset: 10,
        binX: 1,
        binY: 1,
      );
      await fake.mountPark('mount');
      await fake.sequencerStart();
      await fake.endSession();
    });

    test('plateSolveBlind throws StateError when no response is wired',
        () async {
      // Explicit failure required because there is no neutral default.
      await expectLater(
        fake.plateSolveBlind('foo.fits'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('setResponse', () {
    test('overrides default for discoverDevices', () async {
      final devices = [
        const DeviceInfo(
          id: 'fake:cam:1',
          name: 'Fake Camera',
          deviceType: DeviceType.camera,
          driverType: DriverType.simulator,
          description: 'unit test',
          driverVersion: '1.0',
          displayName: 'Fake Camera',
        ),
      ];
      fake.setResponse('discoverDevices', devices);

      final result = await fake.discoverDevices(DeviceType.camera);
      expect(result, hasLength(1));
      expect(result.first.id, 'fake:cam:1');
    });

    test('overrides primitives (mountGetTrackingRate)', () async {
      fake.setResponse('mountGetTrackingRate', 2); // 2 = solar
      expect(await fake.mountGetTrackingRate('m1'), 2);
    });

    test('overrides nullable returns (getLastImage stays null)', () async {
      expect(await fake.getLastImage(deviceId: 'cam'), isNull);
    });

    test('cast mismatch throws TypeError (errors are a feature)', () async {
      fake.setResponse('discoverDevices', 'not a list');
      await expectLater(
        fake.discoverDevices(DeviceType.camera),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('setError', () {
    test('throws the injected exception', () async {
      fake.setError(
        'connectDevice',
        Exception('simulated connection refused'),
      );

      await expectLater(
        fake.connectDevice(DeviceType.camera, 'cam'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('simulated connection refused'),
          ),
        ),
      );
    });

    test('clearError removes the injection', () async {
      fake.setError('mountPark', Exception('boom'));
      await expectLater(fake.mountPark('m1'), throwsA(isA<Exception>()));

      fake.clearError('mountPark');
      // Should complete normally now.
      await fake.mountPark('m1');
    });

    test('error injection takes precedence over canned response', () async {
      fake.setResponse('mountGetTrackingRate', 3);
      fake.setError('mountGetTrackingRate', StateError('explicit'));

      await expectLater(
        fake.mountGetTrackingRate('m1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('event stream', () {
    test('eventStream is broadcast and delivers emitted events', () async {
      final received = <NightshadeEvent>[];
      final sub1 = fake.eventStream().listen(received.add);
      final sub2 = fake.eventStream().listen((_) {}); // second listener

      final evt = fake.makeEvent(category: EventCategory.equipment);
      fake.emitEvent(evt);
      // Broadcast streams dispatch asynchronously; let the microtask queue drain.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.eventId, evt.eventId);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('sequencerEventStream filters by category', () async {
      final received = <NightshadeEvent>[];
      final sub = fake.sequencerEventStream().listen(received.add);

      fake.emitEvent(fake.makeEvent(category: EventCategory.equipment));
      fake.emitEvent(fake.makeEvent(category: EventCategory.sequencer));
      fake.emitEvent(fake.makeEvent(category: EventCategory.guiding));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.category, EventCategory.sequencer);

      await sub.cancel();
    });

    test('makeEvent issues monotonically increasing IDs', () {
      final e1 = fake.makeEvent(category: EventCategory.system);
      final e2 = fake.makeEvent(category: EventCategory.system);
      final e3 = fake.makeEvent(category: EventCategory.system);

      expect(e2.eventId, greaterThan(e1.eventId));
      expect(e3.eventId, greaterThan(e2.eventId));
    });
  });

  group('call recording', () {
    test('captures method name + args in order', () async {
      await fake.connectDevice(DeviceType.camera, 'cam-1');
      await fake.startExposure(
        deviceId: 'cam-1',
        durationSecs: 30.0,
        gain: 100,
        offset: 10,
        binX: 1,
        binY: 1,
      );
      await fake.mountSlewToCoordinates('mount-1', 5.5, 12.3);

      expect(fake.recordedCalls.map((c) => c.method).toList(), [
        'connectDevice',
        'startExposure',
        'mountSlewToCoordinates',
      ]);

      final slew = fake.recordedCalls.last;
      expect(slew.args['deviceId'], 'mount-1');
      expect(slew.args['ra'], 5.5);
      expect(slew.args['dec'], 12.3);
    });

    test('callsTo / callCount filter by method name', () async {
      await fake.mountPark('m1');
      await fake.mountPark('m2');
      await fake.mountUnpark('m1');

      expect(fake.callCount('mountPark'), 2);
      expect(fake.callCount('mountUnpark'), 1);
      expect(fake.callCount('mountAbort'), 0);

      final parks = fake.callsTo('mountPark');
      expect(parks.first.args['deviceId'], 'm1');
      expect(parks.last.args['deviceId'], 'm2');
    });

    test('reset clears calls/responses/errors but keeps the stream alive',
        () async {
      fake.setResponse('mountGetTrackingRate', 3);
      fake.setError('mountPark', Exception('x'));
      await fake.mountUnpark('m1');

      fake.reset();

      expect(fake.recordedCalls, isEmpty);
      expect(await fake.mountGetTrackingRate('m1'), 0); // back to default
      await fake.mountPark('m1'); // no error injection
      // Stream should still accept events post-reset.
      final received = <NightshadeEvent>[];
      final sub = fake.eventStream().listen(received.add);
      fake.emitEvent(fake.makeEvent(category: EventCategory.system));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await sub.cancel();
    });
  });

  group('dispose', () {
    test('using fake after dispose throws StateError', () async {
      await fake.dispose();
      expect(
        () => fake.emitEvent(
          fake.makeEvent(category: EventCategory.system),
        ),
        // makeEvent itself is safe to call (no _ensureLive), but emitEvent is not.
        throwsA(isA<StateError>()),
      );
      // Re-create so the tearDown dispose() is idempotent.
      fake = FakeNativeBridge();
    });

    test('double dispose is a no-op', () async {
      await fake.dispose();
      await fake.dispose();
      fake = FakeNativeBridge();
    });
  });

  group('static-default sanity', () {
    test('default RotatorStatus has the correct shape', () async {
      final s = await fake.apiGetRotatorStatus(deviceId: 'rot');
      expect(s.connected, isFalse);
      expect(s.position, 0.0);
      expect(s.moving, isFalse);
      expect(s.canReverse, isTrue);
    });

    test('default SequencerStatus is idle / 0%', () async {
      final s = await fake.sequencerGetStatus();
      expect(s.state, 'idle');
      expect(s.progress, 0.0);
    });

    test('default getSequencerState is idle', () {
      expect(fake.getSequencerState(), bridge_stub.SequencerState.idle);
    });
  });
}
