import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequencer_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('SequencerHandlers', () {
    late ProviderContainer container;
    late SequencerHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = SequencerHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('status disconnected backend failure returns JSON error', () async {
      final response = await handlers.handleSequencerStatus(
        Request('GET', Uri.parse('http://localhost/api/sequencer/status')),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('load malformed payload returns JSON internal server error', () async {
      final response = await handlers.handleSequencerLoad(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequencer/load'),
          body: jsonEncode({}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('dither config validates required numeric fields as JSON', () async {
      final response = await handlers.handleSequencerUpdateDitherConfig(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequencer/update-dither-config'),
          body: jsonEncode({'pixels': 5}),
        ),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
