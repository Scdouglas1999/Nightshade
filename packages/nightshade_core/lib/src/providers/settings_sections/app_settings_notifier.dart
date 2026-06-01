part of '../settings_provider.dart';

/// Main app settings notifier that persists all settings to database
class AppSettingsNotifier extends AsyncNotifier<AppSettingsState> {
  models.AppSettings? _remoteSettingsSnapshot;

  // [Wave 6B settings sync] Push-event subscription, live only when the
  // active backend is a NetworkBackend. The host emits one
  // `settings.changed` event per field that differs in a POST
  // /api/settings call; the notifier applies the change in-place so
  // every connected client stays consistent without re-fetching the
  // full settings blob.
  StreamSubscription<NightshadeEvent>? _settingsEventSub;

  /// `correlatingCommandId`s of POSTs this notifier itself originated.
  /// Used to drop our own echoes so a local write doesn't fight the
  /// in-flight UI by overwriting state with the value we just sent.
  /// Bounded at 64 entries â€” far more than any realistic in-flight
  /// burst, but cheap to keep.
  final List<String> _ownCommandIds = <String>[];

  Future<void> _writeRemoteSettings(AppSettingsState settings) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      throw StateError(
          'Remote settings write requested without network backend');
    }

    final remote = _toRemoteSettings(settings);
    // [Wave 6B settings sync] generate a command id, register it in the
    // local echo-suppression list, and forward to the host. The host
    // stamps `correlatingCommandId` on every `settings.changed` event
    // emitted from this POST; our event handler drops events whose id
    // matches so we don't fight ourselves.
    final commandId = _generateLocalCommandId();
    _registerOwnCommandId(commandId);
    await backend.updateSettingsWithCommandId(remote, commandId: commandId);
    _remoteSettingsSnapshot = remote;
  }

  /// Bounded FIFO insertion so the echo-suppression list doesn't grow
  /// without bound if the server is offline / dropping events.
  void _registerOwnCommandId(String id) {
    if (_ownCommandIds.length >= 64) {
      _ownCommandIds.removeAt(0);
    }
    _ownCommandIds.add(id);
  }

  /// Cheap, opaque command id generator. We deliberately don't pull
  /// `package:uuid` for one call site â€” a `timestamp-random` pair is
  /// collision-resistant enough for echo-suppression (the id only has
  /// to be unique among an individual client's recent in-flight
  /// writes).
  static int _commandIdCounter = 0;
  static String _generateLocalCommandId() {
    _commandIdCounter += 1;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'settings-${ts.toRadixString(36)}-$_commandIdCounter';
  }

  /// [Wave 6B settings sync] Apply a single `settings.changed` event by
  /// merging its `{key, value}` into the current state. Returns silently
  /// when the event is malformed, the state is not yet loaded, or the
  /// originating command id matches one we wrote ourselves.
  void _applySettingsChangedEvent(NightshadeEvent event) {
    if (event.eventType != settingsChangedEventType) return;

    // Origin filter: drop our own echo so we don't churn the UI.
    final originId = event.correlatingCommandId;
    if (originId != null && _ownCommandIds.remove(originId)) {
      return;
    }

    final current = state.valueOrNull;
    if (current == null) {
      // The build() future is still resolving; the subsequent fetch
      // will include the new value, so skipping is correct.
      return;
    }

    final key = event.data['key'];
    if (key is! String || key.isEmpty) return;

    // Full-snapshot variant emitted when the host couldn't read the
    // previous settings (first-write / recovery path).
    if (key == '__snapshot__') {
      final snapshot = event.data['value'];
      if (snapshot is Map<String, dynamic>) {
        try {
          final remote = models.AppSettings.fromJson(snapshot);
          _remoteSettingsSnapshot = remote;
          state = AsyncData(_fromRemoteSettings(remote));
        } catch (e, st) {
          developer.log(
            'settings.changed snapshot parse failed: $e\n$st',
            name: 'AppSettingsNotifier',
            level: 900,
          );
        }
      }
      return;
    }

    final value = event.data['value'];
    // Merge into the cached remote snapshot so future diffs are
    // accurate; the snapshot mirrors what the host has on disk.
    final snapshot = _remoteSettingsSnapshot;
    if (snapshot != null) {
      final updatedRemoteJson = Map<String, dynamic>.from(snapshot.toJson())
        ..[key] = value;
      try {
        _remoteSettingsSnapshot =
            models.AppSettings.fromJson(updatedRemoteJson);
      } catch (e) {
        // Schema mismatch (e.g. forward-incompat key from a newer host).
        // Keep the previous snapshot to preserve diff integrity.
        developer.log(
          'settings.changed snapshot merge skipped for key=$key: $e',
          name: 'AppSettingsNotifier',
          level: 900,
        );
      }
    }

    final merged = _applyJsonSettingChange(current, key, value);
    if (merged != null && merged != current) {
      state = AsyncData(merged);
    }
  }

  @override
  Future<AppSettingsState> build() async {
    final backend = ref.watch(backendProvider);

    // [Wave 6B settings sync] tear down any previous subscription before
    // re-binding for the freshly-read backend. `build()` is called every
    // time the backend changes (FFI â†’ Network â†’ Disconnected etc.) and
    // each variant needs its own subscription policy. The cancel() future
    // is fire-and-forget; we only care that the listener stops dispatching.
    unawaited(_settingsEventSub?.cancel());
    _settingsEventSub = null;

    if (backend is NetworkBackend) {
      // Subscribe BEFORE the GET so an event that lands between the
      // POST acknowledgment and the GET's response can be re-applied
      // when the future resolves.
      _settingsEventSub = backend.eventStream.listen(
        (event) {
          if (event.category != EventCategory.system) return;
          if (event.eventType != settingsChangedEventType) return;
          _applySettingsChangedEvent(event);
        },
        onError: (Object error) {
          developer.log(
            'settings.changed stream error: $error',
            name: 'AppSettingsNotifier',
            level: 1000,
            error: error,
          );
        },
      );
      ref.onDispose(() {
        _settingsEventSub?.cancel();
        _settingsEventSub = null;
      });

      try {
        final remoteSettings = await backend.getSettings();
        _remoteSettingsSnapshot = remoteSettings;
        return _fromRemoteSettings(remoteSettings);
      } catch (e, stackTrace) {
        // Why: mobile clients pair with control scope; settings reads must
        // not tear down the session if the host rejects or omits a field.
        developer.log(
          'Remote settings fetch failed; using defaults until host responds: $e\n$stackTrace',
          name: 'AppSettingsNotifier',
          level: 900,
        );
        return const AppSettingsState();
      }
    }

    _remoteSettingsSnapshot = null;
    final dao = ref.read(settingsDaoProvider);
    final allSettings = await dao.getAllSettings();

    return _settingsFromStoredMap(allSettings);
  }

  Future<void> _saveSetting(String key, String value) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, {key: value});
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(key, value);
  }

  Future<void> _saveSettings(Map<String, String> settings) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, settings);
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSettings(settings);
  }

  /// Helper to update a single field in the current AppSettingsState.
  ///
  /// If the state hasn't loaded yet (no value), the update is silently skipped
  /// because there's nothing to patch. The database write has already succeeded,
  /// so the next full load will pick up the new value.
  void _patchState(
      AppSettingsState Function(AppSettingsState current) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(updater(current));
  }

  /// Read-side companion to [_patchState] for section extensions.
  ///
  /// Section setters live in `settings_sections/*.dart` as extensions on this
  /// class. Riverpod's [AsyncNotifier.state] is `@protected` /
  /// `@visibleForTesting`, and the analyzer does not treat extension members as
  /// "instance members of subclasses", so reaching for `state` directly from a
  /// section file is a static warning. Sections that need the current value
  /// (e.g. read-modify-write of a JSON map) go through this accessor instead,
  /// keeping all `state` access inside the notifier class body.
  AppSettingsState? get _currentValueOrNull => state.valueOrNull;

  // Section setters are defined in `settings_sections/*.dart` (split via
  // Dart `part` files). The class body below keeps only the lifecycle
  // (build), persistence writes (_saveSetting, _saveSettings), remote-sync
  // glue that needs protected notifier state, and the state accessors reused
  // by section extensions. Translation helpers live in the adjacent mapping
  // parts.
}
