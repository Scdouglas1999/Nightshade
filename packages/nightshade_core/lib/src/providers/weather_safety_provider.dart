import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather/weather_models.dart';
import '../models/equipment/equipment_models.dart';
import '../models/settings/app_settings.dart';
import '../models/sequence/sequence_models.dart' show ConditionsScoreWeights;
import '../services/scheduler/sky_calculations.dart';
import '../services/adaptive_swap_service.dart';
import '../services/safe_rig_service.dart';
import 'imaging_provider.dart';
import 'science_provider.dart';
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
  Timer? _resumeDelayTimer;
  // Wave 5 Agent 4 — periodic push of the cloud-motion analyzer output to
  // the Rust executor. Independent of the 5-min evaluation tick so the
  // Rust-side cloud-aware triggers see fresh data even between full
  // re-evaluations.
  Timer? _cloudMotionPushTimer;
  Timer? _adaptiveConditionsPushTimer;
  bool _resumeInFlight = false;

  /// Latch ensuring the safe-the-rig enforcement fires exactly once per
  /// unsafe episode. Set when we enforce on the safe -> unsafe transition;
  /// cleared when conditions return to safe. Without it, every 5-minute
  /// periodic re-evaluation while still unsafe would re-pause/re-park an
  /// already-safed rig (and re-spam the critical notification).
  bool _safeRigEnforced = false;
  bool _enforceInFlight = false;

  /// Periodic re-evaluation interval (5 minutes)
  static const _evaluationInterval = Duration(minutes: 5);
  static const _parkBeforeDawnLeadTime = Duration(minutes: 30);

  /// Wave 5 Agent 4 — push cadence for cloud-motion data into the Rust
  /// executor. 60 seconds matches the brief's "every 60s say".
  static const _cloudMotionPushInterval = Duration(seconds: 60);
  static const _adaptiveConditionsPushInterval = Duration(seconds: 30);

  /// Why: when weather first reads "safe" after an unsafe stretch we wait a
  /// hold-off period before unparking. Astronomical conditions are noisy —
  /// a transient cloud break can read as "safe" for a single sample before
  /// the front re-arrives, and unparking immediately can leave the rig
  /// mid-recovery when the next gust/cloud hits. Default 5 minutes matches
  /// the periodic re-evaluation cadence so we have at least one confirmation
  /// sample before committing to the resume.
  static const _autoResumeHoldoff = Duration(minutes: 5);

  WeatherSafetyNotifier(this._ref) : super(WeatherSafetyState.initial()) {
    _subscribeToAlerts();
    _startPeriodicEvaluation();
    // Wave 5 Agent 4 — start the cloud-motion forwarding loop so the Rust
    // sequencer's cloud-aware triggers see live data the first time the
    // notifier is constructed (typically at app launch).
    _startCloudMotionPush();
    _startAdaptiveConditionsPush();
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

    // Defense-in-depth (full-night audit 2026-06-04): push this overall verdict
    // into the Rust executor so the in-sequencer `WeatherUnsafe` trigger reacts
    // even on a rig with no hardware safety device (where the executor's
    // `weather_safe` poll would otherwise stay at its default). The Dart SafeRig
    // enforcement above is the primary path; this is the redundant in-sequencer
    // layer. `unsafe` => abort; anything else (safe / disabled / snoozed) => the
    // operator's effective verdict is "do not abort on weather", so we report
    // SAFE — the Rust evaluator ORs this with the hardware reading, so a
    // hardware-unsafe device still aborts regardless.
    unawaited(
      _pushWeatherVerdict(finalStatus == WeatherSafetyStatus.unsafe),
    );

    if (previousStatus == WeatherSafetyStatus.unsafe &&
        finalStatus == WeatherSafetyStatus.safe &&
        weatherSettings.autoResumeEnabled) {
      _scheduleAutoResume();
    } else if (finalStatus == WeatherSafetyStatus.unsafe) {
      // Why: if conditions re-degrade during the hold-off window we cancel
      // the pending resume so we don't unpark into renewed unsafe weather.
      _cancelPendingAutoResume();
    }

    // Enforce the computed safety actions on the hardware. Before this the
    // actions were COMPUTED but never EXECUTED — every consumer was UI-only,
    // so an unattended rig kept tracking/exposing into unsafe weather. We
    // enforce on the *transition into* unsafe (latched once per episode) so
    // the running sequence is paused, the mount parked, and the dome closed
    // exactly once — not re-fired on every 5-minute re-evaluation while the
    // weather stays bad.
    if (finalStatus == WeatherSafetyStatus.unsafe) {
      if (!_safeRigEnforced) {
        _safeRigEnforced = true;
        unawaited(_enforceSafetyActions(finalActions));
      }
    } else if (finalStatus == WeatherSafetyStatus.safe) {
      // Episode over (or never started) — re-arm enforcement for the next one.
      _safeRigEnforced = false;
    }
    // Snoozed: leave the latch as-is. A snooze means the operator explicitly
    // suppressed enforcement; if it expires back to unsafe the latch state
    // already reflects whether we enforced for this episode.
  }

  /// Execute the computed weather-safety actions on the hardware via the
  /// shared [SafeRigService]. Idempotent enough to be safe even if the latch
  /// were bypassed: SafeRig skips an already-parked mount / already-closed
  /// dome. Fail-closed: SafeRig throws on partial failure and surfaces a
  /// CRITICAL notification; we additionally log a warning banner here so the
  /// operator sees the weather-safety framing.
  Future<void> _enforceSafetyActions(WeatherSafetyActions actions) async {
    if (_enforceInFlight) return;
    _enforceInFlight = true;
    try {
      if (!actions.shouldPause &&
          !actions.shouldPark &&
          !actions.shouldCloseDome) {
        return;
      }
      final safeRig = _ref.read(safeRigServiceProvider);
      await safeRig.safeTheRig(
        reason: actions.reason ?? 'Weather turned unsafe',
        park: actions.shouldPark,
        closeDome: actions.shouldCloseDome,
        // Cover follows the dome decision: if conditions warrant closing the
        // dome shutter they also warrant closing a flip-flat / cover.
        closeCover: actions.shouldCloseDome,
      );
    } catch (e) {
      // SafeRig already posted a CRITICAL notification with the per-step
      // failures; add the weather-safety context so the operator knows what
      // tripped it. Do not rethrow — the periodic evaluator must keep running.
      if (!mounted) return;
      _ref.read(uiNotificationProvider.notifier).showError(
            'Weather safety enforcement did not fully complete: $e',
            title: 'Weather Safety',
            duration: const Duration(seconds: 15),
          );
    } finally {
      _enforceInFlight = false;
    }
  }

  void _scheduleAutoResume() {
    // Why: defer the unpark by `_autoResumeHoldoff` so a transient
    // safe-reading does not force an immediate resume. The banner posted
    // here is the same UI surface that announced the park so the operator
    // sees the full park-then-resume narrative in one place.
    _resumeDelayTimer?.cancel();
    final resumeAt = DateTime.now().add(_autoResumeHoldoff);
    Future<void>.microtask(() {
      if (!mounted) return;
      final mins = _autoResumeHoldoff.inMinutes;
      _ref.read(uiNotificationProvider.notifier).showInfo(
            'Weather is clearing; auto-resume scheduled for '
            '${resumeAt.hour.toString().padLeft(2, '0')}:'
            '${resumeAt.minute.toString().padLeft(2, '0')} '
            '(after $mins min hold-off).',
            title: 'Weather Safety',
            duration: const Duration(seconds: 10),
          );
    });
    _resumeDelayTimer = Timer(_autoResumeHoldoff, () {
      if (!mounted) return;
      // Re-check just before resuming. If the periodic evaluator pushed us
      // back to unsafe during the wait we abort.
      if (state.status != WeatherSafetyStatus.safe) {
        Future<void>.microtask(() {
          if (!mounted) return;
          _ref.read(uiNotificationProvider.notifier).showWarning(
                'Auto-resume aborted: conditions deteriorated during hold-off.',
                title: 'Weather Safety',
                duration: const Duration(seconds: 10),
              );
        });
        return;
      }
      unawaited(_autoResumeAfterWeatherClear());
    });
  }

  void _cancelPendingAutoResume() {
    _resumeDelayTimer?.cancel();
    _resumeDelayTimer = null;
  }

  // -------------------------------------------------------------------------
  // Wave 5 Agent 4 — cloud-motion forwarding to the Rust executor.
  //
  // The Rust cloud-aware triggers (`CloudArrivingIn`, `CloudOpeningIn`,
  // `CloudCoverThreshold`) cannot run radar analysis themselves; we push
  // the live `cloudMotionAnalyzerProvider` output every 60s and call
  // `backend.sequencerUpdateCloudMotion(...)`. The first push runs
  // immediately so a sequence that starts right after app launch has
  // current data on its first evaluator tick.
  // -------------------------------------------------------------------------

  void _startCloudMotionPush() {
    _cloudMotionPushTimer?.cancel();
    _cloudMotionPushTimer = Timer.periodic(_cloudMotionPushInterval, (_) {
      if (!mounted) return;
      unawaited(_pushCloudMotion());
    });
    // Run the first push on the next microtask so any sequence already
    // running gets initial data without waiting a full minute.
    Future<void>.microtask(() {
      if (!mounted) return;
      unawaited(_pushCloudMotion());
    });
  }

  void _startAdaptiveConditionsPush() {
    _adaptiveConditionsPushTimer?.cancel();
    _adaptiveConditionsPushTimer =
        Timer.periodic(_adaptiveConditionsPushInterval, (_) {
      if (!mounted) return;
      unawaited(_pushAdaptiveConditions());
    });
    Future<void>.microtask(() {
      if (!mounted) return;
      unawaited(_pushAdaptiveConditions());
    });
  }

  /// Defense-in-depth (full-night audit 2026-06-04): forward the overall
  /// weather-safety verdict to the Rust executor's `WeatherUnsafe` trigger.
  ///
  /// Pushed on every evaluation so the in-sequencer trigger has a current
  /// verdict on its next tick, regardless of whether a hardware safety device
  /// is connected. Best-effort like the cloud-motion push: the backend may be
  /// disconnected (DisconnectedBackend throws), in which case there is no live
  /// executor to inform and we swallow the error. The Rust side folds this as
  /// an additional unsafe source (OR-of-unsafe with the hardware reading), so a
  /// `false` here never suppresses a hardware-unsafe abort.
  Future<void> _pushWeatherVerdict(bool isUnsafe) async {
    if (!mounted) return;
    try {
      final backend = _ref.read(backendProvider);
      await backend.sequencerUpdateWeatherVerdict(unsafeOverride: isUnsafe);
    } catch (_) {
      // No live executor to inform (e.g. backend disconnected). The verdict is
      // re-pushed on the next evaluation; the Dart SafeRig path remains the
      // primary enforcement layer.
    }
  }

  Future<void> _pushCloudMotion() async {
    if (!mounted) return;
    try {
      // Read the latest analyzer output. The provider auto-fetches the
      // most recent radar frames; we deliberately use a fresh `.future`
      // grab rather than caching so a manual weather refresh in the UI
      // shows up here immediately.
      final motion = await _ref.read(analyzeCloudMotionProvider.future);
      final coverAsync = await _ref.read(cloudCoverPercentageProvider.future);
      if (!mounted) return;

      final cover = coverAsync;
      // Cloud arrival prediction: present only when the analyzer reports
      // a finite eta (cloudMotion.etaToLocation). If the analyzer has no
      // motion / no nearby clouds, push None so the Rust trigger stays
      // quiescent — silent fallback to a sentinel would defeat the
      // "errors are a feature" rule.
      final arrivalMinutes = motion?.etaToLocation?.inSeconds != null
          ? motion!.etaToLocation!.inSeconds / 60.0
          : null;

      // Opening prediction: the current analyzer does not yet model a
      // future-opening curve, so we extract a coarse signal from current
      // coverage — when cover is well below the user's threshold we
      // synthesise a "clear opening now (0 min away)" with a generous
      // 30-minute duration. This is an honest approximation that keeps
      // the CloudOpeningIn trigger usable until the analyzer exposes
      // forecast data.
      double? openingMinutes;
      double? openingDurationSecs;
      if (cover != null && cover < 30.0) {
        openingMinutes = 0.0;
        openingDurationSecs = 30 * 60.0;
      }

      // Clear-sky direction: the analyzer does not yet report a single
      // (alt, az) target. Until that lands we leave the direction
      // unspecified — `SlewToGapAndContinue` falls back to
      // `PauseAndWaitForClear` when no direction is reported, which is
      // the documented behaviour.
      final backend = _ref.read(backendProvider);
      await backend.sequencerUpdateCloudMotion(
        currentCoverPercent: cover,
        predictedArrivalMinutes: arrivalMinutes,
        predictedOpeningMinutes: openingMinutes,
        predictedOpeningDurationSecs: openingDurationSecs,
        predictedClearSkyAlt: null,
        predictedClearSkyAz: null,
      );
    } catch (e) {
      // Cloud-motion push failures are best-effort: the analyzer may not
      // have produced data yet, the radar fetch may be in-flight, or the
      // backend may be temporarily disconnected. Log at debug level so
      // diagnostic context is preserved without spamming production logs.
      // ignore: avoid_print
      // We don't have a log helper at this scope; the backend layer will
      // log a more structured message when the call itself fails.
    }
  }

  Future<void> _pushAdaptiveConditions() async {
    if (!mounted) return;
    try {
      final appSettings = _ref.read(appSettingsProvider).valueOrNull;
      final weather = _ref.read(weatherStateProvider);
      final cloudCover = await _ref.read(cloudCoverPercentageProvider.future);
      if (!mounted) return;

      final (_, transparency) = _ref.read(currentScienceSnapshotProvider);
      final hfrValues = _currentHfrValues();
      final inputs = AdaptiveSwapInputComposer.fromTelemetry(
        transparencyPercent: transparency?.transparencyPercent,
        recentHfr: hfrValues,
        hardwareCloudCoverPercent: weather.cloudCover,
        apiCloudCoverPercent: cloudCover,
        windKph: weather.windSpeed,
      );
      final weights = _conditionsScoreWeights(appSettings);
      final driver = AdaptiveSwapDriver(
        composer: AdaptiveSwapService(weights: weights),
        backend: _ref.read(backendProvider),
      );
      await driver.tick(inputs);
    } catch (_) {
      // Periodic telemetry forwarding is opportunistic: disconnected remote
      // clients, missing weather APIs, or an unopened database should not spam
      // the operator. The executor receives a real null score when telemetry
      // is merely absent; this catch is for transport/provider failures.
    }
  }

  List<double?> _currentHfrValues() {
    return _ref
        .read(sessionImagesProvider)
        .map((image) => image.stats?.hfr)
        .toList(growable: false);
  }

  ConditionsScoreWeights _conditionsScoreWeights(AppSettingsState? settings) {
    final weights =
        settings?.conditionsScoreWeights ?? const <String, double>{};
    return ConditionsScoreWeights(
      transparencyWeight: weights['transparency'] ?? 0.40,
      seeingWeight: weights['seeing'] ?? 0.25,
      cloudWeight: weights['cloud'] ?? 0.25,
      windWeight: weights['wind'] ?? 0.10,
    );
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
    _resumeDelayTimer?.cancel();
    _cloudMotionPushTimer?.cancel();
    _adaptiveConditionsPushTimer?.cancel();
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
