import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart'
    show Target, TargetsCompanion;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for target CRUD operations
class TargetHandlers {
  final ProviderContainer container;

  TargetHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'TargetHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'TargetHandlers');

  // ===========================================================================
  // Get All Targets
  // ===========================================================================

  Future<Response> handleGetAllTargets(Request request) async {
    _logInfo('[API] GET /api/targets');
    try {
      final database = container.read(databaseProvider);
      final targets = await database.targetsDao.getAllTargets();

      return jsonOk({
        "targets": targets.map((t) => _targetToJson(t)).toList(),
      });
    } catch (e) {
      _logError('[API] Get all targets error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Target By ID
  // ===========================================================================

  Future<Response> handleGetTargetById(Request request, String id) async {
    _logInfo('[API] GET /api/targets/$id');
    try {
      final targetId = int.parse(id);
      final database = container.read(databaseProvider);
      final target = await database.targetsDao.getTargetById(targetId);

      if (target == null) {
        return jsonNotFound({"error": "Target not found: $id"});
      }

      return jsonOk({"target": _targetToJson(target)});
    } catch (e) {
      _logError('[API] Get target by ID error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Search Targets
  // ===========================================================================

  Future<Response> handleSearchTargets(Request request) async {
    final query = request.url.queryParameters['query'] ?? '';
    _logInfo('[API] GET /api/targets/search?query=$query');
    try {
      final database = container.read(databaseProvider);
      final targets = await database.targetsDao.searchTargets(query);

      return jsonOk({
        "targets": targets.map((t) => _targetToJson(t)).toList(),
      });
    } catch (e) {
      _logError('[API] Search targets error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Favorite Targets
  // ===========================================================================

  Future<Response> handleGetFavoriteTargets(Request request) async {
    _logInfo('[API] GET /api/targets/favorites');
    try {
      final database = container.read(databaseProvider);
      final targets = await database.targetsDao.getFavoriteTargets();

      return jsonOk({
        "targets": targets.map((t) => _targetToJson(t)).toList(),
      });
    } catch (e) {
      _logError('[API] Get favorite targets error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Create Target
  // ===========================================================================

  Future<Response> handleCreateTarget(Request request) async {
    _logInfo('[API] POST /api/targets');
    try {
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      final companion = TargetsCompanion(
        name: Value(payload['name'] as String),
        catalogId: Value(payload['catalogId'] as String?),
        ra: Value((payload['ra'] as num).toDouble()),
        dec: Value((payload['dec'] as num).toDouble()),
        objectType: Value(payload['objectType'] as String?),
        constellation: Value(payload['constellation'] as String?),
        magnitude: Value((payload['magnitude'] as num?)?.toDouble()),
        sizeArcmin: Value((payload['sizeArcmin'] as num?)?.toDouble()),
        positionAngle: Value((payload['positionAngle'] as num?)?.toDouble()),
        minAltitude:
            Value((payload['minAltitude'] as num?)?.toDouble() ?? 30.0),
        notes: Value(payload['notes'] as String?),
        isFavorite: Value(payload['isFavorite'] as bool? ?? false),
        priority: Value(payload['priority'] as int? ?? 0),
        totalPlannedSubs: Value(payload['totalPlannedSubs'] as int? ?? 0),
        capturedSubs: Value(payload['capturedSubs'] as int? ?? 0),
        totalIntegrationSecs:
            Value((payload['totalIntegrationSecs'] as num?)?.toDouble() ?? 0.0),
        goalIntegrationSecs:
            Value((payload['goalIntegrationSecs'] as num?)?.toDouble() ?? 0.0),
        filterProgress: Value(payload['filterProgress'] as String?),
      );

      final id = await database.targetsDao.createTarget(companion);

      return jsonOk({"status": "created", "id": id});
    } catch (e) {
      _logError('[API] Create target error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Target
  // ===========================================================================

  Future<Response> handleUpdateTarget(Request request, String id) async {
    _logInfo('[API] PUT /api/targets/$id');
    try {
      final targetId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      // Get existing target
      final existing = await database.targetsDao.getTargetById(targetId);
      if (existing == null) {
        return jsonNotFound({"error": "Target not found: $id"});
      }

      // Build updated target
      final updated = existing.copyWith(
        name: payload['name'] as String? ?? existing.name,
        catalogId: Value(payload['catalogId'] as String? ?? existing.catalogId),
        ra: (payload['ra'] as num?)?.toDouble() ?? existing.ra,
        dec: (payload['dec'] as num?)?.toDouble() ?? existing.dec,
        objectType:
            Value(payload['objectType'] as String? ?? existing.objectType),
        constellation: Value(
            payload['constellation'] as String? ?? existing.constellation),
        magnitude: Value(
            (payload['magnitude'] as num?)?.toDouble() ?? existing.magnitude),
        sizeArcmin: Value(
            (payload['sizeArcmin'] as num?)?.toDouble() ?? existing.sizeArcmin),
        positionAngle: Value((payload['positionAngle'] as num?)?.toDouble() ??
            existing.positionAngle),
        minAltitude: (payload['minAltitude'] as num?)?.toDouble() ??
            existing.minAltitude,
        notes: Value(payload['notes'] as String? ?? existing.notes),
        isFavorite: payload['isFavorite'] as bool? ?? existing.isFavorite,
        priority: payload['priority'] as int? ?? existing.priority,
        totalPlannedSubs:
            payload['totalPlannedSubs'] as int? ?? existing.totalPlannedSubs,
        capturedSubs: payload['capturedSubs'] as int? ?? existing.capturedSubs,
        totalIntegrationSecs:
            (payload['totalIntegrationSecs'] as num?)?.toDouble() ??
                existing.totalIntegrationSecs,
        goalIntegrationSecs:
            (payload['goalIntegrationSecs'] as num?)?.toDouble() ??
                existing.goalIntegrationSecs,
        filterProgress: Value(
            payload['filterProgress'] as String? ?? existing.filterProgress),
        updatedAt: DateTime.now(),
      );

      await database.targetsDao.updateTarget(updated);

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update target error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Delete Target
  // ===========================================================================

  Future<Response> handleDeleteTarget(Request request, String id) async {
    _logInfo('[API] DELETE /api/targets/$id');
    try {
      final targetId = int.parse(id);
      final database = container.read(databaseProvider);

      final deleted = await database.targetsDao.deleteTarget(targetId);
      if (deleted == 0) {
        return jsonNotFound({"error": "Target not found: $id"});
      }

      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete target error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Toggle Favorite
  // ===========================================================================

  Future<Response> handleToggleFavorite(Request request, String id) async {
    _logInfo('[API] POST /api/targets/$id/favorite');
    try {
      final targetId = int.parse(id);
      final database = container.read(databaseProvider);

      await database.targetsDao.toggleFavorite(targetId);

      return jsonOk({"status": "toggled"});
    } catch (e) {
      _logError('[API] Toggle favorite error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Progress
  // ===========================================================================

  Future<Response> handleUpdateProgress(Request request, String id) async {
    _logInfo('[API] PUT /api/targets/$id/progress');
    try {
      final targetId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      await database.targetsDao.updateProgress(
        targetId,
        capturedSubs: payload['capturedSubs'] as int?,
        totalIntegrationSecs:
            (payload['totalIntegrationSecs'] as num?)?.toDouble(),
        filterProgress: payload['filterProgress'] as String?,
      );

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update progress error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Targets By Type
  // ===========================================================================

  Future<Response> handleGetTargetsByType(Request request) async {
    final objectType = request.url.queryParameters['type'] ?? '';
    _logInfo('[API] GET /api/targets/by-type?type=$objectType');
    try {
      final database = container.read(databaseProvider);
      final targets = await database.targetsDao.getTargetsByType(objectType);

      return jsonOk({
        "targets": targets.map((t) => _targetToJson(t)).toList(),
      });
    } catch (e) {
      _logError('[API] Get targets by type error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Targets By Priority
  // ===========================================================================

  Future<Response> handleGetTargetsByPriority(Request request) async {
    _logInfo('[API] GET /api/targets/by-priority');
    try {
      final database = container.read(databaseProvider);
      final targets = await database.targetsDao.getTargetsByPriority();

      return jsonOk({
        "targets": targets.map((t) => _targetToJson(t)).toList(),
      });
    } catch (e) {
      _logError('[API] Get targets by priority error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Helper: Convert Target to JSON
  // ===========================================================================

  Map<String, dynamic> _targetToJson(Target target) {
    return {
      'id': target.id,
      'name': target.name,
      'catalogId': target.catalogId,
      'ra': target.ra,
      'dec': target.dec,
      'objectType': target.objectType,
      'constellation': target.constellation,
      'magnitude': target.magnitude,
      'sizeArcmin': target.sizeArcmin,
      'positionAngle': target.positionAngle,
      'minAltitude': target.minAltitude,
      'notes': target.notes,
      'isFavorite': target.isFavorite,
      'priority': target.priority,
      'totalPlannedSubs': target.totalPlannedSubs,
      'capturedSubs': target.capturedSubs,
      'totalIntegrationSecs': target.totalIntegrationSecs,
      'goalIntegrationSecs': target.goalIntegrationSecs,
      'filterProgress': target.filterProgress,
      'createdAt': target.createdAt.millisecondsSinceEpoch,
      'updatedAt': target.updatedAt.millisecondsSinceEpoch,
    };
  }
}
