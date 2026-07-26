import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/coimaging_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

/// Collaborative Sky WS3 — the unattended-rig headless mirror for the three
/// "make it real" hooks (framing-offset slew, capture-loop auto-contribute,
/// altitude baton tick). These exercise the new endpoints end-to-end through the
/// real provider graph; with no hub configured the service seam fails closed,
/// which is exactly the contract an appliance relies on (no silent slew/claim
/// without a hub). The deep coordination behaviour is covered by the hub +
/// nightshade_core suites.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoImagingHandlers (WS3 wiring)', () {
    late ProviderContainer container;
    late NightshadeDatabase db;
    late CoImagingHandlers handlers;

    setUp(() {
      // An in-memory DB (empty settings -> no hub configured) so the service
      // seam resolves "no membership" cleanly instead of reaching path_provider.
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = CoImagingHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('framing-offset rejects an empty session id', () async {
      final response = await translateHandlerErrors(
        handlers.handleFramingOffset(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/coimaging/sessions/ /framing-offset',
            ),
          ),
          ' ',
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('framing-offset is 404 when this rig is not a member', () async {
      // No hub configured -> framingOffsetFor returns null -> not-a-member, so
      // the rig is NOT handed a blind slew offset.
      final response = await translateHandlerErrors(
        handlers.handleFramingOffset(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/coimaging/sessions/s1/framing-offset',
            ),
          ),
          's1',
        ),
      );
      expect(response.statusCode, HttpStatus.notFound);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], contains('not an active member'));
    });

    test('sub-complete requires exposureSeconds', () async {
      final response = await translateHandlerErrors(
        handlers.handleSubComplete(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/api/coimaging/sessions/s1/sub-complete',
            ),
            body: jsonEncode(<String, Object?>{}),
          ),
          's1',
        ),
      );
      expect(
        response.statusCode,
        anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });

    test('auto-baton requires the rig location', () async {
      final response = await translateHandlerErrors(
        handlers.handleAutoBaton(
          Request(
            'POST',
            Uri.parse('http://localhost/api/coimaging/sessions/s1/baton/auto'),
            body: jsonEncode(<String, Object?>{'latitudeDeg': 47.0}),
          ),
          's1',
        ),
      );
      expect(
        response.statusCode,
        anyOf(HttpStatus.badRequest, HttpStatus.internalServerError),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['error'], isA<String>());
    });
  });
}
