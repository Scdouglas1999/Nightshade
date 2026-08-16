/// Declarative route table for Collaborative Sky live co-imaging endpoints.
/// Lets an unattended rig discover/open/join a live co-imaging session,
/// report to the COMBINED accounting, and drive the longitude hand-off baton.
///
/// Counterpart to `handlers/coimaging_handlers.dart`.
library;

import '../handlers/coimaging_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [CoImagingHandlers].
List<HeadlessRoute> buildCoImagingRoutes(CoImagingHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(
        HttpMethod.get,
        '/api/coimaging/sessions',
        h.handleListSessions,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions',
        h.handleCreateSession,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/coimaging/sessions/<sessionId>',
        h.handleGetSession,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/join',
        h.handleJoinSession,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/leave',
        h.handleLeaveSession,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/close',
        h.handleCloseSession,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/contribute',
        h.handleContribute,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/coimaging/sessions/<sessionId>/framing-offset',
        h.handleFramingOffset,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/sub-complete',
        h.handleSubComplete,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/baton/auto',
        h.handleAutoBaton,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/baton/claim',
        h.handleClaimBaton,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/coimaging/sessions/<sessionId>/baton/release',
        h.handleReleaseBaton,
      ),
    ];
