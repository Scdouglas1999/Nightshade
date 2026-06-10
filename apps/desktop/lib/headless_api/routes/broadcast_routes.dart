/// Declarative route table for the Wave 7 live-stacking broadcast
/// surface.
///
/// Counterpart to `handlers/broadcast_handlers.dart`. The
/// `/broadcast` HTML page is intentionally served from the same server
/// so a single LAN URL covers the whole audience; the `/api/broadcast/*`
/// endpoints back the SPA running there.
library;

import '../handlers/broadcast_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [BroadcastHandlers].
List<HeadlessRoute> buildBroadcastRoutes(
  BroadcastHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/broadcast/info', h.handleInfo),
  HeadlessRoute(HttpMethod.get, '/api/broadcast/live-stack', h.handleLiveStack),
  HeadlessRoute(HttpMethod.get, '/api/broadcast/sse', h.handleSse),
  HeadlessRoute(HttpMethod.get, '/broadcast', h.handleBroadcastPage),
];
