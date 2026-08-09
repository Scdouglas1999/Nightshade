import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../models/errors/nightshade_error.dart';
import '../providers/settings_provider.dart' show LocationSettings;

/// Resolve an approximate observing site from the machine's public IP.
///
/// One owner for the "ask the internet where we are" request, because there
/// were two, and both of them used cleartext `http://ip-api.com/json`:
/// this one (the FfiBackend, which is what the headless appliance answers
/// `GET /api/location` with) and the desktop GUI's `GeolocationService`
/// fallback. ip-api.com's free tier answers 403 over HTTPS, so the request was
/// unencrypted by construction. The answer is not advisory — it is written into
/// `observer_latitude`/`observer_longitude`, which drive altitude/airmass,
/// meridian-flip timing and the horizon mask — so anyone on the path could
/// both read the observer's public IP and choose where the rig thinks it is.
///
/// The second rule here is that an unusable answer is an error, never a
/// coordinate. The old parser returned `0.0` for a missing `lat`/`lon`, so a
/// rate-limited or rewritten reply silently produced Null Island: a real place
/// in the Gulf of Guinea, where every target is up at the wrong time.
class IpGeolocation {
  /// Free, no-key, TLS-only IP geolocation. Same shape of service as the
  /// cleartext one it replaces (`latitude` / `longitude` / `success`).
  static final Uri endpoint = Uri.parse('https://ipwho.is/');

  /// Client factory, injectable so a test can assert what goes on the wire.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// Fetch the estimate. Throws a [NightshadeError] when the service is
  /// unreachable, refuses, or answers without a usable coordinate.
  static Future<LocationSettings> fetch() async {
    final client = clientFactory();
    final http.Response response;
    try {
      response = await client
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
    } on NightshadeError {
      rethrow;
    } catch (e) {
      throw NightshadeError(
        category: BackendErrorCategory.io,
        message: 'Error fetching location: $e',
        userMessage:
            'Could not reach the location service at ${endpoint.host}.',
        isRecoverable: true,
      );
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      throw NightshadeError(
        category: BackendErrorCategory.io,
        message: 'Failed to fetch location: HTTP ${response.statusCode}',
        userMessage:
            'The location service at ${endpoint.host} returned '
            'HTTP ${response.statusCode}.',
        isRecoverable: true,
      );
    }
    return parse(response.body);
  }

  /// Parse a response body into a site. Separate from [fetch] so the refusal
  /// rules are testable without a socket.
  @visibleForTesting
  static LocationSettings parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      throw NightshadeError(
        category: BackendErrorCategory.io,
        message: 'Location service returned a body that is not JSON: $e',
        userMessage: 'The location service returned an unreadable answer.',
        isRecoverable: true,
      );
    }
    final data = decoded is Map<String, dynamic> ? decoded : null;
    // Read the coordinates as `num`: a whole-degree latitude serialises as
    // `40`, not `40.0`, and a `double` cast would throw on it.
    final lat = data == null ? null : (data['latitude'] as num?)?.toDouble();
    final lon = data == null ? null : (data['longitude'] as num?)?.toDouble();
    if (data == null ||
        data['success'] == false ||
        lat == null ||
        lon == null ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw NightshadeError(
        category: BackendErrorCategory.io,
        message:
            'Location service did not return a usable coordinate '
            '(${data?['message'] ?? body.trim()})',
        userMessage:
            'The location service could not estimate this machine\'s '
            'position. Enter the site coordinates manually.',
        isRecoverable: true,
      );
    }
    // Elevation is deliberately 0: neither IP service reports one, and
    // inventing the previous site's elevation is how a Pennsylvania fix ended
    // up 1234 m above sea level.
    return LocationSettings(latitude: lat, longitude: lon, elevation: 0.0);
  }
}
