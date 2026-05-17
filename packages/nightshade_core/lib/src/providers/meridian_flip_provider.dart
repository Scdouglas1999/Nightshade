import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../models/backend/event_types.dart';
import '../models/equipment/equipment_models.dart'
    show DeviceConnectionState, MountState;
import '../models/meridian_flip_settings.dart';
import '../models/meridian_flip_event.dart';
import '../models/sequence/sequence_models.dart' show SequenceExecutionState;
import '../services/logging_service.dart';
import '../services/notification_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'equipment_provider.dart' show mountStateProvider;
import 'sequence_provider.dart' show sequenceExecutionStateProvider;
import 'settings_provider.dart' show appSettingsProvider;

/// Key used to store global meridian flip settings in app_settings table
const _kMeridianFlipSettingsKey = 'meridian_flip_settings';

/// Provider for global meridian flip settings
final globalMeridianFlipSettingsProvider =
    StateNotifierProvider<GlobalMeridianFlipSettingsNotifier, MeridianFlipSettings>((ref) {
  final db = ref.watch(databaseProvider);
  return GlobalMeridianFlipSettingsNotifier(db);
});

/// Notifier for managing global meridian flip settings
///
/// Handles loading and saving meridian flip settings to the app_settings table.
/// These serve as the default settings when no profile-specific overrides exist.
class GlobalMeridianFlipSettingsNotifier extends StateNotifier<MeridianFlipSettings> {
  final NightshadeDatabase _db;

  GlobalMeridianFlipSettingsNotifier(this._db) : super(const MeridianFlipSettings()) {
    _loadSettings();
  }

  /// Load settings from the database
  Future<void> _loadSettings() async {
    try {
      final setting = await (_db.select(_db.appSettings)
            ..where((t) => t.key.equals(_kMeridianFlipSettingsKey)))
          .getSingleOrNull();

      if (setting != null && setting.value.isNotEmpty) {
        final json = jsonDecode(setting.value) as Map<String, dynamic>;
        state = MeridianFlipSettings.fromJson(json);
      }
    } catch (e) {
      developer.log('Failed to load settings: $e', name: 'MeridianFlip', level: 1000);
    }
  }

  /// Update settings and persist to database
  Future<void> updateSettings(MeridianFlipSettings settings) async {
    state = settings;
    await _saveSettings();
  }

  /// Save current settings to the database
  Future<void> _saveSettings() async {
    try {
      final json = jsonEncode(state.toJson());
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _kMeridianFlipSettingsKey,
              value: json,
            ),
          );
    } catch (e) {
      developer.log('Failed to save settings: $e', name: 'MeridianFlip', level: 1000);
    }
  }

  // === Individual Setting Updates ===
  // These allow updating individual settings without replacing the entire object

  /// Update standalone monitoring enabled
  Future<void> setStandaloneMonitoringEnabled(bool enabled) async {
    await updateSettings(state.copyWith(standaloneMonitoringEnabled: enabled));
  }

  /// Update trigger method
  Future<void> setTriggerMethod(MeridianTriggerMethod method) async {
    await updateSettings(state.copyWith(triggerMethod: method));
  }

  /// Update minutes past meridian threshold
  Future<void> setMinutesPastMeridian(double minutes) async {
    await updateSettings(state.copyWith(minutesPastMeridian: minutes));
  }

  /// Update minutes before limit threshold
  Future<void> setMinutesBeforeLimit(double minutes) async {
    await updateSettings(state.copyWith(minutesBeforeLimit: minutes));
  }

  /// Update hour angle threshold
  Future<void> setHourAngleThreshold(double hours) async {
    await updateSettings(state.copyWith(hourAngleThreshold: hours));
  }

  /// Update tracking limit wait minutes
  Future<void> setTrackingLimitWaitMinutes(double minutes) async {
    await updateSettings(state.copyWith(trackingLimitWaitMinutes: minutes));
  }

  /// Update pause guiding before flip
  Future<void> setPauseGuidingBeforeFlip(bool pause) async {
    await updateSettings(state.copyWith(pauseGuidingBeforeFlip: pause));
  }

  /// Update recenter after flip
  Future<void> setRecenterAfterFlip(bool recenter) async {
    await updateSettings(state.copyWith(recenterAfterFlip: recenter));
  }

  /// Update refocus after flip
  Future<void> setRefocusAfterFlip(bool refocus) async {
    await updateSettings(state.copyWith(refocusAfterFlip: refocus));
  }

  /// Update settle time
  Future<void> setSettleTimeSeconds(double seconds) async {
    await updateSettings(state.copyWith(settleTimeSeconds: seconds));
  }

  /// Update resume guiding after flip
  Future<void> setResumeGuidingAfterFlip(bool resume) async {
    await updateSettings(state.copyWith(resumeGuidingAfterFlip: resume));
  }

  /// Update max retries
  Future<void> setMaxRetries(int retries) async {
    await updateSettings(state.copyWith(maxRetries: retries));
  }

  /// Update retry delays
  Future<void> setRetryDelaysSeconds(List<double> delays) async {
    await updateSettings(state.copyWith(retryDelaysSeconds: delays));
  }

  /// Update failure action
  Future<void> setFailureAction(FlipFailureAction action) async {
    await updateSettings(state.copyWith(failureAction: action));
  }

  /// Update sound alert on flip
  Future<void> setSoundAlertOnFlip(bool enabled) async {
    await updateSettings(state.copyWith(soundAlertOnFlip: enabled));
  }

  /// Update push notification on flip
  Future<void> setPushNotificationOnFlip(bool enabled) async {
    await updateSettings(state.copyWith(pushNotificationOnFlip: enabled));
  }

  /// Reset settings to defaults
  Future<void> resetToDefaults() async {
    await updateSettings(const MeridianFlipSettings());
  }
}

