// Exercises the dedicated set-default / clear-default / reorder profile
// endpoints (LIM-1 / LIM-2) against a real in-memory Drift DB.
//
// The generic saveProfile path runs `remoteProfileToDbRow`, which deliberately
// preserves a host row's `isDefault`/`sortOrder`, so a slave looping
// saveProfile could never flip the default or change the order on the host.
// These dedicated endpoints route through the DAO's atomic
// setDefaultProfile / clearDefaultProfile / reorderProfiles and are the only
// thing that lets a remote slave control the host's default + order.
//
// In-memory DB keeps these hermetic (no path_provider / real disk).
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/profile_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileHandlers default + reorder endpoints', () {
    late ProviderContainer container;
    late NightshadeDatabase db;
    late ProfileHandlers handlers;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = ProfileHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> seedProfile(String name, {int sortOrder = 0}) {
      return db.equipmentProfilesDao.createProfile(
        EquipmentProfilesCompanion.insert(
          name: name,
          sortOrder: Value(sortOrder),
        ),
      );
    }

    test('POST /api/profiles/<id>/default sets the target default and active, '
        'unsetting every other row atomically', () async {
      final idA = await seedProfile('A', sortOrder: 0);
      final idB = await seedProfile('B', sortOrder: 1);
      final idC = await seedProfile('C', sortOrder: 2);

      // The first created profile (A) is the initial default + active.
      expect((await db.equipmentProfilesDao.getDefaultProfile())?.id, idA);

      final response = await translateHandlerErrors(
        handlers.handleSetDefaultProfile(
          Request(
            'POST',
            Uri.parse('http://localhost/api/profiles/$idB/default'),
          ),
          idB.toString(),
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], 'default-set');

      final rows = await db.equipmentProfilesDao.getAllProfiles();
      final byId = {for (final r in rows) r.id: r};
      // Exactly the target is default; all others cleared.
      expect(byId[idB]!.isDefault, isTrue);
      expect(byId[idA]!.isDefault, isFalse);
      expect(byId[idC]!.isDefault, isFalse);
      // makeActive:true moved the active selection to the new default.
      expect((await db.equipmentProfilesDao.getActiveProfile())?.id, idB);
    });

    test(
      'POST /api/profiles/default/clear unsets isDefault on every row',
      () async {
        final idA = await seedProfile('A');
        expect((await db.equipmentProfilesDao.getDefaultProfile())?.id, idA);

        final response = await translateHandlerErrors(
          handlers.handleClearDefaultProfile(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles/default/clear'),
            ),
          ),
        );
        expect(response.statusCode, HttpStatus.ok);

        expect(await db.equipmentProfilesDao.getDefaultProfile(), isNull);
      },
    );

    test(
      'POST /api/profiles/reorder assigns sortOrder == posted index per id',
      () async {
        final idA = await seedProfile('A', sortOrder: 0);
        final idB = await seedProfile('B', sortOrder: 1);
        final idC = await seedProfile('C', sortOrder: 2);

        // Post the reversed order: C, B, A.
        final response = await translateHandlerErrors(
          handlers.handleReorderProfiles(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles/reorder'),
              body: jsonEncode({
                'profileIds': [idC.toString(), idB.toString(), idA.toString()],
              }),
            ),
          ),
        );
        expect(response.statusCode, HttpStatus.ok);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(body['status'], 'reordered');

        final rows = await db.equipmentProfilesDao.getAllProfiles();
        final byId = {for (final r in rows) r.id: r};
        expect(byId[idC]!.sortOrder, 0);
        expect(byId[idB]!.sortOrder, 1);
        expect(byId[idA]!.sortOrder, 2);
      },
    );

    test('reorder skips ids that no longer resolve to a row', () async {
      final idA = await seedProfile('A', sortOrder: 0);
      final idB = await seedProfile('B', sortOrder: 1);

      final response = await translateHandlerErrors(
        handlers.handleReorderProfiles(
          Request(
            'POST',
            Uri.parse('http://localhost/api/profiles/reorder'),
            body: jsonEncode({
              // 999999 is a stale/deleted id; it must not fail the reorder.
              'profileIds': [idB.toString(), '999999', idA.toString()],
            }),
          ),
        ),
      );
      expect(response.statusCode, HttpStatus.ok);

      final rows = await db.equipmentProfilesDao.getAllProfiles();
      final byId = {for (final r in rows) r.id: r};
      expect(byId[idB]!.sortOrder, 0);
      expect(byId[idA]!.sortOrder, 2);
    });
  });
}
