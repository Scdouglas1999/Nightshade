/// Declarative route table for cloud backup/sync endpoints.
///
/// Counterpart to `handlers/sync_handlers.dart`. Pull/restore is covered
/// by the existing `/api/backup/*` routes (upload-restore); this table
/// only adds the sync-specific status + push-now surface.
library;

import '../handlers/sync_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SyncHandlers].
List<HeadlessRoute> buildSyncRoutes(SyncHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/sync/status', h.handleGetStatus),
  HeadlessRoute(HttpMethod.post, '/api/sync/push', h.handlePushNow),
];
