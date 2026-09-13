/// Declarative route table for the DepthLock goal store.
///
/// Counterpart to `handlers/depthlock_handlers.dart`. Ordering is the usual
/// shelf_router rule — the literal `reference/` and `measurement/` paths and
/// the `goals/<goalId>/…` sub-resources are declared before the bare
/// `goals/<goalId>` routes so a parametric path never shadows a literal one.
library;

import '../handlers/depthlock_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [DepthLockHandlers].
List<HeadlessRoute> buildDepthLockRoutes(DepthLockHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/depthlock/status', h.handleGetStatus),
      HeadlessRoute(HttpMethod.get, '/api/depthlock/goals', h.handleListGoals),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/goals',
        h.handleCreateGoal,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/reference/inspect',
        h.handleInspectReference,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/reference/sky-rectangle',
        h.handleSkyRectangle,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/measurement/check',
        h.handleCheckMeasurement,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/measurement/suggest-floor',
        h.handleSuggestFloor,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/goals/<goalId>/preferences',
        h.handleSetPreferences,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/goals/<goalId>/ingest',
        h.handleIngestFrame,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/depthlock/goals/<goalId>/replay',
        h.handleReplayGoal,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/depthlock/goals/<goalId>/curve',
        h.handleGoalCurve,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/depthlock/goals/<goalId>',
        h.handleGetGoal,
      ),
      HeadlessRoute(
        HttpMethod.put,
        '/api/depthlock/goals/<goalId>',
        h.handleReviseGoal,
      ),
      HeadlessRoute(
        HttpMethod.delete,
        '/api/depthlock/goals/<goalId>',
        h.handleRemoveGoal,
      ),
    ];
