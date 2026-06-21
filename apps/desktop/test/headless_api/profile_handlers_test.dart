import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/profile_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileHandlers', () {
    late ProviderContainer container;
    late NightshadeDatabase db;
    late ProfileHandlers handlers;

    setUp(() {
      // Hermetic in-memory DB: the GUI's real DB resolves its file via
      // path_provider, which a unit-test isolate cannot service. Overriding it
      // here keeps these error-translation tests deterministic (the real DB
      // would otherwise leak a MissingPluginException from its lazy open).
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = ProfileHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('get profiles returns a JSON envelope', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetProfiles(
          Request('GET', Uri.parse('http://localhost/api/profiles')),
        ),
      );

      expect(response.headers['content-type'], 'application/json');
      // With a working (empty) DB the handler succeeds with a profiles array;
      // the contract under test is that it always returns structured JSON, not
      // a thrown stack trace.
      expect(response.statusCode, HttpStatus.ok);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['profiles'], isA<List>());
    });

    test(
      'save profile malformed payload returns JSON internal error',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSaveProfile(
            Request(
              'POST',
              Uri.parse('http://localhost/api/profiles'),
              body: jsonEncode({}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );

    test(
      'set location accepts null shape but disconnected backend returns JSON',
      () async {
        final response = await translateHandlerErrors(
          handlers.handleSetLocation(
            Request(
              'POST',
              Uri.parse('http://localhost/api/settings/location'),
              body: jsonEncode({'location': null}),
            ),
          ),
        );

        expect(
          response.statusCode,
          anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
        );
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], isA<String>());
      },
    );
  });
}
