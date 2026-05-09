import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for session management and analytics
class AnalyticsHandlers {
  final ProviderContainer container;

  AnalyticsHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'AnalyticsHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'AnalyticsHandlers');

  // ===========================================================================
  // Get All Sessions
  // ===========================================================================

  Future<Response> handleGetAllSessions(Request request) async {
    _logInfo('[API] GET /api/sessions');
    try {
      final database = container.read(databaseProvider);
      final sessions = await database.sessionsDao.getAllSessions();

      return jsonOk({
        "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
      });
    } catch (e) {
      _logError('[API] Get all sessions error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Session By ID
  // ===========================================================================

  Future<Response> handleGetSessionById(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id');
    try {
      final sessionId = int.parse(id);
      final database = container.read(databaseProvider);
      final session = await database.sessionsDao.getSessionById(sessionId);

      if (session == null) {
        return jsonNotFound({"error": "Session not found: $id"});
      }

      return jsonOk({"session": _sessionToJson(session)});
    } catch (e) {
      _logError('[API] Get session by ID error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Active Session
  // ===========================================================================

  Future<Response> handleGetActiveSession(Request request) async {
    _logInfo('[API] GET /api/sessions/active');
    try {
      final database = container.read(databaseProvider);
      final activeSessions = await database.sessionsDao.getActiveSessions();

      if (activeSessions.isEmpty) {
        return jsonOk({"session": null});
      }

      // Return the most recent active session
      return jsonOk({"session": _sessionToJson(activeSessions.first)});
    } catch (e) {
      _logError('[API] Get active session error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Recent Sessions
  // ===========================================================================

  Future<Response> handleGetRecentSessions(Request request) async {
    final limitStr = request.url.queryParameters['limit'] ?? '10';
    final limit = int.tryParse(limitStr) ?? 10;
    _logInfo('[API] GET /api/sessions/recent?limit=$limit');
    try {
      final database = container.read(databaseProvider);
      final sessions =
          await database.sessionsDao.getRecentSessions(limit: limit);

      return jsonOk({
        "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
      });
    } catch (e) {
      _logError('[API] Get recent sessions error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Create Session
  // ===========================================================================

  Future<Response> handleCreateSession(Request request) async {
    _logInfo('[API] POST /api/sessions');
    try {
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      final id = await database.sessionsDao.startSession(
        name: payload['name'] as String?,
        profileId: payload['profileId'] as int?,
        targetId: payload['targetId'] as int?,
        sequenceId: payload['sequenceId'] as int?,
      );

      return jsonOk({"status": "created", "id": id});
    } catch (e) {
      _logError('[API] Create session error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Session
  // ===========================================================================

  Future<Response> handleUpdateSession(Request request, String id) async {
    _logInfo('[API] PUT /api/sessions/$id');
    try {
      final sessionId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      // Update stats if provided
      if (payload.containsKey('totalExposures') ||
          payload.containsKey('successfulExposures') ||
          payload.containsKey('failedExposures') ||
          payload.containsKey('totalIntegrationSecs') ||
          payload.containsKey('avgHfr') ||
          payload.containsKey('avgGuidingRms') ||
          payload.containsKey('autofocusCount')) {
        await database.sessionsDao.updateSessionStats(
          sessionId,
          totalExposures: payload['totalExposures'] as int?,
          successfulExposures: payload['successfulExposures'] as int?,
          failedExposures: payload['failedExposures'] as int?,
          totalIntegrationSecs:
              (payload['totalIntegrationSecs'] as num?)?.toDouble(),
          avgHfr: (payload['avgHfr'] as num?)?.toDouble(),
          avgGuidingRms: (payload['avgGuidingRms'] as num?)?.toDouble(),
          autofocusCount: payload['autofocusCount'] as int?,
        );
      }

      // Update notes if provided
      if (payload.containsKey('notes')) {
        await database.sessionsDao
            .updateNotes(sessionId, payload['notes'] as String);
      }

      // Update status if provided
      if (payload.containsKey('status')) {
        await database.sessionsDao
            .updateSessionStatus(sessionId, payload['status'] as String);
      }

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update session error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // End Session
  // ===========================================================================

  Future<Response> handleEndSession(Request request, String id) async {
    _logInfo('[API] POST /api/sessions/$id/end');
    try {
      final sessionId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final status = payload['status'] as String? ?? 'completed';
      final database = container.read(databaseProvider);

      await database.sessionsDao.endSession(sessionId, status: status);

      return jsonOk({"status": "ended"});
    } catch (e) {
      _logError('[API] End session error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Delete Session
  // ===========================================================================

  Future<Response> handleDeleteSession(Request request, String id) async {
    _logInfo('[API] DELETE /api/sessions/$id');
    try {
      final sessionId = int.parse(id);
      final database = container.read(databaseProvider);

      final deleted = await database.sessionsDao.deleteSession(sessionId);
      if (deleted == 0) {
        return jsonNotFound({"error": "Session not found: $id"});
      }

      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete session error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Session Stats
  // ===========================================================================

  Future<Response> handleGetSessionStats(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/stats');
    try {
      final sessionId = int.parse(id);
      final database = container.read(databaseProvider);
      final session = await database.sessionsDao.getSessionById(sessionId);

      if (session == null) {
        return jsonNotFound({"error": "Session not found: $id"});
      }

      // Get images for this session
      final images = await database.imagesDao.getImagesForSession(sessionId);

      // Calculate stats
      int lightCount = 0;
      int darkCount = 0;
      int flatCount = 0;
      int biasCount = 0;
      double totalHfr = 0;
      int hfrCount = 0;
      final filterCounts = <String, int>{};

      for (final img in images) {
        switch (img.frameType) {
          case 'light':
            lightCount++;
            break;
          case 'dark':
            darkCount++;
            break;
          case 'flat':
            flatCount++;
            break;
          case 'bias':
            biasCount++;
            break;
        }

        if (img.hfr != null) {
          totalHfr += img.hfr!;
          hfrCount++;
        }

        if (img.filter != null) {
          filterCounts[img.filter!] = (filterCounts[img.filter!] ?? 0) + 1;
        }
      }

      return jsonOk({
        "stats": {
          "totalExposures": session.totalExposures,
          "successfulExposures": session.successfulExposures,
          "failedExposures": session.failedExposures,
          "totalIntegrationSecs": session.totalIntegrationSecs,
          "avgHfr": hfrCount > 0 ? totalHfr / hfrCount : null,
          "avgGuidingRms": session.avgGuidingRms,
          "autofocusCount": session.autofocusCount,
          "frameBreakdown": {
            "light": lightCount,
            "dark": darkCount,
            "flat": flatCount,
            "bias": biasCount,
          },
          "filterBreakdown": filterCounts,
          "durationSecs": session.endTime != null
              ? session.endTime!.difference(session.startTime).inSeconds
              : DateTime.now().difference(session.startTime).inSeconds,
        },
      });
    } catch (e) {
      _logError('[API] Get session stats error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Session Science Data
  // ===========================================================================

  Future<Response> handleGetSessionPsfTiles(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/psf-tiles');
    try {
      final sessionId = int.parse(id);
      final database = container.read(databaseProvider);
      final psfTiles =
          await database.scienceDao.getPsfTilesForSession(sessionId);

      return jsonOk({
        'psfTiles': psfTiles.map(_psfTileToJson).toList(),
      });
    } catch (e) {
      _logError('[API] Get session PSF tiles error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetSessionResiduals(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/residuals');
    try {
      final sessionId = int.parse(id);
      final database = container.read(databaseProvider);
      final residuals =
          await database.scienceDao.getResidualsForSession(sessionId);

      return jsonOk({
        'residuals': residuals.map(_residualVectorToJson).toList(),
      });
    } catch (e) {
      _logError('[API] Get session residuals error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  // ===========================================================================
  // Get Analytics Summary
  // ===========================================================================

  Future<Response> handleGetAnalyticsSummary(Request request) async {
    _logInfo('[API] GET /api/analytics/summary');
    try {
      final database = container.read(databaseProvider);

      // Parse date range if provided
      final startDateStr = request.url.queryParameters['startDate'];
      final endDateStr = request.url.queryParameters['endDate'];

      List<ImagingSession> sessions;
      if (startDateStr != null && endDateStr != null) {
        final startDate = DateTime.parse(startDateStr);
        final endDate = DateTime.parse(endDateStr);
        sessions =
            await database.sessionsDao.getSessionsInRange(startDate, endDate);
      } else {
        sessions = await database.sessionsDao.getAllSessions();
      }

      // Calculate summary stats
      final totalStats = await database.sessionsDao.getTotalStatistics();

      return jsonOk({
        "summary": {
          "totalSessions": totalStats['totalSessions'],
          "totalExposures": totalStats['totalExposures'],
          "totalIntegrationHours": totalStats['totalIntegrationHours'],
          "sessionsInRange": sessions.length,
        },
      });
    } catch (e) {
      _logError('[API] Get analytics summary error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Total Integration Time
  // ===========================================================================

  Future<Response> handleGetTotalIntegrationTime(Request request) async {
    _logInfo('[API] GET /api/analytics/integration-time');
    try {
      final database = container.read(databaseProvider);
      final stats = await database.sessionsDao.getTotalStatistics();

      return jsonOk({
        "totalIntegrationSecs": stats['totalIntegrationHours']! * 3600,
        "totalIntegrationHours": stats['totalIntegrationHours'],
      });
    } catch (e) {
      _logError('[API] Get total integration time error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Target Statistics
  // ===========================================================================

  Future<Response> handleGetTargetStatistics(
      Request request, String targetId) async {
    _logInfo('[API] GET /api/analytics/target/$targetId');
    try {
      final tid = int.parse(targetId);
      final database = container.read(databaseProvider);
      final stats = await database.sessionsDao.getTargetStatistics(tid);

      return jsonOk({"stats": stats});
    } catch (e) {
      _logError('[API] Get target statistics error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Sessions For Target
  // ===========================================================================

  Future<Response> handleGetSessionsForTarget(
      Request request, String targetId) async {
    _logInfo('[API] GET /api/analytics/target/$targetId/sessions');
    try {
      final tid = int.parse(targetId);
      final database = container.read(databaseProvider);
      final sessions = await database.sessionsDao.getSessionsForTarget(tid);

      return jsonOk({
        "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
      });
    } catch (e) {
      _logError('[API] Get sessions for target error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Map<String, dynamic> _sessionToJson(ImagingSession session) {
    return {
      'id': session.id,
      'name': session.name,
      'startTime': session.startTime.millisecondsSinceEpoch,
      'endTime': session.endTime?.millisecondsSinceEpoch,
      'status': session.status,
      'profileId': session.profileId,
      'targetId': session.targetId,
      'sequenceId': session.sequenceId,
      'totalExposures': session.totalExposures,
      'successfulExposures': session.successfulExposures,
      'failedExposures': session.failedExposures,
      'totalIntegrationSecs': session.totalIntegrationSecs,
      'avgHfr': session.avgHfr,
      'avgGuidingRms': session.avgGuidingRms,
      'autofocusCount': session.autofocusCount,
      'avgTemperature': session.avgTemperature,
      'avgHumidity': session.avgHumidity,
      'avgSeeing': session.avgSeeing,
      'notes': session.notes,
      'equipmentSnapshot': session.equipmentSnapshot,
    };
  }

  Map<String, dynamic> _psfTileToJson(PsfFieldTileRow tile) {
    return {
      'id': tile.id,
      'capturedImageId': tile.capturedImageId,
      'sessionId': tile.sessionId,
      'tileRow': tile.tileRow,
      'tileCol': tile.tileCol,
      'starCount': tile.starCount,
      'medianFwhm': tile.medianFwhm,
      'medianHfr': tile.medianHfr,
      'medianEccentricity': tile.medianEccentricity,
      'roundness': tile.roundness,
      'timestamp': tile.timestamp.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> _residualVectorToJson(
    AstrometryResidualVectorRow residual,
  ) {
    return {
      'id': residual.id,
      'capturedImageId': residual.capturedImageId,
      'sessionId': residual.sessionId,
      'x': residual.x,
      'y': residual.y,
      'dxArcsec': residual.dxArcsec,
      'dyArcsec': residual.dyArcsec,
      'magnitudeArcsec': residual.magnitudeArcsec,
      'recommendationCode': residual.recommendationCode,
      'timestamp': residual.timestamp.millisecondsSinceEpoch,
    };
  }
}
