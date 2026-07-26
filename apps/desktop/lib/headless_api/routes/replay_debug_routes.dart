/// Declarative route table for the Replay Debug surface.
///
/// Counterpart to `handlers/replay_debug_handlers.dart`. Lives under
/// `/api/sequencer/replay-debug/*` so it inherits the `sequencer` auth
/// resource (GET → view, POST → control) without any route_metadata change.
library;

import '../handlers/replay_debug_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [ReplayDebugHandlers].
List<HeadlessRoute> buildReplayDebugRoutes(
  ReplayDebugHandlers h,
) => <HeadlessRoute>[
  // Register the more specific `/decisions/count` before `/decisions` so the
  // literal child can never be shadowed.
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequencer/replay-debug/decisions/count',
    h.handleCountDecisions,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequencer/replay-debug/decisions',
    h.handleListDecisions,
  ),
  // Settings sub-routes before the settings GET for the same reason.
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequencer/replay-debug/settings/enabled',
    h.handleSetEnabled,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequencer/replay-debug/settings/retention',
    h.handleSetRetention,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequencer/replay-debug/settings',
    h.handleGetSettings,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequencer/replay-debug/clear',
    h.handleClear,
  ),
];
