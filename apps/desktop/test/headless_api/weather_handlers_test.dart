import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/weather_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('WeatherHandlers', () {
    late ProviderContainer container;
    late WeatherHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = WeatherHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('radar data missing lat/lon returns JSON bad request', () async {
      final response = await translateHandlerErrors(handlers.handleGetRadarData(
        Request('GET', Uri.parse('http://localhost/api/weather/radar')),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Missing lat/lon query parameters');
    });

    test('cloud cover missing lat/lon returns JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetCloudCover(
        Request('GET', Uri.parse('http://localhost/api/weather/cloud-cover')),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Missing lat/lon query parameters');
    });

    test('malformed settings payload returns JSON internal error', () async {
      final response =
          await translateHandlerErrors(handlers.handleUpdateSettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/weather/settings'),
          body: '{',
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
