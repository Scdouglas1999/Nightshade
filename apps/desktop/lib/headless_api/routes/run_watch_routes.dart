/// Declarative route table for the Wave 6 run-watch surface.
///
/// Counterpart to `handlers/run_watch_handlers.dart`. The SSE endpoint
/// is a long-lived GET — registering it as a regular [HttpMethod.get]
/// is intentional; shelf does NOT buffer the response because
/// [RunWatchHandlers.handleEventStream] returns a streaming
/// `Response` whose body is a manually-driven `Stream<List<int>>`.
library;

import '../handlers/run_watch_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [RunWatchHandlers].
List<HeadlessRoute> buildRunWatchRoutes(RunWatchHandlers h) => <HeadlessRoute>[
      HeadlessRoute(
          HttpMethod.get, '/api/run-watch/snapshot', h.handleSnapshot),
      HeadlessRoute(HttpMethod.get, '/api/run-watch/frame-thumbnail',
          h.handleFrameThumbnail),
      HeadlessRoute(
          HttpMethod.get, '/api/run-watch/events', h.handleEventStream),
    ];
