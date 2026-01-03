import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather/weather_models.dart';
import '../models/equipment/equipment_models.dart';
import 'weather_providers.dart';
import 'equipment_provider.dart';

/// Weather safety status for sequencer integration
enum WeatherSafetyStatus {
  /// OK to continue imaging
  safe,

  /// Should pause/park
  unsafe,

  /// Temporarily ignoring alerts
  snoozed,
}

/// Actions recommended by weather safety system
class WeatherSafetyActions {
  final bool shouldPause;
  final bool shouldPark;
  final bool shouldCloseDome;
  final String? reason;
  final DateTime? resumeCheckTime;

  const WeatherSafetyActions({
    this.shouldPause = false,
    this.shouldPark = false,
    this.shouldCloseDome = false,
    this.reason,
    this.resumeCheckTime,
  });

  static const safe = WeatherSafetyActions();
}

/// State for weather safety
class WeatherSafetyState {
  final WeatherSafetyStatus status;
  final WeatherSafetyActions actions;
  final DateTime? snoozeUntil;
  final AlertLevel currentAlertLevel;

  const WeatherSafetyState({
    required this.status,
    required this.actions,
    this.snoozeUntil,
    required this.currentAlertLevel,
  });

  factory WeatherSafetyState.initial() => WeatherSafetyState(
        status: WeatherSafetyStatus.safe,
        actions: WeatherSafetyActions.safe,
        currentAlertLevel: AlertLevel.clear,
      );

  /// Check if conditions are safe for imaging
  bool get isSafe =>
      status == WeatherSafetyStatus.safe ||
      status == WeatherSafetyStatus.snoozed;

  WeatherSafetyState copyWith({
    WeatherSafetyStatus? status,
    WeatherSafetyActions? actions,
    DateTime? snoozeUntil,
    bool clearSnooze = false,
    AlertLevel? currentAlertLevel,
  }) {
    return WeatherSafetyState(
      status: status ?? this.status,
      actions: actions ?? this.actions,
      snoozeUntil: clearSnooze ? null : (snoozeUntil ?? this.snoozeUntil),
      currentAlertLevel: currentAlertLevel ?? this.currentAlertLevel,
    );
  }
}

/// Notifier for weather safety state
class WeatherSafetyNotifier extends StateNotifier<WeatherSafetyState> {
  final Ref _ref;
  StreamSubscription? _alertSubscription;
  Timer? _snoozeTimer;

  WeatherSafetyNotifier(this._ref) : super(WeatherSafetyState.initial()) {
    _subscribeToAlerts();
  }

  /// Subscribe to weather alert stream and update state based on alerts
  void _subscribeToAlerts() {
    final alertService = _ref.read(weatherAlertServiceProvider);

    _alertSubscription = alertService.alertStream.listen((alert) {
      final settings = _ref.read(weatherSettingsProvider);

      final newState = _processAlert(alert, settings);
      state = newState;
    });
  }

  /// Snooze alerts for specified duration
  void snooze(Duration duration) {
    final snoozeUntil = DateTime.now().add(duration);

    // Cancel existing snooze timer if any
    _snoozeTimer?.cancel();

    // Set snooze state
    state = state.copyWith(
      status: WeatherSafetyStatus.snoozed,
      snoozeUntil: snoozeUntil,
      actions: WeatherSafetyActions.safe,
    );

    // Start timer to end snooze
    _snoozeTimer = Timer(duration, () {
      cancelSnooze();
    });
  }

  /// Cancel snooze early and re-evaluate current conditions
  void cancelSnooze() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    // Re-evaluate current alert with settings
    final alertService = _ref.read(weatherAlertServiceProvider);
    final currentAlert = alertService.currentAlert;
    final settings = _ref.read(weatherSettingsProvider);

    if (currentAlert != null) {
      state = _processAlert(currentAlert, settings).copyWith(clearSnooze: true);
    } else {
      // No alert, return to safe state
      state = state.copyWith(
        status: WeatherSafetyStatus.safe,
        actions: WeatherSafetyActions.safe,
        clearSnooze: true,
      );
    }
  }

  /// Process alert and determine safety status based on settings
  WeatherSafetyState _processAlert(
      WeatherAlert alert, WeatherSettings settings) {
    // If safety disabled, always safe
    if (!settings.weatherSafetyEnabled) {
      return WeatherSafetyState(
        status: WeatherSafetyStatus.safe,
        actions: WeatherSafetyActions.safe,
        currentAlertLevel: alert.level,
      );
    }

    // If snoozed and snooze not expired, remain snoozed
    if (state.status == WeatherSafetyStatus.snoozed &&
        state.snoozeUntil != null &&
        DateTime.now().isBefore(state.snoozeUntil!)) {
      return state.copyWith(currentAlertLevel: alert.level);
    }

    // Evaluate alert level against thresholds
    final alertLevel = alert.level;

    // Clear and watch are considered safe
    if (alertLevel == AlertLevel.clear || alertLevel == AlertLevel.watch) {
      return WeatherSafetyState(
        status: WeatherSafetyStatus.safe,
        actions: WeatherSafetyActions.safe,
        currentAlertLevel: alertLevel,
      );
    }

    // Warning and critical are unsafe
    if (alertLevel == AlertLevel.warning || alertLevel == AlertLevel.critical) {
      return _buildUnsafeState(alert, settings);
    }

    // Default to safe
    return WeatherSafetyState(
      status: WeatherSafetyStatus.safe,
      actions: WeatherSafetyActions.safe,
      currentAlertLevel: alertLevel,
    );
  }

  /// Build unsafe state with appropriate actions
  WeatherSafetyState _buildUnsafeState(
      WeatherAlert alert, WeatherSettings settings) {
    final isCritical = alert.level == AlertLevel.critical;
    final shouldPark = settings.autoParkEnabled;

    // Check if dome is connected
    final domeState = _ref.read(domeStateProvider);
    final isDomeConnected =
        domeState.connectionState == DeviceConnectionState.connected;
    final shouldCloseDome = isCritical && isDomeConnected;

    // Calculate when to check for resume conditions
    final resumeCheckTime = alert.eta?.add(const Duration(minutes: 15));

    final actions = WeatherSafetyActions(
      shouldPause: true,
      shouldPark: shouldPark,
      shouldCloseDome: shouldCloseDome,
      reason: alert.message,
      resumeCheckTime: resumeCheckTime,
    );

    return WeatherSafetyState(
      status: WeatherSafetyStatus.unsafe,
      actions: actions,
      currentAlertLevel: alert.level,
    );
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _snoozeTimer?.cancel();
    super.dispose();
  }
}

/// Provider for weather safety state
final weatherSafetyProvider =
    StateNotifierProvider<WeatherSafetyNotifier, WeatherSafetyState>((ref) {
  return WeatherSafetyNotifier(ref);
});

/// Convenience provider for quick safety check
final isWeatherSafeProvider = Provider<bool>((ref) {
  final safety = ref.watch(weatherSafetyProvider);
  return safety.isSafe;
});
