import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/weather/weather_models.dart';
import '../../providers/database_provider.dart';
import 'radar_provider.dart';
import 'radar_provider_factory.dart';
import 'providers/providers.dart';

/// Central service for coordinating weather radar data fetching.
///
/// This service manages radar providers (NOAA, RainViewer, OpenMeteo),
/// handles caching, and streams radar frame updates to the UI.
///
/// Usage:
/// ```dart
/// final service = WeatherRadarService(ref);
/// service.initialize();
///
/// final result = await service.fetchRadarFrames(
///   latitude: 40.7128,
///   longitude: -74.0060,
/// );
///
/// if (result.isSuccess) {
///   print('Fetched ${result.frames.length} radar frames');
/// }
/// ```
class WeatherRadarService {
  final Ref _ref;

  /// Factory for managing and selecting radar providers.
  late final RadarProviderFactory _providerFactory;

  /// Stream controller for broadcasting radar frame updates.
  final StreamController<List<RadarFrame>> _framesController =
      StreamController<List<RadarFrame>>.broadcast();

  /// Cached fetch result from the last successful fetch.
  RadarFetchResult? _cachedResult;

  /// Timestamp of the last fetch operation.
  DateTime? _lastFetchTime;

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Creates a weather radar service instance.
  ///
  /// The service must be initialized via [initialize] before use.
  WeatherRadarService(this._ref);

  /// Initializes the service and registers all radar providers.
  ///
  /// Must be called before using the service. Registers:
  /// - GOES Satellite (US/Americas - actual cloud cover)
  /// - NOAA NEXRAD (US - precipitation only)
  /// - RainViewer (global - precipitation only)
  /// - OpenMeteo (global - cloud forecast)
  void initialize() {
    if (_initialized) {
      return;
    }

    _providerFactory = RadarProviderFactory();

    // Register all available providers
    // GOES Satellite shows actual cloud cover (preferred for astrophotography)
    _providerFactory.registerProvider(GoesSatelliteProvider());
    // NOAA NEXRAD shows precipitation radar
    _providerFactory.registerProvider(NoaaRadarProvider());
    // RainViewer provides global precipitation radar
    _providerFactory.registerProvider(RainViewerRadarProvider());
    // OpenMeteo provides cloud cover forecast data
    _providerFactory.registerProvider(OpenMeteoCloudProvider());

    _initialized = true;
    print('WeatherRadarService initialized with ${_providerFactory.providerCount} providers');
  }

  /// Gets the current provider for the user's location.
  ///
  /// Selects a provider based on:
  /// 1. User's preferred provider from settings (if it covers the location)
  /// 2. Auto-selection with priority: NOAA > RainViewer > OpenMeteo
  ///
  /// Parameters:
  /// - [latitude]: Location latitude in degrees
  /// - [longitude]: Location longitude in degrees
  /// - [preference]: Preferred provider type from settings
  ///
  /// Returns the selected [RadarProvider] or null if no provider covers the location.
  RadarProvider? getCurrentProvider(
    double latitude,
    double longitude,
    RadarProviderType preference,
  ) {
    _ensureInitialized();

    return _providerFactory.selectProvider(
      latitude: latitude,
      longitude: longitude,
      preferredProvider: preference,
    );
  }

