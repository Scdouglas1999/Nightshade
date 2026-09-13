import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';

/// A named place from the geocoding lookup. Town-accurate, with elevation
/// when the service has a DEM sample — unlike an IP estimate, which is a
/// ZIP or city centroid with elevation 0.
class PlaceSearchHit {
  const PlaceSearchHit({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.elevation,
  });

  final double latitude;
  final double longitude;
  final double? elevation;
  final String label;
}

class GeolocationService {
  /// Client used for the IP-geolocation lookups. Injectable so a test can
  /// assert what actually goes on the wire — the transport of these requests
  /// is the point (see [fetchLocationFromIPAlternative]), and a hard-coded
  /// `http.get` cannot be inspected.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// Read a JSON coordinate that may arrive as an int (a whole-degree
  /// latitude serialises as `40`, not `40.0`). A bare `as double?` throws on
  /// that, and every call site here swallows the throw — so the lookup would
  /// silently report "no location" for anyone who happens to sit on a round
  /// degree.
  static double? _coord(Object? value) => (value as num?)?.toDouble();

  /// Primary IP lookup. ipinfo.io's `loc` is typically ZIP-level for US
  /// residential IPs; city-centroid services pin a metro ISP to city hall,
  /// which is where Weather then draws the observatory.
  static final Uri ipPrimaryEndpoint = Uri.parse('https://ipinfo.io/json');

  /// TLS fallback when the primary is unreachable or has no coordinate.
  static final Uri ipFallbackEndpoint = Uri.parse('https://ipwho.is/');

  /// Open-Meteo geocoding. Same vendor as the cloud forecast, TLS, no key.
  static final Uri placeSearchEndpoint =
      Uri.parse('https://geocoding-api.open-meteo.com/v1/search');

  /// Fetch location from IP using ipinfo.io (free, no API key required).
  /// Returns (latitude, longitude, locationName) or null if failed.
  static Future<(double latitude, double longitude, String? locationName)?>
      fetchLocationFromIP() => _fetchIp(ipPrimaryEndpoint);

  /// Fallback for when the primary service is unreachable or rate-limited.
  /// The fallback must remain HTTPS because its coordinates become the active
  /// observing site.
  static Future<(double latitude, double longitude, String? locationName)?>
      fetchLocationFromIPAlternative() => _fetchIp(ipFallbackEndpoint);

  static Future<(double latitude, double longitude, String? locationName)?>
      _fetchIp(Uri uri) async {
    final client = clientFactory();
    try {
      final response =
          await client.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      return _parseIpBody(response.body);
    } catch (e) {
      developer.log(
        '[Geolocation] IP-based location failed (${uri.host}): $e',
        name: 'GeolocationService',
        level: 900,
        error: e,
      );
    } finally {
      client.close();
    }
    return null;
  }

  /// ipinfo.io uses `loc` ("lat,lon"); ipwho.is / ipapi.co use
  /// `latitude`/`longitude`. Prefer `loc` when both exist — that is the
  /// ZIP-level fix. Round to four decimals so a seven-decimal city-centroid
  /// reply cannot look surveyed.
  static (double, double, String?)? _parseIpBody(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['success'] == false || decoded['error'] == true) return null;
    if (decoded['error'] is Map) return null;

    double? lat;
    double? lon;
    final loc = decoded['loc'];
    if (loc is String) {
      final parts = loc.split(',');
      if (parts.length >= 2) {
        lat = double.tryParse(parts[0].trim());
        lon = double.tryParse(parts[1].trim());
      }
    }
    lat ??= _coord(decoded['latitude']);
    lon ??= _coord(decoded['longitude']);
    if (lat == null || lon == null) return null;

