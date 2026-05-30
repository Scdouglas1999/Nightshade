import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart' as settings_models;
// `NightshadeEvent` / `EventCategory` / `EventSeverity` /
// `settingsChangedEventType` are re-exported through
// `nightshade_backend.dart` â†’ `backend_types.dart` â†’ `event_types.dart`,
// so the public barrel below is enough.
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for profile and settings endpoints
class ProfileHandlers {
  final ProviderContainer container;

  /// Wave 6B (P2-4) â€” emit `settings.changed` events for each individual
  /// field that differs between the previous and new settings. Injected by
  /// [HeadlessApiServer.start] so the handler can fan events out to every
  /// connected WebSocket client. The callback is `broadcastEvent` on the
  /// server, which stamps `seq` + `serverInstanceId` + correlating
  /// command id before fan-out.
  ///
  /// `null` when the handler is constructed in a unit test or before the
  /// embedded server has hooked up; the broadcast is then a no-op so test
  /// containers that exercise the handler in isolation don't need a
  /// server.
  void Function(NightshadeEvent event)? emitEvent;

  ProfileHandlers(this.container, {this.emitEvent});

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ProfileHandlers');

  // ===========================================================================
  // Profiles
  // ===========================================================================

  Future<Response> handleGetProfiles(Request request) async {
    final backend = container.read(profileSettingsBackendProvider);
    final profiles = await backend.getProfiles();
    return jsonOk({"profiles": profiles.map((p) => p.toJson()).toList()});
  }

  Future<Response> handleSaveProfile(Request request) async {
    _logInfo('[API] POST /api/profiles');
    final payload = await readJsonObject(request);
    final profileJson = requireObject(payload, 'profile');
    final profile = EquipmentProfile.fromJson(profileJson);

    final backend = container.read(profileSettingsBackendProvider);
    await backend.saveProfile(profile);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.updated,
      entityId: profile.id,
      extra: {'name': profile.name},
    );
    return jsonOk({"status": "saved"});
  }

  Future<Response> handleDeleteProfile(
      Request request, String profileId) async {
    _logInfo('[API] DELETE /api/profiles/$profileId');
    final backend = container.read(profileSettingsBackendProvider);
    await backend.deleteProfile(profileId);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.deleted,
      entityId: profileId,
    );
    return jsonOk({"status": "deleted"});
  }

  Future<Response> handleLoadProfile(Request request, String profileId) async {
    _logInfo('[API] POST /api/profiles/$profileId/load');
    final backend = container.read(profileSettingsBackendProvider);
    await backend.loadProfile(profileId);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.loaded,
      entityId: profileId,
    );
    return jsonOk({"status": "loaded"});
  }

  Future<Response> handleGetActiveProfile(Request request) async {
    final backend = container.read(profileSettingsBackendProvider);
    final profile = await backend.getActiveProfile();
    return jsonOk({"profile": profile?.toJson()});
  }

  // ===========================================================================
  // Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    final backend = container.read(profileSettingsBackendProvider);
    final settings = await backend.getSettings();
    return jsonOk({"settings": settings.toJson()});
  }

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/settings');
    // [Wave 6B settings sync] capture the optional commandId from the
    // request header so we can stamp `correlatingCommandId` on every
    // `settings.changed` event emitted below. The originating client
    // uses this to skip its own echo and avoid re-applying a value it
    // just wrote.
    final commandId = request.headers['x-nightshade-command-id'];
    final payload = await readJsonObject(request);
    final settingsJson = requireObject(payload, 'settings');
    final settings = settings_models.AppSettings.fromJson(settingsJson);

    final backend = container.read(profileSettingsBackendProvider);
    // [Wave 6B settings sync] read previous so we can diff against the
    // new state and emit one fine-grained `settings.changed` event per
    // changed field. If the read fails (first-boot / driver hiccup),
    // fall back to a single full-snapshot event so remote clients still
    // see the update.
    settings_models.AppSettings? previous;
    try {
      previous = await backend.getSettings();
    } catch (_, __) {
      // Why: `previous` only feeds an optional change-diff/notification below;
      // if the prior settings can't be read we proceed without the diff
      // rather than failing the update itself.
      previous = null;
    }

    await backend.updateSettings(settings);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.settings,
      action: HostMutationAction.updated,
    );

    // [Wave 6B settings sync] emit live settings-change events so every
    // connected WS client can update its in-memory state without a GET
    // round-trip. The diff is field-by-field on the freezed `AppSettings`
    // JSON projection â€” same JSON the client originally sent, so the
    // keys match what the receiver expects.
    _emitSettingsChanges(
      previous: previous,
      next: settings,
      commandId: commandId,
    );

    return jsonOk({"status": "updated"});
  }

  /// Wave 6B (P2-4) â€” fan out one `settings.changed` event per
  /// changed field between [previous] and [next]. When [previous] is
  /// null, the entire `next` snapshot is emitted as a single event with
  /// key `__snapshot__` so the client can still rehydrate.
  ///
  /// `commandId` is stamped onto `correlatingCommandId` so the
  /// originating client can filter its own echo.
  void _emitSettingsChanges({
    required settings_models.AppSettings? previous,
    required settings_models.AppSettings next,
    required String? commandId,
  }) {
    final emit = emitEvent;
    if (emit == null) return;

    final changedAt = DateTime.now().toUtc().toIso8601String();
    final nowMillis = DateTime.now().millisecondsSinceEpoch;

    NightshadeEvent buildEvent({
      required String key,
      required dynamic value,
    }) {
      return NightshadeEvent(
        timestamp: nowMillis,
        severity: EventSeverity.info,
        category: EventCategory.system,
        eventType: settingsChangedEventType,
        data: {
          'key': key,
          'value': value,
          'changedAt': changedAt,
        },
        correlatingCommandId: commandId,
      );
    }

    if (previous == null) {
      // First-write or recovery path: emit a full snapshot so the
      // remote applies the entire object at once.
      emit(buildEvent(key: '__snapshot__', value: next.toJson()));
      return;
    }

    final prevJson = previous.toJson();
    final nextJson = next.toJson();

    // Union of both key sets covers additions, removals, and overlaps.
    final keys = <String>{...prevJson.keys, ...nextJson.keys};
    for (final key in keys) {
      final prevValue = prevJson[key];
      final nextValue = nextJson[key];
      if (_settingsValueEquals(prevValue, nextValue)) continue;
      emit(buildEvent(key: key, value: nextValue));
    }
  }

  /// Deep-equality helper for settings-diff. `Map` / `List` get a
  /// `jsonEncode` comparison so we don't pull a deep-equality package
  /// in just for this. The values are JSON-shaped (numbers, strings,
  /// bools, lists, maps, null), so encoding is total and correct.
  static bool _settingsValueEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is Map || b is Map || a is List || b is List) {
      return jsonEncode(a) == jsonEncode(b);
    }
    return a == b;
  }

  Future<Response> handleGetLocation(Request request) async {
    final backend = container.read(profileSettingsBackendProvider);
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

    final backend = container.read(profileSettingsBackendProvider);
    await backend.setLocation(location);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.settings,
      action: HostMutationAction.updated,
      extra: {'scope': 'location'},
    );
    return jsonOk({"status": "updated"});
  }

  Future<Response> handleGetLocationFromInternet(Request request) async {
    final backend = container.read(diagnosticsBackendProvider);
    final location = await backend.getLocationFromInternet();
    return jsonOk({
      "latitude": location.latitude,
      "longitude": location.longitude,
      "elevation": location.elevation,
    });
  }
}
