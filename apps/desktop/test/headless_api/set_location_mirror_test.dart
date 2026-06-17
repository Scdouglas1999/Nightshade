// Regression test for the location store-split bug.
//
// `POST /api/settings/location` writes the canonical backend (native) location
// store, which `GET /api/settings/location` and the planetarium read. But the
// scheduler and "tonight" suggestion subsystems read observer lat/lon straight
// from the Drift `settingsDao`, which on a headless appliance is otherwise only
// ever populated by the GUI settings flow (never run there). Before the fix, a
// remote client that set its location through the API got a working planetarium
// but a permanently "No observer location configured" scheduler.
//
// `handleSetLocation` now mirrors the location into `settingsDao`. This test
// pins that mirror so the two stores cannot silently diverge again.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/database_entities.dart' as settings_models;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/profile_handlers.dart';
import 'package:shelf/shelf.dart';

/// Minimal fake whose `setLocation` succeeds (the real disconnected backend
/// throws NotConnected, which would short-circuit the handler before the
/// mirror runs). Only the two location methods are exercised here.
class _FakeProfileSettingsBackend implements ProfileSettingsBackend {
  settings_models.ObserverLocation? _location;

  @override
  Future<void> setLocation(settings_models.ObserverLocation? location) async {
    _location = location;
  }

  @override
  Future<settings_models.ObserverLocation?> getLocation() async => _location;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('set location mirrors lat/lon/elev into the settings DAO', () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        profileSettingsBackendProvider.overrideWithValue(
          _FakeProfileSettingsBackend(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    // DAO starts unset (zeros) — the scheduler reads this as "no location".
    expect(await db.settingsDao.getObserverLatitude(), 0.0);

    final handlers = ProfileHandlers(container);
    final response = await handlers.handleSetLocation(
      Request(
        'POST',
        Uri.parse('http://localhost/api/settings/location'),
        body: jsonEncode({
          'location': {'latitude': 40.0, 'longitude': -74.0, 'elevation': 50.0},
        }),
      ),
    );
    expect(response.statusCode, 200);

    // The mirror must have populated the DAO that the scheduler reads.
    expect(await db.settingsDao.getObserverLatitude(), 40.0);
    expect(await db.settingsDao.getObserverLongitude(), -74.0);
    expect(await db.settingsDao.getObserverElevation(), 50.0);
  });

  test('clearing location zeroes the mirrored DAO values', () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    await db.settingsDao.setObserverLatitude(12.0);
    await db.settingsDao.setObserverLongitude(34.0);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        profileSettingsBackendProvider.overrideWithValue(
          _FakeProfileSettingsBackend(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final handlers = ProfileHandlers(container);
    final response = await handlers.handleSetLocation(
      Request(
        'POST',
        Uri.parse('http://localhost/api/settings/location'),
        body: jsonEncode({'location': null}),
      ),
    );
    expect(response.statusCode, 200);

    expect(await db.settingsDao.getObserverLatitude(), 0.0);
    expect(await db.settingsDao.getObserverLongitude(), 0.0);
  });
}
