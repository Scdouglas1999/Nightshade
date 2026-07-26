import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/settings_dao.dart';
import '../models/alerts/transient_alert.dart';
import '../models/target/target_models.dart';
import '../services/logging_service.dart';
import '../services/notification/secrets_store.dart';
import '../services/target_library_service.dart';
import '../services/transient_alert_service.dart';
import '../services/transients/transient_alert_mapper.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'notification_router_provider.dart';
import 'science_provider.dart';
import 'transient_detections_provider.dart';
import 'ui_notification_provider.dart';

// =============================================================================
// Transient Alert Settings Provider
// =============================================================================

/// Storage key prefix for transient alert settings in the database
const String _settingsKeyPrefix = 'transient_alert_';

/// Notifier for managing transient alert settings with persistence.
///
/// Settings are persisted to the app settings database and loaded on startup.
/// Changes are immediately saved to ensure settings survive app restarts.
class TransientAlertSettingsNotifier
    extends StateNotifier<TransientAlertSettings> {
  final SettingsDao _settingsDao;
  final LoggingService _logger;
  final NetworkBackend? _remote;
  bool _initialized = false;
  Completer<void>? _loadCompleter;
  TransientAlertSettings _confirmedSettings =
      TransientAlertSettings.defaultSettings;
  TransientAlertSettings _requestedSettings =
      TransientAlertSettings.defaultSettings;
  int _requestRevision = 0;
  Future<void> _writeTail = Future<void>.value();
  Future<void> _requestedWrite = Future<void>.value();

  TransientAlertSettingsNotifier({
    required SettingsDao settingsDao,
    required LoggingService logger,
    NetworkBackend? remote,
  }) : _settingsDao = settingsDao,
       _logger = logger,
       _remote = remote,
       super(TransientAlertSettings.defaultSettings) {
    unawaited(_loadSettings());
  }

  /// Resolves after the local database or remote host has supplied the
  /// authoritative initial snapshot. Headless handlers await this so a request
  /// arriving during startup never observes and writes over temporary defaults.
  Future<void> get loaded {
    if (_initialized) return Future<void>.value();
    _loadCompleter ??= Completer<void>();
    return _loadCompleter!.future;
  }

  Set<TransientSource>? _parseSources(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return null;
      final parsed = <TransientSource>{};
      for (final item in decoded) {
        if (item is! String) continue;
        for (final source in TransientSource.values) {
          if (source.name == item) {
            parsed.add(source);
            break;
          }
        }
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Set<TransientType>? _parseTypes(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return null;
      final parsed = <TransientType>{};
      for (final item in decoded) {
        if (item is! String) continue;
        for (final type in TransientType.values) {
          if (type.name == item) {
            parsed.add(type);
            break;
          }
        }
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  double _parseFiniteDouble(String? raw, double fallback) {
    final value = raw == null ? null : double.tryParse(raw);
    return value != null && value.isFinite ? value : fallback;
  }

  bool _parseBool(String? raw, bool fallback) {
    return switch (raw?.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
  }

  /// Load settings from persistent storage
  Future<void> _loadSettings() async {
    if (_initialized) return;
    final revisionAtStart = _requestRevision;

    try {
      final remote = _remote;
      final allSettings = remote == null
          ? await _settingsDao.getAllSettings()
          : _remoteSettingsAsStored(await remote.getTransientSettings());

      // Parse enabled sources
      final sourcesJson = allSettings['${_settingsKeyPrefix}enabled_sources'];
      final enabledSources =
          _parseSources(sourcesJson) ??
          TransientAlertSettings.defaultSettings.enabledSources;

      // Parse types to monitor
      final typesJson = allSettings['${_settingsKeyPrefix}types_to_monitor'];
      final typesToMonitor =
          _parseTypes(typesJson) ??
          TransientAlertSettings.defaultSettings.typesToMonitor;

      // Parse numeric and boolean settings
      final magnitudeThreshold = _parseFiniteDouble(
        allSettings['${_settingsKeyPrefix}magnitude_threshold'],
        TransientAlertSettings.defaultSettings.magnitudeThreshold,
      );

      final notifyOnNew = _parseBool(
        allSettings['${_settingsKeyPrefix}notify_on_new'],
        TransientAlertSettings.defaultSettings.notifyOnNew,
      );

      final autoQueueBright = _parseBool(
        allSettings['${_settingsKeyPrefix}auto_queue_bright'],
        TransientAlertSettings.defaultSettings.autoQueueBright,
      );

      final autoQueueMagnitude = _parseFiniteDouble(
        allSettings['${_settingsKeyPrefix}auto_queue_magnitude'],
        TransientAlertSettings.defaultSettings.autoQueueMagnitude,
      );

      final loaded = TransientAlertSettings(
        enabledSources: enabledSources,
        magnitudeThreshold: magnitudeThreshold,
        typesToMonitor: typesToMonitor,
        notifyOnNew: notifyOnNew,
        autoQueueBright: autoQueueBright,
        autoQueueMagnitude: autoQueueMagnitude,
      );
      if (mounted && revisionAtStart == _requestRevision) {
        _confirmedSettings = loaded;
        _requestedSettings = loaded;
        state = loaded;
      }

      _logger.debug(
        'Transient alert settings loaded: ${enabledSources.length} sources, '
        '${typesToMonitor.length} types, magnitude <= $magnitudeThreshold',
        source: 'TransientAlertSettingsNotifier',
      );
    } catch (e) {
      _logger.error(
        'Failed to load transient alert settings: $e',
        source: 'TransientAlertSettingsNotifier',
      );
      // Keep default settings on error
    } finally {
      _initialized = true;
      final completer = _loadCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      _loadCompleter = null;
    }
  }

  /// Save all current settings to persistent storage
  Future<void> _saveSettings(TransientAlertSettings settings) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.updateTransientSettings({
          'enabledSources': settings.enabledSources
              .map((source) => source.name)
              .toList(),
          'typesToMonitor': settings.typesToMonitor
              .map((type) => type.name)
              .toList(),
          'magnitudeThreshold': settings.magnitudeThreshold,
          'notifyOnNew': settings.notifyOnNew,
          'autoQueueBright': settings.autoQueueBright,
          'autoQueueMagnitude': settings.autoQueueMagnitude,
        });
      } else {
        await _settingsDao.setSettings({
          '${_settingsKeyPrefix}enabled_sources': json.encode(
            settings.enabledSources.map((s) => s.name).toList(),
          ),
          '${_settingsKeyPrefix}types_to_monitor': json.encode(
            settings.typesToMonitor.map((t) => t.name).toList(),
          ),
          '${_settingsKeyPrefix}magnitude_threshold': settings
              .magnitudeThreshold
              .toString(),
          '${_settingsKeyPrefix}notify_on_new': settings.notifyOnNew.toString(),
          '${_settingsKeyPrefix}auto_queue_bright': settings.autoQueueBright
              .toString(),
          '${_settingsKeyPrefix}auto_queue_magnitude': settings
              .autoQueueMagnitude
              .toString(),
        });
      }
      _logger.debug(
        'Transient alert settings saved',
        source: 'TransientAlertSettingsNotifier',
      );
    } catch (e) {
      _logger.error(
        'Failed to save transient alert settings: $e',
        source: 'TransientAlertSettingsNotifier',
      );
      rethrow;
    }
  }

  Map<String, String> _remoteSettingsAsStored(Map<String, dynamic> settings) {
    final enabledSources = settings['enabledSources'];
    final typesToMonitor = settings['typesToMonitor'];
    return {
      if (enabledSources is List)
        '${_settingsKeyPrefix}enabled_sources': json.encode(enabledSources),
      if (typesToMonitor is List)
        '${_settingsKeyPrefix}types_to_monitor': json.encode(typesToMonitor),
      if (settings['magnitudeThreshold'] != null)
        '${_settingsKeyPrefix}magnitude_threshold':
            settings['magnitudeThreshold'].toString(),
      if (settings['notifyOnNew'] != null)
        '${_settingsKeyPrefix}notify_on_new': settings['notifyOnNew']
            .toString(),
      if (settings['autoQueueBright'] != null)
        '${_settingsKeyPrefix}auto_queue_bright': settings['autoQueueBright']
            .toString(),
      if (settings['autoQueueMagnitude'] != null)
        '${_settingsKeyPrefix}auto_queue_magnitude':
            settings['autoQueueMagnitude'].toString(),
    };
  }

  Future<void> _queueSettingsUpdate(TransientAlertSettings settings) {
    if (_requestedSettings == settings) return _requestedWrite;

    _requestedSettings = settings;
    final revision = ++_requestRevision;
    state = settings;
    final operation = _writeTail.then((_) async {
      if (revision != _requestRevision) return;
      try {
        await _saveSettings(settings);
        _confirmedSettings = settings;
      } catch (_) {
        if (mounted && revision == _requestRevision) {
          _requestedSettings = _confirmedSettings;
          state = _confirmedSettings;
        }
        rethrow;
      }
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, __) {});
    _requestedWrite = operation;
    return operation;
  }

  /// Update all settings at once
  Future<void> updateSettings(TransientAlertSettings settings) async {
    await loaded;
    await _queueSettingsUpdate(settings);
  }

  /// Toggle a specific source on or off
  Future<void> toggleSource(TransientSource source) async {
    await loaded;
    final newSources = Set<TransientSource>.from(
      _requestedSettings.enabledSources,
    );
    if (newSources.contains(source)) {
      newSources.remove(source);
    } else {
      newSources.add(source);
    }
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(enabledSources: newSources),
    );
  }

  /// Toggle a specific transient type on or off
  Future<void> toggleType(TransientType type) async {
    await loaded;
    final newTypes = Set<TransientType>.from(_requestedSettings.typesToMonitor);
    if (newTypes.contains(type)) {
      newTypes.remove(type);
    } else {
      newTypes.add(type);
    }
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(typesToMonitor: newTypes),
    );
  }

  /// Set the magnitude threshold for alerts
  Future<void> setMagnitudeThreshold(double threshold) async {
    if (!threshold.isFinite) {
      throw ArgumentError.value(threshold, 'threshold', 'must be finite');
    }
    await loaded;
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(magnitudeThreshold: threshold),
    );
  }

  /// Set whether to notify on new alerts
  Future<void> setNotifyOnNew(bool notify) async {
    await loaded;
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(notifyOnNew: notify),
    );
  }

  /// Set whether to auto-queue bright transients
  Future<void> setAutoQueueBright(bool autoQueue) async {
    await loaded;
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(autoQueueBright: autoQueue),
    );
  }

  /// Set the magnitude threshold for auto-queuing
  Future<void> setAutoQueueMagnitude(double magnitude) async {
    if (!magnitude.isFinite) {
      throw ArgumentError.value(magnitude, 'magnitude', 'must be finite');
    }
    await loaded;
    await _queueSettingsUpdate(
      _requestedSettings.copyWith(autoQueueMagnitude: magnitude),
    );
  }
}

