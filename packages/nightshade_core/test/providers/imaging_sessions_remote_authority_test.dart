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

  group('imaging sessions remote authority', () {
    test('HostStateChanged session invalidates allSessionsProvider', () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.eventStream,
      ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.getAllSessions()).thenAnswer(
        (_) async => [
          {
            'id': 1,
            'name': 'Night 1',
            'startTime': DateTime(2025, 1, 1).millisecondsSinceEpoch,
            'status': 'active',
          },
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

      await container.read(allSessionsProvider.future);
      clearInteractions(backend);

      when(() => backend.getAllSessions()).thenAnswer(
        (_) async => [
          {
            'id': 1,
            'name': 'Night 1',
            'startTime': DateTime(2025, 1, 1).millisecondsSinceEpoch,
            'status': 'completed',
            'endTime': DateTime(2025, 1, 2).millisecondsSinceEpoch,
          },
          {
            'id': 2,
            'name': 'Night 2',
            'startTime': DateTime(2025, 1, 3).millisecondsSinceEpoch,
            'status': 'active',
          },
        ],
      );

      await applyRemoteSyncEvent(
        container,
        buildHostMutationEvent(
          entityType: HostMutationEntity.session,
          action: HostMutationAction.created,
          entityId: '2',
        ),
      );

      final sessions = await container.read(allSessionsProvider.future);
      expect(sessions, hasLength(2));
      verify(() => backend.getAllSessions()).called(greaterThanOrEqualTo(1));
    });

    test(
      'HostStateChanged capturedImage invalidates allDbImagesProvider',
      () async {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
        when(() => backend.getAllImageRows()).thenAnswer(
          (_) async => [
            {
              'id': 10,
              'filePath': '/a.fits',
              'fileName': 'a.fits',
              'fileFormat': 'fits',
              'frameType': 'light',
              'exposureDuration': 60.0,
              'binX': 1,
              'binY': 1,
              'capturedAt': DateTime(2025, 1, 1).millisecondsSinceEpoch,
              'createdAt': DateTime(2025, 1, 1).millisecondsSinceEpoch,
              'isPlateSolved': false,
              'isAccepted': true,
            },
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

        await container.read(allDbImagesProvider.future);
        clearInteractions(backend);

        when(() => backend.getAllImageRows()).thenAnswer(
          (_) async => [
            {
              'id': 10,
              'filePath': '/a.fits',
              'fileName': 'a.fits',
              'fileFormat': 'fits',
              'frameType': 'light',
              'exposureDuration': 60.0,
              'binX': 1,
              'binY': 1,
              'capturedAt': DateTime(2025, 1, 1).millisecondsSinceEpoch,
              'createdAt': DateTime(2025, 1, 1).millisecondsSinceEpoch,
              'isPlateSolved': false,
              'isAccepted': true,
            },
            {
              'id': 11,
              'filePath': '/b.fits',
              'fileName': 'b.fits',
              'fileFormat': 'fits',
              'frameType': 'light',
              'exposureDuration': 120.0,
              'binX': 1,
              'binY': 1,
              'capturedAt': DateTime(2025, 1, 2).millisecondsSinceEpoch,
              'createdAt': DateTime(2025, 1, 2).millisecondsSinceEpoch,
              'isPlateSolved': false,
              'isAccepted': true,
            },
          ],
        );

        await applyRemoteSyncEvent(
          container,
          buildHostMutationEvent(
            entityType: HostMutationEntity.capturedImage,
            action: HostMutationAction.created,
            entityId: '11',
          ),
        );

        final images = await container.read(allDbImagesProvider.future);
        expect(images, hasLength(2));
        verify(() => backend.getAllImageRows()).called(greaterThanOrEqualTo(1));
      },
    );
  });
}
