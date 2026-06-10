import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Stream<NightshadeEvent>.empty());
  });

  group('remoteSessionSyncProvider', () {
    test('hydrates mount state from host connected devices', () async {
      final backend = _MockNetworkBackend();

      when(() => backend.sequencerGetStatus()).thenAnswer(
        (_) async => const SequencerStatus(state: 'Idle', progress: 0),
      );

      when(() => backend.getConnectedDevices()).thenAnswer(
        (_) async => const [
          DeviceInfo(
            id: 'ascom:mount:0',

            name: 'Host Mount',

            deviceType: DeviceType.mount,

            driverType: DriverType.ascom,

            description: '',

            driverVersion: '1.0',
          ),
        ],
      );

      when(() => backend.phd2GetStatus()).thenAnswer(
        (_) async => const Phd2Status(
          state: 'Stopped',

          connected: false,

          rmsRa: 0,

          rmsDec: 0,

          rmsTotal: 0,

          snr: 0,

          starMass: 0,

          avgDistance: 0,
        ),
      );

      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),

          loggingServiceProvider.overrideWithValue(LoggingService()),
        ],
      );

      addTearDown(container.dispose);

      container.read(remoteSessionSyncProvider);

      await pumpEventQueue();

      final mount = container.read(mountStateProvider);

      expect(mount.connectionState, DeviceConnectionState.connected);

      expect(mount.deviceId, 'ascom:mount:0');

      expect(mount.deviceName, 'Host Mount');
    });

    test('hydrates PHD2 guider when host reports connected', () async {
      final backend = _MockNetworkBackend();

      when(() => backend.sequencerGetStatus()).thenAnswer(
        (_) async => const SequencerStatus(state: 'Idle', progress: 0),
      );

      when(
        () => backend.getConnectedDevices(),
      ).thenAnswer((_) async => const []);

      when(() => backend.phd2GetStatus()).thenAnswer(
        (_) async => const Phd2Status(
          state: 'Guiding',

          connected: true,

          rmsRa: 0.5,

          rmsDec: 0.4,

          rmsTotal: 0.6,

          snr: 100,

          starMass: 500,

          avgDistance: 0,
        ),
      );

      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),

          loggingServiceProvider.overrideWithValue(LoggingService()),
        ],
      );

      addTearDown(container.dispose);

      container.read(remoteSessionSyncProvider);

      await pumpEventQueue();

      final guider = container.read(guiderStateProvider);

      expect(guider.connectionState, DeviceConnectionState.connected);

      expect(guider.deviceId, 'phd2_guider');
    });
  });
}
