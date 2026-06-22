import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Host endpoints serving the planner/scheduler DATA tables to remote slaves.
///
/// On a slave (remote client) the `integration_goals`, `target_constraints`,
/// `horizon_profiles`, `projects`, and `project_targets` tables live ONLY on
/// the host — the slave's local SQLite is empty. Without these endpoints the
/// slave's candidate loader gates with zero constraints/horizons, its goal &
/// constraint editors render blank (and write to a throwaway DB), and the
/// Planner's Projects tab is empty. These handlers read the same host-side
/// services the desktop app uses (so the host path is unchanged) and serialize
/// the rows over REST.
class PlanningDataHandlers {
  final ProviderContainer container;

  PlanningDataHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'PlanningDataHandlers');

  IntegrationGoalService get _goalService =>
      container.read(integrationGoalServiceProvider);

  TargetConstraintService get _constraintService =>
      container.read(targetConstraintServiceProvider);

  ProjectService get _projectService => container.read(projectServiceProvider);

  int? _intParam(Request request, String key) {
    final raw = request.url.queryParameters[key];
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  // ===========================================================================
  // Integration goals
  // ===========================================================================

  /// GET /api/integration-goals?targetId=
  Future<Response> handleGetIntegrationGoals(Request request) async {
    _logInfo('[API] GET /api/integration-goals');
    try {
      final targetId = _intParam(request, 'targetId');
      final goals = targetId != null
          ? await _goalService.listForTarget(targetId)
          : await _goalService.listAll();
      return jsonOk({'goals': goals.map((g) => g.toJson()).toList()});
    } catch (e) {
      return jsonInternalServerError({'error': 'Failed to list goals: $e'});
    }
  }

  /// GET /api/integration-goals/captured-count?targetId=&filter=
  Future<Response> handleGetCapturedFrameCount(Request request) async {
    _logInfo('[API] GET /api/integration-goals/captured-count');
    final targetId = _intParam(request, 'targetId');
    final filter = request.url.queryParameters['filter'];
    if (targetId == null || filter == null) {
      return jsonBadRequest({'error': 'Missing targetId or filter'});
    }
    try {
      final count = await _goalService.capturedFrameCount(
        targetId: targetId,
        filter: filter,
      );
      return jsonOk({'count': count});
    } catch (e) {
      return jsonInternalServerError({'error': 'Failed to count frames: $e'});
    }
  }

  /// POST /api/integration-goals — upsert.
  Future<Response> handleUpsertIntegrationGoal(Request request) async {
    _logInfo('[API] POST /api/integration-goals');
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final goal = IntegrationGoal.fromJson(body);
      final id = await _goalService.upsert(goal);
      return jsonOk({'id': id});
    } catch (e) {
      return jsonInternalServerError({'error': 'Failed to upsert goal: $e'});
    }
  }

  /// DELETE /api/integration-goals?id=|targetId=|all=true
  Future<Response> handleDeleteIntegrationGoal(Request request) async {
    _logInfo('[API] DELETE /api/integration-goals');
    try {
      if (request.url.queryParameters['all'] == 'true') {
        await _goalService.deleteAll();
        return jsonOk({'success': true});
      }
      final targetId = _intParam(request, 'targetId');
      if (targetId != null) {
        await _goalService.deleteForTarget(targetId);
        return jsonOk({'success': true});
      }
      final id = _intParam(request, 'id');
      if (id == null) {
        return jsonBadRequest({'error': 'Missing id, targetId, or all'});
      }
      await _goalService.delete(id);
      return jsonOk({'success': true});
    } catch (e) {
      return jsonInternalServerError({'error': 'Failed to delete goal: $e'});
    }
  }

  // ===========================================================================
  // Target constraints
  // ===========================================================================

  /// GET /api/target-constraints?targetId=
  Future<Response> handleGetTargetConstraints(Request request) async {
    _logInfo('[API] GET /api/target-constraints');
    try {
      final targetId = _intParam(request, 'targetId');
      final constraints = targetId != null
          ? await _constraintService.listForTarget(targetId)
          : await _constraintService.listAll();
      return jsonOk({
        'constraints': constraints.map((c) => c.toJson()).toList(),
      });
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to list constraints: $e',
      });
    }
  }

  /// POST /api/target-constraints — insert.
  Future<Response> handleInsertTargetConstraint(Request request) async {
    _logInfo('[API] POST /api/target-constraints');
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final constraint = TargetConstraint.fromJson(body);
      final id = await _constraintService.insert(constraint);
      return jsonOk({'id': id});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to insert constraint: $e',
      });
    }
  }

  /// POST /api/target-constraints/update — update in place.
  Future<Response> handleUpdateTargetConstraint(Request request) async {
    _logInfo('[API] POST /api/target-constraints/update');
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final constraint = TargetConstraint.fromJson(body);
      await _constraintService.update(constraint);
      return jsonOk({'success': true});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to update constraint: $e',
      });
    }
  }

  /// POST /api/target-constraints/set-enabled — toggle.
  Future<Response> handleSetTargetConstraintEnabled(Request request) async {
    _logInfo('[API] POST /api/target-constraints/set-enabled');
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = (body['id'] as num?)?.toInt();
      final enabled = body['enabled'] as bool?;
      if (id == null || enabled == null) {
        return jsonBadRequest({'error': 'Missing id or enabled'});
      }
      await _constraintService.setEnabled(id, enabled);
      return jsonOk({'success': true});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to set constraint enabled: $e',
      });
    }
  }

  /// DELETE /api/target-constraints?id=|targetId=|all=true
  Future<Response> handleDeleteTargetConstraint(Request request) async {
    _logInfo('[API] DELETE /api/target-constraints');
    try {
      if (request.url.queryParameters['all'] == 'true') {
        await _constraintService.deleteAll();
        return jsonOk({'success': true});
      }
      final targetId = _intParam(request, 'targetId');
      if (targetId != null) {
        await _constraintService.deleteForTarget(targetId);
        return jsonOk({'success': true});
      }
      final id = _intParam(request, 'id');
      if (id == null) {
        return jsonBadRequest({'error': 'Missing id, targetId, or all'});
      }
      await _constraintService.delete(id);
      return jsonOk({'success': true});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to delete constraint: $e',
      });
    }
  }

  // ===========================================================================
  // Horizon profiles
  // ===========================================================================

  /// GET /api/horizon-profiles
  Future<Response> handleGetHorizonProfiles(Request request) async {
    _logInfo('[API] GET /api/horizon-profiles');
    try {
      final db = container.read(databaseProvider);
      // Ensure the table exists before reading (mirrors the loader's defensive
      // DDL — a host that has never opened the scheduler UI may not have it).
      // DDL inlined because the canonical constant is hidden from the barrel;
      // it is `CREATE TABLE IF NOT EXISTS`, so this is a no-op on an existing
      // schema and stays identical to ProjectService/IntegrationGoalService.
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS horizon_profiles ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'name TEXT NOT NULL, '
        'samples_json TEXT NOT NULL)',
      );
      final rows = await db
          .customSelect('SELECT id, name, samples_json FROM horizon_profiles')
          .get();
      final profiles = rows
          .map(
            (row) => HorizonProfile.fromRow(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              samplesJson: row.read<String>('samples_json'),
            ),
          )
          .toList();
      return jsonOk({'profiles': profiles.map((p) => p.toJson()).toList()});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to list horizon profiles: $e',
      });
    }
  }

  // ===========================================================================
  // Projects
  // ===========================================================================

  /// GET /api/projects
  Future<Response> handleGetProjects(Request request) async {
    _logInfo('[API] GET /api/projects');
    try {
      final projects = await _projectService.listProjects();
      return jsonOk({'projects': projects.map((p) => p.toJson()).toList()});
    } catch (e) {
      return jsonInternalServerError({'error': 'Failed to list projects: $e'});
    }
  }

  /// GET /api/projects/targets?projectId=
  Future<Response> handleGetProjectTargets(Request request) async {
    _logInfo('[API] GET /api/projects/targets');
    final projectId = _intParam(request, 'projectId');
    if (projectId == null) {
      return jsonBadRequest({'error': 'Missing projectId'});
    }
    try {
      final targets = await _projectService.listTargets(projectId);
      return jsonOk({'targets': targets.map((t) => t.toJson()).toList()});
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to list project targets: $e',
      });
    }
  }

  /// GET /api/projects/progress?projectId=
  Future<Response> handleGetProjectProgress(Request request) async {
    _logInfo('[API] GET /api/projects/progress');
    final projectId = _intParam(request, 'projectId');
    if (projectId == null) {
      return jsonBadRequest({'error': 'Missing projectId'});
    }
    try {
      final progress = await _projectService.buildProgress(projectId);
      return jsonOk(progress.toJson());
    } catch (e) {
      return jsonInternalServerError({
        'error': 'Failed to build project progress: $e',
      });
    }
  }
}
