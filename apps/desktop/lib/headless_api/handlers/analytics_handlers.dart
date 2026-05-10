import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for session management and analytics
class AnalyticsHandlers {
  final ProviderContainer container;

  AnalyticsHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'AnalyticsHandlers');

  // Why: URL path segments like `/api/sessions/{id}` would otherwise reach
  // `int.parse` and a malformed id (e.g. `/api/sessions/foo`) would surface
  // as FormatException → HTTP 500. Translate at the boundary into a 400.
  int _parsePathId(String raw, String field) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw BadRequestError(field: field, expected: 'integer');
    }
    return parsed;
  }

  // ===========================================================================
  // Get All Sessions
  // ===========================================================================

  Future<Response> handleGetAllSessions(Request request) async {
    _logInfo('[API] GET /api/sessions');
    final database = container.read(databaseProvider);
    final sessions = await database.sessionsDao.getAllSessions();

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
  }

  // ===========================================================================
  // Get Session By ID
  // ===========================================================================

  Future<Response> handleGetSessionById(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final session = await database.sessionsDao.getSessionById(sessionId);

    if (session == null) {
      return jsonNotFound({"error": "Session not found: $id"});
    }

    return jsonOk({"session": _sessionToJson(session)});
  }

  // ===========================================================================
  // Get Active Session
  // ===========================================================================

  Future<Response> handleGetActiveSession(Request request) async {
    _logInfo('[API] GET /api/sessions/active');
    final database = container.read(databaseProvider);
    final activeSessions = await database.sessionsDao.getActiveSessions();

    if (activeSessions.isEmpty) {
      return jsonOk({"session": null});
    }

    // Return the most recent active session
    return jsonOk({"session": _sessionToJson(activeSessions.first)});
  }

  // ===========================================================================
  // Get Recent Sessions
  // ===========================================================================

  Future<Response> handleGetRecentSessions(Request request) async {
    final limitStr = request.url.queryParameters['limit'] ?? '10';
    final limit = int.tryParse(limitStr) ?? 10;
    _logInfo('[API] GET /api/sessions/recent?limit=$limit');
    final database = container.read(databaseProvider);
    final sessions =
        await database.sessionsDao.getRecentSessions(limit: limit);

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
  }

  // ===========================================================================
  // Create Session
  // ===========================================================================

  Future<Response> handleCreateSession(Request request) async {
    _logInfo('[API] POST /api/sessions');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    final id = await database.sessionsDao.startSession(
      name: optionalString(payload, 'name'),
      profileId: optionalInt(payload, 'profileId'),
      targetId: optionalInt(payload, 'targetId'),
      sequenceId: optionalInt(payload, 'sequenceId'),
    );

    return jsonOk({"status": "created", "id": id});
  }

  // ===========================================================================
  // Update Session
  // ===========================================================================

  Future<Response> handleUpdateSession(Request request, String id) async {
    _logInfo('[API] PUT /api/sessions/$id');
    final sessionId = _parsePathId(id, 'id');
    final payload = await readJsonObject(request);
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
        totalExposures: optionalInt(payload, 'totalExposures'),
        successfulExposures: optionalInt(payload, 'successfulExposures'),
        failedExposures: optionalInt(payload, 'failedExposures'),
        totalIntegrationSecs: optionalDouble(payload, 'totalIntegrationSecs'),
        avgHfr: optionalDouble(payload, 'avgHfr'),
        avgGuidingRms: optionalDouble(payload, 'avgGuidingRms'),
        autofocusCount: optionalInt(payload, 'autofocusCount'),
      );
    }

    // Update notes if provided
    if (payload.containsKey('notes')) {
      await database.sessionsDao.updateNotes(
        sessionId,
        requireString(payload, 'notes', allowEmpty: true),
      );
    }

    // Update status if provided
    if (payload.containsKey('status')) {
      await database.sessionsDao
          .updateSessionStatus(sessionId, requireString(payload, 'status'));
    }

    return jsonOk({"status": "updated"});
  }

  // ===========================================================================
  // End Session
  // ===========================================================================

  Future<Response> handleEndSession(Request request, String id) async {
    _logInfo('[API] POST /api/sessions/$id/end');
    final sessionId = _parsePathId(id, 'id');
    final payload = await readJsonObject(request);
    final status = optionalString(payload, 'status') ?? 'completed';
    final database = container.read(databaseProvider);

    await database.sessionsDao.endSession(sessionId, status: status);

    return jsonOk({"status": "ended"});
  }

  // ===========================================================================
  // Delete Session
  // ===========================================================================

  Future<Response> handleDeleteSession(Request request, String id) async {
    _logInfo('[API] DELETE /api/sessions/$id');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);

    final deleted = await database.sessionsDao.deleteSession(sessionId);
    if (deleted == 0) {
      return jsonNotFound({"error": "Session not found: $id"});
    }

    return jsonOk({"status": "deleted"});
  }

  // ===========================================================================
  // Get Session Stats
  // ===========================================================================

  Future<Response> handleGetSessionStats(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/stats');
    final sessionId = _parsePathId(id, 'id');
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
  }

  // ===========================================================================
  // Session Science Data
  // ===========================================================================

  Future<Response> handleGetSessionPsfTiles(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/psf-tiles');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final psfTiles =
        await database.scienceDao.getPsfTilesForSession(sessionId);

    return jsonOk({
      'psfTiles': psfTiles.map(_psfTileToJson).toList(),
    });
  }

  Future<Response> handleGetSessionResiduals(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/residuals');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final residuals =
        await database.scienceDao.getResidualsForSession(sessionId);

    return jsonOk({
      'residuals': residuals.map(_residualVectorToJson).toList(),
    });
  }

  // ===========================================================================
  // Get Analytics Summary
  // ===========================================================================

  Future<Response> handleGetAnalyticsSummary(Request request) async {
    _logInfo('[API] GET /api/analytics/summary');
    final database = container.read(databaseProvider);

    // Parse date range if provided
    final startDateStr = request.url.queryParameters['startDate'];
    final endDateStr = request.url.queryParameters['endDate'];

    List<ImagingSession> sessions;
    if (startDateStr != null && endDateStr != null) {
      // Why: invalid ISO dates would otherwise become FormatException → 500;
      // translate to 400 so clients learn the format is wrong.
      final DateTime startDate;
      final DateTime endDate;
      try {
        startDate = DateTime.parse(startDateStr);
        endDate = DateTime.parse(endDateStr);
      } on FormatException catch (e) {
        throw BadRequestError(
          field: 'startDate|endDate',
          expected: 'iso8601_datetime',
          message: e.message,
        );
      }
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
  }

  // ===========================================================================
  // Get Total Integration Time
  // ===========================================================================

  Future<Response> handleGetTotalIntegrationTime(Request request) async {
    _logInfo('[API] GET /api/analytics/integration-time');
    final database = container.read(databaseProvider);
    final stats = await database.sessionsDao.getTotalStatistics();

    return jsonOk({
      "totalIntegrationSecs": stats['totalIntegrationHours']! * 3600,
      "totalIntegrationHours": stats['totalIntegrationHours'],
    });
  }

  // ===========================================================================
  // Get Target Statistics
  // ===========================================================================

  Future<Response> handleGetTargetStatistics(
      Request request, String targetId) async {
    _logInfo('[API] GET /api/analytics/target/$targetId');
    final tid = _parsePathId(targetId, 'targetId');
    final database = container.read(databaseProvider);
    final stats = await database.sessionsDao.getTargetStatistics(tid);

    return jsonOk({"stats": stats});
  }

  // ===========================================================================
  // Get Sessions For Target
  // ===========================================================================

  Future<Response> handleGetSessionsForTarget(
      Request request, String targetId) async {
    _logInfo('[API] GET /api/analytics/target/$targetId/sessions');
    final tid = _parsePathId(targetId, 'targetId');
    final database = container.read(databaseProvider);
    final sessions = await database.sessionsDao.getSessionsForTarget(tid);

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
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
