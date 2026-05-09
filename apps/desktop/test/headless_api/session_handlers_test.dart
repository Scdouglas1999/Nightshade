import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/session_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('SessionHandlers', () {
    late ProviderContainer container;
    late SessionHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SessionHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('unsupported export format returns JSON bad request', () async {
      final response = await handlers.handleExportSession(
        Request(
          'GET',
          Uri.parse('http://localhost/api/sessions/1/export/pdf'),
        ),
        '1',
        'pdf',
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], 'Unsupported export format');
      expect(body['supportedFormats'], ['json', 'csv', 'html']);
    });

    test('start polar alignment malformed payload returns JSON internal error',
        () async {
      final response = await handlers.handleStartPolarAlignment(
        Request(
          'POST',
          Uri.parse('http://localhost/api/polar-alignment/start'),
          body: jsonEncode({}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('thumbnail invalid image ID returns JSON internal error', () async {
      final response = await handlers.handleGetImageThumbnail(
        Request('GET', Uri.parse('http://localhost/api/images/nope/thumbnail')),
        'nope',
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
