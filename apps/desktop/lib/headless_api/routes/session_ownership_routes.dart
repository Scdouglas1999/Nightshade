/// Declarative route table for session-ownership endpoints.
///
/// Counterpart to `handlers/session_ownership_handlers.dart`. Tracks
/// which paired token currently owns the imaging session; the
/// `_sessionOwnershipMiddleware` short-circuits non-owner writes with a
/// 409 conflict, so these endpoints are the only way for a client to
/// claim or release the ticket.
library;

import '../handlers/session_ownership_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SessionOwnershipHandlers].
List<HeadlessRoute> buildSessionOwnershipRoutes(
        SessionOwnershipHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/session/owner', h.handleGetOwner),
      HeadlessRoute(HttpMethod.get, '/api/session/status', h.handleGetStatus),
      HeadlessRoute(HttpMethod.post, '/api/session/claim', h.handleClaim),
      HeadlessRoute(
          HttpMethod.post, '/api/session/take-over', h.handleTakeOver),
      HeadlessRoute(HttpMethod.post, '/api/session/release', h.handleRelease),
    ];
