import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';

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

  /// Fetch location from IP using ipapi.co (free, no API key required)
  /// Returns (latitude, longitude, locationName) or null if failed
  static Future<(double latitude, double longitude, String? locationName)?>
  fetchLocationFromIP() async {
    final client = clientFactory();
    try {
      // Use ipapi.co for free IP geolocation (no API key required)
      final response = await client
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        final lat = _coord(data['latitude']);
        final lon = _coord(data['longitude']);
        final city = data['city'] as String?;
        final region = data['region'] as String?;
        final country = data['country_name'] as String?;

        if (lat != null && lon != null) {
          // Build location name
          String? locationName;
          if (city != null || region != null || country != null) {
            final parts = <String>[];
            if (city != null) parts.add(city);
            if (region != null) parts.add(region);
            if (country != null) parts.add(country);
            locationName = parts.join(', ');
          }

          return (lat, lon, locationName);
        }
      }
    } catch (e) {
      // Silently fail - network might be unavailable
      developer.log(
        '[Geolocation] IP-based location failed: $e',
        name: 'GeolocationService',
        level: 900,
        error: e,
      );
    } finally {
      client.close();
    }

    return null;
  }

  /// Fallback for when the primary service is unreachable or rate-limited
  /// (ipapi.co answers `{"error":true,"reason":"RateLimited"}` with HTTP 200,
  /// which parses to a null coordinate and lands here).
  /// The fallback must remain HTTPS because its coordinates become the active
  /// observing site.
  static Future<(double latitude, double longitude, String? locationName)?>
  fetchLocationFromIPAlternative() async {
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true) {
          final lat = _coord(data['latitude']);
          final lon = _coord(data['longitude']);
          final city = data['city'] as String?;
          final region = data['region'] as String?;
          final country = data['country'] as String?;

          if (lat != null && lon != null) {
            String? locationName;
            if (city != null || region != null || country != null) {
              final parts = <String>[];
              if (city != null) parts.add(city);
              if (region != null) parts.add(region);
              if (country != null) parts.add(country);
              locationName = parts.join(', ');
            }

            return (lat, lon, locationName);
          }
        }
      }
    } catch (e) {
      developer.log(
        '[Geolocation] Alternative IP-based location failed: $e',
        name: 'GeolocationService',
        level: 900,
        error: e,
      );
    } finally {
      client.close();
    }

    return null;
  }

  /// Try to fetch location, using primary service first, then fallback
  static Future<(double latitude, double longitude, String? locationName)?>
  fetchLocation() async {
    // Try primary service first
    final result = await fetchLocationFromIP();
    if (result != null) return result;

    // Try alternative service
    return await fetchLocationFromIPAlternative();
  }

  /// Fetch location from device GPS
  /// Returns (latitude, longitude, locationName) or null if GPS unavailable or permission denied
  ///
  /// This method handles:
  /// - Location service availability check
  /// - Permission requests (will prompt user if needed)
  /// - GPS position acquisition
  /// - Graceful fallback to IP-based location if GPS fails
  ///
  /// Platform support:
  /// - Mobile (iOS/Android): Uses device GPS
  /// - Desktop (Windows/macOS/Linux): May not have GPS hardware, will fallback to IP
  static Future<(double latitude, double longitude, String? locationName)?>
  fetchLocationFromGPS() async {
    try {
      // Check if location services are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        developer.log(
          '[Geolocation] Location services are disabled on device',
          name: 'GeolocationService',
          level: 900,
        );
        // Fallback to IP-based location
        return await fetchLocation();
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
          // Fallback to IP-based location
          return await fetchLocation();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        developer.log(
          '[Geolocation] Location permissions are permanently denied',
          name: 'GeolocationService',
          level: 900,
        );
        // Fallback to IP-based location
        return await fetchLocation();
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

      // Fallback to IP-based location
      return await fetchLocation();
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
