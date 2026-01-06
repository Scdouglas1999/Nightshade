import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../models/meridian_flip_settings.dart';
import '../models/meridian_flip_event.dart';
import 'database_provider.dart';

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
      print('[MERIDIAN] Failed to load settings: $e');
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
      print('[MERIDIAN] Failed to save settings: $e');
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
    print('[MERIDIAN] Failed to parse profile overrides: $e');
    return global;
  }
});

/// Stream of meridian flip events during flip execution
///
/// This stream will be connected to the Rust event stream via the backend
/// when the flip executor is running. It provides real-time updates about
/// flip progress, step completion, errors, and retries.
final meridianFlipEventStreamProvider = StreamProvider<MeridianFlipEvent?>((ref) {
  // This will be connected to the Rust event stream via the backend
  // when the meridian flip executor is implemented in Task 6.
  // For now, return an empty stream that will be replaced when the
  // backend integration is complete.
  return const Stream.empty();
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
  }
});
