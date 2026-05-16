import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/guiding_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('GuidingHandlers', () {
    late ProviderContainer container;
    late GuidingHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = GuidingHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('algo param names validates axis with JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handlePhd2GetAlgoParamNames(
        Request(
          'GET',
          Uri.parse('http://localhost/api/phd2/algo-param-names?axis=bad'),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        "Missing or invalid 'axis' query parameter",
      );
    });

    test('set algo param validates required value with JSON bad request',
        () async {
      final response =
          await translateHandlerErrors(handlers.handlePhd2SetAlgoParam(
        Request(
          'POST',
          Uri.parse('http://localhost/api/phd2/algo-param'),
          body: jsonEncode({'axis': 'ra', 'name': 'minMove'}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'value is required');
    });

    test('guider lock position validates missing coordinates as JSON',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleGuiderSetLockPosition(
        Request(
          'POST',
          Uri.parse('http://localhost/api/guider/set-lock-position'),
          body: jsonEncode({'deviceId': 'guider-1', 'x': 10}),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'y is required');
    });

    test('disconnected backend failures return JSON internal server error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handlePhd2GetStatus(
        Request('GET', Uri.parse('http://localhost/api/phd2/status')),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
