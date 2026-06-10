part of '../settings_provider.dart';

/// P1 — Observer-location "unset" detection.
///
/// Latitude/longitude/elevation default to 0.0 when the user has never
/// entered a location (the DB seed and every loader fall back to 0.0). The
/// point (0°, 0°) is in the Gulf of Guinea — a perfectly valid coordinate,
/// but in practice it is the unmistakable signature of "never configured".
/// A whole night planned for that point (rise/set times, moon separation,
/// meridian flips, FITS SITELAT/SITELONG) is silently wrong.
///
/// This extension exposes a loud, model-level signal so pre-flight / Smart
/// Night / scheduler code can block (or warn) before computing a night for
/// coordinates the user never actually set. It deliberately lives at the
/// model level (no UI here) so every consumer shares one definition of
/// "location not set".
extension LocationUnsetDetection on AppSettingsState {
  /// Tolerance (in degrees) around the null island within which we treat the
  /// coordinate as unset rather than a deliberate (0,0) choice. ~1.1 km at the
  /// equator — far tighter than any real observing site a user would pick on
  /// purpose, but wide enough to absorb float round-trips through the DAO's
  /// string storage.
  static const double _unsetEpsilonDeg = 0.01;

  /// True when the observer latitude AND longitude are both effectively zero,
  /// i.e. the user has never set a real location. Elevation is ignored on
  /// purpose: many valid sites are at (or near) sea level, so a 0 m elevation
  /// alone must NOT mark the location unset.
  bool get isLocationUnset =>
      latitude.abs() < _unsetEpsilonDeg && longitude.abs() < _unsetEpsilonDeg;

  /// Convenience inverse of [isLocationUnset] for readability at call sites
  /// that gate on a *configured* location.
  bool get isLocationSet => !isLocationUnset;
}

