import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/daos/settings_dao.dart';
import '../models/alerts/transient_alert.dart';
import '../models/target/target_models.dart';
import '../services/logging_service.dart';
import '../services/transient_alert_service.dart';
import 'database_provider.dart';
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
class TransientAlertSettingsNotifier extends StateNotifier<TransientAlertSettings> {
  final SettingsDao _settingsDao;
  final LoggingService _logger;
  bool _initialized = false;

  TransientAlertSettingsNotifier({
    required SettingsDao settingsDao,
    required LoggingService logger,
  })  : _settingsDao = settingsDao,
        _logger = logger,
        super(TransientAlertSettings.defaultSettings) {
    _loadSettings();
  }

  /// Load settings from persistent storage
  Future<void> _loadSettings() async {
    if (_initialized) return;

    try {
      final allSettings = await _settingsDao.getAllSettings();

      // Parse enabled sources
      final sourcesJson = allSettings['${_settingsKeyPrefix}enabled_sources'];
      Set<TransientSource> enabledSources;
      if (sourcesJson != null) {
        final sourcesList = (json.decode(sourcesJson) as List<dynamic>).cast<String>();
        enabledSources = sourcesList
            .map((s) => TransientSource.values.firstWhere(
                  (e) => e.name == s,
                  orElse: () => TransientSource.aavso,
                ))
            .toSet();
      } else {
        enabledSources = TransientAlertSettings.defaultSettings.enabledSources;
      }

      // Parse types to monitor
      final typesJson = allSettings['${_settingsKeyPrefix}types_to_monitor'];
      Set<TransientType> typesToMonitor;
      if (typesJson != null) {
        final typesList = (json.decode(typesJson) as List<dynamic>).cast<String>();
        typesToMonitor = typesList
            .map((t) => TransientType.values.firstWhere(
                  (e) => e.name == t,
                  orElse: () => TransientType.other,
                ))
            .toSet();
      } else {
        typesToMonitor = TransientAlertSettings.defaultSettings.typesToMonitor;
      }

      // Parse numeric and boolean settings
      final magnitudeThreshold = double.tryParse(
            allSettings['${_settingsKeyPrefix}magnitude_threshold'] ?? '',
          ) ??
          TransientAlertSettings.defaultSettings.magnitudeThreshold;

      final notifyOnNew =
          allSettings['${_settingsKeyPrefix}notify_on_new']?.toLowerCase() == 'true' ||
              (allSettings['${_settingsKeyPrefix}notify_on_new'] == null &&
                  TransientAlertSettings.defaultSettings.notifyOnNew);

      final autoQueueBright =
          allSettings['${_settingsKeyPrefix}auto_queue_bright']?.toLowerCase() == 'true';

      final autoQueueMagnitude = double.tryParse(
            allSettings['${_settingsKeyPrefix}auto_queue_magnitude'] ?? '',
          ) ??
          TransientAlertSettings.defaultSettings.autoQueueMagnitude;

      state = TransientAlertSettings(
        enabledSources: enabledSources,
        magnitudeThreshold: magnitudeThreshold,
        typesToMonitor: typesToMonitor,
        notifyOnNew: notifyOnNew,
        autoQueueBright: autoQueueBright,
        autoQueueMagnitude: autoQueueMagnitude,
      );

      _initialized = true;
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
      _initialized = true;
    }
  }

  /// Save all current settings to persistent storage
  Future<void> _saveSettings() async {
    try {
      await _settingsDao.setSettings({
        '${_settingsKeyPrefix}enabled_sources':
            json.encode(state.enabledSources.map((s) => s.name).toList()),
        '${_settingsKeyPrefix}types_to_monitor':
            json.encode(state.typesToMonitor.map((t) => t.name).toList()),
        '${_settingsKeyPrefix}magnitude_threshold': state.magnitudeThreshold.toString(),
        '${_settingsKeyPrefix}notify_on_new': state.notifyOnNew.toString(),
        '${_settingsKeyPrefix}auto_queue_bright': state.autoQueueBright.toString(),
        '${_settingsKeyPrefix}auto_queue_magnitude': state.autoQueueMagnitude.toString(),
      });
      _logger.debug('Transient alert settings saved', source: 'TransientAlertSettingsNotifier');
    } catch (e) {
      _logger.error(
        'Failed to save transient alert settings: $e',
        source: 'TransientAlertSettingsNotifier',
      );
      rethrow;
    }
  }

  /// Update all settings at once
  Future<void> updateSettings(TransientAlertSettings settings) async {
    state = settings;
    await _saveSettings();
  }

  /// Toggle a specific source on or off
  Future<void> toggleSource(TransientSource source) async {
    final newSources = Set<TransientSource>.from(state.enabledSources);
    if (newSources.contains(source)) {
      newSources.remove(source);
    } else {
      newSources.add(source);
    }
    state = state.copyWith(enabledSources: newSources);
    await _saveSettings();
  }

  /// Toggle a specific transient type on or off
  Future<void> toggleType(TransientType type) async {
    final newTypes = Set<TransientType>.from(state.typesToMonitor);
    if (newTypes.contains(type)) {
      newTypes.remove(type);
    } else {
      newTypes.add(type);
    }
    state = state.copyWith(typesToMonitor: newTypes);
    await _saveSettings();
  }

