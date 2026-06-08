import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

/// Phase D — `device_push_tokens` + `device_push_prefs` schema-v3 tables.
///
/// Exercises the accessors the `/api/push/*` endpoints sit on:
///  - register-token upserts (insert then overwrite-in-place on refresh),
///  - preference round-trip (write → read identical),
/// plus the deletion / stale-token cleanup paths the delivery + unpair use.
void main() {
  late PairingDatabase db;

  setUp(() {
    db = PairingDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Seed an ACTIVE paired-device row. `getPushTokensByPlatform` inner-joins
  /// against `paired_devices.is_active = true`, so a token only fans out when
  /// its device is paired and active — mirror that in fixtures.
  Future<void> pair(String deviceId) => db.addPairedDevice(
        deviceId: deviceId,
        deviceName: 'Test $deviceId',
        sessionToken: 'tok-$deviceId',
        deviceType: 'mobile',
      );

  group('device_push_tokens', () {
    test('register-token upserts: insert then overwrite in place', () async {
      await pair('phone-1');
      await db.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'fcm',
        token: 'tok-original',
      );

      var rows = await db.getPushTokensByPlatform('fcm');
      expect(rows, hasLength(1));
      expect(rows.single.deviceId, 'phone-1');
      expect(rows.single.token, 'tok-original');

      // A token refresh for the same (deviceId, platform) overwrites in place
      // rather than inserting a second row — the composite PK guarantees this.
      await db.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'fcm',
        token: 'tok-refreshed',
      );

      rows = await db.getPushTokensByPlatform('fcm');
      expect(rows, hasLength(1), reason: 'upsert must not duplicate the row');
      expect(rows.single.token, 'tok-refreshed');
    });

    test('different platforms for one device are distinct rows', () async {
      await pair('phone-1');
      await db.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'fcm',
        token: 'fcm-tok',
      );
      await db.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'apns',
        token: 'apns-tok',
      );

      expect(await db.getPushTokensByPlatform('fcm'), hasLength(1));
      expect(await db.getPushTokensByPlatform('apns'), hasLength(1));
      expect(await db.getPushTokensForDevice('phone-1'), hasLength(2));
    });

    test('getPushTokensByPlatform partitions by platform', () async {
      await pair('a');
      await pair('b');
      await pair('c');
      await db.upsertPushToken(
          deviceId: 'a', platform: 'fcm', token: 't-a');
      await db.upsertPushToken(
          deviceId: 'b', platform: 'fcm', token: 't-b');
      await db.upsertPushToken(
          deviceId: 'c', platform: 'apns', token: 't-c');

      final fcm = await db.getPushTokensByPlatform('fcm');
      expect(fcm.map((r) => r.deviceId).toSet(), {'a', 'b'});
      final apns = await db.getPushTokensByPlatform('apns');
      expect(apns.map((r) => r.deviceId).toSet(), {'c'});
    });

    test('deletePushTokensForDevice clears all of a device\'s tokens',
        () async {
      await db.upsertPushToken(
          deviceId: 'phone-1', platform: 'fcm', token: 'f');
      await db.upsertPushToken(
          deviceId: 'phone-1', platform: 'apns', token: 'a');
      await db.upsertPushToken(
          deviceId: 'phone-2', platform: 'fcm', token: 'f2');

      await db.deletePushTokensForDevice('phone-1');

      expect(await db.getPushTokensForDevice('phone-1'), isEmpty);
      expect(await db.getPushTokensForDevice('phone-2'), hasLength(1));
    });

    test('deletePushToken removes a single stale token by value', () async {
      await db.upsertPushToken(
          deviceId: 'phone-1', platform: 'fcm', token: 'stale');
      await db.upsertPushToken(
          deviceId: 'phone-2', platform: 'fcm', token: 'fresh');

      await db.deletePushToken('stale');

      final remaining = await db.getAllPushTokens();
      expect(remaining, hasLength(1));
      expect(remaining.single.token, 'fresh');
    });

    test('getPushTokensByPlatform excludes a token with no active device',
        () async {
      // A token row whose paired-device row is inactive (or absent) must not
      // fan out — defense in depth so a revoked phone cannot keep receiving
      // criticals even if its token row lingers.
      await pair('active');
      await db.upsertPushToken(
          deviceId: 'active', platform: 'fcm', token: 'A');
      // Token for a device that was never paired (no paired_devices row).
      await db.upsertPushToken(
          deviceId: 'orphan', platform: 'fcm', token: 'O');

      final rows = await db.getPushTokensByPlatform('fcm');
      expect(rows.map((r) => r.deviceId), ['active']);
    });

    test('revokeDevice deletes push rows and drops the device from fan-out',
        () async {
      await pair('keep');
      await pair('revoked');
      await db.upsertPushToken(
          deviceId: 'keep', platform: 'fcm', token: 'KEEP');
      await db.upsertPushToken(
          deviceId: 'revoked', platform: 'fcm', token: 'REVOKED');
      await db.upsertPushPrefs(
        deviceId: 'revoked',
        enabled: true,
        muteSequenceFailed: false,
        muteWeatherUnsafe: false,
        muteGuidingLost: false,
        muteAutofocusFailed: false,
        muteEquipmentDisconnected: false,
      );

      await db.revokeDevice('revoked');

      // Push token + prefs rows for the revoked device are gone.
      expect(await db.getPushTokensForDevice('revoked'), isEmpty);
      expect(await db.getPushPrefs('revoked'), isNull);
      // The active device still fans out; the revoked one does not.
      final rows = await db.getPushTokensByPlatform('fcm');
      expect(rows.map((r) => r.deviceId), ['keep']);
    });
  });

  group('device_push_prefs', () {
    test('missing row reads as null (caller applies all-enabled default)',
        () async {
      expect(await db.getPushPrefs('never-set'), isNull);
    });

    test('preferences round-trip: write then read identical', () async {
      await db.upsertPushPrefs(
        deviceId: 'phone-1',
        enabled: true,
        muteSequenceFailed: false,
        muteWeatherUnsafe: true,
        muteGuidingLost: false,
        muteAutofocusFailed: true,
        muteEquipmentDisconnected: false,
      );

      final row = await db.getPushPrefs('phone-1');
      expect(row, isNotNull);
      expect(row!.enabled, isTrue);
      expect(row.muteSequenceFailed, isFalse);
      expect(row.muteWeatherUnsafe, isTrue);
      expect(row.muteGuidingLost, isFalse);
      expect(row.muteAutofocusFailed, isTrue);
      expect(row.muteEquipmentDisconnected, isFalse);
    });

    test('upsert overwrites the prefs row in place', () async {
      await db.upsertPushPrefs(
        deviceId: 'phone-1',
        enabled: true,
        muteSequenceFailed: false,
        muteWeatherUnsafe: false,
        muteGuidingLost: false,
        muteAutofocusFailed: false,
        muteEquipmentDisconnected: false,
      );
      await db.upsertPushPrefs(
        deviceId: 'phone-1',
        enabled: false,
        muteSequenceFailed: true,
        muteWeatherUnsafe: true,
        muteGuidingLost: true,
        muteAutofocusFailed: true,
        muteEquipmentDisconnected: true,
      );

      final row = await db.getPushPrefs('phone-1');
      expect(row!.enabled, isFalse);
      expect(row.muteSequenceFailed, isTrue);
      expect(row.muteEquipmentDisconnected, isTrue);
    });

    test('deletePushPrefsForDevice removes the row', () async {
      await db.upsertPushPrefs(
        deviceId: 'phone-1',
        enabled: true,
        muteSequenceFailed: false,
        muteWeatherUnsafe: false,
        muteGuidingLost: false,
        muteAutofocusFailed: false,
        muteEquipmentDisconnected: false,
      );

      await db.deletePushPrefsForDevice('phone-1');
      expect(await db.getPushPrefs('phone-1'), isNull);
    });
  });
}
