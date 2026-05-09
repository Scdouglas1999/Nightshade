import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/route_metadata.dart';

void main() {
  group('headless API route contracts', () {
    test('advertised endpoints match registered API routes', () {
      final serverSource =
          File('lib/headless_api_server.dart').readAsStringSync();

      final registered = _registeredApiRoutes(serverSource);
      final advertised = _advertisedApiRoutes(serverSource);

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
      final serverSource =
          File('lib/headless_api_server.dart').readAsStringSync();
      final clientSource = File(
        '../../packages/nightshade_core/lib/src/backend/network_backend.dart',
      ).readAsStringSync();

      final registered = _registeredApiRoutes(serverSource)
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
      final serverSource =
          File('lib/headless_api_server.dart').readAsStringSync();
      final advertised = _advertisedApiRoutes(serverSource);
      final spec = buildOpenApiSpec(routes: advertised.toList(), port: 8080);
      final paths = spec['paths'] as Map<String, dynamic>;

      for (final route
          in advertised.where((route) => !route.startsWith('WS '))) {
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

Set<String> _registeredApiRoutes(String source) {
  return RegExp(r"router\.(get|post|put|delete)\(\s*'([^']+)'")
      .allMatches(source)
      .map((match) {
        final path = match.group(2)!;
        if (!path.startsWith('/api/') && path != '/events') {
          return null;
        }

        final method = path == '/api/ws' || path == '/events'
            ? 'WS'
            : match.group(1)!.toUpperCase();
        return '$method ${_normalizeRoute(path)}';
      })
      .whereType<String>()
      .toSet();
}

Set<String> _advertisedApiRoutes(String source) {
  final match = RegExp(
    r'List<String> _getAvailableEndpoints\(\) \{\s*return \[(.*?)\];\s*\}',
    dotAll: true,
  ).firstMatch(source);

  expect(match, isNotNull, reason: 'HeadlessApiServer route table not found.');

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

String _normalizeRoute(String path) {
  final querylessPath = path.split('?').first;
  return querylessPath
      .replaceAllMapped(
        RegExp(r'<([^>|]+)(?:\|[^>]+)?>'),
        (_) => '{param}',
      )
      .replaceAllMapped(
        RegExp(r'\$\{[^}]+\}'),
        (_) => '{param}',
      )
      .replaceAllMapped(
        RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'),
        (_) => '{param}',
      )
      .replaceAllMapped(
        RegExp(r'\{[^}]+\}'),
        (_) => '{param}',
      );
}
