import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/planetarium_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('PlanetariumHandlers', () {
    late ProviderContainer container;
    late PlanetariumHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = PlanetariumHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('subscribe info returns JSON websocket metadata', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetSubscribeInfo(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/api/planetarium/subscribe-info'),
        ),
      ));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['websocketUrl'], 'ws://localhost:8080/api/ws');
      expect(body['alternateUrl'], 'ws://localhost:8080/events');
      expect(body['pingPongSupport'], isTrue);
      expect(body['eventTypes'], contains('mount_position'));
    });

    test('catalog region missing parameters returns JSON bad request',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleCatalogRegion(
        Request(
          'GET',
          Uri.parse('http://localhost/api/planetarium/catalog/region?ra=12.5'),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'Missing required parameters: ra, dec, radius (in degrees)',
      );
    });

    test('slew to malformed payload returns JSON internal error', () async {
      final response = await translateHandlerErrors(handlers.handleSlewTo(
        Request(
          'POST',
          Uri.parse('http://localhost/api/planetarium/slew-to'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
