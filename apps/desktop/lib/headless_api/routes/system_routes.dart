/// Declarative route table for the core system / health endpoints.
///
/// Counterpart to `handlers/system_handlers.dart`. These are public-by-
/// design endpoints (`/api/info`, `/api/status`) plus the OpenAPI spec
/// surface and a one-shot self-test. None of them carry per-route auth
/// — the global `_authMiddleware` in [HeadlessApiServer.start] adds
/// `/api/info` and `/api/status` to its `publicPaths` set; everything
/// else falls through to bearer-token enforcement.
library;

import '../handlers/system_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SystemHandlers].
///
/// Order is preserved exactly as it appeared in the legacy
/// `router.<verb>(...)` block so shelf_router's first-hit matching
/// behaviour is identical.
List<HeadlessRoute> buildSystemRoutes(SystemHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/info', h.handleInfo),
  HeadlessRoute(HttpMethod.get, '/api/status', h.handleStatus),
  HeadlessRoute(HttpMethod.get, '/api/self-test', h.handleSelfTest),
  HeadlessRoute(HttpMethod.get, '/api/openapi.json', h.handleOpenApiSpec),
];
