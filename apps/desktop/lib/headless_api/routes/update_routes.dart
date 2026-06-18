/// Declarative route table for the OTA-update surface.
///
/// Counterpart to `handlers/update_handlers.dart`. The handler is
/// optional: tests and headless deployments that opt out of OTA leave
/// the UpdateController unwired, in which case
/// [HeadlessApiServer.start] simply does NOT include this route list.
/// That makes the routes return 404 from the router itself — matching
/// the legacy behaviour exactly.
library;

import '../handlers/update_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [UpdateHandlers]. Only call
/// this when [HeadlessApiServer.setUpdateController] has been
/// invoked, i.e. when an [UpdateController] is wired into the server.
List<HeadlessRoute> buildUpdateRoutes(UpdateHandlers h) => <HeadlessRoute>[
  // NOTE: `/api/system/version` is now an always-on route served by
  // SystemHandlers (see system_routes.dart) so the running build is readable
  // even without an UpdateController. It is intentionally NOT registered here
  // to avoid a duplicate route.
  HeadlessRoute(
    HttpMethod.post,
    '/api/system/update/check',
    h.handleCheckForUpdate,
  ),
  HeadlessRoute(HttpMethod.get, '/api/system/update/status', h.handleGetStatus),
  HeadlessRoute(
    HttpMethod.post,
    '/api/system/update/download',
    h.handleDownload,
  ),
  HeadlessRoute(HttpMethod.post, '/api/system/update/apply', h.handleApply),
  HeadlessRoute(HttpMethod.post, '/api/system/update/abort', h.handleAbort),
  HeadlessRoute(
    HttpMethod.post,
    '/api/system/update/rollback',
    h.handleRollback,
  ),
  HeadlessRoute(HttpMethod.get, '/api/system/update/staged', h.handleGetStaged),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/system/update/staged',
    h.handleDiscardStaged,
  ),
];
