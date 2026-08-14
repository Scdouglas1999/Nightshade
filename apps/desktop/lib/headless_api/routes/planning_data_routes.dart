/// Declarative route table for the planner/scheduler DATA surface.
///
/// Counterpart to `handlers/planning_data_handlers.dart`. These endpoints
/// mirror the host's `integration_goals`, `target_constraints`,
/// `horizon_profiles`, `projects`, and `project_targets` rows to remote
/// slaves, plus the writes a slave operator makes (so they persist on the
/// master, not the slave's throwaway local DB).
library;

import '../handlers/planning_data_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PlanningDataHandlers].
List<HeadlessRoute> buildPlanningDataRoutes(PlanningDataHandlers h) =>
    <HeadlessRoute>[
      // Integration goals
      HeadlessRoute(
        HttpMethod.get,
        '/api/integration-goals',
        h.handleGetIntegrationGoals,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/integration-goals/captured-count',
        h.handleGetCapturedFrameCount,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/integration-goals',
        h.handleUpsertIntegrationGoal,
      ),
      HeadlessRoute(
        HttpMethod.delete,
        '/api/integration-goals',
        h.handleDeleteIntegrationGoal,
      ),
      // Target constraints
      HeadlessRoute(
        HttpMethod.get,
        '/api/target-constraints',
        h.handleGetTargetConstraints,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/target-constraints',
        h.handleInsertTargetConstraint,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/target-constraints/update',
        h.handleUpdateTargetConstraint,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/target-constraints/set-enabled',
        h.handleSetTargetConstraintEnabled,
      ),
      HeadlessRoute(
        HttpMethod.delete,
        '/api/target-constraints',
        h.handleDeleteTargetConstraint,
      ),
      // Scheduler queue membership
      HeadlessRoute(
        HttpMethod.get,
        '/api/scheduler/removed-targets',
        h.handleGetSchedulerRemovedTargets,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/scheduler/removed-targets',
        h.handleRemoveSchedulerTarget,
      ),
      HeadlessRoute(
        HttpMethod.delete,
        '/api/scheduler/removed-targets',
        h.handleReadmitSchedulerTarget,
      ),
      // Horizon profiles
      HeadlessRoute(
        HttpMethod.get,
        '/api/horizon-profiles',
        h.handleGetHorizonProfiles,
      ),
      // Projects
      HeadlessRoute(HttpMethod.get, '/api/projects', h.handleGetProjects),
      HeadlessRoute(
        HttpMethod.get,
        '/api/projects/targets',
        h.handleGetProjectTargets,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/projects/progress',
        h.handleGetProjectProgress,
      ),
    ];
