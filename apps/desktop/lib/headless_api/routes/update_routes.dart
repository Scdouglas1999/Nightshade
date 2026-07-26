/// Declarative route table for the OTA-update surface.
///
/// Counterpart to `handlers/update_handlers.dart`. The controller is optional,
/// but the routes remain present and return a structured 503 until it is wired.
library;

import 'package:shelf/shelf.dart';

import '../handlers/update_handlers.dart';
import '../response_helpers.dart';
import 'headless_route.dart';

/// Build the declarative route table for the optional OTA controller.
///
/// The routes are always registered and resolve the current handler for each
/// request. Both GUI and headless hosts provision the update stack after the
/// HTTP socket is already serving; capturing a nullable handler at router-build
/// time left every advertised `/api/system/update/*` endpoint permanently 404
/// even after [HeadlessApiServer.setUpdateController] succeeded.
List<HeadlessRoute> buildUpdateRoutes(
  UpdateHandlers? Function() resolveHandlers,
) {
  Handler dispatch(
    Future<Response> Function(UpdateHandlers handlers, Request request) invoke,
  ) {
    return (request) {
      final handlers = resolveHandlers();
      if (handlers == null) {
        return Future.value(
          jsonError(
            code: 'update_unavailable',
            message: 'OTA update service is not configured on this host.',
            statusCode: 503,
          ),
        );
      }
      return invoke(handlers, request);
    };
  }

  return <HeadlessRoute>[
    // NOTE: `/api/system/version` is now an always-on route served by
    // SystemHandlers (see system_routes.dart) so the running build is readable
    // even without an UpdateController. It is intentionally NOT registered here
    // to avoid a duplicate route.
    HeadlessRoute(
      HttpMethod.post,
      '/api/system/update/check',
      dispatch((h, request) => h.handleCheckForUpdate(request)),
    ),
    HeadlessRoute(
      HttpMethod.get,
      '/api/system/update/status',
      dispatch((h, request) => h.handleGetStatus(request)),
    ),
    HeadlessRoute(
      HttpMethod.post,
      '/api/system/update/download',
      dispatch((h, request) => h.handleDownload(request)),
    ),
    HeadlessRoute(
      HttpMethod.post,
      '/api/system/update/apply',
      dispatch((h, request) => h.handleApply(request)),
    ),
    HeadlessRoute(
      HttpMethod.post,
      '/api/system/update/abort',
      dispatch((h, request) => h.handleAbort(request)),
    ),
    HeadlessRoute(
      HttpMethod.post,
      '/api/system/update/rollback',
      dispatch((h, request) => h.handleRollback(request)),
    ),
    HeadlessRoute(
      HttpMethod.get,
      '/api/system/update/staged',
      dispatch((h, request) => h.handleGetStaged(request)),
    ),
    HeadlessRoute(
      HttpMethod.delete,
      '/api/system/update/staged',
      dispatch((h, request) => h.handleDiscardStaged(request)),
    ),
  ];
}
