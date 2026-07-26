/// Regression tests for the per-type device slot handover.
///
/// Each device type owns exactly ONE notifier slot. Connecting a second device
/// of the same type used to overwrite that slot while the incumbent's driver
/// connection stayed open. Because every disconnect path matches on the slot's
/// `deviceId`, the displaced device then became unaddressable and its
/// ASCOM/native handle stayed open for the rest of the session.
///
/// Found on the live rig: after a simulator mount took the mount slot, a real
/// Pegasus NYX-101 kept answering position polls, `/api/devices/connected`
/// listed both mounts, and `POST /api/devices/disconnect` for the real one
/// returned `device_id_mismatch` — so nothing could ever close it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart'
    hide CameraState;
import 'package:nightshade_core/src/models/equipment/equipment_models.dart'
    show DeviceConnectionState;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/services/device_service.dart';

import '../mocks/mock_backend.dart';

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

const _mountStatus = MountStatus(
  connected: true,
  tracking: false,
  slewing: false,
  parked: false,
  atHome: false,
  sideOfPier: PierSide.east,
  rightAscension: 0,
  declination: 0,
  altitude: 0,
  azimuth: 0,
  siderealTime: 0,
  trackingRate: TrackingRate.sidereal,
  canPark: false,
  canSlew: false,
  canSync: false,
  canPulseGuide: false,
  canSetTrackingRate: false,
);

void main() {
  late ProviderContainer container;
  late MockBackend mockBackend;
  late StreamController<NightshadeEvent> eventStreamController;

  setUpAll(registerMocktailFallbackValues);

  setUp(() {
    mockBackend = MockBackend();
    eventStreamController = StreamController<NightshadeEvent>.broadcast();

    when(
      () => mockBackend.eventStream,
    ).thenAnswer((_) => eventStreamController.stream);
    when(
      () => mockBackend.polarAlignmentEvents,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockBackend.connectDevice(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockBackend.disconnectDevice(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockBackend.getMountStatus(any()),
    ).thenAnswer((_) async => _mountStatus);

    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, mockBackend),
        ),
      ],
    );
    container.read(deviceServiceProvider);
  });

  tearDown(() {
    eventStreamController.close();
    container.dispose();
  });

  group('device slot handover', () {
    const realMount = 'ascom:ASCOM.PegasusAstroNYX101.Telescope';
    const simMount = 'simulator:sim_mount_1';

    test(
      'connecting a second mount disconnects the incumbent before connecting',
      () async {
        final service = container.read(deviceServiceProvider);

        await service.connectMount(realMount);
        expect(
          container.read(mountStateProvider).connectionState,
          DeviceConnectionState.connected,
        );

        await service.connectMount(simMount);

        // The displaced mount's driver handle is released, and that happens
        // BEFORE the incoming mount is connected so the two never hold the
        // bus at once. (One verifyInOrder rather than a separate `verify`:
        // mocktail will not re-match a call another verify already consumed.)
        verifyInOrder([
          () => mockBackend.connectDevice(DeviceType.mount, realMount),
          () => mockBackend.disconnectDevice(DeviceType.mount, realMount),
          () => mockBackend.connectDevice(DeviceType.mount, simMount),
        ]);
        // The slot now reports ONLY the incoming device.
        expect(container.read(mountStateProvider).deviceId, simMount);
      },
    );

    test('reconnecting the SAME mount does not disconnect it', () async {
      final service = container.read(deviceServiceProvider);

      await service.connectMount(realMount);
      await service.connectMount(realMount);

      verifyNever(() => mockBackend.disconnectDevice(DeviceType.mount, any()));
      expect(container.read(mountStateProvider).deviceId, realMount);
    });

    test('a displaced device that fails to disconnect does not block the '
        'incoming connect', () async {
      final service = container.read(deviceServiceProvider);
      await service.connectMount(realMount);

      // Cable already yanked: the teardown throws.
      when(
        () => mockBackend.disconnectDevice(DeviceType.mount, realMount),
      ).thenThrow(Exception('driver already gone'));

      await service.connectMount(simMount);

      expect(container.read(mountStateProvider).deviceId, simMount);
      expect(
        container.read(mountStateProvider).connectionState,
        DeviceConnectionState.connected,
      );
    });

    test('handover applies to non-mount types too', () async {
      final service = container.read(deviceServiceProvider);
      when(() => mockBackend.getFocuserStatus(any())).thenAnswer(
        (_) async => const FocuserStatus(
          connected: true,
          position: 0,
          moving: false,
          maxPosition: 1000,
          stepSize: 1,
          isAbsolute: true,
          hasTemperature: false,
        ),
      );

      await service.connectFocuser('ascom:ASCOM.EAF.Focuser');
      await service.connectFocuser('simulator:sim_focuser_1');

      verify(
        () => mockBackend.disconnectDevice(
          DeviceType.focuser,
          'ascom:ASCOM.EAF.Focuser',
        ),
      ).called(1);
    });
  });
}