/// Provider for transient alert settings with persistence.
final transientAlertSettingsProvider =
    StateNotifierProvider<
      TransientAlertSettingsNotifier,
      TransientAlertSettings
    >((ref) {
      final settingsDao = ref.watch(settingsDaoProvider);
      final logger = ref.watch(loggingServiceProvider);
      final backend = ref.watch(backendProvider);
      return TransientAlertSettingsNotifier(
        settingsDao: settingsDao,
        logger: logger,
        remote: backend is NetworkBackend ? backend : null,
      );
    });

// =============================================================================
// Active Transient Alerts Provider
// =============================================================================

/// Polling interval for fetching alerts (15 minutes)
const Duration _alertPollingInterval = Duration(minutes: 15);

/// Provider that streams active transient alerts with periodic polling.
///
/// Fetches alerts immediately on subscription, then polls every 15 minutes.
/// Alerts are filtered based on current settings.
///
/// In remote mode (NetworkBackend), fetches from the headless server API.
/// In local mode, fetches directly from AAVSO/TNS APIs.
final activeTransientAlertsProvider =
    StreamProvider.autoDispose<List<TransientAlert>>((ref) {
      final backend = ref.watch(backendProvider);
      final service = ref.watch(transientAlertServiceProvider);
      final settings = ref.watch(transientAlertSettingsProvider);
      final logger = ref.watch(loggingServiceProvider);
      final secretsStore = ref.watch(secretsStoreProvider);
      final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull;
      final networkBackend = backend is NetworkBackend ? backend : null;

      // Create a controller for the stream
      final controller = StreamController<List<TransientAlert>>();

      // Pillar B ("First Light"): self-discovered transients flow through the
      // same alert surfaces. Watch the local difference-imaging detections and
      // merge the non-dismissed ones (most confident first) ahead of the
      // external feed so a fresh discovery sits at the top of the bell.
      var currentDetections =
          ref.read(allTransientDetectionsProvider).valueOrNull ?? const [];
      List<TransientAlert> localFirstLightAlerts() {
        return currentDetections
            .where((d) => !d.dismissed)
            .map(transientAlertFromDetection)
            .toList(growable: false);
      }

      // A single fetch round-trip. Wrapped by [fetchAlerts] below so that
      // overlapping triggers (immediate + poll + detections-change) never run
      // concurrently and out-of-order completion cannot overwrite fresher data.
      Future<void> runFetch() async {
        try {
          List<TransientAlert> alerts;

          if (networkBackend != null) {
            // Fetch from headless server API
            final response = await networkBackend.getActiveTransients();
            final alertsJson = response['alerts'];
            if (alertsJson is! List) {
              throw const FormatException(
                'GET /api/transients returned no alerts list',
              );
            }
            alerts = <TransientAlert>[];
            for (var index = 0; index < alertsJson.length; index++) {
              final item = alertsJson[index];
              if (item is! Map) {
                throw FormatException(
                  'GET /api/transients returned a non-object alerts[$index]',
                );
              }
              final alert = _tryParseTransientAlertFromJson(
                Map<String, dynamic>.from(item),
              );
              if (alert == null) {
                throw FormatException(
                  'GET /api/transients returned malformed alerts[$index]',
                );
              }
              alerts.add(alert);
            }
            logger.debug(
              'Fetched ${alerts.length} transient alerts from remote server',
              source: 'activeTransientAlertsProvider',
            );
          } else {
            // Fetch directly from AAVSO/TNS APIs
            var tnsApiKey = '';
            if (settings.enabledSources.contains(TransientSource.tns) &&
                scienceSettings != null &&
                scienceSettings.tnsBotId > 0 &&
                scienceSettings.tnsBotName.trim().isNotEmpty) {
              try {
                tnsApiKey = await secretsStore.read(SecretField.tnsApiKey);
              } catch (error) {
                // A keyring outage must not hide the independent AAVSO feed.
                logger.warning(
                  'Could not read the TNS API key; fetching other transient '
                  'sources only: $error',
                  source: 'activeTransientAlertsProvider',
                );
              }
            }
            alerts = await service.getAllAlerts(
              settings.copyWith(
                tnsApiKey: tnsApiKey.isEmpty ? null : tnsApiKey,
              ),
              tnsBotId: scienceSettings?.tnsBotId,
              tnsBotName: scienceSettings?.tnsBotName,
              tnsUseSandbox: scienceSettings?.tnsUseSandbox ?? false,
            );
            logger.debug(
              'Fetched ${alerts.length} transient alerts from local service',
              source: 'activeTransientAlertsProvider',
            );
          }

          // Merge local First Light discoveries ahead of the external feed.
          final merged = _mergeAlerts(localFirstLightAlerts(), alerts);

          if (!controller.isClosed) {
            controller.add(merged);
          }
        } catch (e) {
          logger.error(
            'Error fetching transient alerts: $e',
            source: 'activeTransientAlertsProvider',
          );
          // Even if the external feed failed, still surface local discoveries —
          // a self-found transient must never be hidden by a dead uplink.
          final local = localFirstLightAlerts();
          if (local.isNotEmpty) {
            if (!controller.isClosed) controller.add(local);
          } else if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      }

      // Coalesce overlapping triggers: only one fetch runs at a time, and any
      // trigger that arrives mid-flight schedules exactly one follow-up run so
      // the newest data always wins (no out-of-order overwrite, no thundering
      // herd of concurrent requests).
      var fetchInProgress = false;
      var fetchPending = false;
      Future<void> fetchAlerts() async {
        if (fetchInProgress) {
          fetchPending = true;
          return;
        }
        fetchInProgress = true;
        try {
          do {
            fetchPending = false;
            await runFetch();
          } while (fetchPending && !controller.isClosed);
        } finally {
          fetchInProgress = false;
        }
      }

      // Fetch immediately
      fetchAlerts();

      // Set up periodic polling
      final timer = Timer.periodic(_alertPollingInterval, (_) {
        fetchAlerts();
      });

      // Re-merge whenever the local detections change (a fresh scan persisted a
      // new transient) so the bell updates without waiting for the poll tick.
      ref.listen(allTransientDetectionsProvider, (_, next) {
        currentDetections = next.valueOrNull ?? currentDetections;
        fetchAlerts();
      });

      // Clean up on dispose
      ref.onDispose(() {
        timer.cancel();
        controller.close();
      });

      return controller.stream;
    });

/// Parse a TransientAlert from JSON response
List<TransientAlert> _mergeAlerts(
  List<TransientAlert> local,
  List<TransientAlert> external,
) {
  final seen = <String>{};
  return <TransientAlert>[
    for (final alert in [...local, ...external])
      if (alert.id.trim().isNotEmpty && seen.add(alert.id)) alert,
  ];
}

/// Parses one alert received from a remote imaging host. The caller rejects
/// the entire malformed response so corrupt host data cannot masquerade as a
/// trustworthy empty or partial feed.
TransientAlert? _tryParseTransientAlertFromJson(Map<String, dynamic> json) {
  final id = json['id'];
  final name = json['name'];
  final ra = json['raHours'];
  final dec = json['decDegrees'];
  final discoveryMillis = json['discoveryTime'];
  final updatedMillis = json['lastUpdated'];
  if (id is! String ||
      id.trim().isEmpty ||
      name is! String ||
      name.trim().isEmpty ||
      ra is! num ||
      dec is! num ||
      discoveryMillis is! num ||
      updatedMillis is! num) {
    return null;
  }
  final raHours = ra.toDouble();
  final decDegrees = dec.toDouble();
  final magnitude = _finiteJsonDouble(json['magnitude']);
  final peakMagnitude = _finiteJsonDouble(json['peakMagnitude']);
  if (!raHours.isFinite ||
      raHours < 0 ||
      raHours >= 24 ||
      !decDegrees.isFinite ||
      decDegrees < -90 ||
      decDegrees > 90 ||
      (json['magnitude'] != null && magnitude == null) ||
      (json['peakMagnitude'] != null && peakMagnitude == null)) {
    return null;
  }
  final discoveryEpoch = discoveryMillis.toDouble();
  final updatedEpoch = updatedMillis.toDouble();
  const maxDateTimeEpoch = 8640000000000000.0;
  if (!discoveryEpoch.isFinite ||
      discoveryEpoch.abs() > maxDateTimeEpoch ||
      !updatedEpoch.isFinite ||
      updatedEpoch.abs() > maxDateTimeEpoch) {
    return null;
  }

  TransientSource? source;
  for (final candidate in TransientSource.values) {
    if (candidate.name == json['source']) {
      source = candidate;
      break;
    }
  }
  if (source == null) return null;

  TransientType? type;
  for (final candidate in TransientType.values) {
    if (candidate.name == json['type']) {
      type = candidate;
      break;
    }
  }
  if (type == null) return null;

  final priorityValue = json['priority'];
  if (priorityValue is! num ||
      !priorityValue.isFinite ||
      priorityValue != priorityValue.round() ||
      priorityValue < 1 ||
      priorityValue > 10 ||
      (json['sourceUrl'] != null && json['sourceUrl'] is! String) ||
      (json['classification'] != null && json['classification'] is! String) ||
      (json['notes'] != null && json['notes'] is! String)) {
    return null;
  }
  return TransientAlert(
    id: id,
    name: name,
    type: type,
    raHours: raHours,
    decDegrees: decDegrees,
    magnitude: magnitude,
    peakMagnitude: peakMagnitude,
    discoveryTime: DateTime.fromMillisecondsSinceEpoch(discoveryEpoch.round()),
    lastUpdated: DateTime.fromMillisecondsSinceEpoch(updatedEpoch.round()),
    source: source,
    sourceUrl: json['sourceUrl'] is String ? json['sourceUrl'] as String : null,
    priority: priorityValue.toInt(),
    classification: json['classification'] is String
        ? json['classification'] as String
        : null,
    notes: json['notes'] is String ? json['notes'] as String : null,
  );
}

double? _finiteJsonDouble(Object? value) {
  if (value is! num) return null;
  final converted = value.toDouble();
  return converted.isFinite ? converted : null;
}

// =============================================================================
// Transient Alert States Provider
// =============================================================================

/// Storage key prefix for alert states in the database
const String _alertStateKeyPrefix = 'transient_alert_state_';

/// Notifier for tracking user actions on transient alerts.
///
/// Persists alert states (acknowledged, queued, observed, dismissed) to the database
/// so they survive app restarts.
class TransientAlertStatesNotifier
    extends StateNotifier<Map<String, TransientAlertState>> {
  final SettingsDao _settingsDao;
  final LoggingService _logger;
  final NetworkBackend? _remote;
  bool _initialized = false;
  Completer<void>? _loadCompleter;
  int _requestRevision = 0;
  Future<void> _writeTail = Future<void>.value();

  TransientAlertStatesNotifier({
    required SettingsDao settingsDao,
    required LoggingService logger,
    NetworkBackend? remote,
  }) : _settingsDao = settingsDao,
       _logger = logger,
       _remote = remote,
       super({}) {
    unawaited(_loadStates());
  }

  /// Resolves once persisted states have been applied. Mutations wait for this
  /// snapshot so a first click cannot discard unrelated existing alert states.
  Future<void> get loaded {
    if (_initialized) return Future<void>.value();
    _loadCompleter ??= Completer<void>();
    return _loadCompleter!.future;
  }

  /// Load alert states from persistent storage
  Future<void> _loadStates() async {
    if (_initialized) return;
    final revisionAtStart = _requestRevision;

    try {
      final states = <String, TransientAlertState>{};
      final remote = _remote;
      if (remote != null) {
        final remoteStates = await remote.getTransientStates();
        for (final entry in remoteStates.entries) {
          final alertId = entry.key.trim();
          final value = entry.value;
          if (alertId.isEmpty || value is! String) continue;
          for (final candidate in TransientAlertState.values) {
            if (candidate.name == value) {
              states[alertId] = candidate;
              break;
            }
          }
        }
      } else {
        final allSettings = await _settingsDao.getAllSettings();
        // Find all alert state entries
        for (final entry in allSettings.entries) {
          if (entry.key.startsWith(_alertStateKeyPrefix)) {
            final alertId = entry.key.substring(_alertStateKeyPrefix.length);
            final stateValue = TransientAlertState.values.firstWhere(
              (s) => s.name == entry.value,
              orElse: () => TransientAlertState.newAlert,
            );
            states[alertId] = stateValue;
          }
        }
      }

      if (mounted && revisionAtStart == _requestRevision) {
        state = states;
      }
      _logger.debug(
        'Loaded ${states.length} transient alert states',
        source: 'TransientAlertStatesNotifier',
      );
    } catch (e) {
      _logger.error(
        'Failed to load transient alert states: $e',
        source: 'TransientAlertStatesNotifier',
      );
    } finally {
      _initialized = true;
      final completer = _loadCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
      _loadCompleter = null;
    }
  }

  Future<void> _setAlertState(String id, TransientAlertState alertState) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    await loaded;
    if (state[id] == alertState) {
      await _writeTail;
      return;
    }

    _requestRevision++;
    final operation = _writeTail.then((_) async {
      await _saveState(id, alertState);
      if (mounted) state = {...state, id: alertState};
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, __) {});
    await operation;
  }

  /// Save a single alert state to persistent storage
  Future<void> _saveState(
    String alertId,
    TransientAlertState alertState,
  ) async {
    try {
      final remote = _remote;
      if (remote != null) {
        await remote.updateTransientState(alertId, alertState.name);
      } else {
        await _settingsDao.setSetting(
          '$_alertStateKeyPrefix$alertId',
          alertState.name,
        );
      }
    } catch (e) {
      _logger.error(
        'Failed to save alert state for $alertId: $e',
        source: 'TransientAlertStatesNotifier',
      );
      rethrow;
    }
  }

  /// Mark an alert as acknowledged
  Future<void> acknowledge(String id) async {
    await _setAlertState(id, TransientAlertState.acknowledged);
    _logger.debug(
      'Alert $id acknowledged',
      source: 'TransientAlertStatesNotifier',
    );
  }

  /// Mark an alert as queued for observation
  Future<void> queue(String id) async {
    await _setAlertState(id, TransientAlertState.queued);
    _logger.debug('Alert $id queued', source: 'TransientAlertStatesNotifier');
  }

  /// Mark an alert as observed
  Future<void> markObserved(String id) async {
    await _setAlertState(id, TransientAlertState.observed);
    _logger.debug(
      'Alert $id marked as observed',
      source: 'TransientAlertStatesNotifier',
    );
  }

  /// Dismiss an alert
  Future<void> dismiss(String id) async {
    await _setAlertState(id, TransientAlertState.dismissed);
    _logger.debug(
      'Alert $id dismissed',
      source: 'TransientAlertStatesNotifier',
    );
  }

  /// Set a state supplied by a remote API after it has been validated.
  Future<void> setState(String id, TransientAlertState alertState) =>
      _setAlertState(id, alertState);

  /// Get the state of a specific alert
  TransientAlertState? getState(String id) => state[id];

  /// Clear all alert states (useful for testing or reset)
  Future<void> clearAll() async {
    await loaded;
    _requestRevision++;
    final operation = _writeTail.then((_) async {
      try {
        final remote = _remote;
        if (remote != null) {
          await remote.clearTransientStates();
        } else {
          // Remove all alert state entries from the database
          final allSettings = await _settingsDao.getAllSettings();
          for (final key in allSettings.keys) {
            if (key.startsWith(_alertStateKeyPrefix)) {
              await _settingsDao.deleteSetting(key);
            }
          }
        }
        if (mounted) state = {};
        _logger.info(
          'All alert states cleared',
          source: 'TransientAlertStatesNotifier',
        );
      } catch (e) {
        _logger.error(
          'Failed to clear alert states: $e',
          source: 'TransientAlertStatesNotifier',
        );
        rethrow;
      }
    });
    _writeTail = operation.then<void>((_) {}, onError: (_, __) {});
    await operation;
  }
}

