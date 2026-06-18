import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for weather data and alerts
class WeatherHandlers {
  final ProviderContainer container;

  WeatherHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'WeatherHandlers');

  /// Coarsen a coordinate before it reaches a log line. The observer's
  /// precise latitude/longitude is their home/observatory location and
  /// must not be persisted to the structured log (which is readable on
  /// disk and downloadable over `/api/logs/*`). Rounding to one decimal
  /// place (~11 km) keeps the entry useful for debugging which region a
  /// fetch covered without recording where the operator lives. The full
  /// value still flows to the upstream weather provider and the API
  /// response — only the log copy is coarsened.
  static String _coarseCoord(double? value) =>
      value == null ? 'null' : value.toStringAsFixed(1);

  // ===========================================================================
  // Get Radar Data
  // ===========================================================================

  Future<Response> handleGetRadarData(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    final forceRefresh = request.url.queryParameters['refresh'] == 'true';
    _logInfo(
      '[API] GET /api/weather/radar?lat=${_coarseCoord(lat)}&lon=${_coarseCoord(lon)}',
    );

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

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
    }
    // Why: upstream radar fetch failed — surface the failure with a non-2xx
    // status (502 Bad Gateway). Previously this returned 200 with an empty
    // frames list, hiding the failure from clients/observability.
    return jsonResponse({
      "error": result.errorMessage ?? 'radar_fetch_failed',
      "frames": [],
    }, statusCode: 502);
  }

  // ===========================================================================
  // Get Weather Forecast
  // ===========================================================================

  Future<Response> handleGetForecast(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    _logInfo(
      '[API] GET /api/weather/forecast?lat=${_coarseCoord(lat)}&lon=${_coarseCoord(lon)}',
    );

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

    // Back the forecast with the same Open-Meteo hourly cloud feed the desktop
    // planner uses (weekForecastCloudProvider, keyed only on the site so remote
    // and local share one cached fetch). It returns a RadarFetchResult whose
    // frames are hourly cloud-cover samples (opacity 0-1 == cloud cover 0-100%)
    // spanning the past day plus the next several forecast days.
    try {
      final result = await container.read(
        weekForecastCloudProvider(ForecastSite(lat, lon)).future,
      );

      if (!result.isSuccess) {
        return jsonResponse({
          "error": "forecast_fetch_failed",
          "message": result.errorMessage ?? 'Cloud forecast unavailable',
        }, statusCode: 502);
      }

      final now = DateTime.now().toUtc();
      final hourly = result.frames
          .where((f) => !f.timestamp.toUtc().isBefore(now))
          .map(
            (f) => {
              'timestamp': f.timestamp.toUtc().millisecondsSinceEpoch,
              'time': f.timestamp.toUtc().toIso8601String(),
              // Open-Meteo cloud frames carry cloud cover as opacity in [0, 1].
              'cloudCoverPercent': (f.opacity.clamp(0.0, 1.0) * 100.0),
            },
          )
          .toList();

      return jsonOk({
        "hasData": true,
        "latitude": lat,
        "longitude": lon,
        "source": result.providerName ?? 'Open-Meteo',
        "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
        "lastUpdated": DateTime.now().millisecondsSinceEpoch,
        "hourly": hourly,
      });
    } catch (e, stackTrace) {
      // The fetch genuinely requires a live network call; surface a clean 502
      // rather than fabricating a forecast.
      throw HandlerFailure(
        code: 'forecast_fetch_failed',
        message: 'Cloud forecast unavailable.',
        statusCode: 502,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================================
  // Get Active Alerts
  // ===========================================================================

  Future<Response> handleGetAlerts(Request request) async {
    _logInfo('[API] GET /api/weather/alerts');
    final alertService = container.read(weatherAlertServiceProvider);
    final currentAlert = alertService.currentAlert;

    if (currentAlert == null) {
      return jsonOk({"alerts": []});
    }

    return jsonOk({
      "alerts": [_alertToJson(currentAlert)],
    });
  }

  // ===========================================================================
  // Get Cloud Cover Prediction
  // ===========================================================================

  Future<Response> handleGetCloudCover(Request request) async {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    _logInfo(
      '[API] GET /api/weather/cloud-cover?lat=${_coarseCoord(lat)}&lon=${_coarseCoord(lon)}',
    );

    if (lat == null || lon == null) {
      return jsonBadRequest({"error": "Missing lat/lon query parameters"});
    }

    // Use the same Open-Meteo hourly cloud feed the desktop app uses
    // (weekForecastCloudProvider), then read the sample nearest to "now" — the
    // same nearest-hour lookup OpenMeteoCloudProvider.getCloudCoverAt performs.
    // The cloudCoverPercentageProvider the UI watches is location-bound (it
    // reads the configured observer location, not an arbitrary lat/lon), so we
    // can't honor the request's lat/lon through it; this feed takes lat/lon
    // directly and shares the same provider/cache as the planner.
    try {
      final result = await container.read(
        weekForecastCloudProvider(ForecastSite(lat, lon)).future,
      );

      if (!result.isSuccess || result.frames.isEmpty) {
        return jsonResponse({
          "error": "cloud_cover_fetch_failed",
          "message": result.errorMessage ?? 'No cloud cover data available',
        }, statusCode: 502);
      }

      // Nearest frame to the current instant (frame timestamps are UTC) — the
      // same nearest-hour lookup OpenMeteoCloudProvider.getCloudCoverAt does.
      final now = DateTime.now().toUtc();
      RadarFrame nearest = result.frames.first;
      Duration bestDistance = nearest.timestamp.toUtc().difference(now).abs();
      for (final frame in result.frames) {
        final d = frame.timestamp.toUtc().difference(now).abs();
        if (d < bestDistance) {
          bestDistance = d;
          nearest = frame;
        }
      }

      return jsonOk({
        "hasData": true,
        "latitude": lat,
        "longitude": lon,
        "source": result.providerName ?? 'Open-Meteo',
        // Open-Meteo cloud frames carry cloud cover as opacity in [0, 1].
        "cloudCoverPercent": (nearest.opacity.clamp(0.0, 1.0) * 100.0),
        "timestamp": nearest.timestamp.toUtc().millisecondsSinceEpoch,
        "fetchedAt": result.fetchedAt.millisecondsSinceEpoch,
      });
    } catch (e, stackTrace) {
      // Genuine live network fetch can fail; surface a clean 502.
      throw HandlerFailure(
        code: 'cloud_cover_fetch_failed',
        message: 'Cloud cover data unavailable.',
        statusCode: 502,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================================
  // Get Weather Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    _logInfo('[API] GET /api/weather/settings');
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
  }

  // ===========================================================================
  // Update Weather Settings
  // ===========================================================================

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/weather/settings');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    await database.weatherSettingsDao.updateSettings(
      preferredProvider: optionalString(payload, 'preferredProvider'),
      refreshIntervalSeconds: optionalInt(payload, 'refreshIntervalSeconds'),
      triggerDistanceKm: optionalDouble(payload, 'triggerDistanceKm'),
      leadTimeMinutes: optionalInt(payload, 'leadTimeMinutes'),
      cloudDensityThreshold: optionalDouble(payload, 'cloudDensityThreshold'),
      weatherSafetyEnabled: optionalBool(payload, 'weatherSafetyEnabled'),
      maxHumidityPercent: optionalDouble(payload, 'maxHumidityPercent'),
      maxWindSpeedKph: optionalDouble(payload, 'maxWindSpeedKph'),
      maxCloudCoverPercent: optionalDouble(payload, 'maxCloudCoverPercent'),
      autoParkEnabled: optionalBool(payload, 'autoParkEnabled'),
      autoResumeEnabled: optionalBool(payload, 'autoResumeEnabled'),
    );

    return jsonOk({"status": "updated"});
  }

  // ===========================================================================
  // Check Safe Imaging Conditions
  // ===========================================================================

  Future<Response> handleCheckSafeImaging(Request request) async {
    _logInfo('[API] GET /api/weather/safe-imaging');
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
  }

  // ===========================================================================
  // Live telemetry (hardware + safety aggregate)
  // ===========================================================================

  /// GET /api/weather/current
  ///
  /// Returns safe-imaging status plus live ObservingConditions telemetry when
  /// a weather device is connected ([weatherStateProvider]). Fields are omitted
  /// (null) when no hardware source is available — clients must not invent
  /// values.
  Future<Response> handleGetCurrent(Request request) async {
    _logInfo('[API] GET /api/weather/current');
    final alertService = container.read(weatherAlertServiceProvider);
    final currentAlert = alertService.currentAlert;
    final isSafe =
        currentAlert == null || currentAlert.level == AlertLevel.clear;

    final weatherState = container.read(weatherStateProvider);
    final hardwareConnected =
        weatherState.connectionState == DeviceConnectionState.connected;

    double? temperature;
    double? humidity;
    double? cloudCover;
    double? windSpeed;
    double? dewPoint;
    if (hardwareConnected) {
      temperature = weatherState.temperature;
      humidity = weatherState.humidity;
      cloudCover = weatherState.cloudCover;
      windSpeed = weatherState.windSpeed;
      dewPoint = weatherState.dewPoint;
    }

    return jsonOk({
      'safeToImage': isSafe,
      'alertLevel': currentAlert?.level.name ?? 'none',
      'message': currentAlert?.message ?? 'No weather data available',
      'currentAlert': currentAlert != null ? _alertToJson(currentAlert) : null,
      'hardwareConnected': hardwareConnected,
      'deviceId': weatherState.deviceId,
      'deviceName': weatherState.deviceName,
      'lastUpdated': weatherState.lastUpdated?.toIso8601String(),
      'temperature': temperature,
      'humidity': humidity,
      'cloudCover': cloudCover,
      'windSpeed': windSpeed,
      'dewPoint': dewPoint,
      'pressure': hardwareConnected ? weatherState.pressure : null,
      'windDirection': hardwareConnected ? weatherState.windDirection : null,
      'skyQuality': hardwareConnected ? weatherState.skyQuality : null,
      'rainRate': hardwareConnected ? weatherState.rainRate : null,
    });
  }

  // ===========================================================================
  // Clear Weather Cache
  // ===========================================================================

  Future<Response> handleClearCache(Request request) async {
    _logInfo('[API] POST /api/weather/clear-cache');
    final service = container.read(weatherRadarServiceProvider);
    service.clearCache();

    return jsonOk({"status": "cache_cleared"});
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
