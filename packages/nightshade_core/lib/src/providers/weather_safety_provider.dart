import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather/weather_models.dart';
import '../models/equipment/equipment_models.dart';
import '../models/settings/app_settings.dart';
import '../models/sequence/sequence_models.dart'
    show ConditionsScoreWeights, SequenceExecutionState;
import '../backend/disconnected_backend.dart';
import '../backend/nightshade_backend.dart';
import '../backend/network_backend.dart';
import '../services/scheduler/sky_calculations.dart';
import '../services/adaptive_swap_service.dart';
import '../services/safe_rig_service.dart';
import '../services/safety_config_service.dart';
import '../services/weather/weather_threshold_evaluator.dart';
import 'database_provider.dart';
import 'imaging_provider.dart';
import 'science_provider.dart';
import 'weather_providers.dart';
import 'equipment_provider.dart';
import 'settings_provider.dart';
import 'ui_notification_provider.dart';
import 'backend_provider.dart';
import 'sequence_provider.dart';

/// How a [SafetyFailMode] resolves the "no usable safety/weather data"
/// situation (no connected source on the Dart side; poll error on the Rust
/// side).
///
/// Architecture-unification 2026-06-05 (Subsystem 2 step 1, cross-language
/// parity). This is the Dart mirror of the Rust `NoDataResolution` enum in
/// `native/nightshade_native/sequencer/src/lib.rs`. The two MUST agree on the
/// same truth table; [noDataFailModeResolution] below is the single Dart
/// definition and is pinned against the identical table by
/// `test/services/weather/weather_fail_mode_parity_test.dart`, which
/// cross-references the Rust test `safety_fail_mode_no_data_resolution_truth_table`.
enum NoDataResolution {
  /// Treat the absence of data as UNSAFE (fail closed). Dart pushes
  /// `Some(true)`; Rust sets `weather_safe = false`.
  unsafe,

  /// Treat the absence of data as SAFE (fail open). Dart ABSTAINS (`null`)
  /// rather than asserting SAFE — a permissive policy must never gag a
  /// hardware-unsafe device — but the resolution row is "safe". Rust sets
  /// `weather_safe = true`.
  safe,

  /// Preserve the prior reading and emit an operator warning (warn-only). Dart
  /// ABSTAINS (`null`); Rust leaves `weather_safe` unchanged.
  preserve,
}

/// The single Dart definition of how each [SafetyFailMode] resolves a no-data
/// situation. Cross-language parity: mirrors the Rust
/// `safety_fail_mode_no_data_resolution`. If you change a row here, change it in
/// BOTH parity tests (Dart + Rust) or they will fail.
NoDataResolution noDataFailModeResolution(SafetyFailMode mode) {
  switch (mode) {
    case SafetyFailMode.failClosed:
      return NoDataResolution.unsafe;
    case SafetyFailMode.failOpen:
      return NoDataResolution.safe;
    case SafetyFailMode.warnOnly:
      return NoDataResolution.preserve;
  }
}

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

  factory WeatherSafetyState.initial() => const WeatherSafetyState(
    status: WeatherSafetyStatus.unsafe,
    actions: WeatherSafetyActions(
      shouldPause: true,
      reason: 'Weather safety has not been evaluated yet',
    ),
    currentAlertLevel: AlertLevel.clear,
    dataSource: SafetyDataSource.unavailable,
    hardwareWeatherSafe: false,
    safetyMonitorSafe: false,
    apiWeatherSafe: false,
  );

  /// Check if conditions are safe for imaging
  bool get isSafe => status == WeatherSafetyStatus.safe;

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
      failModeWarning: clearWarning
          ? null
          : (failModeWarning ?? this.failModeWarning),
      lastEvaluation: lastEvaluation ?? this.lastEvaluation,
    );
  }
}

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Notifier for weather safety state
class WeatherSafetyNotifier extends StateNotifier<WeatherSafetyState> {
  final Ref _ref;
  final BackendNotifier _backendNotifier;
  final Duration _autoResumeDelay;
  StreamSubscription? _alertSubscription;
  Timer? _snoozeTimer;
  Timer? _periodicEvalTimer;
  Timer? _resumeDelayTimer;
  // Periodic push of the cloud-motion analyzer output to
  // the Rust executor. Independent of the 5-min evaluation tick so the
  // Rust-side cloud-aware triggers see fresh data even between full
  // re-evaluations.
  Timer? _cloudMotionPushTimer;
  Timer? _adaptiveConditionsPushTimer;
  Timer? _remoteStatusTimer;
  Timer? _sourceChangeEvaluationTimer;
  bool _remoteFetchInFlight = false;
  bool _evaluationInFlight = false;
  bool _evaluationPending = false;
  bool _resumeInFlight = false;
  int _autoResumeGeneration = 0;

  /// Latch ensuring a successful safe-the-rig enforcement fires exactly once
  /// per unsafe episode. Set only after every requested action succeeds and
  /// cleared when conditions return to safe. A failed attempt stays re-armed
  /// for the next periodic evaluation.
  bool _safeRigEnforced = false;
  bool _enforceInFlight = false;
  bool _weatherPausedSequence = false;
  bool _weatherParkedMount = false;

  /// Periodic re-evaluation interval (5 minutes)
  static const _evaluationInterval = Duration(minutes: 5);
  static const _parkBeforeDawnLeadTime = Duration(minutes: 30);

