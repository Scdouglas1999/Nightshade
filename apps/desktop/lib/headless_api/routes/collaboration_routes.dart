/// Declarative route table for the collaboration / session-handoff
/// surface.
///
/// Counterpart to `handlers/collaboration_handlers.dart`. Tracks the
/// state of joined viewers, broadcast previews, in-session chat, and the
/// session-handoff handshake used when ownership transfers between
/// a desktop and the mobile companion.
library;

import '../handlers/collaboration_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [CollaborationHandlers].
List<HeadlessRoute> buildCollaborationRoutes(CollaborationHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(
        HttpMethod.get,
        '/api/collaboration/state',
        h.handleCollaborationState,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/collaboration/viewers/join',
        h.handleCollaborationJoin,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/collaboration/viewers/leave',
        h.handleCollaborationLeave,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/collaboration/preview',
        h.handleCollaborationPreview,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/collaboration/chat',
        h.handleCollaborationChat,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/collaboration/annotations',
        h.handleCollaborationAnnotation,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/session-handoff',
        h.handleGetSessionHandoff,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/session-handoff',
        h.handleSetSessionHandoff,
      ),
      HeadlessRoute(
        HttpMethod.delete,
        '/api/session-handoff',
        h.handleClearSessionHandoff,
      ),
    ];
