import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for session management and analytics
class AnalyticsHandlers {
  final ProviderContainer container;

  /// Upper bound for the `/api/sessions/recent` `limit`. Imaging sessions
  /// accumulate slowly; 1000 is far more than any "recent" list shows and keeps
  /// a negative from becoming SQLite `LIMIT -1` (all rows).
  static const int _maxRecentSessionsLimit = 1000;

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

  DateTime? _optionalDateQuery(Request request, String field) {
    final raw = request.url.queryParameters[field];
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw BadRequestError(
        field: field,
        expected: 'iso8601_datetime|epoch_milliseconds',
      );
    }

    // Accept epoch milliseconds from older companion builds while the current
    // client uses the documented ISO-8601 wire shape.
    final epochMilliseconds = int.tryParse(trimmed);
    if (epochMilliseconds != null) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(
          epochMilliseconds,
          isUtc: true,
        );
      } on RangeError {
        throw BadRequestError(
          field: field,
          expected: 'iso8601_datetime|epoch_milliseconds',
        );
      }
    }

    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      throw BadRequestError(
        field: field,
        expected: 'iso8601_datetime|epoch_milliseconds',
      );
    }
    return parsed;
  }

  Future<List<ImagingSession>> _sessionsInRequestedRange(
    Request request,
  ) async {
    final start = _optionalDateQuery(request, 'startDate');
    final end = _optionalDateQuery(request, 'endDate');
    if (start != null && end != null && start.isAfter(end)) {
      throw BadRequestError(
        field: 'startDate|endDate',
        expected: 'startDate <= endDate',
        message: 'The analytics start date must not be after the end date',
      );
    }

    final sessions = await container
        .read(databaseProvider)
        .sessionsDao
        .getAllSessions();
    if (start == null && end == null) return sessions;
    return sessions
        .where(
          (session) =>
              (start == null || !session.startTime.isBefore(start)) &&
              (end == null || !session.startTime.isAfter(end)),
        )
        .toList(growable: false);
  }

  Map<String, num> _statisticsForSessions(List<ImagingSession> sessions) {
    var exposures = 0;
    var integrationSeconds = 0.0;
    for (final session in sessions) {
      exposures += session.totalExposures;
      integrationSeconds += session.totalIntegrationSecs;
    }
    return {
      'totalSessions': sessions.length,
      'totalExposures': exposures,
      'totalIntegrationSecs': integrationSeconds,
      'totalIntegrationHours': integrationSeconds / 3600,
    };
  }

  // Get all sessions

  Future<Response> handleGetAllSessions(Request request) async {
    _logInfo('[API] GET /api/sessions');
    final database = container.read(databaseProvider);
    final sessions = await database.sessionsDao.getAllSessions();

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
  }

  // Get Session By ID

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

  // Get active session

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

  // Get recent sessions

  Future<Response> handleGetRecentSessions(Request request) async {
    // Absent → 10. A supplied limit must be a positive, bounded whole number so
    // a negative can't become SQLite `LIMIT -1` (all rows) and a huge value
    // can't scan the whole session history. Validate before the DAO read.
    final limit =
        optionalQueryInt(
          request.url.queryParameters,
          'limit',
          min: 1,
          max: _maxRecentSessionsLimit,
        ) ??
        10;
    _logInfo('[API] GET /api/sessions/recent?limit=$limit');
    final database = container.read(databaseProvider);
    final sessions = await database.sessionsDao.getRecentSessions(limit: limit);

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
  }

  // Create session

  Future<Response> handleCreateSession(Request request) async {
    _logInfo('[API] POST /api/sessions');
    final payload = await readJsonObject(request);
    const allowedFields = {'name', 'profileId', 'targetId', 'sequenceId'};
    final unknownFields = payload.keys
        .where((key) => !allowedFields.contains(key))
        .toList(growable: false);
    if (unknownFields.isNotEmpty) {
      throw BadRequestError(
        field: unknownFields.join(','),
        expected: 'one of: ${allowedFields.join(', ')}',
        message: 'Unknown session field(s)',
      );
    }
    if (!payload.keys.any(allowedFields.contains)) {
      throw BadRequestError(
        field: 'body',
        expected: 'at least one of: ${allowedFields.join(', ')}',
        message: 'A session must identify its name or imaging context',
      );
    }

    final name = optionalString(payload, 'name')?.trim();
    if (payload.containsKey('name') && (name == null || name.isEmpty)) {
      throw BadRequestError(
        field: 'name',
        expected: 'non-blank string',
        message: 'Session name must not be blank',
      );
    }
    final profileId = optionalInt(payload, 'profileId', min: 1);
    final targetId = optionalInt(payload, 'targetId', min: 1);
    final sequenceId = optionalInt(payload, 'sequenceId', min: 1);
    final database = container.read(databaseProvider);

    if (profileId != null &&
        await database.equipmentProfilesDao.getProfileById(profileId) == null) {
      throw BadRequestError(
        field: 'profileId',
        expected: 'an existing equipment profile id',
      );
    }
    if (targetId != null &&
        await database.targetsDao.getTargetById(targetId) == null) {
      throw BadRequestError(
        field: 'targetId',
        expected: 'an existing target id',
      );
    }
    if (sequenceId != null &&
        await database.sequencesDao.getSequenceById(sequenceId) == null) {
      throw BadRequestError(
        field: 'sequenceId',
        expected: 'an existing sequence id',
      );
    }

    final int id;
    try {
      id = await database.sessionsDao.startSession(
        name: name,
        profileId: profileId,
        targetId: targetId,
        sequenceId: sequenceId,
      );
    } on ActiveImagingSessionException catch (error) {
      return jsonConflict({
        'error': 'active_session_exists',
        'message': error.toString(),
        'activeSessionId': error.sessionId,
      });
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.session,
      action: HostMutationAction.created,
      entityId: id.toString(),
    );
    return jsonOk({"status": "created", "id": id});
  }

  // Update session

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
        totalExposures: optionalInt(payload, 'totalExposures', min: 0),
        successfulExposures: optionalInt(
          payload,
          'successfulExposures',
          min: 0,
        ),
        failedExposures: optionalInt(payload, 'failedExposures', min: 0),
        totalIntegrationSecs: optionalDouble(
          payload,
          'totalIntegrationSecs',
          min: 0,
        ),
        avgHfr: optionalDouble(payload, 'avgHfr', min: 0),
        avgGuidingRms: optionalDouble(payload, 'avgGuidingRms', min: 0),
        autofocusCount: optionalInt(payload, 'autofocusCount', min: 0),
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
      final status = requireString(payload, 'status');
      if (!const {'active', 'completed', 'aborted', 'error'}.contains(status)) {
        throw BadRequestError(
          field: 'status',
          expected: 'active|completed|aborted|error',
        );
      }
      await database.sessionsDao.updateSessionStatus(sessionId, status);
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.session,
      action: HostMutationAction.updated,
      entityId: sessionId.toString(),
    );
    return jsonOk({"status": "updated"});
  }

  // End session

  Future<Response> handleEndSession(Request request, String id) async {
    _logInfo('[API] POST /api/sessions/$id/end');
    final sessionId = _parsePathId(id, 'id');
    final payload = await readJsonObject(request);
    final status = optionalString(payload, 'status') ?? 'completed';
    if (!const {'completed', 'aborted', 'error'}.contains(status)) {
      throw BadRequestError(
        field: 'status',
        expected: 'completed|aborted|error',
      );
    }
    final database = container.read(databaseProvider);

    await database.sessionsDao.endSession(sessionId, status: status);

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.session,
      action: HostMutationAction.updated,
      entityId: sessionId.toString(),
      extra: {'status': status},
    );
    return jsonOk({"status": "ended"});
  }

  // Delete session

  Future<Response> handleDeleteSession(Request request, String id) async {
    _logInfo('[API] DELETE /api/sessions/$id');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);

    final deleted = await database.sessionsDao.deleteSession(sessionId);
    if (deleted == 0) {
      return jsonNotFound({"error": "Session not found: $id"});
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.session,
      action: HostMutationAction.deleted,
      entityId: sessionId.toString(),
    );
    return jsonOk({"status": "deleted"});
  }

  // Get session stats

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
        "avgHfr": hfrCount > 0 ? totalHfr / hfrCount : session.avgHfr,
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

  // Session science data

  Future<Response> handleGetSessionPsfTiles(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/psf-tiles');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final psfTiles = await database.scienceDao.getPsfTilesForSession(sessionId);

    return jsonOk({'psfTiles': psfTiles.map(_psfTileToJson).toList()});
  }

  Future<Response> handleGetSessionResiduals(Request request, String id) async {
    _logInfo('[API] GET /api/sessions/$id/residuals');
    final sessionId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final residuals = await database.scienceDao.getResidualsForSession(
      sessionId,
    );

    return jsonOk({'residuals': residuals.map(_residualVectorToJson).toList()});
  }

  // Get analytics summary

  Future<Response> handleGetAnalyticsSummary(Request request) async {
    _logInfo('[API] GET /api/analytics/summary');
    final sessions = await _sessionsInRequestedRange(request);
    final stats = _statisticsForSessions(sessions);

    return jsonOk({
      "summary": {
        "totalSessions": stats['totalSessions'],
        "totalExposures": stats['totalExposures'],
        "totalIntegrationHours": stats['totalIntegrationHours'],
        "sessionsInRange": sessions.length,
      },
    });
  }

  // Get total integration time

  Future<Response> handleGetTotalIntegrationTime(Request request) async {
    _logInfo('[API] GET /api/analytics/integration-time');
    final sessions = await _sessionsInRequestedRange(request);
    final stats = _statisticsForSessions(sessions);

    return jsonOk({
      "totalIntegrationSecs": stats['totalIntegrationSecs'],
      "totalIntegrationHours": stats['totalIntegrationHours'],
    });
  }

  // Get target statistics

  Future<Response> handleGetTargetStatistics(
    Request request,
    String targetId,
  ) async {
    _logInfo('[API] GET /api/analytics/target/$targetId');
    final tid = _parsePathId(targetId, 'targetId');
    final database = container.read(databaseProvider);
    final stats = await database.sessionsDao.getTargetStatistics(tid);

    return jsonOk({"stats": stats});
  }

  // Untracked targets cleanup

  /// GET /api/analytics/untracked-targets/count
  /// Number of "untracked" library targets (no integration goal, not a
  /// favorite, no captured subs, no integration time, not referenced by any
  /// imaging session) eligible for the opt-in Analytics cleanup. Same
  /// session-aware predicate as the local Drift path, run against the host DB.
  Future<Response> handleGetUntrackedTargetsCount(Request request) async {
    _logInfo('[API] GET /api/analytics/untracked-targets/count');
    final database = container.read(databaseProvider);
    final count = await database.targetsDao.countUntrackedTargets();

    return jsonOk({"count": count});
  }

  /// POST /api/analytics/untracked-targets/remove
  /// Permanently removes every untracked library target (see
  /// [handleGetUntrackedTargetsCount]) and returns how many rows were deleted.
  /// Irreversible — the client confirms with the user before calling this.
  Future<Response> handleRemoveUntrackedTargets(Request request) async {
    _logInfo('[API] POST /api/analytics/untracked-targets/remove');
    final database = container.read(databaseProvider);
    final deleted = await database.targetsDao.deleteUntrackedTargets();

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.target,
      action: HostMutationAction.deleted,
    );
    return jsonOk({"status": "removed", "deleted": deleted});
  }

  // Get sessions for target

  Future<Response> handleGetSessionsForTarget(
    Request request,
    String targetId,
  ) async {
    _logInfo('[API] GET /api/analytics/target/$targetId/sessions');
    final tid = _parsePathId(targetId, 'targetId');
    final database = container.read(databaseProvider);
    final sessions = await database.sessionsDao.getSessionsForTarget(tid);

    return jsonOk({
      "sessions": sessions.map((s) => _sessionToJson(s)).toList(),
    });
  }

  // Helpers

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
