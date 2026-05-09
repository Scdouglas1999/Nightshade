import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/analytics_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('AnalyticsHandlers', () {
    late ProviderContainer container;
    late AnalyticsHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = AnalyticsHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('invalid session ID returns JSON internal error', () async {
      final response = await handlers.handleGetSessionById(
        Request('GET', Uri.parse('http://localhost/api/sessions/not-an-id')),
        'not-an-id',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('update session malformed payload returns JSON internal error',
        () async {
      final response = await handlers.handleUpdateSession(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/sessions/1'),
          body: '{',
        ),
        '1',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('invalid target statistics ID returns JSON internal error', () async {
      final response = await handlers.handleGetTargetStatistics(
        Request(
          'GET',
          Uri.parse('http://localhost/api/analytics/target/not-an-id'),
        ),
        'not-an-id',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
