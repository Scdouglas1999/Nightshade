import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather/weather_models.dart';
import '../models/equipment/equipment_models.dart';
import '../models/settings/app_settings.dart';
import '../services/scheduler/sky_calculations.dart';
import 'weather_providers.dart';
import 'equipment_provider.dart';
import 'settings_provider.dart';
import 'ui_notification_provider.dart';
import 'backend_provider.dart';

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

/// Source of safety data
enum SafetyDataSource {
  /// Data from external weather API (Open-Meteo, radar, etc.)
  weatherApi,

  /// Data from connected hardware weather device
  hardwareWeather,

  /// Data from connected safety monitor device
  safetyMonitor,

  /// Combined evaluation of multiple sources
  combined,

  /// No data source available (using fail mode)
  unavailable,
}

/// State for weather safety
class WeatherSafetyState {
  final WeatherSafetyStatus status;
  final WeatherSafetyActions actions;
  final DateTime? snoozeUntil;
  final AlertLevel currentAlertLevel;
  final SafetyDataSource dataSource;
  final bool hardwareWeatherSafe;
  final bool safetyMonitorSafe;
  final bool apiWeatherSafe;
  final String? failModeWarning;
  final DateTime? lastEvaluation;

  const WeatherSafetyState({
    required this.status,
    required this.actions,
    this.snoozeUntil,
    required this.currentAlertLevel,
    this.dataSource = SafetyDataSource.weatherApi,
    this.hardwareWeatherSafe = true,
    this.safetyMonitorSafe = true,
    this.apiWeatherSafe = true,
    this.failModeWarning,
    this.lastEvaluation,
  });

  factory WeatherSafetyState.initial() => WeatherSafetyState(
        status: WeatherSafetyStatus.safe,
        actions: WeatherSafetyActions.safe,
        currentAlertLevel: AlertLevel.clear,
        lastEvaluation: DateTime.now(),
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
    SafetyDataSource? dataSource,
    bool? hardwareWeatherSafe,
    bool? safetyMonitorSafe,
    bool? apiWeatherSafe,
    String? failModeWarning,
    bool clearWarning = false,
    DateTime? lastEvaluation,
  }) {
    return WeatherSafetyState(
      status: status ?? this.status,
      actions: actions ?? this.actions,
      snoozeUntil: clearSnooze ? null : (snoozeUntil ?? this.snoozeUntil),
      currentAlertLevel: currentAlertLevel ?? this.currentAlertLevel,
      dataSource: dataSource ?? this.dataSource,
      hardwareWeatherSafe: hardwareWeatherSafe ?? this.hardwareWeatherSafe,
      safetyMonitorSafe: safetyMonitorSafe ?? this.safetyMonitorSafe,
      apiWeatherSafe: apiWeatherSafe ?? this.apiWeatherSafe,
      failModeWarning:
          clearWarning ? null : (failModeWarning ?? this.failModeWarning),
      lastEvaluation: lastEvaluation ?? this.lastEvaluation,
    );
  }
}

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Notifier for weather safety state
class WeatherSafetyNotifier extends StateNotifier<WeatherSafetyState> {
  final Ref _ref;
  StreamSubscription? _alertSubscription;
  Timer? _snoozeTimer;
  Timer? _periodicEvalTimer;
  bool _resumeInFlight = false;

  /// Periodic re-evaluation interval (5 minutes)
  static const _evaluationInterval = Duration(minutes: 5);
  static const _parkBeforeDawnLeadTime = Duration(minutes: 30);

  WeatherSafetyNotifier(this._ref) : super(WeatherSafetyState.initial()) {
    _subscribeToAlerts();
    _startPeriodicEvaluation();
  }

  /// Start periodic re-evaluation timer independent of weather screen
  void _startPeriodicEvaluation() {
    _periodicEvalTimer?.cancel();
    _periodicEvalTimer = Timer.periodic(_evaluationInterval, (_) {
      if (!mounted) return;
      _evaluateAllSources();
    });
    // Also run initial evaluation
    _evaluateAllSources();
  }