/// Provider for tracking user actions on transient alerts.
final transientAlertStatesProvider =
    StateNotifierProvider<
      TransientAlertStatesNotifier,
      Map<String, TransientAlertState>
    >((ref) {
      final settingsDao = ref.watch(settingsDaoProvider);
      final logger = ref.watch(loggingServiceProvider);
      final backend = ref.watch(backendProvider);
      return TransientAlertStatesNotifier(
        settingsDao: settingsDao,
        logger: logger,
        remote: backend is NetworkBackend ? backend : null,
      );
    });

// =============================================================================
// Unacknowledged Alert Count Provider
// =============================================================================

/// Provider that computes the count of unacknowledged alerts.
///
/// An alert is considered unacknowledged if:
/// - It has no state entry (brand new)
/// - Its state is [TransientAlertState.newAlert]
final unacknowledgedAlertCountProvider = Provider<int>((ref) {
  final alertsAsync = ref.watch(activeTransientAlertsProvider);
  final states = ref.watch(transientAlertStatesProvider);

  final alerts = alertsAsync.valueOrNull ?? [];

  return alerts.where((alert) {
    final alertState = states[alert.id];
    return alertState == null || alertState == TransientAlertState.newAlert;
  }).length;
});

// =============================================================================
// Queue Transient Action
// =============================================================================

