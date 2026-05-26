/// Declarative route-table primitives for the headless API.
///
/// The headless server currently still registers HTTP routes inline by
/// calling `router.get/post/put/delete(...)` inside `start()`. This
/// module is the typed foundation a follow-up step will build on: each
/// per-domain route file will expose a top-level
/// `List<HeadlessRoute> buildXxxRoutes(handler refs)` function, and
/// `HeadlessApiServer.start()` will concatenate them all and call
/// [registerRoutes] which iterates and invokes the appropriate
/// `router.<verb>(...)` for each entry. Until that conversion lands,
/// [HeadlessRoute] is unused at runtime — checked in so the type, the
/// dispatch walker, and the design-decision rationale below are in
/// review and ready to consume.
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

import 'package:shelf_router/shelf_router.dart';

/// HTTP verbs supported by the headless API router.
///
/// Mirrors the shelf_router public surface (`get`/`post`/`put`/
/// `delete`/`patch`) plus `head` and `options` so future audit
/// findings can wire those without adding a new enum value first.
enum HttpMethod {
  get,
  post,
  put,
  delete,
  patch,
  head,
  options,
}

/// A single declarative entry in the headless route table.
///
/// The pair `(method, path)` MUST be unique across every registered
/// list; [registerRoutes] does not de-duplicate so a collision is a
/// shelf-router-detected ambiguity (the second registration silently
/// shadows the first, which would be a behaviour regression).
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
  for (final route in routes) {
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