  /// Evaluate all safety sources (API weather, hardware weather, safety monitor)
  void _evaluateAllSources() {
    if (!mounted) return;
    final weatherSettings = _ref.read(weatherSettingsProvider);
    final appSettings = _ref.read(appSettingsProvider).valueOrNull;
    final failMode = appSettings?.safetyFailMode ?? SafetyFailMode.failClosed;
    final parkPolicyEnabled = appSettings?.parkOnUnsafeWeather ?? true;
    final shouldAutoPark = parkPolicyEnabled && weatherSettings.autoParkEnabled;
    final dawnParkDue = _isParkBeforeDawnDue(appSettings);
    var shouldShowFailModeWarning = false;

    // Get hardware weather device state
    final weatherDeviceState = _ref.read(weatherStateProvider);
    final isWeatherDeviceConnected =
        weatherDeviceState.connectionState == DeviceConnectionState.connected;

    // Get safety monitor device state
    final safetyMonitorState = _ref.read(safetyMonitorStateProvider);
    final isSafetyMonitorConnected =
        safetyMonitorState.connectionState == DeviceConnectionState.connected;

    // Evaluate hardware weather device
    bool hardwareWeatherSafe = true;
    if (isWeatherDeviceConnected) {
      // Check if conditions are safe based on hardware weather data
      hardwareWeatherSafe = _evaluateHardwareWeather(weatherDeviceState);
    }

    // Evaluate safety monitor
    bool safetyMonitorSafe = true;
    if (isSafetyMonitorConnected) {
      safetyMonitorSafe = safetyMonitorState.isSafe;
    }

    // Get API weather status
    final alertService = _ref.read(weatherAlertServiceProvider);
    final currentAlert = alertService.currentAlert;
    final apiWeatherSafe = currentAlert == null ||
        currentAlert.level == AlertLevel.clear ||
        currentAlert.level == AlertLevel.watch;

    // Determine data source
    SafetyDataSource dataSource;
    if (isWeatherDeviceConnected || isSafetyMonitorConnected) {
      dataSource = SafetyDataSource.combined;
    } else {
      dataSource = SafetyDataSource.weatherApi;
    }

    // Check for failures requiring fail mode handling
    String? failModeWarning;
    bool useFailMode = false;

    // If no data sources are available, apply fail mode
    if (!isWeatherDeviceConnected &&
        !isSafetyMonitorConnected &&
        currentAlert == null) {
      useFailMode = true;
      dataSource = SafetyDataSource.unavailable;
      failModeWarning = 'No weather data sources available';
    }

    // Combine all sources for final safety determination
    final allSourcesSafe =
        hardwareWeatherSafe && safetyMonitorSafe && apiWeatherSafe;

    WeatherSafetyStatus finalStatus;
    WeatherSafetyActions finalActions;

    final previousStatus = state.status;

    if (state.status == WeatherSafetyStatus.snoozed &&
        state.snoozeUntil != null &&
        DateTime.now().isBefore(state.snoozeUntil!)) {
      // Keep snoozed state
      finalStatus = WeatherSafetyStatus.snoozed;
      finalActions = WeatherSafetyActions.safe;
    } else if (!weatherSettings.weatherSafetyEnabled) {
      // Safety disabled
      finalStatus = WeatherSafetyStatus.safe;
      finalActions = WeatherSafetyActions.safe;
    } else if (useFailMode) {
      switch (failMode) {
        case SafetyFailMode.failClosed:
          // Most conservative: treat unavailable data as unsafe, block operations.
          finalStatus = WeatherSafetyStatus.unsafe;
          finalActions = WeatherSafetyActions(
            shouldPause: true,
            shouldPark: shouldAutoPark,
            reason: failModeWarning,
          );
          break;
        case SafetyFailMode.failOpen:
          // Permissive: treat unavailable data as safe, allow operations to continue.
          finalStatus = WeatherSafetyStatus.safe;
          finalActions = WeatherSafetyActions.safe;
          break;
        case SafetyFailMode.warnOnly:
          // Permissive with notification: treat as safe but emit a UI warning.
          finalStatus = WeatherSafetyStatus.safe;
          finalActions = WeatherSafetyActions.safe;
          shouldShowFailModeWarning = true;
          break;
      }
    } else if (allSourcesSafe) {
      finalStatus = WeatherSafetyStatus.safe;
      finalActions = WeatherSafetyActions.safe;
    } else {
      // Determine which source caused unsafe
      String reason;
      if (!safetyMonitorSafe) {
        reason = 'Safety monitor reports unsafe conditions';
      } else if (!hardwareWeatherSafe) {
        reason = 'Weather device reports unsafe conditions';
      } else {
        reason = currentAlert?.message ?? 'Unsafe weather conditions detected';
      }

      finalStatus = WeatherSafetyStatus.unsafe;
      finalActions = WeatherSafetyActions(
        shouldPause: true,
        shouldPark: shouldAutoPark,
        shouldCloseDome: _shouldCloseDome(currentAlert),
        reason: reason,
        resumeCheckTime: currentAlert?.eta?.add(const Duration(minutes: 15)),
      );
    }

    if (dawnParkDue && finalStatus == WeatherSafetyStatus.safe) {
      finalStatus = WeatherSafetyStatus.unsafe;
      finalActions = WeatherSafetyActions(
        shouldPause: true,
        shouldPark: shouldAutoPark,
        shouldCloseDome: shouldAutoPark,
        reason: 'Astronomical dawn is approaching',
      );
    }

    state = state.copyWith(
      status: finalStatus,
      actions: finalActions,
      currentAlertLevel: currentAlert?.level ?? AlertLevel.clear,
      dataSource: dataSource,
      hardwareWeatherSafe: hardwareWeatherSafe,
      safetyMonitorSafe: safetyMonitorSafe,
      apiWeatherSafe: apiWeatherSafe,
      failModeWarning: failModeWarning,
      lastEvaluation: DateTime.now(),
    );

    if (shouldShowFailModeWarning) {
      Future<void>.microtask(() {
        if (!mounted) return;
        _ref.read(uiNotificationProvider.notifier).showWarning(
              failModeWarning ?? 'No weather data sources available',
              title: 'Weather Safety',
              duration: const Duration(seconds: 10),
            );
      });
    }

    if (previousStatus == WeatherSafetyStatus.unsafe &&
        finalStatus == WeatherSafetyStatus.safe &&
        weatherSettings.autoResumeEnabled) {
      unawaited(_autoResumeAfterWeatherClear());
    }
  }