/// Provider that returns effective meridian flip settings
/// (profile overrides merged with global defaults)
///
/// This provider watches both the global settings and the active equipment profile.
/// If the active profile has meridian flip overrides, they are merged with the
/// global defaults, with profile values taking precedence.
final effectiveMeridianFlipSettingsProvider = Provider<MeridianFlipSettings>((ref) {
  final global = ref.watch(globalMeridianFlipSettingsProvider);
  final activeProfile = ref.watch(activeProfileProvider).valueOrNull;

  if (activeProfile == null) {
    return global;
  }

  // Check if profile has overrides
  final overridesJson = activeProfile.meridianFlipOverrides;
  if (overridesJson == null || overridesJson.isEmpty) {
    return global;
  }

  try {
    final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
    // Merge overrides with global defaults
    final globalJson = global.toJson();
    final merged = {...globalJson, ...overrides};
    return MeridianFlipSettings.fromJson(merged);
  } catch (e) {
    developer.log('Failed to parse profile overrides: $e', name: 'MeridianFlip', level: 1000);
    return global;
  }
});

/// Stream of meridian flip events during flip execution.
///
/// Listens to the backend event stream for equipment events with
/// meridian-flip-related event types and maps them to [MeridianFlipEvent].
final meridianFlipEventStreamProvider = StreamProvider<MeridianFlipEvent?>((ref) {
  final backend = ref.watch(backendProvider);

  return backend.eventStream
      .where((event) =>
          event.category == EventCategory.equipment &&
          event.eventType.startsWith('MeridianFlip'))
      .map((event) {
    try {
      return MeridianFlipEvent.fromJson(event.data);
    } catch (e) {
      // If parsing fails, emit null rather than crashing the stream
      return null;
    }
  });
});

/// Current flip state for UI
///
/// Represents the current state of a meridian flip operation.
enum FlipExecutionState {
  /// No flip is in progress
  idle,

  /// Flip is currently executing
  executing,

  /// Flip failed and is being retried
  retrying,

  /// Flip completed successfully
  completed,

  /// Flip failed after all retries
  failed,

  /// Flip was aborted by user
  aborted,
}

/// Provider tracking current flip execution state
///
/// UI components can watch this to show appropriate status indicators,
/// enable/disable controls, and display progress information.
final flipExecutionStateProvider = StateProvider<FlipExecutionState>((ref) {
  return FlipExecutionState.idle;
});

/// Provider for the current flip attempt number during retries
///
/// Returns 0 when no flip is in progress, or the current attempt number
/// (1-indexed) during flip execution.
final flipCurrentAttemptProvider = StateProvider<int>((ref) => 0);

/// Provider for the current flip step being executed
///
/// Returns null when no flip is in progress, or the current FlipStep
/// during flip execution.
final flipCurrentStepProvider = StateProvider<FlipStep?>((ref) => null);

/// Provider for flip progress percentage (0-100)
final flipProgressProvider = StateProvider<int>((ref) => 0);

/// Provider for the last flip error message
final flipLastErrorProvider = StateProvider<String?>((ref) => null);

