/// Declarative route table for static-file serving (dashboard + run-
/// watch SPAs).
///
/// Counterpart to `handlers/static_file_handlers.dart`. The handler
/// class owns SPA-directory resolution, the MIME-type table, the CSP
/// security headers, and the symlink-traversal guard.
library;

import '../handlers/static_file_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [StaticFileHandlers].
List<HeadlessRoute> buildStaticFileRoutes(
  StaticFileHandlers h,
) => <HeadlessRoute>[
  // Site root: browsers get sent to the dashboard, machines get a JSON pointer.
  HeadlessRoute(HttpMethod.get, '/', h.handleRoot),
  // Requested unprompted by every browser; 204 so it is not an auth failure.
  HeadlessRoute(HttpMethod.get, '/favicon.ico', h.handleFavicon),

  // Web Dashboard
  HeadlessRoute(HttpMethod.get, '/dashboard', h.handleDashboardIndex),
  HeadlessRoute(HttpMethod.get, '/dashboard/', h.handleDashboardIndex),
  HeadlessRoute(HttpMethod.get, '/dashboard/<path|.*>', h.handleDashboardFile),

  // Run-Watch SPA static files. Mirrors the /dashboard
  // resolver but searches `web_run_watch/` next to the executable
  // and in the source tree.
  HeadlessRoute(HttpMethod.get, '/run-watch', h.handleRunWatchIndex),
  HeadlessRoute(HttpMethod.get, '/run-watch/', h.handleRunWatchIndex),
  HeadlessRoute(HttpMethod.get, '/run-watch/<path|.*>', h.handleRunWatchFile),
];