  /// Push cadence for cloud-motion data into the Rust
  /// executor. 60 seconds matches the brief's "every 60s say".
  static const _cloudMotionPushInterval = Duration(seconds: 60);
  static const _adaptiveConditionsPushInterval = Duration(seconds: 30);

  /// `cloudCoverPercentageProvider` is a one-shot FutureProvider: without an
  /// explicit invalidation its first result (including a transient-failure
  /// null) is cached for the whole session, so the safety pushes would feed
  /// the executor the same startup sample all night. Re-fetch on a TTL from
  /// this notifier's existing push cadence — no extra Timer, so widget tests
  /// that mount cloud-cover consumers stay timer-leak free. Failures retry
  /// sooner than successes so an Open-Meteo blip doesn't blind the safety
  /// triggers for long.
  static const _cloudCoverTtl = Duration(minutes: 10);
  static const _cloudCoverErrorRetryTtl = Duration(minutes: 2);
  DateTime? _cloudCoverFetchedAt;

  /// Why: when weather first reads "safe" after an unsafe stretch we wait a
  /// hold-off period before unparking. Astronomical conditions are noisy —
  /// a transient cloud break can read as "safe" for a single sample before
  /// the front re-arrives, and unparking immediately can leave the rig
  /// mid-recovery when the next gust/cloud hits. Default 5 minutes matches
  /// the periodic re-evaluation cadence so we have at least one confirmation
  /// sample before committing to the resume.
  static const _autoResumeHoldoff = Duration(minutes: 5);