extension _AppSettingsStoredSnapshotMapping on AppSettingsNotifier {
  AppSettingsState _settingsFromStoredMap(Map<String, String> allSettings) {
    return AppSettingsState(
      // General
      startMinimized: _parseBool(allSettings['start_minimized'], false),
      autoConnectEquipment: _parseBool(
        allSettings['auto_connect_equipment'],
        true,
      ),
      autoSaveSequences: _parseBool(allSettings['auto_save_sequences'], true),
      confirmBeforeClosing: _parseBool(
        allSettings['confirm_before_closing'],
        true,
      ),
      autoDiscoverOnLaunch: _parseBool(
        allSettings['auto_discover_on_launch'],
        true,
      ),

      // Appearance
      theme: allSettings['theme'] ?? 'dark',
      language: allSettings['language'] ?? 'en',
      accentColor: allSettings['accent_color'] ?? kDefaultAccentColorHex,
      fontSize: allSettings['font_size'] ?? 'Medium',
      uiScale: allSettings['ui_scale'] ?? 'Auto',
      sidebarCollapsed: _parseBool(allSettings['sidebar_collapsed'], false),

      // Location
      latitude: _parseDouble(allSettings['observer_latitude'], 0.0),
      longitude: _parseDouble(allSettings['observer_longitude'], 0.0),
      elevation: _parseDouble(allSettings['observer_elevation'], 0.0),
      timezone: allSettings['timezone'] ?? 'UTC',
      useSystemTime: _parseBool(allSettings['use_system_time'], true),

      // Imaging
      imageFormat: allSettings['image_format'] ?? 'FITS',
      fileNamingPattern:
          allSettings['file_naming_pattern'] ?? r'$TARGET_$FILTER_$DATE_$SEQ',
      bitDepth: allSettings['bit_depth'] ?? '16-bit',

      // Sequencer
      parkOnUnsafeWeather: _parseBool(
        allSettings['park_on_unsafe_weather'],
        true,
      ),
      parkBeforeDawn: _parseBool(allSettings['park_before_dawn'], true),
      meridianFlipMinutes: _parseInt(allSettings['meridian_flip_minutes'], 5),
      autoFocusOnFilterChange: _parseBool(
        allSettings['auto_focus_on_filter_change'],
        true,
      ),
      useFilterFocusOffsets: _parseBool(
        allSettings['use_filter_focus_offsets'],
        true,
      ),
      autoFocusEveryMinutes: _parseInt(
        allSettings['auto_focus_every_minutes'],
        60,
      ),
      ditherEnabled: _parseBool(allSettings['dither_enabled'], true),
      ditherEveryFrames: _parseInt(allSettings['dither_every_frames'], 3),
      safetyFailMode: _parseSafetyFailMode(allSettings['safety_fail_mode']),

      // Plate Solving
      plateSolver: allSettings['plate_solver'] ?? 'ASTAP',
      astapPath: allSettings['astap_path'] ?? '',
      astrometryPath: allSettings['astrometry_path'] ?? '',
      plateSolveTimeout: _parseInt(allSettings['plate_solve_timeout'], 60),
      plateSolveSearchRadius: _parseDouble(
        allSettings['plate_solve_search_radius'],
        30.0,
      ),
      blindSolve: _parseBool(allSettings['blind_solve'], false),

      // PHD2 Guiding
      phd2Path: allSettings['phd2_path'] ?? '',
      phd2Host: allSettings['phd2_host'] ?? 'localhost',
      phd2Port: _parseInt(allSettings['phd2_port'], 4400),

      // Notifications
      notificationsEnabled: _parseBool(
        allSettings['notifications_enabled'],
        true,
      ),
      discordWebhook: allSettings['discord_webhook'] ?? '',
      pushoverKey: allSettings['pushover_key'] ?? '',
      pushoverUser: allSettings['pushover_user'] ?? '',
      notifyOnSequenceComplete: _parseBool(
        allSettings['notify_on_sequence_complete'],
        true,
      ),
      notifyOnError: _parseBool(allSettings['notify_on_error'], true),
      notifyOnMeridianFlip: _parseBool(
        allSettings['notify_on_meridian_flip'],
        false,
      ),
      soundEnabled: _parseBool(allSettings['sound_enabled'], true),

      // File Paths
      imageOutputPath: allSettings['image_output_path'] ?? '',
      sequencesPath: allSettings['sequences_path'] ?? '',
      databasePath: allSettings['database_path'] ?? '',
      logsPath: allSettings['logs_path'] ?? '',

      // Protocol Settings
      indiServerHost: allSettings['indi_server_host'] ?? 'localhost',
      indiServerPort: _parseInt(allSettings['indi_server_port'], 7624),
      indiAutoConnect: _parseBool(allSettings['indi_auto_connect'], false),
      alpacaServerHost: allSettings['alpaca_server_host'] ?? 'localhost',
      alpacaServerPort: _parseInt(allSettings['alpaca_server_port'], 11111),
      alpacaAutoDiscover: _parseBool(
        allSettings['alpaca_auto_discover'],
        false,
      ),

      // Sequencer Execution
      useNativeExecution: _parseBool(allSettings['use_native_execution'], true),
      useSimulationMode: _parseBool(allSettings['use_simulation_mode'], false),

      // Remote Access / Web Server
      webServerEnabled: _parseBool(allSettings['web_server_enabled'], false),
      webServerPort: _parseInt(allSettings['web_server_port'], 8080),

      // Equipment Settings - Camera
      coolingBehavior: allSettings['cooling_behavior'] ?? 'On Connect',
      defaultGain: _parseInt(allSettings['default_gain'], 100),
      defaultOffset: _parseInt(allSettings['default_offset'], 50),

      // Equipment Settings - Mount
      enableMeridianFlip: _parseBool(allSettings['enable_meridian_flip'], true),

      // Equipment Settings - Focuser
      tempCompensation: _parseBool(allSettings['temp_compensation'], true),
      tempCoefficient: _parseDouble(allSettings['temp_coefficient'], -12.0),
      backlashCompensation: _parseInt(allSettings['backlash_compensation'], 0),

      // Equipment Settings - Guider
      ditherScale: allSettings['dither_scale'] ?? 'Medium',
      settleThreshold: _parseDouble(allSettings['settle_threshold'], 0.5),
      settleTimeout: _parseInt(allSettings['settle_timeout'], 30),

      // Autofocus Settings
      // Observing Environment
      bortleClass: _parseInt(allSettings['bortle_class'], 5),
      horizonProfileJson:
          allSettings['horizon_profile_json'] ??
          '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}',
      effectiveHorizonDeg: _parseDouble(
        allSettings['effective_horizon_deg'],
        0.0,
      ),
      audibleAlertsOnCritical: _parseBool(
        allSettings['audible_alerts_on_critical'],
        false,
      ),
      criticalAlertSound: _normaliseCriticalAlertSound(
        allSettings['critical_alert_sound'],
      ),
      pushCriticalAlerts: _parseBool(allSettings['push_critical_alerts'], true),

      // Wave 4 Recovery Mode — persisted defaults. Missing keys (first
      // launch, upgrade from pre-Wave-4 release) fall back to the
      // SGP-matching constructor defaults. Values are clamped here so a
      // pathological persisted setting (zero retry interval, negative
      // duration) can't put the executor into a busy-loop recovery state.
      recoveryDefaultRetryIntervalMins: _parseDouble(
        allSettings['recovery_default_retry_interval_mins'],
        10.0,
      ).clamp(1.0, 240.0),
      recoveryDefaultMaxDurationMins: _parseDouble(
        allSettings['recovery_default_max_duration_mins'],
        90.0,
      ).clamp(1.0, 1440.0),
      recoveryStopTrackingDuringRecovery: _parseBool(
        allSettings['recovery_stop_tracking_during_recovery'],
        true,
      ),
      recoveryAbortOnMeridian: _parseBool(
        allSettings['recovery_abort_on_meridian'],
        true,
      ),
      recoveryAudibleAlertWhenEntered: _parseBool(
        allSettings['recovery_audible_alert_when_entered'],
        true,
      ),

      afMethod: allSettings['af_method'] ?? 'Star HFR',
      afCurveFitting: allSettings['af_curve_fitting'] ?? 'Hyperbolic',
      afStepSize: _parseInt(allSettings['af_step_size'], 50),
      afExposureTime: _parseDouble(allSettings['af_exposure_time'], 4.0),
      afInitialOffsetSteps: _parseInt(
        allSettings['af_initial_offset_steps'],
        4,
      ),
      afNumberOfAttempts: _parseInt(allSettings['af_number_of_attempts'], 1),
      afUseBrightestNStars: _parseInt(
        allSettings['af_use_brightest_n_stars'],
        0,
      ),
      afOuterCropRatio: _parseDouble(allSettings['af_outer_crop_ratio'], 1.0),
      afInnerCropRatio: _parseDouble(allSettings['af_inner_crop_ratio'], 0.0),
      afBinning: _parseInt(allSettings['af_binning'], 1),
      afRSquaredThreshold: _parseDouble(
        allSettings['af_r_squared_threshold'],
        0.7,
      ),
      afDisableGuidingDuringAf: _parseBool(
        allSettings['af_disable_guiding'],
        false,
      ),
      afFocuserSettleTimeMs: _parseInt(
        allSettings['af_focuser_settle_time_ms'],
        500,
      ),
      afExposuresPerPoint: _parseInt(allSettings['af_exposures_per_point'], 1),
      afBacklashCompMethod:
          allSettings['af_backlash_comp_method'] ?? 'Overshoot',
      afBacklashIn: _parseInt(allSettings['af_backlash_in'], 350),
      afBacklashOut: _parseInt(allSettings['af_backlash_out'], 0),
      afAutofocusFilterName: allSettings['af_autofocus_filter_name'] ?? '',
      afFilterSettingsJson: allSettings['af_filter_settings'] ?? '{}',

      // Pack G — observer name (FITS OBSERVER).
      observerName: allSettings['observer_name'] ?? '',

      // Pack G — Wave 3 Image Grading. Each `_parseOptionalDouble` /
      // `_parseOptionalInt` returns `null` only when the key is *absent*
      // OR the persisted value is the literal string "null"; an actual
      // numeric value parses normally. This is how the UI lets the user
      // clear a threshold without flipping the master toggle off.
      enableImageGrading: _parseBool(
        allSettings['image_grading_enabled'],
        false,
      ),
      imageGradingHfrThresholdPx: _parseOptionalDouble(
        allSettings['image_grading_hfr_threshold_px'],
        defaultIfMissing: 3.5,
      ),
      imageGradingHfrBaselinePercent: _parseOptionalDouble(
        allSettings['image_grading_hfr_baseline_percent'],
        defaultIfMissing: 50.0,
      ),
      imageGradingEccentricityThreshold: _parseOptionalDouble(
        allSettings['image_grading_eccentricity_threshold'],
        defaultIfMissing: 0.7,
      ),
      imageGradingStarCountMin: _parseOptionalInt(
        allSettings['image_grading_star_count_min'],
        defaultIfMissing: 10,
      ),
      imageGradingMaxConsecutiveRejects: _parseInt(
        allSettings['image_grading_max_consecutive_rejects'],
        3,
      ),
      imageGradingRejectFolderPath:
          (allSettings['image_grading_reject_folder_path'] == null ||
              allSettings['image_grading_reject_folder_path']!.isEmpty)
          ? null
          : allSettings['image_grading_reject_folder_path'],

      // Wave 5 Agent 2 — Sky-brightness adaptive exposure. Per-filter
      // maps are stored as JSON strings in app_settings; an empty map
      // falls back to the implicit-global behaviour at runtime.
      adaptiveExposureEnabled: _parseBool(
        allSettings['adaptive_exposure_enabled'],
        false,
      ),
      adaptiveExposureTargetSnr: _parseDouble(
        allSettings['adaptive_exposure_target_snr'],
        30.0,
      ),
      adaptiveExposureReferenceMag: _parseDouble(
        allSettings['adaptive_exposure_reference_mag'],
        21.5,
      ),
      adaptiveExposureMinSecs: _parseDouble(
        allSettings['adaptive_exposure_min_secs'],
        5.0,
      ),
      adaptiveExposureMaxSecs: _parseDouble(
        allSettings['adaptive_exposure_max_secs'],
        600.0,
      ),
      adaptiveExposurePerFilterEnabled: _parseFilterBoolMap(
        allSettings['adaptive_exposure_per_filter_enabled'],
      ),
      adaptiveExposurePerFilterMinSecs: _parseFilterDoubleMap(
        allSettings['adaptive_exposure_per_filter_min_secs'],
      ),
      adaptiveExposurePerFilterMaxSecs: _parseFilterDoubleMap(
        allSettings['adaptive_exposure_per_filter_max_secs'],
      ),

      // Wave 5 Agent 3 — Pre-flight checks. Values are clamped to defend
      // against pathological persisted values (zero / negative days, zero
      // coverage quorum). The drift threshold has no upper bound — a user
      // who wants the optical-train check silenced can crank it sky-high.
      preflightStrictness: _parsePreflightStrictness(
        allSettings['preflight_strictness'],
      ),
      polarAlignmentMaxAgeDays: _parseInt(
        allSettings['polar_alignment_max_age_days'],
        7,
      ).clamp(1, 365),
      darkLibraryMinCoverage: _parseInt(
        allSettings['dark_library_min_coverage'],
        10,
      ).clamp(1, 1000),
      opticalTrainDriftThreshold: _parseDouble(
        allSettings['optical_train_drift_threshold'],
        8.0,
      ).clamp(0.1, 1000.0),
      // Wave 6 Agent 1 — Smart Night persisted defaults. Each numeric
      // knob is clamped to a sane range so a pathological persisted
      // value can't blow up the wizard with a multi-day session or a
      // zero-frame autofocus cadence.
      smartNightMaxSessionHours: _parseOptionalDouble(
        allSettings['smart_night_max_session_hours'],
        defaultIfMissing: null,
      ),
      smartNightDefaultAfCadenceFrames: _parseInt(
        allSettings['smart_night_default_af_cadence_frames'],
        25,
      ).clamp(1, 9999),
      smartNightDefaultIntegrationBudgetMinsPerTarget: _parseInt(
        allSettings['smart_night_default_integration_budget_mins_per_target'],
        240,
      ).clamp(1, 24 * 60),
      smartNightIncludeFlatsAtEnd: _parseBool(
        allSettings['smart_night_include_flats_at_end'],
        true,
      ),
      smartNightUseSchedulerForMultiTarget: _parseBool(
        allSettings['smart_night_use_scheduler_for_multi_target'],
        true,
      ),
      smartNightSchedulerTargetThreshold: _parseInt(
        allSettings['smart_night_scheduler_target_threshold'],
        3,
      ).clamp(2, 20),
      smartNightDefaultStrategy:
          allSettings['smart_night_default_strategy'] ?? 'auto_lrgb',
      smartNightPolarAlignmentStaleAfterDays: _parseInt(
        allSettings['smart_night_polar_alignment_stale_after_days'],
        7,
      ).clamp(1, 365),
      // Wave 6 Agent 5 — Notes prompt opt-out. Same key the
      // NotesService writes through `notesPromptToggleProvider`.
      smartNightSubExposureFloorSecs: _parseDouble(
        allSettings['smart_night_sub_exposure_floor_secs'],
        30.0,
      ).clamp(1.0, 3600.0),
      smartNightSubExposureCeilingSecs: _parseDouble(
        allSettings['smart_night_sub_exposure_ceiling_secs'],
        300.0,
      ).clamp(1.0, 7200.0),
      smartNightTargetSnr: _parseDouble(
        allSettings['smart_night_target_snr'],
        30.0,
      ).clamp(1.0, 500.0),
      smartNightAutoPromptEnabled: _parseBool(
        allSettings['smart_night.auto_prompt_enabled'],
        true,
      ),
      promptForNotesAfterRun: _parseBool(
        allSettings['notes.prompt_after_run'],
        true,
      ),
      // Wave 7 — Session lifecycle persistence.
      sessionHandoffAutoPrompt: _parseBool(
        allSettings['session.handoff_auto_prompt'],
        true,
      ),
      campaignRollupSurfaceTargetsTab: _parseBool(
        allSettings['campaign_rollup.surface_targets_tab'],
        true,
      ),
      campaignRollupGroupingMode: _parseCampaignGroupingMode(
        allSettings['campaign_rollup.grouping_mode'],
      ),
      // Wave 8 — Adaptive sky-conditions defaults. The weights map is
      // JSON-encoded under `adaptive_swap.score_weights`; missing /
      // malformed entries fall back to the constructor defaults via the
      // [_parseConditionsScoreWeights] helper.
      adaptiveSwapEnabledByDefault: _parseBool(
        allSettings['adaptive_swap.enabled_by_default'],
        false,
      ),
      adaptiveSwapDefaultThreshold: _parseDouble(
        allSettings['adaptive_swap.default_threshold'],
        50.0,
      ).clamp(0.0, 100.0),
      adaptiveSwapDefaultHysteresisSecs: _parseDouble(
        allSettings['adaptive_swap.default_hysteresis_secs'],
        180.0,
      ).clamp(0.0, 3600.0),
      conditionsScoreWeights: _parseConditionsScoreWeights(
        allSettings['adaptive_swap.score_weights'],
      ),
    );
  }

