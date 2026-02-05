import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class GeolocationService {
  /// Fetch location from IP using ipapi.co (free, no API key required)
  /// Returns (latitude, longitude, locationName) or null if failed
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocationFromIP() async {
    try {
      // Use ipapi.co for free IP geolocation (no API key required)
      final response = await http.get(
        Uri.parse('https://ipapi.co/json/'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        final lat = data['latitude'] as double?;
        final lon = data['longitude'] as double?;
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
      debugPrint('[Geolocation] IP-based location failed: $e');
    }
    
    return null;
  }
  
  /// Alternative: Use ip-api.com (also free, no API key)
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocationFromIPAlternative() async {
    try {
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data['status'] == 'success') {
          final lat = data['lat'] as double?;
          final lon = data['lon'] as double?;
          final city = data['city'] as String?;
          final region = data['regionName'] as String?;
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
      debugPrint('[Geolocation] Alternative IP-based location failed: $e');
    }
    
    return null;
  }
  
  /// Try to fetch location, using primary service first, then fallback
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocation() async {
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
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocationFromGPS() async {
    try {
      // Check if location services are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[Geolocation] Location services are disabled on device');
        // Fallback to IP-based location
        return await fetchLocation();
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[Geolocation] Location permission denied by user');
          // Fallback to IP-based location
          return await fetchLocation();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[Geolocation] Location permissions are permanently denied');
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
        // For now, we'll use coordinates only. If needed, integrate
        // geocoding package or use a reverse geocoding API
        locationName = 'GPS: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      } catch (e) {
        // Geocoding failed, use simple coordinates
        locationName = 'GPS Location';
      }

      return (
        position.latitude,
        position.longitude,
        locationName,
      );

    } catch (e) {
      // GPS failed (timeout, no GPS hardware, etc.)
      debugPrint('[Geolocation] GPS location fetch failed: $e');

      // Fallback to IP-based location
      return await fetchLocation();
    }
  }

  /// Get the best available location using GPS first, then IP fallback
  /// This is the recommended method for most use cases
  static Future<(double latitude, double longitude, String? locationName)?> getBestLocation() async {
    // Try GPS first (will auto-fallback to IP if GPS unavailable)
    return await fetchLocationFromGPS();
  }
}



