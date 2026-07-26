/// Declarative route table for the transient-alert surface.
///
/// Counterpart to `handlers/transient_handlers.dart`. Backs the
/// supernovae / nova / GRB notification stream the dashboard renders,
/// plus the queue / dismiss / settings management UI.
library;

import '../handlers/transient_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [TransientHandlers].
List<HeadlessRoute> buildTransientRoutes(
  TransientHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/transients', h.handleGetActiveTransients),
  HeadlessRoute(
    HttpMethod.get,
    '/api/transients/settings',
    h.handleGetSettings,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/transients/settings',
    h.handleUpdateSettings,
  ),
  HeadlessRoute(HttpMethod.get, '/api/transients/queued', h.handleGetQueued),
  HeadlessRoute(HttpMethod.get, '/api/transients/states', h.handleGetStates),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/transients/states',
    h.handleClearStates,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/transients/<id>/queue',
    h.handleQueueTransient,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/transients/<id>/dismiss',
    h.handleDismissTransient,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/transients/<id>/state',
    h.handleUpdateState,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/transients/refresh',
    h.handleRefreshAlerts,
  ),
];
