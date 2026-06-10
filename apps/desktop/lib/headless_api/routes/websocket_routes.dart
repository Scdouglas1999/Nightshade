/// Declarative route table for the WebSocket-upgrade endpoints.
///
/// These routes are special because [HeadlessApiServer.start] hands
/// them pre-built [Handler] closures rather than method tear-offs on a
/// per-domain handler class. Two reasons:
///
///   1. `/api/ws` and `/events` BOTH bind the same upgrade callback;
///      the closure factory in the server captures `_handleWebSocket
///      WithQuery` plus the per-request auth identity that the auth
///      middleware stashed in the request context. Lifting that
///      factory into a route-builder argument keeps the
///      [HeadlessApiServer] private state private.
///   2. `/ws/live-view` upgrades onto [LiveViewStreamHandlers.
///      handleSocket]; that is a pre-built shelf [Handler] closure
///      because the underlying `webSocketHandler` from
///      `package:shelf_web_socket` returns a [Handler], not a method
///      ref.
///
/// Therefore the API of this builder is intentionally function-typed,
/// not handler-class-typed.
library;

import 'package:shelf/shelf.dart';

import 'headless_route.dart';

/// Build the declarative route table for the WebSocket-upgrade
/// endpoints.
///
/// [eventsHandler] is shared between `/api/ws` and `/events`. The
/// legacy `/events` path is kept for `NetworkBackend` compatibility
/// (pinned mobile / web builds that pre-date the rename).
List<HeadlessRoute> buildWebSocketRoutes({
  required Handler eventsHandler,
  required Handler liveViewHandler,
}) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/ws', eventsHandler),
  HeadlessRoute(HttpMethod.get, '/events', eventsHandler),
  HeadlessRoute(HttpMethod.get, '/ws/live-view', liveViewHandler),
];
