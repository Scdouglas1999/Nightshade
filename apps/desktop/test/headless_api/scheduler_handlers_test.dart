import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/scheduler_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('SchedulerHandlers', () {
    late ProviderContainer container;
    late SchedulerHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SchedulerHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('altitude missing coordinates returns JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleCalculateAltitude(
        Request('GET', Uri.parse('http://localhost/api/scheduler/altitude')),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Missing required parameters: ra and dec');
    });

    test('altitude invalid time returns JSON bad request', () async {
      final response =
          await translateHandlerErrors(handlers.handleCalculateAltitude(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/scheduler/altitude?ra=12.5&dec=45&time=nope',
          ),
        ),
      ));

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(
        body['error'],
        'Invalid time format. Use ISO8601 or epoch milliseconds.',
      );
    });

    test('optimize targets malformed payload returns JSON internal error',
        () async {
      final response =
          await translateHandlerErrors(handlers.handleOptimizeTargets(
        Request(
          'POST',
          Uri.parse('http://localhost/api/scheduler/optimize-targets'),
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
