import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/framing_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('FramingHandlers', () {
    late ProviderContainer container;
    late FramingHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = FramingHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('slew to target malformed payload returns JSON internal error',
        () async {
      final response = await translateHandlerErrors(handlers.handleSlewToTarget(
        Request(
          'POST',
          Uri.parse('http://localhost/api/framing/slew-to-target'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('center on target malformed payload returns JSON internal error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleCenterOnTarget(
        Request(
          'POST',
          Uri.parse('http://localhost/api/framing/center-on-target'),
          body: '{',
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('rotate to malformed payload returns JSON internal error', () async {
      final response = await translateHandlerErrors(handlers.handleRotateTo(
        Request(
          'POST',
          Uri.parse('http://localhost/api/framing/rotate-to'),
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
