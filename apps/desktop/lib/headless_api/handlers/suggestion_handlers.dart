import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for target suggestion service
class SuggestionHandlers {
  final ProviderContainer container;

  SuggestionHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SuggestionHandlers');

  // Why: a malformed `/api/suggestions/score/{targetId}` path would otherwise
  // surface a FormatException → 500. Throw BadRequestError so the middleware
  // returns a structured 400.
  int _parsePathId(String raw, String field) {
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw BadRequestError(field: field, expected: 'integer');
    }
    return parsed;
  }

  // ===========================================================================
  // Get Suggestions For Tonight
  // ===========================================================================

  Future<Response> handleGetSuggestionsForTonight(Request request) async {
    _logInfo('[API] GET /api/suggestions/tonight');
    final database = container.read(databaseProvider);

    // Parse query parameters
    final minAltitude =
        double.tryParse(request.url.queryParameters['minAltitude'] ?? '') ??
            30.0;
    final minScore =
        double.tryParse(request.url.queryParameters['minScore'] ?? '') ?? 0.0;
    final maxResults =
        int.tryParse(request.url.queryParameters['maxResults'] ?? '') ?? 20;
    final sortModeStr =
        request.url.queryParameters['sortMode'] ?? 'bestScore';
    final prioritizeIncomplete =
        request.url.queryParameters['prioritizeIncomplete'] == 'true';
    final objectTypesStr = request.url.queryParameters['objectTypes'];

    // Parse preferred object types
    final preferredObjectTypes = objectTypesStr?.split(',') ?? <String>[];

    // Parse sort mode
    final sortMode = SuggestionSortMode.values.firstWhere(
      (m) => m.name == sortModeStr,
      orElse: () => SuggestionSortMode.bestScore,
    );

    // Get location from settings
    final latitude = await database.settingsDao.getObserverLatitude();
    final longitude = await database.settingsDao.getObserverLongitude();
    if (latitude == 0.0 && longitude == 0.0) {
      return jsonBadRequest(
        {"error": "No location configured. Set location in settings first."},
      );
    }

    // Get all targets
    final targets = await database.targetsDao.getAllTargets();
    if (targets.isEmpty) {
      return jsonOk({"suggestions": []});
    }

    // Get all sessions for progress calculation
    final sessions = await database.sessionsDao.getAllSessions();

    // Create suggestion config
    final config = TargetSuggestionConfig(
      minAltitude: minAltitude,
      minScore: minScore,
      sortMode: sortMode,
      prioritizeIncomplete: prioritizeIncomplete,
      preferredObjectTypes: preferredObjectTypes,
    );

    // Generate suggestions
    final loggingService = container.read(loggingServiceProvider);
    final suggestionService =
        TargetSuggestionService(loggingService: loggingService);

    final suggestions = await suggestionService.getSuggestionsForTonight(
      config: config,
      latitude: latitude,
      longitude: longitude,
      targets: targets,
      sessions: sessions,
    );

    // Limit results
    final limited = suggestions.take(maxResults).toList();

    return jsonOk({
      "suggestions": limited.map((s) => _suggestionToJson(s)).toList(),
      "totalMatching": suggestions.length,
      "location": {
        "latitude": latitude,
        "longitude": longitude,
      },
    });
  }

  // ===========================================================================
  // Get Suggestion Config
  // ===========================================================================

  Future<Response> handleGetConfig(Request request) async {
    _logInfo('[API] GET /api/suggestions/config');
    // Return default configuration
    const config = TargetSuggestionConfig();

    return jsonOk({
      "config": {
        "minAltitude": config.minAltitude,
        "minScore": config.minScore,
        "maxMoonDistance": config.maxMoonDistance,
        "sortMode": config.sortMode.name,
        "prioritizeIncomplete": config.prioritizeIncomplete,
        "preferredObjectTypes": config.preferredObjectTypes,
      },
    });
  }

  // ===========================================================================
  // Get Target Score
  // ===========================================================================

  Future<Response> handleGetTargetScore(
      Request request, String targetId) async {
    _logInfo('[API] GET /api/suggestions/score/$targetId');
    final tid = _parsePathId(targetId, 'targetId');
    final database = container.read(databaseProvider);

    // Get target
    final target = await database.targetsDao.getTargetById(tid);
    if (target == null) {
      return jsonNotFound({"error": "Target not found: $targetId"});
    }

    // Get location
    final latitude = await database.settingsDao.getObserverLatitude();
    final longitude = await database.settingsDao.getObserverLongitude();
    if (latitude == 0.0 && longitude == 0.0) {
      return jsonBadRequest({"error": "No location configured"});
    }

    // Get sessions for progress calculation
    final sessions = await database.sessionsDao.getSessionsForTarget(tid);

    // Generate suggestion for this target
    final loggingService = container.read(loggingServiceProvider);
    final suggestionService =
        TargetSuggestionService(loggingService: loggingService);

    const config = TargetSuggestionConfig(
      minAltitude: -90, // Include all altitudes
      minScore: -1000, // Include all scores
    );

    final suggestions = await suggestionService.getSuggestionsForTonight(
      config: config,
      latitude: latitude,
      longitude: longitude,
      targets: [target],
      sessions: sessions,
    );

    if (suggestions.isEmpty) {
      return jsonOk({
        "targetId": tid,
        "targetName": target.name,
        "belowHorizon": null,
        "message":
            "Unable to score target - target may be below horizon or not visible tonight",
      });
    }

    final suggestion = suggestions.first;

    return jsonOk({
      "targetId": tid,
      "targetName": target.name,
      "suggestion": _suggestionToJson(suggestion),
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Map<String, dynamic> _suggestionToJson(TargetSuggestion s) {
    return {
      'targetId': s.targetId,
      'targetName': s.targetName,
      'catalogId': s.catalogId,
      'raHours': s.raHours,
      'decDegrees': s.decDegrees,
      'totalScore': s.totalScore,
      'scoreBreakdown': s.scoreBreakdown,
      'warnings': s.warnings
          .map((w) => {
                'message': w.message,
                'severity': w.severity.name,
              })
          .toList(),
      'visibility': {
        'currentAltitude': s.visibility.currentAltitude,
        'currentAzimuth': s.visibility.currentAzimuth,
        'transitAltitude': s.visibility.transitAltitude,
        'riseTime': s.visibility.riseTime?.millisecondsSinceEpoch,
        'transitTime': s.visibility.transitTime?.millisecondsSinceEpoch,
        'setTime': s.visibility.setTime?.millisecondsSinceEpoch,
        'isCircumpolar': s.visibility.isCircumpolar,
        'neverRises': s.visibility.neverRises,
        'airmass': s.visibility.airmass,
        'moonDistance': s.visibility.moonDistance,
      },
      'reasoning': s.reasoning,
      'dataProgress': s.dataProgress,
      'objectType': s.objectType,
      'magnitude': s.magnitude,
      'sizeArcmin': s.sizeArcmin,
      'constellation': s.constellation,
    };
  }
}
