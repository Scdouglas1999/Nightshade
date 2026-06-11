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
    registerFallbackValue(
      const EquipmentProfile(id: 'fallback', name: 'fallback'),
    );
  });

  group('master/slave host authority', () {
    test('profile CRUD uses NetworkBackend not local DAO', () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.saveProfile(any())).thenAnswer((_) async {});
      when(() => backend.getProfiles()).thenAnswer(
        (_) async => [
          const EquipmentProfile(id: '42', name: 'Remote Rig', isActive: true),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(equipmentProfilesProvider.notifier);
      await notifier.createProfile(name: 'Remote Rig');

      verify(() => backend.saveProfile(any())).called(1);
      verifyNever(() => backend.loadProfile('0'));
    });

    test('setActiveProfile on slave calls host loadProfile', () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.getProfiles()).thenAnswer((_) async => []);
      when(() => backend.getActiveProfile()).thenAnswer((_) async => null);
      when(() => backend.loadProfile('7')).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(equipmentProfilesProvider.future);
      await container
          .read(equipmentProfilesProvider.notifier)
          .setActiveProfile(7);

      verify(() => backend.loadProfile('7')).called(1);
    });

    test('HostStateChanged target invalidates remote target catalog', () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.getAllTargets()).thenAnswer(
        (_) async => [
          {'id': 1, 'name': 'M42', 'ra': 5.58, 'dec': -5.39},
        ],
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(allDbTargetsProvider.future);
      clearInteractions(backend);

      when(() => backend.getAllTargets()).thenAnswer(
        (_) async => [
          {'id': 1, 'name': 'M42', 'ra': 5.58, 'dec': -5.39},
          {'id': 2, 'name': 'M43', 'ra': 5.6, 'dec': -5.2},
        ],
      );

      await applyRemoteSyncEvent(
        container,
        buildHostMutationEvent(
          entityType: HostMutationEntity.target,
          action: HostMutationAction.created,
          entityId: '2',
        ),
      );

      final targets = await container.read(allDbTargetsProvider.future);
      expect(targets, hasLength(2));
      verify(() => backend.getAllTargets()).called(greaterThanOrEqualTo(1));
    });
  });
}