  /// Set the magnitude threshold for alerts
  Future<void> setMagnitudeThreshold(double threshold) async {
    state = state.copyWith(magnitudeThreshold: threshold);
    await _saveSettings();
  }

  /// Set whether to notify on new alerts
  Future<void> setNotifyOnNew(bool notify) async {
    state = state.copyWith(notifyOnNew: notify);
    await _saveSettings();
  }

  /// Set whether to auto-queue bright transients
  Future<void> setAutoQueueBright(bool autoQueue) async {
    state = state.copyWith(autoQueueBright: autoQueue);
    await _saveSettings();
  }

  /// Set the magnitude threshold for auto-queuing
  Future<void> setAutoQueueMagnitude(double magnitude) async {
    state = state.copyWith(autoQueueMagnitude: magnitude);
    await _saveSettings();
  }
}

/// Provider for transient alert settings with persistence.
final transientAlertSettingsProvider =
    StateNotifierProvider<TransientAlertSettingsNotifier, TransientAlertSettings>((ref) {
  final settingsDao = ref.watch(settingsDaoProvider);
  final logger = ref.watch(loggingServiceProvider);
  return TransientAlertSettingsNotifier(
    settingsDao: settingsDao,
    logger: logger,
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
final activeTransientAlertsProvider =
    StreamProvider.autoDispose<List<TransientAlert>>((ref) {
  final service = ref.watch(transientAlertServiceProvider);
  final settings = ref.watch(transientAlertSettingsProvider);
  final logger = ref.watch(loggingServiceProvider);

  // Create a controller for the stream
  final controller = StreamController<List<TransientAlert>>();

  // Initial fetch
  Future<void> fetchAlerts() async {
    try {
      final alerts = await service.getAllAlerts(settings);
      if (!controller.isClosed) {
        controller.add(alerts);
      }
      logger.debug(
        'Fetched ${alerts.length} transient alerts',
        source: 'activeTransientAlertsProvider',
      );
    } catch (e) {
      logger.error(
        'Error fetching transient alerts: $e',
        source: 'activeTransientAlertsProvider',
      );
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  // Fetch immediately
  fetchAlerts();

  // Set up periodic polling
  final timer = Timer.periodic(_alertPollingInterval, (_) {
    fetchAlerts();
  });

  // Clean up on dispose
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

// =============================================================================
// Transient Alert States Provider
// =============================================================================

/// Storage key prefix for alert states in the database
const String _alertStateKeyPrefix = 'transient_alert_state_';

/// Notifier for tracking user actions on transient alerts.
///
/// Persists alert states (acknowledged, queued, observed, dismissed) to the database
/// so they survive app restarts.
class TransientAlertStatesNotifier extends StateNotifier<Map<String, TransientAlertState>> {
  final SettingsDao _settingsDao;
  final LoggingService _logger;
  bool _initialized = false;

  TransientAlertStatesNotifier({
    required SettingsDao settingsDao,
    required LoggingService logger,
  })  : _settingsDao = settingsDao,
        _logger = logger,
        super({}) {
    _loadStates();
  }

  /// Load alert states from persistent storage
  Future<void> _loadStates() async {
    if (_initialized) return;

    try {
      final allSettings = await _settingsDao.getAllSettings();
      final states = <String, TransientAlertState>{};

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

      state = states;
      _initialized = true;
      _logger.debug(
        'Loaded ${states.length} transient alert states',
        source: 'TransientAlertStatesNotifier',
      );
    } catch (e) {
      _logger.error(
        'Failed to load transient alert states: $e',
        source: 'TransientAlertStatesNotifier',
      );
      _initialized = true;
    }
  }

  /// Save a single alert state to persistent storage
  Future<void> _saveState(String alertId, TransientAlertState alertState) async {
    try {
      await _settingsDao.setSetting(
        '$_alertStateKeyPrefix$alertId',
        alertState.name,
      );
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
    state = {...state, id: TransientAlertState.acknowledged};
    await _saveState(id, TransientAlertState.acknowledged);
    _logger.debug('Alert $id acknowledged', source: 'TransientAlertStatesNotifier');
  }

  /// Mark an alert as queued for observation
  Future<void> queue(String id) async {
    state = {...state, id: TransientAlertState.queued};
    await _saveState(id, TransientAlertState.queued);
    _logger.debug('Alert $id queued', source: 'TransientAlertStatesNotifier');
  }

  /// Mark an alert as observed
  Future<void> markObserved(String id) async {
    state = {...state, id: TransientAlertState.observed};
    await _saveState(id, TransientAlertState.observed);
    _logger.debug('Alert $id marked as observed', source: 'TransientAlertStatesNotifier');
  }

  /// Dismiss an alert
  Future<void> dismiss(String id) async {
    state = {...state, id: TransientAlertState.dismissed};
    await _saveState(id, TransientAlertState.dismissed);
    _logger.debug('Alert $id dismissed', source: 'TransientAlertStatesNotifier');
  }

  /// Get the state of a specific alert
  TransientAlertState? getState(String id) => state[id];

  /// Clear all alert states (useful for testing or reset)
  Future<void> clearAll() async {
    try {
      // Remove all alert state entries from the database
      final allSettings = await _settingsDao.getAllSettings();
      for (final key in allSettings.keys) {
        if (key.startsWith(_alertStateKeyPrefix)) {
          await _settingsDao.deleteSetting(key);
        }
      }
      state = {};
      _logger.info('All alert states cleared', source: 'TransientAlertStatesNotifier');
    } catch (e) {
      _logger.error(
        'Failed to clear alert states: $e',
        source: 'TransientAlertStatesNotifier',
      );
      rethrow;
    }
  }
}

/// Provider for tracking user actions on transient alerts.
final transientAlertStatesProvider =
    StateNotifierProvider<TransientAlertStatesNotifier, Map<String, TransientAlertState>>((ref) {
  final settingsDao = ref.watch(settingsDaoProvider);
  final logger = ref.watch(loggingServiceProvider);
  return TransientAlertStatesNotifier(
    settingsDao: settingsDao,
    logger: logger,
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
// Filtered Alerts Providers
// =============================================================================

/// Provider for alerts that have been queued for observation
final queuedAlertsProvider = Provider<List<TransientAlert>>((ref) {
  final alertsAsync = ref.watch(activeTransientAlertsProvider);
  final states = ref.watch(transientAlertStatesProvider);

  final alerts = alertsAsync.valueOrNull ?? [];

  return alerts.where((alert) {
    return states[alert.id] == TransientAlertState.queued;
  }).toList();
});

/// Provider for alerts that are actionable (new or acknowledged, not dismissed/observed)
final actionableAlertsProvider = Provider<List<TransientAlert>>((ref) {
  final alertsAsync = ref.watch(activeTransientAlertsProvider);
  final states = ref.watch(transientAlertStatesProvider);

  final alerts = alertsAsync.valueOrNull ?? [];

  return alerts.where((alert) {
    final alertState = states[alert.id];
    return alertState == null ||
        alertState == TransientAlertState.newAlert ||
        alertState == TransientAlertState.acknowledged;
  }).toList();
});

// =============================================================================
// Queue Transient Action
// =============================================================================

/// Queue a transient alert for tonight's observation.
///
/// This function:
/// 1. Marks the alert as queued in the state provider
/// 2. Creates a new target from the alert's coordinates
/// 3. Shows a notification confirming the action
///
/// Parameters:
/// - [ref]: WidgetRef for accessing providers
/// - [alert]: The transient alert to queue
///
/// Returns the created target, or null if creation failed.
Future<CelestialTarget?> queueTransientForTonight(WidgetRef ref, TransientAlert alert) async {
  final logger = ref.read(loggingServiceProvider);
  final statesNotifier = ref.read(transientAlertStatesProvider.notifier);
  final notificationNotifier = ref.read(uiNotificationProvider.notifier);
  final targetsDao = ref.read(targetsDaoProvider);

  try {
    // Mark as queued
    await statesNotifier.queue(alert.id);

    // Map TransientType to TargetType
    final targetType = _mapTransientTypeToTargetType(alert.type);

    // Build notes combining all transient info
    final alertNotes = StringBuffer();
    alertNotes.writeln('Transient alert from ${alert.source.name.toUpperCase()}');
    if (alert.classification != null) {
      alertNotes.writeln('Classification: ${alert.classification}');
    }
    if (alert.notes != null) {
      alertNotes.writeln('Alert notes: ${alert.notes}');
    }
    alertNotes.writeln('Queued from transient alert on ${DateTime.now().toIso8601String()}');
    alertNotes.writeln('Discovery time: ${alert.discoveryTime.toIso8601String()}');
    if (alert.sourceUrl != null) {
      alertNotes.writeln('Source URL: ${alert.sourceUrl}');
    }

    // Create target from alert
    final targetCompanion = TargetsCompanion.insert(
      name: alert.name,
      catalogId: Value(alert.id),
      ra: alert.raHours,
      dec: alert.decDegrees,
      objectType: Value(targetType.name),
      magnitude: Value(alert.magnitude),
      isFavorite: const Value(false),
      priority: Value(alert.priority),
      notes: Value(alertNotes.toString()),
    );

    final targetId = await targetsDao.createTarget(targetCompanion);

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

    // Show notification
    notificationNotifier.showSuccess(
      'Queued ${alert.name} for tonight',
      title: 'Transient Queued',
    );

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
  logger.info('Transient alerts refresh triggered', source: 'refreshTransientAlerts');
}

// =============================================================================
// Alert Detail Provider
// =============================================================================

/// Provider for getting a specific alert by ID
final transientAlertByIdProvider =
    Provider.family.autoDispose<TransientAlert?, String>((ref, alertId) {
  final alertsAsync = ref.watch(activeTransientAlertsProvider);
  final alerts = alertsAsync.valueOrNull ?? [];

  try {
    return alerts.firstWhere((a) => a.id == alertId);
  } catch (_) {
    return null;
  }
});
