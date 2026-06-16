import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for the Night Narrator feed.
///
/// The NarratorService runs on the appliance (where captures land) and persists
/// accepted events to the local DB. A remote tablet/desktop cannot watch that
/// DB, so these read-only endpoints expose the appliance's narrator feed over
/// REST. The mobile client fetches a snapshot here and refreshes when backend
/// events arrive (new captures → new narrator events). Both GETs default to
/// `view` scope (read-only monitoring) per route_metadata.
class NarratorHandlers {
  final ProviderContainer container;

  NarratorHandlers(this.container);

  /// GET `/api/narrator/feed?sessionId=` — pinned-first, newest-first feed for
  /// a single session.
  Future<Response> handleFeed(Request request) async {
    final raw = request.url.queryParameters['sessionId'];
    final sessionId = int.tryParse(raw ?? '');
    if (sessionId == null) {
      throw BadRequestError(
        field: 'sessionId',
        expected: 'integer',
        message: 'sessionId query parameter is required',
      );
    }
    final dao = container.read(narratorEventsDaoProvider);
    final rows = await dao.getFeedForSession(sessionId);
    return jsonOk({'events': rows.map(_rowToWireJson).toList()});
  }

  /// GET `/api/narrator/recent?limit=` — sessionless recent feed, scoped
  /// server-side to the most-recent session that has events (matches the local
  /// `watchRecentFeed` behaviour).
  Future<Response> handleRecent(Request request) async {
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50).clamp(
          1,
          200,
        );
    final dao = container.read(narratorEventsDaoProvider);
    final rows = await dao.getRecentFeed(limit: limit);
    return jsonOk({'events': rows.map(_rowToWireJson).toList()});
  }

  /// Serialize a persisted row to the wire shape the client's
  /// `narratorEventFromWireJson` reconstructs. Category/severity travel as their
  /// stored name strings and evidence as its already-encoded JSON string, so
  /// this is a straight field copy.
  Map<String, dynamic> _rowToWireJson(NarratorEventRow row) => {
    'id': row.id,
    'sessionId': row.sessionId,
    'capturedImageId': row.capturedImageId,
    'timestamp': row.timestamp.millisecondsSinceEpoch,
    'eventType': row.eventType,
    'category': row.category,
    'severity': row.severity,
    'headline': row.headline,
    'body': row.body,
    'evidenceJson': row.evidenceJson,
    'dedupeKey': row.dedupeKey,
    'pinned': row.pinned,
  };
}
