import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart' as settings_models;
// `NightshadeEvent` / `EventCategory` / `EventSeverity` /
// `settingsChangedEventType` are re-exported through
// `nightshade_backend.dart` → `backend_types.dart` → `event_types.dart`,
// so the public barrel below is enough.
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for profile and settings endpoints
class ProfileHandlers {
  final ProviderContainer container;

  /// Emit `settings.changed` events for each individual
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

  EquipmentProfilesDao get _profilesDao =>
      container.read(equipmentProfilesDaoProvider);

  Future<Response> handleGetProfiles(Request request) async {
    // SQLite (Drift) is the single source of truth shared with the GUI. Map the
    // real DB rows to the REST wire model via the canonical converter so the
    // slave sees the profiles the user actually built (incl.
    // meridianFlipOverrides / safetyMonitorId / switchId).
    final rows = await _profilesDao.getAllProfiles();
    final profiles = rows.map(dbProfileToRemote).toList();
    return jsonOk({"profiles": profiles.map((p) => p.toJson()).toList()});
  }

  Future<Response> handleSaveProfile(Request request) async {
    _logInfo('[API] POST /api/profiles');
    final payload = await readJsonObject(request);
    final profileJson = requireObject(payload, 'profile');
    final profile = EquipmentProfile.fromJson(profileJson);

    final dao = _profilesDao;
    // Deterministic create-vs-update by id. If the payload's id parses to an
    // EXISTING row, issue a full-row update (preserving default/active/sort
    // flags via the converter's `existing` arg); otherwise create a new row and
    // capture the autoincrement id. Going through updateProfile (not
    // createProfile) for an existing row avoids createProfile's first-row
    // auto-default/auto-active side effect silently flipping a slave's flags.
    final parsedId = int.tryParse(profile.id);
    final existing = parsedId == null
        ? null
        : await dao.getProfileById(parsedId);

    final int resultId;
    if (existing != null) {
      final row = remoteProfileToDbRow(profile, existing: existing);
      await dao.updateProfile(row);
      resultId = existing.id;
    } else {
      resultId = await dao.createProfile(remoteProfileToCompanion(profile));
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.updated,
      entityId: resultId.toString(),
      extra: {'name': profile.name},
    );
    // Return the resulting id so the slave's saveProfile can resolve the row
    // deterministically instead of by (racy) name.
    return jsonOk({"status": "saved", "id": resultId.toString()});
  }

