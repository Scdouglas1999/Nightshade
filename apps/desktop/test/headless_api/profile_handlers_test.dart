import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/handlers/profile_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('ProfileHandlers', () {
    late ProviderContainer container;
    late ProfileHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = ProfileHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    test('get profiles disconnected backend failure returns JSON', () async {
      final response = await translateHandlerErrors(handlers.handleGetProfiles(
        Request('GET', Uri.parse('http://localhost/api/profiles')),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('save profile malformed payload returns JSON internal error',
        () async {
      final response = await translateHandlerErrors(handlers.handleSaveProfile(
        Request(
          'POST',
          Uri.parse('http://localhost/api/profiles'),
          body: jsonEncode({}),
        ),
      ));

      expect(response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError));
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test(
        'set location accepts null shape but disconnected backend returns JSON',
        () async {
      final response = await translateHandlerErrors(handlers.handleSetLocation(
        Request(
          'POST',
          Uri.parse('http://localhost/api/settings/location'),
          body: jsonEncode({'location': null}),
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
