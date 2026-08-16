/// Declarative route-table primitives for the headless API.
///
/// The headless server registers every HTTP route through this typed
/// table. Each per-domain route file exposes a top-level
/// `List<HeadlessRoute> buildXxxRoutes(handler refs)` function;
/// `server_lifecycle.dart` concatenates them all into a single
/// `allRoutes` list and calls [registerRoutes], which iterates the list
/// and invokes the appropriate `router.<verb>(...)` for each entry. As a
/// result [HeadlessRoute] is the single source of truth for the routing
/// table at runtime — there is no inline `router.get/post/...` wiring in
/// `start()` anymore.
///
/// Design choices baked in here:
///   * `List<HeadlessRoute>` over `Map<(method,path), handler>`. The
///     list preserves declaration order, which matters because
///     shelf_router matches paths in registration order — e.g.
///     `/api/images/backfill-thumbnails` must register BEFORE
///     `/api/images/<imageId>` or the literal path is shadowed by the
///     parametric one. A map would be unordered.
///   * `Function` handler type rather than the narrower
///     `FutureOr<Response> Function(Request)`. shelf_router accepts any
///     function whose arity matches the number of `<path-param>`
///     placeholders in the URL, and we have ~30 routes that take an
///     additional `String` parameter (`/api/jobs/<jobId>` etc.); using
///     `Function` lets the same `HeadlessRoute` type carry both shapes.
///   * Explicit [HttpMethod] enum rather than `String` constants — the
///     compiler enforces the dispatch in [registerRoutes] is exhaustive.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// HTTP verbs supported by the headless API router.
///
/// Mirrors the shelf_router public surface (`get`/`post`/`put`/
/// `delete`/`patch`) plus `head` and `options` so future audit
/// findings can wire those without adding a new enum value first.
enum HttpMethod { get, post, put, delete, patch, head, options }

/// A single declarative entry in the headless route table.
///
/// The pair `(method, path)` MUST be unique across every registered
/// list; [registerRoutes] does not de-duplicate, so a collision is a
/// shelf-router-detected ambiguity — the second registration silently
/// shadows the first.
class HeadlessRoute {
  /// HTTP verb the router binds [handler] to.
  final HttpMethod method;

  /// Path template understood by shelf_router. Path parameters use the
  /// angle-bracket form (`<id>`, `<sessionId>`, `<path|.*>`).
  final String path;

  /// Route handler. Accepts either `Future<Response> Function(Request)`
  /// or `Future<Response> Function(Request, String, ...)` for routes
  /// with path parameters. shelf_router introspects the arity at
  /// dispatch time.
  final Function handler;

  const HeadlessRoute(this.method, this.path, this.handler);
}

/// Register every [HeadlessRoute] in [routes] against the provided
/// [Router]. Call once per server start; the router itself is
/// re-created on every start so the registration is idempotent across
/// stop/start cycles.
///
/// Why a switch rather than per-method maps: the enum makes the dart
/// analyzer enforce the dispatch is exhaustive — if someone adds a new
/// [HttpMethod] value without updating the walker, the build fails at
/// compile time rather than silently dropping registrations.
void registerRoutes(Router router, List<HeadlessRoute> routes) {
  for (final route in withMethodNotAllowedFallbacks(routes)) {
    switch (route.method) {
      case HttpMethod.get:
        router.get(route.path, route.handler);
      case HttpMethod.post:
        router.post(route.path, route.handler);
      case HttpMethod.put:
        router.put(route.path, route.handler);
      case HttpMethod.delete:
        router.delete(route.path, route.handler);
      case HttpMethod.patch:
        router.patch(route.path, route.handler);
      case HttpMethod.head:
        router.head(route.path, route.handler);
      case HttpMethod.options:
        router.options(route.path, route.handler);
    }
  }
}

/// Verbs a synthesized 405 is generated for. `head` and `options` are
/// excluded deliberately: OPTIONS is CORS preflight, which the middleware
/// answers, and a HEAD is a legitimate probe of a GET route.
const _methodNotAllowedVerbs = <HttpMethod>{
  HttpMethod.get,
  HttpMethod.post,
  HttpMethod.put,
  HttpMethod.delete,
  HttpMethod.patch,
};

const _httpMethodNames = <HttpMethod, String>{
  HttpMethod.get: 'GET',
  HttpMethod.post: 'POST',
  HttpMethod.put: 'PUT',
  HttpMethod.delete: 'DELETE',
  HttpMethod.patch: 'PATCH',
  HttpMethod.head: 'HEAD',
  HttpMethod.options: 'OPTIONS',
};

/// Return [routes] with a `405 Method Not Allowed` entry synthesized for every
/// verb a LITERAL path does not implement.
///
/// Without the stub, a GET to a POST-only endpoint answers a question nobody
/// asked. `GET /api/calibration/darks/find-match` finds no literal GET route,
/// falls through to the parameterised `GET /api/calibration/darks/<id>`, and
/// that handler tries to parse `find-match` as an integer:
///
/// ```
/// GET /api/calibration/darks/find-match -> 400 {"error":"Path segment is not a
///                                               valid integer","field":"id"}
/// ```
///
/// The error names a field the caller never sent, about a value they never
/// supplied, for a path that exists — it points away from its own cause. Every
/// literal sibling on a prefix that also carries an `<id>` route has the same
/// trap.
///
/// Doing this here rather than per-route is the point: the route table is the
/// single source of truth for what exists, so a path added tomorrow gets the
/// correct 405 without anyone remembering to ask for it.
///
/// Ordering is load-bearing. Each stub is inserted immediately after the LAST
/// real registration of its path, which keeps it behind the handlers that do
/// implement the path and ahead of any parameterised route declared later —
/// the same ordering rule the literal routes themselves already depend on.
List<HeadlessRoute> withMethodNotAllowedFallbacks(List<HeadlessRoute> routes) {
  final implemented = <String, Set<HttpMethod>>{};
  final lastIndexOfPath = <String, int>{};
  for (var i = 0; i < routes.length; i++) {
    final route = routes[i];
    // Parameterised and catch-all paths are skipped: `<id>` matches whatever
    // the caller sent, so "this path exists but not with that verb" is not a
    // claim this function can make about them.
    if (route.path.contains('<')) continue;
    implemented.putIfAbsent(route.path, () => <HttpMethod>{}).add(route.method);
    lastIndexOfPath[route.path] = i;
  }

  final result = <HeadlessRoute>[];
  for (var i = 0; i < routes.length; i++) {
    final route = routes[i];
    result.add(route);
    if (lastIndexOfPath[route.path] != i) continue;

    final allowed = implemented[route.path]!;
    final allowHeader = _methodNotAllowedVerbs
        .where(allowed.contains)
        .map((m) => _httpMethodNames[m]!)
        .join(', ');
    for (final method in _methodNotAllowedVerbs) {
      if (allowed.contains(method)) continue;
      result.add(
        HeadlessRoute(
          method,
          route.path,
          _methodNotAllowed(route.path, allowHeader),
        ),
      );
    }
  }
  return result;
}

Response Function(Request) _methodNotAllowed(String path, String allowHeader) =>
    (Request request) => Response(
      405,
      body: jsonEncode({
        'error':
            '${request.method} is not supported for $path. This endpoint '
            'accepts: $allowHeader.',
        'code': 'method_not_allowed',
        'allow': allowHeader,
      }),
      headers: {
        'content-type': 'application/json',
        // RFC 9110 requires Allow on a 405, and it is what lets a client fix
        // itself without reading the route table.
        'allow': allowHeader,
      },
    );