  bool _isParkBeforeDawnDue(AppSettingsState? appSettings) {
    if (appSettings == null || !appSettings.parkBeforeDawn) return false;
    final now = DateTime.now();
    final twilight = SkyCalculations.computeTwilight(
      noonLocal: DateTime(now.year, now.month, now.day, 12),
      latitudeDegrees: appSettings.latitude,
      longitudeDegrees: appSettings.longitude,
      kind: TwilightKind.astronomical,
    );
    final dawn = twilight.morningStart?.toLocal();
    if (dawn == null || now.isAfter(dawn)) return false;
    return dawn.difference(now) <= _parkBeforeDawnLeadTime;
  }

  Future<void> _autoResumeAfterWeatherClear() async {
    if (_resumeInFlight) return;
    _resumeInFlight = true;
    try {
      final backend = _ref.read(backendProvider);
      final mount = _ref.read(mountStateProvider);
      if (mount.connectionState == DeviceConnectionState.connected &&
          mount.deviceId != null &&
          mount.isParked) {
        await backend.mountUnpark(mount.deviceId!);
      }
      await backend.sequencerResume();
      if (!mounted) return;
      _ref.read(uiNotificationProvider.notifier).showInfo(
            'Weather is safe again; sequence resume was requested.',
            title: 'Weather Safety',
            duration: const Duration(seconds: 8),
          );
    } catch (e) {
      if (!mounted) return;
      _ref.read(uiNotificationProvider.notifier).showWarning(
            'Weather cleared, but automatic resume failed: $e',
            title: 'Weather Safety',
            duration: const Duration(seconds: 10),
          );
    } finally {
      _resumeInFlight = false;
    }
  }

  /// Evaluate hardware weather device for safety
  bool _evaluateHardwareWeather(WeatherState weatherState) {
    final settings = _ref.read(weatherSettingsProvider);
    // Check various weather metrics if available
    if (weatherState.humidity != null &&
        weatherState.humidity! > settings.maxHumidityPercent) {
      return false; // Too humid
    }
    if (weatherState.windSpeed != null &&
        weatherState.windSpeed! > settings.maxWindSpeedKph) {
      return false; // Too windy
    }
    if (weatherState.rainRate != null && weatherState.rainRate! > 0) {
      return false; // Any rain is unsafe
    }
    if (weatherState.cloudCover != null &&
        weatherState.cloudCover! > settings.maxCloudCoverPercent) {
      return false; // Too cloudy
    }
    return true;
  }

  /// Determine if dome should be closed
  bool _shouldCloseDome(WeatherAlert? alert) {
    if (alert == null || alert.level != AlertLevel.critical) {
      return false;
    }
    final domeState = _ref.read(domeStateProvider);
    return domeState.connectionState == DeviceConnectionState.connected;
  }

  /// Subscribe to weather alert stream and update state based on alerts
  void _subscribeToAlerts() {
    final alertService = _ref.read(weatherAlertServiceProvider);

    _alertSubscription = alertService.alertStream.listen((alert) {
      if (!mounted) return;
      // Re-evaluate all sources when API alert changes
      _evaluateAllSources();
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
      if (!mounted) return;
      cancelSnooze();
    });
  }

  /// Cancel snooze early and re-evaluate current conditions
  void cancelSnooze() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    // Clear snooze and re-evaluate all sources
    state = state.copyWith(clearSnooze: true);
    _evaluateAllSources();
  }

  /// Force immediate re-evaluation of all safety sources
  void forceEvaluation() {
    _evaluateAllSources();
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _snoozeTimer?.cancel();
    _periodicEvalTimer?.cancel();
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
