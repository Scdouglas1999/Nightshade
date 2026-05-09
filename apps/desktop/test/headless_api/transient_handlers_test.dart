import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/transient_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('TransientHandlers', () {
    late ProviderContainer container;
    late TransientHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = TransientHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('get settings returns JSON defaults', () async {
      final response = await handlers.handleGetSettings(
        Request('GET', Uri.parse('http://localhost/api/transients/settings')),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['settings'], isA<Map>());
    });

    test('update settings malformed payload returns JSON internal error',
        () async {
      final response = await handlers.handleUpdateSettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/transients/settings'),
          body: '{',
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('queue transient returns JSON state', () async {
      final response = await handlers.handleQueueTransient(
        Request('POST', Uri.parse('http://localhost/api/transients/t-1/queue')),
        't-1',
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'queued');
      expect(body['alertId'], 't-1');
      expect(body['queuedCount'], 1);
    });
  });
}
