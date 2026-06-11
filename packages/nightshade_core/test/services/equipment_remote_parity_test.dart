import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    hide CameraState;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/profiles_provider.dart';
import 'package:nightshade_core/src/models/backend/device_types.dart'
    as device_types;
import 'package:nightshade_core/src/models/equipment_profile.dart'
    as remote_profile;
import 'package:nightshade_core/src/providers/remote_sync_handler.dart';
import 'package:nightshade_core/src/services/device_service.dart';
import 'package:nightshade_core/src/services/profile_service.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Stream<NightshadeEvent>.empty());
    registerFallbackValue(
      const remote_profile.EquipmentProfile(id: '0', name: 'fallback'),
    );
    registerFallbackValue(DeviceType.camera);
  });

  group('equipment remote parity', () {
    test(
      'connectActiveProfile uses host active profile on NetworkBackend',
      () async {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
        when(() => backend.getProfiles()).thenAnswer(
          (_) async => [
            const remote_profile.EquipmentProfile(
              id: '3',
              name: 'Remote Rig',
              isActive: true,
              cameraId: 'simulator:cam-1',
              mountId: 'simulator:mount-1',
            ),
          ],
        );
        when(() => backend.getActiveProfile()).thenAnswer(
          (_) async => const remote_profile.EquipmentProfile(
            id: '3',
            name: 'Remote Rig',
            isActive: true,
            cameraId: 'simulator:cam-1',
            mountId: 'simulator:mount-1',
          ),
        );
        when(() => backend.discoverDevices(any())).thenAnswer(
          (_) async => [
            const DeviceInfo(
              id: 'simulator:cam-1',
              name: 'Camera',
              deviceType: DeviceType.camera,
              driverType: DriverType.simulator,
              description: '',
              driverVersion: '1',
            ),
            const DeviceInfo(
              id: 'simulator:mount-1',
              name: 'Mount',
              deviceType: DeviceType.mount,
              driverType: DriverType.simulator,
              description: '',
              driverVersion: '1',
            ),
          ],
        );
        when(
          () => backend.connectDevice(any(), any()),
        ).thenAnswer((_) async {});
        when(() => backend.getMountStatus('simulator:mount-1')).thenAnswer(
          (_) async => const MountStatus(
            connected: true,
            tracking: true,
            slewing: false,
            parked: false,
            atHome: false,
            sideOfPier: PierSide.east,
            rightAscension: 1,
            declination: 2,
            altitude: 3,
            azimuth: 4,
            siderealTime: 0,
            trackingRate: TrackingRate.sidereal,
            canPark: true,
            canSlew: true,
            canSync: true,
            canPulseGuide: true,
            canSetTrackingRate: true,
            availability: {},
          ),
        );
        when(
          () => backend.startDeviceHeartbeat(
            deviceType: any(named: 'deviceType'),
            deviceId: any(named: 'deviceId'),
            intervalMs: any(named: 'intervalMs'),
          ),
        ).thenAnswer((_) async {});
        when(() => backend.getCameraStatus('simulator:cam-1')).thenAnswer(
          (_) async => const CameraStatus(
            connected: true,
            state: device_types.CameraState.idle,
            sensorTemp: -10,
            coolerPower: 0,
            coolerOn: false,
            gain: 0,
            offset: 0,
            binX: 1,
            binY: 1,
            sensorWidth: 100,
            sensorHeight: 100,
            pixelSizeX: 3.76,
            pixelSizeY: 3.76,
            maxAdu: 65535,
            canCool: true,
            canSetGain: true,
            canSetOffset: true,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, backend),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(equipmentProfilesProvider.future);
        final service = container.read(deviceServiceProvider);
        await service.connectActiveProfile();

        verify(
          () => backend.connectDevice(DeviceType.camera, 'simulator:cam-1'),
        ).called(1);
        verify(
          () => backend.connectDevice(DeviceType.mount, 'simulator:mount-1'),
        ).called(1);
      },
    );

    test(
      'updateProfileDevices saves through host API on NetworkBackend',
      () async {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
        when(() => backend.getProfiles()).thenAnswer(
          (_) async => [
            const remote_profile.EquipmentProfile(
              id: '9',
              name: 'Rig',
              cameraId: 'old-cam',
            ),
          ],
        );
        when(() => backend.saveProfile(any())).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, backend),
            ),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(profileServiceProvider);
        await service.updateProfileDevices(9, cameraId: 'new-cam');

        final captured = verify(
          () => backend.saveProfile(captureAny()),
        ).captured;
        final saved = captured.single as remote_profile.EquipmentProfile;
        expect(saved.id, '9');
        expect(saved.cameraId, 'new-cam');
      },
    );

    test('equipment Connected WS event invalidates profile catalog', () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());

      var loadCount = 0;
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
          equipmentProfilesProvider.overrideWith(() {
            return _TestProfilesNotifier(onLoad: () => loadCount++);
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(equipmentProfilesProvider.future);

      await applyRemoteSyncEvent(
        container,
        const NightshadeEvent(
          timestamp: 1,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: {'device_type': 'camera', 'device_id': 'cam-42'},
        ),
      );

      await container.read(equipmentProfilesProvider.future);
      expect(loadCount, greaterThanOrEqualTo(2));
    });
  });
}

class _TestProfilesNotifier extends EquipmentProfilesNotifier {
  _TestProfilesNotifier({required this.onLoad});

  final void Function() onLoad;

  @override
  Future<EquipmentProfilesState> build() async {
    onLoad();
    return const EquipmentProfilesState(profiles: [], activeProfile: null);
  }
}
