/// Declarative route table for Pillar B ("First Light") — the difference-imaging
/// transient discovery surface.
///
/// Counterpart to `handlers/first_light_handlers.dart`. The GET is read-only
/// (defaults to `view` scope); the review / dismiss POSTs are triage mutations
/// and fall through to `control` scope per `route_metadata.dart`.
library;

import '../handlers/first_light_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [FirstLightHandlers].
List<HeadlessRoute> buildFirstLightRoutes(
  FirstLightHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.get,
    '/api/firstlight/candidates',
    h.handleGetCandidates,
  ),
  // Cross-night history of one transient (light-curve detail view). Single
  // static segment so it never shadows the `<id>/<action>` triage routes.
  HeadlessRoute(HttpMethod.get, '/api/firstlight/near', h.handleGetNear),
  HeadlessRoute(HttpMethod.post, '/api/firstlight/<id>/review', h.handleReview),
  HeadlessRoute(
    HttpMethod.post,
    '/api/firstlight/<id>/dismiss',
    h.handleDismiss,
  ),
  // Submission: a host action (credentials + outbound HTTP live on the rig
  // host). TNS is a real bot-API upload; AAVSO/MPC return downloadable
  // ingestible reports the slave saves / share-sheets.
  HeadlessRoute(
    HttpMethod.post,
    '/api/firstlight/<id>/submit/tns',
    h.handleSubmitTns,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/firstlight/<id>/export/aavso',
    h.handleExportAavso,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/firstlight/<id>/export/mpc',
    h.handleExportMpc,
  ),
];