  /// Fetches radar frames for the specified location.
  ///
  /// Uses cached data if available and fresh (within refresh interval),
  /// otherwise fetches new data from the appropriate provider.
  ///
  /// Parameters:
  /// - [latitude]: Center latitude in degrees
  /// - [longitude]: Center longitude in degrees
  /// - [radiusKm]: Search radius in kilometers (default: 100.0)
  /// - [forceRefresh]: If true, bypass cache and fetch fresh data
  ///
  /// Returns a [RadarFetchResult] containing frames or an error message.
  Future<RadarFetchResult> fetchRadarFrames({
    required double latitude,
    required double longitude,
    double radiusKm = 100.0,
    bool forceRefresh = false,
  }) async {
    _ensureInitialized();

    // Get weather settings to determine refresh interval and provider preference
    final database = _ref.read(databaseProvider);
    final settingsRow = await database.weatherSettingsDao.getOrCreateSettings();
    final refreshInterval = Duration(seconds: settingsRow.refreshIntervalSeconds);

    // Check if we have fresh cached data
    if (!forceRefresh && !isCacheStale(refreshInterval)) {
      if (_cachedResult != null && _cachedResult!.isSuccess) {
        debugPrint('WeatherRadarService: Returning cached data (${_cachedResult!.frames.length} frames)');
        return _cachedResult!;
      }
    }

    // Parse provider preference from settings
    final providerPreference = _parseProviderType(settingsRow.preferredProvider);

    // Select appropriate provider
    final provider = getCurrentProvider(latitude, longitude, providerPreference);

    if (provider == null) {
      final errorResult = RadarFetchResult.error(
        'No radar provider available for location ($latitude, $longitude)',
      );
      _cachedResult = errorResult;
      _lastFetchTime = DateTime.now();
      return errorResult;
    }

    debugPrint('WeatherRadarService: Fetching from ${provider.name}');

    // Fetch radar frames from the selected provider
    try {
      final result = await provider.fetchRadarFrames(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );

      // Cache the result
      _cachedResult = result;
      _lastFetchTime = DateTime.now();

      // Broadcast frames to stream listeners
      if (result.isSuccess) {
        _framesController.add(result.frames);
        debugPrint('WeatherRadarService: Fetched ${result.frames.length} frames from ${provider.name}');
      } else {
        debugPrint('WeatherRadarService: Fetch failed - ${result.errorMessage}');
      }

      return result;
    } catch (e, stackTrace) {
      final errorResult = RadarFetchResult.error(
        'Unexpected error fetching radar data: $e',
      );
      _cachedResult = errorResult;
      _lastFetchTime = DateTime.now();

      debugPrint('WeatherRadarService: Exception during fetch - $e');
      debugPrint('Stack trace: $stackTrace');

      return errorResult;
    }
  }

  /// Gets cached radar frames if available.
  ///
  /// Returns null if no cache exists or the last fetch failed.
  List<RadarFrame>? getCachedFrames() {
    if (_cachedResult == null || !_cachedResult!.isSuccess) {
      return null;
    }
    return _cachedResult!.frames;
  }

  /// Checks if cached data is stale (older than the refresh interval).
  ///
  /// Parameters:
  /// - [refreshInterval]: Maximum age for cached data to be considered fresh
  ///
  /// Returns true if cache is stale or doesn't exist, false if fresh.
  bool isCacheStale(Duration refreshInterval) {
    if (_lastFetchTime == null) {
      return true;
    }

    final age = DateTime.now().difference(_lastFetchTime!);
    return age >= refreshInterval;
  }

  /// Clears all cached radar data.
  ///
  /// Forces the next [fetchRadarFrames] call to fetch fresh data.
  void clearCache() {
    _cachedResult = null;
    _lastFetchTime = null;
    debugPrint('WeatherRadarService: Cache cleared');
  }

  /// Stream of radar frame updates for reactive UI.
  ///
  /// Emits a new list of frames each time [fetchRadarFrames] completes successfully.
  /// This is a broadcast stream, so multiple listeners are supported.
  Stream<List<RadarFrame>> get framesStream => _framesController.stream;

  /// Disposes all resources used by the service.
  ///
  /// Closes the stream controller and disposes all registered providers.
  /// The service cannot be used after calling dispose.
  void dispose() {
    if (!_framesController.isClosed) {
      _framesController.close();
    }

    if (_initialized) {
      _providerFactory.dispose();
      _initialized = false;
    }

    debugPrint('WeatherRadarService disposed');
  }

  /// Ensures the service has been initialized before use.
  ///
  /// Throws [StateError] if called before [initialize].
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'WeatherRadarService not initialized. Call initialize() first.',
      );
    }
  }

  /// Parses a provider type string from database settings.
  ///
  /// Maps database string values to [RadarProviderType] enum.
  /// Defaults to [RadarProviderType.auto] if the value is unrecognized.
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
        print('Unknown provider type: $providerString, defaulting to auto');
        return RadarProviderType.auto;
    }
  }
}
