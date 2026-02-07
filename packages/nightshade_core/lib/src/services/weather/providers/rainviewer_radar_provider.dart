import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../../models/weather/weather_models.dart';
import '../radar_provider.dart';

/// Radar provider implementation using the RainViewer global radar service.
///
/// RainViewer provides free global radar coverage without requiring an API key.
/// The service aggregates radar data from multiple sources worldwide.
///
/// API Documentation: https://www.rainviewer.com/api.html
///
/// Coverage: Global (entire world)
/// Update Frequency: Every 10 minutes
/// History: ~2 hours of past data
/// Forecast: ~30 minutes of nowcast data
class RainViewerRadarProvider extends RadarProvider {
  /// API endpoint for fetching radar data metadata.
  static const String _apiUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  /// HTTP client for making API requests.
  final http.Client _httpClient;

  /// Creates a new RainViewer radar provider instance.
  ///
  /// Optionally accepts a custom [httpClient] for testing purposes.
  RainViewerRadarProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get name => 'RainViewer';

  @override
  RadarProviderType get providerType => RadarProviderType.rainviewer;

  @override
  GeoBounds get coverageBounds => const GeoBounds.global();

  @override
  Future<RadarFetchResult> fetchRadarFrames({
    required double latitude,
    required double longitude,
    double radiusKm = 100.0,
  }) async {
    developer.log('Fetching radar frames for ($latitude, $longitude)',
        name: 'RainViewer', level: 800);
    try {
      // Fetch the radar metadata from RainViewer API
      final response = await _httpClient.get(Uri.parse(_apiUrl));

      if (response.statusCode != 200) {
        return RadarFetchResult.error(
          'RainViewer API returned status ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      // Parse JSON response
      final Map<String, dynamic> data;
      try {
        data = json.decode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return RadarFetchResult.error(
          'Failed to parse RainViewer API response: $e',
        );
      }

      // Extract host URL and radar data
      final String host = data['host'] as String? ?? '';

      final Map<String, dynamic>? radarData =
          data['radar'] as Map<String, dynamic>?;

      if (radarData == null) {
        return RadarFetchResult.error(
          'RainViewer API response missing radar data',
        );
      }

      // Build list of radar frames
      final List<RadarFrame> frames = [];

      // Add historical frames (past radar data)
      final List<dynamic>? pastFrames = radarData['past'] as List<dynamic>?;
      if (pastFrames != null) {
        for (final frameData in pastFrames) {
          if (frameData is! Map<String, dynamic>) continue;

          final int? timestamp = frameData['time'] as int?;
          final String? path = frameData['path'] as String?;

          if (timestamp != null && path != null) {
            final tileUrl = _buildFrameTileUrl(host, path);
            frames.add(
              RadarFrame(
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
                tileUrlTemplate: tileUrl,
                north: 90.0,
                south: -90.0,
                east: 180.0,
                west: -180.0,
                opacity: 1.0,
                isForecast: false,
              ),
            );
          }
        }
      }

      // Add nowcast frames (forecast radar data)
      final List<dynamic>? nowcastFrames =
          radarData['nowcast'] as List<dynamic>?;
      if (nowcastFrames != null) {
        for (final frameData in nowcastFrames) {
          if (frameData is! Map<String, dynamic>) continue;

          final int? timestamp = frameData['time'] as int?;
          final String? path = frameData['path'] as String?;

          if (timestamp != null && path != null) {
            final tileUrl = _buildFrameTileUrl(host, path);
            frames.add(
              RadarFrame(
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
                tileUrlTemplate: tileUrl,
                north: 90.0,
                south: -90.0,
                east: 180.0,
                west: -180.0,
                opacity: 0.85, // Slightly lower opacity for forecast
                isForecast: true,
              ),
            );
          }
        }
      }

      // Check if we got any frames
      if (frames.isEmpty) {
        developer.log('No frames returned from API',
            name: 'RainViewer', level: 900);
        return RadarFetchResult.error(
          'RainViewer API returned no radar frames',
        );
      }

      // Sort frames by timestamp
      frames.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      developer.log('Parsed ${frames.length} frames from host: $host',
          name: 'RainViewer', level: 800);
      return RadarFetchResult.success(frames);
    } on http.ClientException catch (e) {
      return RadarFetchResult.error(
        'Network error fetching RainViewer data: $e',
      );
    } catch (e) {
      return RadarFetchResult.error(
        'Unexpected error fetching RainViewer data: $e',
      );
    }
  }

  @override
  (Duration history, Duration forecast) getAvailableTimeRange() {
    // RainViewer typically provides:
    // - 2 hours of historical radar data
    // - 30 minutes of nowcast (forecast) data
    return (
      const Duration(hours: 2),
      const Duration(minutes: 30),
    );
  }

  @override
  String buildTileUrl(RadarFrame frame, int z, int x, int y) {
    // Replace tokens in the tile URL template
    // Template format: "https://tilecache.rainviewer.com/v2/radar/1234567890/256/{z}/{x}/{y}/2/1_1.png"
    return frame.tileUrlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }

  String _buildFrameTileUrl(String host, String path) {
    final normalizedHost =
        host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // RainViewer generally returns a full tile template in `path`.
    if (normalizedPath.contains('{z}') &&
        normalizedPath.contains('{x}') &&
        normalizedPath.contains('{y}')) {
      return '$normalizedHost$normalizedPath';
    }

    return '$normalizedHost$normalizedPath/256/{z}/{x}/{y}/2/1_1.png';
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
