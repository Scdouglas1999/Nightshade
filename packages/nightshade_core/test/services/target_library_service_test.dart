import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/database/database.dart' hide Target;

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('TargetLibraryService', () {
    test('uses host REST API when connected remotely', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.getAllTargets()).thenAnswer((_) async => []);
      when(() => backend.createTarget(any())).thenAnswer((_) async => 42);

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      final id = await container
          .read(targetLibraryServiceProvider)
          .createTarget(
            name: 'SN 2026abc',
            raHours: 5.5,
            decDegrees: 20.0,
            catalogId: 'SN2026abc',
            objectType: 'star',
          );

      expect(id, 42);
      verify(
        () => backend.createTarget(
          any(
            that: predicate<Map<String, dynamic>>(
              (payload) =>
                  payload['name'] == 'SN 2026abc' && payload['ra'] == 5.5,
            ),
          ),
        ),
      ).called(1);
    });

    test('writes to local database when using FFI backend', () async {
      final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => db.close());

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, DisconnectedBackend()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final id = await container
          .read(targetLibraryServiceProvider)
          .createTarget(
            name: 'M31',
            raHours: 0.7,
            decDegrees: 41.3,
            catalogId: 'M31',
          );

      final rows = await db.targetsDao.getAllTargets();
      expect(id, greaterThan(0));
      expect(rows.any((t) => t.id == id && t.name == 'M31'), isTrue);
    });

    test('ensureCatalogTarget returns existing row without duplicate',
        () async {
      final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => db.close());

      final existingId = await db.targetsDao.createTarget(
        TargetsCompanion.insert(
          name: 'M42',
          ra: 5.58,
          dec: -5.39,
          catalogId: const Value('M42'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, DisconnectedBackend()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final resolved = await container
          .read(targetLibraryServiceProvider)
          .ensureCatalogTarget(
            targetName: 'M42',
            raHours: 5.58,
            decDegrees: -5.39,
            catalogId: 'M42',
          );

      expect(resolved.id, existingId);
      expect(await db.targetsDao.getAllTargets(), hasLength(1));
    });
  });
}
