// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ObserverLocation _$ObserverLocationFromJson(Map<String, dynamic> json) {
  return _ObserverLocation.fromJson(json);
}

/// @nodoc
mixin _$ObserverLocation {
  double get latitude => throw _privateConstructorUsedError;
  double get longitude => throw _privateConstructorUsedError;
  double get elevation => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ObserverLocationCopyWith<ObserverLocation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ObserverLocationCopyWith<$Res> {
  factory $ObserverLocationCopyWith(
          ObserverLocation value, $Res Function(ObserverLocation) then) =
      _$ObserverLocationCopyWithImpl<$Res, ObserverLocation>;
  @useResult
  $Res call({double latitude, double longitude, double elevation});
}

/// @nodoc
class _$ObserverLocationCopyWithImpl<$Res, $Val extends ObserverLocation>
    implements $ObserverLocationCopyWith<$Res> {
  _$ObserverLocationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latitude = null,
    Object? longitude = null,
    Object? elevation = null,
  }) {
    return _then(_value.copyWith(
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
      elevation: null == elevation
          ? _value.elevation
          : elevation // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ObserverLocationImplCopyWith<$Res>
    implements $ObserverLocationCopyWith<$Res> {
  factory _$$ObserverLocationImplCopyWith(_$ObserverLocationImpl value,
          $Res Function(_$ObserverLocationImpl) then) =
      __$$ObserverLocationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double latitude, double longitude, double elevation});
}

/// @nodoc
class __$$ObserverLocationImplCopyWithImpl<$Res>
    extends _$ObserverLocationCopyWithImpl<$Res, _$ObserverLocationImpl>
    implements _$$ObserverLocationImplCopyWith<$Res> {
  __$$ObserverLocationImplCopyWithImpl(_$ObserverLocationImpl _value,
      $Res Function(_$ObserverLocationImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latitude = null,
    Object? longitude = null,
    Object? elevation = null,
  }) {
    return _then(_$ObserverLocationImpl(
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
      elevation: null == elevation
          ? _value.elevation
          : elevation // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ObserverLocationImpl implements _ObserverLocation {
  const _$ObserverLocationImpl(
      {required this.latitude,
      required this.longitude,
      required this.elevation});

  factory _$ObserverLocationImpl.fromJson(Map<String, dynamic> json) =>
      _$$ObserverLocationImplFromJson(json);

  @override
  final double latitude;
  @override
  final double longitude;
  @override
  final double elevation;

  @override
  String toString() {
    return 'ObserverLocation(latitude: $latitude, longitude: $longitude, elevation: $elevation)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ObserverLocationImpl &&
            (identical(other.latitude, latitude) ||
                other.latitude == latitude) &&
            (identical(other.longitude, longitude) ||
                other.longitude == longitude) &&
            (identical(other.elevation, elevation) ||
                other.elevation == elevation));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, latitude, longitude, elevation);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ObserverLocationImplCopyWith<_$ObserverLocationImpl> get copyWith =>
      __$$ObserverLocationImplCopyWithImpl<_$ObserverLocationImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ObserverLocationImplToJson(
      this,
    );
  }
}

abstract class _ObserverLocation implements ObserverLocation {
  const factory _ObserverLocation(
      {required final double latitude,
      required final double longitude,
      required final double elevation}) = _$ObserverLocationImpl;

  factory _ObserverLocation.fromJson(Map<String, dynamic> json) =
      _$ObserverLocationImpl.fromJson;

  @override
  double get latitude;
  @override
  double get longitude;
  @override
  double get elevation;
  @override
  @JsonKey(ignore: true)
  _$$ObserverLocationImplCopyWith<_$ObserverLocationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) {
  return _AppSettings.fromJson(json);
}

/// @nodoc
mixin _$AppSettings {
  ObserverLocation? get location => throw _privateConstructorUsedError;
  String get theme => throw _privateConstructorUsedError;
  String get language => throw _privateConstructorUsedError;
  bool get autoConnect =>
      throw _privateConstructorUsedError; // Additional fields for compatibility with provider AppSettings
  double get latitude => throw _privateConstructorUsedError;
  double get longitude => throw _privateConstructorUsedError;
  double get elevation => throw _privateConstructorUsedError;
  String get fileNamingPattern => throw _privateConstructorUsedError;
  int get meridianFlipMinutes => throw _privateConstructorUsedError;
  int get autoFocusEveryMinutes => throw _privateConstructorUsedError;
  int get ditherEveryFrames => throw _privateConstructorUsedError;
  int get plateSolveTimeout => throw _privateConstructorUsedError;
  double get plateSolveSearchRadius => throw _privateConstructorUsedError;
  String get discordWebhook => throw _privateConstructorUsedError;
  String get pushoverKey => throw _privateConstructorUsedError;
  String get pushoverUser => throw _privateConstructorUsedError;
  String get astapPath =>
      throw _privateConstructorUsedError; // Discovery settings
  bool get autoDiscoverOnLaunch => throw _privateConstructorUsedError;
  String get accentColor => throw _privateConstructorUsedError;
  String get fontSize => throw _privateConstructorUsedError;
  String get uiScale =>
      throw _privateConstructorUsedError; // Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)
// Protocol settings
  String get indiServerHost => throw _privateConstructorUsedError;
  int get indiServerPort => throw _privateConstructorUsedError;
  bool get indiAutoConnect => throw _privateConstructorUsedError;
  String get alpacaServerHost => throw _privateConstructorUsedError;
  int get alpacaServerPort => throw _privateConstructorUsedError;
  bool get alpacaAutoDiscover =>
      throw _privateConstructorUsedError; // Sequencer execution settings
  bool get useNativeExecution => throw _privateConstructorUsedError;
  bool get useSimulationMode =>
      throw _privateConstructorUsedError; // Image capture settings
  String get imageOutputPath => throw _privateConstructorUsedError;
  String get observer => throw _privateConstructorUsedError;
  String get telescope => throw _privateConstructorUsedError;
  String get instrument =>
      throw _privateConstructorUsedError; // Update settings
  bool get updateCheckEnabled => throw _privateConstructorUsedError;
  String get updateServerUrl => throw _privateConstructorUsedError;
  String get updateChannel => throw _privateConstructorUsedError;
  int get updateCheckIntervalHours => throw _privateConstructorUsedError;
  String get skippedUpdateVersion =>
      throw _privateConstructorUsedError; // Safety settings
  SafetyFailMode get safetyFailMode =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Wave 3 Image Grading: live frame Pass/Reject thresholds. Opt-in:
// disabled by default so existing users keep current behaviour
// (every captured frame saved, none auto-rejected).
// -------------------------------------------------------------------
  /// Master switch: when false, no grading runs at all.
  bool get enableImageGrading => throw _privateConstructorUsedError;

  /// Reject if HFR exceeds this absolute pixel value. `null` => don't
  /// apply the absolute check.
  double? get imageGradingHfrThresholdPx => throw _privateConstructorUsedError;

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. `null` =>
  /// don't apply the baseline-relative check.
  double? get imageGradingHfrBaselinePercent =>
      throw _privateConstructorUsedError;

  /// Reject if star eccentricity exceeds this value. `null` => don't apply.
  double? get imageGradingEccentricityThreshold =>
      throw _privateConstructorUsedError;

  /// Reject if detected star count falls below this. `null` => don't apply.
  int? get imageGradingStarCountMin => throw _privateConstructorUsedError;

  /// Pause sequence after this many consecutive rejects (default 3).
  int get imageGradingMaxConsecutiveRejects =>
      throw _privateConstructorUsedError;

  /// Override for the reject folder. `null` => use `<save_path>/Reject/`.
  /// Relative paths resolve against the run save_path; absolute paths
  /// are used verbatim.
  String? get imageGradingRejectFolderPath =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Wave 5 Agent 2 — Sky-brightness adaptive exposures: global defaults.
// Per-ExposureNode overrides still win at runtime; these are the
// values pushed into the executor via
// `sequencerUpdateDefaultAdaptiveExposure` when none of the active
// nodes carry their own block.
// -------------------------------------------------------------------
  /// Master switch — when false, the global default adaptive-exposure
  /// is cleared and the executor falls back to nominal duration for
  /// any node without an explicit per-node override.
  bool get adaptiveExposureEnabled => throw _privateConstructorUsedError;

  /// Target SNR for the SNR-based scaling (informational; the live
  /// math uses background flux ratio).
  double get adaptiveExposureTargetSnr => throw _privateConstructorUsedError;

  /// Reference sky brightness in mag/arcsec² the nominal exposure
  /// duration was calibrated for. Dark-site default is 21.5.
  double get adaptiveExposureReferenceMag => throw _privateConstructorUsedError;

  /// Global minimum exposure clamp in seconds.
  double get adaptiveExposureMinSecs => throw _privateConstructorUsedError;

  /// Global maximum exposure clamp in seconds.
  double get adaptiveExposureMaxSecs => throw _privateConstructorUsedError;

  /// Per-filter enable map (filter name -> bool). Empty => apply
  /// globally (matches the Rust `is_enabled_for_filter` semantics).
  Map<String, bool> get adaptiveExposurePerFilterEnabled =>
      throw _privateConstructorUsedError;

  /// Per-filter minimum exposure overrides (seconds).
  Map<String, double> get adaptiveExposurePerFilterMinSecs =>
      throw _privateConstructorUsedError;

  /// Per-filter maximum exposure overrides (seconds).
  Map<String, double> get adaptiveExposurePerFilterMaxSecs =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Full-night audit 2026-06-04 follow-up — high-value unattended-night
// knobs that previously had NO wire field, so a phone/remote save of
// them was rejected by the `_assertKeysRemotable` fail-loud guard. These
// round-trip the autofocus / dither / weather-safety / recovery settings
// that an operator must be able to tune for an unattended night.
// -------------------------------------------------------------------
  /// Weather-safety: when true, the rig parks (not just pauses) when weather
  /// turns unsafe. Mirrors `app_settings` DB key `park_on_unsafe_weather`.
  bool get parkOnUnsafeWeather => throw _privateConstructorUsedError;

  /// Autofocus: run an autofocus pass on every filter change.
  /// DB key `auto_focus_on_filter_change`.
  bool get autoFocusOnFilterChange => throw _privateConstructorUsedError;

  /// Autofocus: disable the guider while an autofocus sweep runs (avoids the
  /// guide star wandering out of frame during the focuser sweep).
  /// DB key `af_disable_guiding`.
  bool get afDisableGuidingDuringAf => throw _privateConstructorUsedError;

  /// Dither: master enable for between-frame dithering.
  /// DB key `dither_enabled`.
  bool get ditherEnabled => throw _privateConstructorUsedError;

  /// Dither: dither step size — 'Small', 'Medium', or 'Large'.
  /// DB key `dither_scale`.
  String get ditherScale => throw _privateConstructorUsedError;

  /// Recovery: minutes between auto-retry attempts during a recovery loop.
  /// DB key `recovery_default_retry_interval_mins`.
  double get recoveryDefaultRetryIntervalMins =>
      throw _privateConstructorUsedError;

  /// Recovery: total minutes before the recovery loop gives up.
  /// DB key `recovery_default_max_duration_mins`.
  double get recoveryDefaultMaxDurationMins =>
      throw _privateConstructorUsedError;

  /// Recovery: stop tracking while recovering (dew/cloud wait).
  /// DB key `recovery_stop_tracking_during_recovery`.
  bool get recoveryStopTrackingDuringRecovery =>
      throw _privateConstructorUsedError;

  /// Recovery: abort the recovery loop if a meridian crossing falls inside
  /// the recovery window. DB key `recovery_abort_on_meridian`.
  bool get recoveryAbortOnMeridian => throw _privateConstructorUsedError;

  /// Recovery: ring the platform alert sound on recovery entry.
  /// DB key `recovery_audible_alert_when_entered`.
  bool get recoveryAudibleAlertWhenEntered =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Full-night audit 2026-06-04 follow-up (long tail) — the remaining
// high-value unattended-night knobs that `_applySettingsMap` already
// maps into AppSettingsState but which had NO wire field, so a remote
// save of them was rejected by the `_assertKeysRemotable` fail-loud
// guard. Carrying them here lets a phone-driven night keep them.
// -------------------------------------------------------------------
// Weather-safety / dawn.
  /// Park the mount before astronomical dawn at the end of the night.
  /// DB key `park_before_dawn`.
  bool get parkBeforeDawn =>
      throw _privateConstructorUsedError; // Meridian flip detail.
  /// Master enable for automatic meridian flips. DB key `enable_meridian_flip`.
  bool get enableMeridianFlip =>
      throw _privateConstructorUsedError; // Focuser temperature compensation + backlash (calibration).
  /// Enable focuser temperature compensation. DB key `temp_compensation`.
  bool get tempCompensation => throw _privateConstructorUsedError;

  /// Temp-comp coefficient (steps per °C). DB key `temp_coefficient`.
  double get tempCoefficient => throw _privateConstructorUsedError;

  /// Focuser backlash compensation (steps). DB key `backlash_compensation`.
  int get backlashCompensation =>
      throw _privateConstructorUsedError; // Guider settle (calibration).
  /// Guider settle pixel threshold. DB key `settle_threshold`.
  double get settleThreshold => throw _privateConstructorUsedError;

  /// Guider settle timeout in seconds. DB key `settle_timeout`.
  int get settleTimeout =>
      throw _privateConstructorUsedError; // Plate-solving extra.
  /// Selected plate solver ('ASTAP', 'Astrometry.net', 'PlateSolve2').
  /// DB key `plate_solver`.
  String get plateSolver => throw _privateConstructorUsedError;

  /// Allow a blind (no-hint) solve fallback. DB key `blind_solve`.
  bool get blindSolve => throw _privateConstructorUsedError; // Site / horizon.
  /// Bortle dark-sky class (1-9). DB key `bortle_class`.
  int get bortleClass => throw _privateConstructorUsedError;

  /// Effective horizon altitude floor in degrees. DB key `effective_horizon_deg`.
  double get effectiveHorizonDeg =>
      throw _privateConstructorUsedError; // Pre-flight checklist strictness + freshness gates.
  /// Pre-flight strictness as the enum name ('lax' / 'normal' / 'strict').
  /// Carried as a String to avoid the wire model depending on the provider
  /// library that owns the `PreflightStrictness` enum. DB key
  /// `preflight_strictness`.
  String get preflightStrictness => throw _privateConstructorUsedError;

  /// Polar-alignment max age (days) before pre-flight flags it.
  /// DB key `polar_alignment_max_age_days`.
  int get polarAlignmentMaxAgeDays => throw _privateConstructorUsedError;

  /// Optical-train drift threshold (arcmin) before pre-flight flags it.
  /// DB key `optical_train_drift_threshold`.
  double get opticalTrainDriftThreshold =>
      throw _privateConstructorUsedError; // Dark library.
  /// Minimum matching dark frames before the dark library is "covered".
  /// DB key `dark_library_min_coverage`.
  int get darkLibraryMinCoverage =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Smart Night defaults — the one-click "plan tonight" builder reads these
// when assembling a sequence, so an unattended night planned from a phone
// must carry them.
// -------------------------------------------------------------------
  /// Cap a planned session to this many hours. `null` => use the full dark
  /// window. DB key `smart_night_max_session_hours`.
  double? get smartNightMaxSessionHours => throw _privateConstructorUsedError;

  /// Default autofocus cadence (frames) for built sequences.
  /// DB key `smart_night_default_af_cadence_frames`.
  int get smartNightDefaultAfCadenceFrames =>
      throw _privateConstructorUsedError;

  /// Default per-target integration budget (minutes).
  /// DB key `smart_night_default_integration_budget_mins_per_target`.
  int get smartNightDefaultIntegrationBudgetMinsPerTarget =>
      throw _privateConstructorUsedError;

  /// Append flats at the end of the planned night.
  /// DB key `smart_night_include_flats_at_end`.
  bool get smartNightIncludeFlatsAtEnd => throw _privateConstructorUsedError;

  /// Use the scheduler (vs a single linear sequence) for multi-target nights.
  /// DB key `smart_night_use_scheduler_for_multi_target`.
  bool get smartNightUseSchedulerForMultiTarget =>
      throw _privateConstructorUsedError;

  /// Target count at/above which the scheduler is used.
  /// DB key `smart_night_scheduler_target_threshold`.
  int get smartNightSchedulerTargetThreshold =>
      throw _privateConstructorUsedError;

  /// Default capture strategy id (e.g. 'auto_lrgb').
  /// DB key `smart_night_default_strategy`.
  String get smartNightDefaultStrategy => throw _privateConstructorUsedError;

  /// Days after which polar alignment is considered stale for the wizard.
  /// DB key `smart_night_polar_alignment_stale_after_days`.
  int get smartNightPolarAlignmentStaleAfterDays =>
      throw _privateConstructorUsedError;

  /// Sub-exposure floor (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_floor_secs`.
  double get smartNightSubExposureFloorSecs =>
      throw _privateConstructorUsedError;

  /// Sub-exposure ceiling (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_ceiling_secs`.
  double get smartNightSubExposureCeilingSecs =>
      throw _privateConstructorUsedError;

  /// Target SNR the planner sizes sub-exposures toward.
  /// DB key `smart_night_target_snr`.
  double get smartNightTargetSnr =>
      throw _privateConstructorUsedError; // -------------------------------------------------------------------
// Full remote-settings parity 2026-06-05 — the remaining setter-reachable
// knobs that `_applySettingsMap` already maps into AppSettingsState but
// which had NO wire field, so a phone/remote save of them was rejected by
// the `_assertKeysRemotable` fail-loud guard. Carrying them here completes
// the unattended-night knob set so a phone can edit the whole config.
// The defaults mirror AppSettingsState's constructor defaults so the wire
// model never injects a different value than local state.
// -------------------------------------------------------------------
// Equipment defaults (camera).
  /// Cooling behaviour: 'On Connect' / 'Manual' / 'Never'. DB `cooling_behavior`.
  String get coolingBehavior => throw _privateConstructorUsedError;

  /// Default camera gain. DB `default_gain`.
  int get defaultGain => throw _privateConstructorUsedError;

  /// Default camera offset. DB `default_offset`.
  int get defaultOffset =>
      throw _privateConstructorUsedError; // Remote access / web server.
  /// Headless web server enabled. DB `web_server_enabled`.
  bool get webServerEnabled => throw _privateConstructorUsedError;

  /// Headless web server port. DB `web_server_port`.
  int get webServerPort =>
      throw _privateConstructorUsedError; // PHD2 connection.
  /// PHD2 executable path. DB `phd2_path`.
  String get phd2Path => throw _privateConstructorUsedError;

  /// PHD2 host. DB `phd2_host`.
  String get phd2Host => throw _privateConstructorUsedError;

  /// PHD2 port. DB `phd2_port`.
  int get phd2Port =>
      throw _privateConstructorUsedError; // Notification toggles.
  /// Master notifications switch. DB `notifications_enabled`.
  bool get notificationsEnabled => throw _privateConstructorUsedError;

  /// Notify when a sequence completes. DB `notify_on_sequence_complete`.
  bool get notifyOnSequenceComplete => throw _privateConstructorUsedError;

  /// Notify on error. DB `notify_on_error`.
  bool get notifyOnError => throw _privateConstructorUsedError;

  /// Notify on meridian flip. DB `notify_on_meridian_flip`.
  bool get notifyOnMeridianFlip => throw _privateConstructorUsedError;

  /// In-app notification sound. DB `sound_enabled`.
  bool get soundEnabled => throw _privateConstructorUsedError;

  /// Ring the platform alert on critical-severity events. DB
  /// `audible_alerts_on_critical`.
  bool get audibleAlertsOnCritical => throw _privateConstructorUsedError;

  /// Which sound for critical alerts ('systemBell' / 'none'). DB
  /// `critical_alert_sound`.
  String get criticalAlertSound => throw _privateConstructorUsedError;

  /// Forward critical alerts to paired phones as push. DB `push_critical_alerts`.
  bool get pushCriticalAlerts =>
      throw _privateConstructorUsedError; // Session-lifecycle + campaign-rollup prefs.
  /// Show the Smart-Night auto-prompt when equipment is ready. DB
  /// `smart_night.auto_prompt_enabled`.
  bool get smartNightAutoPromptEnabled => throw _privateConstructorUsedError;

  /// Prompt for notes after a run. DB `notes.prompt_after_run`.
  bool get promptForNotesAfterRun => throw _privateConstructorUsedError;

  /// Auto-open the multi-night carry-over banner. DB
  /// `session.handoff_auto_prompt`.
  bool get sessionHandoffAutoPrompt => throw _privateConstructorUsedError;

  /// Surface the campaign-rollup column on the Targets tab. DB
  /// `campaign_rollup.surface_targets_tab`.
  bool get campaignRollupSurfaceTargetsTab =>
      throw _privateConstructorUsedError;

  /// Campaign-rollup grouping mode. DB `campaign_rollup.grouping_mode`.
  String get campaignRollupGroupingMode =>
      throw _privateConstructorUsedError; // Autofocus detailed sweep params.
  /// AF method. DB `af_method`.
  String get afMethod => throw _privateConstructorUsedError;

  /// AF curve fitting. DB `af_curve_fitting`.
  String get afCurveFitting => throw _privateConstructorUsedError;

  /// AF step size between measurement points. DB `af_step_size`.
  int get afStepSize => throw _privateConstructorUsedError;

  /// AF exposure time (seconds). DB `af_exposure_time`.
  double get afExposureTime => throw _privateConstructorUsedError;

  /// AF initial offset steps out from center. DB `af_initial_offset_steps`.
  int get afInitialOffsetSteps => throw _privateConstructorUsedError;

  /// AF retry count on failure. DB `af_number_of_attempts`.
  int get afNumberOfAttempts => throw _privateConstructorUsedError;

  /// AF brightest-N stars (0 = all). DB `af_use_brightest_n_stars`.
  int get afUseBrightestNStars => throw _privateConstructorUsedError;

  /// AF outer crop ratio. DB `af_outer_crop_ratio`.
  double get afOuterCropRatio => throw _privateConstructorUsedError;

  /// AF inner crop ratio. DB `af_inner_crop_ratio`.
  double get afInnerCropRatio => throw _privateConstructorUsedError;

  /// AF binning. DB `af_binning`.
  int get afBinning => throw _privateConstructorUsedError;

  /// AF R² fit-quality threshold. DB `af_r_squared_threshold`.
  double get afRSquaredThreshold => throw _privateConstructorUsedError;

  /// AF focuser settle time (ms). DB `af_focuser_settle_time_ms`.
  int get afFocuserSettleTimeMs => throw _privateConstructorUsedError;

  /// AF exposures per measurement point. DB `af_exposures_per_point`.
  int get afExposuresPerPoint => throw _privateConstructorUsedError;

  /// AF backlash compensation method. DB `af_backlash_comp_method`.
  String get afBacklashCompMethod => throw _privateConstructorUsedError;

  /// AF backlash-in steps. DB `af_backlash_in`.
  int get afBacklashIn => throw _privateConstructorUsedError;

  /// AF backlash-out steps. DB `af_backlash_out`.
  int get afBacklashOut => throw _privateConstructorUsedError;

  /// Designated AF filter (empty = current). DB `af_autofocus_filter_name`.
  String get afAutofocusFilterName => throw _privateConstructorUsedError;

  /// Per-filter AF config JSON map. DB `af_filter_settings`.
  String get afFilterSettingsJson => throw _privateConstructorUsedError;

  /// Apply focus offsets on filter change. DB `use_filter_focus_offsets`.
  bool get useFilterFocusOffsets =>
      throw _privateConstructorUsedError; // Misc imaging / FITS / plate-solve config relevant to an unattended night.
  /// Astrometry.net solver path. DB `astrometry_path`.
  String get astrometryPath => throw _privateConstructorUsedError;

  /// FITS OBSERVER keyword. DB `observer_name`.
  String get observerName => throw _privateConstructorUsedError;

  /// Image format ('FITS' / 'XISF' / 'TIFF'). DB `image_format`.
  String get imageFormat => throw _privateConstructorUsedError;

  /// Bit depth ('16-bit' / '32-bit'). DB `bit_depth`.
  String get bitDepth => throw _privateConstructorUsedError;

  /// Observing timezone. DB `timezone`.
  String get timezone => throw _privateConstructorUsedError;

  /// Use system time vs a fixed observing time. DB `use_system_time`.
  bool get useSystemTime => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AppSettingsCopyWith<AppSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppSettingsCopyWith<$Res> {
  factory $AppSettingsCopyWith(
          AppSettings value, $Res Function(AppSettings) then) =
      _$AppSettingsCopyWithImpl<$Res, AppSettings>;
  @useResult
  $Res call(
      {ObserverLocation? location,
      String theme,
      String language,
      bool autoConnect,
      double latitude,
      double longitude,
      double elevation,
      String fileNamingPattern,
      int meridianFlipMinutes,
      int autoFocusEveryMinutes,
      int ditherEveryFrames,
      int plateSolveTimeout,
      double plateSolveSearchRadius,
      String discordWebhook,
      String pushoverKey,
      String pushoverUser,
      String astapPath,
      bool autoDiscoverOnLaunch,
      String accentColor,
      String fontSize,
      String uiScale,
      String indiServerHost,
      int indiServerPort,
      bool indiAutoConnect,
      String alpacaServerHost,
      int alpacaServerPort,
      bool alpacaAutoDiscover,
      bool useNativeExecution,
      bool useSimulationMode,
      String imageOutputPath,
      String observer,
      String telescope,
      String instrument,
      bool updateCheckEnabled,
      String updateServerUrl,
      String updateChannel,
      int updateCheckIntervalHours,
      String skippedUpdateVersion,
      SafetyFailMode safetyFailMode,
      bool enableImageGrading,
      double? imageGradingHfrThresholdPx,
      double? imageGradingHfrBaselinePercent,
      double? imageGradingEccentricityThreshold,
      int? imageGradingStarCountMin,
      int imageGradingMaxConsecutiveRejects,
      String? imageGradingRejectFolderPath,
      bool adaptiveExposureEnabled,
      double adaptiveExposureTargetSnr,
      double adaptiveExposureReferenceMag,
      double adaptiveExposureMinSecs,
      double adaptiveExposureMaxSecs,
      Map<String, bool> adaptiveExposurePerFilterEnabled,
      Map<String, double> adaptiveExposurePerFilterMinSecs,
      Map<String, double> adaptiveExposurePerFilterMaxSecs,
      bool parkOnUnsafeWeather,
      bool autoFocusOnFilterChange,
      bool afDisableGuidingDuringAf,
      bool ditherEnabled,
      String ditherScale,
      double recoveryDefaultRetryIntervalMins,
      double recoveryDefaultMaxDurationMins,
      bool recoveryStopTrackingDuringRecovery,
      bool recoveryAbortOnMeridian,
      bool recoveryAudibleAlertWhenEntered,
      bool parkBeforeDawn,
      bool enableMeridianFlip,
      bool tempCompensation,
      double tempCoefficient,
      int backlashCompensation,
      double settleThreshold,
      int settleTimeout,
      String plateSolver,
      bool blindSolve,
      int bortleClass,
      double effectiveHorizonDeg,
      String preflightStrictness,
      int polarAlignmentMaxAgeDays,
      double opticalTrainDriftThreshold,
      int darkLibraryMinCoverage,
      double? smartNightMaxSessionHours,
      int smartNightDefaultAfCadenceFrames,
      int smartNightDefaultIntegrationBudgetMinsPerTarget,
      bool smartNightIncludeFlatsAtEnd,
      bool smartNightUseSchedulerForMultiTarget,
      int smartNightSchedulerTargetThreshold,
      String smartNightDefaultStrategy,
      int smartNightPolarAlignmentStaleAfterDays,
      double smartNightSubExposureFloorSecs,
      double smartNightSubExposureCeilingSecs,
      double smartNightTargetSnr,
      String coolingBehavior,
      int defaultGain,
      int defaultOffset,
      bool webServerEnabled,
      int webServerPort,
      String phd2Path,
      String phd2Host,
      int phd2Port,
      bool notificationsEnabled,
      bool notifyOnSequenceComplete,
      bool notifyOnError,
      bool notifyOnMeridianFlip,
      bool soundEnabled,
      bool audibleAlertsOnCritical,
      String criticalAlertSound,
      bool pushCriticalAlerts,
      bool smartNightAutoPromptEnabled,
      bool promptForNotesAfterRun,
      bool sessionHandoffAutoPrompt,
      bool campaignRollupSurfaceTargetsTab,
      String campaignRollupGroupingMode,
      String afMethod,
      String afCurveFitting,
      int afStepSize,
      double afExposureTime,
      int afInitialOffsetSteps,
      int afNumberOfAttempts,
      int afUseBrightestNStars,
      double afOuterCropRatio,
      double afInnerCropRatio,
      int afBinning,
      double afRSquaredThreshold,
      int afFocuserSettleTimeMs,
      int afExposuresPerPoint,
      String afBacklashCompMethod,
      int afBacklashIn,
      int afBacklashOut,
      String afAutofocusFilterName,
      String afFilterSettingsJson,
      bool useFilterFocusOffsets,
      String astrometryPath,
      String observerName,
      String imageFormat,
      String bitDepth,
      String timezone,
      bool useSystemTime});

  $ObserverLocationCopyWith<$Res>? get location;
}

/// @nodoc
class _$AppSettingsCopyWithImpl<$Res, $Val extends AppSettings>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? location = freezed,
    Object? theme = null,
    Object? language = null,
    Object? autoConnect = null,
    Object? latitude = null,
    Object? longitude = null,
    Object? elevation = null,
    Object? fileNamingPattern = null,
    Object? meridianFlipMinutes = null,
    Object? autoFocusEveryMinutes = null,
    Object? ditherEveryFrames = null,
    Object? plateSolveTimeout = null,
    Object? plateSolveSearchRadius = null,
    Object? discordWebhook = null,
    Object? pushoverKey = null,
    Object? pushoverUser = null,
    Object? astapPath = null,
    Object? autoDiscoverOnLaunch = null,
    Object? accentColor = null,
    Object? fontSize = null,
    Object? uiScale = null,
    Object? indiServerHost = null,
    Object? indiServerPort = null,
    Object? indiAutoConnect = null,
    Object? alpacaServerHost = null,
    Object? alpacaServerPort = null,
    Object? alpacaAutoDiscover = null,
    Object? useNativeExecution = null,
    Object? useSimulationMode = null,
    Object? imageOutputPath = null,
    Object? observer = null,
    Object? telescope = null,
    Object? instrument = null,
    Object? updateCheckEnabled = null,
    Object? updateServerUrl = null,
    Object? updateChannel = null,
    Object? updateCheckIntervalHours = null,
    Object? skippedUpdateVersion = null,
    Object? safetyFailMode = null,
    Object? enableImageGrading = null,
    Object? imageGradingHfrThresholdPx = freezed,
    Object? imageGradingHfrBaselinePercent = freezed,
    Object? imageGradingEccentricityThreshold = freezed,
    Object? imageGradingStarCountMin = freezed,
    Object? imageGradingMaxConsecutiveRejects = null,
    Object? imageGradingRejectFolderPath = freezed,
    Object? adaptiveExposureEnabled = null,
    Object? adaptiveExposureTargetSnr = null,
    Object? adaptiveExposureReferenceMag = null,
    Object? adaptiveExposureMinSecs = null,
    Object? adaptiveExposureMaxSecs = null,
    Object? adaptiveExposurePerFilterEnabled = null,
    Object? adaptiveExposurePerFilterMinSecs = null,
    Object? adaptiveExposurePerFilterMaxSecs = null,
    Object? parkOnUnsafeWeather = null,
    Object? autoFocusOnFilterChange = null,
    Object? afDisableGuidingDuringAf = null,
    Object? ditherEnabled = null,
    Object? ditherScale = null,
    Object? recoveryDefaultRetryIntervalMins = null,
    Object? recoveryDefaultMaxDurationMins = null,
    Object? recoveryStopTrackingDuringRecovery = null,
    Object? recoveryAbortOnMeridian = null,
    Object? recoveryAudibleAlertWhenEntered = null,
    Object? parkBeforeDawn = null,
    Object? enableMeridianFlip = null,
    Object? tempCompensation = null,
    Object? tempCoefficient = null,
    Object? backlashCompensation = null,
    Object? settleThreshold = null,
    Object? settleTimeout = null,
    Object? plateSolver = null,
    Object? blindSolve = null,
    Object? bortleClass = null,
    Object? effectiveHorizonDeg = null,
    Object? preflightStrictness = null,
    Object? polarAlignmentMaxAgeDays = null,
    Object? opticalTrainDriftThreshold = null,
    Object? darkLibraryMinCoverage = null,
    Object? smartNightMaxSessionHours = freezed,
    Object? smartNightDefaultAfCadenceFrames = null,
    Object? smartNightDefaultIntegrationBudgetMinsPerTarget = null,
    Object? smartNightIncludeFlatsAtEnd = null,
    Object? smartNightUseSchedulerForMultiTarget = null,
    Object? smartNightSchedulerTargetThreshold = null,
    Object? smartNightDefaultStrategy = null,
    Object? smartNightPolarAlignmentStaleAfterDays = null,
    Object? smartNightSubExposureFloorSecs = null,
    Object? smartNightSubExposureCeilingSecs = null,
    Object? smartNightTargetSnr = null,
    Object? coolingBehavior = null,
    Object? defaultGain = null,
    Object? defaultOffset = null,
    Object? webServerEnabled = null,
    Object? webServerPort = null,
    Object? phd2Path = null,
    Object? phd2Host = null,
    Object? phd2Port = null,
    Object? notificationsEnabled = null,
    Object? notifyOnSequenceComplete = null,
    Object? notifyOnError = null,
    Object? notifyOnMeridianFlip = null,
    Object? soundEnabled = null,
    Object? audibleAlertsOnCritical = null,
    Object? criticalAlertSound = null,
    Object? pushCriticalAlerts = null,
    Object? smartNightAutoPromptEnabled = null,
    Object? promptForNotesAfterRun = null,
    Object? sessionHandoffAutoPrompt = null,
    Object? campaignRollupSurfaceTargetsTab = null,
    Object? campaignRollupGroupingMode = null,
    Object? afMethod = null,
    Object? afCurveFitting = null,
    Object? afStepSize = null,
    Object? afExposureTime = null,
    Object? afInitialOffsetSteps = null,
    Object? afNumberOfAttempts = null,
    Object? afUseBrightestNStars = null,
    Object? afOuterCropRatio = null,
    Object? afInnerCropRatio = null,
    Object? afBinning = null,
    Object? afRSquaredThreshold = null,
    Object? afFocuserSettleTimeMs = null,
    Object? afExposuresPerPoint = null,
    Object? afBacklashCompMethod = null,
    Object? afBacklashIn = null,
    Object? afBacklashOut = null,
    Object? afAutofocusFilterName = null,
    Object? afFilterSettingsJson = null,
    Object? useFilterFocusOffsets = null,
    Object? astrometryPath = null,
    Object? observerName = null,
    Object? imageFormat = null,
    Object? bitDepth = null,
    Object? timezone = null,
    Object? useSystemTime = null,
  }) {
    return _then(_value.copyWith(
      location: freezed == location
          ? _value.location
          : location // ignore: cast_nullable_to_non_nullable
              as ObserverLocation?,
      theme: null == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String,
      language: null == language
          ? _value.language
          : language // ignore: cast_nullable_to_non_nullable
              as String,
      autoConnect: null == autoConnect
          ? _value.autoConnect
          : autoConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
      elevation: null == elevation
          ? _value.elevation
          : elevation // ignore: cast_nullable_to_non_nullable
              as double,
      fileNamingPattern: null == fileNamingPattern
          ? _value.fileNamingPattern
          : fileNamingPattern // ignore: cast_nullable_to_non_nullable
              as String,
      meridianFlipMinutes: null == meridianFlipMinutes
          ? _value.meridianFlipMinutes
          : meridianFlipMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      autoFocusEveryMinutes: null == autoFocusEveryMinutes
          ? _value.autoFocusEveryMinutes
          : autoFocusEveryMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      ditherEveryFrames: null == ditherEveryFrames
          ? _value.ditherEveryFrames
          : ditherEveryFrames // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolveTimeout: null == plateSolveTimeout
          ? _value.plateSolveTimeout
          : plateSolveTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolveSearchRadius: null == plateSolveSearchRadius
          ? _value.plateSolveSearchRadius
          : plateSolveSearchRadius // ignore: cast_nullable_to_non_nullable
              as double,
      discordWebhook: null == discordWebhook
          ? _value.discordWebhook
          : discordWebhook // ignore: cast_nullable_to_non_nullable
              as String,
      pushoverKey: null == pushoverKey
          ? _value.pushoverKey
          : pushoverKey // ignore: cast_nullable_to_non_nullable
              as String,
      pushoverUser: null == pushoverUser
          ? _value.pushoverUser
          : pushoverUser // ignore: cast_nullable_to_non_nullable
              as String,
      astapPath: null == astapPath
          ? _value.astapPath
          : astapPath // ignore: cast_nullable_to_non_nullable
              as String,
      autoDiscoverOnLaunch: null == autoDiscoverOnLaunch
          ? _value.autoDiscoverOnLaunch
          : autoDiscoverOnLaunch // ignore: cast_nullable_to_non_nullable
              as bool,
      accentColor: null == accentColor
          ? _value.accentColor
          : accentColor // ignore: cast_nullable_to_non_nullable
              as String,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as String,
      uiScale: null == uiScale
          ? _value.uiScale
          : uiScale // ignore: cast_nullable_to_non_nullable
              as String,
      indiServerHost: null == indiServerHost
          ? _value.indiServerHost
          : indiServerHost // ignore: cast_nullable_to_non_nullable
              as String,
      indiServerPort: null == indiServerPort
          ? _value.indiServerPort
          : indiServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      indiAutoConnect: null == indiAutoConnect
          ? _value.indiAutoConnect
          : indiAutoConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      alpacaServerHost: null == alpacaServerHost
          ? _value.alpacaServerHost
          : alpacaServerHost // ignore: cast_nullable_to_non_nullable
              as String,
      alpacaServerPort: null == alpacaServerPort
          ? _value.alpacaServerPort
          : alpacaServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      alpacaAutoDiscover: null == alpacaAutoDiscover
          ? _value.alpacaAutoDiscover
          : alpacaAutoDiscover // ignore: cast_nullable_to_non_nullable
              as bool,
      useNativeExecution: null == useNativeExecution
          ? _value.useNativeExecution
          : useNativeExecution // ignore: cast_nullable_to_non_nullable
              as bool,
      useSimulationMode: null == useSimulationMode
          ? _value.useSimulationMode
          : useSimulationMode // ignore: cast_nullable_to_non_nullable
              as bool,
      imageOutputPath: null == imageOutputPath
          ? _value.imageOutputPath
          : imageOutputPath // ignore: cast_nullable_to_non_nullable
              as String,
      observer: null == observer
          ? _value.observer
          : observer // ignore: cast_nullable_to_non_nullable
              as String,
      telescope: null == telescope
          ? _value.telescope
          : telescope // ignore: cast_nullable_to_non_nullable
              as String,
      instrument: null == instrument
          ? _value.instrument
          : instrument // ignore: cast_nullable_to_non_nullable
              as String,
      updateCheckEnabled: null == updateCheckEnabled
          ? _value.updateCheckEnabled
          : updateCheckEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      updateServerUrl: null == updateServerUrl
          ? _value.updateServerUrl
          : updateServerUrl // ignore: cast_nullable_to_non_nullable
              as String,
      updateChannel: null == updateChannel
          ? _value.updateChannel
          : updateChannel // ignore: cast_nullable_to_non_nullable
              as String,
      updateCheckIntervalHours: null == updateCheckIntervalHours
          ? _value.updateCheckIntervalHours
          : updateCheckIntervalHours // ignore: cast_nullable_to_non_nullable
              as int,
      skippedUpdateVersion: null == skippedUpdateVersion
          ? _value.skippedUpdateVersion
          : skippedUpdateVersion // ignore: cast_nullable_to_non_nullable
              as String,
      safetyFailMode: null == safetyFailMode
          ? _value.safetyFailMode
          : safetyFailMode // ignore: cast_nullable_to_non_nullable
              as SafetyFailMode,
      enableImageGrading: null == enableImageGrading
          ? _value.enableImageGrading
          : enableImageGrading // ignore: cast_nullable_to_non_nullable
              as bool,
      imageGradingHfrThresholdPx: freezed == imageGradingHfrThresholdPx
          ? _value.imageGradingHfrThresholdPx
          : imageGradingHfrThresholdPx // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingHfrBaselinePercent: freezed == imageGradingHfrBaselinePercent
          ? _value.imageGradingHfrBaselinePercent
          : imageGradingHfrBaselinePercent // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingEccentricityThreshold: freezed ==
              imageGradingEccentricityThreshold
          ? _value.imageGradingEccentricityThreshold
          : imageGradingEccentricityThreshold // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingStarCountMin: freezed == imageGradingStarCountMin
          ? _value.imageGradingStarCountMin
          : imageGradingStarCountMin // ignore: cast_nullable_to_non_nullable
              as int?,
      imageGradingMaxConsecutiveRejects: null ==
              imageGradingMaxConsecutiveRejects
          ? _value.imageGradingMaxConsecutiveRejects
          : imageGradingMaxConsecutiveRejects // ignore: cast_nullable_to_non_nullable
              as int,
      imageGradingRejectFolderPath: freezed == imageGradingRejectFolderPath
          ? _value.imageGradingRejectFolderPath
          : imageGradingRejectFolderPath // ignore: cast_nullable_to_non_nullable
              as String?,
      adaptiveExposureEnabled: null == adaptiveExposureEnabled
          ? _value.adaptiveExposureEnabled
          : adaptiveExposureEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      adaptiveExposureTargetSnr: null == adaptiveExposureTargetSnr
          ? _value.adaptiveExposureTargetSnr
          : adaptiveExposureTargetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureReferenceMag: null == adaptiveExposureReferenceMag
          ? _value.adaptiveExposureReferenceMag
          : adaptiveExposureReferenceMag // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureMinSecs: null == adaptiveExposureMinSecs
          ? _value.adaptiveExposureMinSecs
          : adaptiveExposureMinSecs // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureMaxSecs: null == adaptiveExposureMaxSecs
          ? _value.adaptiveExposureMaxSecs
          : adaptiveExposureMaxSecs // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposurePerFilterEnabled: null == adaptiveExposurePerFilterEnabled
          ? _value.adaptiveExposurePerFilterEnabled
          : adaptiveExposurePerFilterEnabled // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      adaptiveExposurePerFilterMinSecs: null == adaptiveExposurePerFilterMinSecs
          ? _value.adaptiveExposurePerFilterMinSecs
          : adaptiveExposurePerFilterMinSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      adaptiveExposurePerFilterMaxSecs: null == adaptiveExposurePerFilterMaxSecs
          ? _value.adaptiveExposurePerFilterMaxSecs
          : adaptiveExposurePerFilterMaxSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      parkOnUnsafeWeather: null == parkOnUnsafeWeather
          ? _value.parkOnUnsafeWeather
          : parkOnUnsafeWeather // ignore: cast_nullable_to_non_nullable
              as bool,
      autoFocusOnFilterChange: null == autoFocusOnFilterChange
          ? _value.autoFocusOnFilterChange
          : autoFocusOnFilterChange // ignore: cast_nullable_to_non_nullable
              as bool,
      afDisableGuidingDuringAf: null == afDisableGuidingDuringAf
          ? _value.afDisableGuidingDuringAf
          : afDisableGuidingDuringAf // ignore: cast_nullable_to_non_nullable
              as bool,
      ditherEnabled: null == ditherEnabled
          ? _value.ditherEnabled
          : ditherEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      ditherScale: null == ditherScale
          ? _value.ditherScale
          : ditherScale // ignore: cast_nullable_to_non_nullable
              as String,
      recoveryDefaultRetryIntervalMins: null == recoveryDefaultRetryIntervalMins
          ? _value.recoveryDefaultRetryIntervalMins
          : recoveryDefaultRetryIntervalMins // ignore: cast_nullable_to_non_nullable
              as double,
      recoveryDefaultMaxDurationMins: null == recoveryDefaultMaxDurationMins
          ? _value.recoveryDefaultMaxDurationMins
          : recoveryDefaultMaxDurationMins // ignore: cast_nullable_to_non_nullable
              as double,
      recoveryStopTrackingDuringRecovery: null ==
              recoveryStopTrackingDuringRecovery
          ? _value.recoveryStopTrackingDuringRecovery
          : recoveryStopTrackingDuringRecovery // ignore: cast_nullable_to_non_nullable
              as bool,
      recoveryAbortOnMeridian: null == recoveryAbortOnMeridian
          ? _value.recoveryAbortOnMeridian
          : recoveryAbortOnMeridian // ignore: cast_nullable_to_non_nullable
              as bool,
      recoveryAudibleAlertWhenEntered: null == recoveryAudibleAlertWhenEntered
          ? _value.recoveryAudibleAlertWhenEntered
          : recoveryAudibleAlertWhenEntered // ignore: cast_nullable_to_non_nullable
              as bool,
      parkBeforeDawn: null == parkBeforeDawn
          ? _value.parkBeforeDawn
          : parkBeforeDawn // ignore: cast_nullable_to_non_nullable
              as bool,
      enableMeridianFlip: null == enableMeridianFlip
          ? _value.enableMeridianFlip
          : enableMeridianFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      tempCompensation: null == tempCompensation
          ? _value.tempCompensation
          : tempCompensation // ignore: cast_nullable_to_non_nullable
              as bool,
      tempCoefficient: null == tempCoefficient
          ? _value.tempCoefficient
          : tempCoefficient // ignore: cast_nullable_to_non_nullable
              as double,
      backlashCompensation: null == backlashCompensation
          ? _value.backlashCompensation
          : backlashCompensation // ignore: cast_nullable_to_non_nullable
              as int,
      settleThreshold: null == settleThreshold
          ? _value.settleThreshold
          : settleThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      settleTimeout: null == settleTimeout
          ? _value.settleTimeout
          : settleTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolver: null == plateSolver
          ? _value.plateSolver
          : plateSolver // ignore: cast_nullable_to_non_nullable
              as String,
      blindSolve: null == blindSolve
          ? _value.blindSolve
          : blindSolve // ignore: cast_nullable_to_non_nullable
              as bool,
      bortleClass: null == bortleClass
          ? _value.bortleClass
          : bortleClass // ignore: cast_nullable_to_non_nullable
              as int,
      effectiveHorizonDeg: null == effectiveHorizonDeg
          ? _value.effectiveHorizonDeg
          : effectiveHorizonDeg // ignore: cast_nullable_to_non_nullable
              as double,
      preflightStrictness: null == preflightStrictness
          ? _value.preflightStrictness
          : preflightStrictness // ignore: cast_nullable_to_non_nullable
              as String,
      polarAlignmentMaxAgeDays: null == polarAlignmentMaxAgeDays
          ? _value.polarAlignmentMaxAgeDays
          : polarAlignmentMaxAgeDays // ignore: cast_nullable_to_non_nullable
              as int,
      opticalTrainDriftThreshold: null == opticalTrainDriftThreshold
          ? _value.opticalTrainDriftThreshold
          : opticalTrainDriftThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      darkLibraryMinCoverage: null == darkLibraryMinCoverage
          ? _value.darkLibraryMinCoverage
          : darkLibraryMinCoverage // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightMaxSessionHours: freezed == smartNightMaxSessionHours
          ? _value.smartNightMaxSessionHours
          : smartNightMaxSessionHours // ignore: cast_nullable_to_non_nullable
              as double?,
      smartNightDefaultAfCadenceFrames: null == smartNightDefaultAfCadenceFrames
          ? _value.smartNightDefaultAfCadenceFrames
          : smartNightDefaultAfCadenceFrames // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightDefaultIntegrationBudgetMinsPerTarget: null ==
              smartNightDefaultIntegrationBudgetMinsPerTarget
          ? _value.smartNightDefaultIntegrationBudgetMinsPerTarget
          : smartNightDefaultIntegrationBudgetMinsPerTarget // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightIncludeFlatsAtEnd: null == smartNightIncludeFlatsAtEnd
          ? _value.smartNightIncludeFlatsAtEnd
          : smartNightIncludeFlatsAtEnd // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightUseSchedulerForMultiTarget: null ==
              smartNightUseSchedulerForMultiTarget
          ? _value.smartNightUseSchedulerForMultiTarget
          : smartNightUseSchedulerForMultiTarget // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightSchedulerTargetThreshold: null ==
              smartNightSchedulerTargetThreshold
          ? _value.smartNightSchedulerTargetThreshold
          : smartNightSchedulerTargetThreshold // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightDefaultStrategy: null == smartNightDefaultStrategy
          ? _value.smartNightDefaultStrategy
          : smartNightDefaultStrategy // ignore: cast_nullable_to_non_nullable
              as String,
      smartNightPolarAlignmentStaleAfterDays: null ==
              smartNightPolarAlignmentStaleAfterDays
          ? _value.smartNightPolarAlignmentStaleAfterDays
          : smartNightPolarAlignmentStaleAfterDays // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightSubExposureFloorSecs: null == smartNightSubExposureFloorSecs
          ? _value.smartNightSubExposureFloorSecs
          : smartNightSubExposureFloorSecs // ignore: cast_nullable_to_non_nullable
              as double,
      smartNightSubExposureCeilingSecs: null == smartNightSubExposureCeilingSecs
          ? _value.smartNightSubExposureCeilingSecs
          : smartNightSubExposureCeilingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      smartNightTargetSnr: null == smartNightTargetSnr
          ? _value.smartNightTargetSnr
          : smartNightTargetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      coolingBehavior: null == coolingBehavior
          ? _value.coolingBehavior
          : coolingBehavior // ignore: cast_nullable_to_non_nullable
              as String,
      defaultGain: null == defaultGain
          ? _value.defaultGain
          : defaultGain // ignore: cast_nullable_to_non_nullable
              as int,
      defaultOffset: null == defaultOffset
          ? _value.defaultOffset
          : defaultOffset // ignore: cast_nullable_to_non_nullable
              as int,
      webServerEnabled: null == webServerEnabled
          ? _value.webServerEnabled
          : webServerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      webServerPort: null == webServerPort
          ? _value.webServerPort
          : webServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      phd2Path: null == phd2Path
          ? _value.phd2Path
          : phd2Path // ignore: cast_nullable_to_non_nullable
              as String,
      phd2Host: null == phd2Host
          ? _value.phd2Host
          : phd2Host // ignore: cast_nullable_to_non_nullable
              as String,
      phd2Port: null == phd2Port
          ? _value.phd2Port
          : phd2Port // ignore: cast_nullable_to_non_nullable
              as int,
      notificationsEnabled: null == notificationsEnabled
          ? _value.notificationsEnabled
          : notificationsEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnSequenceComplete: null == notifyOnSequenceComplete
          ? _value.notifyOnSequenceComplete
          : notifyOnSequenceComplete // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnError: null == notifyOnError
          ? _value.notifyOnError
          : notifyOnError // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnMeridianFlip: null == notifyOnMeridianFlip
          ? _value.notifyOnMeridianFlip
          : notifyOnMeridianFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      soundEnabled: null == soundEnabled
          ? _value.soundEnabled
          : soundEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      audibleAlertsOnCritical: null == audibleAlertsOnCritical
          ? _value.audibleAlertsOnCritical
          : audibleAlertsOnCritical // ignore: cast_nullable_to_non_nullable
              as bool,
      criticalAlertSound: null == criticalAlertSound
          ? _value.criticalAlertSound
          : criticalAlertSound // ignore: cast_nullable_to_non_nullable
              as String,
      pushCriticalAlerts: null == pushCriticalAlerts
          ? _value.pushCriticalAlerts
          : pushCriticalAlerts // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightAutoPromptEnabled: null == smartNightAutoPromptEnabled
          ? _value.smartNightAutoPromptEnabled
          : smartNightAutoPromptEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      promptForNotesAfterRun: null == promptForNotesAfterRun
          ? _value.promptForNotesAfterRun
          : promptForNotesAfterRun // ignore: cast_nullable_to_non_nullable
              as bool,
      sessionHandoffAutoPrompt: null == sessionHandoffAutoPrompt
          ? _value.sessionHandoffAutoPrompt
          : sessionHandoffAutoPrompt // ignore: cast_nullable_to_non_nullable
              as bool,
      campaignRollupSurfaceTargetsTab: null == campaignRollupSurfaceTargetsTab
          ? _value.campaignRollupSurfaceTargetsTab
          : campaignRollupSurfaceTargetsTab // ignore: cast_nullable_to_non_nullable
              as bool,
      campaignRollupGroupingMode: null == campaignRollupGroupingMode
          ? _value.campaignRollupGroupingMode
          : campaignRollupGroupingMode // ignore: cast_nullable_to_non_nullable
              as String,
      afMethod: null == afMethod
          ? _value.afMethod
          : afMethod // ignore: cast_nullable_to_non_nullable
              as String,
      afCurveFitting: null == afCurveFitting
          ? _value.afCurveFitting
          : afCurveFitting // ignore: cast_nullable_to_non_nullable
              as String,
      afStepSize: null == afStepSize
          ? _value.afStepSize
          : afStepSize // ignore: cast_nullable_to_non_nullable
              as int,
      afExposureTime: null == afExposureTime
          ? _value.afExposureTime
          : afExposureTime // ignore: cast_nullable_to_non_nullable
              as double,
      afInitialOffsetSteps: null == afInitialOffsetSteps
          ? _value.afInitialOffsetSteps
          : afInitialOffsetSteps // ignore: cast_nullable_to_non_nullable
              as int,
      afNumberOfAttempts: null == afNumberOfAttempts
          ? _value.afNumberOfAttempts
          : afNumberOfAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      afUseBrightestNStars: null == afUseBrightestNStars
          ? _value.afUseBrightestNStars
          : afUseBrightestNStars // ignore: cast_nullable_to_non_nullable
              as int,
      afOuterCropRatio: null == afOuterCropRatio
          ? _value.afOuterCropRatio
          : afOuterCropRatio // ignore: cast_nullable_to_non_nullable
              as double,
      afInnerCropRatio: null == afInnerCropRatio
          ? _value.afInnerCropRatio
          : afInnerCropRatio // ignore: cast_nullable_to_non_nullable
              as double,
      afBinning: null == afBinning
          ? _value.afBinning
          : afBinning // ignore: cast_nullable_to_non_nullable
              as int,
      afRSquaredThreshold: null == afRSquaredThreshold
          ? _value.afRSquaredThreshold
          : afRSquaredThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      afFocuserSettleTimeMs: null == afFocuserSettleTimeMs
          ? _value.afFocuserSettleTimeMs
          : afFocuserSettleTimeMs // ignore: cast_nullable_to_non_nullable
              as int,
      afExposuresPerPoint: null == afExposuresPerPoint
          ? _value.afExposuresPerPoint
          : afExposuresPerPoint // ignore: cast_nullable_to_non_nullable
              as int,
      afBacklashCompMethod: null == afBacklashCompMethod
          ? _value.afBacklashCompMethod
          : afBacklashCompMethod // ignore: cast_nullable_to_non_nullable
              as String,
      afBacklashIn: null == afBacklashIn
          ? _value.afBacklashIn
          : afBacklashIn // ignore: cast_nullable_to_non_nullable
              as int,
      afBacklashOut: null == afBacklashOut
          ? _value.afBacklashOut
          : afBacklashOut // ignore: cast_nullable_to_non_nullable
              as int,
      afAutofocusFilterName: null == afAutofocusFilterName
          ? _value.afAutofocusFilterName
          : afAutofocusFilterName // ignore: cast_nullable_to_non_nullable
              as String,
      afFilterSettingsJson: null == afFilterSettingsJson
          ? _value.afFilterSettingsJson
          : afFilterSettingsJson // ignore: cast_nullable_to_non_nullable
              as String,
      useFilterFocusOffsets: null == useFilterFocusOffsets
          ? _value.useFilterFocusOffsets
          : useFilterFocusOffsets // ignore: cast_nullable_to_non_nullable
              as bool,
      astrometryPath: null == astrometryPath
          ? _value.astrometryPath
          : astrometryPath // ignore: cast_nullable_to_non_nullable
              as String,
      observerName: null == observerName
          ? _value.observerName
          : observerName // ignore: cast_nullable_to_non_nullable
              as String,
      imageFormat: null == imageFormat
          ? _value.imageFormat
          : imageFormat // ignore: cast_nullable_to_non_nullable
              as String,
      bitDepth: null == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as String,
      timezone: null == timezone
          ? _value.timezone
          : timezone // ignore: cast_nullable_to_non_nullable
              as String,
      useSystemTime: null == useSystemTime
          ? _value.useSystemTime
          : useSystemTime // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ObserverLocationCopyWith<$Res>? get location {
    if (_value.location == null) {
      return null;
    }

    return $ObserverLocationCopyWith<$Res>(_value.location!, (value) {
      return _then(_value.copyWith(location: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$AppSettingsImplCopyWith<$Res>
    implements $AppSettingsCopyWith<$Res> {
  factory _$$AppSettingsImplCopyWith(
          _$AppSettingsImpl value, $Res Function(_$AppSettingsImpl) then) =
      __$$AppSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {ObserverLocation? location,
      String theme,
      String language,
      bool autoConnect,
      double latitude,
      double longitude,
      double elevation,
      String fileNamingPattern,
      int meridianFlipMinutes,
      int autoFocusEveryMinutes,
      int ditherEveryFrames,
      int plateSolveTimeout,
      double plateSolveSearchRadius,
      String discordWebhook,
      String pushoverKey,
      String pushoverUser,
      String astapPath,
      bool autoDiscoverOnLaunch,
      String accentColor,
      String fontSize,
      String uiScale,
      String indiServerHost,
      int indiServerPort,
      bool indiAutoConnect,
      String alpacaServerHost,
      int alpacaServerPort,
      bool alpacaAutoDiscover,
      bool useNativeExecution,
      bool useSimulationMode,
      String imageOutputPath,
      String observer,
      String telescope,
      String instrument,
      bool updateCheckEnabled,
      String updateServerUrl,
      String updateChannel,
      int updateCheckIntervalHours,
      String skippedUpdateVersion,
      SafetyFailMode safetyFailMode,
      bool enableImageGrading,
      double? imageGradingHfrThresholdPx,
      double? imageGradingHfrBaselinePercent,
      double? imageGradingEccentricityThreshold,
      int? imageGradingStarCountMin,
      int imageGradingMaxConsecutiveRejects,
      String? imageGradingRejectFolderPath,
      bool adaptiveExposureEnabled,
      double adaptiveExposureTargetSnr,
      double adaptiveExposureReferenceMag,
      double adaptiveExposureMinSecs,
      double adaptiveExposureMaxSecs,
      Map<String, bool> adaptiveExposurePerFilterEnabled,
      Map<String, double> adaptiveExposurePerFilterMinSecs,
      Map<String, double> adaptiveExposurePerFilterMaxSecs,
      bool parkOnUnsafeWeather,
      bool autoFocusOnFilterChange,
      bool afDisableGuidingDuringAf,
      bool ditherEnabled,
      String ditherScale,
      double recoveryDefaultRetryIntervalMins,
      double recoveryDefaultMaxDurationMins,
      bool recoveryStopTrackingDuringRecovery,
      bool recoveryAbortOnMeridian,
      bool recoveryAudibleAlertWhenEntered,
      bool parkBeforeDawn,
      bool enableMeridianFlip,
      bool tempCompensation,
      double tempCoefficient,
      int backlashCompensation,
      double settleThreshold,
      int settleTimeout,
      String plateSolver,
      bool blindSolve,
      int bortleClass,
      double effectiveHorizonDeg,
      String preflightStrictness,
      int polarAlignmentMaxAgeDays,
      double opticalTrainDriftThreshold,
      int darkLibraryMinCoverage,
      double? smartNightMaxSessionHours,
      int smartNightDefaultAfCadenceFrames,
      int smartNightDefaultIntegrationBudgetMinsPerTarget,
      bool smartNightIncludeFlatsAtEnd,
      bool smartNightUseSchedulerForMultiTarget,
      int smartNightSchedulerTargetThreshold,
      String smartNightDefaultStrategy,
      int smartNightPolarAlignmentStaleAfterDays,
      double smartNightSubExposureFloorSecs,
      double smartNightSubExposureCeilingSecs,
      double smartNightTargetSnr,
      String coolingBehavior,
      int defaultGain,
      int defaultOffset,
      bool webServerEnabled,
      int webServerPort,
      String phd2Path,
      String phd2Host,
      int phd2Port,
      bool notificationsEnabled,
      bool notifyOnSequenceComplete,
      bool notifyOnError,
      bool notifyOnMeridianFlip,
      bool soundEnabled,
      bool audibleAlertsOnCritical,
      String criticalAlertSound,
      bool pushCriticalAlerts,
      bool smartNightAutoPromptEnabled,
      bool promptForNotesAfterRun,
      bool sessionHandoffAutoPrompt,
      bool campaignRollupSurfaceTargetsTab,
      String campaignRollupGroupingMode,
      String afMethod,
      String afCurveFitting,
      int afStepSize,
      double afExposureTime,
      int afInitialOffsetSteps,
      int afNumberOfAttempts,
      int afUseBrightestNStars,
      double afOuterCropRatio,
      double afInnerCropRatio,
      int afBinning,
      double afRSquaredThreshold,
      int afFocuserSettleTimeMs,
      int afExposuresPerPoint,
      String afBacklashCompMethod,
      int afBacklashIn,
      int afBacklashOut,
      String afAutofocusFilterName,
      String afFilterSettingsJson,
      bool useFilterFocusOffsets,
      String astrometryPath,
      String observerName,
      String imageFormat,
      String bitDepth,
      String timezone,
      bool useSystemTime});

  @override
  $ObserverLocationCopyWith<$Res>? get location;
}

/// @nodoc
class __$$AppSettingsImplCopyWithImpl<$Res>
    extends _$AppSettingsCopyWithImpl<$Res, _$AppSettingsImpl>
    implements _$$AppSettingsImplCopyWith<$Res> {
  __$$AppSettingsImplCopyWithImpl(
      _$AppSettingsImpl _value, $Res Function(_$AppSettingsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? location = freezed,
    Object? theme = null,
    Object? language = null,
    Object? autoConnect = null,
    Object? latitude = null,
    Object? longitude = null,
    Object? elevation = null,
    Object? fileNamingPattern = null,
    Object? meridianFlipMinutes = null,
    Object? autoFocusEveryMinutes = null,
    Object? ditherEveryFrames = null,
    Object? plateSolveTimeout = null,
    Object? plateSolveSearchRadius = null,
    Object? discordWebhook = null,
    Object? pushoverKey = null,
    Object? pushoverUser = null,
    Object? astapPath = null,
    Object? autoDiscoverOnLaunch = null,
    Object? accentColor = null,
    Object? fontSize = null,
    Object? uiScale = null,
    Object? indiServerHost = null,
    Object? indiServerPort = null,
    Object? indiAutoConnect = null,
    Object? alpacaServerHost = null,
    Object? alpacaServerPort = null,
    Object? alpacaAutoDiscover = null,
    Object? useNativeExecution = null,
    Object? useSimulationMode = null,
    Object? imageOutputPath = null,
    Object? observer = null,
    Object? telescope = null,
    Object? instrument = null,
    Object? updateCheckEnabled = null,
    Object? updateServerUrl = null,
    Object? updateChannel = null,
    Object? updateCheckIntervalHours = null,
    Object? skippedUpdateVersion = null,
    Object? safetyFailMode = null,
    Object? enableImageGrading = null,
    Object? imageGradingHfrThresholdPx = freezed,
    Object? imageGradingHfrBaselinePercent = freezed,
    Object? imageGradingEccentricityThreshold = freezed,
    Object? imageGradingStarCountMin = freezed,
    Object? imageGradingMaxConsecutiveRejects = null,
    Object? imageGradingRejectFolderPath = freezed,
    Object? adaptiveExposureEnabled = null,
    Object? adaptiveExposureTargetSnr = null,
    Object? adaptiveExposureReferenceMag = null,
    Object? adaptiveExposureMinSecs = null,
    Object? adaptiveExposureMaxSecs = null,
    Object? adaptiveExposurePerFilterEnabled = null,
    Object? adaptiveExposurePerFilterMinSecs = null,
    Object? adaptiveExposurePerFilterMaxSecs = null,
    Object? parkOnUnsafeWeather = null,
    Object? autoFocusOnFilterChange = null,
    Object? afDisableGuidingDuringAf = null,
    Object? ditherEnabled = null,
    Object? ditherScale = null,
    Object? recoveryDefaultRetryIntervalMins = null,
    Object? recoveryDefaultMaxDurationMins = null,
    Object? recoveryStopTrackingDuringRecovery = null,
    Object? recoveryAbortOnMeridian = null,
    Object? recoveryAudibleAlertWhenEntered = null,
    Object? parkBeforeDawn = null,
    Object? enableMeridianFlip = null,
    Object? tempCompensation = null,
    Object? tempCoefficient = null,
    Object? backlashCompensation = null,
    Object? settleThreshold = null,
    Object? settleTimeout = null,
    Object? plateSolver = null,
    Object? blindSolve = null,
    Object? bortleClass = null,
    Object? effectiveHorizonDeg = null,
    Object? preflightStrictness = null,
    Object? polarAlignmentMaxAgeDays = null,
    Object? opticalTrainDriftThreshold = null,
    Object? darkLibraryMinCoverage = null,
    Object? smartNightMaxSessionHours = freezed,
    Object? smartNightDefaultAfCadenceFrames = null,
    Object? smartNightDefaultIntegrationBudgetMinsPerTarget = null,
    Object? smartNightIncludeFlatsAtEnd = null,
    Object? smartNightUseSchedulerForMultiTarget = null,
    Object? smartNightSchedulerTargetThreshold = null,
    Object? smartNightDefaultStrategy = null,
    Object? smartNightPolarAlignmentStaleAfterDays = null,
    Object? smartNightSubExposureFloorSecs = null,
    Object? smartNightSubExposureCeilingSecs = null,
    Object? smartNightTargetSnr = null,
    Object? coolingBehavior = null,
    Object? defaultGain = null,
    Object? defaultOffset = null,
    Object? webServerEnabled = null,
    Object? webServerPort = null,
    Object? phd2Path = null,
    Object? phd2Host = null,
    Object? phd2Port = null,
    Object? notificationsEnabled = null,
    Object? notifyOnSequenceComplete = null,
    Object? notifyOnError = null,
    Object? notifyOnMeridianFlip = null,
    Object? soundEnabled = null,
    Object? audibleAlertsOnCritical = null,
    Object? criticalAlertSound = null,
    Object? pushCriticalAlerts = null,
    Object? smartNightAutoPromptEnabled = null,
    Object? promptForNotesAfterRun = null,
    Object? sessionHandoffAutoPrompt = null,
    Object? campaignRollupSurfaceTargetsTab = null,
    Object? campaignRollupGroupingMode = null,
    Object? afMethod = null,
    Object? afCurveFitting = null,
    Object? afStepSize = null,
    Object? afExposureTime = null,
    Object? afInitialOffsetSteps = null,
    Object? afNumberOfAttempts = null,
    Object? afUseBrightestNStars = null,
    Object? afOuterCropRatio = null,
    Object? afInnerCropRatio = null,
    Object? afBinning = null,
    Object? afRSquaredThreshold = null,
    Object? afFocuserSettleTimeMs = null,
    Object? afExposuresPerPoint = null,
    Object? afBacklashCompMethod = null,
    Object? afBacklashIn = null,
    Object? afBacklashOut = null,
    Object? afAutofocusFilterName = null,
    Object? afFilterSettingsJson = null,
    Object? useFilterFocusOffsets = null,
    Object? astrometryPath = null,
    Object? observerName = null,
    Object? imageFormat = null,
    Object? bitDepth = null,
    Object? timezone = null,
    Object? useSystemTime = null,
  }) {
    return _then(_$AppSettingsImpl(
      location: freezed == location
          ? _value.location
          : location // ignore: cast_nullable_to_non_nullable
              as ObserverLocation?,
      theme: null == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String,
      language: null == language
          ? _value.language
          : language // ignore: cast_nullable_to_non_nullable
              as String,
      autoConnect: null == autoConnect
          ? _value.autoConnect
          : autoConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
      elevation: null == elevation
          ? _value.elevation
          : elevation // ignore: cast_nullable_to_non_nullable
              as double,
      fileNamingPattern: null == fileNamingPattern
          ? _value.fileNamingPattern
          : fileNamingPattern // ignore: cast_nullable_to_non_nullable
              as String,
      meridianFlipMinutes: null == meridianFlipMinutes
          ? _value.meridianFlipMinutes
          : meridianFlipMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      autoFocusEveryMinutes: null == autoFocusEveryMinutes
          ? _value.autoFocusEveryMinutes
          : autoFocusEveryMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      ditherEveryFrames: null == ditherEveryFrames
          ? _value.ditherEveryFrames
          : ditherEveryFrames // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolveTimeout: null == plateSolveTimeout
          ? _value.plateSolveTimeout
          : plateSolveTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolveSearchRadius: null == plateSolveSearchRadius
          ? _value.plateSolveSearchRadius
          : plateSolveSearchRadius // ignore: cast_nullable_to_non_nullable
              as double,
      discordWebhook: null == discordWebhook
          ? _value.discordWebhook
          : discordWebhook // ignore: cast_nullable_to_non_nullable
              as String,
      pushoverKey: null == pushoverKey
          ? _value.pushoverKey
          : pushoverKey // ignore: cast_nullable_to_non_nullable
              as String,
      pushoverUser: null == pushoverUser
          ? _value.pushoverUser
          : pushoverUser // ignore: cast_nullable_to_non_nullable
              as String,
      astapPath: null == astapPath
          ? _value.astapPath
          : astapPath // ignore: cast_nullable_to_non_nullable
              as String,
      autoDiscoverOnLaunch: null == autoDiscoverOnLaunch
          ? _value.autoDiscoverOnLaunch
          : autoDiscoverOnLaunch // ignore: cast_nullable_to_non_nullable
              as bool,
      accentColor: null == accentColor
          ? _value.accentColor
          : accentColor // ignore: cast_nullable_to_non_nullable
              as String,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as String,
      uiScale: null == uiScale
          ? _value.uiScale
          : uiScale // ignore: cast_nullable_to_non_nullable
              as String,
      indiServerHost: null == indiServerHost
          ? _value.indiServerHost
          : indiServerHost // ignore: cast_nullable_to_non_nullable
              as String,
      indiServerPort: null == indiServerPort
          ? _value.indiServerPort
          : indiServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      indiAutoConnect: null == indiAutoConnect
          ? _value.indiAutoConnect
          : indiAutoConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      alpacaServerHost: null == alpacaServerHost
          ? _value.alpacaServerHost
          : alpacaServerHost // ignore: cast_nullable_to_non_nullable
              as String,
      alpacaServerPort: null == alpacaServerPort
          ? _value.alpacaServerPort
          : alpacaServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      alpacaAutoDiscover: null == alpacaAutoDiscover
          ? _value.alpacaAutoDiscover
          : alpacaAutoDiscover // ignore: cast_nullable_to_non_nullable
              as bool,
      useNativeExecution: null == useNativeExecution
          ? _value.useNativeExecution
          : useNativeExecution // ignore: cast_nullable_to_non_nullable
              as bool,
      useSimulationMode: null == useSimulationMode
          ? _value.useSimulationMode
          : useSimulationMode // ignore: cast_nullable_to_non_nullable
              as bool,
      imageOutputPath: null == imageOutputPath
          ? _value.imageOutputPath
          : imageOutputPath // ignore: cast_nullable_to_non_nullable
              as String,
      observer: null == observer
          ? _value.observer
          : observer // ignore: cast_nullable_to_non_nullable
              as String,
      telescope: null == telescope
          ? _value.telescope
          : telescope // ignore: cast_nullable_to_non_nullable
              as String,
      instrument: null == instrument
          ? _value.instrument
          : instrument // ignore: cast_nullable_to_non_nullable
              as String,
      updateCheckEnabled: null == updateCheckEnabled
          ? _value.updateCheckEnabled
          : updateCheckEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      updateServerUrl: null == updateServerUrl
          ? _value.updateServerUrl
          : updateServerUrl // ignore: cast_nullable_to_non_nullable
              as String,
      updateChannel: null == updateChannel
          ? _value.updateChannel
          : updateChannel // ignore: cast_nullable_to_non_nullable
              as String,
      updateCheckIntervalHours: null == updateCheckIntervalHours
          ? _value.updateCheckIntervalHours
          : updateCheckIntervalHours // ignore: cast_nullable_to_non_nullable
              as int,
      skippedUpdateVersion: null == skippedUpdateVersion
          ? _value.skippedUpdateVersion
          : skippedUpdateVersion // ignore: cast_nullable_to_non_nullable
              as String,
      safetyFailMode: null == safetyFailMode
          ? _value.safetyFailMode
          : safetyFailMode // ignore: cast_nullable_to_non_nullable
              as SafetyFailMode,
      enableImageGrading: null == enableImageGrading
          ? _value.enableImageGrading
          : enableImageGrading // ignore: cast_nullable_to_non_nullable
              as bool,
      imageGradingHfrThresholdPx: freezed == imageGradingHfrThresholdPx
          ? _value.imageGradingHfrThresholdPx
          : imageGradingHfrThresholdPx // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingHfrBaselinePercent: freezed == imageGradingHfrBaselinePercent
          ? _value.imageGradingHfrBaselinePercent
          : imageGradingHfrBaselinePercent // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingEccentricityThreshold: freezed ==
              imageGradingEccentricityThreshold
          ? _value.imageGradingEccentricityThreshold
          : imageGradingEccentricityThreshold // ignore: cast_nullable_to_non_nullable
              as double?,
      imageGradingStarCountMin: freezed == imageGradingStarCountMin
          ? _value.imageGradingStarCountMin
          : imageGradingStarCountMin // ignore: cast_nullable_to_non_nullable
              as int?,
      imageGradingMaxConsecutiveRejects: null ==
              imageGradingMaxConsecutiveRejects
          ? _value.imageGradingMaxConsecutiveRejects
          : imageGradingMaxConsecutiveRejects // ignore: cast_nullable_to_non_nullable
              as int,
      imageGradingRejectFolderPath: freezed == imageGradingRejectFolderPath
          ? _value.imageGradingRejectFolderPath
          : imageGradingRejectFolderPath // ignore: cast_nullable_to_non_nullable
              as String?,
      adaptiveExposureEnabled: null == adaptiveExposureEnabled
          ? _value.adaptiveExposureEnabled
          : adaptiveExposureEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      adaptiveExposureTargetSnr: null == adaptiveExposureTargetSnr
          ? _value.adaptiveExposureTargetSnr
          : adaptiveExposureTargetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureReferenceMag: null == adaptiveExposureReferenceMag
          ? _value.adaptiveExposureReferenceMag
          : adaptiveExposureReferenceMag // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureMinSecs: null == adaptiveExposureMinSecs
          ? _value.adaptiveExposureMinSecs
          : adaptiveExposureMinSecs // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposureMaxSecs: null == adaptiveExposureMaxSecs
          ? _value.adaptiveExposureMaxSecs
          : adaptiveExposureMaxSecs // ignore: cast_nullable_to_non_nullable
              as double,
      adaptiveExposurePerFilterEnabled: null == adaptiveExposurePerFilterEnabled
          ? _value._adaptiveExposurePerFilterEnabled
          : adaptiveExposurePerFilterEnabled // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      adaptiveExposurePerFilterMinSecs: null == adaptiveExposurePerFilterMinSecs
          ? _value._adaptiveExposurePerFilterMinSecs
          : adaptiveExposurePerFilterMinSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      adaptiveExposurePerFilterMaxSecs: null == adaptiveExposurePerFilterMaxSecs
          ? _value._adaptiveExposurePerFilterMaxSecs
          : adaptiveExposurePerFilterMaxSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      parkOnUnsafeWeather: null == parkOnUnsafeWeather
          ? _value.parkOnUnsafeWeather
          : parkOnUnsafeWeather // ignore: cast_nullable_to_non_nullable
              as bool,
      autoFocusOnFilterChange: null == autoFocusOnFilterChange
          ? _value.autoFocusOnFilterChange
          : autoFocusOnFilterChange // ignore: cast_nullable_to_non_nullable
              as bool,
      afDisableGuidingDuringAf: null == afDisableGuidingDuringAf
          ? _value.afDisableGuidingDuringAf
          : afDisableGuidingDuringAf // ignore: cast_nullable_to_non_nullable
              as bool,
      ditherEnabled: null == ditherEnabled
          ? _value.ditherEnabled
          : ditherEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      ditherScale: null == ditherScale
          ? _value.ditherScale
          : ditherScale // ignore: cast_nullable_to_non_nullable
              as String,
      recoveryDefaultRetryIntervalMins: null == recoveryDefaultRetryIntervalMins
          ? _value.recoveryDefaultRetryIntervalMins
          : recoveryDefaultRetryIntervalMins // ignore: cast_nullable_to_non_nullable
              as double,
      recoveryDefaultMaxDurationMins: null == recoveryDefaultMaxDurationMins
          ? _value.recoveryDefaultMaxDurationMins
          : recoveryDefaultMaxDurationMins // ignore: cast_nullable_to_non_nullable
              as double,
      recoveryStopTrackingDuringRecovery: null ==
              recoveryStopTrackingDuringRecovery
          ? _value.recoveryStopTrackingDuringRecovery
          : recoveryStopTrackingDuringRecovery // ignore: cast_nullable_to_non_nullable
              as bool,
      recoveryAbortOnMeridian: null == recoveryAbortOnMeridian
          ? _value.recoveryAbortOnMeridian
          : recoveryAbortOnMeridian // ignore: cast_nullable_to_non_nullable
              as bool,
      recoveryAudibleAlertWhenEntered: null == recoveryAudibleAlertWhenEntered
          ? _value.recoveryAudibleAlertWhenEntered
          : recoveryAudibleAlertWhenEntered // ignore: cast_nullable_to_non_nullable
              as bool,
      parkBeforeDawn: null == parkBeforeDawn
          ? _value.parkBeforeDawn
          : parkBeforeDawn // ignore: cast_nullable_to_non_nullable
              as bool,
      enableMeridianFlip: null == enableMeridianFlip
          ? _value.enableMeridianFlip
          : enableMeridianFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      tempCompensation: null == tempCompensation
          ? _value.tempCompensation
          : tempCompensation // ignore: cast_nullable_to_non_nullable
              as bool,
      tempCoefficient: null == tempCoefficient
          ? _value.tempCoefficient
          : tempCoefficient // ignore: cast_nullable_to_non_nullable
              as double,
      backlashCompensation: null == backlashCompensation
          ? _value.backlashCompensation
          : backlashCompensation // ignore: cast_nullable_to_non_nullable
              as int,
      settleThreshold: null == settleThreshold
          ? _value.settleThreshold
          : settleThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      settleTimeout: null == settleTimeout
          ? _value.settleTimeout
          : settleTimeout // ignore: cast_nullable_to_non_nullable
              as int,
      plateSolver: null == plateSolver
          ? _value.plateSolver
          : plateSolver // ignore: cast_nullable_to_non_nullable
              as String,
      blindSolve: null == blindSolve
          ? _value.blindSolve
          : blindSolve // ignore: cast_nullable_to_non_nullable
              as bool,
      bortleClass: null == bortleClass
          ? _value.bortleClass
          : bortleClass // ignore: cast_nullable_to_non_nullable
              as int,
      effectiveHorizonDeg: null == effectiveHorizonDeg
          ? _value.effectiveHorizonDeg
          : effectiveHorizonDeg // ignore: cast_nullable_to_non_nullable
              as double,
      preflightStrictness: null == preflightStrictness
          ? _value.preflightStrictness
          : preflightStrictness // ignore: cast_nullable_to_non_nullable
              as String,
      polarAlignmentMaxAgeDays: null == polarAlignmentMaxAgeDays
          ? _value.polarAlignmentMaxAgeDays
          : polarAlignmentMaxAgeDays // ignore: cast_nullable_to_non_nullable
              as int,
      opticalTrainDriftThreshold: null == opticalTrainDriftThreshold
          ? _value.opticalTrainDriftThreshold
          : opticalTrainDriftThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      darkLibraryMinCoverage: null == darkLibraryMinCoverage
          ? _value.darkLibraryMinCoverage
          : darkLibraryMinCoverage // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightMaxSessionHours: freezed == smartNightMaxSessionHours
          ? _value.smartNightMaxSessionHours
          : smartNightMaxSessionHours // ignore: cast_nullable_to_non_nullable
              as double?,
      smartNightDefaultAfCadenceFrames: null == smartNightDefaultAfCadenceFrames
          ? _value.smartNightDefaultAfCadenceFrames
          : smartNightDefaultAfCadenceFrames // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightDefaultIntegrationBudgetMinsPerTarget: null ==
              smartNightDefaultIntegrationBudgetMinsPerTarget
          ? _value.smartNightDefaultIntegrationBudgetMinsPerTarget
          : smartNightDefaultIntegrationBudgetMinsPerTarget // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightIncludeFlatsAtEnd: null == smartNightIncludeFlatsAtEnd
          ? _value.smartNightIncludeFlatsAtEnd
          : smartNightIncludeFlatsAtEnd // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightUseSchedulerForMultiTarget: null ==
              smartNightUseSchedulerForMultiTarget
          ? _value.smartNightUseSchedulerForMultiTarget
          : smartNightUseSchedulerForMultiTarget // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightSchedulerTargetThreshold: null ==
              smartNightSchedulerTargetThreshold
          ? _value.smartNightSchedulerTargetThreshold
          : smartNightSchedulerTargetThreshold // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightDefaultStrategy: null == smartNightDefaultStrategy
          ? _value.smartNightDefaultStrategy
          : smartNightDefaultStrategy // ignore: cast_nullable_to_non_nullable
              as String,
      smartNightPolarAlignmentStaleAfterDays: null ==
              smartNightPolarAlignmentStaleAfterDays
          ? _value.smartNightPolarAlignmentStaleAfterDays
          : smartNightPolarAlignmentStaleAfterDays // ignore: cast_nullable_to_non_nullable
              as int,
      smartNightSubExposureFloorSecs: null == smartNightSubExposureFloorSecs
          ? _value.smartNightSubExposureFloorSecs
          : smartNightSubExposureFloorSecs // ignore: cast_nullable_to_non_nullable
              as double,
      smartNightSubExposureCeilingSecs: null == smartNightSubExposureCeilingSecs
          ? _value.smartNightSubExposureCeilingSecs
          : smartNightSubExposureCeilingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      smartNightTargetSnr: null == smartNightTargetSnr
          ? _value.smartNightTargetSnr
          : smartNightTargetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      coolingBehavior: null == coolingBehavior
          ? _value.coolingBehavior
          : coolingBehavior // ignore: cast_nullable_to_non_nullable
              as String,
      defaultGain: null == defaultGain
          ? _value.defaultGain
          : defaultGain // ignore: cast_nullable_to_non_nullable
              as int,
      defaultOffset: null == defaultOffset
          ? _value.defaultOffset
          : defaultOffset // ignore: cast_nullable_to_non_nullable
              as int,
      webServerEnabled: null == webServerEnabled
          ? _value.webServerEnabled
          : webServerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      webServerPort: null == webServerPort
          ? _value.webServerPort
          : webServerPort // ignore: cast_nullable_to_non_nullable
              as int,
      phd2Path: null == phd2Path
          ? _value.phd2Path
          : phd2Path // ignore: cast_nullable_to_non_nullable
              as String,
      phd2Host: null == phd2Host
          ? _value.phd2Host
          : phd2Host // ignore: cast_nullable_to_non_nullable
              as String,
      phd2Port: null == phd2Port
          ? _value.phd2Port
          : phd2Port // ignore: cast_nullable_to_non_nullable
              as int,
      notificationsEnabled: null == notificationsEnabled
          ? _value.notificationsEnabled
          : notificationsEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnSequenceComplete: null == notifyOnSequenceComplete
          ? _value.notifyOnSequenceComplete
          : notifyOnSequenceComplete // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnError: null == notifyOnError
          ? _value.notifyOnError
          : notifyOnError // ignore: cast_nullable_to_non_nullable
              as bool,
      notifyOnMeridianFlip: null == notifyOnMeridianFlip
          ? _value.notifyOnMeridianFlip
          : notifyOnMeridianFlip // ignore: cast_nullable_to_non_nullable
              as bool,
      soundEnabled: null == soundEnabled
          ? _value.soundEnabled
          : soundEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      audibleAlertsOnCritical: null == audibleAlertsOnCritical
          ? _value.audibleAlertsOnCritical
          : audibleAlertsOnCritical // ignore: cast_nullable_to_non_nullable
              as bool,
      criticalAlertSound: null == criticalAlertSound
          ? _value.criticalAlertSound
          : criticalAlertSound // ignore: cast_nullable_to_non_nullable
              as String,
      pushCriticalAlerts: null == pushCriticalAlerts
          ? _value.pushCriticalAlerts
          : pushCriticalAlerts // ignore: cast_nullable_to_non_nullable
              as bool,
      smartNightAutoPromptEnabled: null == smartNightAutoPromptEnabled
          ? _value.smartNightAutoPromptEnabled
          : smartNightAutoPromptEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      promptForNotesAfterRun: null == promptForNotesAfterRun
          ? _value.promptForNotesAfterRun
          : promptForNotesAfterRun // ignore: cast_nullable_to_non_nullable
              as bool,
      sessionHandoffAutoPrompt: null == sessionHandoffAutoPrompt
          ? _value.sessionHandoffAutoPrompt
          : sessionHandoffAutoPrompt // ignore: cast_nullable_to_non_nullable
              as bool,
      campaignRollupSurfaceTargetsTab: null == campaignRollupSurfaceTargetsTab
          ? _value.campaignRollupSurfaceTargetsTab
          : campaignRollupSurfaceTargetsTab // ignore: cast_nullable_to_non_nullable
              as bool,
      campaignRollupGroupingMode: null == campaignRollupGroupingMode
          ? _value.campaignRollupGroupingMode
          : campaignRollupGroupingMode // ignore: cast_nullable_to_non_nullable
              as String,
      afMethod: null == afMethod
          ? _value.afMethod
          : afMethod // ignore: cast_nullable_to_non_nullable
              as String,
      afCurveFitting: null == afCurveFitting
          ? _value.afCurveFitting
          : afCurveFitting // ignore: cast_nullable_to_non_nullable
              as String,
      afStepSize: null == afStepSize
          ? _value.afStepSize
          : afStepSize // ignore: cast_nullable_to_non_nullable
              as int,
      afExposureTime: null == afExposureTime
          ? _value.afExposureTime
          : afExposureTime // ignore: cast_nullable_to_non_nullable
              as double,
      afInitialOffsetSteps: null == afInitialOffsetSteps
          ? _value.afInitialOffsetSteps
          : afInitialOffsetSteps // ignore: cast_nullable_to_non_nullable
              as int,
      afNumberOfAttempts: null == afNumberOfAttempts
          ? _value.afNumberOfAttempts
          : afNumberOfAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      afUseBrightestNStars: null == afUseBrightestNStars
          ? _value.afUseBrightestNStars
          : afUseBrightestNStars // ignore: cast_nullable_to_non_nullable
              as int,
      afOuterCropRatio: null == afOuterCropRatio
          ? _value.afOuterCropRatio
          : afOuterCropRatio // ignore: cast_nullable_to_non_nullable
              as double,
      afInnerCropRatio: null == afInnerCropRatio
          ? _value.afInnerCropRatio
          : afInnerCropRatio // ignore: cast_nullable_to_non_nullable
              as double,
      afBinning: null == afBinning
          ? _value.afBinning
          : afBinning // ignore: cast_nullable_to_non_nullable
              as int,
      afRSquaredThreshold: null == afRSquaredThreshold
          ? _value.afRSquaredThreshold
          : afRSquaredThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      afFocuserSettleTimeMs: null == afFocuserSettleTimeMs
          ? _value.afFocuserSettleTimeMs
          : afFocuserSettleTimeMs // ignore: cast_nullable_to_non_nullable
              as int,
      afExposuresPerPoint: null == afExposuresPerPoint
          ? _value.afExposuresPerPoint
          : afExposuresPerPoint // ignore: cast_nullable_to_non_nullable
              as int,
      afBacklashCompMethod: null == afBacklashCompMethod
          ? _value.afBacklashCompMethod
          : afBacklashCompMethod // ignore: cast_nullable_to_non_nullable
              as String,
      afBacklashIn: null == afBacklashIn
          ? _value.afBacklashIn
          : afBacklashIn // ignore: cast_nullable_to_non_nullable
              as int,
      afBacklashOut: null == afBacklashOut
          ? _value.afBacklashOut
          : afBacklashOut // ignore: cast_nullable_to_non_nullable
              as int,
      afAutofocusFilterName: null == afAutofocusFilterName
          ? _value.afAutofocusFilterName
          : afAutofocusFilterName // ignore: cast_nullable_to_non_nullable
              as String,
      afFilterSettingsJson: null == afFilterSettingsJson
          ? _value.afFilterSettingsJson
          : afFilterSettingsJson // ignore: cast_nullable_to_non_nullable
              as String,
      useFilterFocusOffsets: null == useFilterFocusOffsets
          ? _value.useFilterFocusOffsets
          : useFilterFocusOffsets // ignore: cast_nullable_to_non_nullable
              as bool,
      astrometryPath: null == astrometryPath
          ? _value.astrometryPath
          : astrometryPath // ignore: cast_nullable_to_non_nullable
              as String,
      observerName: null == observerName
          ? _value.observerName
          : observerName // ignore: cast_nullable_to_non_nullable
              as String,
      imageFormat: null == imageFormat
          ? _value.imageFormat
          : imageFormat // ignore: cast_nullable_to_non_nullable
              as String,
      bitDepth: null == bitDepth
          ? _value.bitDepth
          : bitDepth // ignore: cast_nullable_to_non_nullable
              as String,
      timezone: null == timezone
          ? _value.timezone
          : timezone // ignore: cast_nullable_to_non_nullable
              as String,
      useSystemTime: null == useSystemTime
          ? _value.useSystemTime
          : useSystemTime // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AppSettingsImpl implements _AppSettings {
  const _$AppSettingsImpl(
      {this.location,
      this.theme = 'dark',
      this.language = 'en',
      this.autoConnect = true,
      this.latitude = 0.0,
      this.longitude = 0.0,
      this.elevation = 0.0,
      this.fileNamingPattern = '',
      this.meridianFlipMinutes = 5,
      this.autoFocusEveryMinutes = 60,
      this.ditherEveryFrames = 3,
      this.plateSolveTimeout = 60,
      this.plateSolveSearchRadius = 30.0,
      this.discordWebhook = '',
      this.pushoverKey = '',
      this.pushoverUser = '',
      this.astapPath = '',
      this.autoDiscoverOnLaunch = true,
      this.accentColor = '',
      this.fontSize = 'Medium',
      this.uiScale = 'Auto',
      this.indiServerHost = 'localhost',
      this.indiServerPort = 7624,
      this.indiAutoConnect = false,
      this.alpacaServerHost = 'localhost',
      this.alpacaServerPort = 11111,
      this.alpacaAutoDiscover = false,
      this.useNativeExecution = true,
      this.useSimulationMode = false,
      this.imageOutputPath = '',
      this.observer = '',
      this.telescope = '',
      this.instrument = '',
      this.updateCheckEnabled = true,
      this.updateServerUrl = '',
      this.updateChannel = 'stable',
      this.updateCheckIntervalHours = 24,
      this.skippedUpdateVersion = '',
      this.safetyFailMode = SafetyFailMode.failClosed,
      this.enableImageGrading = false,
      this.imageGradingHfrThresholdPx,
      this.imageGradingHfrBaselinePercent,
      this.imageGradingEccentricityThreshold,
      this.imageGradingStarCountMin,
      this.imageGradingMaxConsecutiveRejects = 3,
      this.imageGradingRejectFolderPath,
      this.adaptiveExposureEnabled = false,
      this.adaptiveExposureTargetSnr = 30.0,
      this.adaptiveExposureReferenceMag = 21.5,
      this.adaptiveExposureMinSecs = 5.0,
      this.adaptiveExposureMaxSecs = 600.0,
      final Map<String, bool> adaptiveExposurePerFilterEnabled =
          const <String, bool>{},
      final Map<String, double> adaptiveExposurePerFilterMinSecs =
          const <String, double>{},
      final Map<String, double> adaptiveExposurePerFilterMaxSecs =
          const <String, double>{},
      this.parkOnUnsafeWeather = true,
      this.autoFocusOnFilterChange = true,
      this.afDisableGuidingDuringAf = false,
      this.ditherEnabled = true,
      this.ditherScale = 'Medium',
      this.recoveryDefaultRetryIntervalMins = 10.0,
      this.recoveryDefaultMaxDurationMins = 90.0,
      this.recoveryStopTrackingDuringRecovery = true,
      this.recoveryAbortOnMeridian = true,
      this.recoveryAudibleAlertWhenEntered = true,
      this.parkBeforeDawn = true,
      this.enableMeridianFlip = true,
      this.tempCompensation = true,
      this.tempCoefficient = -12.0,
      this.backlashCompensation = 0,
      this.settleThreshold = 0.5,
      this.settleTimeout = 30,
      this.plateSolver = 'ASTAP',
      this.blindSolve = false,
      this.bortleClass = 5,
      this.effectiveHorizonDeg = 0.0,
      this.preflightStrictness = 'normal',
      this.polarAlignmentMaxAgeDays = 7,
      this.opticalTrainDriftThreshold = 8.0,
      this.darkLibraryMinCoverage = 10,
      this.smartNightMaxSessionHours,
      this.smartNightDefaultAfCadenceFrames = 25,
      this.smartNightDefaultIntegrationBudgetMinsPerTarget = 240,
      this.smartNightIncludeFlatsAtEnd = true,
      this.smartNightUseSchedulerForMultiTarget = true,
      this.smartNightSchedulerTargetThreshold = 3,
      this.smartNightDefaultStrategy = 'auto_lrgb',
      this.smartNightPolarAlignmentStaleAfterDays = 7,
      this.smartNightSubExposureFloorSecs = 30.0,
      this.smartNightSubExposureCeilingSecs = 300.0,
      this.smartNightTargetSnr = 30.0,
      this.coolingBehavior = 'On Connect',
      this.defaultGain = 100,
      this.defaultOffset = 50,
      this.webServerEnabled = false,
      this.webServerPort = 8080,
      this.phd2Path = '',
      this.phd2Host = 'localhost',
      this.phd2Port = 4400,
      this.notificationsEnabled = true,
      this.notifyOnSequenceComplete = true,
      this.notifyOnError = true,
      this.notifyOnMeridianFlip = false,
      this.soundEnabled = true,
      this.audibleAlertsOnCritical = false,
      this.criticalAlertSound = 'systemBell',
      this.pushCriticalAlerts = true,
      this.smartNightAutoPromptEnabled = true,
      this.promptForNotesAfterRun = true,
      this.sessionHandoffAutoPrompt = true,
      this.campaignRollupSurfaceTargetsTab = true,
      this.campaignRollupGroupingMode = 'by_target_name',
      this.afMethod = 'Star HFR',
      this.afCurveFitting = 'Hyperbolic',
      this.afStepSize = 50,
      this.afExposureTime = 4.0,
      this.afInitialOffsetSteps = 4,
      this.afNumberOfAttempts = 1,
      this.afUseBrightestNStars = 0,
      this.afOuterCropRatio = 1.0,
      this.afInnerCropRatio = 0.0,
      this.afBinning = 1,
      this.afRSquaredThreshold = 0.7,
      this.afFocuserSettleTimeMs = 500,
      this.afExposuresPerPoint = 1,
      this.afBacklashCompMethod = 'Overshoot',
      this.afBacklashIn = 350,
      this.afBacklashOut = 0,
      this.afAutofocusFilterName = '',
      this.afFilterSettingsJson = '{}',
      this.useFilterFocusOffsets = true,
      this.astrometryPath = '',
      this.observerName = '',
      this.imageFormat = 'FITS',
      this.bitDepth = '16-bit',
      this.timezone = 'UTC',
      this.useSystemTime = true})
      : _adaptiveExposurePerFilterEnabled = adaptiveExposurePerFilterEnabled,
        _adaptiveExposurePerFilterMinSecs = adaptiveExposurePerFilterMinSecs,
        _adaptiveExposurePerFilterMaxSecs = adaptiveExposurePerFilterMaxSecs;

  factory _$AppSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppSettingsImplFromJson(json);

  @override
  final ObserverLocation? location;
  @override
  @JsonKey()
  final String theme;
  @override
  @JsonKey()
  final String language;
  @override
  @JsonKey()
  final bool autoConnect;
// Additional fields for compatibility with provider AppSettings
  @override
  @JsonKey()
  final double latitude;
  @override
  @JsonKey()
  final double longitude;
  @override
  @JsonKey()
  final double elevation;
  @override
  @JsonKey()
  final String fileNamingPattern;
  @override
  @JsonKey()
  final int meridianFlipMinutes;
  @override
  @JsonKey()
  final int autoFocusEveryMinutes;
  @override
  @JsonKey()
  final int ditherEveryFrames;
  @override
  @JsonKey()
  final int plateSolveTimeout;
  @override
  @JsonKey()
  final double plateSolveSearchRadius;
  @override
  @JsonKey()
  final String discordWebhook;
  @override
  @JsonKey()
  final String pushoverKey;
  @override
  @JsonKey()
  final String pushoverUser;
  @override
  @JsonKey()
  final String astapPath;
// Discovery settings
  @override
  @JsonKey()
  final bool autoDiscoverOnLaunch;
  @override
  @JsonKey()
  final String accentColor;
  @override
  @JsonKey()
  final String fontSize;
  @override
  @JsonKey()
  final String uiScale;
// Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)
// Protocol settings
  @override
  @JsonKey()
  final String indiServerHost;
  @override
  @JsonKey()
  final int indiServerPort;
  @override
  @JsonKey()
  final bool indiAutoConnect;
  @override
  @JsonKey()
  final String alpacaServerHost;
  @override
  @JsonKey()
  final int alpacaServerPort;
  @override
  @JsonKey()
  final bool alpacaAutoDiscover;
// Sequencer execution settings
  @override
  @JsonKey()
  final bool useNativeExecution;
  @override
  @JsonKey()
  final bool useSimulationMode;
// Image capture settings
  @override
  @JsonKey()
  final String imageOutputPath;
  @override
  @JsonKey()
  final String observer;
  @override
  @JsonKey()
  final String telescope;
  @override
  @JsonKey()
  final String instrument;
// Update settings
  @override
  @JsonKey()
  final bool updateCheckEnabled;
  @override
  @JsonKey()
  final String updateServerUrl;
  @override
  @JsonKey()
  final String updateChannel;
  @override
  @JsonKey()
  final int updateCheckIntervalHours;
  @override
  @JsonKey()
  final String skippedUpdateVersion;
// Safety settings
  @override
  @JsonKey()
  final SafetyFailMode safetyFailMode;
// -------------------------------------------------------------------
// Wave 3 Image Grading: live frame Pass/Reject thresholds. Opt-in:
// disabled by default so existing users keep current behaviour
// (every captured frame saved, none auto-rejected).
// -------------------------------------------------------------------
  /// Master switch: when false, no grading runs at all.
  @override
  @JsonKey()
  final bool enableImageGrading;

  /// Reject if HFR exceeds this absolute pixel value. `null` => don't
  /// apply the absolute check.
  @override
  final double? imageGradingHfrThresholdPx;

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. `null` =>
  /// don't apply the baseline-relative check.
  @override
  final double? imageGradingHfrBaselinePercent;

  /// Reject if star eccentricity exceeds this value. `null` => don't apply.
  @override
  final double? imageGradingEccentricityThreshold;

  /// Reject if detected star count falls below this. `null` => don't apply.
  @override
  final int? imageGradingStarCountMin;

  /// Pause sequence after this many consecutive rejects (default 3).
  @override
  @JsonKey()
  final int imageGradingMaxConsecutiveRejects;

  /// Override for the reject folder. `null` => use `<save_path>/Reject/`.
  /// Relative paths resolve against the run save_path; absolute paths
  /// are used verbatim.
  @override
  final String? imageGradingRejectFolderPath;
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
  @override
  @JsonKey()
  final bool adaptiveExposureEnabled;

  /// Target SNR for the SNR-based scaling (informational; the live
  /// math uses background flux ratio).
  @override
  @JsonKey()
  final double adaptiveExposureTargetSnr;

  /// Reference sky brightness in mag/arcsec² the nominal exposure
  /// duration was calibrated for. Dark-site default is 21.5.
  @override
  @JsonKey()
  final double adaptiveExposureReferenceMag;

  /// Global minimum exposure clamp in seconds.
  @override
  @JsonKey()
  final double adaptiveExposureMinSecs;

  /// Global maximum exposure clamp in seconds.
  @override
  @JsonKey()
  final double adaptiveExposureMaxSecs;

  /// Per-filter enable map (filter name -> bool). Empty => apply
  /// globally (matches the Rust `is_enabled_for_filter` semantics).
  final Map<String, bool> _adaptiveExposurePerFilterEnabled;

  /// Per-filter enable map (filter name -> bool). Empty => apply
  /// globally (matches the Rust `is_enabled_for_filter` semantics).
  @override
  @JsonKey()
  Map<String, bool> get adaptiveExposurePerFilterEnabled {
    if (_adaptiveExposurePerFilterEnabled is EqualUnmodifiableMapView)
      return _adaptiveExposurePerFilterEnabled;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_adaptiveExposurePerFilterEnabled);
  }

  /// Per-filter minimum exposure overrides (seconds).
  final Map<String, double> _adaptiveExposurePerFilterMinSecs;

  /// Per-filter minimum exposure overrides (seconds).
  @override
  @JsonKey()
  Map<String, double> get adaptiveExposurePerFilterMinSecs {
    if (_adaptiveExposurePerFilterMinSecs is EqualUnmodifiableMapView)
      return _adaptiveExposurePerFilterMinSecs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_adaptiveExposurePerFilterMinSecs);
  }

  /// Per-filter maximum exposure overrides (seconds).
  final Map<String, double> _adaptiveExposurePerFilterMaxSecs;

  /// Per-filter maximum exposure overrides (seconds).
  @override
  @JsonKey()
  Map<String, double> get adaptiveExposurePerFilterMaxSecs {
    if (_adaptiveExposurePerFilterMaxSecs is EqualUnmodifiableMapView)
      return _adaptiveExposurePerFilterMaxSecs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_adaptiveExposurePerFilterMaxSecs);
  }

// -------------------------------------------------------------------
// Full-night audit 2026-06-04 follow-up — high-value unattended-night
// knobs that previously had NO wire field, so a phone/remote save of
// them was rejected by the `_assertKeysRemotable` fail-loud guard. These
// round-trip the autofocus / dither / weather-safety / recovery settings
// that an operator must be able to tune for an unattended night.
// -------------------------------------------------------------------
  /// Weather-safety: when true, the rig parks (not just pauses) when weather
  /// turns unsafe. Mirrors `app_settings` DB key `park_on_unsafe_weather`.
  @override
  @JsonKey()
  final bool parkOnUnsafeWeather;

  /// Autofocus: run an autofocus pass on every filter change.
  /// DB key `auto_focus_on_filter_change`.
  @override
  @JsonKey()
  final bool autoFocusOnFilterChange;

  /// Autofocus: disable the guider while an autofocus sweep runs (avoids the
  /// guide star wandering out of frame during the focuser sweep).
  /// DB key `af_disable_guiding`.
  @override
  @JsonKey()
  final bool afDisableGuidingDuringAf;

  /// Dither: master enable for between-frame dithering.
  /// DB key `dither_enabled`.
  @override
  @JsonKey()
  final bool ditherEnabled;

  /// Dither: dither step size — 'Small', 'Medium', or 'Large'.
  /// DB key `dither_scale`.
  @override
  @JsonKey()
  final String ditherScale;

  /// Recovery: minutes between auto-retry attempts during a recovery loop.
  /// DB key `recovery_default_retry_interval_mins`.
  @override
  @JsonKey()
  final double recoveryDefaultRetryIntervalMins;

  /// Recovery: total minutes before the recovery loop gives up.
  /// DB key `recovery_default_max_duration_mins`.
  @override
  @JsonKey()
  final double recoveryDefaultMaxDurationMins;

  /// Recovery: stop tracking while recovering (dew/cloud wait).
  /// DB key `recovery_stop_tracking_during_recovery`.
  @override
  @JsonKey()
  final bool recoveryStopTrackingDuringRecovery;

  /// Recovery: abort the recovery loop if a meridian crossing falls inside
  /// the recovery window. DB key `recovery_abort_on_meridian`.
  @override
  @JsonKey()
  final bool recoveryAbortOnMeridian;

  /// Recovery: ring the platform alert sound on recovery entry.
  /// DB key `recovery_audible_alert_when_entered`.
  @override
  @JsonKey()
  final bool recoveryAudibleAlertWhenEntered;
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
  @override
  @JsonKey()
  final bool parkBeforeDawn;
// Meridian flip detail.
  /// Master enable for automatic meridian flips. DB key `enable_meridian_flip`.
  @override
  @JsonKey()
  final bool enableMeridianFlip;
// Focuser temperature compensation + backlash (calibration).
  /// Enable focuser temperature compensation. DB key `temp_compensation`.
  @override
  @JsonKey()
  final bool tempCompensation;

  /// Temp-comp coefficient (steps per °C). DB key `temp_coefficient`.
  @override
  @JsonKey()
  final double tempCoefficient;

  /// Focuser backlash compensation (steps). DB key `backlash_compensation`.
  @override
  @JsonKey()
  final int backlashCompensation;
// Guider settle (calibration).
  /// Guider settle pixel threshold. DB key `settle_threshold`.
  @override
  @JsonKey()
  final double settleThreshold;

  /// Guider settle timeout in seconds. DB key `settle_timeout`.
  @override
  @JsonKey()
  final int settleTimeout;
// Plate-solving extra.
  /// Selected plate solver ('ASTAP', 'Astrometry.net', 'PlateSolve2').
  /// DB key `plate_solver`.
  @override
  @JsonKey()
  final String plateSolver;

  /// Allow a blind (no-hint) solve fallback. DB key `blind_solve`.
  @override
  @JsonKey()
  final bool blindSolve;
// Site / horizon.
  /// Bortle dark-sky class (1-9). DB key `bortle_class`.
  @override
  @JsonKey()
  final int bortleClass;

  /// Effective horizon altitude floor in degrees. DB key `effective_horizon_deg`.
  @override
  @JsonKey()
  final double effectiveHorizonDeg;
// Pre-flight checklist strictness + freshness gates.
  /// Pre-flight strictness as the enum name ('lax' / 'normal' / 'strict').
  /// Carried as a String to avoid the wire model depending on the provider
  /// library that owns the `PreflightStrictness` enum. DB key
  /// `preflight_strictness`.
  @override
  @JsonKey()
  final String preflightStrictness;

  /// Polar-alignment max age (days) before pre-flight flags it.
  /// DB key `polar_alignment_max_age_days`.
  @override
  @JsonKey()
  final int polarAlignmentMaxAgeDays;

  /// Optical-train drift threshold (arcmin) before pre-flight flags it.
  /// DB key `optical_train_drift_threshold`.
  @override
  @JsonKey()
  final double opticalTrainDriftThreshold;
// Dark library.
  /// Minimum matching dark frames before the dark library is "covered".
  /// DB key `dark_library_min_coverage`.
  @override
  @JsonKey()
  final int darkLibraryMinCoverage;
// -------------------------------------------------------------------
// Smart Night defaults — the one-click "plan tonight" builder reads these
// when assembling a sequence, so an unattended night planned from a phone
// must carry them.
// -------------------------------------------------------------------
  /// Cap a planned session to this many hours. `null` => use the full dark
  /// window. DB key `smart_night_max_session_hours`.
  @override
  final double? smartNightMaxSessionHours;

  /// Default autofocus cadence (frames) for built sequences.
  /// DB key `smart_night_default_af_cadence_frames`.
  @override
  @JsonKey()
  final int smartNightDefaultAfCadenceFrames;

  /// Default per-target integration budget (minutes).
  /// DB key `smart_night_default_integration_budget_mins_per_target`.
  @override
  @JsonKey()
  final int smartNightDefaultIntegrationBudgetMinsPerTarget;

  /// Append flats at the end of the planned night.
  /// DB key `smart_night_include_flats_at_end`.
  @override
  @JsonKey()
  final bool smartNightIncludeFlatsAtEnd;

  /// Use the scheduler (vs a single linear sequence) for multi-target nights.
  /// DB key `smart_night_use_scheduler_for_multi_target`.
  @override
  @JsonKey()
  final bool smartNightUseSchedulerForMultiTarget;

  /// Target count at/above which the scheduler is used.
  /// DB key `smart_night_scheduler_target_threshold`.
  @override
  @JsonKey()
  final int smartNightSchedulerTargetThreshold;

  /// Default capture strategy id (e.g. 'auto_lrgb').
  /// DB key `smart_night_default_strategy`.
  @override
  @JsonKey()
  final String smartNightDefaultStrategy;

  /// Days after which polar alignment is considered stale for the wizard.
  /// DB key `smart_night_polar_alignment_stale_after_days`.
  @override
  @JsonKey()
  final int smartNightPolarAlignmentStaleAfterDays;

  /// Sub-exposure floor (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_floor_secs`.
  @override
  @JsonKey()
  final double smartNightSubExposureFloorSecs;

  /// Sub-exposure ceiling (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_ceiling_secs`.
  @override
  @JsonKey()
  final double smartNightSubExposureCeilingSecs;

  /// Target SNR the planner sizes sub-exposures toward.
  /// DB key `smart_night_target_snr`.
  @override
  @JsonKey()
  final double smartNightTargetSnr;
// -------------------------------------------------------------------
// Full remote-settings parity 2026-06-05 — the remaining setter-reachable
// knobs that `_applySettingsMap` already maps into AppSettingsState but
// which had NO wire field, so a phone/remote save of them was rejected by
// the `_assertKeysRemotable` fail-loud guard. Carrying them here completes
// the unattended-night knob set so a phone can edit the whole config.
// The defaults mirror AppSettingsState's constructor defaults so the wire
// model never injects a different value than local state.
// -------------------------------------------------------------------
// Equipment defaults (camera).
  /// Cooling behaviour: 'On Connect' / 'Manual' / 'Never'. DB `cooling_behavior`.
  @override
  @JsonKey()
  final String coolingBehavior;

  /// Default camera gain. DB `default_gain`.
  @override
  @JsonKey()
  final int defaultGain;

  /// Default camera offset. DB `default_offset`.
  @override
  @JsonKey()
  final int defaultOffset;
// Remote access / web server.
  /// Headless web server enabled. DB `web_server_enabled`.
  @override
  @JsonKey()
  final bool webServerEnabled;

  /// Headless web server port. DB `web_server_port`.
  @override
  @JsonKey()
  final int webServerPort;
// PHD2 connection.
  /// PHD2 executable path. DB `phd2_path`.
  @override
  @JsonKey()
  final String phd2Path;

  /// PHD2 host. DB `phd2_host`.
  @override
  @JsonKey()
  final String phd2Host;

  /// PHD2 port. DB `phd2_port`.
  @override
  @JsonKey()
  final int phd2Port;
// Notification toggles.
  /// Master notifications switch. DB `notifications_enabled`.
  @override
  @JsonKey()
  final bool notificationsEnabled;

  /// Notify when a sequence completes. DB `notify_on_sequence_complete`.
  @override
  @JsonKey()
  final bool notifyOnSequenceComplete;

  /// Notify on error. DB `notify_on_error`.
  @override
  @JsonKey()
  final bool notifyOnError;

  /// Notify on meridian flip. DB `notify_on_meridian_flip`.
  @override
  @JsonKey()
  final bool notifyOnMeridianFlip;

  /// In-app notification sound. DB `sound_enabled`.
  @override
  @JsonKey()
  final bool soundEnabled;

  /// Ring the platform alert on critical-severity events. DB
  /// `audible_alerts_on_critical`.
  @override
  @JsonKey()
  final bool audibleAlertsOnCritical;

  /// Which sound for critical alerts ('systemBell' / 'none'). DB
  /// `critical_alert_sound`.
  @override
  @JsonKey()
  final String criticalAlertSound;

  /// Forward critical alerts to paired phones as push. DB `push_critical_alerts`.
  @override
  @JsonKey()
  final bool pushCriticalAlerts;
// Session-lifecycle + campaign-rollup prefs.
  /// Show the Smart-Night auto-prompt when equipment is ready. DB
  /// `smart_night.auto_prompt_enabled`.
  @override
  @JsonKey()
  final bool smartNightAutoPromptEnabled;

  /// Prompt for notes after a run. DB `notes.prompt_after_run`.
  @override
  @JsonKey()
  final bool promptForNotesAfterRun;

  /// Auto-open the multi-night carry-over banner. DB
  /// `session.handoff_auto_prompt`.
  @override
  @JsonKey()
  final bool sessionHandoffAutoPrompt;

  /// Surface the campaign-rollup column on the Targets tab. DB
  /// `campaign_rollup.surface_targets_tab`.
  @override
  @JsonKey()
  final bool campaignRollupSurfaceTargetsTab;

  /// Campaign-rollup grouping mode. DB `campaign_rollup.grouping_mode`.
  @override
  @JsonKey()
  final String campaignRollupGroupingMode;
// Autofocus detailed sweep params.
  /// AF method. DB `af_method`.
  @override
  @JsonKey()
  final String afMethod;

  /// AF curve fitting. DB `af_curve_fitting`.
  @override
  @JsonKey()
  final String afCurveFitting;

  /// AF step size between measurement points. DB `af_step_size`.
  @override
  @JsonKey()
  final int afStepSize;

  /// AF exposure time (seconds). DB `af_exposure_time`.
  @override
  @JsonKey()
  final double afExposureTime;

  /// AF initial offset steps out from center. DB `af_initial_offset_steps`.
  @override
  @JsonKey()
  final int afInitialOffsetSteps;

  /// AF retry count on failure. DB `af_number_of_attempts`.
  @override
  @JsonKey()
  final int afNumberOfAttempts;

  /// AF brightest-N stars (0 = all). DB `af_use_brightest_n_stars`.
  @override
  @JsonKey()
  final int afUseBrightestNStars;

  /// AF outer crop ratio. DB `af_outer_crop_ratio`.
  @override
  @JsonKey()
  final double afOuterCropRatio;

  /// AF inner crop ratio. DB `af_inner_crop_ratio`.
  @override
  @JsonKey()
  final double afInnerCropRatio;

  /// AF binning. DB `af_binning`.
  @override
  @JsonKey()
  final int afBinning;

  /// AF R² fit-quality threshold. DB `af_r_squared_threshold`.
  @override
  @JsonKey()
  final double afRSquaredThreshold;

  /// AF focuser settle time (ms). DB `af_focuser_settle_time_ms`.
  @override
  @JsonKey()
  final int afFocuserSettleTimeMs;

  /// AF exposures per measurement point. DB `af_exposures_per_point`.
  @override
  @JsonKey()
  final int afExposuresPerPoint;

  /// AF backlash compensation method. DB `af_backlash_comp_method`.
  @override
  @JsonKey()
  final String afBacklashCompMethod;

  /// AF backlash-in steps. DB `af_backlash_in`.
  @override
  @JsonKey()
  final int afBacklashIn;

  /// AF backlash-out steps. DB `af_backlash_out`.
  @override
  @JsonKey()
  final int afBacklashOut;

  /// Designated AF filter (empty = current). DB `af_autofocus_filter_name`.
  @override
  @JsonKey()
  final String afAutofocusFilterName;

  /// Per-filter AF config JSON map. DB `af_filter_settings`.
  @override
  @JsonKey()
  final String afFilterSettingsJson;

  /// Apply focus offsets on filter change. DB `use_filter_focus_offsets`.
  @override
  @JsonKey()
  final bool useFilterFocusOffsets;
// Misc imaging / FITS / plate-solve config relevant to an unattended night.
  /// Astrometry.net solver path. DB `astrometry_path`.
  @override
  @JsonKey()
  final String astrometryPath;

  /// FITS OBSERVER keyword. DB `observer_name`.
  @override
  @JsonKey()
  final String observerName;

  /// Image format ('FITS' / 'XISF' / 'TIFF'). DB `image_format`.
  @override
  @JsonKey()
  final String imageFormat;

  /// Bit depth ('16-bit' / '32-bit'). DB `bit_depth`.
  @override
  @JsonKey()
  final String bitDepth;

  /// Observing timezone. DB `timezone`.
  @override
  @JsonKey()
  final String timezone;

  /// Use system time vs a fixed observing time. DB `use_system_time`.
  @override
  @JsonKey()
  final bool useSystemTime;

  @override
  String toString() {
    return 'AppSettings(location: $location, theme: $theme, language: $language, autoConnect: $autoConnect, latitude: $latitude, longitude: $longitude, elevation: $elevation, fileNamingPattern: $fileNamingPattern, meridianFlipMinutes: $meridianFlipMinutes, autoFocusEveryMinutes: $autoFocusEveryMinutes, ditherEveryFrames: $ditherEveryFrames, plateSolveTimeout: $plateSolveTimeout, plateSolveSearchRadius: $plateSolveSearchRadius, discordWebhook: $discordWebhook, pushoverKey: $pushoverKey, pushoverUser: $pushoverUser, astapPath: $astapPath, autoDiscoverOnLaunch: $autoDiscoverOnLaunch, accentColor: $accentColor, fontSize: $fontSize, uiScale: $uiScale, indiServerHost: $indiServerHost, indiServerPort: $indiServerPort, indiAutoConnect: $indiAutoConnect, alpacaServerHost: $alpacaServerHost, alpacaServerPort: $alpacaServerPort, alpacaAutoDiscover: $alpacaAutoDiscover, useNativeExecution: $useNativeExecution, useSimulationMode: $useSimulationMode, imageOutputPath: $imageOutputPath, observer: $observer, telescope: $telescope, instrument: $instrument, updateCheckEnabled: $updateCheckEnabled, updateServerUrl: $updateServerUrl, updateChannel: $updateChannel, updateCheckIntervalHours: $updateCheckIntervalHours, skippedUpdateVersion: $skippedUpdateVersion, safetyFailMode: $safetyFailMode, enableImageGrading: $enableImageGrading, imageGradingHfrThresholdPx: $imageGradingHfrThresholdPx, imageGradingHfrBaselinePercent: $imageGradingHfrBaselinePercent, imageGradingEccentricityThreshold: $imageGradingEccentricityThreshold, imageGradingStarCountMin: $imageGradingStarCountMin, imageGradingMaxConsecutiveRejects: $imageGradingMaxConsecutiveRejects, imageGradingRejectFolderPath: $imageGradingRejectFolderPath, adaptiveExposureEnabled: $adaptiveExposureEnabled, adaptiveExposureTargetSnr: $adaptiveExposureTargetSnr, adaptiveExposureReferenceMag: $adaptiveExposureReferenceMag, adaptiveExposureMinSecs: $adaptiveExposureMinSecs, adaptiveExposureMaxSecs: $adaptiveExposureMaxSecs, adaptiveExposurePerFilterEnabled: $adaptiveExposurePerFilterEnabled, adaptiveExposurePerFilterMinSecs: $adaptiveExposurePerFilterMinSecs, adaptiveExposurePerFilterMaxSecs: $adaptiveExposurePerFilterMaxSecs, parkOnUnsafeWeather: $parkOnUnsafeWeather, autoFocusOnFilterChange: $autoFocusOnFilterChange, afDisableGuidingDuringAf: $afDisableGuidingDuringAf, ditherEnabled: $ditherEnabled, ditherScale: $ditherScale, recoveryDefaultRetryIntervalMins: $recoveryDefaultRetryIntervalMins, recoveryDefaultMaxDurationMins: $recoveryDefaultMaxDurationMins, recoveryStopTrackingDuringRecovery: $recoveryStopTrackingDuringRecovery, recoveryAbortOnMeridian: $recoveryAbortOnMeridian, recoveryAudibleAlertWhenEntered: $recoveryAudibleAlertWhenEntered, parkBeforeDawn: $parkBeforeDawn, enableMeridianFlip: $enableMeridianFlip, tempCompensation: $tempCompensation, tempCoefficient: $tempCoefficient, backlashCompensation: $backlashCompensation, settleThreshold: $settleThreshold, settleTimeout: $settleTimeout, plateSolver: $plateSolver, blindSolve: $blindSolve, bortleClass: $bortleClass, effectiveHorizonDeg: $effectiveHorizonDeg, preflightStrictness: $preflightStrictness, polarAlignmentMaxAgeDays: $polarAlignmentMaxAgeDays, opticalTrainDriftThreshold: $opticalTrainDriftThreshold, darkLibraryMinCoverage: $darkLibraryMinCoverage, smartNightMaxSessionHours: $smartNightMaxSessionHours, smartNightDefaultAfCadenceFrames: $smartNightDefaultAfCadenceFrames, smartNightDefaultIntegrationBudgetMinsPerTarget: $smartNightDefaultIntegrationBudgetMinsPerTarget, smartNightIncludeFlatsAtEnd: $smartNightIncludeFlatsAtEnd, smartNightUseSchedulerForMultiTarget: $smartNightUseSchedulerForMultiTarget, smartNightSchedulerTargetThreshold: $smartNightSchedulerTargetThreshold, smartNightDefaultStrategy: $smartNightDefaultStrategy, smartNightPolarAlignmentStaleAfterDays: $smartNightPolarAlignmentStaleAfterDays, smartNightSubExposureFloorSecs: $smartNightSubExposureFloorSecs, smartNightSubExposureCeilingSecs: $smartNightSubExposureCeilingSecs, smartNightTargetSnr: $smartNightTargetSnr, coolingBehavior: $coolingBehavior, defaultGain: $defaultGain, defaultOffset: $defaultOffset, webServerEnabled: $webServerEnabled, webServerPort: $webServerPort, phd2Path: $phd2Path, phd2Host: $phd2Host, phd2Port: $phd2Port, notificationsEnabled: $notificationsEnabled, notifyOnSequenceComplete: $notifyOnSequenceComplete, notifyOnError: $notifyOnError, notifyOnMeridianFlip: $notifyOnMeridianFlip, soundEnabled: $soundEnabled, audibleAlertsOnCritical: $audibleAlertsOnCritical, criticalAlertSound: $criticalAlertSound, pushCriticalAlerts: $pushCriticalAlerts, smartNightAutoPromptEnabled: $smartNightAutoPromptEnabled, promptForNotesAfterRun: $promptForNotesAfterRun, sessionHandoffAutoPrompt: $sessionHandoffAutoPrompt, campaignRollupSurfaceTargetsTab: $campaignRollupSurfaceTargetsTab, campaignRollupGroupingMode: $campaignRollupGroupingMode, afMethod: $afMethod, afCurveFitting: $afCurveFitting, afStepSize: $afStepSize, afExposureTime: $afExposureTime, afInitialOffsetSteps: $afInitialOffsetSteps, afNumberOfAttempts: $afNumberOfAttempts, afUseBrightestNStars: $afUseBrightestNStars, afOuterCropRatio: $afOuterCropRatio, afInnerCropRatio: $afInnerCropRatio, afBinning: $afBinning, afRSquaredThreshold: $afRSquaredThreshold, afFocuserSettleTimeMs: $afFocuserSettleTimeMs, afExposuresPerPoint: $afExposuresPerPoint, afBacklashCompMethod: $afBacklashCompMethod, afBacklashIn: $afBacklashIn, afBacklashOut: $afBacklashOut, afAutofocusFilterName: $afAutofocusFilterName, afFilterSettingsJson: $afFilterSettingsJson, useFilterFocusOffsets: $useFilterFocusOffsets, astrometryPath: $astrometryPath, observerName: $observerName, imageFormat: $imageFormat, bitDepth: $bitDepth, timezone: $timezone, useSystemTime: $useSystemTime)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppSettingsImpl &&
            (identical(other.location, location) ||
                other.location == location) &&
            (identical(other.theme, theme) || other.theme == theme) &&
            (identical(other.language, language) ||
                other.language == language) &&
            (identical(other.autoConnect, autoConnect) ||
                other.autoConnect == autoConnect) &&
            (identical(other.latitude, latitude) ||
                other.latitude == latitude) &&
            (identical(other.longitude, longitude) ||
                other.longitude == longitude) &&
            (identical(other.elevation, elevation) ||
                other.elevation == elevation) &&
            (identical(other.fileNamingPattern, fileNamingPattern) ||
                other.fileNamingPattern == fileNamingPattern) &&
            (identical(other.meridianFlipMinutes, meridianFlipMinutes) ||
                other.meridianFlipMinutes == meridianFlipMinutes) &&
            (identical(other.autoFocusEveryMinutes, autoFocusEveryMinutes) ||
                other.autoFocusEveryMinutes == autoFocusEveryMinutes) &&
            (identical(other.ditherEveryFrames, ditherEveryFrames) ||
                other.ditherEveryFrames == ditherEveryFrames) &&
            (identical(other.plateSolveTimeout, plateSolveTimeout) ||
                other.plateSolveTimeout == plateSolveTimeout) &&
            (identical(other.plateSolveSearchRadius, plateSolveSearchRadius) ||
                other.plateSolveSearchRadius == plateSolveSearchRadius) &&
            (identical(other.discordWebhook, discordWebhook) ||
                other.discordWebhook == discordWebhook) &&
            (identical(other.pushoverKey, pushoverKey) ||
                other.pushoverKey == pushoverKey) &&
            (identical(other.pushoverUser, pushoverUser) ||
                other.pushoverUser == pushoverUser) &&
            (identical(other.astapPath, astapPath) ||
                other.astapPath == astapPath) &&
            (identical(other.autoDiscoverOnLaunch, autoDiscoverOnLaunch) ||
                other.autoDiscoverOnLaunch == autoDiscoverOnLaunch) &&
            (identical(other.accentColor, accentColor) ||
                other.accentColor == accentColor) &&
            (identical(other.fontSize, fontSize) ||
                other.fontSize == fontSize) &&
            (identical(other.uiScale, uiScale) || other.uiScale == uiScale) &&
            (identical(other.indiServerHost, indiServerHost) ||
                other.indiServerHost == indiServerHost) &&
            (identical(other.indiServerPort, indiServerPort) ||
                other.indiServerPort == indiServerPort) &&
            (identical(other.indiAutoConnect, indiAutoConnect) ||
                other.indiAutoConnect == indiAutoConnect) &&
            (identical(other.alpacaServerHost, alpacaServerHost) ||
                other.alpacaServerHost == alpacaServerHost) &&
            (identical(other.alpacaServerPort, alpacaServerPort) ||
                other.alpacaServerPort == alpacaServerPort) &&
            (identical(other.alpacaAutoDiscover, alpacaAutoDiscover) ||
                other.alpacaAutoDiscover == alpacaAutoDiscover) &&
            (identical(other.useNativeExecution, useNativeExecution) ||
                other.useNativeExecution == useNativeExecution) &&
            (identical(other.useSimulationMode, useSimulationMode) ||
                other.useSimulationMode == useSimulationMode) &&
            (identical(other.imageOutputPath, imageOutputPath) ||
                other.imageOutputPath == imageOutputPath) &&
            (identical(other.observer, observer) ||
                other.observer == observer) &&
            (identical(other.telescope, telescope) ||
                other.telescope == telescope) &&
            (identical(other.instrument, instrument) ||
                other.instrument == instrument) &&
            (identical(other.updateCheckEnabled, updateCheckEnabled) ||
                other.updateCheckEnabled == updateCheckEnabled) &&
            (identical(other.updateServerUrl, updateServerUrl) ||
                other.updateServerUrl == updateServerUrl) &&
            (identical(other.updateChannel, updateChannel) ||
                other.updateChannel == updateChannel) &&
            (identical(other.updateCheckIntervalHours, updateCheckIntervalHours) ||
                other.updateCheckIntervalHours == updateCheckIntervalHours) &&
            (identical(other.skippedUpdateVersion, skippedUpdateVersion) ||
                other.skippedUpdateVersion == skippedUpdateVersion) &&
            (identical(other.safetyFailMode, safetyFailMode) ||
                other.safetyFailMode == safetyFailMode) &&
            (identical(other.enableImageGrading, enableImageGrading) ||
                other.enableImageGrading == enableImageGrading) &&
            (identical(other.imageGradingHfrThresholdPx, imageGradingHfrThresholdPx) ||
                other.imageGradingHfrThresholdPx ==
                    imageGradingHfrThresholdPx) &&
            (identical(other.imageGradingHfrBaselinePercent, imageGradingHfrBaselinePercent) ||
                other.imageGradingHfrBaselinePercent ==
                    imageGradingHfrBaselinePercent) &&
            (identical(other.imageGradingEccentricityThreshold, imageGradingEccentricityThreshold) ||
                other.imageGradingEccentricityThreshold == imageGradingEccentricityThreshold) &&
            (identical(other.imageGradingStarCountMin, imageGradingStarCountMin) || other.imageGradingStarCountMin == imageGradingStarCountMin) &&
            (identical(other.imageGradingMaxConsecutiveRejects, imageGradingMaxConsecutiveRejects) || other.imageGradingMaxConsecutiveRejects == imageGradingMaxConsecutiveRejects) &&
            (identical(other.imageGradingRejectFolderPath, imageGradingRejectFolderPath) || other.imageGradingRejectFolderPath == imageGradingRejectFolderPath) &&
            (identical(other.adaptiveExposureEnabled, adaptiveExposureEnabled) || other.adaptiveExposureEnabled == adaptiveExposureEnabled) &&
            (identical(other.adaptiveExposureTargetSnr, adaptiveExposureTargetSnr) || other.adaptiveExposureTargetSnr == adaptiveExposureTargetSnr) &&
            (identical(other.adaptiveExposureReferenceMag, adaptiveExposureReferenceMag) || other.adaptiveExposureReferenceMag == adaptiveExposureReferenceMag) &&
            (identical(other.adaptiveExposureMinSecs, adaptiveExposureMinSecs) || other.adaptiveExposureMinSecs == adaptiveExposureMinSecs) &&
            (identical(other.adaptiveExposureMaxSecs, adaptiveExposureMaxSecs) || other.adaptiveExposureMaxSecs == adaptiveExposureMaxSecs) &&
            const DeepCollectionEquality().equals(other._adaptiveExposurePerFilterEnabled, _adaptiveExposurePerFilterEnabled) &&
            const DeepCollectionEquality().equals(other._adaptiveExposurePerFilterMinSecs, _adaptiveExposurePerFilterMinSecs) &&
            const DeepCollectionEquality().equals(other._adaptiveExposurePerFilterMaxSecs, _adaptiveExposurePerFilterMaxSecs) &&
            (identical(other.parkOnUnsafeWeather, parkOnUnsafeWeather) || other.parkOnUnsafeWeather == parkOnUnsafeWeather) &&
            (identical(other.autoFocusOnFilterChange, autoFocusOnFilterChange) || other.autoFocusOnFilterChange == autoFocusOnFilterChange) &&
            (identical(other.afDisableGuidingDuringAf, afDisableGuidingDuringAf) || other.afDisableGuidingDuringAf == afDisableGuidingDuringAf) &&
            (identical(other.ditherEnabled, ditherEnabled) || other.ditherEnabled == ditherEnabled) &&
            (identical(other.ditherScale, ditherScale) || other.ditherScale == ditherScale) &&
            (identical(other.recoveryDefaultRetryIntervalMins, recoveryDefaultRetryIntervalMins) || other.recoveryDefaultRetryIntervalMins == recoveryDefaultRetryIntervalMins) &&
            (identical(other.recoveryDefaultMaxDurationMins, recoveryDefaultMaxDurationMins) || other.recoveryDefaultMaxDurationMins == recoveryDefaultMaxDurationMins) &&
            (identical(other.recoveryStopTrackingDuringRecovery, recoveryStopTrackingDuringRecovery) || other.recoveryStopTrackingDuringRecovery == recoveryStopTrackingDuringRecovery) &&
            (identical(other.recoveryAbortOnMeridian, recoveryAbortOnMeridian) || other.recoveryAbortOnMeridian == recoveryAbortOnMeridian) &&
            (identical(other.recoveryAudibleAlertWhenEntered, recoveryAudibleAlertWhenEntered) || other.recoveryAudibleAlertWhenEntered == recoveryAudibleAlertWhenEntered) &&
            (identical(other.parkBeforeDawn, parkBeforeDawn) || other.parkBeforeDawn == parkBeforeDawn) &&
            (identical(other.enableMeridianFlip, enableMeridianFlip) || other.enableMeridianFlip == enableMeridianFlip) &&
            (identical(other.tempCompensation, tempCompensation) || other.tempCompensation == tempCompensation) &&
            (identical(other.tempCoefficient, tempCoefficient) || other.tempCoefficient == tempCoefficient) &&
            (identical(other.backlashCompensation, backlashCompensation) || other.backlashCompensation == backlashCompensation) &&
            (identical(other.settleThreshold, settleThreshold) || other.settleThreshold == settleThreshold) &&
            (identical(other.settleTimeout, settleTimeout) || other.settleTimeout == settleTimeout) &&
            (identical(other.plateSolver, plateSolver) || other.plateSolver == plateSolver) &&
            (identical(other.blindSolve, blindSolve) || other.blindSolve == blindSolve) &&
            (identical(other.bortleClass, bortleClass) || other.bortleClass == bortleClass) &&
            (identical(other.effectiveHorizonDeg, effectiveHorizonDeg) || other.effectiveHorizonDeg == effectiveHorizonDeg) &&
            (identical(other.preflightStrictness, preflightStrictness) || other.preflightStrictness == preflightStrictness) &&
            (identical(other.polarAlignmentMaxAgeDays, polarAlignmentMaxAgeDays) || other.polarAlignmentMaxAgeDays == polarAlignmentMaxAgeDays) &&
            (identical(other.opticalTrainDriftThreshold, opticalTrainDriftThreshold) || other.opticalTrainDriftThreshold == opticalTrainDriftThreshold) &&
            (identical(other.darkLibraryMinCoverage, darkLibraryMinCoverage) || other.darkLibraryMinCoverage == darkLibraryMinCoverage) &&
            (identical(other.smartNightMaxSessionHours, smartNightMaxSessionHours) || other.smartNightMaxSessionHours == smartNightMaxSessionHours) &&
            (identical(other.smartNightDefaultAfCadenceFrames, smartNightDefaultAfCadenceFrames) || other.smartNightDefaultAfCadenceFrames == smartNightDefaultAfCadenceFrames) &&
            (identical(other.smartNightDefaultIntegrationBudgetMinsPerTarget, smartNightDefaultIntegrationBudgetMinsPerTarget) || other.smartNightDefaultIntegrationBudgetMinsPerTarget == smartNightDefaultIntegrationBudgetMinsPerTarget) &&
            (identical(other.smartNightIncludeFlatsAtEnd, smartNightIncludeFlatsAtEnd) || other.smartNightIncludeFlatsAtEnd == smartNightIncludeFlatsAtEnd) &&
            (identical(other.smartNightUseSchedulerForMultiTarget, smartNightUseSchedulerForMultiTarget) || other.smartNightUseSchedulerForMultiTarget == smartNightUseSchedulerForMultiTarget) &&
            (identical(other.smartNightSchedulerTargetThreshold, smartNightSchedulerTargetThreshold) || other.smartNightSchedulerTargetThreshold == smartNightSchedulerTargetThreshold) &&
            (identical(other.smartNightDefaultStrategy, smartNightDefaultStrategy) || other.smartNightDefaultStrategy == smartNightDefaultStrategy) &&
            (identical(other.smartNightPolarAlignmentStaleAfterDays, smartNightPolarAlignmentStaleAfterDays) || other.smartNightPolarAlignmentStaleAfterDays == smartNightPolarAlignmentStaleAfterDays) &&
            (identical(other.smartNightSubExposureFloorSecs, smartNightSubExposureFloorSecs) || other.smartNightSubExposureFloorSecs == smartNightSubExposureFloorSecs) &&
            (identical(other.smartNightSubExposureCeilingSecs, smartNightSubExposureCeilingSecs) || other.smartNightSubExposureCeilingSecs == smartNightSubExposureCeilingSecs) &&
            (identical(other.smartNightTargetSnr, smartNightTargetSnr) || other.smartNightTargetSnr == smartNightTargetSnr) &&
            (identical(other.coolingBehavior, coolingBehavior) || other.coolingBehavior == coolingBehavior) &&
            (identical(other.defaultGain, defaultGain) || other.defaultGain == defaultGain) &&
            (identical(other.defaultOffset, defaultOffset) || other.defaultOffset == defaultOffset) &&
            (identical(other.webServerEnabled, webServerEnabled) || other.webServerEnabled == webServerEnabled) &&
            (identical(other.webServerPort, webServerPort) || other.webServerPort == webServerPort) &&
            (identical(other.phd2Path, phd2Path) || other.phd2Path == phd2Path) &&
            (identical(other.phd2Host, phd2Host) || other.phd2Host == phd2Host) &&
            (identical(other.phd2Port, phd2Port) || other.phd2Port == phd2Port) &&
            (identical(other.notificationsEnabled, notificationsEnabled) || other.notificationsEnabled == notificationsEnabled) &&
            (identical(other.notifyOnSequenceComplete, notifyOnSequenceComplete) || other.notifyOnSequenceComplete == notifyOnSequenceComplete) &&
            (identical(other.notifyOnError, notifyOnError) || other.notifyOnError == notifyOnError) &&
            (identical(other.notifyOnMeridianFlip, notifyOnMeridianFlip) || other.notifyOnMeridianFlip == notifyOnMeridianFlip) &&
            (identical(other.soundEnabled, soundEnabled) || other.soundEnabled == soundEnabled) &&
            (identical(other.audibleAlertsOnCritical, audibleAlertsOnCritical) || other.audibleAlertsOnCritical == audibleAlertsOnCritical) &&
            (identical(other.criticalAlertSound, criticalAlertSound) || other.criticalAlertSound == criticalAlertSound) &&
            (identical(other.pushCriticalAlerts, pushCriticalAlerts) || other.pushCriticalAlerts == pushCriticalAlerts) &&
            (identical(other.smartNightAutoPromptEnabled, smartNightAutoPromptEnabled) || other.smartNightAutoPromptEnabled == smartNightAutoPromptEnabled) &&
            (identical(other.promptForNotesAfterRun, promptForNotesAfterRun) || other.promptForNotesAfterRun == promptForNotesAfterRun) &&
            (identical(other.sessionHandoffAutoPrompt, sessionHandoffAutoPrompt) || other.sessionHandoffAutoPrompt == sessionHandoffAutoPrompt) &&
            (identical(other.campaignRollupSurfaceTargetsTab, campaignRollupSurfaceTargetsTab) || other.campaignRollupSurfaceTargetsTab == campaignRollupSurfaceTargetsTab) &&
            (identical(other.campaignRollupGroupingMode, campaignRollupGroupingMode) || other.campaignRollupGroupingMode == campaignRollupGroupingMode) &&
            (identical(other.afMethod, afMethod) || other.afMethod == afMethod) &&
            (identical(other.afCurveFitting, afCurveFitting) || other.afCurveFitting == afCurveFitting) &&
            (identical(other.afStepSize, afStepSize) || other.afStepSize == afStepSize) &&
            (identical(other.afExposureTime, afExposureTime) || other.afExposureTime == afExposureTime) &&
            (identical(other.afInitialOffsetSteps, afInitialOffsetSteps) || other.afInitialOffsetSteps == afInitialOffsetSteps) &&
            (identical(other.afNumberOfAttempts, afNumberOfAttempts) || other.afNumberOfAttempts == afNumberOfAttempts) &&
            (identical(other.afUseBrightestNStars, afUseBrightestNStars) || other.afUseBrightestNStars == afUseBrightestNStars) &&
            (identical(other.afOuterCropRatio, afOuterCropRatio) || other.afOuterCropRatio == afOuterCropRatio) &&
            (identical(other.afInnerCropRatio, afInnerCropRatio) || other.afInnerCropRatio == afInnerCropRatio) &&
            (identical(other.afBinning, afBinning) || other.afBinning == afBinning) &&
            (identical(other.afRSquaredThreshold, afRSquaredThreshold) || other.afRSquaredThreshold == afRSquaredThreshold) &&
            (identical(other.afFocuserSettleTimeMs, afFocuserSettleTimeMs) || other.afFocuserSettleTimeMs == afFocuserSettleTimeMs) &&
            (identical(other.afExposuresPerPoint, afExposuresPerPoint) || other.afExposuresPerPoint == afExposuresPerPoint) &&
            (identical(other.afBacklashCompMethod, afBacklashCompMethod) || other.afBacklashCompMethod == afBacklashCompMethod) &&
            (identical(other.afBacklashIn, afBacklashIn) || other.afBacklashIn == afBacklashIn) &&
            (identical(other.afBacklashOut, afBacklashOut) || other.afBacklashOut == afBacklashOut) &&
            (identical(other.afAutofocusFilterName, afAutofocusFilterName) || other.afAutofocusFilterName == afAutofocusFilterName) &&
            (identical(other.afFilterSettingsJson, afFilterSettingsJson) || other.afFilterSettingsJson == afFilterSettingsJson) &&
            (identical(other.useFilterFocusOffsets, useFilterFocusOffsets) || other.useFilterFocusOffsets == useFilterFocusOffsets) &&
            (identical(other.astrometryPath, astrometryPath) || other.astrometryPath == astrometryPath) &&
            (identical(other.observerName, observerName) || other.observerName == observerName) &&
            (identical(other.imageFormat, imageFormat) || other.imageFormat == imageFormat) &&
            (identical(other.bitDepth, bitDepth) || other.bitDepth == bitDepth) &&
            (identical(other.timezone, timezone) || other.timezone == timezone) &&
            (identical(other.useSystemTime, useSystemTime) || other.useSystemTime == useSystemTime));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        location,
        theme,
        language,
        autoConnect,
        latitude,
        longitude,
        elevation,
        fileNamingPattern,
        meridianFlipMinutes,
        autoFocusEveryMinutes,
        ditherEveryFrames,
        plateSolveTimeout,
        plateSolveSearchRadius,
        discordWebhook,
        pushoverKey,
        pushoverUser,
        astapPath,
        autoDiscoverOnLaunch,
        accentColor,
        fontSize,
        uiScale,
        indiServerHost,
        indiServerPort,
        indiAutoConnect,
        alpacaServerHost,
        alpacaServerPort,
        alpacaAutoDiscover,
        useNativeExecution,
        useSimulationMode,
        imageOutputPath,
        observer,
        telescope,
        instrument,
        updateCheckEnabled,
        updateServerUrl,
        updateChannel,
        updateCheckIntervalHours,
        skippedUpdateVersion,
        safetyFailMode,
        enableImageGrading,
        imageGradingHfrThresholdPx,
        imageGradingHfrBaselinePercent,
        imageGradingEccentricityThreshold,
        imageGradingStarCountMin,
        imageGradingMaxConsecutiveRejects,
        imageGradingRejectFolderPath,
        adaptiveExposureEnabled,
        adaptiveExposureTargetSnr,
        adaptiveExposureReferenceMag,
        adaptiveExposureMinSecs,
        adaptiveExposureMaxSecs,
        const DeepCollectionEquality().hash(_adaptiveExposurePerFilterEnabled),
        const DeepCollectionEquality().hash(_adaptiveExposurePerFilterMinSecs),
        const DeepCollectionEquality().hash(_adaptiveExposurePerFilterMaxSecs),
        parkOnUnsafeWeather,
        autoFocusOnFilterChange,
        afDisableGuidingDuringAf,
        ditherEnabled,
        ditherScale,
        recoveryDefaultRetryIntervalMins,
        recoveryDefaultMaxDurationMins,
        recoveryStopTrackingDuringRecovery,
        recoveryAbortOnMeridian,
        recoveryAudibleAlertWhenEntered,
        parkBeforeDawn,
        enableMeridianFlip,
        tempCompensation,
        tempCoefficient,
        backlashCompensation,
        settleThreshold,
        settleTimeout,
        plateSolver,
        blindSolve,
        bortleClass,
        effectiveHorizonDeg,
        preflightStrictness,
        polarAlignmentMaxAgeDays,
        opticalTrainDriftThreshold,
        darkLibraryMinCoverage,
        smartNightMaxSessionHours,
        smartNightDefaultAfCadenceFrames,
        smartNightDefaultIntegrationBudgetMinsPerTarget,
        smartNightIncludeFlatsAtEnd,
        smartNightUseSchedulerForMultiTarget,
        smartNightSchedulerTargetThreshold,
        smartNightDefaultStrategy,
        smartNightPolarAlignmentStaleAfterDays,
        smartNightSubExposureFloorSecs,
        smartNightSubExposureCeilingSecs,
        smartNightTargetSnr,
        coolingBehavior,
        defaultGain,
        defaultOffset,
        webServerEnabled,
        webServerPort,
        phd2Path,
        phd2Host,
        phd2Port,
        notificationsEnabled,
        notifyOnSequenceComplete,
        notifyOnError,
        notifyOnMeridianFlip,
        soundEnabled,
        audibleAlertsOnCritical,
        criticalAlertSound,
        pushCriticalAlerts,
        smartNightAutoPromptEnabled,
        promptForNotesAfterRun,
        sessionHandoffAutoPrompt,
        campaignRollupSurfaceTargetsTab,
        campaignRollupGroupingMode,
        afMethod,
        afCurveFitting,
        afStepSize,
        afExposureTime,
        afInitialOffsetSteps,
        afNumberOfAttempts,
        afUseBrightestNStars,
        afOuterCropRatio,
        afInnerCropRatio,
        afBinning,
        afRSquaredThreshold,
        afFocuserSettleTimeMs,
        afExposuresPerPoint,
        afBacklashCompMethod,
        afBacklashIn,
        afBacklashOut,
        afAutofocusFilterName,
        afFilterSettingsJson,
        useFilterFocusOffsets,
        astrometryPath,
        observerName,
        imageFormat,
        bitDepth,
        timezone,
        useSystemTime
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AppSettingsImplCopyWith<_$AppSettingsImpl> get copyWith =>
      __$$AppSettingsImplCopyWithImpl<_$AppSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppSettingsImplToJson(
      this,
    );
  }
}

abstract class _AppSettings implements AppSettings {
  const factory _AppSettings(
      {final ObserverLocation? location,
      final String theme,
      final String language,
      final bool autoConnect,
      final double latitude,
      final double longitude,
      final double elevation,
      final String fileNamingPattern,
      final int meridianFlipMinutes,
      final int autoFocusEveryMinutes,
      final int ditherEveryFrames,
      final int plateSolveTimeout,
      final double plateSolveSearchRadius,
      final String discordWebhook,
      final String pushoverKey,
      final String pushoverUser,
      final String astapPath,
      final bool autoDiscoverOnLaunch,
      final String accentColor,
      final String fontSize,
      final String uiScale,
      final String indiServerHost,
      final int indiServerPort,
      final bool indiAutoConnect,
      final String alpacaServerHost,
      final int alpacaServerPort,
      final bool alpacaAutoDiscover,
      final bool useNativeExecution,
      final bool useSimulationMode,
      final String imageOutputPath,
      final String observer,
      final String telescope,
      final String instrument,
      final bool updateCheckEnabled,
      final String updateServerUrl,
      final String updateChannel,
      final int updateCheckIntervalHours,
      final String skippedUpdateVersion,
      final SafetyFailMode safetyFailMode,
      final bool enableImageGrading,
      final double? imageGradingHfrThresholdPx,
      final double? imageGradingHfrBaselinePercent,
      final double? imageGradingEccentricityThreshold,
      final int? imageGradingStarCountMin,
      final int imageGradingMaxConsecutiveRejects,
      final String? imageGradingRejectFolderPath,
      final bool adaptiveExposureEnabled,
      final double adaptiveExposureTargetSnr,
      final double adaptiveExposureReferenceMag,
      final double adaptiveExposureMinSecs,
      final double adaptiveExposureMaxSecs,
      final Map<String, bool> adaptiveExposurePerFilterEnabled,
      final Map<String, double> adaptiveExposurePerFilterMinSecs,
      final Map<String, double> adaptiveExposurePerFilterMaxSecs,
      final bool parkOnUnsafeWeather,
      final bool autoFocusOnFilterChange,
      final bool afDisableGuidingDuringAf,
      final bool ditherEnabled,
      final String ditherScale,
      final double recoveryDefaultRetryIntervalMins,
      final double recoveryDefaultMaxDurationMins,
      final bool recoveryStopTrackingDuringRecovery,
      final bool recoveryAbortOnMeridian,
      final bool recoveryAudibleAlertWhenEntered,
      final bool parkBeforeDawn,
      final bool enableMeridianFlip,
      final bool tempCompensation,
      final double tempCoefficient,
      final int backlashCompensation,
      final double settleThreshold,
      final int settleTimeout,
      final String plateSolver,
      final bool blindSolve,
      final int bortleClass,
      final double effectiveHorizonDeg,
      final String preflightStrictness,
      final int polarAlignmentMaxAgeDays,
      final double opticalTrainDriftThreshold,
      final int darkLibraryMinCoverage,
      final double? smartNightMaxSessionHours,
      final int smartNightDefaultAfCadenceFrames,
      final int smartNightDefaultIntegrationBudgetMinsPerTarget,
      final bool smartNightIncludeFlatsAtEnd,
      final bool smartNightUseSchedulerForMultiTarget,
      final int smartNightSchedulerTargetThreshold,
      final String smartNightDefaultStrategy,
      final int smartNightPolarAlignmentStaleAfterDays,
      final double smartNightSubExposureFloorSecs,
      final double smartNightSubExposureCeilingSecs,
      final double smartNightTargetSnr,
      final String coolingBehavior,
      final int defaultGain,
      final int defaultOffset,
      final bool webServerEnabled,
      final int webServerPort,
      final String phd2Path,
      final String phd2Host,
      final int phd2Port,
      final bool notificationsEnabled,
      final bool notifyOnSequenceComplete,
      final bool notifyOnError,
      final bool notifyOnMeridianFlip,
      final bool soundEnabled,
      final bool audibleAlertsOnCritical,
      final String criticalAlertSound,
      final bool pushCriticalAlerts,
      final bool smartNightAutoPromptEnabled,
      final bool promptForNotesAfterRun,
      final bool sessionHandoffAutoPrompt,
      final bool campaignRollupSurfaceTargetsTab,
      final String campaignRollupGroupingMode,
      final String afMethod,
      final String afCurveFitting,
      final int afStepSize,
      final double afExposureTime,
      final int afInitialOffsetSteps,
      final int afNumberOfAttempts,
      final int afUseBrightestNStars,
      final double afOuterCropRatio,
      final double afInnerCropRatio,
      final int afBinning,
      final double afRSquaredThreshold,
      final int afFocuserSettleTimeMs,
      final int afExposuresPerPoint,
      final String afBacklashCompMethod,
      final int afBacklashIn,
      final int afBacklashOut,
      final String afAutofocusFilterName,
      final String afFilterSettingsJson,
      final bool useFilterFocusOffsets,
      final String astrometryPath,
      final String observerName,
      final String imageFormat,
      final String bitDepth,
      final String timezone,
      final bool useSystemTime}) = _$AppSettingsImpl;

  factory _AppSettings.fromJson(Map<String, dynamic> json) =
      _$AppSettingsImpl.fromJson;

  @override
  ObserverLocation? get location;
  @override
  String get theme;
  @override
  String get language;
  @override
  bool get autoConnect;
  @override // Additional fields for compatibility with provider AppSettings
  double get latitude;
  @override
  double get longitude;
  @override
  double get elevation;
  @override
  String get fileNamingPattern;
  @override
  int get meridianFlipMinutes;
  @override
  int get autoFocusEveryMinutes;
  @override
  int get ditherEveryFrames;
  @override
  int get plateSolveTimeout;
  @override
  double get plateSolveSearchRadius;
  @override
  String get discordWebhook;
  @override
  String get pushoverKey;
  @override
  String get pushoverUser;
  @override
  String get astapPath;
  @override // Discovery settings
  bool get autoDiscoverOnLaunch;
  @override
  String get accentColor;
  @override
  String get fontSize;
  @override
  String get uiScale;
  @override // Auto, Small (0.8x), Normal (1.0x), Large (1.2x), Extra Large (1.4x)
// Protocol settings
  String get indiServerHost;
  @override
  int get indiServerPort;
  @override
  bool get indiAutoConnect;
  @override
  String get alpacaServerHost;
  @override
  int get alpacaServerPort;
  @override
  bool get alpacaAutoDiscover;
  @override // Sequencer execution settings
  bool get useNativeExecution;
  @override
  bool get useSimulationMode;
  @override // Image capture settings
  String get imageOutputPath;
  @override
  String get observer;
  @override
  String get telescope;
  @override
  String get instrument;
  @override // Update settings
  bool get updateCheckEnabled;
  @override
  String get updateServerUrl;
  @override
  String get updateChannel;
  @override
  int get updateCheckIntervalHours;
  @override
  String get skippedUpdateVersion;
  @override // Safety settings
  SafetyFailMode get safetyFailMode;
  @override // -------------------------------------------------------------------
// Wave 3 Image Grading: live frame Pass/Reject thresholds. Opt-in:
// disabled by default so existing users keep current behaviour
// (every captured frame saved, none auto-rejected).
// -------------------------------------------------------------------
  /// Master switch: when false, no grading runs at all.
  bool get enableImageGrading;
  @override

  /// Reject if HFR exceeds this absolute pixel value. `null` => don't
  /// apply the absolute check.
  double? get imageGradingHfrThresholdPx;
  @override

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. `null` =>
  /// don't apply the baseline-relative check.
  double? get imageGradingHfrBaselinePercent;
  @override

  /// Reject if star eccentricity exceeds this value. `null` => don't apply.
  double? get imageGradingEccentricityThreshold;
  @override

  /// Reject if detected star count falls below this. `null` => don't apply.
  int? get imageGradingStarCountMin;
  @override

  /// Pause sequence after this many consecutive rejects (default 3).
  int get imageGradingMaxConsecutiveRejects;
  @override

  /// Override for the reject folder. `null` => use `<save_path>/Reject/`.
  /// Relative paths resolve against the run save_path; absolute paths
  /// are used verbatim.
  String? get imageGradingRejectFolderPath;
  @override // -------------------------------------------------------------------
// Wave 5 Agent 2 — Sky-brightness adaptive exposures: global defaults.
// Per-ExposureNode overrides still win at runtime; these are the
// values pushed into the executor via
// `sequencerUpdateDefaultAdaptiveExposure` when none of the active
// nodes carry their own block.
// -------------------------------------------------------------------
  /// Master switch — when false, the global default adaptive-exposure
  /// is cleared and the executor falls back to nominal duration for
  /// any node without an explicit per-node override.
  bool get adaptiveExposureEnabled;
  @override

  /// Target SNR for the SNR-based scaling (informational; the live
  /// math uses background flux ratio).
  double get adaptiveExposureTargetSnr;
  @override

  /// Reference sky brightness in mag/arcsec² the nominal exposure
  /// duration was calibrated for. Dark-site default is 21.5.
  double get adaptiveExposureReferenceMag;
  @override

  /// Global minimum exposure clamp in seconds.
  double get adaptiveExposureMinSecs;
  @override

  /// Global maximum exposure clamp in seconds.
  double get adaptiveExposureMaxSecs;
  @override

  /// Per-filter enable map (filter name -> bool). Empty => apply
  /// globally (matches the Rust `is_enabled_for_filter` semantics).
  Map<String, bool> get adaptiveExposurePerFilterEnabled;
  @override

  /// Per-filter minimum exposure overrides (seconds).
  Map<String, double> get adaptiveExposurePerFilterMinSecs;
  @override

  /// Per-filter maximum exposure overrides (seconds).
  Map<String, double> get adaptiveExposurePerFilterMaxSecs;
  @override // -------------------------------------------------------------------
// Full-night audit 2026-06-04 follow-up — high-value unattended-night
// knobs that previously had NO wire field, so a phone/remote save of
// them was rejected by the `_assertKeysRemotable` fail-loud guard. These
// round-trip the autofocus / dither / weather-safety / recovery settings
// that an operator must be able to tune for an unattended night.
// -------------------------------------------------------------------
  /// Weather-safety: when true, the rig parks (not just pauses) when weather
  /// turns unsafe. Mirrors `app_settings` DB key `park_on_unsafe_weather`.
  bool get parkOnUnsafeWeather;
  @override

  /// Autofocus: run an autofocus pass on every filter change.
  /// DB key `auto_focus_on_filter_change`.
  bool get autoFocusOnFilterChange;
  @override

  /// Autofocus: disable the guider while an autofocus sweep runs (avoids the
  /// guide star wandering out of frame during the focuser sweep).
  /// DB key `af_disable_guiding`.
  bool get afDisableGuidingDuringAf;
  @override

  /// Dither: master enable for between-frame dithering.
  /// DB key `dither_enabled`.
  bool get ditherEnabled;
  @override

  /// Dither: dither step size — 'Small', 'Medium', or 'Large'.
  /// DB key `dither_scale`.
  String get ditherScale;
  @override

  /// Recovery: minutes between auto-retry attempts during a recovery loop.
  /// DB key `recovery_default_retry_interval_mins`.
  double get recoveryDefaultRetryIntervalMins;
  @override

  /// Recovery: total minutes before the recovery loop gives up.
  /// DB key `recovery_default_max_duration_mins`.
  double get recoveryDefaultMaxDurationMins;
  @override

  /// Recovery: stop tracking while recovering (dew/cloud wait).
  /// DB key `recovery_stop_tracking_during_recovery`.
  bool get recoveryStopTrackingDuringRecovery;
  @override

  /// Recovery: abort the recovery loop if a meridian crossing falls inside
  /// the recovery window. DB key `recovery_abort_on_meridian`.
  bool get recoveryAbortOnMeridian;
  @override

  /// Recovery: ring the platform alert sound on recovery entry.
  /// DB key `recovery_audible_alert_when_entered`.
  bool get recoveryAudibleAlertWhenEntered;
  @override // -------------------------------------------------------------------
// Full-night audit 2026-06-04 follow-up (long tail) — the remaining
// high-value unattended-night knobs that `_applySettingsMap` already
// maps into AppSettingsState but which had NO wire field, so a remote
// save of them was rejected by the `_assertKeysRemotable` fail-loud
// guard. Carrying them here lets a phone-driven night keep them.
// -------------------------------------------------------------------
// Weather-safety / dawn.
  /// Park the mount before astronomical dawn at the end of the night.
  /// DB key `park_before_dawn`.
  bool get parkBeforeDawn;
  @override // Meridian flip detail.
  /// Master enable for automatic meridian flips. DB key `enable_meridian_flip`.
  bool get enableMeridianFlip;
  @override // Focuser temperature compensation + backlash (calibration).
  /// Enable focuser temperature compensation. DB key `temp_compensation`.
  bool get tempCompensation;
  @override

  /// Temp-comp coefficient (steps per °C). DB key `temp_coefficient`.
  double get tempCoefficient;
  @override

  /// Focuser backlash compensation (steps). DB key `backlash_compensation`.
  int get backlashCompensation;
  @override // Guider settle (calibration).
  /// Guider settle pixel threshold. DB key `settle_threshold`.
  double get settleThreshold;
  @override

  /// Guider settle timeout in seconds. DB key `settle_timeout`.
  int get settleTimeout;
  @override // Plate-solving extra.
  /// Selected plate solver ('ASTAP', 'Astrometry.net', 'PlateSolve2').
  /// DB key `plate_solver`.
  String get plateSolver;
  @override

  /// Allow a blind (no-hint) solve fallback. DB key `blind_solve`.
  bool get blindSolve;
  @override // Site / horizon.
  /// Bortle dark-sky class (1-9). DB key `bortle_class`.
  int get bortleClass;
  @override

  /// Effective horizon altitude floor in degrees. DB key `effective_horizon_deg`.
  double get effectiveHorizonDeg;
  @override // Pre-flight checklist strictness + freshness gates.
  /// Pre-flight strictness as the enum name ('lax' / 'normal' / 'strict').
  /// Carried as a String to avoid the wire model depending on the provider
  /// library that owns the `PreflightStrictness` enum. DB key
  /// `preflight_strictness`.
  String get preflightStrictness;
  @override

  /// Polar-alignment max age (days) before pre-flight flags it.
  /// DB key `polar_alignment_max_age_days`.
  int get polarAlignmentMaxAgeDays;
  @override

  /// Optical-train drift threshold (arcmin) before pre-flight flags it.
  /// DB key `optical_train_drift_threshold`.
  double get opticalTrainDriftThreshold;
  @override // Dark library.
  /// Minimum matching dark frames before the dark library is "covered".
  /// DB key `dark_library_min_coverage`.
  int get darkLibraryMinCoverage;
  @override // -------------------------------------------------------------------
// Smart Night defaults — the one-click "plan tonight" builder reads these
// when assembling a sequence, so an unattended night planned from a phone
// must carry them.
// -------------------------------------------------------------------
  /// Cap a planned session to this many hours. `null` => use the full dark
  /// window. DB key `smart_night_max_session_hours`.
  double? get smartNightMaxSessionHours;
  @override

  /// Default autofocus cadence (frames) for built sequences.
  /// DB key `smart_night_default_af_cadence_frames`.
  int get smartNightDefaultAfCadenceFrames;
  @override

  /// Default per-target integration budget (minutes).
  /// DB key `smart_night_default_integration_budget_mins_per_target`.
  int get smartNightDefaultIntegrationBudgetMinsPerTarget;
  @override

  /// Append flats at the end of the planned night.
  /// DB key `smart_night_include_flats_at_end`.
  bool get smartNightIncludeFlatsAtEnd;
  @override

  /// Use the scheduler (vs a single linear sequence) for multi-target nights.
  /// DB key `smart_night_use_scheduler_for_multi_target`.
  bool get smartNightUseSchedulerForMultiTarget;
  @override

  /// Target count at/above which the scheduler is used.
  /// DB key `smart_night_scheduler_target_threshold`.
  int get smartNightSchedulerTargetThreshold;
  @override

  /// Default capture strategy id (e.g. 'auto_lrgb').
  /// DB key `smart_night_default_strategy`.
  String get smartNightDefaultStrategy;
  @override

  /// Days after which polar alignment is considered stale for the wizard.
  /// DB key `smart_night_polar_alignment_stale_after_days`.
  int get smartNightPolarAlignmentStaleAfterDays;
  @override

  /// Sub-exposure floor (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_floor_secs`.
  double get smartNightSubExposureFloorSecs;
  @override

  /// Sub-exposure ceiling (seconds) for the planner.
  /// DB key `smart_night_sub_exposure_ceiling_secs`.
  double get smartNightSubExposureCeilingSecs;
  @override

  /// Target SNR the planner sizes sub-exposures toward.
  /// DB key `smart_night_target_snr`.
  double get smartNightTargetSnr;
  @override // -------------------------------------------------------------------
// Full remote-settings parity 2026-06-05 — the remaining setter-reachable
// knobs that `_applySettingsMap` already maps into AppSettingsState but
// which had NO wire field, so a phone/remote save of them was rejected by
// the `_assertKeysRemotable` fail-loud guard. Carrying them here completes
// the unattended-night knob set so a phone can edit the whole config.
// The defaults mirror AppSettingsState's constructor defaults so the wire
// model never injects a different value than local state.
// -------------------------------------------------------------------
// Equipment defaults (camera).
  /// Cooling behaviour: 'On Connect' / 'Manual' / 'Never'. DB `cooling_behavior`.
  String get coolingBehavior;
  @override

  /// Default camera gain. DB `default_gain`.
  int get defaultGain;
  @override

  /// Default camera offset. DB `default_offset`.
  int get defaultOffset;
  @override // Remote access / web server.
  /// Headless web server enabled. DB `web_server_enabled`.
  bool get webServerEnabled;
  @override

  /// Headless web server port. DB `web_server_port`.
  int get webServerPort;
  @override // PHD2 connection.
  /// PHD2 executable path. DB `phd2_path`.
  String get phd2Path;
  @override

  /// PHD2 host. DB `phd2_host`.
  String get phd2Host;
  @override

  /// PHD2 port. DB `phd2_port`.
  int get phd2Port;
  @override // Notification toggles.
  /// Master notifications switch. DB `notifications_enabled`.
  bool get notificationsEnabled;
  @override

  /// Notify when a sequence completes. DB `notify_on_sequence_complete`.
  bool get notifyOnSequenceComplete;
  @override

  /// Notify on error. DB `notify_on_error`.
  bool get notifyOnError;
  @override

  /// Notify on meridian flip. DB `notify_on_meridian_flip`.
  bool get notifyOnMeridianFlip;
  @override

  /// In-app notification sound. DB `sound_enabled`.
  bool get soundEnabled;
  @override

  /// Ring the platform alert on critical-severity events. DB
  /// `audible_alerts_on_critical`.
  bool get audibleAlertsOnCritical;
  @override

  /// Which sound for critical alerts ('systemBell' / 'none'). DB
  /// `critical_alert_sound`.
  String get criticalAlertSound;
  @override

  /// Forward critical alerts to paired phones as push. DB `push_critical_alerts`.
  bool get pushCriticalAlerts;
  @override // Session-lifecycle + campaign-rollup prefs.
  /// Show the Smart-Night auto-prompt when equipment is ready. DB
  /// `smart_night.auto_prompt_enabled`.
  bool get smartNightAutoPromptEnabled;
  @override

  /// Prompt for notes after a run. DB `notes.prompt_after_run`.
  bool get promptForNotesAfterRun;
  @override

  /// Auto-open the multi-night carry-over banner. DB
  /// `session.handoff_auto_prompt`.
  bool get sessionHandoffAutoPrompt;
  @override

  /// Surface the campaign-rollup column on the Targets tab. DB
  /// `campaign_rollup.surface_targets_tab`.
  bool get campaignRollupSurfaceTargetsTab;
  @override

  /// Campaign-rollup grouping mode. DB `campaign_rollup.grouping_mode`.
  String get campaignRollupGroupingMode;
  @override // Autofocus detailed sweep params.
  /// AF method. DB `af_method`.
  String get afMethod;
  @override

  /// AF curve fitting. DB `af_curve_fitting`.
  String get afCurveFitting;
  @override

  /// AF step size between measurement points. DB `af_step_size`.
  int get afStepSize;
  @override

  /// AF exposure time (seconds). DB `af_exposure_time`.
  double get afExposureTime;
  @override

  /// AF initial offset steps out from center. DB `af_initial_offset_steps`.
  int get afInitialOffsetSteps;
  @override

  /// AF retry count on failure. DB `af_number_of_attempts`.
  int get afNumberOfAttempts;
  @override

  /// AF brightest-N stars (0 = all). DB `af_use_brightest_n_stars`.
  int get afUseBrightestNStars;
  @override

  /// AF outer crop ratio. DB `af_outer_crop_ratio`.
  double get afOuterCropRatio;
  @override

  /// AF inner crop ratio. DB `af_inner_crop_ratio`.
  double get afInnerCropRatio;
  @override

  /// AF binning. DB `af_binning`.
  int get afBinning;
  @override

  /// AF R² fit-quality threshold. DB `af_r_squared_threshold`.
  double get afRSquaredThreshold;
  @override

  /// AF focuser settle time (ms). DB `af_focuser_settle_time_ms`.
  int get afFocuserSettleTimeMs;
  @override

  /// AF exposures per measurement point. DB `af_exposures_per_point`.
  int get afExposuresPerPoint;
  @override

  /// AF backlash compensation method. DB `af_backlash_comp_method`.
  String get afBacklashCompMethod;
  @override

  /// AF backlash-in steps. DB `af_backlash_in`.
  int get afBacklashIn;
  @override

  /// AF backlash-out steps. DB `af_backlash_out`.
  int get afBacklashOut;
  @override

  /// Designated AF filter (empty = current). DB `af_autofocus_filter_name`.
  String get afAutofocusFilterName;
  @override

  /// Per-filter AF config JSON map. DB `af_filter_settings`.
  String get afFilterSettingsJson;
  @override

  /// Apply focus offsets on filter change. DB `use_filter_focus_offsets`.
  bool get useFilterFocusOffsets;
  @override // Misc imaging / FITS / plate-solve config relevant to an unattended night.
  /// Astrometry.net solver path. DB `astrometry_path`.
  String get astrometryPath;
  @override

  /// FITS OBSERVER keyword. DB `observer_name`.
  String get observerName;
  @override

  /// Image format ('FITS' / 'XISF' / 'TIFF'). DB `image_format`.
  String get imageFormat;
  @override

  /// Bit depth ('16-bit' / '32-bit'). DB `bit_depth`.
  String get bitDepth;
  @override

  /// Observing timezone. DB `timezone`.
  String get timezone;
  @override

  /// Use system time vs a fixed observing time. DB `use_system_time`.
  bool get useSystemTime;
  @override
  @JsonKey(ignore: true)
  _$$AppSettingsImplCopyWith<_$AppSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
