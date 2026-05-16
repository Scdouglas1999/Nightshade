import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/safety_monitor_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('SafetyMonitorHandlers', () {
    late ProviderContainer container;
    late SafetyMonitorHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SafetyMonitorHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('get safety settings returns JSON defaults', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetSafetySettings(
        Request('GET', Uri.parse('http://localhost/api/safety/settings')),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['failMode'], 'fail_closed');
      expect(body['autoStopOnUnsafe'], isTrue);
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

    test('valid safety settings payload returns JSON not implemented',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleUpdateSafetySettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/safety/settings'),
          body: jsonEncode({'failMode': 'fail_closed'}),
        ),
      ));

      expect(response.statusCode, HttpStatus.notImplemented);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], contains('not yet implemented'));
      expect(body['receivedPayload'], {'failMode': 'fail_closed'});
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
  });
}