final _transientQueueFlightsProvider =
    Provider<Map<String, Future<CelestialTarget?>>>((ref) => {});

/// Queue a transient alert for tonight's observation.
///
/// This function:
/// 1. Creates a new target from the alert's coordinates
/// 2. Marks the alert as queued after creation succeeds
/// 3. Shows a notification confirming the action
///
/// Parameters:
/// - [ref]: WidgetRef for accessing providers
/// - [alert]: The transient alert to queue
///
/// Returns the created target, or null if creation failed.
Future<CelestialTarget?> queueTransientForTonight(
  WidgetRef ref,
  TransientAlert alert,
) async {
  final flights = ref.read(_transientQueueFlightsProvider);
  final existing = flights[alert.id];
  if (existing != null) return existing;

  final operation = _performQueueTransientForTonight(ref, alert);
  flights[alert.id] = operation;
  try {
    return await operation;
  } finally {
    if (identical(flights[alert.id], operation)) {
      flights.remove(alert.id)?.ignore();
    }
  }
}

Future<CelestialTarget?> _performQueueTransientForTonight(
  WidgetRef ref,
  TransientAlert alert,
) async {
  final logger = ref.read(loggingServiceProvider);
  final statesNotifier = ref.read(transientAlertStatesProvider.notifier);
  final notificationNotifier = ref.read(uiNotificationProvider.notifier);
  try {
    // Map TransientType to TargetType
    final targetType = _mapTransientTypeToTargetType(alert.type);

    // Build notes combining all transient info
    final alertNotes = StringBuffer();
    alertNotes.writeln(
      'Transient alert from ${alert.source.name.toUpperCase()}',
    );
    if (alert.classification != null) {
      alertNotes.writeln('Classification: ${alert.classification}');
    }
    if (alert.notes != null) {
      alertNotes.writeln('Alert notes: ${alert.notes}');
    }
    alertNotes.writeln(
      'Queued from transient alert on ${DateTime.now().toIso8601String()}',
    );
    alertNotes.writeln(
      'Discovery time: ${alert.discoveryTime.toIso8601String()}',
    );
    if (alert.sourceUrl != null) {
      alertNotes.writeln('Source URL: ${alert.sourceUrl}');
    }

    final targetId = await ref
        .read(targetLibraryServiceProvider)
        .createTarget(
          name: alert.name,
          catalogId: alert.id,
          raHours: alert.raHours,
          decDegrees: alert.decDegrees,
          objectType: targetType.name,
          magnitude: alert.magnitude,
          isFavorite: false,
          priority: alert.priority,
          notes: alertNotes.toString(),
        );

    // Create the target object to return
    final target = CelestialTarget(
      id: targetId,
      name: alert.name,
      catalogId: alert.id,
      raHours: alert.raHours,
      decDegrees: alert.decDegrees,
      objectType: targetType,
      magnitude: alert.magnitude,
      priority: alert.priority,
    );

    // The durable target is the primary action. Mark the feed item queued only
    // after target creation succeeds so a failed create never leaves an alert
    // falsely labelled as queued. A status-write failure must not turn a real,
    // successfully-created target into a reported total failure.
    var statusSaved = true;
    try {
      await statesNotifier.queue(alert.id);
    } catch (e) {
      statusSaved = false;
      logger.error(
        'Target $targetId was created for transient ${alert.name}, but its '
        'queued state could not be saved: $e',
        source: 'queueTransientForTonight',
      );
    }

    // Show notification
    notificationNotifier.showSuccess(
      'Added ${alert.name} to your target library',
      title: 'Added to Library',
    );
    if (!statusSaved) {
      notificationNotifier.showWarning(
        'The target was added, but this alert could not be marked as queued.',
        title: 'Alert Status Not Saved',
      );
    }

    logger.info(
      'Queued transient ${alert.name} (ID: ${alert.id}) as target ID: $targetId',
      source: 'queueTransientForTonight',
    );

    return target;
  } catch (e) {
    logger.error(
      'Failed to queue transient ${alert.name}: $e',
      source: 'queueTransientForTonight',
    );
    notificationNotifier.showError(
      'Failed to queue ${alert.name}: $e',
      title: 'Queue Error',
    );
    return null;
  }
}

/// Maps a TransientType to a TargetType for target creation.
TargetType _mapTransientTypeToTargetType(TransientType type) {
  switch (type) {
    case TransientType.nova:
    case TransientType.supernova:
    case TransientType.cataclysmic:
    case TransientType.variableStar:
    case TransientType.gammaRayBurst:
      return TargetType.star;
    case TransientType.comet:
      return TargetType.comet;
    case TransientType.asteroid:
      return TargetType.asteroid;
    case TransientType.other:
      return TargetType.other;
  }
}

// =============================================================================
// Refresh Action
// =============================================================================

/// Force refresh the transient alerts by clearing the service cache.
///
/// This clears the internal cache and triggers a new fetch.
void refreshTransientAlerts(WidgetRef ref) {
  final service = ref.read(transientAlertServiceProvider);
  service.clearCache();

  // Invalidate the provider to trigger a fresh fetch
  ref.invalidate(activeTransientAlertsProvider);

  final logger = ref.read(loggingServiceProvider);
  logger.info(
    'Transient alerts refresh triggered',
    source: 'refreshTransientAlerts',
  );
}
