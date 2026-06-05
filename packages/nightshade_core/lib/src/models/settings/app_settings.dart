import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Default accent color hex — matches `NightshadeColors.dark.primary` (#5B9EC4).
const kDefaultAccentColorHex = '#5B9EC4';

/// Defines how the safety system behaves when weather/safety devices fail or are unavailable
enum SafetyFailMode {
  /// Treat unavailable safety data as safe; allow imaging to continue uninterrupted.
  failOpen,
  /// Treat unavailable safety data as unsafe; pause imaging and optionally park the mount.
  failClosed,
  /// Treat unavailable safety data as safe but emit a UI warning so the user is aware.
  warnOnly,
}

@freezed
class ObserverLocation with _$ObserverLocation {
  const factory ObserverLocation({
    required double latitude,
    required double longitude,
    required double elevation,
  }) = _ObserverLocation;

  factory ObserverLocation.fromJson(Map<String, dynamic> json) =>
      _$ObserverLocationFromJson(json);
}

@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    ObserverLocation? location,
    @Default('dark') String theme,
    @Default('en') String language,
    @Default(true) bool autoConnect,
    // Additional fields for compatibility with provider AppSettings
    @Default(0.0) double latitude,
    @Default(0.0) double longitude,
    @Default(0.0) double elevation,
    @Default('') String fileNamingPattern,
    @Default(5) int meridianFlipMinutes,
    @Default(60) int autoFocusEveryMinutes,
    @Default(3) int ditherEveryFrames,
    @Default(60) int plateSolveTimeout,
    @Default(30.0) double plateSolveSearchRadius,
    @Default('') String discordWebhook,
    @Default('') String pushoverKey,
    @Default('') String pushoverUser,
    @Default('') String astapPath,
    // Discovery settings
    @Default(true) bool autoDiscoverOnLaunch,
    @Default('') String accentColor,
    @Default('Medium') String fontSize,
    @Default('Auto') String uiScale, // Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)
    // Protocol settings
    @Default('localhost') String indiServerHost,
    @Default(7624) int indiServerPort,
    @Default(false) bool indiAutoConnect,
    @Default('localhost') String alpacaServerHost,
    @Default(11111) int alpacaServerPort,
    @Default(false) bool alpacaAutoDiscover,
    // Sequencer execution settings
    @Default(true) bool useNativeExecution,
    @Default(false) bool useSimulationMode,
    // Image capture settings
    @Default('') String imageOutputPath,
    @Default('') String observer,
    @Default('') String telescope,
    @Default('') String instrument,
    // Update settings
    @Default(true) bool updateCheckEnabled,
    @Default('') String updateServerUrl,
    @Default('stable') String updateChannel,
    @Default(24) int updateCheckIntervalHours,
    @Default('') String skippedUpdateVersion,
    // Safety settings
    @Default(SafetyFailMode.failClosed) SafetyFailMode safetyFailMode,
    // -------------------------------------------------------------------
    // Wave 3 Image Grading: live frame Pass/Reject thresholds. Opt-in:
    // disabled by default so existing users keep current behaviour
    // (every captured frame saved, none auto-rejected).
    // -------------------------------------------------------------------
    /// Master switch: when false, no grading runs at all.
    @Default(false) bool enableImageGrading,
    /// Reject if HFR exceeds this absolute pixel value. `null` => don't
    /// apply the absolute check.
    double? imageGradingHfrThresholdPx,
    /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. `null` =>
    /// don't apply the baseline-relative check.
    double? imageGradingHfrBaselinePercent,
    /// Reject if star eccentricity exceeds this value. `null` => don't apply.
    double? imageGradingEccentricityThreshold,
    /// Reject if detected star count falls below this. `null` => don't apply.
    int? imageGradingStarCountMin,
    /// Pause sequence after this many consecutive rejects (default 3).
    @Default(3) int imageGradingMaxConsecutiveRejects,
    /// Override for the reject folder. `null` => use `<save_path>/Reject/`.
    /// Relative paths resolve against the run save_path; absolute paths
    /// are used verbatim.
    String? imageGradingRejectFolderPath,
    // -------------------------------------------------------------------
    // Wave 5 Agent 2 — Sky-brightness adaptive exposures: global defaults.
    // Per-ExposureNode overrides still win at runtime; these are the
    // values pushed into the executor via
    // `sequencerUpdateDefaultAdaptiveExposure` when none of the active
    // nodes carry their own block.
    // -------------------------------------------------------------------
    /// Master switch — when false, the global default adaptive-exposure
    /// is cleared and the executor falls back to nominal duration for
    /// any node without an explicit per-node override.
    @Default(false) bool adaptiveExposureEnabled,
    /// Target SNR for the SNR-based scaling (informational; the live
    /// math uses background flux ratio).
    @Default(30.0) double adaptiveExposureTargetSnr,
    /// Reference sky brightness in mag/arcsec² the nominal exposure
    /// duration was calibrated for. Dark-site default is 21.5.
    @Default(21.5) double adaptiveExposureReferenceMag,
    /// Global minimum exposure clamp in seconds.
    @Default(5.0) double adaptiveExposureMinSecs,
    /// Global maximum exposure clamp in seconds.
    @Default(600.0) double adaptiveExposureMaxSecs,
    /// Per-filter enable map (filter name -> bool). Empty => apply
    /// globally (matches the Rust `is_enabled_for_filter` semantics).
    @Default(<String, bool>{}) Map<String, bool>
        adaptiveExposurePerFilterEnabled,
    /// Per-filter minimum exposure overrides (seconds).
    @Default(<String, double>{}) Map<String, double>
        adaptiveExposurePerFilterMinSecs,
    /// Per-filter maximum exposure overrides (seconds).
    @Default(<String, double>{}) Map<String, double>
        adaptiveExposurePerFilterMaxSecs,
    // -------------------------------------------------------------------
    // Full-night audit 2026-06-04 follow-up — high-value unattended-night
    // knobs that previously had NO wire field, so a phone/remote save of
    // them was rejected by the `_assertKeysRemotable` fail-loud guard. These
    // round-trip the autofocus / dither / weather-safety / recovery settings
    // that an operator must be able to tune for an unattended night.
    // -------------------------------------------------------------------
    /// Weather-safety: when true, the rig parks (not just pauses) when weather
    /// turns unsafe. Mirrors `app_settings` DB key `park_on_unsafe_weather`.
    @Default(true) bool parkOnUnsafeWeather,
    /// Autofocus: run an autofocus pass on every filter change.
    /// DB key `auto_focus_on_filter_change`.
    @Default(true) bool autoFocusOnFilterChange,
    /// Autofocus: disable the guider while an autofocus sweep runs (avoids the
    /// guide star wandering out of frame during the focuser sweep).
    /// DB key `af_disable_guiding`.
    @Default(false) bool afDisableGuidingDuringAf,
    /// Dither: master enable for between-frame dithering.
    /// DB key `dither_enabled`.
    @Default(true) bool ditherEnabled,
    /// Dither: dither step size — 'Small', 'Medium', or 'Large'.
    /// DB key `dither_scale`.
    @Default('Medium') String ditherScale,
    /// Recovery: minutes between auto-retry attempts during a recovery loop.
    /// DB key `recovery_default_retry_interval_mins`.
    @Default(10.0) double recoveryDefaultRetryIntervalMins,
    /// Recovery: total minutes before the recovery loop gives up.
    /// DB key `recovery_default_max_duration_mins`.
    @Default(90.0) double recoveryDefaultMaxDurationMins,
    /// Recovery: stop tracking while recovering (dew/cloud wait).
    /// DB key `recovery_stop_tracking_during_recovery`.
    @Default(true) bool recoveryStopTrackingDuringRecovery,
    /// Recovery: abort the recovery loop if a meridian crossing falls inside
    /// the recovery window. DB key `recovery_abort_on_meridian`.
    @Default(true) bool recoveryAbortOnMeridian,
    /// Recovery: ring the platform alert sound on recovery entry.
    /// DB key `recovery_audible_alert_when_entered`.
    @Default(true) bool recoveryAudibleAlertWhenEntered,
    // -------------------------------------------------------------------
    // Full-night audit 2026-06-04 follow-up (long tail) — the remaining
    // high-value unattended-night knobs that `_applySettingsMap` already
    // maps into AppSettingsState but which had NO wire field, so a remote
    // save of them was rejected by the `_assertKeysRemotable` fail-loud
    // guard. Carrying them here lets a phone-driven night keep them.
    // -------------------------------------------------------------------
    // Weather-safety / dawn.
    /// Park the mount before astronomical dawn at the end of the night.
    /// DB key `park_before_dawn`.
    @Default(true) bool parkBeforeDawn,
    // Meridian flip detail.
    /// Master enable for automatic meridian flips. DB key `enable_meridian_flip`.
    @Default(true) bool enableMeridianFlip,
    // Focuser temperature compensation + backlash (calibration).
    /// Enable focuser temperature compensation. DB key `temp_compensation`.
    @Default(true) bool tempCompensation,
    /// Temp-comp coefficient (steps per °C). DB key `temp_coefficient`.
    @Default(-12.0) double tempCoefficient,
    /// Focuser backlash compensation (steps). DB key `backlash_compensation`.
    @Default(0) int backlashCompensation,
    // Guider settle (calibration).
    /// Guider settle pixel threshold. DB key `settle_threshold`.
    @Default(0.5) double settleThreshold,
    /// Guider settle timeout in seconds. DB key `settle_timeout`.
    @Default(30) int settleTimeout,
    // Plate-solving extra.
    /// Selected plate solver ('ASTAP', 'Astrometry.net', 'PlateSolve2').
    /// DB key `plate_solver`.
    @Default('ASTAP') String plateSolver,
    /// Allow a blind (no-hint) solve fallback. DB key `blind_solve`.
    @Default(false) bool blindSolve,
    // Site / horizon.
    /// Bortle dark-sky class (1-9). DB key `bortle_class`.
    @Default(5) int bortleClass,
    /// Effective horizon altitude floor in degrees. DB key `effective_horizon_deg`.
    @Default(0.0) double effectiveHorizonDeg,
    // Pre-flight checklist strictness + freshness gates.
    /// Pre-flight strictness as the enum name ('lax' / 'normal' / 'strict').
    /// Carried as a String to avoid the wire model depending on the provider
    /// library that owns the `PreflightStrictness` enum. DB key
    /// `preflight_strictness`.
    @Default('normal') String preflightStrictness,
    /// Polar-alignment max age (days) before pre-flight flags it.
    /// DB key `polar_alignment_max_age_days`.
    @Default(7) int polarAlignmentMaxAgeDays,
    /// Optical-train drift threshold (arcmin) before pre-flight flags it.
    /// DB key `optical_train_drift_threshold`.
    @Default(8.0) double opticalTrainDriftThreshold,
    // Dark library.
    /// Minimum matching dark frames before the dark library is "covered".
    /// DB key `dark_library_min_coverage`.
    @Default(10) int darkLibraryMinCoverage,
    // -------------------------------------------------------------------
    // Smart Night defaults — the one-click "plan tonight" builder reads these
    // when assembling a sequence, so an unattended night planned from a phone
    // must carry them.
    // -------------------------------------------------------------------
    /// Cap a planned session to this many hours. `null` => use the full dark
    /// window. DB key `smart_night_max_session_hours`.
    double? smartNightMaxSessionHours,
    /// Default autofocus cadence (frames) for built sequences.
    /// DB key `smart_night_default_af_cadence_frames`.
    @Default(25) int smartNightDefaultAfCadenceFrames,
    /// Default per-target integration budget (minutes).
    /// DB key `smart_night_default_integration_budget_mins_per_target`.
    @Default(240) int smartNightDefaultIntegrationBudgetMinsPerTarget,
    /// Append flats at the end of the planned night.
    /// DB key `smart_night_include_flats_at_end`.
    @Default(true) bool smartNightIncludeFlatsAtEnd,
    /// Use the scheduler (vs a single linear sequence) for multi-target nights.
    /// DB key `smart_night_use_scheduler_for_multi_target`.
    @Default(true) bool smartNightUseSchedulerForMultiTarget,
    /// Target count at/above which the scheduler is used.
    /// DB key `smart_night_scheduler_target_threshold`.
    @Default(3) int smartNightSchedulerTargetThreshold,
    /// Default capture strategy id (e.g. 'auto_lrgb').
    /// DB key `smart_night_default_strategy`.
    @Default('auto_lrgb') String smartNightDefaultStrategy,
    /// Days after which polar alignment is considered stale for the wizard.
    /// DB key `smart_night_polar_alignment_stale_after_days`.
    @Default(7) int smartNightPolarAlignmentStaleAfterDays,
    /// Sub-exposure floor (seconds) for the planner.
    /// DB key `smart_night_sub_exposure_floor_secs`.
    @Default(30.0) double smartNightSubExposureFloorSecs,
    /// Sub-exposure ceiling (seconds) for the planner.
    /// DB key `smart_night_sub_exposure_ceiling_secs`.
    @Default(300.0) double smartNightSubExposureCeilingSecs,
    /// Target SNR the planner sizes sub-exposures toward.
    /// DB key `smart_night_target_snr`.
    @Default(30.0) double smartNightTargetSnr,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}

// Extension to provide compatibility getters
extension AppSettingsExtension on AppSettings {
  /// Get latitude from location or direct field
  double get effectiveLatitude => this.location?.latitude ?? this.latitude;
  
  /// Get longitude from location or direct field
  double get effectiveLongitude => this.location?.longitude ?? this.longitude;
  
  /// Get elevation from location or direct field
  double get effectiveElevation => this.location?.elevation ?? this.elevation;
}