  /// Wave 8 — parse the persisted [conditionsScoreWeights] JSON object.
  /// Falls back to the canonical defaults when the value is missing,
  /// malformed, or weighted-key-set-incomplete.
  Map<String, double> _parseConditionsScoreWeights(String? raw) {
    const defaults = <String, double>{
      'transparency': 0.40,
      'seeing': 0.25,
      'cloud': 0.25,
      'wind': 0.10,
    };
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return defaults;
      final out = <String, double>{};
      for (final key in defaults.keys) {
        final v = decoded[key];
        out[key] = v is num ? v.toDouble() : defaults[key]!;
      }
      return out;
    } catch (_) {
      // Malformed JSON — fall back to defaults so the rest of settings
      // load anyway. Per CLAUDE.md we surface this elsewhere (the
      // settings page renders a warning when weights drift from 1.0).
      return defaults;
    }
  }

  /// Wave 7 — clamp the grouping mode to the allowed enum-style values.
  /// Unknown / empty persists fall through to the default. Keeps the
  /// rest of the settings codebase free of a separate enum type — the
  /// three call sites just compare to the string constants.
  String _parseCampaignGroupingMode(String? value) {
    const allowed = ['by_target_name', 'by_target_id', 'by_user_tag'];
    if (value == null || !allowed.contains(value)) return 'by_target_name';
    return value;
  }

  /// Pack G — parse a persisted `Optional<double>`. The DAO stores values as
  /// strings; a missing key returns the supplied default (so the master
  /// toggle defaults are honoured on first launch), the literal string
  /// "null" returns null (user explicitly cleared the field), and any
  /// numeric value parses normally.
  double? _parseOptionalDouble(
    String? value, {
    required double? defaultIfMissing,
  }) {
    if (value == null) return defaultIfMissing;
    if (value == 'null' || value.isEmpty) return null;
    return double.tryParse(value) ?? defaultIfMissing;
  }

  int? _parseOptionalInt(String? value, {required int? defaultIfMissing}) {
    if (value == null) return defaultIfMissing;
    if (value == 'null' || value.isEmpty) return null;
    return int.tryParse(value) ?? defaultIfMissing;
  }

  bool _parseBool(String? value, bool defaultValue) {
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true';
  }

  /// Wave 5 Agent 2 — parse a JSON-encoded `Map<String, bool>` from
  /// app_settings. Returns an empty map on null / invalid input so the
  /// runtime falls back to the implicit-global behaviour rather than
  /// firing on garbage data.
  Map<String, bool> _parseFilterBoolMap(String? value) {
    if (value == null || value.isEmpty || value == 'null') {
      return const {};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {
      // Treat parse errors as no-data; CLAUDE.md "errors are a
      // feature" doesn't apply to disk-side persisted values we
      // don't control the format of — fall back to empty rather than
      // crashing settings load.
    }
    return const {};
  }

  /// Wave 5 Agent 2 — parse a JSON-encoded `Map<String, double>`.
  Map<String, double> _parseFilterDoubleMap(String? value) {
    if (value == null || value.isEmpty || value == 'null') {
      return const {};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
      }
    } catch (_) {
      // Fall back to empty on parse error — see [_parseFilterBoolMap].
    }
    return const {};
  }

  /// Normalise the persisted `critical_alert_sound` string into the allowed
  /// values. Unknown strings fall back to the system bell (the safest default
  /// — silence-on-typo would defeat the whole point of an audible alert).
  String _normaliseCriticalAlertSound(String? value) {
    switch (value) {
      case 'none':
        return 'none';
      case 'systemBell':
      case null:
        return 'systemBell';
      default:
        return 'systemBell';
    }
  }

  double _parseDouble(String? value, double defaultValue) {
    if (value == null) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  int _parseInt(String? value, int defaultValue) {
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  SafetyFailMode _parseSafetyFailMode(String? value) {
    if (value == null) return SafetyFailMode.failClosed;
    return switch (value) {
      'failOpen' => SafetyFailMode.failOpen,
      'failClosed' => SafetyFailMode.failClosed,
      'warnOnly' => SafetyFailMode.warnOnly,
      _ => SafetyFailMode.failClosed,
    };
  }
}
