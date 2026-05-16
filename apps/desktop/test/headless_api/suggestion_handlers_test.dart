import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/suggestion_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('SuggestionHandlers', () {
    late ProviderContainer container;
    late SuggestionHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SuggestionHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('get config returns JSON default config', () async {
      final response = await translateHandlerErrors(handlers.handleGetConfig(
        Request('GET', Uri.parse('http://localhost/api/suggestions/config')),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['config'], isA<Map>());
    });

    test('invalid target ID returns JSON internal error', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetTargetScore(
        Request(
          'GET',
          Uri.parse('http://localhost/api/suggestions/score/not-an-id'),
        ),
        'not-an-id',
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
