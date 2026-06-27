// End-to-end proof for NAME-001: the Living Sky atlas handlers emit the
// unified error envelope, and those responses decode through the single
// converged client parser ([ServerError.tryFromJson]) with a non-empty
// machine code — while still carrying a human-readable `error` string for
// legacy display clients.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/atlas_handlers.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('AtlasHandlers error envelope', () {
    late ProviderContainer container;
    late AtlasHandlers handlers;

    setUp(() {
      container = ProviderContainer();
      handlers = AtlasHandlers(container);
    });

    tearDown(() {
      container.dispose();
    });

    Future<void> expectUnifiedError(
      Response response, {
      required int expectedStatus,
    }) async {
      expect(response.statusCode, expectedStatus);
      expect(response.headers['content-type'], 'application/json');

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      // Legacy display field is still a human-readable string.
      expect(body['error'], isA<String>());
      expect((body['error'] as String), isNotEmpty);

      // Machine code present and non-empty.
      expect(body['code'], isA<String>());
      expect((body['code'] as String), isNotEmpty);

      // Decodes through the single converged parser with a non-empty code.
      final parsed = ServerError.tryFromJson(body, httpStatus: expectedStatus);
      expect(parsed, isNotNull);
      expect(parsed!.code, isNotEmpty);
      expect(parsed.message, body['message']);
      expect(parsed.httpStatus, expectedStatus);
    }

    test(
      'GET region with a non-integer id returns a 400 unified error',
      () async {
        final response = await handlers.handleGetRegion(
          Request(
            'GET',
            Uri.parse('http://localhost/api/atlas/region/not-an-id'),
          ),
          'not-an-id',
        );

        await expectUnifiedError(
          response,
          expectedStatus: HttpStatus.badRequest,
        );
      },
    );

    test(
      'GET region cutout with a non-integer id returns a 400 unified error',
      () async {
        final response = await handlers.handleGetRegionCutout(
          Request(
            'GET',
            Uri.parse('http://localhost/api/atlas/region/nope/cutout'),
          ),
          'nope',
        );

        await expectUnifiedError(
          response,
          expectedStatus: HttpStatus.badRequest,
        );
      },
    );

    test('GET region timeline with a non-integer id returns a 400 unified '
        'error', () async {
      final response = await handlers.handleGetRegionTimeline(
        Request(
          'GET',
          Uri.parse('http://localhost/api/atlas/region/xyz/timeline'),
        ),
        'xyz',
      );

      await expectUnifiedError(response, expectedStatus: HttpStatus.badRequest);
    });
  });
}
