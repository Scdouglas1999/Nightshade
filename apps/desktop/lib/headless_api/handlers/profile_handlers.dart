import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart' as settings_models;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for profile and settings endpoints
class ProfileHandlers {
  final ProviderContainer container;

  ProfileHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ProfileHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'ProfileHandlers');

  // ===========================================================================
  // Profiles
  // ===========================================================================

  Future<Response> handleGetProfiles(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final profiles = await backend.getProfiles();
      return jsonOk({"profiles": profiles.map((p) => p.toJson()).toList()});
    } catch (e) {
      _logError('[API] Get profiles error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSaveProfile(Request request) async {
    _logInfo('[API] POST /api/profiles');
    try {
      final payload = jsonDecode(await request.readAsString());
      final profileJson = payload['profile'] as Map<String, dynamic>;
      final profile = EquipmentProfile.fromJson(profileJson);

      final backend = container.read(backendProvider);
      await backend.saveProfile(profile);
      return jsonOk({"status": "saved"});
    } catch (e) {
      _logError('[API] Save profile error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleDeleteProfile(
      Request request, String profileId) async {
    _logInfo('[API] DELETE /api/profiles/$profileId');
    try {
      final backend = container.read(backendProvider);
      await backend.deleteProfile(profileId);
      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete profile error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleLoadProfile(Request request, String profileId) async {
    _logInfo('[API] POST /api/profiles/$profileId/load');
    try {
      final backend = container.read(backendProvider);
      await backend.loadProfile(profileId);
      return jsonOk({"status": "loaded"});
    } catch (e) {
      _logError('[API] Load profile error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGetActiveProfile(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final profile = await backend.getActiveProfile();
      return jsonOk({"profile": profile?.toJson()});
    } catch (e) {
      _logError('[API] Get active profile error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final settings = await backend.getSettings();
      return jsonOk({"settings": settings.toJson()});
    } catch (e) {
      _logError('[API] Get settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/settings');
    try {
      final payload = jsonDecode(await request.readAsString());
      final settingsJson = payload['settings'] as Map<String, dynamic>;
      final settings = settings_models.AppSettings.fromJson(settingsJson);

      final backend = container.read(backendProvider);
      await backend.updateSettings(settings);
      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGetLocation(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final location = await backend.getLocation();
      return jsonOk({"location": location?.toJson()});
    } catch (e) {
      _logError('[API] Get location error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleSetLocation(Request request) async {
    _logInfo('[API] POST /api/settings/location');
    try {
      final payload = jsonDecode(await request.readAsString());
      final locationJson = payload['location'] as Map<String, dynamic>?;
      final location = locationJson != null
          ? settings_models.ObserverLocation.fromJson(locationJson)
          : null;

      final backend = container.read(backendProvider);
      await backend.setLocation(location);
      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Set location error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGetLocationFromInternet(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final location = await backend.getLocationFromInternet();
      return jsonOk({
        "latitude": location.latitude,
        "longitude": location.longitude,
        "elevation": location.elevation,
      });
    } catch (e) {
      _logError('[API] Get location from internet error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }
}
