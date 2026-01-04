import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart' as settings_models;
import 'package:shelf/shelf.dart';

/// Handlers for profile and settings endpoints
class ProfileHandlers {
  final ProviderContainer container;

  ProfileHandlers(this.container);

  // ===========================================================================
  // Profiles
  // ===========================================================================

  Future<Response> handleGetProfiles(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final profiles = await backend.getProfiles();
      return Response.ok(
        jsonEncode({"profiles": profiles.map((p) => p.toJson()).toList()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get profiles error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSaveProfile(Request request) async {
    print('[API] POST /api/profiles');
    try {
      final payload = jsonDecode(await request.readAsString());
      final profileJson = payload['profile'] as Map<String, dynamic>;
      final profile = EquipmentProfile.fromJson(profileJson);

      final backend = container.read(backendProvider);
      await backend.saveProfile(profile);
      return Response.ok(
        jsonEncode({"status": "saved"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Save profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleDeleteProfile(Request request, String profileId) async {
    print('[API] DELETE /api/profiles/$profileId');
    try {
      final backend = container.read(backendProvider);
      await backend.deleteProfile(profileId);
      return Response.ok(
        jsonEncode({"status": "deleted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Delete profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleLoadProfile(Request request, String profileId) async {
    print('[API] POST /api/profiles/$profileId/load');
    try {
      final backend = container.read(backendProvider);
      await backend.loadProfile(profileId);
      return Response.ok(
        jsonEncode({"status": "loaded"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Load profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetActiveProfile(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final profile = await backend.getActiveProfile();
      return Response.ok(
        jsonEncode({"profile": profile?.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get active profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final settings = await backend.getSettings();
      return Response.ok(
        jsonEncode({"settings": settings.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleUpdateSettings(Request request) async {
    print('[API] POST /api/settings');
    try {
      final payload = jsonDecode(await request.readAsString());
      final settingsJson = payload['settings'] as Map<String, dynamic>;
      final settings = settings_models.AppSettings.fromJson(settingsJson);

      final backend = container.read(backendProvider);
      await backend.updateSettings(settings);
      return Response.ok(
        jsonEncode({"status": "updated"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Update settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetLocation(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final location = await backend.getLocation();
      return Response.ok(
        jsonEncode({"location": location?.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get location error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSetLocation(Request request) async {
    print('[API] POST /api/settings/location');
    try {
      final payload = jsonDecode(await request.readAsString());
      final locationJson = payload['location'] as Map<String, dynamic>?;
      final location = locationJson != null
          ? settings_models.ObserverLocation.fromJson(locationJson)
          : null;

      final backend = container.read(backendProvider);
      await backend.setLocation(location);
      return Response.ok(
        jsonEncode({"status": "updated"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Set location error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetLocationFromInternet(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final location = await backend.getLocationFromInternet();
      return Response.ok(
        jsonEncode({
          "latitude": location.latitude,
          "longitude": location.longitude,
          "elevation": location.elevation,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get location from internet error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
