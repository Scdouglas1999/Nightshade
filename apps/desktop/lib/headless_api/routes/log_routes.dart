/// Declarative route table for the P1-14 remote log surface.
///
/// Counterpart to `handlers/log_handlers.dart`. Mobile operators on
/// headless deployments (Pi / embedded) use these to diagnose without
/// SSH. The SSE tail handler is registered as a regular GET because
/// the handler returns a streaming `Response` whose body is a
/// manually-driven `Stream<List<int>>`; shelf does NOT buffer it.
library;

import '../handlers/log_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [LogHandlers].
List<HeadlessRoute> buildLogRoutes(LogHandlers h) => <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/logs', h.handleListFiles),
      HeadlessRoute(HttpMethod.get, '/api/logs/recent', h.handleRecent),
      HeadlessRoute(HttpMethod.get, '/api/logs/files/<filename>/download',
          h.handleDownloadFile),
      HeadlessRoute(HttpMethod.get, '/api/logs/tail', h.handleTail),
      HeadlessRoute(HttpMethod.post, '/api/logs/clear', h.handleClear),
      HeadlessRoute(
          HttpMethod.post, '/api/logs/test-entry', h.handleTestEntry),
    ];
