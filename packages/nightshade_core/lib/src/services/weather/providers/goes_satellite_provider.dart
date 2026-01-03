import 'package:http/http.dart' as http;
import '../radar_provider.dart';
import '../../../models/weather/weather_models.dart';

/// GOES satellite infrared imagery provider for cloud cover visualization.
///
/// Uses the Iowa Environmental Mesonet (IEM) WMS service to provide
/// GOES-16/17/18 infrared satellite imagery. Unlike radar which shows
/// precipitation, infrared satellite shows actual cloud cover by detecting
/// cloud top temperatures - clouds appear bright (cold) against dark (warm) ground.
///
/// This provider is ideal for astrophotography applications where you need
/// to see ALL clouds, not just precipitating ones.
///
/// Technical details:
/// - Data source: Iowa State University IEM GOES archive
/// - Update frequency: ~5-15 minutes
/// - Resolution: 4km (CONUS IR)
/// - Coverage: CONUS (lat 14-57, lon -153 to -53)
/// - Works 24/7 (infrared doesn't require sunlight)
class GoesSatelliteProvider extends RadarProvider {
  /// HTTP client for fetching metadata.
  final http.Client _client;

  /// Base URL for the IEM GOES CONUS IR WMS service.
  static const String _baseWmsUrl =
      'https://mesonet.agron.iastate.edu/cgi-bin/wms/goes/conus_ir.cgi?';

  /// Layer name for CONUS infrared imagery.
  static const String _layerName = 'conus_ir_4km';

  /// Coverage area for GOES CONUS: Continental US + margins.
  static const GeoBounds _coverage = GeoBounds(
    north: 56.0, // Northern US/Canada border
    south: 15.0, // Southern Mexico
    east: -53.0, // East Atlantic margin
    west: -152.0, // West Pacific margin (includes Hawaii)
  );

  /// Creates a new GOES satellite provider.
  GoesSatelliteProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get name => 'GOES Satellite';

  @override
  RadarProviderType get providerType => RadarProviderType.goesSatellite;

  @override
  GeoBounds get coverageBounds => _coverage;

  @override
  (Duration, Duration) getAvailableTimeRange() {
    // GOES provides near real-time imagery, no forecast
    // Historical imagery available but we'll just use current
    return (const Duration(hours: 1), Duration.zero);
  }

  @override
  Future<RadarFetchResult> fetchRadarFrames({
    required double latitude,
    required double longitude,
    double radiusKm = 100.0,
  }) async {
    // Verify coverage
    if (!coversLocation(latitude, longitude)) {
      return RadarFetchResult.error(
        'Location ($latitude, $longitude) is outside GOES satellite coverage area',
      );
    }

    try {
      // GOES satellite imagery is essentially real-time with automatic refresh
      // We'll create a single frame representing "now" - the WMS service
      // automatically returns the most recent imagery
      final now = DateTime.now().toUtc();

      // Round to nearest 5 minutes for consistency
      final roundedMinutes = (now.minute ~/ 5) * 5;
      final timestamp = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        roundedMinutes,
      );

      final frame = RadarFrame(
        timestamp: timestamp,
        tileUrlTemplate: _baseWmsUrl,
        north: _coverage.north,
        south: _coverage.south,
        east: _coverage.east,
        west: _coverage.west,
        opacity: 1.0,
        isForecast: false,
        tileType: RadarTileType.wms,
        wmsLayers: _layerName,
        wmsAdditionalOptions: {
          'transparent': 'true',
        },
      );

      print('GoesSatelliteProvider: Built satellite frame for $timestamp');
      print('GoesSatelliteProvider: Layer: $_layerName');

      return RadarFetchResult.success([frame]);
    } on http.ClientException catch (e) {
      return RadarFetchResult.error('Network error fetching GOES satellite: $e');
    } catch (e) {
      return RadarFetchResult.error('Unexpected error fetching GOES satellite: $e');
    }
  }

  @override
  String buildTileUrl(RadarFrame frame, int z, int x, int y) {
    // Calculate Web Mercator bounding box for this tile
    final bbox = _tileToBBox(x, y, z);

    // Build WMS GetMap URL
    final params = {
      'service': 'WMS',
      'version': '1.1.1',
      'request': 'GetMap',
      'layers': frame.wmsLayers ?? _layerName,
      'format': 'image/png',
      'transparent': 'true',
      'srs': 'EPSG:3857',
      'width': '256',
      'height': '256',
      'bbox': '${bbox[0]},${bbox[1]},${bbox[2]},${bbox[3]}',
    };

    final url = Uri.parse(_baseWmsUrl).replace(queryParameters: params);
    return url.toString();
  }

  /// Converts tile coordinates (x, y, z) to Web Mercator bounding box.
  List<double> _tileToBBox(int x, int y, int z) {
    const worldSize = 20037508.342789244;
    final tileSize = (2 * worldSize) / (1 << z);

    final west = -worldSize + (x * tileSize);
    final north = worldSize - (y * tileSize);
    final east = west + tileSize;
    final south = north - tileSize;

    return [west, south, east, north];
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