/// Provider indicating if a flip is currently in progress
final isFlipInProgressProvider = Provider<bool>((ref) {
  final state = ref.watch(flipExecutionStateProvider);
  return state == FlipExecutionState.executing || state == FlipExecutionState.retrying;
});

/// StateNotifier that resets flip execution state when the mount disconnects.
///
/// If a meridian flip is in progress (executing or retrying) and the mount
/// disconnects, the flip can never complete. This notifier listens to the mount
/// connection state and resets the flip providers to prevent the UI from
/// being stuck in a "flipping" state indefinitely.
///
/// Uses ref.listen in its constructor instead of mutating state in a Provider
/// build function, which would be a Riverpod violation.
class MeridianFlipDisconnectGuard extends StateNotifier<void> {
  final Ref _ref;

  MeridianFlipDisconnectGuard(this._ref) : super(null) {
    _ref.listen<MountState>(mountStateProvider, (prev, next) {
      if (next.connectionState == DeviceConnectionState.disconnected) {
        final flipState = _ref.read(flipExecutionStateProvider);
        if (flipState == FlipExecutionState.executing ||
            flipState == FlipExecutionState.retrying) {
          developer.log(
            'Mount disconnected during meridian flip - aborting flip state',
            name: 'MeridianFlip',
            level: 900,
          );
          _ref.read(flipExecutionStateProvider.notifier).state =
              FlipExecutionState.aborted;
          _ref.read(flipCurrentStepProvider.notifier).state = null;
          _ref.read(flipProgressProvider.notifier).state = 0;
          _ref.read(flipCurrentAttemptProvider.notifier).state = 0;
          _ref.read(flipLastErrorProvider.notifier).state =
              'Meridian flip aborted: mount disconnected';
        }
      }
    });
  }
}

/// Provider that resets flip execution state when the mount disconnects.
///
/// This provider must be watched (e.g., by the app shell) so it stays alive.
final meridianFlipDisconnectGuardProvider =
    StateNotifierProvider<MeridianFlipDisconnectGuard, void>((ref) {
  return MeridianFlipDisconnectGuard(ref);
});

/// Provider for checking if settings indicate flip should be enabled
///
/// This combines the global enable setting with the effective settings
/// to determine if auto-flip should be active.
final isMeridianFlipEnabledProvider = Provider<bool>((ref) {
  // Check if any trigger conditions are configured (non-zero thresholds)
  final settings = ref.watch(effectiveMeridianFlipSettingsProvider);

  // A trigger method is always selected, but check if the threshold is sensible
  switch (settings.triggerMethod) {
    case MeridianTriggerMethod.minutesPastMeridian:
      return settings.minutesPastMeridian >= 0;
    case MeridianTriggerMethod.minutesBeforeLimit:
      return settings.minutesBeforeLimit >= 0;
    case MeridianTriggerMethod.hourAngleThreshold:
      return settings.hourAngleThreshold >= 0;
    case MeridianTriggerMethod.onTrackingLimitHit:
      return true; // Always enabled when selected (wait time >= 0 is valid)
  }
});

