import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';
import 'package:nightshade_core/src/providers/remote_sync_handler.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_catalog_sync.dart';

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

  group('applyRemoteSyncEvent', () {
    test('equipment Connected updates mount chip without hydration', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      await applyRemoteSyncEvent(
        container,
        NightshadeEvent(
          timestamp: 1,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: const {
            'device_type': 'mount',
            'device_id': 'ascom:mount:0',
          },
        ),
      );

      final mount = container.read(mountStateProvider);
      expect(mount.connectionState, DeviceConnectionState.connected);
      expect(mount.deviceId, 'ascom:mount:0');
    });

    test('HostStateChanged profile mutation invalidates profiles', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );

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
        buildHostMutationEvent(
          entityType: HostMutationEntity.profile,
          action: HostMutationAction.updated,
          entityId: '1',
        ),
      );

      await container.read(equipmentProfilesProvider.future);
      expect(loadCount, greaterThanOrEqualTo(2));
    });

    test('HostStateChanged target mutation invalidates target catalog', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );
      when(() => backend.getAllTargets()).thenAnswer((_) async => []);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(allDbTargetsProvider.future);

      await applyRemoteSyncEvent(
        container,
        buildHostMutationEvent(
          entityType: HostMutationEntity.target,
          action: HostMutationAction.updated,
          entityId: '3',
        ),
      );

      await container.read(allDbTargetsProvider.future);
      verify(() => backend.getAllTargets()).called(greaterThanOrEqualTo(2));
    });

    test('ImageCaptured invalidates target progress providers', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );

      var progressReads = 0;
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
          allTargetProgressProvider.overrideWith((ref) async {
            progressReads++;
            return {};
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(allTargetProgressProvider.future);
      final readsBefore = progressReads;

      await applyRemoteSyncEvent(
        container,
        NightshadeEvent(
          timestamp: 4,
          severity: EventSeverity.info,
          category: EventCategory.imaging,
          eventType: 'ImageCaptured',
          data: const {'targetId': 1},
        ),
      );

      await container.read(allTargetProgressProvider.future);
      expect(progressReads, greaterThan(readsBefore));
    });

    test('SequenceUpdated over WS invalidates savedSequencesProvider', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );
      when(() => backend.listFullSequences()).thenAnswer((_) async => []);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(savedSequencesProvider, (_, __) {});
      await container.read(savedSequencesProvider.future);

      await applyRemoteSyncEvent(
        container,
        NightshadeEvent.fromWireJson({
          'type': 'event',
          'timestamp': 2,
          'severity': 'info',
          'category': 'sequencer',
          'eventType': sequenceUpdatedEventType,
          'data': {'sequenceId': 4, 'action': 'saved'},
        }),
      );

      await container.read(savedSequencesProvider.future);
      verify(() => backend.listFullSequences()).called(greaterThanOrEqualTo(2));
    });

    test('HostStateChanged sequence mutation invalidates library', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer(
        (_) => const Stream<NightshadeEvent>.empty(),
      );
      when(() => backend.listFullSequences()).thenAnswer((_) async => []);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(savedSequencesProvider.future);

      await applyRemoteSyncEvent(
        container,
        NightshadeEvent.fromWireJson({
          'type': 'event',
          'timestamp': 3,
          'severity': 'info',
          'category': 'system',
          'eventType': hostStateChangedEventType,
          'data': {
            'entityType': HostMutationEntity.sequence,
            'action': HostMutationAction.updated,
            'entityId': '9',
          },
        }),
      );

      await container.read(savedSequencesProvider.future);
      verify(() => backend.listFullSequences()).called(greaterThanOrEqualTo(2));
    });

    test('remoteSessionSyncProvider reacts to live equipment events', () async {
      final eventController = StreamController<NightshadeEvent>.broadcast();
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer((_) => eventController.stream);
      when(() => backend.sequencerGetStatus()).thenAnswer(
        (_) async => const SequencerStatus(state: 'Idle', progress: 0),
      );
      when(() => backend.getConnectedDevices()).thenAnswer((_) async => const []);
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

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
          loggingServiceProvider.overrideWithValue(LoggingService()),
        ],
      );
      addTearDown(() async {
        await eventController.close();
        container.dispose();
      });

      container.read(remoteSessionSyncProvider);
      await pumpEventQueue();

      eventController.add(
        NightshadeEvent(
          timestamp: 2,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: const {
            'device_type': 'camera',
            'device_id': 'asi:0',
          },
        ),
      );
      await pumpEventQueue();

      final camera = container.read(cameraStateProvider);
      expect(camera.connectionState, DeviceConnectionState.connected);
      expect(camera.deviceId, 'asi:0');
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
