/// Declarative route table for the Night Narrator feed.
///
/// Counterpart to `handlers/narrator_handlers.dart`. Both are read-only GETs
/// and default to `view` scope per `route_metadata.dart`.
library;

import '../handlers/narrator_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [NarratorHandlers].
List<HeadlessRoute> buildNarratorRoutes(NarratorHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/narrator/feed', h.handleFeed),
  HeadlessRoute(HttpMethod.get, '/api/narrator/recent', h.handleRecent),
];
