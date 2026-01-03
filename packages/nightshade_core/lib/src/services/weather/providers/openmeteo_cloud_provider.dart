import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../models/weather/weather_models.dart';
import '../radar_provider.dart';

/// Open-Meteo API provider for cloud cover percentage data.
///
/// Unlike traditional radar providers, this provides numerical cloud cover
/// percentage data rather than radar imagery. It supplements radar providers
/// with cloud density values used for threshold calculations.
///
/// Uses the free Open-Meteo API (no API key required) to fetch hourly
/// cloud cover percentages with both historical and forecast data.
class OpenMeteoCloudProvider extends RadarProvider {
  /// HTTP client for API requests.
  final http.Client _httpClient;

  /// Base URL for the Open-Meteo forecast API.
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Number of past days to fetch (0-92).
  static const int _pastDays = 1;

  /// Number of forecast days to fetch (1-16).
  static const int _forecastDays = 2;

  /// Creates an Open-Meteo cloud cover provider.
  ///
  /// Optionally accepts a custom [httpClient] for testing.
  OpenMeteoCloudProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get name => 'Open-Meteo Cloud Cover';

  @override
  RadarProviderType get providerType => RadarProviderType.openmeteo;

  @override
  GeoBounds get coverageBounds => const GeoBounds.global();

  @override
  Future<RadarFetchResult> fetchRadarFrames({
    required double latitude,
    required double longitude,
    double radiusKm = 100.0,
  }) async {
    try {
      // Build the API URL
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'hourly': 'cloud_cover',
        'forecast_days': _forecastDays.toString(),
        'past_days': _pastDays.toString(),
      });

      // Fetch data from API
      final response = await _httpClient.get(uri);

      if (response.statusCode != 200) {
        return RadarFetchResult.error(
          'Open-Meteo API returned status ${response.statusCode}',
        );
      }

      // Parse JSON response
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return RadarFetchResult.error('Failed to parse JSON response: $e');
      }

      // Extract hourly data
      final hourly = json['hourly'] as Map<String, dynamic>?;
      if (hourly == null) {
        return RadarFetchResult.error('Missing hourly data in response');
      }

      final timeList = hourly['time'] as List<dynamic>?;
      final cloudCoverList = hourly['cloud_cover'] as List<dynamic>?;

      if (timeList == null || cloudCoverList == null) {
        return RadarFetchResult.error(
          'Missing time or cloud_cover data in response',
        );
      }

      if (timeList.length != cloudCoverList.length) {
        return RadarFetchResult.error(
          'Time and cloud_cover arrays have different lengths',
        );
      }

      // Convert to RadarFrame objects
      final now = DateTime.now();
      final frames = <RadarFrame>[];

      for (int i = 0; i < timeList.length; i++) {
        final timeStr = timeList[i] as String?;
        final cloudCoverValue = cloudCoverList[i];

        if (timeStr == null) {
          continue; // Skip null entries
        }

        // Parse timestamp
        final DateTime timestamp;
        try {
          timestamp = DateTime.parse(timeStr);
        } catch (e) {
          // Skip invalid timestamps
          continue;
        }

        // Parse cloud cover value (can be null for missing data)
        final double cloudCover;
        if (cloudCoverValue == null) {
          continue; // Skip missing data points
        } else if (cloudCoverValue is num) {
          cloudCover = cloudCoverValue.toDouble();
        } else {
          continue; // Skip invalid types
        }

        // Clamp cloud cover to valid range [0, 100]
        final clampedCloudCover = cloudCover.clamp(0.0, 100.0);

        // Convert cloud cover percentage to opacity (0.0-1.0)
        final opacity = clampedCloudCover / 100.0;

        // Determine if this is a forecast frame
        final isForecast = timestamp.isAfter(now);

        // Create point bounds (±0.5 degrees around the requested location)
        final north = latitude + 0.5;
        final south = latitude - 0.5;
        final east = longitude + 0.5;
        final west = longitude - 0.5;

        frames.add(
          RadarFrame(
            timestamp: timestamp,
            tileUrlTemplate: '', // No tiles for this provider
            north: north,
            south: south,
            east: east,
            west: west,
            opacity: opacity,
            isForecast: isForecast,
          ),
        );
      }

      if (frames.isEmpty) {
        return RadarFetchResult.error('No valid cloud cover data available');
      }

      return RadarFetchResult.success(frames);
    } on http.ClientException catch (e) {
      return RadarFetchResult.error('Network error: $e');
    } catch (e) {
      return RadarFetchResult.error('Unexpected error: $e');
    }
  }

  @override
  (Duration history, Duration forecast) getAvailableTimeRange() {
    // Open-Meteo provides 1 day of history and 2 days of forecast
    return (const Duration(hours: 24), const Duration(hours: 48));
  }

  @override
  String buildTileUrl(RadarFrame frame, int z, int x, int y) {
    // This provider doesn't have map tiles - cloud cover is stored as opacity
    return '';
  }

  /// Gets cloud cover percentage at a specific time.
  ///
  /// Finds the closest frame to the requested time and returns the
  /// cloud cover percentage (0-100). Returns null if no data is available
  /// or if the frames list is empty.
  ///
  /// Parameters:
  /// - [time]: The time to query cloud cover for
  /// - [frames]: List of radar frames to search
  ///
  /// Returns the cloud cover percentage or null if unavailable.
  double? getCloudCoverAt(DateTime time, List<RadarFrame> frames) {
    if (frames.isEmpty) {
      return null;
    }

    // Find the frame with the closest timestamp to the requested time
    RadarFrame? closestFrame;
    Duration? minDifference;

    for (final frame in frames) {
      final difference = (frame.timestamp.difference(time)).abs();

      if (minDifference == null || difference < minDifference) {
        minDifference = difference;
        closestFrame = frame;
      }
    }

    if (closestFrame == null) {
      return null;
    }

    // Convert opacity back to percentage (0-100)
    return closestFrame.opacity * 100.0;
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
