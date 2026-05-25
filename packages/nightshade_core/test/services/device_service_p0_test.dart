import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/disconnected_backend.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    hide CameraState;
import 'package:nightshade_core/src/models/backend/device_types.dart'
    as device_types;
import 'package:nightshade_core/src/models/equipment/equipment_models.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';
import 'package:nightshade_core/src/services/device_exceptions.dart';
import 'package:nightshade_core/src/services/device_service.dart';

import '../mocks/mock_backend.dart';

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend initial) : super(ref) {
    state = initial;
  }
}

void main() {
  late ProviderContainer container;
  late MockBackend mockBackend;
  late StreamController<NightshadeEvent> eventStreamController;

  setUpAll(() {
    registerMocktailFallbackValues();
  });

  setUp(() {
    mockBackend = MockBackend();
    eventStreamController = StreamController<NightshadeEvent>.broadcast();

    when(() => mockBackend.eventStream)
        .thenAnswer((_) => eventStreamController.stream);
    when(() => mockBackend.polarAlignmentEvents)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockBackend.getConnectedDevices()).thenAnswer((_) async => []);
    when(() => mockBackend.cameraGetRecommendedSettings(any())).thenAnswer(
      (_) async => const CameraRecommendedSettings(notes: ''),
    );
    when(() => mockBackend.getCameraStatus(any())).thenAnswer(
      (_) async => const CameraStatus(
        connected: true,
        state: device_types.CameraState.idle,
        coolerOn: false,
        gain: 0,
        offset: 0,
        binX: 1,
        binY: 1,
        sensorWidth: 0,
        sensorHeight: 0,
        pixelSizeX: 0,
        pixelSizeY: 0,
        maxAdu: 65535,
        canCool: false,
        canSetGain: false,
        canSetOffset: false,
      ),
    );
    when(
      () => mockBackend.startDeviceHeartbeat(
        deviceType: any(named: 'deviceType'),
        deviceId: any(named: 'deviceId'),
        intervalMs: any(named: 'intervalMs'),
      ),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, mockBackend),
        ),
      ],
    );
    container.read(deviceServiceProvider);
  });

  tearDown(() {
    eventStreamController.close();
    container.dispose();
  });

  group('DV-P0-3: user-initiated disconnect suppresses auto-reconnect', () {
    test('disconnectCamera prevents reconnect after Disconnected event',
        () async {
      const deviceId = TestFixtures.cameraId;

      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting(deviceId, 'Test Camera');
      camNotifier.setConnected();

      when(() => mockBackend.stopDeviceHeartbeat(deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.disconnectCamera();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'camera',
          'device_id': deviceId,
        },
      ));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      verifyNever(
        () => mockBackend.connectDevice(DeviceType.camera, deviceId),
      );
    });
  });

  group('DV-P0-7: notifier disconnect always reaches disconnected state', () {
    test('CameraStateNotifier.disconnect clears state when backend throws',
        () async {
      const deviceId = TestFixtures.cameraId;

      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting(deviceId, 'Test Camera');
      camNotifier.setConnected();

      when(() => mockBackend.stopDeviceHeartbeat(deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.camera, deviceId))
          .thenThrow(Exception('INDI driver rejected disconnect'));

      await camNotifier.disconnect();

      final state = container.read(cameraStateProvider);
      expect(state.connectionState, DeviceConnectionState.disconnected);
      expect(state.deviceId, isNull);
    });

    test('mount StateNotifier.disconnect clears state when backend throws',
        () async {
      const deviceId = TestFixtures.mountId;

      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting(deviceId, 'Test Mount');
      mountNotifier.setConnected();

      when(() => mockBackend.stopDeviceHeartbeat(deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.mount, deviceId))
          .thenThrow(Exception('COM disconnect failed'));

      await mountNotifier.disconnect();

      expect(
        container.read(mountStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
    });
  });

  group('DV-P0-8: event stream onError resubscribes', () {
    test('equipment events continue after stream error', () async {
      const deviceId = TestFixtures.mountId;

      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting(deviceId, 'Test Mount');
      mountNotifier.setConnected();

      eventStreamController.addError(Exception('transient stream fault'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'mount',
          'device_id': deviceId,
        },
      ));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(mountStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
    });
  });

  group('DV-P0-1: backend swap resets equipment notifiers', () {
    test('disconnect clears connected camera state', () async {
      const deviceId = TestFixtures.cameraId;

      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting(deviceId, 'Test Camera');
      camNotifier.setConnected();

      await container.read(backendProvider.notifier).disconnect();

      expect(
        container.read(cameraStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
      expect(container.read(backendProvider), isA<DisconnectedBackend>());
    });
  });

  group('DV-P0-2: backend swap waits for in-flight operations', () {
    test('disconnect waits for connect operation before swapping backend',
        () async {
      const deviceId = TestFixtures.cameraId;
      final connectCompleter = Completer<void>();

      when(() => mockBackend.getConnectedDevices()).thenAnswer((_) async => [
            const DeviceInfo(
              id: deviceId,
              name: 'Test Camera',
              deviceType: DeviceType.camera,
              driverType: DriverType.ascom,
              description: 'Test camera',
              driverVersion: '1.0',
            ),
          ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) => connectCompleter.future);

      final service = container.read(deviceServiceProvider);
      final connectFuture = service.connectCamera(deviceId);
      await Future<void>.delayed(Duration.zero);

      final disconnectFuture =
          container.read(backendProvider.notifier).disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(backendProvider), same(mockBackend));

      connectCompleter.complete();
      await connectFuture;
      await disconnectFuture;

      expect(container.read(backendProvider), isA<DisconnectedBackend>());
      expect(
        container.read(cameraStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
    });
  });

  group('DV-P0-4: connect avoids discovery sweeps', () {
    test('connectCamera uses connected-device lookup for display name only',
        () async {
      const deviceId = TestFixtures.cameraId;

      when(() => mockBackend.getConnectedDevices()).thenAnswer((_) async => [
            const DeviceInfo(
              id: deviceId,
              name: 'Known Camera',
              deviceType: DeviceType.camera,
              driverType: DriverType.ascom,
              description: 'Test camera',
              driverVersion: '1.0',
            ),
          ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(deviceId);

      verifyNever(() => mockBackend.discoverDevices(DeviceType.camera));
      expect(container.read(cameraStateProvider).deviceName, 'Known Camera');
    });
  });

  group('DV-P0-5: connectProfile sequential abort', () {
    test('stops after first failure and emits progress', () async {
      const cameraId = TestFixtures.cameraId;
      const mountId = TestFixtures.mountId;

      when(() => mockBackend.connectDevice(DeviceType.camera, cameraId))
          .thenThrow(Exception('camera unreachable'));
      when(() => mockBackend.connectDevice(DeviceType.mount, mountId))
          .thenAnswer((_) async {});

      final progress = <DeviceConnectProgress>[];
      final service = container.read(deviceServiceProvider);

      await expectLater(
        service.connectProfile(
          cameraId: cameraId,
          mountId: mountId,
          onProgress: progress.add,
        ),
        throwsA(isA<Exception>()),
      );

      expect(progress, hasLength(2));
      expect(progress.first.status, DeviceConnectProgressStatus.connecting);
      expect(progress.last.status, DeviceConnectProgressStatus.failed);
      verifyNever(
        () => mockBackend.connectDevice(DeviceType.mount, mountId),
      );
    });
  });

  group('XC-P0-4: critical disconnect checkpoints before pause', () {
    test(
        'running sequence saves checkpoint before pausing on camera disconnect',
        () async {
      const deviceId = TestFixtures.cameraId;
      final callOrder = <String>[];

      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      container.read(cameraStateProvider.notifier)
        ..setAutoReconnect(false)
        ..setConnecting(deviceId, 'Test Camera')
        ..setConnected();

      when(() => mockBackend.saveCheckpoint()).thenAnswer((_) async {
        callOrder.add('checkpoint');
      });
      when(() => mockBackend.sequencerPause()).thenAnswer((_) async {
        callOrder.add('pause');
      });

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'camera',
          'device_id': deviceId,
        },
      ));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callOrder, ['checkpoint', 'pause']);
    });

    test('paused sequence saves checkpoint without issuing another pause',
        () async {
      const deviceId = TestFixtures.mountId;

      container.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.paused;
      container.read(mountStateProvider.notifier)
        ..setAutoReconnect(false)
        ..setConnecting(deviceId, 'Test Mount')
        ..setConnected();

      when(() => mockBackend.saveCheckpoint()).thenAnswer((_) async {});
      when(() => mockBackend.sequencerPause()).thenAnswer((_) async {});

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'mount',
          'device_id': deviceId,
        },
      ));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      verify(() => mockBackend.saveCheckpoint()).called(1);
      verifyNever(() => mockBackend.sequencerPause());
    });
  });
}