  WeatherSafetyNotifier(
    Ref ref, {
    Duration autoResumeDelay = _autoResumeHoldoff,
  }) : _ref = ref,
       _backendNotifier = ref.read(backendProvider.notifier),
       _autoResumeDelay = autoResumeDelay,
       super(WeatherSafetyState.initial()) {
    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      _startRemoteStatusPolling();
      return;
    }
    if (backend is DisconnectedBackend) {
      // UI-only mode has no rig to protect and no authority to issue hardware
      // commands. Keep the conservative unknown/unsafe verdict so imaging is
      // never presented as weather-safe, but make the state passive: evaluating
      // the fail-closed policy here would invoke SafeRig against a deliberately
      // disconnected backend and report a pair of false CRITICAL failures.
      state = state.copyWith(
        actions: WeatherSafetyActions.safe,
        failModeWarning:
            'Connect to an imaging host to evaluate weather safety.',
      );
      return;
    }
    _subscribeToAlerts();
    // Hardware connection and telemetry changes must update the consolidated
    // verdict promptly. Previously only alert changes and the five-minute
    // timer triggered evaluation, so a newly connected weather/safety device
    // could remain labelled "unavailable" for minutes.
    _ref.listen<WeatherState>(weatherStateProvider, (_, __) {
      _scheduleSourceChangeEvaluation();
    });
    _ref.listen<SafetyMonitorState>(safetyMonitorStateProvider, (_, __) {
      _scheduleSourceChangeEvaluation();
    });
    // Configuration changes are safety inputs too. Persisting
    // weatherSafetyEnabled/failMode previously updated Drift and the settings
    // UI but left this notifier's verdict unchanged until the five-minute
    // timer (or an unrelated device event) fired.
    _ref.listen<AsyncValue<WeatherSettings>>(weatherSettingsDataProvider, (
      _,
      __,
    ) {
      _scheduleSourceChangeEvaluation();
    });
    _ref.listen<AsyncValue<AppSettingsState>>(appSettingsProvider, (_, __) {
      _scheduleSourceChangeEvaluation();
    });
    _startPeriodicEvaluation();
    // Start the cloud-motion forwarding loop so the Rust
    // sequencer's cloud-aware triggers see live data the first time the
    // notifier is constructed (typically at app launch).
    _startCloudMotionPush();
    _startAdaptiveConditionsPush();
  }

  void _startRemoteStatusPolling() {
    unawaited(_refreshRemoteStatus());
    _remoteStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshRemoteStatus());
    });
  }

  Future<void> _refreshRemoteStatus() async {
    if (_remoteFetchInFlight || !mounted) return;
    final backend = _ref.read(backendProvider);
    if (backend is! NetworkBackend) return;
    _remoteFetchInFlight = true;
    try {
      final response = await backend.getSafetyStatus();
      if (!mounted) return;
      final rawStatus = response['safetyStatus'];
      final status = WeatherSafetyStatus.values.firstWhere(
        (candidate) => candidate.name == rawStatus,
        orElse: () => WeatherSafetyStatus.unsafe,
      );
      final rawSource = response['dataSource'];
      final dataSource = SafetyDataSource.values.firstWhere(
        (candidate) => candidate.name == rawSource,
        orElse: () => SafetyDataSource.unavailable,
      );
      final isSafe = status == WeatherSafetyStatus.safe;
      final failModeWarning = response['failModeWarning'] is String
          ? response['failModeWarning'] as String
          : null;
      final rawActions = response['actions'];
      bool actionFlag(String key, bool fallback) {
        if (rawActions is! Map) return fallback;
        final value = rawActions[key];
        return value is bool ? value : fallback;
      }

      String? actionText(String key) {
        if (rawActions is! Map) return null;
        final value = rawActions[key];
        return value is String ? value : null;
      }

      DateTime? wireDate(Object? value) =>
          value is String ? DateTime.tryParse(value) : null;

      final rawAlertLevel = response['currentAlertLevel'];
      final alertLevel = AlertLevel.values.firstWhere(
        (candidate) => candidate.name == rawAlertLevel,
        // Compatibility with pre-parity hosts: their aggregate response did
        // not carry severity, so retain the old conservative unsafe=warning
        // projection rather than treating an unknown value as clear.
        orElse: () => isSafe ? AlertLevel.clear : AlertLevel.warning,
      );
      final lastEvaluationRaw = response['lastEvaluation'];
      final snoozeUntilRaw = response['snoozeUntil'];
      state = WeatherSafetyState(
        status: status,
        actions: WeatherSafetyActions(
          shouldPause: actionFlag(
            'shouldPause',
            status == WeatherSafetyStatus.unsafe,
          ),
          shouldPark: actionFlag('shouldPark', false),
          shouldCloseDome: actionFlag('shouldCloseDome', false),
          reason:
              actionText('reason') ??
              (status == WeatherSafetyStatus.unsafe ? failModeWarning : null),
          resumeCheckTime: wireDate(actionText('resumeCheckTime')),
        ),
        snoozeUntil: wireDate(snoozeUntilRaw),
        currentAlertLevel: alertLevel,
        dataSource: dataSource,
        hardwareWeatherSafe: response['hardwareWeatherSafe'] as bool? ?? isSafe,
        safetyMonitorSafe: response['safetyMonitorSafe'] as bool? ?? isSafe,
        apiWeatherSafe: response['apiWeatherSafe'] as bool? ?? isSafe,
        failModeWarning: failModeWarning,
        lastEvaluation: wireDate(lastEvaluationRaw),
      );
    } catch (error) {
      if (!mounted) return;
      state = WeatherSafetyState.initial().copyWith(
        failModeWarning: 'Imaging host safety status unavailable: $error',
        lastEvaluation: DateTime.now(),
      );
    } finally {
      _remoteFetchInFlight = false;
    }
  }

  /// Start periodic re-evaluation timer independent of weather screen
  void _startPeriodicEvaluation() {
    _periodicEvalTimer?.cancel();
    _periodicEvalTimer = Timer.periodic(_evaluationInterval, (_) {
      if (!mounted) return;
      _evaluateAllSources();
    });
    // Also run initial evaluation, but not synchronously from the provider
    // constructor: evaluation can post UI notifications when conditions are
    // unsafe, and Riverpod forbids modifying another provider while this one is
    // still initializing.
    Timer.run(() {
      if (!mounted) return;
      _evaluateAllSources();
    });
  }

  void _scheduleSourceChangeEvaluation() {
    _sourceChangeEvaluationTimer?.cancel();
    _sourceChangeEvaluationTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _evaluateAllSources();
      }
    });
  }

  /// Evaluate all safety sources (API weather, hardware weather, safety monitor)
  void _evaluateAllSources() {
    unawaited(_evaluateAllSourcesAsync());
  }

  Future<void> _evaluateAllSourcesAsync() async {
    if (!mounted) return;
    if (_evaluationInFlight) {
      _evaluationPending = true;
      return;
    }
    _evaluationInFlight = true;
    try {
      final weatherSettings = await _ref.read(
        weatherSettingsDataProvider.future,
      );
      final appSettings = await _ref.read(appSettingsProvider.future);
      if (!mounted) return;
      _evaluateAllSourcesWithConfiguration(weatherSettings, appSettings);
    } catch (error) {
      if (!mounted) return;
      final failure = WeatherSafetyState.initial().copyWith(
        failModeWarning: 'Weather safety configuration unavailable: $error',
        lastEvaluation: DateTime.now(),
      );
      state = failure;
      _cancelPendingAutoResume();
      unawaited(_pushWeatherVerdict(true));
      if (!_safeRigEnforced) {
        unawaited(_enforceSafetyActionsAndLatch(failure.actions));
      }
    } finally {
      _evaluationInFlight = false;
      if (_evaluationPending && mounted) {
        _evaluationPending = false;
        _evaluateAllSources();
      }
    }
  }

  void _evaluateAllSourcesWithConfiguration(
    WeatherSettings weatherSettings,
    AppSettingsState appSettings,
  ) {
    if (!mounted) return;
    final failMode = appSettings.safetyFailMode;
    final parkPolicyEnabled = appSettings.parkOnUnsafeWeather;
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
      hardwareWeatherSafe = _evaluateHardwareWeather(
        weatherDeviceState,
        weatherSettings,
      );
    }

    // Evaluate safety monitor
    bool safetyMonitorSafe = true;
    if (isSafetyMonitorConnected) {
      safetyMonitorSafe = safetyMonitorState.isSafe;
    }

    // Get API weather status
    final alertService = _ref.read(weatherAlertServiceProvider);
    final currentAlert = alertService.currentAlert;
    final apiWeatherSafe =
        currentAlert == null ||
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
      // Cross-language parity: the no-data fail-mode resolution comes from the
      // SINGLE shared truth table ([noDataFailModeResolution], mirrored by the
      // Rust `safety_fail_mode_no_data_resolution`). The UI status/actions are
      // derived from that resolution so this screen-facing path and the
      // executor-facing [_computePushedVerdict] cannot disagree about what each
      // fail mode means.
      switch (noDataFailModeResolution(failMode)) {
        case NoDataResolution.unsafe:
          // Most conservative: treat unavailable data as unsafe, block operations.
          finalStatus = WeatherSafetyStatus.unsafe;
          finalActions = WeatherSafetyActions(
            shouldPause: true,
            shouldPark: shouldAutoPark,
            reason: failModeWarning,
          );
          break;
        case NoDataResolution.safe:
          // Permissive: treat unavailable data as safe, allow operations to continue.
          finalStatus = WeatherSafetyStatus.safe;
          finalActions = WeatherSafetyActions.safe;
          break;
        case NoDataResolution.preserve:
          // Warn-only: treat as safe for operations but emit a UI warning so the
          // operator knows the safety data is missing.
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
        _ref
            .read(uiNotificationProvider.notifier)
            .showWarning(
              failModeWarning ?? 'No weather data sources available',
              title: 'Weather Safety',
              duration: const Duration(seconds: 10),
            );
      });
    }

    // Defense-in-depth (full-night audit 2026-06-04): push this verdict into
    // the Rust executor so the in-sequencer `WeatherUnsafe` trigger reacts even
    // on a rig with no hardware safety device. The Dart SafeRig enforcement
    // above is the primary path; this is the redundant in-sequencer layer.
    //
    // Architecture-unification 2026-06-05 (Subsystem 2 steps 1+2): compute the
    // pushed verdict from the NON-HARDWARE Dart sources only (API alert /
    // hardware-weather thresholds / dawn) and ABSTAIN (`None`) when the operator
    // has effectively opted out of weather-driven aborts. See
    // [_computePushedVerdict] for the full rationale; in short:
    //   * the safety-monitor component is excluded so it is evaluated ONCE (Rust
    //     polls `safety_is_safe` and ORs it); folding it here too double-counted
    //     it.
    //   * disabled / snoozed / failOpen / warnOnly push `None`, never `false`.
    //     Pushing `false` (SAFE) is only harmless today because Rust ORs it; if a
    //     future refactor ever made Rust trust the verdict, a disabled toggle
    //     asserting SAFE could suppress a hardware-unsafe abort. `None` makes the
    //     channel strictly "add-unsafe-or-abstain" and closes that landmine.
    unawaited(
      _pushWeatherVerdict(
        _computePushedVerdict(
          weatherSettings: weatherSettings,
          finalStatus: finalStatus,
          failMode: failMode,
          useFailMode: useFailMode,
          apiWeatherSafe: apiWeatherSafe,
          hardwareWeatherSafe: hardwareWeatherSafe,
          dawnParkDue: dawnParkDue,
        ),
      ),
    );

    if (previousStatus == WeatherSafetyStatus.unsafe &&
        finalStatus == WeatherSafetyStatus.safe &&
        weatherSettings.autoResumeEnabled &&
        (_weatherPausedSequence || _weatherParkedMount)) {
      _scheduleAutoResume();
    } else if (finalStatus == WeatherSafetyStatus.unsafe) {
      // Why: if conditions re-degrade during the hold-off window we cancel
      // the pending resume so we don't unpark into renewed unsafe weather.
      _cancelPendingAutoResume();
    }

    // Enforce the computed safety actions on the hardware. Before this the
    // actions were COMPUTED but never EXECUTED — every consumer was UI-only,
    // so an unattended rig kept tracking/exposing into unsafe weather. We
    // enforce until one attempt fully succeeds, then latch for the rest of the
    // unsafe episode. A partial failure must stay re-armed so the next
    // 5-minute evaluation retries any incomplete pause / park / dome action.
    if (finalStatus == WeatherSafetyStatus.unsafe) {
      if (!_safeRigEnforced) {
        unawaited(_enforceSafetyActionsAndLatch(finalActions));
      }
    } else if (finalStatus == WeatherSafetyStatus.safe) {
      // Episode over (or never started) — re-arm enforcement for the next one.
      _safeRigEnforced = false;
    }
    // Snoozed: leave the latch as-is. A snooze means the operator explicitly
    // suppressed enforcement; if it expires back to unsafe the latch state
    // already reflects whether we enforced for this episode.
  }

  /// Execute and latch the computed actions only after every requested SafeRig
  /// step succeeds. Failed attempts deliberately leave the episode re-armed.
  Future<void> _enforceSafetyActionsAndLatch(
    WeatherSafetyActions actions,
  ) async {
    if (_safeRigEnforced || _enforceInFlight) return;
    final succeeded = await _enforceSafetyActions(actions);
    if (!mounted) return;
    if (succeeded && state.status == WeatherSafetyStatus.unsafe) {
      _safeRigEnforced = true;
    }
  }

  /// Execute the computed weather-safety actions on the hardware via the
  /// shared [SafeRigService]. Idempotent enough to be safe even if the latch
  /// were bypassed: SafeRig skips an already-parked mount / already-closed
  /// dome. Fail-closed: SafeRig throws on partial failure and surfaces a
  /// CRITICAL notification; we additionally log a warning banner here so the
  /// operator sees the weather-safety framing.
  Future<bool> _enforceSafetyActions(WeatherSafetyActions actions) async {
    // Authority may change while an evaluation is in flight. Neither a remote
    // client nor disconnected UI-only mode may execute the host's local
    // SafeRig workflow.
    final backend = _ref.read(backendProvider);
    if (backend is DisconnectedBackend || backend is NetworkBackend) {
      return false;
    }
    if (_enforceInFlight) return false;
    _enforceInFlight = true;
    final executionBefore = _ref.read(sequenceExecutionStateProvider);
    final mountBefore = _ref.read(mountStateProvider);
    void recordOwnership(SafeRigResult result) {
      _weatherPausedSequence =
          actions.shouldPause &&
          executionBefore == SequenceExecutionState.running &&
          result.sequencePaused;
      _weatherParkedMount =
          actions.shouldPark && !mountBefore.isParked && result.mountParked;
    }

    try {
      if (!actions.shouldPause &&
          !actions.shouldPark &&
          !actions.shouldCloseDome) {
        return true;
      }
      final safeRig = _ref.read(safeRigServiceProvider);
      final result = await safeRig.safeTheRig(
        reason: actions.reason ?? 'Weather turned unsafe',
        park: actions.shouldPark,
        closeDome: actions.shouldCloseDome,
        // Cover follows the dome decision: if conditions warrant closing the
        // dome shutter they also warrant closing a flip-flat / cover.
        closeCover: actions.shouldCloseDome,
      );
      recordOwnership(result);
      return true;
    } on SafeRigException catch (e) {
      recordOwnership(e.result);
      if (mounted) {
        _ref
            .read(uiNotificationProvider.notifier)
            .showError(
              'Weather safety enforcement did not fully complete: $e',
              title: 'Weather Safety',
              duration: const Duration(seconds: 15),
            );
      }
      return false;
    } catch (e) {
      // SafeRig already posted a CRITICAL notification with the per-step
      // failures; add the weather-safety context so the operator knows what
      // tripped it. Do not rethrow — the periodic evaluator must keep running.
      if (mounted) {
        _ref
            .read(uiNotificationProvider.notifier)
            .showError(
              'Weather safety enforcement did not fully complete: $e',
              title: 'Weather Safety',
              duration: const Duration(seconds: 15),
            );
      }
      return false;
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
    final generation = ++_autoResumeGeneration;
    final resumeAt = DateTime.now().add(_autoResumeDelay);
    Future<void>.microtask(() {
      if (!mounted || generation != _autoResumeGeneration) return;
      final mins = _autoResumeDelay.inMinutes;
      _ref
          .read(uiNotificationProvider.notifier)
          .showInfo(
            'Weather is clearing; auto-resume scheduled for '
            '${resumeAt.hour.toString().padLeft(2, '0')}:'
            '${resumeAt.minute.toString().padLeft(2, '0')} '
            '(after $mins min hold-off).',
            title: 'Weather Safety',
            duration: const Duration(seconds: 10),
          );
    });
    _resumeDelayTimer = Timer(_autoResumeDelay, () {
      if (!mounted || generation != _autoResumeGeneration) return;
      // Re-check just before resuming. If the periodic evaluator pushed us
      // back to unsafe during the wait we abort.
      if (state.status != WeatherSafetyStatus.safe) {
        Future<void>.microtask(() {
          if (!mounted) return;
          _ref
              .read(uiNotificationProvider.notifier)
              .showWarning(
                'Auto-resume aborted: conditions deteriorated during hold-off.',
                title: 'Weather Safety',
                duration: const Duration(seconds: 10),
              );
        });
        return;
      }
      unawaited(_autoResumeAfterWeatherClear(generation));
    });
  }

  void _cancelPendingAutoResume() {
    // Invalidating the generation also retires a recovery that has already
    // passed the hold-off timer and is awaiting an unpark/resume command.
    // Cancelling only the Timer allowed that stale continuation to resume the
    // sequence after conditions had turned unsafe again.
    _autoResumeGeneration++;
    _resumeDelayTimer?.cancel();
    _resumeDelayTimer = null;
  }

  // -------------------------------------------------------------------------
  // Cloud-motion forwarding to the Rust executor.
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
    _adaptiveConditionsPushTimer = Timer.periodic(
      _adaptiveConditionsPushInterval,
      (_) {
        if (!mounted) return;
        unawaited(_pushAdaptiveConditions());
      },
    );
    Future<void>.microtask(() {
      if (!mounted) return;
      unawaited(_pushAdaptiveConditions());
    });
  }

  /// Compute the verdict pushed to the Rust executor's `WeatherUnsafe` trigger.
  ///
  /// Architecture-unification 2026-06-05 (Subsystem 2). Returns:
  ///   * `null` (ABSTAIN) when the operator has effectively opted out of
  ///     weather-driven aborts — safety disabled, currently snoozed, or the
  ///     no-data fail-mode is permissive (failOpen / warnOnly). Abstaining
  ///     leaves the Rust trigger to rely solely on its own hardware poll; it
  ///     can never suppress a hardware-unsafe abort.
  ///   * `Some(true)` (UNSAFE) when the NON-HARDWARE Dart sources — API alert,
  ///     hardware-weather thresholds (humidity/wind/rain/cloud), or
  ///     park-before-dawn — say unsafe, OR the fail-closed no-data path is
  ///     active. The hardware **safety-monitor** component is deliberately
  ///     EXCLUDED: Rust already polls `safety_is_safe` and ORs it in, so folding
  ///     it here too would double-count the same device.
  ///   * `Some(false)` (SAFE) when none of the above non-hardware sources are
  ///     unsafe and the operator has NOT opted out.
  ///
  /// This is strictly safety-monotone: it only ever ADDS an unsafe assertion or
  /// ABSTAINS — it never asserts SAFE in a situation where the previous code
  /// would have asserted UNSAFE on a non-hardware source.
  bool? _computePushedVerdict({
    required WeatherSettings weatherSettings,
    required WeatherSafetyStatus finalStatus,
    required SafetyFailMode failMode,
    required bool useFailMode,
    required bool apiWeatherSafe,
    required bool hardwareWeatherSafe,
    required bool dawnParkDue,
  }) {
    // Opt-out cases ABSTAIN. `finalStatus == snoozed` covers an active snooze;
    // we also abstain for an explicit just-issued snooze that has not yet been
    // re-evaluated (the snooze() setter pushes status to snoozed directly).
    if (!weatherSettings.weatherSafetyEnabled ||
        finalStatus == WeatherSafetyStatus.snoozed) {
      return null;
    }

    // No-data fail-mode: resolved through the SINGLE cross-language truth table
    // ([noDataFailModeResolution], mirrored by the Rust
    // `safety_fail_mode_no_data_resolution`). `unsafe` asserts UNSAFE (matches
    // finalStatus); the permissive resolutions (`safe` / `preserve`) ABSTAIN
    // rather than assert SAFE, so a permissive fail-mode can never suppress a
    // hardware-unsafe abort.
    if (useFailMode) {
      switch (noDataFailModeResolution(failMode)) {
        case NoDataResolution.unsafe:
          return true;
        case NoDataResolution.safe:
        case NoDataResolution.preserve:
          return null;
      }
    }

    // Normal path: fold the non-hardware sources. The safety monitor is
    // intentionally absent (Rust evaluates it once). `dawnParkDue` is folded so
    // the park-before-dawn abort also reaches the in-sequencer trigger.
    final nonHardwareUnsafe =
        !apiWeatherSafe || !hardwareWeatherSafe || dawnParkDue;
    return nonHardwareUnsafe;
  }

  /// Defense-in-depth (full-night audit 2026-06-04): forward the
  /// weather-safety verdict to the Rust executor's `WeatherUnsafe` trigger.
  ///
  /// Pushed on every evaluation so the in-sequencer trigger has a current
  /// verdict on its next tick, regardless of whether a hardware safety device
  /// is connected. Best-effort like the cloud-motion push: the backend may be
  /// disconnected (DisconnectedBackend throws), in which case there is no live
  /// executor to inform and we swallow the error.
  ///
  /// `verdict` is `null` (abstain), `true` (unsafe) or `false` (safe) — see
  /// [_computePushedVerdict]. The Rust side ORs `Some(true)` as an additional
  /// unsafe source and treats `Some(false)` / `None` as non-asserting, so this
  /// channel can only ever add-unsafe or abstain — it never weakens the
  /// hardware gate.
  Future<void> _pushWeatherVerdict(bool? verdict) async {
    if (!mounted) return;
    try {
      final backend = _ref.read(backendProvider);
      await backend.sequencerUpdateWeatherVerdict(unsafeOverride: verdict);
    } catch (_) {
      // No live executor to inform (e.g. backend disconnected). The verdict is
      // re-pushed on the next evaluation; the Dart SafeRig path remains the
      // primary enforcement layer.
    }
  }

  /// Read the current cloud cover, re-fetching when the cached sample is
  /// older than its TTL (shorter when the last fetch failed). The first call
  /// stamps the clock without invalidating so it shares whatever fetch the UI
  /// already triggered.
  Future<double?> _freshCloudCover() async {
    final now = DateTime.now();
    final fetchedAt = _cloudCoverFetchedAt;
    if (fetchedAt == null) {
      _cloudCoverFetchedAt = now;
    } else {
      final hasValue =
          _ref.read(cloudCoverPercentageProvider).valueOrNull != null;
      final ttl = hasValue ? _cloudCoverTtl : _cloudCoverErrorRetryTtl;
      if (now.difference(fetchedAt) > ttl) {
        _ref.invalidate(cloudCoverPercentageProvider);
        _cloudCoverFetchedAt = now;
      }
    }
    return _ref.read(cloudCoverPercentageProvider.future);
  }

  Future<void> _pushCloudMotion() async {
    if (!mounted) return;
    try {
      // Read the latest analyzer output. The provider auto-fetches the
      // most recent radar frames; we deliberately use a fresh `.future`
      // grab rather than caching so a manual weather refresh in the UI
      // shows up here immediately.
      final motion = await _ref.read(analyzeCloudMotionProvider.future);
      final cover = await _freshCloudCover();
      if (!mounted) return;
      // Cloud arrival prediction: present only when the analyzer reports
      // a finite eta (cloudMotion.etaToLocation). If the analyzer has no
      // motion / no nearby clouds, push None so the Rust trigger stays
      // quiescent — silent fallback to a sentinel would defeat the
      // "errors are a feature" rule.
      final arrivalMinutes = motion?.etaToLocation?.inSeconds != null
          ? motion!.etaToLocation!.inSeconds / 60.0
          : null;

      // The analyzer does not yet model future openings. Preserve that honest
      // absence instead of manufacturing "opening now for 30 minutes" from a
      // single low-cover sample: doing so can fire CloudOpeningIn and resume a
      // paused sequence without any forecast evidence. Current cover still
      // drives CloudCoverThreshold independently.

      // Clear-sky direction: the analyzer does not yet report a single
      // (alt, az) target. Until that lands we leave the direction
      // unspecified — `SlewToGapAndContinue` falls back to
      // `PauseAndWaitForClear` when no direction is reported, which is
      // the documented behaviour.
      final backend = _ref.read(backendProvider);
      await backend.sequencerUpdateCloudMotion(
        currentCoverPercent: cover,
        predictedArrivalMinutes: arrivalMinutes,
        predictedOpeningMinutes: null,
        predictedOpeningDurationSecs: null,
        predictedClearSkyAlt: null,
        predictedClearSkyAz: null,
      );
    } catch (e, stack) {
      // Cloud-motion push is opportunistic forecast telemetry layered on top
      // of the authoritative SafeRig (Dart) and WeatherUnsafe (Rust) gates, so
      // a failure here must never propagate and block the safety path. It is
      // still a diagnosable condition (analyzer not ready yet, radar fetch
      // in-flight, or backend disconnected), so record it at a low severity
      // instead of silently dropping it.
      developer.log(
        'weather: cloud-motion push failed: $e',
        name: 'WeatherSafety',
        level: 700,
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _pushAdaptiveConditions() async {
    if (!mounted) return;
    try {
      final appSettings = _ref.read(appSettingsProvider).valueOrNull;
      final weather = _ref.read(weatherStateProvider);
      final cloudCover = await _freshCloudCover();
      if (!mounted) return;

      final (_, transparency) = _ref.read(currentScienceSnapshotProvider);
      final hfrValues = _currentHfrValues();
      final inputs = AdaptiveSwapInputComposer.fromTelemetry(
        transparencyPercent: transparency?.transparencyPercent,
        recentHfr: hfrValues,
        hardwareCloudCoverPercent: weather.cloudCover,
        apiCloudCoverPercent: cloudCover,
        windKph: weather.windSpeedKph,
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

  bool _canContinueAutoResume(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _autoResumeGeneration &&
      state.status == WeatherSafetyStatus.safe &&
      _backendNotifier.isCurrentBackend(backend);

  Future<void> _restoreSafetyAfterInterruptedResume({
    required NightshadeBackend backend,
    required bool sequenceResumeIssued,
    required bool mountUnparkIssued,
    required String? mountDeviceId,
  }) async {
    // A command can finish after weather re-degrades. The normal unsafe
    // enforcement may have run while that command was still pending, so undo
    // our own late completion explicitly; otherwise an unpark/resume can be
    // the final command and leave an unattended rig active in unsafe weather.
    if (!mounted ||
        state.status != WeatherSafetyStatus.unsafe ||
        !_backendNotifier.isCurrentBackend(backend)) {
      return;
    }

    final failures = <String>[];
    if (sequenceResumeIssued) {
      try {
        await backend.sequencerPause();
      } catch (error) {
        failures.add('pause sequence: $error');
      }
    }
    if (mountUnparkIssued && mountDeviceId != null) {
      try {
        await backend.mountPark(mountDeviceId);
      } catch (error) {
        failures.add('park mount: $error');
      }
    }

    if (failures.isNotEmpty && mounted) {
      _ref
          .read(uiNotificationProvider.notifier)
          .showError(
            'Weather became unsafe during automatic recovery, and Nightshade '
            'could not fully restore the safe state (${failures.join('; ')}).',
            title: 'Weather Safety',
            duration: const Duration(seconds: 15),
          );
    }
  }

  Future<void> _autoResumeAfterWeatherClear(int generation) async {
    if (_resumeInFlight) return;
    _resumeInFlight = true;
    final backend = _backendNotifier.currentBackend;
    var mountUnparkIssued = false;
    var sequenceResumeIssued = false;
    String? mountDeviceId;
    try {
      if (!_canContinueAutoResume(backend, generation)) return;
      if (_weatherParkedMount) {
        final mount = _ref.read(mountStateProvider);
        final connected =
            mount.connectionState == DeviceConnectionState.connected &&
            mount.deviceId != null &&
            mount.deviceId!.isNotEmpty;
        if (!connected) {
          throw StateError(
            'Cannot auto-resume: the weather-parked mount is disconnected',
          );
        }
        mountDeviceId = mount.deviceId!;
        if (mount.isParked) {
          await backend.mountUnpark(mountDeviceId);
          mountUnparkIssued = true;
        }
        if (!_canContinueAutoResume(backend, generation)) {
          await _restoreSafetyAfterInterruptedResume(
            backend: backend,
            sequenceResumeIssued: sequenceResumeIssued,
            mountUnparkIssued: mountUnparkIssued,
            mountDeviceId: mountDeviceId,
          );
          return;
        }
        _weatherParkedMount = false;
      }
      if (_weatherPausedSequence) {
        if (!_canContinueAutoResume(backend, generation)) return;
        await backend.sequencerResume();
        sequenceResumeIssued = true;
        if (!_canContinueAutoResume(backend, generation)) {
          await _restoreSafetyAfterInterruptedResume(
            backend: backend,
            sequenceResumeIssued: sequenceResumeIssued,
            mountUnparkIssued: mountUnparkIssued,
            mountDeviceId: mountDeviceId,
          );
          return;
        }
        _weatherPausedSequence = false;
      }
      if (!_canContinueAutoResume(backend, generation)) return;
      _ref
          .read(uiNotificationProvider.notifier)
          .showInfo(
            'Weather is safe again; weather-owned safing actions were reversed.',
            title: 'Weather Safety',
            duration: const Duration(seconds: 8),
          );
    } catch (e) {
      if (!_canContinueAutoResume(backend, generation)) return;
      _ref
          .read(uiNotificationProvider.notifier)
          .showWarning(
            'Weather cleared, but automatic resume failed: $e',
            title: 'Weather Safety',
            duration: const Duration(seconds: 10),
          );
    } finally {
      _resumeInFlight = false;
    }
  }

  /// Evaluate hardware weather device for safety.
  ///
  /// Architecture-unification 2026-06-05 (Subsystem 2 step 3): the threshold
  /// comparison logic now lives in the pure [WeatherThresholdEvaluator] so it
  /// has one definition and is unit-testable in isolation. This method just
  /// adapts the provider's [WeatherState] / [WeatherSettings] into the
  /// evaluator's plain inputs.
  bool _evaluateHardwareWeather(
    WeatherState weatherState,
    WeatherSettings settings,
  ) {
    const evaluator = WeatherThresholdEvaluator();
    final result = evaluator.evaluate(
      WeatherReading(
        humidityPercent: weatherState.humidity,
        windSpeedKph: weatherState.windSpeedKph,
        rainRate: weatherState.rainRate,
        cloudCoverPercent: weatherState.cloudCover,
      ),
      WeatherThresholds(
        maxHumidityPercent: settings.maxHumidityPercent,
        maxWindSpeedKph: settings.maxWindSpeedKph,
        maxCloudCoverPercent: settings.maxCloudCoverPercent,
      ),
    );
    return result.isSafe;
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

    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      unawaited(
        backend
            .acknowledgeSafetyCondition(
              reason: 'Remote operator snoozed weather safety alerts',
              durationMinutes: duration.inMinutes.clamp(1, 1440),
            )
            .then((_) => _refreshRemoteStatus())
            .catchError((Object error) {
              if (mounted) {
                state = WeatherSafetyState.initial().copyWith(
                  failModeWarning: 'Could not snooze host safety: $error',
                  lastEvaluation: DateTime.now(),
                );
              }
            }),
      );
      return;
    }

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

    // Clear the acknowledgement immediately and fail closed while fresh
    // conditions are being fetched. Merely clearing `snoozeUntil` used to
    // leave `status == snoozed` until an asynchronous evaluation completed,
    // so the Cancel Snooze button appeared to do nothing and a stalled remote
    // refresh could leave the client snoozed indefinitely.
    state = state.copyWith(
      status: WeatherSafetyStatus.unsafe,
      actions: const WeatherSafetyActions(
        shouldPause: true,
        reason: 'Weather safety snooze cancelled; re-evaluating conditions',
      ),
      clearSnooze: true,
    );
    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      unawaited(
        backend
            .cancelSafetyAcknowledgement()
            .then((_) => _refreshRemoteStatus())
            .catchError((Object error) {
              if (mounted) {
                state = WeatherSafetyState.initial().copyWith(
                  failModeWarning: 'Could not cancel host snooze: $error',
                  lastEvaluation: DateTime.now(),
                );
              }
            }),
      );
      return;
    }
    _evaluateAllSources();
  }

  /// Force immediate re-evaluation of all safety sources
  void forceEvaluation() {
    if (_ref.read(backendProvider) is NetworkBackend) {
      unawaited(_refreshRemoteStatus());
      return;
    }
    _evaluateAllSources();
  }

  /// Force a safety evaluation and wait until it and any coalesced follow-up
  /// evaluation have completed.
  Future<void> evaluateNow() async {
    if (_ref.read(backendProvider) is NetworkBackend) {
      await _refreshRemoteStatus();
      return;
    }
    _evaluateAllSources();
    while (mounted && (_evaluationInFlight || _evaluationPending)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _snoozeTimer?.cancel();
    _periodicEvalTimer?.cancel();
    _cancelPendingAutoResume();
    _cloudMotionPushTimer?.cancel();
    _adaptiveConditionsPushTimer?.cancel();
    _remoteStatusTimer?.cancel();
    _sourceChangeEvaluationTimer?.cancel();
    super.dispose();
  }
}

/// Provider for weather safety state
final weatherSafetyProvider =
    StateNotifierProvider<WeatherSafetyNotifier, WeatherSafetyState>((ref) {
      ref.watch(backendProvider);
      return WeatherSafetyNotifier(ref);
    });

/// Convenience provider for quick safety check
final isWeatherSafeProvider = Provider<bool>((ref) {
  final safety = ref.watch(weatherSafetyProvider);
  return safety.isSafe;
});

/// The single read/write path for the consolidated [SafetyConfig].
///
/// Consolidation (Phase 2, 2026-06-22): the one logical safety config used to
/// be split across `weatherSettingsDao`, `appSettings`, and `settingsDao`.
/// [SafetyConfigStore] owns the field→store routing so callers no longer fan
/// writes across stores themselves. See [SafetyConfigStore] for the field map.
final safetyConfigStoreProvider = Provider<SafetyConfigStore>((ref) {
  return SafetyConfigStore(ref.watch(databaseProvider));
});
