import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/route_metadata.dart';

void main() {
  group('headless API route contracts', () {
    // A-5b's route-table refactor relocated route
    // registrations from inline `router.<verb>(...)` calls in
    // `headless_api_server.dart` into per-domain `routes/*.dart` files,
    // and moved the advertised-endpoint catalog from
    // `_getAvailableEndpoints()` in the server class to
    // `availableHeadlessEndpoints()` in `handlers/system_handlers.dart`.
    // These scanners follow the new locations.

    test('advertised endpoints match registered API routes', () {
      final registered = _registeredApiRoutes();
      final advertised = _advertisedApiRoutes();

      expect(
        advertised.difference(registered),
        isEmpty,
        reason: 'Advertised endpoints must be registered by HeadlessApiServer.',
      );
      expect(
        registered.difference(advertised),
        isEmpty,
        reason:
            'Every registered API endpoint must be advertised in /api/info and OpenAPI.',
      );
    });

    test('NetworkBackend call sites map to registered server routes', () {
      final clientSource = _networkBackendSource();

      final registered = _registeredApiRoutes()
          .where((route) => !route.startsWith('WS '))
          .toSet();
      final clientRoutes = _networkBackendRoutes(clientSource);

      expect(
        clientRoutes.difference(registered),
        isEmpty,
        reason: 'NetworkBackend must not call endpoints missing on the server.',
      );
    });

    test('OpenAPI spec advertises every HTTP route from the route table', () {
      final advertised = _advertisedApiRoutes();
      final spec = buildOpenApiSpec(routes: advertised.toList(), port: 8080);
      final paths = spec['paths'] as Map<String, dynamic>;

      for (final route in advertised.where(
        (route) => !route.startsWith('WS '),
      )) {
        final parts = route.split(' ');
        final method = parts.first.toLowerCase();
        final path = openApiPath(parts.last);
        expect(
          paths[path],
          contains(method),
          reason: 'OpenAPI must include advertised route $route.',
        );
      }

      expect(
        paths.keys.any((path) => path == '/api/ws' || path == '/events'),
        isFalse,
        reason:
            'WebSocket endpoints are advertised in /api/info but not OpenAPI.',
      );
    });
  });
}

/// Scan all per-domain route files under `lib/headless_api/routes/` for
/// `HeadlessRoute(HttpMethod.<verb>, '<path>', ...)` entries, plus the
/// remaining inline `router.<verb>(...)` calls in `headless_api_server.dart`
/// (WebSocket upgrade routes still live there because they take a built
/// `Handler` closure).
Set<String> _registeredApiRoutes() {
  final routeFiles = Directory('lib/headless_api/routes')
      .listSync()
      .whereType<File>()
      .where(
        (f) =>
            f.path.endsWith('.dart') && !f.path.endsWith('headless_route.dart'),
      );
  final allSource = StringBuffer();
  for (final f in routeFiles) {
    allSource.writeln(f.readAsStringSync());
  }
  allSource.writeln(File('lib/headless_api_server.dart').readAsStringSync());
  return _scanRegisteredRoutes(allSource.toString());
}

Set<String> _scanRegisteredRoutes(String source) {
  final headlessRoutes =
      RegExp(
        r"HeadlessRoute\(\s*HttpMethod\.(get|post|put|delete)\s*,\s*'([^']+)'",
      ).allMatches(source).map((match) {
        final path = match.group(2)!;
        // Same WS-route classification rule as the legacy inline-route scanner:
        // `/api/ws`, `/events`, and `/ws/*` upgrade routes are advertised as
        // `WS <path>` in `availableHeadlessEndpoints()`, even though shelf_router
        // registers them as HTTP GET handlers. websocket_routes.dart does this.
        final isWsRoute =
            path == '/api/ws' || path == '/events' || path.startsWith('/ws/');
        // Static-file routes (`/dashboard`, `/broadcast`, `/run-watch`) are
        // registered but deliberately NOT advertised in the API catalog —
        // they're operator-facing pages, not endpoints clients call.
        if (!path.startsWith('/api/') && !isWsRoute) {
          return null;
        }
        final method = isWsRoute ? 'WS' : match.group(1)!.toUpperCase();
        return '$method ${_normalizeRoute(path)}';
      }).whereType<String>();
  final inlineRoutes = RegExp(r"router\.(get|post|put|delete)\(\s*'([^']+)'")
      .allMatches(source)
      .map((match) {
        final path = match.group(2)!;
        // also surface `/ws/*` upgrade routes (e.g. /ws/live-view)
        // so the advertised-vs-registered diff catches typos in either
        // place.
        final isWsRoute =
            path == '/api/ws' || path == '/events' || path.startsWith('/ws/');
        if (!path.startsWith('/api/') && !isWsRoute) {
          return null;
        }

        final method = isWsRoute ? 'WS' : match.group(1)!.toUpperCase();
        return '$method ${_normalizeRoute(path)}';
      })
      .whereType<String>();
  return {...headlessRoutes, ...inlineRoutes};
}

Set<String> _advertisedApiRoutes() {
  // A-5b moved this catalog from `_getAvailableEndpoints()` in
  // `headless_api_server.dart` to `availableHeadlessEndpoints()` in
  // `handlers/system_handlers.dart`.
  final source = File(
    'lib/headless_api/handlers/system_handlers.dart',
  ).readAsStringSync();
  final match = RegExp(
    r'List<String> availableHeadlessEndpoints\(\) \{\s*return (?:const )?\[(.*?)\];\s*\}',
    dotAll: true,
  ).firstMatch(source);

  expect(
    match,
    isNotNull,
    reason: 'availableHeadlessEndpoints() not found in system_handlers.dart.',
  );

  return RegExp(r"'([^']+)'").allMatches(match!.group(1)!).map((match) {
    final parts = match.group(1)!.split(' ');
    expect(parts, hasLength(2));
    return '${parts[0]} ${_normalizeRoute(parts[1])}';
  }).toSet();
}

Set<String> _networkBackendRoutes(String source) {
  return RegExp(
    r"_(get|post|put|delete|downloadBytes|postRaw|postRawBytes)\(\s*'([^']+)'",
  ).allMatches(source).map((match) {
    final method = switch (match.group(1)!) {
      'get' => 'GET',
      'post' => 'POST',
      'put' => 'PUT',
      'delete' => 'DELETE',
      'downloadBytes' => 'GET',
      'postRaw' => 'POST',
      'postRawBytes' => 'POST',
      _ => throw StateError('Unsupported NetworkBackend helper'),
    };
    return '$method /api/${_normalizeRoute(match.group(2)!)}';
  }).toSet();
}

String _networkBackendSource() {
  const backendRoot = '../../packages/nightshade_core/lib/src/backend';
  final sources = <String>[
    File('$backendRoot/network_backend.dart').readAsStringSync(),
  ];
  final partsDirectory = Directory('$backendRoot/network_backend');
  if (!partsDirectory.existsSync()) {
    return sources.single;
  }
  final partFiles =
      partsDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  sources.addAll(partFiles.map((file) => file.readAsStringSync()));
  return sources.join('\n');
}

String _normalizeRoute(String path) {
  final querylessPath = path.split('?').first;
  return querylessPath
      .replaceAllMapped(RegExp(r'<([^>|]+)(?:\|[^>]+)?>'), (_) => '{param}')
      .replaceAllMapped(RegExp(r'\$\{[^}]+\}'), (_) => '{param}')
      .replaceAllMapped(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), (_) => '{param}')
      .replaceAllMapped(RegExp(r'\{[^}]+\}'), (_) => '{param}');
}
