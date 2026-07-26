import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/profile_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

class _MockProfileSettingsBackend extends Mock
    implements ProfileSettingsBackend {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(const EquipmentProfile(id: '0', name: 'fallback'));
    registerFallbackValue(const AppSettings());
  });

  group('ProfileHandlers', () {
    late ProviderContainer container;
    late NightshadeDatabase db;
    late ProfileHandlers handlers;
    late SecretsStore secrets;
    late _MockProfileSettingsBackend profileBackend;

    setUp(() {
      // Hermetic in-memory DB: the GUI's real DB resolves its file via
      // path_provider, which a unit-test isolate cannot service. Overriding it
      // here keeps these error-translation tests deterministic (the real DB
      // would otherwise leak a MissingPluginException from its lazy open).
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      secrets = SecretsStore(InMemorySecureKeyValueStore());
      profileBackend = _MockProfileSettingsBackend();
      when(() => profileBackend.saveProfile(any())).thenAnswer((_) async {});
      when(() => profileBackend.loadProfile(any())).thenAnswer((_) async {});
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretsStoreProvider.overrideWithValue(secrets),
          profileSettingsBackendProvider.overrideWithValue(profileBackend),
        ],
      );
      handlers = ProfileHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('get profiles returns a JSON envelope', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetProfiles(
          Request('GET', Uri.parse('http://localhost/api/profiles')),
        ),
      );

      expect(response.headers['content-type'], 'application/json');
      // With a working (empty) DB the handler succeeds with a profiles array;
      // the contract under test is that it always returns structured JSON, not
      // a thrown stack trace.
      expect(response.statusCode, HttpStatus.ok);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['profiles'], isA<List>());
    });

    test(
      'load rejects malformed and missing ids without clearing active',
      () async {
        final existingId = await db.equipmentProfilesDao.createProfile(
          EquipmentProfilesCompanion.insert(name: 'Existing'),
        );
        expect(
          (await db.equipmentProfilesDao.getActiveProfile())?.id,
          existingId,
        );

        final malformed = await translateHandlerErrors(
          handlers.handleLoadProfile(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles/nope/load'),
            ),
            'nope',
          ),
        );
        expect(malformed.statusCode, HttpStatus.badRequest);

        final missing = await handlers.handleLoadProfile(
          Request('POST', Uri.parse('http://localhost/api/profiles/999/load')),
          '999',
        );
        expect(missing.statusCode, HttpStatus.notFound);
        final body = jsonDecode(await missing.readAsString()) as Map;
        expect(body['error'], 'profile_not_found');
        expect(
          (await db.equipmentProfilesDao.getActiveProfile())?.id,
          existingId,
        );
      },
    );

    test(
      'load native failure does not switch the SQLite active profile',
      () async {
        final idA = await db.equipmentProfilesDao.createProfile(
          EquipmentProfilesCompanion.insert(name: 'A'),
        );
        final idB = await db.equipmentProfilesDao.createProfile(
          EquipmentProfilesCompanion.insert(name: 'B'),
        );
        when(
          () => profileBackend.loadProfile(idB.toString()),
        ).thenThrow(StateError('native executor unavailable'));

        final response = await translateHandlerErrors(
          handlers.handleLoadProfile(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles/$idB/load'),
            ),
            idB.toString(),
          ),
        );

        expect(response.statusCode, HttpStatus.internalServerError);
        expect((await db.equipmentProfilesDao.getActiveProfile())?.id, idA);
      },
    );

    test(
      'delete rejects malformed and missing ids instead of claiming success',
      () async {
        final malformed = await translateHandlerErrors(
          handlers.handleDeleteProfile(
            Request('DELETE', Uri.parse('http://localhost/api/profiles/nope')),
            'nope',
          ),
        );
        expect(malformed.statusCode, HttpStatus.badRequest);

        final missing = await handlers.handleDeleteProfile(
          Request('DELETE', Uri.parse('http://localhost/api/profiles/999')),
          '999',
        );
        expect(missing.statusCode, HttpStatus.notFound);
        final body = jsonDecode(await missing.readAsString()) as Map;
        expect(body['error'], 'profile_not_found');
      },
    );

    test(
      'save profile malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSaveProfile(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles'),
              body: jsonEncode({}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );

    test(
      'set location accepts null shape but disconnected backend returns JSON',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSetLocation(
            Request(
              'POST',
              Uri.parse('http://localhost/api/settings/location'),
              body: jsonEncode({'location': null}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );

    test('meridian-flip settings round-trip through the host', () async {
      const settings = MeridianFlipSettings(
        standaloneMonitoringEnabled: true,
        triggerMethod: MeridianTriggerMethod.hourAngleThreshold,
        hourAngleThreshold: 1.5,
        recenterAfterFlip: false,
        refocusAfterFlip: true,
        maxRetries: 7,
        failureAction: FlipFailureAction.abortAndPark,
      );
      final update = await handlers.handleUpdateMeridianFlipSettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/settings/meridian-flip'),
          body: jsonEncode({'settings': settings.toJson()}),
        ),
      );
      expect(update.statusCode, HttpStatus.ok);

      final get = await handlers.handleGetMeridianFlipSettings(
        Request(
          'GET',
          Uri.parse('http://localhost/api/settings/meridian-flip'),
        ),
      );
      final body = jsonDecode(await get.readAsString()) as Map<String, dynamic>;
      expect(
        MeridianFlipSettings.fromJson(
          (body['settings'] as Map).cast<String, dynamic>(),
        ),
        settings,
      );

      final persisted = await db.settingsDao.getSetting(
        'meridian_flip_settings',
      );
      expect(persisted, isNotNull);
      expect(
        MeridianFlipSettings.fromJson(
          (jsonDecode(persisted!) as Map).cast<String, dynamic>(),
        ),
        settings,
      );
    });

    test('meridian-flip settings reject invalid host values', () async {
      final response = await translateHandlerErrors(
        handlers.handleUpdateMeridianFlipSettings(
          Request(
            'POST',
            Uri.parse('http://localhost/api/settings/meridian-flip'),
            body: jsonEncode({
              'settings': const MeridianFlipSettings(maxRetries: 99).toJson(),
            }),
          ),
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], contains('Max retries should not exceed 10'));
    });

    test(
      'Home Assistant settings preserve, replace, and clear host secrets',
      () async {
        const originalBroker = MqttTransportConfig(
          host: 'mqtt.internal',
          port: 1883,
          username: 'nightshade',
          password: 'old-secret',
          topic: 'nightshade/state',
          qos: 1,
          retain: true,
          clientId: 'nightshade-host',
        );
        await container.read(mqttTransportConfigProvider.future);
        await container
            .read(mqttTransportConfigProvider.notifier)
            .save(originalBroker);

        const config = HomeAssistantDiscoveryConfig(
          enabled: true,
          deviceName: 'Backyard Observatory',
          allowControl: true,
          discoveryPrefix: 'homeassistant',
        );
        final preserved = await handlers.handleUpdateHomeAssistantSettings(
          Request(
            'POST',
            Uri.parse('http://localhost/api/settings/home-assistant'),
            body: jsonEncode({
              'config': config.toJson(),
              'broker': originalBroker.copyWith(clearPassword: true).toJson(),
            }),
          ),
        );
        expect(preserved.statusCode, HttpStatus.ok);
        final preservedBody =
            jsonDecode(await preserved.readAsString()) as Map<String, dynamic>;
        expect(
          (preservedBody['broker'] as Map<String, dynamic>)['password'],
          isNull,
        );
        expect(preservedBody['brokerPasswordConfigured'], isTrue);
        expect(
          container.read(mqttTransportConfigProvider).requireValue.password,
          'old-secret',
        );

        final replaced = await handlers.handleUpdateHomeAssistantSettings(
          Request(
            'POST',
            Uri.parse('http://localhost/api/settings/home-assistant'),
            body: jsonEncode({
              'config': config.toJson(),
              'broker': originalBroker.copyWith(clearPassword: true).toJson(),
              'password': 'new-secret',
            }),
          ),
        );
        expect(replaced.statusCode, HttpStatus.ok);
        expect(
          container.read(mqttTransportConfigProvider).requireValue.password,
          'new-secret',
        );

        final cleared = await handlers.handleUpdateHomeAssistantSettings(
          Request(
            'POST',
            Uri.parse('http://localhost/api/settings/home-assistant'),
            body: jsonEncode({
              'config': config.toJson(),
              'broker': originalBroker.copyWith(clearPassword: true).toJson(),
              'password': '',
            }),
          ),
        );
        final clearedBody =
            jsonDecode(await cleared.readAsString()) as Map<String, dynamic>;
        expect(clearedBody['brokerPasswordConfigured'], isFalse);
        expect(
          container.read(mqttTransportConfigProvider).requireValue.password,
          isNull,
        );
        expect(await secrets.read(SecretField.mqttPassword), isEmpty);

        final storedBroker = await db.settingsDao.getSetting(
          'notification_transport_mqtt',
        );
        expect(storedBroker, isNot(contains('old-secret')));
        expect(storedBroker, isNot(contains('new-secret')));
        expect(
          await container.read(homeAssistantConfigProvider.future),
          config,
        );
      },
    );

    test(
      'Home Assistant rejects enabled discovery without a host broker',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleUpdateHomeAssistantSettings(
            Request(
              'POST',
              Uri.parse('http://localhost/api/settings/home-assistant'),
              body: jsonEncode({
                'config': const HomeAssistantDiscoveryConfig(
                  enabled: true,
                ).toJson(),
                'broker': const MqttTransportConfig().toJson(),
              }),
            ),
          ),
        );

        expect(response.statusCode, HttpStatus.badRequest);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], contains('Configure an MQTT broker'));
      },
    );

    test('partial settings update merges onto current values instead of '
        'resetting omitted keys to model defaults', () async {
      when(() => profileBackend.updateSettings(any())).thenAnswer((_) async {});

      Future<Response> post(Map<String, dynamic> settings) =>
          translateHandlerErrors(
            handlers.handleUpdateSettings(
              Request(
                'POST',
                Uri.parse('http://localhost/api/settings'),
                body: jsonEncode({'settings': settings}),
                headers: {'content-type': 'application/json'},
              ),
            ),
          );

      // Establish a non-default value for a key the second write omits.
      Response response;
      try {
        response = await handlers.handleUpdateSettings(
          Request(
            'POST',
            Uri.parse('http://localhost/api/settings'),
            body: jsonEncode({
              'settings': {'webServerEnabled': true},
            }),
            headers: {'content-type': 'application/json'},
          ),
        );
      } catch (e, st) {
        fail('first update threw: $e\n$st');
      }
      expect(response.statusCode, HttpStatus.ok);

      // A later partial update of an UNRELATED key must not clobber it.
      // (Pre-merge, AppSettings.fromJson refilled every omitted key with
      // its default, silently resetting ~150 settings — including the
      // web server flag, which tore down the caller's own connection.)
      response = await post({'parkOnUnsafeWeather': false});
      expect(response.statusCode, HttpStatus.ok);

      final get = await translateHandlerErrors(
        handlers.handleGetSettings(
          Request('GET', Uri.parse('http://localhost/api/settings')),
        ),
      );
      expect(get.statusCode, HttpStatus.ok);
      final envelope =
          jsonDecode(await get.readAsString()) as Map<String, dynamic>;
      final saved = envelope['settings'] as Map<String, dynamic>;
      expect(saved['parkOnUnsafeWeather'], isFalse);
      expect(
        saved['webServerEnabled'],
        isTrue,
        reason: 'a partial update must preserve keys it does not mention',
      );
    });
  });
}
