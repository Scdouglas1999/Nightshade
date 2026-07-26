// Regression coverage for `GET /api/push/targets` — the host's answer to
// "can a critical alert actually reach a phone right now?".
//
// Observed live (2026-07-25): Settings -> Notifications rendered "Push
// critical alerts to mobile" toggled ON with nothing indicating that this
// device could not receive them. On Android in a stock build none ever can —
// `apps/mobile/android/app/google-services.json` is absent, so the client logs
// `FCM not configured (no google-services.json); push registration dormant`
// and never registers a token. There was no endpoint that could tell the UI
// that, so this one exists to make the setting stop asserting a capability the
// system does not have.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/auth/pairing_service.dart';
import 'package:nightshade_desktop/headless_api/handlers/push_handlers.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('GET /api/push/targets', () {
    late PairingDatabase database;
    late PairingService pairingService;
    var cloudConfigured = false;
    late PushHandlers handlers;

    setUp(() {
      database = PairingDatabase.forTesting(NativeDatabase.memory());
      pairingService = PairingService(database: database);
      cloudConfigured = false;
      handlers = PushHandlers(
        ensurePairingService: () => pairingService,
        logger: LoggingService(
          nativeInitWithLogging: ({logDirectory}) {},
          nativeInit: () {},
          currentLogFileProvider: () => null,
        ),
        cloudDeliveryConfigured: () => cloudConfigured,
      );
    });

    tearDown(() async {
      await pairingService.close();
    });

    Future<Map<String, dynamic>> targets() async {
      final response = await handlers.handleGetTargets(
        Request('GET', Uri.parse('http://localhost/api/push/targets')),
      );
      expect(response.statusCode, HttpStatus.ok);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    Future<void> pairDevice(String deviceId) async {
      await database.addPairedDevice(
        deviceId: deviceId,
        deviceName: 'Device $deviceId',
        deviceType: 'mobile',
        sessionToken: 'token-$deviceId',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
    }

    test('reports zero targets when nothing has registered', () async {
      final body = await targets();

      expect(body['registeredDeviceCount'], 0);
      expect(body['fcmTokenCount'], 0);
      expect(body['apnsTokenCount'], 0);
      expect(body['cloudDeliveryConfigured'], isFalse);
      // The single question the UI asks.
      expect(body['canDeliver'], isFalse);

      final parsed = PushDeliveryTargets.fromJson(body);
      expect(parsed.canDeliver, isFalse);
      expect(parsed.blockedReason, isNotNull);
    });

    test(
      'a registered token alone is NOT enough when no channel is configured',
      () async {
        await pairDevice('phone-1');
        await database.upsertPushToken(
          deviceId: 'phone-1',
          platform: 'fcm',
          token: 'fcm-token-value',
        );

        final body = await targets();
        expect(body['registeredDeviceCount'], 1);
        expect(body['fcmTokenCount'], 1);
        expect(body['cloudDeliveryConfigured'], isFalse);
        // Registered, but the host has nothing to send WITH.
        expect(body['canDeliver'], isFalse);
        expect(
          PushDeliveryTargets.fromJson(body).blockedReason,
          contains('no push delivery configured'),
        );
      },
    );

    test('reports a deliverable target once both halves are true', () async {
      cloudConfigured = true;
      await pairDevice('phone-1');
      await database.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'fcm',
        token: 'fcm-token-value',
      );

      final body = await targets();
      expect(body['registeredDeviceCount'], 1);
      expect(body['canDeliver'], isTrue);
      expect(PushDeliveryTargets.fromJson(body).blockedReason, isNull);
    });

    test('counts devices, not tokens, and splits by platform', () async {
      cloudConfigured = true;
      await pairDevice('phone-1');
      await pairDevice('phone-2');
      // One device registered on both platforms — still ONE device.
      await database.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'fcm',
        token: 'fcm-1',
      );
      await database.upsertPushToken(
        deviceId: 'phone-1',
        platform: 'apns',
        token: 'apns-1',
      );
      await database.upsertPushToken(
        deviceId: 'phone-2',
        platform: 'apns',
        token: 'apns-2',
      );

      final body = await targets();
      expect(body['registeredDeviceCount'], 2);
      expect(body['fcmTokenCount'], 1);
      expect(body['apnsTokenCount'], 2);
    });

    test('never returns token values or device identifiers', () async {
      cloudConfigured = true;
      await pairDevice('phone-secret');
      await database.upsertPushToken(
        deviceId: 'phone-secret',
        platform: 'fcm',
        token: 'super-secret-token-value',
      );

      final response = await handlers.handleGetTargets(
        Request('GET', Uri.parse('http://localhost/api/push/targets')),
      );
      final raw = await response.readAsString();

      expect(raw, isNot(contains('super-secret-token-value')));
      expect(raw, isNot(contains('phone-secret')));
    });

    test(
      'tracks the live delivery configuration, not a boot snapshot',
      () async {
        await pairDevice('phone-1');
        await database.upsertPushToken(
          deviceId: 'phone-1',
          platform: 'fcm',
          token: 'fcm-1',
        );

        expect((await targets())['canDeliver'], isFalse);
        cloudConfigured = true;
        expect((await targets())['canDeliver'], isTrue);
      },
    );
  });
}
