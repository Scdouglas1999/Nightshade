import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for weather data and alerts
class WeatherHandlers {
  final ProviderContainer container;

  WeatherHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'WeatherHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'WeatherHandlers');

  // ===========================================================================
  // Get Radar Data
  // ===========================================================================

  Future<Response> handleGetRadarData(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    final forceRefresh = request.url.queryParameters['refresh'] == 'true';
    _logInfo('[API] GET /api/weather/radar?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

    try {
      final service = container.read(weatherRadarServiceProvider);
      service.initialize();

      final result = await service.fetchRadarFrames(
        latitude: lat,
        longitude: lon,
        forceRefresh: forceRefresh,
      );

      if (result.isSuccess) {
        return jsonOk({
          "frames": result.frames.map((f) => _frameToJson(f)).toList(),
          "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
          "cachedAt": DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        return jsonOk({
          "frames": [],
          "error": result.errorMessage,
        });
      }
    } catch (e) {
      _logError('[API] Get radar data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Weather Forecast
  // ===========================================================================

  Future<Response> handleGetForecast(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    _logInfo('[API] GET /api/weather/forecast?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

    try {
      // Weather forecast can be calculated from radar frames
      final service = container.read(weatherRadarServiceProvider);
      service.initialize();

      final result = await service.fetchRadarFrames(
        latitude: lat,
        longitude: lon,
      );

      // Return basic forecast info based on radar data
      return jsonOk({
        "hasData": result.isSuccess,
        "frameCount": result.frames.length,
        "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
        "lastUpdated": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _logError('[API] Get forecast error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Active Alerts
  // ===========================================================================

  Future<Response> handleGetAlerts(Request request) async {
    _logInfo('[API] GET /api/weather/alerts');
    try {
      final alertService = container.read(weatherAlertServiceProvider);
      final currentAlert = alertService.currentAlert;

      if (currentAlert == null) {
        return jsonOk({"alerts": []});
      }

      return jsonOk({
        "alerts": [_alertToJson(currentAlert)],
      });
    } catch (e) {
      _logError('[API] Get alerts error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Cloud Cover Prediction
  // ===========================================================================

  Future<Response> handleGetCloudCover(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    _logInfo('[API] GET /api/weather/cloud-cover?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

    try {
      final service = container.read(weatherRadarServiceProvider);
      service.initialize();

      // Get cached frames for cloud cover analysis
      final frames = service.getCachedFrames();

      if (frames == null || frames.isEmpty) {
        return jsonOk({
          "hasData": false,
          "message": "No cloud cover data available. Fetch radar data first.",
        });
      }

      // Get the most recent frame
      final latestFrame = frames.last;

      return jsonOk({
        "hasData": true,
        "timestamp": latestFrame.timestamp.millisecondsSinceEpoch,
        "frameCount": frames.length,
      });
    } catch (e) {
      _logError('[API] Get cloud cover error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Weather Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    _logInfo('[API] GET /api/weather/settings');
    try {
      final database = container.read(databaseProvider);
      final settings = await database.weatherSettingsDao.getOrCreateSettings();

      return jsonOk({
        "settings": {
          "id": settings.id,
          "preferredProvider": settings.preferredProvider,
          "refreshIntervalSeconds": settings.refreshIntervalSeconds,
          "triggerDistanceKm": settings.triggerDistanceKm,
          "leadTimeMinutes": settings.leadTimeMinutes,
          "cloudDensityThreshold": settings.cloudDensityThreshold,
          "weatherSafetyEnabled": settings.weatherSafetyEnabled,
          "maxHumidityPercent": settings.maxHumidityPercent,
          "maxWindSpeedKph": settings.maxWindSpeedKph,
          "maxCloudCoverPercent": settings.maxCloudCoverPercent,
          "autoParkEnabled": settings.autoParkEnabled,
          "autoResumeEnabled": settings.autoResumeEnabled,
        },
      });
    } catch (e) {
      _logError('[API] Get weather settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Weather Settings
  // ===========================================================================

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/weather/settings');
    try {
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      await database.weatherSettingsDao.updateSettings(
        preferredProvider: payload['preferredProvider'] as String?,
        refreshIntervalSeconds: payload['refreshIntervalSeconds'] as int?,
        triggerDistanceKm: (payload['triggerDistanceKm'] as num?)?.toDouble(),
        leadTimeMinutes: payload['leadTimeMinutes'] as int?,
        cloudDensityThreshold:
            (payload['cloudDensityThreshold'] as num?)?.toDouble(),
        weatherSafetyEnabled: payload['weatherSafetyEnabled'] as bool?,
        maxHumidityPercent: (payload['maxHumidityPercent'] as num?)?.toDouble(),
        maxWindSpeedKph: (payload['maxWindSpeedKph'] as num?)?.toDouble(),
        maxCloudCoverPercent:
            (payload['maxCloudCoverPercent'] as num?)?.toDouble(),
        autoParkEnabled: payload['autoParkEnabled'] as bool?,
        autoResumeEnabled: payload['autoResumeEnabled'] as bool?,
      );

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update weather settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Check Safe Imaging Conditions
  // ===========================================================================

  Future<Response> handleCheckSafeImaging(Request request) async {
    _logInfo('[API] GET /api/weather/safe-imaging');
    try {
      final alertService = container.read(weatherAlertServiceProvider);
      final currentAlert = alertService.currentAlert;

      // Safe to image if no alert or alert level is clear
      final isSafe =
          currentAlert == null || currentAlert.level == AlertLevel.clear;

      return jsonOk({
        "safeToImage": isSafe,
        "alertLevel": currentAlert?.level.name ?? "none",
        "message": currentAlert?.message ?? "No weather data available",
      });
    } catch (e) {
      _logError('[API] Check safe imaging error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Clear Weather Cache
  // ===========================================================================

  Future<Response> handleClearCache(Request request) async {
    _logInfo('[API] POST /api/weather/clear-cache');
    try {
      final service = container.read(weatherRadarServiceProvider);
      service.clearCache();

      return jsonOk({"status": "cache_cleared"});
    } catch (e) {
      _logError('[API] Clear cache error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Map<String, dynamic> _frameToJson(RadarFrame frame) {
    return {
      'timestamp': frame.timestamp.millisecondsSinceEpoch,
      'tileUrlTemplate': frame.tileUrlTemplate,
      'north': frame.north,
      'south': frame.south,
      'east': frame.east,
      'west': frame.west,
      'opacity': frame.opacity,
      'isForecast': frame.isForecast,
      'tileType': frame.tileType.name,
    };
  }

  Map<String, dynamic> _alertToJson(WeatherAlert alert) {
    return {
      'level': alert.level.name,
      'message': alert.message,
      'eta': alert.eta?.millisecondsSinceEpoch,
      'cloudDensityPercent': alert.cloudDensityPercent,
      'distanceKm': alert.distanceKm,
      'generatedAt': alert.generatedAt.millisecondsSinceEpoch,
    };
  }
}