    return (
      double.parse(lat.toStringAsFixed(4)),
      double.parse(lon.toStringAsFixed(4)),
      _ipLocationName(decoded),
    );
  }

  /// City + region, plus a country name when the service sent one. Skip a
  /// two-letter ISO code so ipinfo's `"country":"US"` does not become the
  /// label "Broomall, Pennsylvania, US".
  static String? _ipLocationName(Map<String, dynamic> data) {
    final city = data['city'] as String?;
    final region = data['region'] as String?;
    final country = (data['country_name'] as String?) ??
        data['country'] as String?;
    final parts = <String>[
      if (city != null && city.isNotEmpty) city,
      if (region != null && region.isNotEmpty) region,
      if (country != null && country.length > 2) country,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Try to fetch location, using primary service first, then fallback
  static Future<(double latitude, double longitude, String? locationName)?>
      fetchLocation() async {
    final result = await fetchLocationFromIP();
    if (result != null) return result;
    return fetchLocationFromIPAlternative();
  }

  /// Look up a town, observatory, or address by name.
  ///
  /// This is the accurate desktop path: a wired observatory PC has no GPS and
  /// its public IP geolocates to the ISP's city, often a town over. The
  /// operator types the place they actually observe from.
  static Future<List<PlaceSearchHit>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = placeSearchEndpoint.replace(
      queryParameters: <String, String>{
        'name': trimmed,
        'count': '6',
        'language': 'en',
        'format': 'json',
      },
    );
    final client = clientFactory();
    try {
      final response = await client.get(
        uri,
        headers: const {'User-Agent': 'Nightshade/observatory'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      return parsePlaceSearchBody(response.body);
    } catch (e) {
      developer.log(
        '[Geolocation] Place search failed: $e',
        name: 'GeolocationService',
        level: 900,
        error: e,
      );
      return const [];
    } finally {
      client.close();
    }
  }

  /// Parse an Open-Meteo geocoding body. Public so a test can pin the
  /// coordinate + elevation extraction without a socket.
  @visibleForTesting
  static List<PlaceSearchHit> parsePlaceSearchBody(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];

    final hits = <PlaceSearchHit>[];
    for (final raw in results) {
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final lat = _coord(data['latitude']);
      final lon = _coord(data['longitude']);
      if (lat == null || lon == null) continue;
      final name = data['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final admin1 = data['admin1'] as String?;
      final country = data['country'] as String?;
      final parts = <String>[
        name,
        if (admin1 != null && admin1.isNotEmpty) admin1,
        if (country != null && country.isNotEmpty) country,
      ];
      hits.add(
        PlaceSearchHit(
          latitude: double.parse(lat.toStringAsFixed(4)),
          longitude: double.parse(lon.toStringAsFixed(4)),
          elevation: _coord(data['elevation']),
          label: parts.join(', '),
        ),
      );
    }
    return hits;
  }

  /// Fetch location from device GPS.
  ///
  /// [fallbackToIp] is the desktop escape hatch: most observatory PCs have no
  /// GPS, and the IP estimate is a town-level guess. Settings and the
  /// onboarding "use my location" control pass false so an ISP city cannot
  /// overwrite a site the operator named. The onboarding "Estimate from IP"
  /// button still calls [fetchLocation] directly.
  static Future<(double latitude, double longitude, String? locationName)?>
      fetchLocationFromGPS({bool fallbackToIp = true}) async {
    try {
      // Check if location services are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log(
          '[Geolocation] Location services are disabled on device',
          name: 'GeolocationService',
          level: 900,
        );
        return fallbackToIp ? await fetchLocation() : null;
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          developer.log(
            '[Geolocation] Location permission denied by user',
            name: 'GeolocationService',
            level: 900,
          );
          return fallbackToIp ? await fetchLocation() : null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        developer.log(
          '[Geolocation] Location permissions are permanently denied',
          name: 'GeolocationService',
          level: 900,
        );
        return fallbackToIp ? await fetchLocation() : null;
      }

      // Get current position
      // Use best accuracy for precise astronomical positioning
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Get location name from reverse geocoding if available
      String? locationName;
      try {
        // Note: Reverse geocoding requires platform-specific setup
        // Use coordinates only. Integrate reverse geocoding when platform support is enabled
        // geocoding package or use a reverse geocoding API
        locationName =
            'GPS: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      } catch (e) {
        // Geocoding failed, use simple coordinates
        locationName = 'GPS Location';
      }

      return (position.latitude, position.longitude, locationName);
    } catch (e) {
      // GPS failed (timeout, no GPS hardware, etc.)
      developer.log(
        '[Geolocation] GPS location fetch failed: $e',
        name: 'GeolocationService',
        level: 900,
        error: e,
      );

      return fallbackToIp ? await fetchLocation() : null;
    }
  }

  /// Get the best available location using GPS first, then IP fallback
  /// This is the recommended method for most use cases
  static Future<(double latitude, double longitude, String? locationName)?>
  getBestLocation() async {
    // Try GPS first (will auto-fallback to IP if GPS unavailable)
    return await fetchLocationFromGPS();
  }
}
