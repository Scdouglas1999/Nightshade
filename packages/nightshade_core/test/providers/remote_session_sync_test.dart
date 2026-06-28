import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

/// hydrateRemoteSessionState invalidates the host-mirrored planner/scheduler
/// data providers on connect (projects, integration goals, target constraints,
/// scheduler preview, sequence runs, observing lists) so the slave shows the
/// host's rows immediately. In NetworkBackend mode those providers re-fetch via
/// these endpoints, so a mock must answer them or the (eager) StreamProvider
/// rebuild throws a null-future and aborts hydration before PHD2/device state
/// is asserted. These stubs are intentionally empty payloads — the test only
/// cares that hydration completes, not what the planner data contains.
void _stubHydrationParityEndpoints(_MockNetworkBackend backend) {
  when(() => backend.getIntegrationGoals()).thenAnswer((_) async => const []);
  when(
    () => backend.getIntegrationGoals(targetId: any(named: 'targetId')),
  ).thenAnswer((_) async => const []);
  when(() => backend.getTargetConstraints()).thenAnswer((_) async => const []);
  when(
    () => backend.getTargetConstraints(targetId: any(named: 'targetId')),
  ).thenAnswer((_) async => const []);
  when(() => backend.getProjects()).thenAnswer((_) async => const []);
  when(() => backend.getObservingLists()).thenAnswer((_) async => const []);
  when(
    () => backend.getListedCatalogIds(listId: any(named: 'listId')),
  ).thenAnswer((_) async => const <String>{});
  when(() => backend.getListedCatalogIds()).thenAnswer((_) async => const {});
  when(() => backend.getSchedulerPreview()).thenAnswer(
    (_) async => SchedulerDecision(
      score: 0,
      reasoning: const [],
      scoredCandidates: const [],
      evaluatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
  when(() => backend.getProfiles()).thenAnswer((_) async => const []);
  when(() => backend.getActiveProfile()).thenAnswer((_) async => null);
  when(
    () => backend.fetchSequenceRuns(
      sequenceId: any(named: 'sequenceId'),
      limit: any(named: 'limit'),
      offset: any(named: 'offset'),
    ),
  ).thenAnswer(
    (_) async => const RemotePage<RemoteSequenceRun>(items: [], total: 0),
  );
}

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

      _stubHydrationParityEndpoints(backend);

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
