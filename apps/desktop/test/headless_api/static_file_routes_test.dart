import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/static_file_handlers.dart';
import 'package:nightshade_desktop/headless_api/routes/headless_route.dart';
import 'package:nightshade_desktop/headless_api/routes/static_file_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// D4W-4 — the run-watch SPA must have exactly one address.
///
/// The service worker registers with scope `/run-watch/`, so a document served
/// at `/run-watch` is outside it and nothing controls the page. Measured
/// against the release bundle: with the daemon killed, `/run-watch` rendered
/// Chrome's ERR_CONNECTION_REFUSED interstitial while `/run-watch/` loaded the
/// cached offline shell in the same browser, the same second. Both spellings
/// answered 200 and neither redirected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LoggingService logger;
  late Router router;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_static_routes_test_');
    logger = LoggingService(
      applicationSupportDirectoryProvider: () async => tempDir,
      nativeInitWithLogging: ({logDirectory}) {},
      nativeInit: () {},
      currentLogFileProvider: () => null,
    );
    await logger.ensureInitialized();
    router = Router();
    registerRoutes(
      router,
      buildStaticFileRoutes(StaticFileHandlers(logger: logger)),
    );
  });

  tearDown(() async {
    await logger.dispose();
    await tempDir.delete(recursive: true);
  });

  test('GET /run-watch redirects permanently to the canonical URL', () async {
    final response = await router(
      Request('GET', Uri.parse('http://localhost/run-watch')),
    );

    expect(response.statusCode, HttpStatus.movedPermanently);
    expect(response.headers['location'], '/run-watch/');
  });

  test('the redirect carries the query string across', () async {
    final response = await router(
      Request('GET', Uri.parse('http://localhost/run-watch?token=abc&x=1')),
    );

    expect(response.statusCode, HttpStatus.movedPermanently);
    expect(response.headers['location'], '/run-watch/?token=abc&x=1');
  });

  test('the redirect asks for no credential of its own', () async {
    final response = await router(
      Request('GET', Uri.parse('http://localhost/run-watch')),
    );

    expect(response.headers['www-authenticate'], isNull);
    expect(response.headers['set-cookie'], isNull);
    expect(await response.readAsString(), isEmpty);
  });

  test('GET /run-watch/ is served, never redirected', () async {
    final response = await router(
      Request('GET', Uri.parse('http://localhost/run-watch/')),
    );

    expect(
      response.statusCode,
      isNot(HttpStatus.movedPermanently),
      reason: 'the canonical URL must not bounce — that is a redirect loop',
    );
    expect(response.headers['location'], isNull);
  });

  test('nested run-watch assets are untouched by the redirect', () async {
    for (final path in ['/run-watch/sw.js', '/run-watch/js/run-watch.js']) {
      final response = await router(
        Request('GET', Uri.parse('http://localhost$path')),
      );
      expect(
        response.statusCode,
        isNot(HttpStatus.movedPermanently),
        reason: '$path is an asset, not the SPA entry point',
      );
    }
  });
}