/// Compute Local Sidereal Time (hours) for the given UTC instant and observer
/// longitude (degrees, east positive).
///
/// Why: nightshade_core is the wrong place for a heavy planetarium dep, and
/// the scheduler engine already uses an identical inline computation. Lifting
/// it to a shared helper would be a larger refactor; duplicating the proven
/// formula here keeps the change local. See
/// `scheduler_engine.dart:_localSiderealTime` — the algorithm is the same.
double computeLocalSiderealTimeHours(DateTime utc, double longitudeDeg) {
  final t = utc.toUtc();
  int y = t.year;
  int m = t.month;
  final d = t.day +
      t.hour / 24.0 +
      t.minute / 1440.0 +
      t.second / 86400.0 +
      t.millisecond / 86400000.0;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  final jd = (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      d +
      b -
      1524.5;
  final tt = (jd - 2451545.0) / 36525.0;
  var gmst = 280.46061837 +
      360.98564736629 * (jd - 2451545.0) +
      0.000387933 * tt * tt -
      tt * tt * tt / 38710000.0;
  gmst = gmst % 360.0;
  if (gmst < 0) gmst += 360.0;
  var lst = gmst / 15.0 + longitudeDeg / 15.0;
  while (lst < 0) {
    lst += 24.0;
  }
  while (lst >= 24.0) {
    lst -= 24.0;
  }
  return lst;
}

/// Compute the mount's hour angle in hours, normalized to (-12, +12].
///
/// HA = LST - RA, where positive HA means the target is west of the meridian
/// (i.e., already crossed).
double computeHourAngleHours(double raHours, double lstHours) {
  var ha = lstHours - raHours;
  while (ha > 12.0) {
    ha -= 24.0;
  }
  while (ha <= -12.0) {
    ha += 24.0;
  }
  return ha;
}

/// Result of a standalone-monitor poll, exposed so tests can validate the
/// decision logic without faking timers.
enum MeridianMonitorDecision {
  /// Monitoring is off, mount missing, or trigger settings disable it.
  inactive,

  /// Conditions evaluated but no trigger fired.
  noTrigger,

  /// Cooldown active from a recent trigger fire.
  cooldown,

  /// A sequence is running — let the sequencer own the flip.
  sequenceRunning,

  /// Trigger condition met and an alert was emitted.
  triggered,
}

/// Watcher that fires meridian-flip alerts when standalone monitoring is on
/// and the mount crosses the configured trigger condition.
///
/// Why this exists (audit-handoff §1.2):
///   The Sequencer Settings -> Meridian Flip section exposes a
///   `standaloneMonitoringEnabled` toggle. Prior to this wire-up the toggle
///   flipped a database row that nothing watched. Operators reasonably expect
///   that enabling "monitor meridian even when no sequence is running"
///   produces an observable effect: when the mount approaches the meridian,
///   *something* must happen.
///
/// Why this implementation alerts rather than auto-flips:
///   The Rust meridian flip executor is only reachable through the sequencer
///   today — there is no `api_perform_meridian_flip` bridge call. Hijacking
///   the user's loaded sequence to inject a one-node flip would silently
///   destroy in-progress edits, which is a worse failure mode than missing
///   a flip. So when the trigger fires we surface it via:
///     1. `flipExecutionStateProvider` -> `executing` (UI banner + log
///        timeline pick this up via the existing event subscribers).
///     2. `NotificationService.notifyMeridianFlip` — routes through the
///        operator-configured Discord / Pushover / push channels per the
///        `pushNotificationOnFlip` setting.
///     3. `LoggingService.warning` so the trigger is captured in diagnostics.
///   A cooldown prevents re-firing while the operator is acting on the
///   notification. When a future bridge call exposes a standalone flip path,
///   the alert step can be replaced with the actual flip without disturbing
///   the rest of this watcher.
class MeridianFlipStandaloneMonitor extends StateNotifier<void> {
  final Ref _ref;
  Timer? _pollTimer;
  DateTime? _lastTriggerAt;

  /// Minimum interval between trigger fires.
  ///
  /// Why: the Rust sequencer trigger has a 10-minute cooldown
  /// (triggers.rs:1268). Match it so a single meridian crossing doesn't
  /// spam the operator with notifications while they are walking to the
  /// scope to act on the alert.
  static const Duration _cooldown = Duration(minutes: 10);

  /// Poll cadence while monitoring is active.
  ///
  /// Why: a 30-second cadence matches the sequencer's trigger evaluation
  /// frequency — finer resolution buys nothing because meridian crossings
  /// move slowly (mount sidereal rate is 15"/sec).
  static const Duration _pollInterval = Duration(seconds: 30);

  MeridianFlipStandaloneMonitor(this._ref) : super(null) {
    // Why: react to settings changes (toggle on/off) immediately rather than
    // waiting for the next poll. ref.listen survives across rebuilds.
    _ref.listen<MeridianFlipSettings>(globalMeridianFlipSettingsProvider,
        (prev, next) {
      if (prev?.standaloneMonitoringEnabled != next.standaloneMonitoringEnabled) {
        _reconcileTimer(next.standaloneMonitoringEnabled);
      }
    });
    final initial = _ref.read(globalMeridianFlipSettingsProvider);
    _reconcileTimer(initial.standaloneMonitoringEnabled);
  }

  void _reconcileTimer(bool enabled) {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!enabled) {
      return;
    }
    _pollTimer = Timer.periodic(_pollInterval, (_) => evaluateOnce());
  }

  /// Public for tests — runs a single poll cycle and returns the decision.
  MeridianMonitorDecision evaluateOnce() {
    final settings = _ref.read(globalMeridianFlipSettingsProvider);
    if (!settings.standaloneMonitoringEnabled) {
      return MeridianMonitorDecision.inactive;
    }

    final execState = _ref.read(sequenceExecutionStateProvider);
    if (execState == SequenceExecutionState.running ||
        execState == SequenceExecutionState.paused) {
      // Why: when a sequence is running the in-sequence MeridianFlipNode (or
      // the always-on `meridian_flip` Rust trigger) owns the decision. A
      // parallel standalone alert would double-fire.
      return MeridianMonitorDecision.sequenceRunning;
    }

    if (_lastTriggerAt != null &&
        DateTime.now().difference(_lastTriggerAt!) < _cooldown) {
      return MeridianMonitorDecision.cooldown;
    }

    final mount = _ref.read(mountStateProvider);
    if (mount.connectionState != DeviceConnectionState.connected ||
        mount.isParked ||
        !mount.isTracking ||
        mount.ra == null) {
      return MeridianMonitorDecision.inactive;
    }

    final appSettings = _ref.read(appSettingsProvider).valueOrNull;
    if (appSettings == null ||
        (appSettings.latitude == 0.0 && appSettings.longitude == 0.0)) {
      // Why: HA computation needs a real longitude. Refuse to alert from a
      // 0,0 default — that would be a spurious notification.
      return MeridianMonitorDecision.inactive;
    }

    final lst = computeLocalSiderealTimeHours(
      DateTime.now().toUtc(),
      appSettings.longitude,
    );
    final ha = computeHourAngleHours(mount.ra!, lst);

    final fired = _evaluateTrigger(settings, ha);
    if (!fired) {
      return MeridianMonitorDecision.noTrigger;
    }

    _emitAlert(settings, ha);
    _lastTriggerAt = DateTime.now();
    return MeridianMonitorDecision.triggered;
  }

  bool _evaluateTrigger(MeridianFlipSettings settings, double ha) {
    switch (settings.triggerMethod) {
      case MeridianTriggerMethod.minutesPastMeridian:
        // Positive HA means past meridian (west of zenith).
        if (ha <= 0) return false;
        final minutesPast = ha * 60.0;
        return minutesPast >= settings.minutesPastMeridian;
      case MeridianTriggerMethod.hourAngleThreshold:
        if (ha <= 0) return false;
        return ha >= settings.hourAngleThreshold;
      case MeridianTriggerMethod.minutesBeforeLimit:
        // Why: requires mount-advertised tracking-limit time, which is only
        // surfaced inside the Rust sequencer state. Standalone Dart side
        // has no equivalent today — explicitly skip rather than approximate.
        return false;
      case MeridianTriggerMethod.onTrackingLimitHit:
        // Why: tracking-limit detection lives in the Rust trigger evaluator
        // (triggers.rs::looks_like_tracking_limit_hit) and depends on state
        // history the standalone Dart monitor doesn't carry. Skip.
        return false;
    }
  }

  void _emitAlert(MeridianFlipSettings settings, double hourAngleHours) {
    _ref.read(flipExecutionStateProvider.notifier).state =
        FlipExecutionState.executing;
    _ref.read(flipCurrentStepProvider.notifier).state = null;
    _ref.read(flipProgressProvider.notifier).state = 0;
    _ref.read(flipLastErrorProvider.notifier).state = null;

    final logger = _ref.read(loggingServiceProvider);
    logger.warning(
      'Standalone meridian monitor: trigger fired '
      '(method=${settings.triggerMethod.name}, HA=${hourAngleHours.toStringAsFixed(3)}h)',
      source: 'MeridianFlipStandaloneMonitor',
      fields: {
        'triggerMethod': settings.triggerMethod.name,
        'hourAngleHours': hourAngleHours,
        'pushNotificationOnFlip': settings.pushNotificationOnFlip,
        'soundAlertOnFlip': settings.soundAlertOnFlip,
      },
    );

    if (settings.pushNotificationOnFlip) {
      // Why: the operator opted into push notifications for flip events.
      // Route through NotificationService so Discord / Pushover / system push
      // all honor the toggle. Errors here are reported but never propagate —
      // a missed notification must not stall the monitor.
      unawaited(_ref
          .read(notificationServiceProvider)
          .notifyMeridianFlip(isStarting: true)
          .catchError((Object e, StackTrace s) {
        logger.error(
          'Failed to dispatch meridian flip notification: $e',
          source: 'MeridianFlipStandaloneMonitor',
        );
        return false;
      }));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}

/// Standalone meridian-flip watcher.
///
/// Must be watched (e.g., by the app shell) so the timer survives provider
/// invalidation. Operates only while
/// `globalMeridianFlipSettings.standaloneMonitoringEnabled` is true.
final meridianFlipStandaloneMonitorProvider =
    StateNotifierProvider<MeridianFlipStandaloneMonitor, void>((ref) {
  return MeridianFlipStandaloneMonitor(ref);
});
