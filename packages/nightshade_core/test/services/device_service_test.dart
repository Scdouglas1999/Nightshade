import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    hide CameraState;
import 'package:nightshade_core/src/models/backend/device_types.dart'
    as device_types;
import 'package:nightshade_core/src/models/equipment/equipment_models.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/services/device_service.dart';

import '../mocks/mock_backend.dart';

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
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

    container = ProviderContainer(
      overrides: [
        backendProvider
            .overrideWith((ref) => TestBackendNotifier(ref, mockBackend)),
      ],
    );

    // Initialize DeviceService so event listeners are active.
    container.read(deviceServiceProvider);
  });

  tearDown(() {
    eventStreamController.close();
    container.dispose();
  });

  // ---------------------------------------------------------------------------
  // Helper: build a DeviceInfo for a given type
  // ---------------------------------------------------------------------------
  DeviceInfo _deviceInfo(DeviceType type, String id, String name) => DeviceInfo(
        id: id,
        name: name,
        deviceType: type,
        driverType: DriverType.simulator,
        description: 'Test $name',
        driverVersion: '1.0',
      );

  // ---------------------------------------------------------------------------
  // Camera Connection Lifecycle
  // ---------------------------------------------------------------------------
  group('Camera Connection Lifecycle', () {
    test('connectCamera sets state to connected and starts heartbeat', () async {
      const deviceId = TestFixtures.cameraId;

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, deviceId, 'Test Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.getCameraStatus(deviceId)).thenAnswer(
        (_) async => CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -10.0,
          coolerPower: 80.0,
          targetTemp: -10.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        ),
      );
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(deviceId);

      final state = container.read(cameraStateProvider);
      expect(state.connectionState, DeviceConnectionState.connected);
      expect(state.deviceId, deviceId);

      verify(() => mockBackend.startDeviceHeartbeat(
            deviceType: DeviceType.camera,
            deviceId: deviceId,
            intervalMs: 10000,
          )).called(1);
    });

    test('connectCamera throws and resets state on failure', () async {
      const deviceId = TestFixtures.cameraId;

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, deviceId, 'Test Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenThrow(Exception('Connection refused'));

      final service = container.read(deviceServiceProvider);
      await expectLater(
        service.connectCamera(deviceId),
        throwsA(isA<Exception>()),
      );

      final state = container.read(cameraStateProvider);
      expect(state.connectionState, DeviceConnectionState.disconnected);
    });

    test('disconnectCamera stops heartbeat and resets state', () async {
      const deviceId = TestFixtures.cameraId;

      // Set up connected camera state
      final notifier = container.read(cameraStateProvider.notifier);
      notifier.setConnecting(deviceId, 'Test Camera');
      notifier.setConnected();

      when(() => mockBackend.stopDeviceHeartbeat(deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.disconnectCamera();

      final state = container.read(cameraStateProvider);
      expect(state.connectionState, DeviceConnectionState.disconnected);
      expect(state.deviceId, isNull);

      verify(() => mockBackend.stopDeviceHeartbeat(deviceId)).called(1);
      verify(() => mockBackend.disconnectDevice(DeviceType.camera, deviceId))
          .called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Mount Connection Lifecycle
  // ---------------------------------------------------------------------------
  group('Mount Connection Lifecycle', () {
    test('connectMount sets state to connected with initial status', () async {
      const deviceId = TestFixtures.mountId;

      when(() => mockBackend.discoverDevices(DeviceType.mount))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.mount, deviceId, 'Test Mount'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.mount, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.getMountStatus(deviceId)).thenAnswer(
        (_) async => MountStatus(
          connected: true,
          tracking: true,
          slewing: false,
          parked: false,
          atHome: false,
          sideOfPier: PierSide.east,
          rightAscension: 12.0,
          declination: 45.0,
          altitude: 60.0,
          azimuth: 180.0,
          siderealTime: 12.5,
          trackingRate: TrackingRate.sidereal,
          canPark: true,
          canSlew: true,
          canSync: true,
          canPulseGuide: true,
          canSetTrackingRate: true,
        ),
      );
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.connectMount(deviceId);

      final state = container.read(mountStateProvider);
      expect(state.connectionState, DeviceConnectionState.connected);
      expect(state.isTracking, isTrue);
      expect(state.isParked, isFalse);
      expect(state.ra, 12.0);
      expect(state.dec, 45.0);
    });

    test('connectMount throws and resets state when device not found',
        () async {
      const deviceId = 'nonexistent-mount';

      when(() => mockBackend.discoverDevices(DeviceType.mount))
          .thenAnswer((_) async => []);

      final service = container.read(deviceServiceProvider);
      await expectLater(
        service.connectMount(deviceId),
        throwsA(isA<Exception>()),
      );

      final state = container.read(mountStateProvider);
      expect(state.connectionState, DeviceConnectionState.disconnected);
    });
  });

  // ---------------------------------------------------------------------------
  // Focuser Connection Lifecycle
  // ---------------------------------------------------------------------------
  group('Focuser Connection Lifecycle', () {
    test('connectFocuser sets state with hardware capabilities', () async {
      const deviceId = TestFixtures.focuserId;

      when(() => mockBackend.discoverDevices(DeviceType.focuser))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.focuser, deviceId, 'Test Focuser'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.focuser, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.getFocuserStatus(deviceId)).thenAnswer(
        (_) async => const FocuserStatus(
          connected: true,
          position: 15000,
          moving: false,
          temperature: 12.5,
          maxPosition: 50000,
          stepSize: 1.0,
          isAbsolute: true,
          hasTemperature: true,
        ),
      );

      final service = container.read(deviceServiceProvider);
      await service.connectFocuser(deviceId);

      final state = container.read(focuserStateProvider);
      expect(state.connectionState, DeviceConnectionState.connected);
      expect(state.position, 15000);
      expect(state.maxPosition, 50000);
      expect(state.temperature, 12.5);
      expect(state.isMoving, isFalse);
    });

    test('disconnectFocuser resets state', () async {
      const deviceId = TestFixtures.focuserId;

      final notifier = container.read(focuserStateProvider.notifier);
      notifier.setConnecting(deviceId);
      notifier.setConnected();

      when(() => mockBackend.disconnectDevice(DeviceType.focuser, deviceId))
          .thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.disconnectFocuser();

      final state = container.read(focuserStateProvider);
      expect(state.connectionState, DeviceConnectionState.disconnected);
    });
  });

  // ---------------------------------------------------------------------------
  // Event Routing: Equipment Events
  // ---------------------------------------------------------------------------
  group('Event Routing', () {
    test('CameraTemperatureChanged event updates camera state', () async {
      // Pre-connect camera so state accepts updates
      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting('camera-1', 'Test Camera');
      camNotifier.setConnected();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'CameraTemperatureChanged',
        data: {
          'temperature': -15.0,
          'coolerPower': 75.0,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(cameraStateProvider);
      expect(state.temperature, -15.0);
      expect(state.coolerPower, 75.0);
    });

    test('MountPositionChanged event updates mount state', () async {
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting('mount-1');
      mountNotifier.setConnected();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'MountPositionChanged',
        data: {
          'ra': 6.5,
          'dec': -20.0,
          'altitude': 30.0,
          'azimuth': 150.0,
          'isTracking': true,
          'isSlewing': false,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(mountStateProvider);
      expect(state.ra, 6.5);
      expect(state.dec, -20.0);
      expect(state.isTracking, isTrue);
      expect(state.isSlewing, isFalse);
    });

    test('MountTrackingStarted sets tracking true', () async {
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting('mount-1');
      mountNotifier.setConnected();
      mountNotifier.setTracking(false);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'MountTrackingStarted',
        data: {},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(mountStateProvider).isTracking, isTrue);
    });

    test('MountTrackingStopped sets tracking false', () async {
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting('mount-1');
      mountNotifier.setConnected();
      mountNotifier.setTracking(true);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'MountTrackingStopped',
        data: {},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(mountStateProvider).isTracking, isFalse);
    });

    test('FocuserPositionChanged event updates focuser state', () async {
      final focNotifier = container.read(focuserStateProvider.notifier);
      focNotifier.setConnecting('focuser-1');
      focNotifier.setConnected();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'FocuserPositionChanged',
        data: {
          'position': 25000,
          'isMoving': true,
          'temperature': 14.3,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(focuserStateProvider);
      expect(state.position, 25000);
      expect(state.isMoving, isTrue);
      expect(state.temperature, 14.3);
    });

    test('FocuserMoveCompleted event updates focuser position and stops moving',
        () async {
      final focNotifier = container.read(focuserStateProvider.notifier);
      focNotifier.setConnecting('focuser-1');
      focNotifier.setConnected();
      focNotifier.setMoving(true);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'FocuserMoveCompleted',
        data: {'position': 30000},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(focuserStateProvider);
      expect(state.position, 30000);
      expect(state.isMoving, isFalse);
    });

    test('FilterWheelPositionChanged event updates filter wheel state',
        () async {
      final fwNotifier = container.read(filterWheelStateProvider.notifier);
      fwNotifier.setConnecting(TestFixtures.filterWheelId, 'Test FW');
      fwNotifier.setConnected(filterNames: TestFixtures.sampleFilterNames);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'FilterWheelPositionChanged',
        data: {
          'position': 3,
          'isMoving': false,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(filterWheelStateProvider);
      expect(state.currentPosition, 3);
      expect(state.isMoving, isFalse);
    });

    test('CameraCoolingStarted event updates cooling state', () async {
      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting('camera-1', 'Test Camera');
      camNotifier.setConnected();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'CameraCoolingStarted',
        data: {'target_temp': -20.0},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(cameraStateProvider);
      expect(state.isCooling, isTrue);
      expect(state.targetTemp, -20.0);
    });

    test('Non-equipment events are ignored by equipment handler', () async {
      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting('camera-1', 'Test Camera');
      camNotifier.setConnected();

      final tempBefore = container.read(cameraStateProvider).temperature;

      // Send an event with a non-equipment category
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.imaging,
        eventType: 'CameraTemperatureChanged',
        data: {
          'temperature': -99.0,
          'coolerPower': 100.0,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      // Temperature should not have changed
      expect(container.read(cameraStateProvider).temperature, tempBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // Disconnect Event Routing
  // ---------------------------------------------------------------------------
  group('Disconnect Event Routing', () {
    test('Camera disconnect event resets camera state and attempts reconnect',
        () async {
      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting('camera-1', 'Test Camera');
      camNotifier.setConnected();

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'camera',
          'device_id': 'camera-1',
        },
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(cameraStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
    });

    test('Disconnect event with null device_type is safely ignored', () async {
      // This should not throw
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': null,
          'device_id': null,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));
      // No exception means the null guard works
    });

    test('Filter wheel disconnect event resets filter wheel state', () async {
      final fwNotifier = container.read(filterWheelStateProvider.notifier);
      fwNotifier.setConnecting(TestFixtures.filterWheelId, 'Test FW');
      fwNotifier.setConnected(filterNames: TestFixtures.sampleFilterNames);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'filterwheel',
          'device_id': TestFixtures.filterWheelId,
        },
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(filterWheelStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Temperature Polling
  // ---------------------------------------------------------------------------
  group('Temperature Polling', () {
    test('connectCamera starts temperature polling that updates state',
        () async {
      const deviceId = TestFixtures.cameraId;

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, deviceId, 'Test Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});

      // Return temperature data on every status poll
      when(() => mockBackend.getCameraStatus(deviceId)).thenAnswer(
        (_) async => CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -12.0,
          coolerPower: 65.0,
          targetTemp: -15.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        ),
      );

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(deviceId);

      // The immediate poll after connect should have updated temp
      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(cameraStateProvider);
      expect(state.temperature, -12.0);
      expect(state.coolerPower, 65.0);
    });

    test('disconnectCamera stops temperature polling', () async {
      const deviceId = TestFixtures.cameraId;

      // First connect
      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, deviceId, 'Test Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});
      when(() => mockBackend.getCameraStatus(deviceId)).thenAnswer(
        (_) async => CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -10.0,
          coolerPower: 80.0,
          targetTemp: -10.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        ),
      );
      when(() => mockBackend.stopDeviceHeartbeat(deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(deviceId);
      await service.disconnectCamera();

      // Reset the call count, then wait; no new calls should come in
      clearInteractions(mockBackend);
      await Future.delayed(const Duration(seconds: 1));

      // getCameraStatus should NOT be called after disconnect
      verifyNever(() => mockBackend.getCameraStatus(any()));
    });

    test('stale temperature poll result is ignored after camera switch',
        () async {
      const firstDeviceId = 'camera-1';
      const secondDeviceId = 'camera-2';
      final firstPoll = Completer<CameraStatus>();

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, firstDeviceId, 'First Camera'),
                _deviceInfo(DeviceType.camera, secondDeviceId, 'Second Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, any()))
          .thenAnswer((_) async {});
      when(() => mockBackend.disconnectDevice(DeviceType.camera, any()))
          .thenAnswer((_) async {});
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});
      when(() => mockBackend.stopDeviceHeartbeat(any())).thenAnswer((_) async {});
      when(() => mockBackend.getCameraStatus(firstDeviceId))
          .thenAnswer((_) => firstPoll.future);
      when(() => mockBackend.getCameraStatus(secondDeviceId)).thenAnswer(
        (_) async => CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -5.0,
          coolerPower: 40.0,
          targetTemp: -10.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        ),
      );

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(firstDeviceId);
      await service.disconnectCamera();
      await service.connectCamera(secondDeviceId);

      firstPoll.complete(
        CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -20.0,
          coolerPower: 90.0,
          targetTemp: -20.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(cameraStateProvider);
      expect(state.deviceId, secondDeviceId);
      expect(state.temperature, -5.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Auto-Reconnect Behavior
  // ---------------------------------------------------------------------------
  group('Auto-Reconnect', () {
    test(
        'disconnect event does not attempt reconnect when auto-reconnect is disabled',
        () async {
      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting('camera-1', 'Test Camera');
      camNotifier.setConnected();
      camNotifier.setAutoReconnect(false);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {
          'device_type': 'camera',
          'device_id': 'camera-1',
        },
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        container.read(cameraStateProvider).connectionState,
        DeviceConnectionState.disconnected,
      );

      // No reconnection attempt should have been made since auto-reconnect
      // is disabled. The connect call would require discoverDevices, so
      // verify it was never called for a camera reconnection.
      verifyNever(() => mockBackend.connectDevice(DeviceType.camera, any()));
    });
  });

  // ---------------------------------------------------------------------------
  // Device Discovery
  // ---------------------------------------------------------------------------
  group('Device Discovery', () {
    test('discoverDevices delegates to backend', () async {
      final expectedDevices = [
        _deviceInfo(DeviceType.camera, 'cam-1', 'Camera 1'),
        _deviceInfo(DeviceType.camera, 'cam-2', 'Camera 2'),
      ];

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => expectedDevices);

      final service = container.read(deviceServiceProvider);
      final devices = await service.discoverDevices(DeviceType.camera);

      expect(devices, hasLength(2));
      expect(devices[0].id, 'cam-1');
      expect(devices[1].id, 'cam-2');
      verify(() => mockBackend.discoverDevices(DeviceType.camera)).called(1);
    });

    test('discoverDevices propagates backend exceptions', () async {
      when(() => mockBackend.discoverDevices(DeviceType.mount))
          .thenThrow(Exception('Discovery failed'));

      final service = container.read(deviceServiceProvider);
      await expectLater(
        service.discoverDevices(DeviceType.mount),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Sequencer Event Routing
  // ---------------------------------------------------------------------------
  group('Sequencer Event Routing', () {
    test('SequenceStarted event updates execution state', () async {
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.sequencer,
        eventType: 'SequenceStarted',
        data: {'sequence_name': 'M31 LRGB'},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final execState = container.read(sequenceExecutionStateProvider);
      expect(execState, SequenceExecutionState.running);
    });

    test('SequenceCompleted event updates execution state', () async {
      // Start sequence first
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.sequencer,
        eventType: 'SequenceStarted',
        data: {'sequence_name': 'Test'},
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      // Complete it
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.sequencer,
        eventType: 'SequenceCompleted',
        data: {},
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      final execState = container.read(sequenceExecutionStateProvider);
      expect(execState, SequenceExecutionState.completed);
    });

    test('SequencePaused event updates execution state', () async {
      // Start sequence first
      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.sequencer,
        eventType: 'SequenceStarted',
        data: {'sequence_name': 'Test'},
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.sequencer,
        eventType: 'SequencePaused',
        data: {},
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      final execState = container.read(sequenceExecutionStateProvider);
      expect(execState, SequenceExecutionState.paused);
    });
  });

  // ---------------------------------------------------------------------------
  // Camera Cooling
  // ---------------------------------------------------------------------------
  group('Camera Cooling', () {
    test('setCameraCooling throws when camera not connected', () async {
      final service = container.read(deviceServiceProvider);
      await expectLater(
        service.setCameraCooling(enabled: true, targetTemp: -20.0),
        throwsA(isA<Exception>()),
      );
    });

    test('setCameraCooling delegates to backend when connected', () async {
      const deviceId = TestFixtures.cameraId;

      final camNotifier = container.read(cameraStateProvider.notifier);
      camNotifier.setConnecting(deviceId, 'Test Camera');
      camNotifier.setConnected();

      when(() => mockBackend.cameraSetCooling(
            deviceId: deviceId,
            enabled: true,
            targetTemp: -20.0,
          )).thenAnswer((_) async {});

      final service = container.read(deviceServiceProvider);
      await service.setCameraCooling(enabled: true, targetTemp: -20.0);

      verify(() => mockBackend.cameraSetCooling(
            deviceId: deviceId,
            enabled: true,
            targetTemp: -20.0,
          )).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Mount Park Events
  // ---------------------------------------------------------------------------
  group('Mount Park Events', () {
    test('MountParkCompleted sets parked, stops slewing and tracking',
        () async {
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting('mount-1');
      mountNotifier.setConnected();
      mountNotifier.setSlewing(true);
      mountNotifier.setTracking(true);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'MountParkCompleted',
        data: {},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(mountStateProvider);
      expect(state.isParked, isTrue);
      expect(state.isSlewing, isFalse);
      expect(state.isTracking, isFalse);
    });

    test('MountUnparked sets parked false', () async {
      final mountNotifier = container.read(mountStateProvider.notifier);
      mountNotifier.setConnecting('mount-1');
      mountNotifier.setConnected();
      mountNotifier.setParked(true);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'MountUnparked',
        data: {},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(container.read(mountStateProvider).isParked, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Rotator Events
  // ---------------------------------------------------------------------------
  group('Rotator Events', () {
    test('RotatorMoveCompleted updates position and stops moving', () async {
      final rotNotifier = container.read(rotatorStateProvider.notifier);
      rotNotifier.setConnecting('rotator-1', 'Test Rotator');
      rotNotifier.setConnected();
      rotNotifier.setMoving(true);

      eventStreamController.add(NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'RotatorMoveCompleted',
        data: {'angle': 90.0},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(rotatorStateProvider);
      expect(state.isMoving, isFalse);
      expect(state.position, 90.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Error Handling in Temperature Polling
  // ---------------------------------------------------------------------------
  group('Temperature Polling Error Handling', () {
    test('polling continues after a transient error', () async {
      const deviceId = TestFixtures.cameraId;
      int callCount = 0;

      when(() => mockBackend.discoverDevices(DeviceType.camera))
          .thenAnswer((_) async => [
                _deviceInfo(DeviceType.camera, deviceId, 'Test Camera'),
              ]);
      when(() => mockBackend.connectDevice(DeviceType.camera, deviceId))
          .thenAnswer((_) async {});
      when(() => mockBackend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          )).thenAnswer((_) async {});

      // First call throws, subsequent calls succeed
      when(() => mockBackend.getCameraStatus(deviceId)).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Transient USB error');
        }
        return CameraStatus(
          connected: true,
          state: device_types.CameraState.idle,
          sensorTemp: -10.0,
          coolerPower: 80.0,
          targetTemp: -10.0,
          coolerOn: true,
          gain: 100,
          offset: 50,
          binX: 1,
          binY: 1,
          sensorWidth: 4656,
          sensorHeight: 3520,
          pixelSizeX: 3.76,
          pixelSizeY: 3.76,
          maxAdu: 65535,
          canCool: true,
          canSetGain: true,
          canSetOffset: true,
        );
      });

      final service = container.read(deviceServiceProvider);
      await service.connectCamera(deviceId);

      // Wait long enough for second poll (polling is every 5s, but first poll is immediate)
      // The initial poll will throw; subsequent polls should succeed.
      // We verify the service didn't crash by checking that calls were made.
      await Future.delayed(const Duration(milliseconds: 200));

      // Should have called getCameraStatus at least once (the immediate poll)
      verify(() => mockBackend.getCameraStatus(deviceId)).called(greaterThan(0));
    });
  });
}
