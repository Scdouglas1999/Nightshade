import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/weather/weather_models.dart';
import '../services/weather/weather_radar_service.dart';
import '../services/weather/cloud_motion_analyzer.dart';
import '../services/weather/weather_alert_service.dart';
import '../database/database.dart' as db;
import 'database_provider.dart';
import 'settings_provider.dart';

// Export weather safety provider
export 'weather_safety_provider.dart';

// ============================================================================
// Service Providers
// ============================================================================

/// Provider for the weather radar service
///
/// Manages radar data fetching from multiple providers (NOAA, RainViewer, OpenMeteo).
/// Initializes on first access and disposes when the provider is destroyed.
final weatherRadarServiceProvider = Provider<WeatherRadarService>((ref) {
  final service = WeatherRadarService(ref);
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the cloud motion analyzer
///
/// Stateless service that analyzes radar frame sequences to predict cloud movement
/// and calculate estimated time of arrival at user location.
final cloudMotionAnalyzerProvider = Provider<CloudMotionAnalyzer>((ref) {
  return CloudMotionAnalyzer();
});

/// Provider for the weather alert service
///
/// Evaluates weather conditions and generates alerts based on cloud proximity,
/// density, and motion. Disposes stream resources when provider is destroyed.
final weatherAlertServiceProvider = Provider<WeatherAlertService>((ref) {
  final service = WeatherAlertService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ============================================================================
// Settings Providers
// ============================================================================

/// Stream provider for weather settings from database
///
/// Watches the weather settings row in the database and emits updates
/// whenever settings change. Returns null if no settings row exists yet.
final weatherSettingsStreamProvider =
    StreamProvider<db.WeatherSettingRow?>((ref) {
  final database = ref.watch(databaseProvider);
  return database.weatherSettingsDao.watchSettings();
});

/// Synchronous provider for weather settings
///
/// Returns the current weather settings model, converting from the database
/// row type. Returns default settings if database settings are not yet loaded.
final weatherSettingsProvider = Provider<WeatherSettings>((ref) {
  final settingsAsync = ref.watch(weatherSettingsStreamProvider);
  final row = settingsAsync.valueOrNull;

  if (row == null) {
    return WeatherSettings.defaultSettings;
  }

  // Convert database row to model
  return WeatherSettings(
    triggerDistanceKm: row.triggerDistanceKm,
    cloudDensityThreshold: row.cloudDensityThreshold,
    leadTimeMinutes: row.leadTimeMinutes,
    weatherSafetyEnabled: row.weatherSafetyEnabled,
    maxHumidityPercent: row.maxHumidityPercent,
    maxWindSpeedKph: row.maxWindSpeedKph,
    maxCloudCoverPercent: row.maxCloudCoverPercent,
    autoParkEnabled: row.autoParkEnabled,
    autoResumeEnabled: row.autoResumeEnabled,
    preferredProvider: _parseProviderType(row.preferredProvider),
    refreshIntervalSeconds: row.refreshIntervalSeconds,
  );
});

/// Parse radar provider type from database string
RadarProviderType _parseProviderType(String providerString) {
  switch (providerString.toLowerCase()) {
    case 'auto':
      return RadarProviderType.auto;
    case 'goessatellite':
      return RadarProviderType.goesSatellite;
    case 'noaa':
      return RadarProviderType.noaa;
    case 'rainviewer':
      return RadarProviderType.rainviewer;
    case 'openmeteo':
      return RadarProviderType.openmeteo;
    default:
      return RadarProviderType.auto;
  }
}

// ============================================================================
// Cloud Cover Provider
// ============================================================================

/// Provider for current cloud cover percentage from Open-Meteo
///
/// Fetches real-time cloud cover data independent of the visual satellite overlay.
/// Returns a percentage 0-100 where 0 = clear skies, 100 = fully overcast.
final cloudCoverPercentageProvider = FutureProvider<double?>((ref) async {
  final observerLocation = ref.watch(appObserverLocationProvider);
  if (observerLocation == null) {
    return null;
  }

  final latitude = observerLocation.latitude;
  final longitude = observerLocation.longitude;

  // Skip if location not set
  if (latitude == 0.0 && longitude == 0.0) {
    return null;
  }

  try {
    // Use Open-Meteo API directly for cloud cover
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current': 'cloud_cover',
      },
    );

    final client = http.Client();
    try {
      final response = await client.get(uri);

      if (response.statusCode != 200) {
        developer.log('Cloud cover fetch failed: ${response.statusCode}',
            name: 'Weather', level: 900);
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;

      if (current == null) {
        return null;
      }

      final cloudCover = current['cloud_cover'];
      if (cloudCover is num) {
        developer.log('Current cloud cover: ${cloudCover.toDouble()}%',
            name: 'Weather');
        return cloudCover.toDouble();
      }

      return null;
    } finally {
      client.close();
    }
  } catch (e) {
    developer.log('Error fetching cloud cover: $e',
        name: 'Weather', level: 1000);
    return null;
  }
});

// ============================================================================
// Data Stream Providers
// ============================================================================

/// Provider for radar frames that triggers fetching automatically.
///
/// Watches the user's location from app settings and fetches radar frames
/// from the appropriate provider. Re-fetches when invalidated.
final weatherRadarFramesProvider =
    FutureProvider<List<RadarFrame>>((ref) async {
  final observerLocation = ref.watch(appObserverLocationProvider);
  if (observerLocation == null) {
    developer.log('No app settings yet, returning empty', name: 'WeatherRadar');
    return [];
  }

  final latitude = observerLocation.latitude;
  final longitude = observerLocation.longitude;

  // Skip fetch if location not set
  if (latitude == 0.0 && longitude == 0.0) {
    developer.log('Location not set, returning empty', name: 'WeatherRadar');
    return [];
  }

  developer.log('Fetching for location ($latitude, $longitude)',
      name: 'WeatherRadar');

  final radarService = ref.read(weatherRadarServiceProvider);

  // Force fresh fetch (clear cache to get updated URL format)
  radarService.clearCache();

  final result = await radarService.fetchRadarFrames(
    latitude: latitude,
    longitude: longitude,
    forceRefresh: true,
  );

  if (result.isSuccess) {
    developer.log('Got ${result.frames.length} frames', name: 'WeatherRadar');
    return result.frames;
  } else {
    developer.log('Fetch failed - ${result.errorMessage}',
        name: 'WeatherRadar', level: 900);
    // Return empty list instead of throwing to avoid breaking the UI
    return [];
  }
});

/// Stream provider for weather alerts
///
/// Broadcasts weather alerts as conditions change. Alerts are debounced
/// to prevent rapid flapping between alert levels.
final weatherAlertStreamProvider = StreamProvider<WeatherAlert>((ref) {
  final alertService = ref.watch(weatherAlertServiceProvider);
  return alertService.alertStream;
});

/// Current alert level provider
///
/// Provides quick synchronous access to the current alert level without
/// needing to handle async state. Returns AlertLevel.clear if no alert exists.
final currentAlertLevelProvider = Provider<AlertLevel>((ref) {
  final alertAsync = ref.watch(weatherAlertStreamProvider);
  return alertAsync.valueOrNull?.level ?? AlertLevel.clear;
});

// ============================================================================
// Combined Status Provider
// ============================================================================

/// Combined weather status provider for UI consumption
///
/// Aggregates radar frames, evaluated alert conditions, and settings into a
/// single status object for convenient access in UI widgets. Watches the
/// evaluated conditions provider directly so that the alert level reflects
/// real cloud cover and motion data rather than relying on the alert stream
/// (which only emits after debouncing and explicit evaluation calls).
final weatherStatusProvider = Provider<WeatherStatus>((ref) {
  final framesAsync = ref.watch(weatherRadarFramesProvider);

  // Watch evaluated conditions directly - this is the source of truth for
  // current weather alert level, incorporating real cloud cover from Open-Meteo
  // and cloud motion analysis from radar frames.
  final evaluatedAsync = ref.watch(evaluateWeatherConditionsProvider);

  // Also watch the stream for debounced alerts (used for notifications)
  final streamAlertAsync = ref.watch(weatherAlertStreamProvider);

  // Determine loading state
  final isLoading = framesAsync.isLoading;

  // Determine error message
  String? errorMessage;
  if (framesAsync.hasError) {
    errorMessage = framesAsync.error.toString();
  }
  // Don't treat evaluation errors as weather errors - they just mean
  // we can't determine conditions yet (e.g., location not set)

  // Use the evaluated alert as the primary source of truth for current level.
  // Fall back to the stream alert if evaluation hasn't completed yet.
  // Only default to clear if neither source has data.
  final WeatherAlert? activeAlert;
  final AlertLevel currentLevel;

  if (evaluatedAsync.hasValue) {
    activeAlert = evaluatedAsync.value;
    currentLevel = activeAlert?.level ?? AlertLevel.clear;
  } else if (streamAlertAsync.hasValue) {
    activeAlert = streamAlertAsync.value;
    currentLevel = activeAlert?.level ?? AlertLevel.clear;
  } else {
    activeAlert = null;
    currentLevel = AlertLevel.clear;
  }

  // Get radar frames or empty list
  final radarFrames = framesAsync.valueOrNull ?? [];

  // Build combined status
  return WeatherStatus(
    currentLevel: currentLevel,
    activeAlert: activeAlert,
    motion: null, // Updated separately by motion analysis
    radarFrames: radarFrames,
    currentFrameIndex: 0,
    lastUpdate: DateTime.now(),
    isLoading: isLoading,
    errorMessage: errorMessage,
  );
});

// ============================================================================
// Action Providers
// ============================================================================

/// Provider that triggers radar data fetch for user's location
///
/// Call ref.read(fetchWeatherProvider) to trigger a radar data fetch.
/// Automatically uses location from app settings. Auto-disposes after use.
final fetchWeatherProvider = FutureProvider.autoDispose<void>((ref) async {
  final observerLocation = ref.watch(appObserverLocationProvider);
  if (observerLocation == null) {
    return;
  }

  final latitude = observerLocation.latitude;
  final longitude = observerLocation.longitude;

  // Skip fetch if location not set
  if (latitude == 0.0 && longitude == 0.0) {
    return;
  }

  final radarService = ref.read(weatherRadarServiceProvider);
  await radarService.fetchRadarFrames(
    latitude: latitude,
    longitude: longitude,
  );
});

/// Provider that performs cloud motion analysis on current radar frames
///
/// Call ref.read(analyzeCloudMotionProvider) to trigger motion analysis.
/// Returns CloudMotion result or null if insufficient data. Auto-disposes.
final analyzeCloudMotionProvider =
    FutureProvider.autoDispose<CloudMotion?>((ref) async {
  final observerLocation = ref.watch(appObserverLocationProvider);
  if (observerLocation == null) {
    return null;
  }

  final latitude = observerLocation.latitude;
  final longitude = observerLocation.longitude;

  // Skip analysis if location not set
  if (latitude == 0.0 && longitude == 0.0) {
    return null;
  }

  final radarService = ref.read(weatherRadarServiceProvider);
  final frames = radarService.getCachedFrames();

  if (frames == null || frames.isEmpty) {
    return null;
  }

  final analyzer = ref.read(cloudMotionAnalyzerProvider);
  return analyzer.analyzeMotion(
    frames: frames,
    userLatitude: latitude,
    userLongitude: longitude,
  );
});

/// Provider that evaluates weather conditions and generates alerts
///
/// Call ref.read(evaluateWeatherConditionsProvider) to evaluate current
/// conditions and generate an alert. Auto-disposes after use.
final evaluateWeatherConditionsProvider =
    FutureProvider.autoDispose<WeatherAlert>((ref) async {
  final weatherSettings = ref.watch(weatherSettingsProvider);
  final motion = await ref.watch(analyzeCloudMotionProvider.future);

  // Get actual cloud cover percentage from Open-Meteo API
  // This is the real-time cloud cover at the user's location
  final cloudCoverPercent =
      await ref.watch(cloudCoverPercentageProvider.future);

  // Use actual cloud cover if available, otherwise fall back to 0 (clear)
  final currentCloudDensity = cloudCoverPercent ?? 0.0;

  final alertService = ref.read(weatherAlertServiceProvider);
  return alertService.evaluateConditions(
    motion: motion,
    currentCloudDensity: currentCloudDensity,
    settings: weatherSettings,
  );
});
