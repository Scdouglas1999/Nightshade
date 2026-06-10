/// Live-collaboration HTTP handlers for the headless API.
///
/// Owns the read/write surface under `/api/collaboration/*` and
/// `/api/session-handoff` that the desktop dashboard, mobile companion,
/// and outreach broadcast clients use to keep their UI state in sync:
///   * viewer-join / viewer-leave (presence tracking),
///   * preview snapshots, chat, and arbitrary annotations,
///   * session-handoff payloads that hand control between operators.
///
/// Authoritative viewer identity comes from the auth-identity digest
/// the auth middleware stashed on the request context (see
/// `request_context.dart`). When auth is disabled (no tokens
/// configured), we fall back to the client-supplied viewerId so existing
/// no-auth deployments keep working — that is the explicit "auth
/// disabled" path the operator opted into.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:shelf/shelf.dart';

import '../request_context.dart';
import '../response_helpers.dart';

/// HTTP handlers for the `/api/collaboration/*` and `/api/session-handoff`
/// endpoints. Constructed once per server with the shared
/// [LiveCollaborationSessionManager] so HTTP, the WS upgrade path, and
/// the desktop GUI all observe the same in-memory state.
class CollaborationHandlers {
  final LiveCollaborationSessionManager manager;
  final LoggingService logger;

  CollaborationHandlers({required this.manager, required this.logger});

  void _logWarning(String message, {Map<String, Object?>? fields}) =>
      logger.warning(message, source: 'CollaborationHandlers', fields: fields);

  /// `GET /api/collaboration/state` — snapshot the current presence list,
  /// preview, chat backlog, and active annotations. Read-only.
  Future<Response> handleCollaborationState(Request request) async {
    return jsonOk(manager.state.toJson());
  }

  /// `POST /api/collaboration/viewers/join` — register a new viewer.
  /// The authenticated identity wins over any client-supplied viewerId
  /// (P2-15); a mismatch is logged at WARNING as a potential
  /// impersonation attempt and the authenticated id is substituted.
  Future<Response> handleCollaborationJoin(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final clientViewerId = payload['viewerId'] as String?;
      final name = payload['name'] as String?;
      if (name == null || name.isEmpty) {
        return jsonBadRequest({'error': 'Missing name'});
      }
      // P2-15: the authenticated identity wins over any client-supplied
      // viewerId, mirroring the WebSocket-path semantics. When auth is
      // disabled (no tokens configured), fall back to the payload value
      // so existing clients keep working.
      final authIdentity = authIdentityFrom(request);
      final effectiveViewerId = authIdentity ?? clientViewerId;
      if (effectiveViewerId == null || effectiveViewerId.isEmpty) {
        return jsonBadRequest({
          'error': 'Missing viewerId',
          'message': 'viewerId required when authentication is disabled.',
        });
      }
      if (authIdentity != null &&
          clientViewerId != null &&
          clientViewerId.isNotEmpty &&
          clientViewerId != authIdentity) {
        _logWarning(
          '[COLLAB] HTTP join impersonation attempt '
          '(claimed=$clientViewerId actual=${redactBearer(authIdentity)}); '
          'substituting authenticated identity.',
        );
      }
      manager.upsertViewer(effectiveViewerId, name);
      return jsonOk(manager.state.toJson());
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `POST /api/collaboration/viewers/leave` — release a viewer slot. A
  /// client can only release its own slot; the authenticated identity
  /// overrides any payload value to prevent removing other operators.
  Future<Response> handleCollaborationLeave(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final clientViewerId = payload['viewerId'] as String?;
      // P2-15: a client cannot remove an arbitrary viewer slot — it can
      // only release its own. The authenticated identity overrides the
      // payload value. When auth is disabled (test fixtures), we fall
      // back to the payload value.
      final authIdentity = authIdentityFrom(request);
      final viewerId = authIdentity ?? clientViewerId;
      if (viewerId == null || viewerId.isEmpty) {
        return jsonBadRequest({'error': 'Missing viewerId'});
      }
      manager.removeViewer(viewerId);
      return jsonOk(manager.state.toJson());
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `POST /api/collaboration/preview` — update the shared preview
  /// thumbnail/snapshot. Pass `{"preview": null}` to clear.
  Future<Response> handleCollaborationPreview(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final preview = payload['preview'];
      if (preview != null && preview is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'preview must be an object'});
      }
      manager.updatePreview(preview as Map<String, dynamic>?);
      return jsonOk(manager.state.toJson());
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `POST /api/collaboration/chat` — append a chat line. The viewerId
  /// of the chat row is forced to the authenticated identity (P2-15) so
  /// a client cannot put words in another operator's mouth.
  Future<Response> handleCollaborationChat(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final viewerId = payload['viewerId'] as String?;
      final viewerName = payload['viewerName'] as String?;
      final message = payload['message'] as String?;
      if (viewerId == null || viewerName == null || message == null) {
        return jsonBadRequest({
          'error': 'viewerId, viewerName, and message are required',
        });
      }
      manager.addChat(
        viewerId: viewerId,
        viewerName: viewerName,
        message: message,
      );
      return jsonOk(manager.state.toJson());
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `POST /api/collaboration/annotations` — append an annotation
  /// (highlight, label, ROI box) to the shared overlay. The
  /// `payload` field is an opaque map echoed verbatim to subscribers.
  Future<Response> handleCollaborationAnnotation(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final annotationId = payload['annotationId'] as String?;
      final viewerId = payload['viewerId'] as String?;
      final kind = payload['kind'] as String?;
      final annotationPayload = payload['payload'];
      if (annotationId == null ||
          viewerId == null ||
          kind == null ||
          annotationPayload is! Map<String, dynamic>) {
        return jsonBadRequest({
          'error': 'annotationId, viewerId, kind, and payload are required',
        });
      }
      manager.addAnnotation(
        annotationId: annotationId,
        viewerId: viewerId,
        kind: kind,
        payload: annotationPayload,
      );
      return jsonOk(manager.state.toJson());
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `GET /api/session-handoff` — snapshot the currently-active handoff
  /// payload (null when no operator has set one).
  Future<Response> handleGetSessionHandoff(Request request) async {
    return jsonOk({'sessionHandoff': manager.state.sessionHandoff});
  }

  /// `POST /api/session-handoff` — set the handoff payload. The body
  /// shape is `{"handoff": {...}}`; an object value replaces the
  /// existing handoff, null clears it.
  Future<Response> handleSetSessionHandoff(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final handoff = payload['handoff'];
      if (handoff != null && handoff is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'handoff must be an object'});
      }
      manager.setSessionHandoff(handoff as Map<String, dynamic>?);
      return jsonOk({'sessionHandoff': manager.state.sessionHandoff});
    } catch (e, st) {
      // Fail-closed: surface a stable 500 with a sanitized message; the real
      // cause/stack is logged server-side, never serialized to the caller.
      developer.log(
        '[API] collaboration handler failed',
        name: 'collaboration_handlers',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return jsonInternalServerError(const {
        'error': 'collaboration_request_failed',
        'message': 'The collaboration request could not be completed.',
      });
    }
  }

  /// `DELETE /api/session-handoff` — clear any active handoff payload.
  Future<Response> handleClearSessionHandoff(Request request) async {
    manager.setSessionHandoff(null);
    return jsonOk({'sessionHandoff': null});
  }
}
