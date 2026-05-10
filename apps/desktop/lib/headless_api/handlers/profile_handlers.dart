import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart' as settings_models;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for profile and settings endpoints
class ProfileHandlers {
  final ProviderContainer container;

  ProfileHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ProfileHandlers');

  // ===========================================================================
  // Profiles
  // ===========================================================================

  Future<Response> handleGetProfiles(Request request) async {
    final backend = container.read(backendProvider);
    final profiles = await backend.getProfiles();
    return jsonOk({"profiles": profiles.map((p) => p.toJson()).toList()});
  }

  Future<Response> handleSaveProfile(Request request) async {
    _logInfo('[API] POST /api/profiles');
    final payload = await readJsonObject(request);
    final profileJson = requireObject(payload, 'profile');
    final profile = EquipmentProfile.fromJson(profileJson);

    final backend = container.read(backendProvider);
    await backend.saveProfile(profile);
    return jsonOk({"status": "saved"});
  }

  Future<Response> handleDeleteProfile(
      Request request, String profileId) async {
    _logInfo('[API] DELETE /api/profiles/$profileId');
    final backend = container.read(backendProvider);
    await backend.deleteProfile(profileId);
    return jsonOk({"status": "deleted"});
  }

  Future<Response> handleLoadProfile(Request request, String profileId) async {
    _logInfo('[API] POST /api/profiles/$profileId/load');
    final backend = container.read(backendProvider);
    await backend.loadProfile(profileId);
    return jsonOk({"status": "loaded"});
  }

  Future<Response> handleGetActiveProfile(Request request) async {
    final backend = container.read(backendProvider);
    final profile = await backend.getActiveProfile();
    return jsonOk({"profile": profile?.toJson()});
  }

  // ===========================================================================
  // Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    final backend = container.read(backendProvider);
    final settings = await backend.getSettings();
    return jsonOk({"settings": settings.toJson()});
  }

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/settings');
    final payload = await readJsonObject(request);
    final settingsJson = requireObject(payload, 'settings');
    final settings = settings_models.AppSettings.fromJson(settingsJson);

    final backend = container.read(backendProvider);
    await backend.updateSettings(settings);
    return jsonOk({"status": "updated"});
  }

  Future<Response> handleGetLocation(Request request) async {
    final backend = container.read(backendProvider);
    final location = await backend.getLocation();
    return jsonOk({"location": location?.toJson()});
  }

  Future<Response> handleSetLocation(Request request) async {
    _logInfo('[API] POST /api/settings/location');
    final payload = await readJsonObject(request);
    final locationJson = optionalObject(payload, 'location');
    final location = locationJson != null
        ? settings_models.ObserverLocation.fromJson(locationJson)
        : null;

    final backend = container.read(backendProvider);
    await backend.setLocation(location);
    return jsonOk({"status": "updated"});
  }

  Future<Response> handleGetLocationFromInternet(Request request) async {
    final backend = container.read(backendProvider);
    final location = await backend.getLocationFromInternet();
    return jsonOk({
      "latitude": location.latitude,
      "longitude": location.longitude,
      "elevation": location.elevation,
    });
  }
}
