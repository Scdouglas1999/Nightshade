/// Declarative route table for the cookie / CSRF / ws-ticket auth
/// surface used by the web dashboard.
///
/// Counterpart to `handlers/auth_handlers.dart`. These endpoints carry
/// the same bearer-token requirement as every other `/api/*` route;
/// the dashboard exchanges its bearer token for an HttpOnly cookie via
/// `/api/auth/cookie` so JS code never touches the raw bearer.
library;

import '../handlers/auth_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [AuthHandlers].
List<HeadlessRoute> buildAuthRoutes(AuthHandlers h) => <HeadlessRoute>[
  // WebSocket auth ticket. Issues a one-shot ticket so browsers don't have
  // to leak the bearer token via WS query parameters.
  HeadlessRoute(HttpMethod.post, '/api/ws/ticket', h.handleWsTicketIssue),
  // HttpOnly cookie + CSRF token for the dashboard "remember me" path. The
  // dashboard exchanges a freshly-paired bearer token for a cookie that JS
  // cannot read, plus a CSRF token it must echo on every write. Logout
  // invalidates both.
  HeadlessRoute(HttpMethod.post, '/api/auth/cookie', h.handleAuthCookieIssue),
  HeadlessRoute(HttpMethod.get, '/api/auth/csrf', h.handleAuthCsrfFetch),
  HeadlessRoute(HttpMethod.post, '/api/auth/logout', h.handleAuthLogout),
];
