import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for weather data and alerts
class WeatherHandlers {
  final ProviderContainer container;

  WeatherHandlers(this.container);

  // ===========================================================================
  // Get Radar Data
  // ===========================================================================

  Future<Response> handleGetRadarData(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    final forceRefresh = request.url.queryParameters['refresh'] == 'true';
    print('[API] GET /api/weather/radar?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return Response.badRequest(
        body: jsonEncode({"error": "Missing lat/lon query parameters"}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.ok(
          jsonEncode({
            "frames": result.frames.map((f) => _frameToJson(f)).toList(),
            "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
            "cachedAt": DateTime.now().millisecondsSinceEpoch,
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        return Response.ok(
          jsonEncode({
            "frames": [],
            "error": result.errorMessage,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    } catch (e) {
      print('[API] Get radar data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Weather Forecast
  // ===========================================================================

  Future<Response> handleGetForecast(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    print('[API] GET /api/weather/forecast?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return Response.badRequest(
        body: jsonEncode({"error": "Missing lat/lon query parameters"}),
        headers: {'content-type': 'application/json'},
      );
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
      return Response.ok(
        jsonEncode({
          "hasData": result.isSuccess,
          "frameCount": result.frames.length,
          "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
          "lastUpdated": DateTime.now().millisecondsSinceEpoch,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get forecast error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Active Alerts
  // ===========================================================================

  Future<Response> handleGetAlerts(Request request) async {
    print('[API] GET /api/weather/alerts');
    try {
      final alertService = container.read(weatherAlertServiceProvider);
      final currentAlert = alertService.currentAlert;

      if (currentAlert == null) {
        return Response.ok(
          jsonEncode({"alerts": []}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          "alerts": [_alertToJson(currentAlert)],
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get alerts error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Cloud Cover Prediction
  // ===========================================================================

  Future<Response> handleGetCloudCover(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    print('[API] GET /api/weather/cloud-cover?lat=$lat&lon=$lon');

    if (lat == null || lon == null) {
      return Response.badRequest(
        body: jsonEncode({"error": "Missing lat/lon query parameters"}),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      final service = container.read(weatherRadarServiceProvider);
      service.initialize();

      // Get cached frames for cloud cover analysis
      final frames = service.getCachedFrames();

      if (frames == null || frames.isEmpty) {
        return Response.ok(
          jsonEncode({
            "hasData": false,
            "message": "No cloud cover data available. Fetch radar data first.",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Get the most recent frame
      final latestFrame = frames.last;

      return Response.ok(
        jsonEncode({
          "hasData": true,
          "timestamp": latestFrame.timestamp.millisecondsSinceEpoch,
          "frameCount": frames.length,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get cloud cover error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Weather Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    print('[API] GET /api/weather/settings');
    try {
      final database = container.read(databaseProvider);
      final settings = await database.weatherSettingsDao.getOrCreateSettings();

      return Response.ok(
        jsonEncode({
          "settings": {
            "id": settings.id,
            "preferredProvider": settings.preferredProvider,
            "refreshIntervalSeconds": settings.refreshIntervalSeconds,
            "triggerDistanceKm": settings.triggerDistanceKm,
            "leadTimeMinutes": settings.leadTimeMinutes,
            "cloudDensityThreshold": settings.cloudDensityThreshold,
            "weatherSafetyEnabled": settings.weatherSafetyEnabled,
            "autoParkEnabled": settings.autoParkEnabled,
            "autoResumeEnabled": settings.autoResumeEnabled,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get weather settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Update Weather Settings
  // ===========================================================================

  Future<Response> handleUpdateSettings(Request request) async {
    print('[API] POST /api/weather/settings');
    try {
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      await database.weatherSettingsDao.updateSettings(
        preferredProvider: payload['preferredProvider'] as String?,
        refreshIntervalSeconds: payload['refreshIntervalSeconds'] as int?,
        triggerDistanceKm: (payload['triggerDistanceKm'] as num?)?.toDouble(),
        leadTimeMinutes: payload['leadTimeMinutes'] as int?,
        cloudDensityThreshold: (payload['cloudDensityThreshold'] as num?)?.toDouble(),
        weatherSafetyEnabled: payload['weatherSafetyEnabled'] as bool?,
        autoParkEnabled: payload['autoParkEnabled'] as bool?,
        autoResumeEnabled: payload['autoResumeEnabled'] as bool?,
      );

      return Response.ok(
        jsonEncode({"status": "updated"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Update weather settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Check Safe Imaging Conditions
  // ===========================================================================

  Future<Response> handleCheckSafeImaging(Request request) async {
    print('[API] GET /api/weather/safe-imaging');
    try {
      final alertService = container.read(weatherAlertServiceProvider);
      final currentAlert = alertService.currentAlert;

      // Safe to image if no alert or alert level is clear
      final isSafe = currentAlert == null || currentAlert.level == AlertLevel.clear;

      return Response.ok(
        jsonEncode({
          "safeToImage": isSafe,
          "alertLevel": currentAlert?.level.name ?? "none",
          "message": currentAlert?.message ?? "No weather data available",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Check safe imaging error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Clear Weather Cache
  // ===========================================================================

  Future<Response> handleClearCache(Request request) async {
    print('[API] POST /api/weather/clear-cache');
    try {
      final service = container.read(weatherRadarServiceProvider);
      service.clearCache();

      return Response.ok(
        jsonEncode({"status": "cache_cleared"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Clear cache error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
