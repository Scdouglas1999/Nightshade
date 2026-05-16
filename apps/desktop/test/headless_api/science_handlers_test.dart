import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/science_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('ScienceHandlers', () {
    late ProviderContainer container;
    late ScienceHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = ScienceHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('invalid session bundle ID returns JSON internal error', () async {
      final response =
          await translateHandlerErrors(handlers.handleGetSessionBundle(
        Request(
          'GET',
          Uri.parse('http://localhost/api/science/session/not-an-id/bundle'),
        ),
        'not-an-id',
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('compute transform without filter returns JSON bad request', () async {
      final response = await translateHandlerErrors(
          handlers.handleComputePhotometricTransform(
        Request(
          'POST',
          Uri.parse(
              'http://localhost/api/science/calibration/compute-transform'),
          body: jsonEncode({'starMatches': []}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'filterName is required');
    });

    test('update settings malformed payload returns JSON internal error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleUpdateScienceSettings(
        Request(
          'POST',
          Uri.parse('http://localhost/api/science/settings'),
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