  Future<Response> handleDeleteProfile(
    Request request,
    String profileId,
  ) async {
    _logInfo('[API] DELETE /api/profiles/$profileId');
    final parsedId = int.tryParse(profileId);
    if (parsedId != null) {
      await _profilesDao.deleteProfile(parsedId);
    }
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
    final parsedId = int.tryParse(profileId);
    if (parsedId != null) {
      await _profilesDao.setActiveProfile(parsedId);
      // Write-through to the native (Rust) store: SQLite owns reads, but the
      // Rust executor still resolves the active profile from its own store via
      // load_and_set_profile. Push the now-active profile so headless
      // sequencing keeps a correct active-profile context.
      await _writeActiveProfileThroughToRust(parsedId);
    }
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.loaded,
      entityId: profileId,
    );
    return jsonOk({"status": "loaded"});
  }

  /// Set [profileId] as the default startup profile (and active profile),
  /// atomically unsetting `isDefault` on every other row.
  ///
  /// The canonical converter's `remoteProfileToDbRow` deliberately preserves
  /// `existing.isDefault`, so a slave's saveProfile loop could never flip the
  /// default on the host. This dedicated endpoint routes through the DAO's
  /// `setDefaultProfile`, which owns the unset-others-then-set transaction.
  Future<Response> handleSetDefaultProfile(
    Request request,
    String profileId,
  ) async {
    _logInfo('[API] POST /api/profiles/$profileId/default');
    final parsedId = int.tryParse(profileId);
    if (parsedId != null) {
      await _profilesDao.setDefaultProfile(parsedId, makeActive: true);
      // Keep the native (Rust) executor's active-profile context aligned,
      // exactly like handleLoadProfile — setDefaultProfile(makeActive:true)
      // also makes the row active.
      await _writeActiveProfileThroughToRust(parsedId);
    }
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.updated,
      entityId: profileId,
    );
    return jsonOk({"status": "default-set"});
  }

  /// Clear the persisted default startup profile (unset `isDefault` on every
  /// row) without changing the current active selection.
  ///
  /// The generic saveProfile path can't do this: `remoteProfileToDbRow`
  /// preserves the existing row's `isDefault`, so a slave clearing the default
  /// would be a host-side no-op. This routes through the DAO's
  /// `clearDefaultProfile`.
  Future<Response> handleClearDefaultProfile(Request request) async {
    _logInfo('[API] POST /api/profiles/default/clear');
    await _profilesDao.clearDefaultProfile();
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.updated,
    );
    return jsonOk({"status": "default-cleared"});
  }

  /// Persist a new display order for the equipment profiles.
  ///
  /// The body is `{"profileIds": ["3","1","2"]}`; each id is assigned
  /// `sortOrder == its index`. The converter's `remoteProfileToDbRow`
  /// preserves `existing.sortOrder`, so a slave's saveProfile loop was a
  /// host-side no-op — this dedicated endpoint writes sortOrder directly via
  /// the DAO's transactional `reorderProfiles`.
  Future<Response> handleReorderProfiles(Request request) async {
    _logInfo('[API] POST /api/profiles/reorder');
    final payload = await readJsonObject(request);
    final rawIds = requireList<dynamic>(payload, 'profileIds');
    final orderedIds = <int>[];
    for (final raw in rawIds) {
      final parsed = int.tryParse(raw.toString());
      if (parsed != null) {
        orderedIds.add(parsed);
      }
    }
    await _profilesDao.reorderProfiles(orderedIds);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.profile,
      action: HostMutationAction.updated,
    );
    return jsonOk({"status": "reordered"});
  }

  Future<Response> handleGetActiveProfile(Request request) async {
    final row = await _profilesDao.getActiveProfile();
    return jsonOk({
      "profile": row == null ? null : dbProfileToRemote(row).toJson(),
    });
  }

  /// Push the SQLite-active profile into the native (Rust) executor store so
  /// `load_and_set_profile` side effects run. The native store keeps exactly
  /// one job now: feed the active profile to the executor. Best-effort — a
  /// native hiccup must not fail the REST activation.
  Future<void> _writeActiveProfileThroughToRust(int profileId) async {
    try {
      final row = await _profilesDao.getProfileById(profileId);
      if (row == null) return;
      final remote = dbProfileToRemote(row);
      final backend = container.read(profileSettingsBackendProvider);
      await backend.saveProfile(remote);
      await backend.loadProfile(remote.id);
    } on Object catch (e) {
      _logger.debug(
        'Active-profile write-through to native store failed: $e',
        source: 'ProfileHandlers',
      );
    }
  }

  // ===========================================================================
  // Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    // Read from the DB-backed settings notifier (the desktop's source of
    // truth) rather than the Rust bridge, which only carries the ~7
    // engine-relevant fields and would report defaults for everything else.
    final notifier = container.read(appSettingsProvider.notifier);
    await container.read(appSettingsProvider.future);
    return jsonOk({"settings": notifier.exportRemoteSettings().toJson()});
  }

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/settings');
    // [settings sync] capture the optional commandId from the
    // request header so we can stamp `correlatingCommandId` on every
    // `settings.changed` event emitted below. The originating client
    // uses this to skip its own echo and avoid re-applying a value it
    // just wrote.
    final commandId = request.headers['x-nightshade-command-id'];
    final payload = await readJsonObject(request);
    final settingsJson = requireObject(payload, 'settings');
    final settings = settings_models.AppSettings.fromJson(settingsJson);

    final backend = container.read(profileSettingsBackendProvider);
    final settingsNotifier = container.read(appSettingsProvider.notifier);
    // [settings sync] capture the full previous settings (DB-backed) so we can
    // diff against the new state and emit one fine-grained `settings.changed`
    // event per changed field. If the read fails (first-boot / driver hiccup),
    // fall back to a single full-snapshot event so remote clients still see
    // the update.
    settings_models.AppSettings? previous;
    try {
      await container.read(appSettingsProvider.future);
      previous = settingsNotifier.exportRemoteSettings();
    } on Object catch (e) {
      // Why: `previous` only feeds an optional change-diff/notification below;
      // if the prior settings can't be read we proceed without the diff
      // rather than failing the update itself.
      _logger.debug(
        'Settings update: could not read previous settings for the '
        'change diff: $e',
        source: 'ProfileHandlers',
      );
      previous = null;
    }

    // Persist the COMPLETE settings to the database — the single source of
    // truth shared with the desktop — then sync the engine-relevant subset
    // (location/theme/language/autoConnect) to the native bridge so the
    // executor stays consistent. Writing only the bridge previously dropped
    // every other field on the floor (B16): the API returned "updated" but
    // the value never persisted.
    await settingsNotifier.applyRemoteSettings(settings);
    await backend.updateSettings(settings);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.settings,
      action: HostMutationAction.updated,
    );

    // [settings sync] emit live settings-change events so every
    // connected WS client can update its in-memory state without a GET
    // round-trip. The diff is field-by-field on the freezed `AppSettings`
    // JSON projection — same JSON the client originally sent, so the
    // keys match what the receiver expects.
    _emitSettingsChanges(
      previous: previous,
      next: settings,
      commandId: commandId,
    );

    return jsonOk({"status": "updated"});
  }

  /// Fan out one `settings.changed` event per
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

    NightshadeEvent buildEvent({required String key, required dynamic value}) {
      return NightshadeEvent(
        timestamp: nowMillis,
        severity: EventSeverity.info,
        category: EventCategory.system,
        eventType: settingsChangedEventType,
        data: {'key': key, 'value': value, 'changedAt': changedAt},
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

    // Mirror the location into the Drift settings DAO. The backend store above
    // is the canonical one read by GET /api/settings/location, the planetarium,
    // and the native sequencer — but the scheduler and "tonight" suggestion
    // subsystems read observer lat/lon straight from `settingsDao`, which on a
    // headless appliance is otherwise only ever populated by the GUI settings
    // flow (never run here). Without this mirror, a remote client that sets its
    // location through the API gets a working planetarium but a permanently
    // "No observer location configured" scheduler. Clearing (null) zeroes both.
    final settingsDao = container.read(databaseProvider).settingsDao;
    await settingsDao.setObserverLatitude(location?.latitude ?? 0.0);
    await settingsDao.setObserverLongitude(location?.longitude ?? 0.0);
    await settingsDao.setObserverElevation(location?.elevation ?? 0.0);

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
