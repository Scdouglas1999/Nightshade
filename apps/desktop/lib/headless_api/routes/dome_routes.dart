/// Declarative route table for dome / shutter control.
///
/// Counterpart to `handlers/dome_handlers.dart`. The
/// open/close/slew/park endpoints are flagged as high-risk in
/// `route_metadata.dart` (dome motions can crash into a tube assembly).
library;

import '../handlers/dome_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [DomeHandlers].
List<HeadlessRoute> buildDomeRoutes(DomeHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.post, '/api/dome/open', h.handleDomeOpen),
  HeadlessRoute(HttpMethod.post, '/api/dome/close', h.handleDomeClose),
  HeadlessRoute(HttpMethod.post, '/api/dome/slew', h.handleDomeSlew),
  HeadlessRoute(HttpMethod.post, '/api/dome/sync', h.handleDomeSync),
  HeadlessRoute(HttpMethod.post, '/api/dome/park', h.handleDomePark),
  HeadlessRoute(HttpMethod.post, '/api/dome/home', h.handleDomeHome),
  HeadlessRoute(HttpMethod.post, '/api/dome/halt', h.handleDomeHalt),
  HeadlessRoute(HttpMethod.get, '/api/dome/status', h.handleDomeStatus),
  HeadlessRoute(
    HttpMethod.get,
    '/api/dome/capabilities',
    h.handleDomeCapabilities,
  ),
];
