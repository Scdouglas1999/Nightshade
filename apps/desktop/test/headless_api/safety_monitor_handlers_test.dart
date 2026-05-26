import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/backend/disconnected_backend.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';
import 'package:nightshade_desktop/headless_api/handlers/safety_monitor_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafetyMonitorHandlers', () {
    late ProviderContainer container;
    late SafetyMonitorHandlers handlers;
    late NightshadeDatabase db;

    setUp(() async {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref),
          ),
        ],
      );
      handlers = SafetyMonitorHandlers(container);
      await container.read(appSettingsProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('get safety settings returns persisted defaults', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetSafetySettings(
        Request('GET', Uri.parse('http://localhost/api/safety/settings')),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['failMode'], 'fail_closed');
      expect(body['autoStopOnUnsafe'], isA<bool>());
      expect(body['checkIntervalSeconds'], isA<int>());
    });

    test('invalid fail mode returns JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleUpdateSafetySettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/safety/settings'),
          body: jsonEncode({'failMode': 'ignore'}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'],
          contains('Must be one of: fail_open, fail_closed, warn_only'));
    });

    test('valid safety settings payload persists and returns updated settings',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleUpdateSafetySettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/safety/settings'),
          body: jsonEncode({
            'checkIntervalSeconds': 45,
            'autoStopOnUnsafe': false,
            'warningDelaySeconds': 90,
          }),
        ),
      ));

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'updated');
      final settings = body['settings'] as Map;
      expect(settings['checkIntervalSeconds'], 45);
      expect(settings['autoStopOnUnsafe'], isFalse);
      expect(settings['warningDelaySeconds'], 90);
    });

    test('acknowledge unsafe missing reason returns JSON bad request',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleAcknowledgeUnsafe(
        Request(
          'POST',
          Uri.parse('http://localhost/api/safety/acknowledge'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'reason is required');
    });

    test('acknowledge unsafe with reason returns snooze metadata', () async {
      final response =
          await translateHandlerErrors(handlers.handleAcknowledgeUnsafe(
        Request(
          'POST',
          Uri.parse('http://localhost/api/safety/acknowledge'),
          body: jsonEncode({
            'reason': 'Operator verified sky is clear',
            'durationMinutes': 30,
          }),
        ),
      ));

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'acknowledged');
      expect(body['snoozeUntil'], isA<String>());
    });
  });
}

class _NoopSafetyBackend extends DisconnectedBackend {
  @override
  Future<void> sequencerSetSafetyFailMode(String mode) async {}

  @override
  Future<void> sequencerSetSafetyCheckIntervalSeconds(int seconds) async {}
}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref) {
    state = _NoopSafetyBackend();
  }
}
