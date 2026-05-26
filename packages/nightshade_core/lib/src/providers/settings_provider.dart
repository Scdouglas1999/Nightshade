import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import '../models/backend/event_types.dart'
    show EventCategory, NightshadeEvent, settingsChangedEventType;
import 'database_provider.dart';
import 'backend_provider.dart';
import '../models/settings/app_settings.dart' as models;
import '../models/settings/app_settings.dart'
    show SafetyFailMode, kDefaultAccentColorHex;
import '../models/settings/rendering_platform.dart';
import '../models/imaging/imaging_models.dart'
    show AutofocusSettings, FilterAutofocusConfig;

// ============================================================================
// Wave 5 Agent 3 — Pre-flight strictness
// ============================================================================

/// Pre-flight validation strictness mode. Tunes how aggressively the
/// pre-flight dialog should warn (or block) on questionable conditions:
///
///   * [lax]     — only obvious hardware errors block. Missing darks, stale
///                 polar alignment, mild time drift all surface as `info`.
///                 Suitable for "experienced user, knows what they're doing".
///   * [normal]  — default. Missing darks / stale alignment / cooler ambient
///                 issues become `warning`. Sequence can still start.
///   * [strict]  — production / unattended imaging. Missing darks and stale
///                 polar alignment become `error` (sequence won't start).
///                 Time-sync drift > 30 s is always an error regardless of
///                 strictness (it would falsify FITS timestamps).
enum PreflightStrictness { lax, normal, strict }

extension PreflightStrictnessLabel on PreflightStrictness {
  String get persistedName {
    switch (this) {
      case PreflightStrictness.lax:
        return 'lax';
      case PreflightStrictness.normal:
        return 'normal';
      case PreflightStrictness.strict:
        return 'strict';
    }
  }

  String get displayName {
    switch (this) {
      case PreflightStrictness.lax:
        return 'Lax';
      case PreflightStrictness.normal:
        return 'Normal';
      case PreflightStrictness.strict:
        return 'Strict';
    }
  }

  String get description {
    switch (this) {
      case PreflightStrictness.lax:
        return 'Soft warnings only. Missing darks and stale calibration surface as info.';
      case PreflightStrictness.normal:
        return 'Default. Missing darks and stale calibration are warnings; severe issues block.';
      case PreflightStrictness.strict:
        return 'Production / unattended. Missing darks and stale alignment block the start.';
    }
  }
}

PreflightStrictness _parsePreflightStrictness(String? value) {
  switch (value) {
    case 'lax':
      return PreflightStrictness.lax;
    case 'strict':
      return PreflightStrictness.strict;
    case 'normal':
    case null:
      return PreflightStrictness.normal;
    default:
      return PreflightStrictness.normal;
  }
}

// ============================================================================
// App Settings - Complete settings model
// ============================================================================

/// Runtime, in-memory application-settings state owned by
/// [AppSettingsNotifier]. Distinct from the persisted/freezed
/// `AppSettings` model in `models/settings/app_settings.dart`, which is the
/// Pack G — sentinel used by `AppSettingsState.copyWith` to distinguish
/// "no change" from "explicitly clear the nullable field". Dart's
/// `T?` parameter cannot express both "leave alone" and "set to null"
/// without this trick. Keep this private to the file so callers always
/// go through `copyWith`.
const Object _unset = Object();

/// Rust-bridge / JSON-persisted snapshot. Renamed from `AppSettings` to
/// disambiguate (audit-arch §2.2).
class AppSettingsState {
  // General
  final bool startMinimized;
  final bool autoConnectEquipment;
  final bool autoSaveSequences;
  final bool confirmBeforeClosing;
  final bool autoDiscoverOnLaunch;

  // Appearance
  final String theme; // 'dark' or 'light'
  final String language; // 'en', 'es'
  final String accentColor; // hex color
  final String fontSize; // 'Small', 'Medium', 'Large'
  final String
      uiScale; // 'Auto', 'Small (0.8x)', 'Normal (1.0x)', 'Large (1.2x)', 'Extra Large (1.4x)'
  final bool sidebarCollapsed;

  // Location
  final double latitude;
  final double longitude;
  final double elevation;
  final String timezone;
  final bool useSystemTime;

  // Imaging
  final String imageFormat; // 'FITS', 'XISF', 'TIFF'
  final String fileNamingPattern;
  final String bitDepth; // '16-bit', '32-bit'

  // Sequencer
  final bool parkOnUnsafeWeather;
  final bool parkBeforeDawn;
  final int meridianFlipMinutes; // minutes before meridian
  final bool autoFocusOnFilterChange;
  final bool useFilterFocusOffsets; // Apply focus offsets when changing filters
  final int autoFocusEveryMinutes;
  final bool ditherEnabled;
  final int ditherEveryFrames;
  final SafetyFailMode
      safetyFailMode; // How to behave when safety data unavailable

  // Plate Solving
  final String plateSolver; // 'ASTAP', 'Astrometry.net', 'PlateSolve2'
  final String astapPath;
  final String astrometryPath;
  final int plateSolveTimeout;
  final double plateSolveSearchRadius;
  final bool blindSolve;

  // PHD2 Guiding
  final String phd2Path;
  final String phd2Host;
  final int phd2Port;

  // Notifications
  final bool notificationsEnabled;
  final String discordWebhook;
  final String pushoverKey;
  final String pushoverUser;
  final bool notifyOnSequenceComplete;
  final bool notifyOnError;
  final bool notifyOnMeridianFlip;
  final bool soundEnabled;

  // File Paths
  final String imageOutputPath;
  final String sequencesPath;
  final String databasePath;
  final String logsPath;

  // Protocol Settings
  final String indiServerHost;
  final int indiServerPort;
  final bool indiAutoConnect;
  final String alpacaServerHost;
  final int alpacaServerPort;
  final bool alpacaAutoDiscover;

  // Sequencer Execution Settings
  final bool useNativeExecution;
  final bool useSimulationMode;

  // Remote Access / Web Server Settings
  final bool webServerEnabled;
  final int webServerPort;

  // Equipment Settings - Camera
  final String coolingBehavior; // 'On Connect', 'Manual', 'Never'
  final int defaultGain;
  final int defaultOffset;

  // Equipment Settings - Mount
  final bool enableMeridianFlip;

  // Equipment Settings - Focuser
  final bool tempCompensation;
  final double tempCoefficient;
  final int backlashCompensation;

  // Equipment Settings - Guider
  final String ditherScale; // 'Small', 'Medium', 'Large'
  final double settleThreshold;
  final int settleTimeout;

  // Observing Environment
  final int bortleClass; // 1-9, Bortle dark-sky scale
  final String
      horizonProfileJson; // JSON: 8 altitude values at N/NE/E/SE/S/SW/W/NW

  /// Effective horizon in degrees used by the Run Dashboard, scheduler and
  /// planetarium when computing "time-to-set". 0° = mathematical horizon;
  /// a value like 20° models trees / structures the user can't see
  /// through. The same value is consumed by every "set" display in the
  /// app so the dashboard and the planetarium agree to the second.
  final double effectiveHorizonDeg;

  /// When true, critical-severity executor events trigger a system bell on
  /// top of the in-app banner / notification. Useful for unattended
  /// imaging where the user has walked away from the laptop.
  final bool audibleAlertsOnCritical;

  /// Planetarium renderer: legacy CustomPainter (v1) or Rust+wgpu (v2).
  final RenderingPlatform renderingPlatform;

  /// Which sound to play when [audibleAlertsOnCritical] fires.
  ///
  /// Allowed values:
  ///   * `systemBell` (default): Flutter's [SystemSound.alert] — works on
  ///     Windows / macOS / Linux / iOS / Android.
  ///   * `none`: silence even when [audibleAlertsOnCritical] is true (kept
  ///     because we may add custom sound assets later; "none" lets the user
  ///     keep the toggle on but mute the audio temporarily without flipping
  ///     it off and losing the banner-only behaviour).
  final String criticalAlertSound;

  /// When true, the headless server forwards critical-severity executor
  /// events to paired mobile clients as push notifications, on top of the
  /// in-app banner / notification. Default on — if the user has gone to the
  /// trouble of pairing a phone, they want to be alerted.
  final bool pushCriticalAlerts;

  // -------------------------------------------------------------------
  // Wave 4 Recovery Mode — user-tunable defaults
  // -------------------------------------------------------------------
  /// Minutes between auto-retry attempts during a recovery loop. SGP
  /// default: 10 minutes. Persisted as a double-precision count of
  /// minutes so the bridge layer can multiply by 60 once.
  final double recoveryDefaultRetryIntervalMins;

  /// Total minutes before the recovery loop gives up. SGP default: 90.
  final double recoveryDefaultMaxDurationMins;

  /// When true, the executor commands the mount to stop tracking on
  /// recovery entry. Default on — most failure modes (guide star, dew,
  /// weather, drift) are improved by parking tracking so the rig doesn't
  /// keep sliding while the operator is asleep.
  final bool recoveryStopTrackingDuringRecovery;

  /// When true, an imminent meridian crossing inside the recovery window
  /// aborts the loop instead of trying to retry across the flip. SGP
  /// behaviour: a recovery loop that straddles a flip leaves the rig in
  /// an unpredictable state.
  final bool recoveryAbortOnMeridian;

  /// When true, ring the platform alert sound on recovery entry. Reuses
  /// the existing critical-alert path so the user setting is unified
  /// with [audibleAlertsOnCritical].
  final bool recoveryAudibleAlertWhenEntered;

  // Autofocus Settings
  final String afMethod; // 'Star HFR'
  final String afCurveFitting; // 'Hyperbolic', 'Parabolic', 'Trend Lines'
  final int afStepSize; // step size between measurement points
  final double afExposureTime; // default exposure for AF frames
  final int afInitialOffsetSteps; // how many steps out from center
  final int afNumberOfAttempts; // retry count on failure
  final int afUseBrightestNStars; // 0 = use all
  final double afOuterCropRatio;
  final double afInnerCropRatio;
  final int afBinning;
  final double afRSquaredThreshold;
  final bool afDisableGuidingDuringAf;
  final int afFocuserSettleTimeMs;
  final int afExposuresPerPoint;
  final String afBacklashCompMethod; // 'None', 'Overshoot', 'Absolute'
  final int afBacklashIn;
  final int afBacklashOut;
  final String
      afAutofocusFilterName; // designated filter for AF runs (empty = use current)
  final String
      afFilterSettingsJson; // JSON map of filter name to FilterAutofocusConfig

  /// Pack G — observer name written into FITS `OBSERVER`. Empty string
  /// (the default) is treated as "no observer" and the keyword is omitted
  /// from FITS rather than emitted with a sentinel.
  final String observerName;

  // -------------------------------------------------------------------
  // Pack G — Wave 3 Image Grading (live frame Pass/Reject)
  // -------------------------------------------------------------------
  /// Master switch: when false, no grading runs and the executor's
  /// RuntimeConfig.default_quality_check is set to None at start.
  final bool enableImageGrading;

  /// Reject if HFR exceeds this absolute pixel value. `null` => don't
  /// apply the absolute check.
  final double? imageGradingHfrThresholdPx;

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. `null` =>
  /// don't apply the baseline-relative check.
  final double? imageGradingHfrBaselinePercent;

  /// Reject if star eccentricity exceeds this value. `null` => don't apply.
  final double? imageGradingEccentricityThreshold;

  /// Reject if detected star count falls below this. `null` => don't apply.
  final int? imageGradingStarCountMin;

  /// Pause sequence after this many consecutive rejects (default 3).
  final int imageGradingMaxConsecutiveRejects;

  /// Override for the reject folder. `null` => use `<save_path>/Reject/`.
  /// Relative paths resolve against the run save_path; absolute paths are
  /// used verbatim.
  final String? imageGradingRejectFolderPath;

  // -------------------------------------------------------------------
  // Wave 5 Agent 2 — Sky-brightness adaptive exposure (global defaults)
  // -------------------------------------------------------------------
  /// Master switch for the global default adaptive-exposure config.
  /// When false the global default is cleared in the executor and only
  /// per-node overrides apply.
  final bool adaptiveExposureEnabled;

  /// Target SNR (informational; live math uses background flux ratio).
  final double adaptiveExposureTargetSnr;

  /// Reference sky brightness (mag/arcsec²) the nominal duration was
  /// calibrated for. Dark-site default 21.5.
  final double adaptiveExposureReferenceMag;

  /// Global minimum exposure clamp (seconds).
  final double adaptiveExposureMinSecs;

  /// Global maximum exposure clamp (seconds).
  final double adaptiveExposureMaxSecs;

  /// Per-filter enable map. Empty => apply globally.
  final Map<String, bool> adaptiveExposurePerFilterEnabled;

  /// Per-filter minimum exposure overrides (seconds).
  final Map<String, double> adaptiveExposurePerFilterMinSecs;

  /// Per-filter maximum exposure overrides (seconds).
  final Map<String, double> adaptiveExposurePerFilterMaxSecs;

  // -------------------------------------------------------------------
  // Wave 5 Agent 3 — Pre-flight checks
  // -------------------------------------------------------------------
  /// How aggressively the pre-flight dialog should warn or block on
  /// questionable conditions (missing darks, stale polar alignment, time
  /// drift, focuser at edge of travel, etc.). Default [PreflightStrictness.normal].
  final PreflightStrictness preflightStrictness;

  /// Maximum age in days for the last polar alignment before pre-flight
  /// flags it as stale. Default 7 days (assuming a permanently-mounted
  /// rig). Portable rigs typically want 1 (every session).
  final int polarAlignmentMaxAgeDays;

  /// Minimum number of dark frames required to consider a (gain, offset,
  /// temp, duration, binning) combination "covered". Below this the
  /// pre-flight rule emits a coverage warning. Default 10 (median-combine
  /// produces a master with usable read-noise reduction at N >= 10).
  final int darkLibraryMinCoverage;

  /// Threshold (mm or score units) above which the optical-train pre-flight
  /// comparison flags "your rig has shifted since last session". The
  /// comparison runs over the diagnostics `tiltScore` + `collimationScore`
  /// delta. Default 8 — picks up a meaningful spacer change without firing
  /// on noise.
  final double opticalTrainDriftThreshold;

  // -------------------------------------------------------------------
  // Wave 6 Agent 1 — Smart Night auto-builder defaults
  // -------------------------------------------------------------------
  /// Maximum session wall-clock duration (hours) the Smart Night wizard
  /// uses to cap the planning window. `null` => use the full dark window
  /// (astronomical dusk → dawn).
  final double? smartNightMaxSessionHours;

  /// Default autofocus cadence (frames) for the Smart Night wizard when
  /// running the `everyNFrames` strategy.
  final int smartNightDefaultAfCadenceFrames;

  /// Default integration budget per target (minutes) the wizard uses.
  /// Tweaks the per-target window cap when composing per-filter plans.
  final int smartNightDefaultIntegrationBudgetMinsPerTarget;

  /// Whether the wizard appends end-of-session flats when the active
  /// profile has a cover calibrator.
  final bool smartNightIncludeFlatsAtEnd;

  /// Whether the wizard wraps multi-target plans in a TargetSchedulerNode
  /// (rather than a linear chain) when the target count is at or above
  /// [smartNightSchedulerTargetThreshold].
  final bool smartNightUseSchedulerForMultiTarget;

  /// Minimum target count before the wizard auto-picks scheduler mode.
  final int smartNightSchedulerTargetThreshold;

  /// Default Smart Night strategy persisted across sessions. One of
  /// `auto_lrgb`, `mono_lrgb`, `narrowband_hoo`, `narrowband_sho`,
  /// `osc_one_shot`.
  final String smartNightDefaultStrategy;

  /// Days after which a polar alignment is "stale" enough to warrant the
  /// Smart Night wizard prepending an alignment node. Distinct from the
  /// pre-flight rule's [polarAlignmentMaxAgeDays] knob because the wizard
  /// wants the freshness target to be configurable independently (e.g.
  /// pre-flight at 7 days, but Smart Night prepends only at 14 days).
  final int smartNightPolarAlignmentStaleAfterDays;

  /// Smart Night exposure calculator floor (seconds). Separate from the
  /// runtime adaptive-exposure floor so one feature does not silently tune
  /// the other.
  final double smartNightSubExposureFloorSecs;

  /// Smart Night exposure calculator ceiling (seconds).
  final double smartNightSubExposureCeilingSecs;

  /// Smart Night planning SNR target used by the exposure calculator.
  final double smartNightTargetSnr;

  /// Whether the dashboard may show the Smart Night auto-prompt after
  /// equipment is ready. Manual Plan Tonight actions stay available when
  /// this is false.
  final bool smartNightAutoPromptEnabled;

  // -------------------------------------------------------------------
  // Wave 6 Agent 5 — Notes / journal preferences
  // -------------------------------------------------------------------
  /// Whether the auto-prompt note dialog appears after a sequence run
  /// completes. Defaults to true (opt-out, not opt-in: the session
  /// report is more useful when the user is in the habit of dropping
  /// a quick note at the end of every run).
  ///
  /// Mirrored in the database app_settings table under the
  /// `notes.prompt_after_run` key (see [kPromptForNotesAfterRunKey]).
  final bool promptForNotesAfterRun;

  // -------------------------------------------------------------------
  // Wave 7 — Session lifecycle preferences
  // -------------------------------------------------------------------

  /// Whether the multi-night carry-over banner auto-opens at pre-flight
  /// when an unfinished session is detected for one of the sequence's
  /// targets. Default true: the banner is informational only, the user
  /// still has to pick Resume / Restart / Continue New.
  ///
  /// Mirrored in the database under `session.handoff_auto_prompt`.
  final bool sessionHandoffAutoPrompt;

  /// Whether the Targets tab in the sequencer surfaces a per-target
  /// campaign rollup column ("Total integration: 24h Lum, 8h Ha across
  /// 6 sessions"). Default true. Users with a clean targets table can
  /// flip this off for less visual noise.
  ///
  /// Mirrored in the database under `campaign_rollup.surface_targets_tab`.
  final bool campaignRollupSurfaceTargetsTab;

  /// How the campaign rollup groups runs for a given target:
  ///   * `by_target_name` — case-insensitive name match (default; works
  ///     across sequences that re-name the same object).
  ///   * `by_target_id` — exact Drift `targets.id` match (stricter).
  ///   * `by_user_tag` — group by the `targets.tags` field when present.
  ///
  /// Mirrored in the database under `campaign_rollup.grouping_mode`.
  final String campaignRollupGroupingMode;

  // -------------------------------------------------------------------
  // Wave 8 — Adaptive sky-conditions target swap defaults
  //
  // These knobs pre-fill the matching fields on a newly-created
  // [TargetSchedulerNode]. Changing them never mutates an existing node
  // — they're "what should the next scheduler I drop in look like?".
  // Persisted as raw strings in `app_settings`; the map is JSON-encoded.
  // -------------------------------------------------------------------

  /// When true, new [TargetSchedulerNode]s are created with
  /// [TargetSchedulerNode.swapOnConditionsBelow] set to
  /// [adaptiveSwapDefaultThreshold]. When false, new schedulers ship
  /// with adaptive swap *disabled* (`swapOnConditionsBelow = null`) so
  /// the user has to opt in explicitly.
  ///
  /// Mirrored under `adaptive_swap.enabled_by_default`.
  final bool adaptiveSwapEnabledByDefault;

  /// Default conditions-score floor (0..=100) seeded into a new
  /// scheduler's `swapOnConditionsBelow`. Only consulted when
  /// [adaptiveSwapEnabledByDefault] is true.
  ///
  /// Mirrored under `adaptive_swap.default_threshold`.
  final double adaptiveSwapDefaultThreshold;

  /// Default `swapHysteresisSecs` (seconds between consecutive swaps)
  /// seeded into a new scheduler. Mirrored under
  /// `adaptive_swap.default_hysteresis_secs`.
  final double adaptiveSwapDefaultHysteresisSecs;

  /// Per-axis composer weights for the live ConditionsScore. Keys:
  /// `transparency` / `seeing` / `cloud` / `wind`. Mirrored under
  /// `adaptive_swap.score_weights` as a JSON object.
  final Map<String, double> conditionsScoreWeights;

  const AppSettingsState({
    // General
    this.startMinimized = false,
    this.autoConnectEquipment = true,
    this.autoSaveSequences = true,
    this.confirmBeforeClosing = true,
    this.autoDiscoverOnLaunch = true,

    // Appearance
    this.theme = 'dark',
    this.language = 'en',
    this.accentColor = kDefaultAccentColorHex,
    this.fontSize = 'Medium',
    this.uiScale = 'Auto',
    this.sidebarCollapsed = false,

    // Location
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.elevation = 0.0,
    this.timezone = 'UTC',
    this.useSystemTime = true,

    // Imaging
    this.imageFormat = 'FITS',
    this.fileNamingPattern = r'$TARGET_$FILTER_$DATE_$SEQ',
    this.bitDepth = '16-bit',

    // Sequencer
    this.parkOnUnsafeWeather = true,
    this.parkBeforeDawn = true,
    this.meridianFlipMinutes = 5,
    this.autoFocusOnFilterChange = true,
    this.useFilterFocusOffsets = true,
    this.autoFocusEveryMinutes = 60,
    this.ditherEnabled = true,
    this.ditherEveryFrames = 3,
    this.safetyFailMode = SafetyFailMode.failClosed,

    // Plate Solving
    this.plateSolver = 'ASTAP',
    this.astapPath = '',
    this.astrometryPath = '',
    this.plateSolveTimeout = 60,
    this.plateSolveSearchRadius = 30.0,
    this.blindSolve = false,

    // PHD2 Guiding
    this.phd2Path = '',
    this.phd2Host = 'localhost',
    this.phd2Port = 4400,

    // Notifications
    this.notificationsEnabled = true,
    this.discordWebhook = '',
    this.pushoverKey = '',
    this.pushoverUser = '',
    this.notifyOnSequenceComplete = true,
    this.notifyOnError = true,
    this.notifyOnMeridianFlip = false,
    this.soundEnabled = true,

    // File Paths
    this.imageOutputPath = '',
    this.sequencesPath = '',
    this.databasePath = '',
    this.logsPath = '',

    // Protocol Settings
    this.indiServerHost = 'localhost',
    this.indiServerPort = 7624,
    this.indiAutoConnect = false,
    this.alpacaServerHost = 'localhost',
    this.alpacaServerPort = 11111,
    this.alpacaAutoDiscover = false,

    // Sequencer Execution
    this.useNativeExecution = true,
    this.useSimulationMode = false,

    // Remote Access / Web Server
    this.webServerEnabled = false,
    this.webServerPort = 8080,

    // Equipment Settings - Camera
    this.coolingBehavior = 'On Connect',
    this.defaultGain = 100,
    this.defaultOffset = 50,

    // Equipment Settings - Mount
    this.enableMeridianFlip = true,

    // Equipment Settings - Focuser
    this.tempCompensation = true,
    this.tempCoefficient = -12.0,
    this.backlashCompensation = 0,

    // Equipment Settings - Guider
    this.ditherScale = 'Medium',
    this.settleThreshold = 0.5,
    this.settleTimeout = 30,

    // Observing Environment
    this.bortleClass = 5,
    this.horizonProfileJson =
        '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}',
    this.effectiveHorizonDeg = 0.0,
    this.audibleAlertsOnCritical = false,
    this.renderingPlatform = RenderingPlatform.v1,
    this.criticalAlertSound = 'systemBell',
    this.pushCriticalAlerts = true,
    // Wave 4 Recovery Mode — SGP-matching defaults.
    this.recoveryDefaultRetryIntervalMins = 10.0,
    this.recoveryDefaultMaxDurationMins = 90.0,
    this.recoveryStopTrackingDuringRecovery = true,
    this.recoveryAbortOnMeridian = true,
    this.recoveryAudibleAlertWhenEntered = true,

    // Autofocus Settings
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
    this.afDisableGuidingDuringAf = false,
    this.afFocuserSettleTimeMs = 500,
    this.afExposuresPerPoint = 1,
    this.afBacklashCompMethod = 'Overshoot',
    this.afBacklashIn = 350,
    this.afBacklashOut = 0,
    this.afAutofocusFilterName = '',
    this.afFilterSettingsJson = '{}',

    // Pack G — observer name (FITS OBSERVER keyword).
    this.observerName = '',

    // Pack G — Wave 3 Image Grading defaults. Opt-in: disabled by default
    // so existing users keep current behaviour (every captured frame
    // saved, none auto-rejected). Defaults below match the recommended
    // thresholds in the strategic report:
    //   * 3.5 px HFR — catches catastrophic focus drift
    //   * 50% above baseline — catches gradual focus drift
    //   * 0.7 eccentricity — catches trailed frames
    //   * 10 stars min — catches clouds rolling in
    //   * 3 consecutive rejects — pauses the sequence so the user knows
    //     "something is systematically wrong"
    this.enableImageGrading = false,
    this.imageGradingHfrThresholdPx = 3.5,
    this.imageGradingHfrBaselinePercent = 50.0,
    this.imageGradingEccentricityThreshold = 0.7,
    this.imageGradingStarCountMin = 10,
    this.imageGradingMaxConsecutiveRejects = 3,
    this.imageGradingRejectFolderPath,

    // Wave 5 Agent 2 — Sky-brightness adaptive exposure defaults. Off
    // by default so existing users keep current behaviour; reference
    // mag set to 21.5 (rural dark site); 5s–600s global clamp covers
    // the practical exposure range for most rigs.
    this.adaptiveExposureEnabled = false,
    this.adaptiveExposureTargetSnr = 30.0,
    this.adaptiveExposureReferenceMag = 21.5,
    this.adaptiveExposureMinSecs = 5.0,
    this.adaptiveExposureMaxSecs = 600.0,
    this.adaptiveExposurePerFilterEnabled = const {},
    this.adaptiveExposurePerFilterMinSecs = const {},
    this.adaptiveExposurePerFilterMaxSecs = const {},

    // Wave 5 Agent 3 — Pre-flight defaults. Normal strictness, 7-day
    // polar-alignment freshness target (permanent rigs), 10-frame dark
    // coverage quorum, and an optical-train drift threshold that catches
    // a meaningful spacer change without firing on noise.
    this.preflightStrictness = PreflightStrictness.normal,
    this.polarAlignmentMaxAgeDays = 7,
    this.darkLibraryMinCoverage = 10,
    this.opticalTrainDriftThreshold = 8.0,
    // Wave 6 Agent 1 — Smart Night auto-builder defaults. `null` for
    // [smartNightMaxSessionHours] means "use the full dark window";
    // otherwise we cap to the user's chosen duration. The remaining
    // values mirror the SmartNightSettings constructor defaults so the
    // wizard's first launch is consistent whether or not the user has
    // touched Settings → Sequencer Defaults.
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
    this.smartNightAutoPromptEnabled = true,
    // Wave 6 Agent 5 — Notes prompt opt-out. Default on so the journal
    // becomes a habit; user can flip the toggle in Settings → Sequencer.
    this.promptForNotesAfterRun = true,
    // Wave 7 — Session lifecycle. All three default to surface-on so a
    // fresh install gets the carry-over banner and the campaign columns
    // without an explicit opt-in.
    this.sessionHandoffAutoPrompt = true,
    this.campaignRollupSurfaceTargetsTab = true,
    this.campaignRollupGroupingMode = 'by_target_name',
    // Wave 8 — adaptive sky-conditions defaults. The "enabled by default"
    // flag is off so existing users don't get their scheduler behaviour
    // changed by a silent upgrade; opt-in via Settings → Adaptive
    // Conditions. The threshold (50) sits midway in the 0..=100 score
    // band, the hysteresis (180s = 3 min) matches the Rust default, and
    // the weight map mirrors `ConditionsScoreWeights` defaults
    // (transparency 0.40, seeing 0.25, cloud 0.25, wind 0.10).
    this.adaptiveSwapEnabledByDefault = false,
    this.adaptiveSwapDefaultThreshold = 50.0,
    this.adaptiveSwapDefaultHysteresisSecs = 180.0,
    this.conditionsScoreWeights = const {
      'transparency': 0.40,
      'seeing': 0.25,
      'cloud': 0.25,
      'wind': 0.10,
    },
  });

  AppSettingsState copyWith({
    bool? startMinimized,
    bool? autoConnectEquipment,
    bool? autoSaveSequences,
    bool? confirmBeforeClosing,
    bool? autoDiscoverOnLaunch,
    String? theme,
    String? language,
    String? accentColor,
    String? fontSize,
    String? uiScale,
    bool? sidebarCollapsed,
    double? latitude,
    double? longitude,
    double? elevation,
    String? timezone,
    bool? useSystemTime,
    String? imageFormat,
    String? fileNamingPattern,
    String? bitDepth,
    bool? parkOnUnsafeWeather,
    bool? parkBeforeDawn,
    int? meridianFlipMinutes,
    bool? autoFocusOnFilterChange,
    bool? useFilterFocusOffsets,
    int? autoFocusEveryMinutes,
    bool? ditherEnabled,
    int? ditherEveryFrames,
    SafetyFailMode? safetyFailMode,
    String? plateSolver,
    String? astapPath,
    String? astrometryPath,
    int? plateSolveTimeout,
    double? plateSolveSearchRadius,
    bool? blindSolve,
    String? phd2Path,
    String? phd2Host,
    int? phd2Port,
    bool? notificationsEnabled,
    String? discordWebhook,
    String? pushoverKey,
    String? pushoverUser,
    bool? notifyOnSequenceComplete,
    bool? notifyOnError,
    bool? notifyOnMeridianFlip,
    bool? soundEnabled,
    String? imageOutputPath,
    String? sequencesPath,
    String? databasePath,
    String? logsPath,
    String? indiServerHost,
    int? indiServerPort,
    bool? indiAutoConnect,
    String? alpacaServerHost,
    int? alpacaServerPort,
    bool? alpacaAutoDiscover,
    bool? useNativeExecution,
    bool? useSimulationMode,
    // Remote Access / Web Server
    bool? webServerEnabled,
    int? webServerPort,
    // Equipment Settings
    String? coolingBehavior,
    int? defaultGain,
    int? defaultOffset,
    bool? enableMeridianFlip,
    bool? tempCompensation,
    double? tempCoefficient,
    int? backlashCompensation,
    String? ditherScale,
    double? settleThreshold,
    int? settleTimeout,
    // Observing Environment
    int? bortleClass,
    String? horizonProfileJson,
    double? effectiveHorizonDeg,
    bool? audibleAlertsOnCritical,
    RenderingPlatform? renderingPlatform,
    String? criticalAlertSound,
    bool? pushCriticalAlerts,
    // Wave 4 Recovery Mode
    double? recoveryDefaultRetryIntervalMins,
    double? recoveryDefaultMaxDurationMins,
    bool? recoveryStopTrackingDuringRecovery,
    bool? recoveryAbortOnMeridian,
    bool? recoveryAudibleAlertWhenEntered,
    // Autofocus Settings
    String? afMethod,
    String? afCurveFitting,
    int? afStepSize,
    double? afExposureTime,
    int? afInitialOffsetSteps,
    int? afNumberOfAttempts,
    int? afUseBrightestNStars,
    double? afOuterCropRatio,
    double? afInnerCropRatio,
    int? afBinning,
    double? afRSquaredThreshold,
    bool? afDisableGuidingDuringAf,
    int? afFocuserSettleTimeMs,
    int? afExposuresPerPoint,
    String? afBacklashCompMethod,
    int? afBacklashIn,
    int? afBacklashOut,
    String? afAutofocusFilterName,
    String? afFilterSettingsJson,
    // Pack G — observer name (FITS OBSERVER)
    String? observerName,
    // Pack G — Wave 3 Image Grading
    bool? enableImageGrading,
    // Wrap nullable fields with Object() sentinels so callers can set them
    // back to null. We use a private `_unset` sentinel to distinguish
    // "no change" from "set to null". Dart doesn't have a built-in
    // optional-but-nullable pattern; this is the canonical workaround.
    Object? imageGradingHfrThresholdPx = _unset,
    Object? imageGradingHfrBaselinePercent = _unset,
    Object? imageGradingEccentricityThreshold = _unset,
    Object? imageGradingStarCountMin = _unset,
    int? imageGradingMaxConsecutiveRejects,
    Object? imageGradingRejectFolderPath = _unset,
    // Wave 5 Agent 2 — Sky-brightness adaptive exposure
    bool? adaptiveExposureEnabled,
    double? adaptiveExposureTargetSnr,
    double? adaptiveExposureReferenceMag,
    double? adaptiveExposureMinSecs,
    double? adaptiveExposureMaxSecs,
    Map<String, bool>? adaptiveExposurePerFilterEnabled,
    Map<String, double>? adaptiveExposurePerFilterMinSecs,
    Map<String, double>? adaptiveExposurePerFilterMaxSecs,
    // Wave 5 Agent 3 — Pre-flight
    PreflightStrictness? preflightStrictness,
    int? polarAlignmentMaxAgeDays,
    int? darkLibraryMinCoverage,
    double? opticalTrainDriftThreshold,
    // Wave 6 Agent 1 — Smart Night defaults. `smartNightMaxSessionHours`
    // uses the same `_unset` sentinel pattern as the nullable Image
    // Grading thresholds so callers can deliberately clear it back to
    // "use the full dark window".
    Object? smartNightMaxSessionHours = _unset,
    int? smartNightDefaultAfCadenceFrames,
    int? smartNightDefaultIntegrationBudgetMinsPerTarget,
    bool? smartNightIncludeFlatsAtEnd,
    bool? smartNightUseSchedulerForMultiTarget,
    int? smartNightSchedulerTargetThreshold,
    String? smartNightDefaultStrategy,
    int? smartNightPolarAlignmentStaleAfterDays,
    double? smartNightSubExposureFloorSecs,
    double? smartNightSubExposureCeilingSecs,
    double? smartNightTargetSnr,
    bool? smartNightAutoPromptEnabled,
    // Wave 6 Agent 5 — Notes prompt toggle.
    bool? promptForNotesAfterRun,
    // Wave 7 — Session lifecycle.
    bool? sessionHandoffAutoPrompt,
    bool? campaignRollupSurfaceTargetsTab,
    String? campaignRollupGroupingMode,
    // Wave 8 — Adaptive sky-conditions defaults.
    bool? adaptiveSwapEnabledByDefault,
    double? adaptiveSwapDefaultThreshold,
    double? adaptiveSwapDefaultHysteresisSecs,
    Map<String, double>? conditionsScoreWeights,
  }) {
    return AppSettingsState(
      startMinimized: startMinimized ?? this.startMinimized,
      autoConnectEquipment: autoConnectEquipment ?? this.autoConnectEquipment,
      autoSaveSequences: autoSaveSequences ?? this.autoSaveSequences,
      confirmBeforeClosing: confirmBeforeClosing ?? this.confirmBeforeClosing,
      autoDiscoverOnLaunch: autoDiscoverOnLaunch ?? this.autoDiscoverOnLaunch,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      accentColor: accentColor ?? this.accentColor,
      fontSize: fontSize ?? this.fontSize,
      uiScale: uiScale ?? this.uiScale,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      timezone: timezone ?? this.timezone,
      useSystemTime: useSystemTime ?? this.useSystemTime,
      imageFormat: imageFormat ?? this.imageFormat,
      fileNamingPattern: fileNamingPattern ?? this.fileNamingPattern,
      bitDepth: bitDepth ?? this.bitDepth,
      parkOnUnsafeWeather: parkOnUnsafeWeather ?? this.parkOnUnsafeWeather,
      parkBeforeDawn: parkBeforeDawn ?? this.parkBeforeDawn,
      meridianFlipMinutes: meridianFlipMinutes ?? this.meridianFlipMinutes,
      autoFocusOnFilterChange:
          autoFocusOnFilterChange ?? this.autoFocusOnFilterChange,
      useFilterFocusOffsets:
          useFilterFocusOffsets ?? this.useFilterFocusOffsets,
      autoFocusEveryMinutes:
          autoFocusEveryMinutes ?? this.autoFocusEveryMinutes,
      ditherEnabled: ditherEnabled ?? this.ditherEnabled,
      ditherEveryFrames: ditherEveryFrames ?? this.ditherEveryFrames,
      safetyFailMode: safetyFailMode ?? this.safetyFailMode,
      plateSolver: plateSolver ?? this.plateSolver,
      astapPath: astapPath ?? this.astapPath,
      astrometryPath: astrometryPath ?? this.astrometryPath,
      plateSolveTimeout: plateSolveTimeout ?? this.plateSolveTimeout,
      plateSolveSearchRadius:
          plateSolveSearchRadius ?? this.plateSolveSearchRadius,
      blindSolve: blindSolve ?? this.blindSolve,
      phd2Path: phd2Path ?? this.phd2Path,
      phd2Host: phd2Host ?? this.phd2Host,
      phd2Port: phd2Port ?? this.phd2Port,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      discordWebhook: discordWebhook ?? this.discordWebhook,
      pushoverKey: pushoverKey ?? this.pushoverKey,
      pushoverUser: pushoverUser ?? this.pushoverUser,
      notifyOnSequenceComplete:
          notifyOnSequenceComplete ?? this.notifyOnSequenceComplete,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnMeridianFlip: notifyOnMeridianFlip ?? this.notifyOnMeridianFlip,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      imageOutputPath: imageOutputPath ?? this.imageOutputPath,
      sequencesPath: sequencesPath ?? this.sequencesPath,
      databasePath: databasePath ?? this.databasePath,
      logsPath: logsPath ?? this.logsPath,
      indiServerHost: indiServerHost ?? this.indiServerHost,
      indiServerPort: indiServerPort ?? this.indiServerPort,
      indiAutoConnect: indiAutoConnect ?? this.indiAutoConnect,
      alpacaServerHost: alpacaServerHost ?? this.alpacaServerHost,
      alpacaServerPort: alpacaServerPort ?? this.alpacaServerPort,
      alpacaAutoDiscover: alpacaAutoDiscover ?? this.alpacaAutoDiscover,
      useNativeExecution: useNativeExecution ?? this.useNativeExecution,
      useSimulationMode: useSimulationMode ?? this.useSimulationMode,
      // Remote Access / Web Server
      webServerEnabled: webServerEnabled ?? this.webServerEnabled,
      webServerPort: webServerPort ?? this.webServerPort,
      // Equipment Settings
      coolingBehavior: coolingBehavior ?? this.coolingBehavior,
      defaultGain: defaultGain ?? this.defaultGain,
      defaultOffset: defaultOffset ?? this.defaultOffset,
      enableMeridianFlip: enableMeridianFlip ?? this.enableMeridianFlip,
      tempCompensation: tempCompensation ?? this.tempCompensation,
      tempCoefficient: tempCoefficient ?? this.tempCoefficient,
      backlashCompensation: backlashCompensation ?? this.backlashCompensation,
      ditherScale: ditherScale ?? this.ditherScale,
      settleThreshold: settleThreshold ?? this.settleThreshold,
      settleTimeout: settleTimeout ?? this.settleTimeout,
      // Autofocus Settings
      bortleClass: bortleClass ?? this.bortleClass,
      horizonProfileJson: horizonProfileJson ?? this.horizonProfileJson,
      effectiveHorizonDeg: effectiveHorizonDeg ?? this.effectiveHorizonDeg,
      audibleAlertsOnCritical:
          audibleAlertsOnCritical ?? this.audibleAlertsOnCritical,
      renderingPlatform: renderingPlatform ?? this.renderingPlatform,
      criticalAlertSound: criticalAlertSound ?? this.criticalAlertSound,
      pushCriticalAlerts: pushCriticalAlerts ?? this.pushCriticalAlerts,
      // Wave 4 Recovery Mode
      recoveryDefaultRetryIntervalMins: recoveryDefaultRetryIntervalMins ??
          this.recoveryDefaultRetryIntervalMins,
      recoveryDefaultMaxDurationMins:
          recoveryDefaultMaxDurationMins ?? this.recoveryDefaultMaxDurationMins,
      recoveryStopTrackingDuringRecovery: recoveryStopTrackingDuringRecovery ??
          this.recoveryStopTrackingDuringRecovery,
      recoveryAbortOnMeridian:
          recoveryAbortOnMeridian ?? this.recoveryAbortOnMeridian,
      recoveryAudibleAlertWhenEntered: recoveryAudibleAlertWhenEntered ??
          this.recoveryAudibleAlertWhenEntered,
      afMethod: afMethod ?? this.afMethod,
      afCurveFitting: afCurveFitting ?? this.afCurveFitting,
      afStepSize: afStepSize ?? this.afStepSize,
      afExposureTime: afExposureTime ?? this.afExposureTime,
      afInitialOffsetSteps: afInitialOffsetSteps ?? this.afInitialOffsetSteps,
      afNumberOfAttempts: afNumberOfAttempts ?? this.afNumberOfAttempts,
      afUseBrightestNStars: afUseBrightestNStars ?? this.afUseBrightestNStars,
      afOuterCropRatio: afOuterCropRatio ?? this.afOuterCropRatio,
      afInnerCropRatio: afInnerCropRatio ?? this.afInnerCropRatio,
      afBinning: afBinning ?? this.afBinning,
      afRSquaredThreshold: afRSquaredThreshold ?? this.afRSquaredThreshold,
      afDisableGuidingDuringAf:
          afDisableGuidingDuringAf ?? this.afDisableGuidingDuringAf,
      afFocuserSettleTimeMs:
          afFocuserSettleTimeMs ?? this.afFocuserSettleTimeMs,
      afExposuresPerPoint: afExposuresPerPoint ?? this.afExposuresPerPoint,
      afBacklashCompMethod: afBacklashCompMethod ?? this.afBacklashCompMethod,
      afBacklashIn: afBacklashIn ?? this.afBacklashIn,
      afBacklashOut: afBacklashOut ?? this.afBacklashOut,
      afAutofocusFilterName:
          afAutofocusFilterName ?? this.afAutofocusFilterName,
      afFilterSettingsJson: afFilterSettingsJson ?? this.afFilterSettingsJson,
      // Pack G — observer name (FITS OBSERVER)
      observerName: observerName ?? this.observerName,
      // Pack G — Wave 3 Image Grading
      enableImageGrading: enableImageGrading ?? this.enableImageGrading,
      imageGradingHfrThresholdPx: identical(imageGradingHfrThresholdPx, _unset)
          ? this.imageGradingHfrThresholdPx
          : imageGradingHfrThresholdPx as double?,
      imageGradingHfrBaselinePercent:
          identical(imageGradingHfrBaselinePercent, _unset)
              ? this.imageGradingHfrBaselinePercent
              : imageGradingHfrBaselinePercent as double?,
      imageGradingEccentricityThreshold:
          identical(imageGradingEccentricityThreshold, _unset)
              ? this.imageGradingEccentricityThreshold
              : imageGradingEccentricityThreshold as double?,
      imageGradingStarCountMin: identical(imageGradingStarCountMin, _unset)
          ? this.imageGradingStarCountMin
          : imageGradingStarCountMin as int?,
      imageGradingMaxConsecutiveRejects: imageGradingMaxConsecutiveRejects ??
          this.imageGradingMaxConsecutiveRejects,
      imageGradingRejectFolderPath:
          identical(imageGradingRejectFolderPath, _unset)
              ? this.imageGradingRejectFolderPath
              : imageGradingRejectFolderPath as String?,
      // Wave 5 Agent 2 — Sky-brightness adaptive exposure
      adaptiveExposureEnabled:
          adaptiveExposureEnabled ?? this.adaptiveExposureEnabled,
      adaptiveExposureTargetSnr:
          adaptiveExposureTargetSnr ?? this.adaptiveExposureTargetSnr,
      adaptiveExposureReferenceMag:
          adaptiveExposureReferenceMag ?? this.adaptiveExposureReferenceMag,
      adaptiveExposureMinSecs:
          adaptiveExposureMinSecs ?? this.adaptiveExposureMinSecs,
      adaptiveExposureMaxSecs:
          adaptiveExposureMaxSecs ?? this.adaptiveExposureMaxSecs,
      adaptiveExposurePerFilterEnabled: adaptiveExposurePerFilterEnabled ??
          this.adaptiveExposurePerFilterEnabled,
      adaptiveExposurePerFilterMinSecs: adaptiveExposurePerFilterMinSecs ??
          this.adaptiveExposurePerFilterMinSecs,
      adaptiveExposurePerFilterMaxSecs: adaptiveExposurePerFilterMaxSecs ??
          this.adaptiveExposurePerFilterMaxSecs,
      // Wave 5 Agent 3 — Pre-flight
      preflightStrictness: preflightStrictness ?? this.preflightStrictness,
      polarAlignmentMaxAgeDays:
          polarAlignmentMaxAgeDays ?? this.polarAlignmentMaxAgeDays,
      darkLibraryMinCoverage:
          darkLibraryMinCoverage ?? this.darkLibraryMinCoverage,
      opticalTrainDriftThreshold:
          opticalTrainDriftThreshold ?? this.opticalTrainDriftThreshold,
      // Wave 6 Agent 1 — Smart Night defaults.
      smartNightMaxSessionHours: identical(smartNightMaxSessionHours, _unset)
          ? this.smartNightMaxSessionHours
          : smartNightMaxSessionHours as double?,
      smartNightDefaultAfCadenceFrames: smartNightDefaultAfCadenceFrames ??
          this.smartNightDefaultAfCadenceFrames,
      smartNightDefaultIntegrationBudgetMinsPerTarget:
          smartNightDefaultIntegrationBudgetMinsPerTarget ??
              this.smartNightDefaultIntegrationBudgetMinsPerTarget,
      smartNightIncludeFlatsAtEnd:
          smartNightIncludeFlatsAtEnd ?? this.smartNightIncludeFlatsAtEnd,
      smartNightUseSchedulerForMultiTarget:
          smartNightUseSchedulerForMultiTarget ??
              this.smartNightUseSchedulerForMultiTarget,
      smartNightSchedulerTargetThreshold: smartNightSchedulerTargetThreshold ??
          this.smartNightSchedulerTargetThreshold,
      smartNightDefaultStrategy:
          smartNightDefaultStrategy ?? this.smartNightDefaultStrategy,
      smartNightPolarAlignmentStaleAfterDays:
          smartNightPolarAlignmentStaleAfterDays ??
              this.smartNightPolarAlignmentStaleAfterDays,
      smartNightSubExposureFloorSecs:
          smartNightSubExposureFloorSecs ?? this.smartNightSubExposureFloorSecs,
      smartNightSubExposureCeilingSecs: smartNightSubExposureCeilingSecs ??
          this.smartNightSubExposureCeilingSecs,
      smartNightTargetSnr: smartNightTargetSnr ?? this.smartNightTargetSnr,
      smartNightAutoPromptEnabled:
          smartNightAutoPromptEnabled ?? this.smartNightAutoPromptEnabled,
      // Wave 6 Agent 5 — Notes prompt toggle.
      promptForNotesAfterRun:
          promptForNotesAfterRun ?? this.promptForNotesAfterRun,
      // Wave 7 — Session lifecycle.
      sessionHandoffAutoPrompt:
          sessionHandoffAutoPrompt ?? this.sessionHandoffAutoPrompt,
      campaignRollupSurfaceTargetsTab: campaignRollupSurfaceTargetsTab ??
          this.campaignRollupSurfaceTargetsTab,
      campaignRollupGroupingMode:
          campaignRollupGroupingMode ?? this.campaignRollupGroupingMode,
      // Wave 8 — Adaptive sky-conditions defaults.
      adaptiveSwapEnabledByDefault:
          adaptiveSwapEnabledByDefault ?? this.adaptiveSwapEnabledByDefault,
      adaptiveSwapDefaultThreshold:
          adaptiveSwapDefaultThreshold ?? this.adaptiveSwapDefaultThreshold,
      adaptiveSwapDefaultHysteresisSecs: adaptiveSwapDefaultHysteresisSecs ??
          this.adaptiveSwapDefaultHysteresisSecs,
      conditionsScoreWeights:
          conditionsScoreWeights ?? this.conditionsScoreWeights,
    );
  }
}

/// Main app settings notifier that persists all settings to database
class AppSettingsNotifier extends AsyncNotifier<AppSettingsState> {
  models.AppSettings? _remoteSettingsSnapshot;

  // [Wave 6B settings sync] Push-event subscription, live only when the
  // active backend is a NetworkBackend. The host emits one
  // `settings.changed` event per field that differs in a POST
  // /api/settings call; the notifier applies the change in-place so
  // every connected client stays consistent without re-fetching the
  // full settings blob.
  StreamSubscription<NightshadeEvent>? _settingsEventSub;

  /// `correlatingCommandId`s of POSTs this notifier itself originated.
  /// Used to drop our own echoes so a local write doesn't fight the
  /// in-flight UI by overwriting state with the value we just sent.
  /// Bounded at 64 entries — far more than any realistic in-flight
  /// burst, but cheap to keep.
  final List<String> _ownCommandIds = <String>[];

  AppSettingsState _fromRemoteSettings(models.AppSettings remote) {
    final location = remote.location;
    return AppSettingsState(
      autoConnectEquipment: remote.autoConnect,
      autoDiscoverOnLaunch: remote.autoDiscoverOnLaunch,
      theme: remote.theme,
      language: remote.language,
      accentColor: remote.accentColor.isEmpty
          ? kDefaultAccentColorHex
          : remote.accentColor,
      fontSize: remote.fontSize,
      uiScale: remote.uiScale,
      latitude: location?.latitude ?? remote.latitude,
      longitude: location?.longitude ?? remote.longitude,
      elevation: location?.elevation ?? remote.elevation,
      fileNamingPattern: remote.fileNamingPattern.isEmpty
          ? r'$TARGET_$FILTER_$DATE_$SEQ'
          : remote.fileNamingPattern,
      meridianFlipMinutes: remote.meridianFlipMinutes,
      autoFocusEveryMinutes: remote.autoFocusEveryMinutes,
      ditherEveryFrames: remote.ditherEveryFrames,
      plateSolveTimeout: remote.plateSolveTimeout,
      plateSolveSearchRadius: remote.plateSolveSearchRadius,
      discordWebhook: remote.discordWebhook,
      pushoverKey: remote.pushoverKey,
      pushoverUser: remote.pushoverUser,
      astapPath: remote.astapPath,
      indiServerHost: remote.indiServerHost,
      indiServerPort: remote.indiServerPort,
      indiAutoConnect: remote.indiAutoConnect,
      alpacaServerHost: remote.alpacaServerHost,
      alpacaServerPort: remote.alpacaServerPort,
      alpacaAutoDiscover: remote.alpacaAutoDiscover,
      useNativeExecution: remote.useNativeExecution,
      useSimulationMode: remote.useSimulationMode,
      imageOutputPath: remote.imageOutputPath,
      safetyFailMode: remote.safetyFailMode,
    );
  }

  models.AppSettings _toRemoteSettings(AppSettingsState settings) {
    final previous = _remoteSettingsSnapshot;
    return models.AppSettings(
      location: models.ObserverLocation(
        latitude: settings.latitude,
        longitude: settings.longitude,
        elevation: settings.elevation,
      ),
      theme: settings.theme,
      language: settings.language,
      autoConnect: settings.autoConnectEquipment,
      latitude: settings.latitude,
      longitude: settings.longitude,
      elevation: settings.elevation,
      fileNamingPattern: settings.fileNamingPattern,
      meridianFlipMinutes: settings.meridianFlipMinutes,
      autoFocusEveryMinutes: settings.autoFocusEveryMinutes,
      ditherEveryFrames: settings.ditherEveryFrames,
      plateSolveTimeout: settings.plateSolveTimeout,
      plateSolveSearchRadius: settings.plateSolveSearchRadius,
      discordWebhook: settings.discordWebhook,
      pushoverKey: settings.pushoverKey,
      pushoverUser: settings.pushoverUser,
      astapPath: settings.astapPath,
      autoDiscoverOnLaunch: settings.autoDiscoverOnLaunch,
      accentColor: settings.accentColor,
      fontSize: settings.fontSize,
      uiScale: settings.uiScale,
      indiServerHost: settings.indiServerHost,
      indiServerPort: settings.indiServerPort,
      indiAutoConnect: settings.indiAutoConnect,
      alpacaServerHost: settings.alpacaServerHost,
      alpacaServerPort: settings.alpacaServerPort,
      alpacaAutoDiscover: settings.alpacaAutoDiscover,
      useNativeExecution: settings.useNativeExecution,
      useSimulationMode: settings.useSimulationMode,
      imageOutputPath: settings.imageOutputPath,
      observer: previous?.observer ?? '',
      telescope: previous?.telescope ?? '',
      instrument: previous?.instrument ?? '',
      updateCheckEnabled: previous?.updateCheckEnabled ?? true,
      updateServerUrl: previous?.updateServerUrl ?? '',
      updateChannel: previous?.updateChannel ?? 'stable',
      updateCheckIntervalHours: previous?.updateCheckIntervalHours ?? 24,
      skippedUpdateVersion: previous?.skippedUpdateVersion ?? '',
      safetyFailMode: settings.safetyFailMode,
    );
  }

  Future<void> _writeRemoteSettings(AppSettingsState settings) async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      throw StateError(
          'Remote settings write requested without network backend');
    }

    final remote = _toRemoteSettings(settings);
    // [Wave 6B settings sync] generate a command id, register it in the
    // local echo-suppression list, and forward to the host. The host
    // stamps `correlatingCommandId` on every `settings.changed` event
    // emitted from this POST; our event handler drops events whose id
    // matches so we don't fight ourselves.
    final commandId = _generateLocalCommandId();
    _registerOwnCommandId(commandId);
    await backend.updateSettingsWithCommandId(remote, commandId: commandId);
    _remoteSettingsSnapshot = remote;
  }

  /// Bounded FIFO insertion so the echo-suppression list doesn't grow
  /// without bound if the server is offline / dropping events.
  void _registerOwnCommandId(String id) {
    if (_ownCommandIds.length >= 64) {
      _ownCommandIds.removeAt(0);
    }
    _ownCommandIds.add(id);
  }

  /// Cheap, opaque command id generator. We deliberately don't pull
  /// `package:uuid` for one call site — a `timestamp-random` pair is
  /// collision-resistant enough for echo-suppression (the id only has
  /// to be unique among an individual client's recent in-flight
  /// writes).
  static int _commandIdCounter = 0;
  static String _generateLocalCommandId() {
    _commandIdCounter += 1;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'settings-${ts.toRadixString(36)}-$_commandIdCounter';
  }

  /// [Wave 6B settings sync] Apply a single `settings.changed` event by
  /// merging its `{key, value}` into the current state. Returns silently
  /// when the event is malformed, the state is not yet loaded, or the
  /// originating command id matches one we wrote ourselves.
  void _applySettingsChangedEvent(NightshadeEvent event) {
    if (event.eventType != settingsChangedEventType) return;

    // Origin filter: drop our own echo so we don't churn the UI.
    final originId = event.correlatingCommandId;
    if (originId != null && _ownCommandIds.remove(originId)) {
      return;
    }

    final current = state.valueOrNull;
    if (current == null) {
      // The build() future is still resolving; the subsequent fetch
      // will include the new value, so skipping is correct.
      return;
    }

    final key = event.data['key'];
    if (key is! String || key.isEmpty) return;

    // Full-snapshot variant emitted when the host couldn't read the
    // previous settings (first-write / recovery path).
    if (key == '__snapshot__') {
      final snapshot = event.data['value'];
      if (snapshot is Map<String, dynamic>) {
        try {
          final remote = models.AppSettings.fromJson(snapshot);
          _remoteSettingsSnapshot = remote;
          state = AsyncData(_fromRemoteSettings(remote));
        } catch (e, st) {
          developer.log(
            'settings.changed snapshot parse failed: $e\n$st',
            name: 'AppSettingsNotifier',
            level: 900,
          );
        }
      }
      return;
    }

    final value = event.data['value'];
    // Merge into the cached remote snapshot so future diffs are
    // accurate; the snapshot mirrors what the host has on disk.
    final snapshot = _remoteSettingsSnapshot;
    if (snapshot != null) {
      final updatedRemoteJson =
          Map<String, dynamic>.from(snapshot.toJson())..[key] = value;
      try {
        _remoteSettingsSnapshot =
            models.AppSettings.fromJson(updatedRemoteJson);
      } catch (e) {
        // Schema mismatch (e.g. forward-incompat key from a newer host).
        // Keep the previous snapshot to preserve diff integrity.
        developer.log(
          'settings.changed snapshot merge skipped for key=$key: $e',
          name: 'AppSettingsNotifier',
          level: 900,
        );
      }
    }

    final merged = _applyJsonSettingChange(current, key, value);
    if (merged != null && merged != current) {
      state = AsyncData(merged);
    }
  }

  /// Translate a single JSON-shaped `(key, value)` from the server into
  /// a copyWith on the in-memory [AppSettingsState]. Unknown keys are a
  /// no-op (a newer host may carry settings this build does not yet
  /// know about — silent skipping preserves forward-compatibility).
  ///
  /// Returns null when the value parses to something the current state
  /// already has — caller checks for that to avoid pointless rebuilds.
  AppSettingsState? _applyJsonSettingChange(
    AppSettingsState current,
    String key,
    dynamic value,
  ) {
    // The keys mirror `models.AppSettings.toJson()` — which is the freezed
    // JSON projection — NOT the database column names. The settings provider
    // already has `_applySettingsMap` for the db-column form; here we only
    // need to handle the remote-JSON form for the keys that round-trip.
    switch (key) {
      case 'theme':
        return value is String ? current.copyWith(theme: value) : null;
      case 'language':
        return value is String ? current.copyWith(language: value) : null;
      case 'autoConnect':
        return value is bool
            ? current.copyWith(autoConnectEquipment: value)
            : null;
      case 'autoDiscoverOnLaunch':
        return value is bool
            ? current.copyWith(autoDiscoverOnLaunch: value)
            : null;
      case 'latitude':
        return value is num
            ? current.copyWith(latitude: value.toDouble())
            : null;
      case 'longitude':
        return value is num
            ? current.copyWith(longitude: value.toDouble())
            : null;
      case 'elevation':
        return value is num
            ? current.copyWith(elevation: value.toDouble())
            : null;
      case 'fileNamingPattern':
        return value is String
            ? current.copyWith(fileNamingPattern: value)
            : null;
      case 'meridianFlipMinutes':
        return value is num
            ? current.copyWith(meridianFlipMinutes: value.toInt())
            : null;
      case 'autoFocusEveryMinutes':
        return value is num
            ? current.copyWith(autoFocusEveryMinutes: value.toInt())
            : null;
      case 'ditherEveryFrames':
        return value is num
            ? current.copyWith(ditherEveryFrames: value.toInt())
            : null;
      case 'plateSolveTimeout':
        return value is num
            ? current.copyWith(plateSolveTimeout: value.toInt())
            : null;
      case 'plateSolveSearchRadius':
        return value is num
            ? current.copyWith(plateSolveSearchRadius: value.toDouble())
            : null;
      case 'accentColor':
        return value is String
            ? current.copyWith(accentColor: value)
            : null;
      case 'fontSize':
        return value is String ? current.copyWith(fontSize: value) : null;
      case 'uiScale':
        return value is String ? current.copyWith(uiScale: value) : null;
      case 'discordWebhook':
        return value is String
            ? current.copyWith(discordWebhook: value)
            : null;
      case 'pushoverKey':
        return value is String
            ? current.copyWith(pushoverKey: value)
            : null;
      case 'pushoverUser':
        return value is String
            ? current.copyWith(pushoverUser: value)
            : null;
      case 'astapPath':
        return value is String ? current.copyWith(astapPath: value) : null;
      case 'indiServerHost':
        return value is String
            ? current.copyWith(indiServerHost: value)
            : null;
      case 'indiServerPort':
        return value is num
            ? current.copyWith(indiServerPort: value.toInt())
            : null;
      case 'indiAutoConnect':
        return value is bool
            ? current.copyWith(indiAutoConnect: value)
            : null;
      case 'alpacaServerHost':
        return value is String
            ? current.copyWith(alpacaServerHost: value)
            : null;
      case 'alpacaServerPort':
        return value is num
            ? current.copyWith(alpacaServerPort: value.toInt())
            : null;
      case 'alpacaAutoDiscover':
        return value is bool
            ? current.copyWith(alpacaAutoDiscover: value)
            : null;
      case 'useNativeExecution':
        return value is bool
            ? current.copyWith(useNativeExecution: value)
            : null;
      case 'useSimulationMode':
        return value is bool
            ? current.copyWith(useSimulationMode: value)
            : null;
      case 'imageOutputPath':
        return value is String
            ? current.copyWith(imageOutputPath: value)
            : null;
      case 'safetyFailMode':
        if (value is String) {
          return current.copyWith(
            safetyFailMode: _parseSafetyFailMode(value),
          );
        }
        return null;
      default:
        // Forward-compat: a newer host may emit settings this build
        // does not yet have a copyWith for. The persisted snapshot
        // captures the value (above) so a subsequent rebuild still
        // sees it via `_fromRemoteSettings`.
        return null;
    }
  }

  @override
  Future<AppSettingsState> build() async {
    final backend = ref.watch(backendProvider);

    // [Wave 6B settings sync] tear down any previous subscription before
    // re-binding for the freshly-read backend. `build()` is called every
    // time the backend changes (FFI → Network → Disconnected etc.) and
    // each variant needs its own subscription policy. The cancel() future
    // is fire-and-forget; we only care that the listener stops dispatching.
    unawaited(_settingsEventSub?.cancel());
    _settingsEventSub = null;

    if (backend is NetworkBackend) {
      // Subscribe BEFORE the GET so an event that lands between the
      // POST acknowledgment and the GET's response can be re-applied
      // when the future resolves.
      _settingsEventSub = backend.eventStream.listen(
        (event) {
          if (event.category != EventCategory.system) return;
          if (event.eventType != settingsChangedEventType) return;
          _applySettingsChangedEvent(event);
        },
        onError: (Object error) {
          developer.log(
            'settings.changed stream error: $error',
            name: 'AppSettingsNotifier',
            level: 1000,
            error: error,
          );
        },
      );
      ref.onDispose(() {
        _settingsEventSub?.cancel();
        _settingsEventSub = null;
      });

      try {
        final remoteSettings = await backend.getSettings();
        _remoteSettingsSnapshot = remoteSettings;
        return _fromRemoteSettings(remoteSettings);
      } catch (e, stackTrace) {
        // Why: mobile clients pair with control scope; settings reads must
        // not tear down the session if the host rejects or omits a field.
        developer.log(
          'Remote settings fetch failed; using defaults until host responds: $e\n$stackTrace',
          name: 'AppSettingsNotifier',
          level: 900,
        );
        return const AppSettingsState();
      }
    }

    _remoteSettingsSnapshot = null;
    final dao = ref.read(settingsDaoProvider);
    final allSettings = await dao.getAllSettings();

    return AppSettingsState(
      // General
      startMinimized: _parseBool(allSettings['start_minimized'], false),
      autoConnectEquipment:
          _parseBool(allSettings['auto_connect_equipment'], true),
      autoSaveSequences: _parseBool(allSettings['auto_save_sequences'], true),
      confirmBeforeClosing:
          _parseBool(allSettings['confirm_before_closing'], true),
      autoDiscoverOnLaunch:
          _parseBool(allSettings['auto_discover_on_launch'], true),

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
      parkOnUnsafeWeather:
          _parseBool(allSettings['park_on_unsafe_weather'], true),
      parkBeforeDawn: _parseBool(allSettings['park_before_dawn'], true),
      meridianFlipMinutes: _parseInt(allSettings['meridian_flip_minutes'], 5),
      autoFocusOnFilterChange:
          _parseBool(allSettings['auto_focus_on_filter_change'], true),
      useFilterFocusOffsets:
          _parseBool(allSettings['use_filter_focus_offsets'], true),
      autoFocusEveryMinutes:
          _parseInt(allSettings['auto_focus_every_minutes'], 60),
      ditherEnabled: _parseBool(allSettings['dither_enabled'], true),
      ditherEveryFrames: _parseInt(allSettings['dither_every_frames'], 3),
      safetyFailMode: _parseSafetyFailMode(allSettings['safety_fail_mode']),

      // Plate Solving
      plateSolver: allSettings['plate_solver'] ?? 'ASTAP',
      astapPath: allSettings['astap_path'] ?? '',
      astrometryPath: allSettings['astrometry_path'] ?? '',
      plateSolveTimeout: _parseInt(allSettings['plate_solve_timeout'], 60),
      plateSolveSearchRadius:
          _parseDouble(allSettings['plate_solve_search_radius'], 30.0),
      blindSolve: _parseBool(allSettings['blind_solve'], false),

      // PHD2 Guiding
      phd2Path: allSettings['phd2_path'] ?? '',
      phd2Host: allSettings['phd2_host'] ?? 'localhost',
      phd2Port: _parseInt(allSettings['phd2_port'], 4400),

      // Notifications
      notificationsEnabled:
          _parseBool(allSettings['notifications_enabled'], true),
      discordWebhook: allSettings['discord_webhook'] ?? '',
      pushoverKey: allSettings['pushover_key'] ?? '',
      pushoverUser: allSettings['pushover_user'] ?? '',
      notifyOnSequenceComplete:
          _parseBool(allSettings['notify_on_sequence_complete'], true),
      notifyOnError: _parseBool(allSettings['notify_on_error'], true),
      notifyOnMeridianFlip:
          _parseBool(allSettings['notify_on_meridian_flip'], false),
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
      alpacaAutoDiscover:
          _parseBool(allSettings['alpaca_auto_discover'], false),

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
      horizonProfileJson: allSettings['horizon_profile_json'] ??
          '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}',
      effectiveHorizonDeg:
          _parseDouble(allSettings['effective_horizon_deg'], 0.0),
      audibleAlertsOnCritical:
          _parseBool(allSettings['audible_alerts_on_critical'], false),
      renderingPlatform:
          RenderingPlatform.parseStored(allSettings['rendering_platform']),
      criticalAlertSound:
          _normaliseCriticalAlertSound(allSettings['critical_alert_sound']),
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
      afInitialOffsetSteps:
          _parseInt(allSettings['af_initial_offset_steps'], 4),
      afNumberOfAttempts: _parseInt(allSettings['af_number_of_attempts'], 1),
      afUseBrightestNStars:
          _parseInt(allSettings['af_use_brightest_n_stars'], 0),
      afOuterCropRatio: _parseDouble(allSettings['af_outer_crop_ratio'], 1.0),
      afInnerCropRatio: _parseDouble(allSettings['af_inner_crop_ratio'], 0.0),
      afBinning: _parseInt(allSettings['af_binning'], 1),
      afRSquaredThreshold:
          _parseDouble(allSettings['af_r_squared_threshold'], 0.7),
      afDisableGuidingDuringAf:
          _parseBool(allSettings['af_disable_guiding'], false),
      afFocuserSettleTimeMs:
          _parseInt(allSettings['af_focuser_settle_time_ms'], 500),
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
          allSettings['adaptive_exposure_per_filter_enabled']),
      adaptiveExposurePerFilterMinSecs: _parseFilterDoubleMap(
          allSettings['adaptive_exposure_per_filter_min_secs']),
      adaptiveExposurePerFilterMaxSecs: _parseFilterDoubleMap(
          allSettings['adaptive_exposure_per_filter_max_secs']),

      // Wave 5 Agent 3 — Pre-flight checks. Values are clamped to defend
      // against pathological persisted values (zero / negative days, zero
      // coverage quorum). The drift threshold has no upper bound — a user
      // who wants the optical-train check silenced can crank it sky-high.
      preflightStrictness:
          _parsePreflightStrictness(allSettings['preflight_strictness']),
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

  int? _parseOptionalInt(
    String? value, {
    required int? defaultIfMissing,
  }) {
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

  Future<void> _saveSetting(String key, String value) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, {key: value});
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(key, value);
  }

  Future<void> _saveSettings(Map<String, String> settings) async {
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final current = state.valueOrNull;
      if (current == null) {
        throw StateError('Settings are not loaded yet');
      }
      final updated = _applySettingsMap(current, settings);
      await _writeRemoteSettings(updated);
      return;
    }
    final dao = ref.read(settingsDaoProvider);
    await dao.setSettings(settings);
  }

  AppSettingsState _applySettingsMap(
    AppSettingsState current,
    Map<String, String> settings,
  ) {
    return current.copyWith(
      startMinimized: settings.containsKey('start_minimized')
          ? _parseBool(settings['start_minimized'], current.startMinimized)
          : null,
      autoConnectEquipment: settings.containsKey('auto_connect_equipment')
          ? _parseBool(
              settings['auto_connect_equipment'],
              current.autoConnectEquipment,
            )
          : null,
      autoSaveSequences: settings.containsKey('auto_save_sequences')
          ? _parseBool(
              settings['auto_save_sequences'],
              current.autoSaveSequences,
            )
          : null,
      confirmBeforeClosing: settings.containsKey('confirm_before_closing')
          ? _parseBool(
              settings['confirm_before_closing'],
              current.confirmBeforeClosing,
            )
          : null,
      autoDiscoverOnLaunch: settings.containsKey('auto_discover_on_launch')
          ? _parseBool(
              settings['auto_discover_on_launch'],
              current.autoDiscoverOnLaunch,
            )
          : null,
      theme: settings['theme'],
      language: settings['language'],
      accentColor: settings['accent_color'],
      fontSize: settings['font_size'],
      sidebarCollapsed: settings.containsKey('sidebar_collapsed')
          ? _parseBool(settings['sidebar_collapsed'], current.sidebarCollapsed)
          : null,
      latitude: settings.containsKey('observer_latitude')
          ? _parseDouble(settings['observer_latitude'], current.latitude)
          : null,
      longitude: settings.containsKey('observer_longitude')
          ? _parseDouble(settings['observer_longitude'], current.longitude)
          : null,
      elevation: settings.containsKey('observer_elevation')
          ? _parseDouble(settings['observer_elevation'], current.elevation)
          : null,
      timezone: settings['timezone'],
      useSystemTime: settings.containsKey('use_system_time')
          ? _parseBool(settings['use_system_time'], current.useSystemTime)
          : null,
      imageFormat: settings['image_format'],
      fileNamingPattern: settings['file_naming_pattern'],
      bitDepth: settings['bit_depth'],
      parkOnUnsafeWeather: settings.containsKey('park_on_unsafe_weather')
          ? _parseBool(
              settings['park_on_unsafe_weather'],
              current.parkOnUnsafeWeather,
            )
          : null,
      parkBeforeDawn: settings.containsKey('park_before_dawn')
          ? _parseBool(settings['park_before_dawn'], current.parkBeforeDawn)
          : null,
      meridianFlipMinutes: settings.containsKey('meridian_flip_minutes')
          ? _parseInt(
              settings['meridian_flip_minutes'],
              current.meridianFlipMinutes,
            )
          : null,
      autoFocusOnFilterChange:
          settings.containsKey('auto_focus_on_filter_change')
              ? _parseBool(
                  settings['auto_focus_on_filter_change'],
                  current.autoFocusOnFilterChange,
                )
              : null,
      useFilterFocusOffsets: settings.containsKey('use_filter_focus_offsets')
          ? _parseBool(
              settings['use_filter_focus_offsets'],
              current.useFilterFocusOffsets,
            )
          : null,
      autoFocusEveryMinutes: settings.containsKey('auto_focus_every_minutes')
          ? _parseInt(
              settings['auto_focus_every_minutes'],
              current.autoFocusEveryMinutes,
            )
          : null,
      ditherEnabled: settings.containsKey('dither_enabled')
          ? _parseBool(settings['dither_enabled'], current.ditherEnabled)
          : null,
      ditherEveryFrames: settings.containsKey('dither_every_frames')
          ? _parseInt(
              settings['dither_every_frames'],
              current.ditherEveryFrames,
            )
          : null,
      safetyFailMode: settings.containsKey('safety_fail_mode')
          ? _parseSafetyFailMode(settings['safety_fail_mode'])
          : null,
      plateSolver: settings['plate_solver'],
      astapPath: settings['astap_path'],
      astrometryPath: settings['astrometry_path'],
      plateSolveTimeout: settings.containsKey('plate_solve_timeout')
          ? _parseInt(
              settings['plate_solve_timeout'],
              current.plateSolveTimeout,
            )
          : null,
      plateSolveSearchRadius: settings.containsKey('plate_solve_search_radius')
          ? _parseDouble(
              settings['plate_solve_search_radius'],
              current.plateSolveSearchRadius,
            )
          : null,
      blindSolve: settings.containsKey('blind_solve')
          ? _parseBool(settings['blind_solve'], current.blindSolve)
          : null,
      phd2Path: settings['phd2_path'],
      phd2Host: settings['phd2_host'],
      phd2Port: settings.containsKey('phd2_port')
          ? _parseInt(settings['phd2_port'], current.phd2Port)
          : null,
      notificationsEnabled: settings.containsKey('notifications_enabled')
          ? _parseBool(
              settings['notifications_enabled'],
              current.notificationsEnabled,
            )
          : null,
      discordWebhook: settings['discord_webhook'],
      pushoverKey: settings['pushover_key'],
      pushoverUser: settings['pushover_user'],
      notifyOnSequenceComplete:
          settings.containsKey('notify_on_sequence_complete')
              ? _parseBool(
                  settings['notify_on_sequence_complete'],
                  current.notifyOnSequenceComplete,
                )
              : null,
      notifyOnError: settings.containsKey('notify_on_error')
          ? _parseBool(settings['notify_on_error'], current.notifyOnError)
          : null,
      notifyOnMeridianFlip: settings.containsKey('notify_on_meridian_flip')
          ? _parseBool(
              settings['notify_on_meridian_flip'],
              current.notifyOnMeridianFlip,
            )
          : null,
      soundEnabled: settings.containsKey('sound_enabled')
          ? _parseBool(settings['sound_enabled'], current.soundEnabled)
          : null,
      imageOutputPath: settings['image_output_path'],
      sequencesPath: settings['sequences_path'],
      databasePath: settings['database_path'],
      logsPath: settings['logs_path'],
      indiServerHost: settings['indi_server_host'],
      indiServerPort: settings.containsKey('indi_server_port')
          ? _parseInt(settings['indi_server_port'], current.indiServerPort)
          : null,
      indiAutoConnect: settings.containsKey('indi_auto_connect')
          ? _parseBool(settings['indi_auto_connect'], current.indiAutoConnect)
          : null,
      alpacaServerHost: settings['alpaca_server_host'],
      alpacaServerPort: settings.containsKey('alpaca_server_port')
          ? _parseInt(settings['alpaca_server_port'], current.alpacaServerPort)
          : null,
      alpacaAutoDiscover: settings.containsKey('alpaca_auto_discover')
          ? _parseBool(
              settings['alpaca_auto_discover'],
              current.alpacaAutoDiscover,
            )
          : null,
      useNativeExecution: settings.containsKey('use_native_execution')
          ? _parseBool(
              settings['use_native_execution'],
              current.useNativeExecution,
            )
          : null,
      useSimulationMode: settings.containsKey('use_simulation_mode')
          ? _parseBool(
              settings['use_simulation_mode'],
              current.useSimulationMode,
            )
          : null,
      webServerEnabled: settings.containsKey('web_server_enabled')
          ? _parseBool(settings['web_server_enabled'], current.webServerEnabled)
          : null,
      webServerPort: settings.containsKey('web_server_port')
          ? _parseInt(settings['web_server_port'], current.webServerPort)
          : null,
      coolingBehavior: settings['cooling_behavior'],
      defaultGain: settings.containsKey('default_gain')
          ? _parseInt(settings['default_gain'], current.defaultGain)
          : null,
      defaultOffset: settings.containsKey('default_offset')
          ? _parseInt(settings['default_offset'], current.defaultOffset)
          : null,
      enableMeridianFlip: settings.containsKey('enable_meridian_flip')
          ? _parseBool(
              settings['enable_meridian_flip'],
              current.enableMeridianFlip,
            )
          : null,
      tempCompensation: settings.containsKey('temp_compensation')
          ? _parseBool(
              settings['temp_compensation'],
              current.tempCompensation,
            )
          : null,
      tempCoefficient: settings.containsKey('temp_coefficient')
          ? _parseDouble(
              settings['temp_coefficient'],
              current.tempCoefficient,
            )
          : null,
      backlashCompensation: settings.containsKey('backlash_compensation')
          ? _parseInt(
              settings['backlash_compensation'],
              current.backlashCompensation,
            )
          : null,
      ditherScale: settings['dither_scale'],
      settleThreshold: settings.containsKey('settle_threshold')
          ? _parseDouble(settings['settle_threshold'], current.settleThreshold)
          : null,
      settleTimeout: settings.containsKey('settle_timeout')
          ? _parseInt(settings['settle_timeout'], current.settleTimeout)
          : null,
      bortleClass: settings.containsKey('bortle_class')
          ? _parseInt(settings['bortle_class'], current.bortleClass)
          : null,
      horizonProfileJson: settings['horizon_profile_json'],
      effectiveHorizonDeg: settings.containsKey('effective_horizon_deg')
          ? _parseDouble(
              settings['effective_horizon_deg'],
              current.effectiveHorizonDeg,
            )
          : null,
      audibleAlertsOnCritical:
          settings.containsKey('audible_alerts_on_critical')
              ? _parseBool(
                  settings['audible_alerts_on_critical'],
                  current.audibleAlertsOnCritical,
                )
              : null,
      criticalAlertSound: settings.containsKey('critical_alert_sound')
          ? _normaliseCriticalAlertSound(settings['critical_alert_sound'])
          : null,
      pushCriticalAlerts: settings.containsKey('push_critical_alerts')
          ? _parseBool(
              settings['push_critical_alerts'],
              current.pushCriticalAlerts,
            )
          : null,
      renderingPlatform: settings.containsKey('rendering_platform')
          ? RenderingPlatform.parseStored(settings['rendering_platform'])
          : null,
      // Wave 4 Recovery Mode — partial-update path. Each key is only
      // honoured if present in the patch, mirroring the rest of this
      // helper.
      recoveryDefaultRetryIntervalMins:
          settings.containsKey('recovery_default_retry_interval_mins')
              ? _parseDouble(
                  settings['recovery_default_retry_interval_mins'],
                  current.recoveryDefaultRetryIntervalMins,
                )
              : null,
      recoveryDefaultMaxDurationMins:
          settings.containsKey('recovery_default_max_duration_mins')
              ? _parseDouble(
                  settings['recovery_default_max_duration_mins'],
                  current.recoveryDefaultMaxDurationMins,
                )
              : null,
      recoveryStopTrackingDuringRecovery:
          settings.containsKey('recovery_stop_tracking_during_recovery')
              ? _parseBool(
                  settings['recovery_stop_tracking_during_recovery'],
                  current.recoveryStopTrackingDuringRecovery,
                )
              : null,
      recoveryAbortOnMeridian:
          settings.containsKey('recovery_abort_on_meridian')
              ? _parseBool(
                  settings['recovery_abort_on_meridian'],
                  current.recoveryAbortOnMeridian,
                )
              : null,
      recoveryAudibleAlertWhenEntered:
          settings.containsKey('recovery_audible_alert_when_entered')
              ? _parseBool(
                  settings['recovery_audible_alert_when_entered'],
                  current.recoveryAudibleAlertWhenEntered,
                )
              : null,
      afMethod: settings['af_method'],
      afCurveFitting: settings['af_curve_fitting'],
      afStepSize: settings.containsKey('af_step_size')
          ? _parseInt(settings['af_step_size'], current.afStepSize)
          : null,
      afExposureTime: settings.containsKey('af_exposure_time')
          ? _parseDouble(settings['af_exposure_time'], current.afExposureTime)
          : null,
      afInitialOffsetSteps: settings.containsKey('af_initial_offset_steps')
          ? _parseInt(
              settings['af_initial_offset_steps'],
              current.afInitialOffsetSteps,
            )
          : null,
      afNumberOfAttempts: settings.containsKey('af_number_of_attempts')
          ? _parseInt(
              settings['af_number_of_attempts'],
              current.afNumberOfAttempts,
            )
          : null,
      afUseBrightestNStars: settings.containsKey('af_use_brightest_n_stars')
          ? _parseInt(
              settings['af_use_brightest_n_stars'],
              current.afUseBrightestNStars,
            )
          : null,
      afOuterCropRatio: settings.containsKey('af_outer_crop_ratio')
          ? _parseDouble(
              settings['af_outer_crop_ratio'],
              current.afOuterCropRatio,
            )
          : null,
      afInnerCropRatio: settings.containsKey('af_inner_crop_ratio')
          ? _parseDouble(
              settings['af_inner_crop_ratio'],
              current.afInnerCropRatio,
            )
          : null,
      afBinning: settings.containsKey('af_binning')
          ? _parseInt(settings['af_binning'], current.afBinning)
          : null,
      afRSquaredThreshold: settings.containsKey('af_r_squared_threshold')
          ? _parseDouble(
              settings['af_r_squared_threshold'],
              current.afRSquaredThreshold,
            )
          : null,
      afDisableGuidingDuringAf:
          settings.containsKey('af_disable_guiding_during_af')
              ? _parseBool(
                  settings['af_disable_guiding_during_af'],
                  current.afDisableGuidingDuringAf,
                )
              : null,
      afFocuserSettleTimeMs: settings.containsKey('af_focuser_settle_time_ms')
          ? _parseInt(
              settings['af_focuser_settle_time_ms'],
              current.afFocuserSettleTimeMs,
            )
          : null,
      afExposuresPerPoint: settings.containsKey('af_exposures_per_point')
          ? _parseInt(
              settings['af_exposures_per_point'],
              current.afExposuresPerPoint,
            )
          : null,
      afBacklashCompMethod: settings['af_backlash_comp_method'],
      afBacklashIn: settings.containsKey('af_backlash_in')
          ? _parseInt(settings['af_backlash_in'], current.afBacklashIn)
          : null,
      afBacklashOut: settings.containsKey('af_backlash_out')
          ? _parseInt(settings['af_backlash_out'], current.afBacklashOut)
          : null,
      afAutofocusFilterName: settings['af_autofocus_filter_name'],
      afFilterSettingsJson: settings['af_filter_settings'],
      // Pack G — observer name (FITS OBSERVER).
      observerName: settings['observer_name'],
      // Pack G — Wave 3 Image Grading. Nullable double / int fields use
      // the `_unset` sentinel for "no change"; an explicit "null" string
      // clears the field.
      enableImageGrading: settings.containsKey('image_grading_enabled')
          ? _parseBool(
              settings['image_grading_enabled'],
              current.enableImageGrading,
            )
          : null,
      imageGradingHfrThresholdPx:
          settings.containsKey('image_grading_hfr_threshold_px')
              ? _parseNullableDouble(
                  settings['image_grading_hfr_threshold_px'],
                  current.imageGradingHfrThresholdPx,
                )
              : _unset,
      imageGradingHfrBaselinePercent:
          settings.containsKey('image_grading_hfr_baseline_percent')
              ? _parseNullableDouble(
                  settings['image_grading_hfr_baseline_percent'],
                  current.imageGradingHfrBaselinePercent,
                )
              : _unset,
      imageGradingEccentricityThreshold:
          settings.containsKey('image_grading_eccentricity_threshold')
              ? _parseNullableDouble(
                  settings['image_grading_eccentricity_threshold'],
                  current.imageGradingEccentricityThreshold,
                )
              : _unset,
      imageGradingStarCountMin:
          settings.containsKey('image_grading_star_count_min')
              ? _parseNullableInt(
                  settings['image_grading_star_count_min'],
                  current.imageGradingStarCountMin,
                )
              : _unset,
      imageGradingMaxConsecutiveRejects:
          settings.containsKey('image_grading_max_consecutive_rejects')
              ? _parseInt(
                  settings['image_grading_max_consecutive_rejects'],
                  current.imageGradingMaxConsecutiveRejects,
                )
              : null,
      imageGradingRejectFolderPath:
          settings.containsKey('image_grading_reject_folder_path')
              ? (settings['image_grading_reject_folder_path']?.isEmpty ?? true
                  ? null
                  : settings['image_grading_reject_folder_path'])
              : _unset,
      // Wave 5 Agent 3 — Pre-flight partial-update wire-up.
      preflightStrictness: settings.containsKey('preflight_strictness')
          ? _parsePreflightStrictness(settings['preflight_strictness'])
          : null,
      polarAlignmentMaxAgeDays:
          settings.containsKey('polar_alignment_max_age_days')
              ? _parseInt(
                  settings['polar_alignment_max_age_days'],
                  current.polarAlignmentMaxAgeDays,
                )
              : null,
      darkLibraryMinCoverage: settings.containsKey('dark_library_min_coverage')
          ? _parseInt(
              settings['dark_library_min_coverage'],
              current.darkLibraryMinCoverage,
            )
          : null,
      opticalTrainDriftThreshold:
          settings.containsKey('optical_train_drift_threshold')
              ? _parseDouble(
                  settings['optical_train_drift_threshold'],
                  current.opticalTrainDriftThreshold,
                )
              : null,
      // Wave 6 Agent 1 — Smart Night partial-update wiring. The nullable
      // session-hours knob uses the `_unset` sentinel so a patch can
      // either leave it alone (omit the key) or clear it back to
      // "use full dark window" (pass the literal string "null").
      smartNightMaxSessionHours:
          settings.containsKey('smart_night_max_session_hours')
              ? _parseNullableDouble(
                  settings['smart_night_max_session_hours'],
                  current.smartNightMaxSessionHours,
                )
              : _unset,
      smartNightDefaultAfCadenceFrames:
          settings.containsKey('smart_night_default_af_cadence_frames')
              ? _parseInt(
                  settings['smart_night_default_af_cadence_frames'],
                  current.smartNightDefaultAfCadenceFrames,
                )
              : null,
      smartNightDefaultIntegrationBudgetMinsPerTarget: settings.containsKey(
              'smart_night_default_integration_budget_mins_per_target')
          ? _parseInt(
              settings[
                  'smart_night_default_integration_budget_mins_per_target'],
              current.smartNightDefaultIntegrationBudgetMinsPerTarget,
            )
          : null,
      smartNightIncludeFlatsAtEnd:
          settings.containsKey('smart_night_include_flats_at_end')
              ? _parseBool(
                  settings['smart_night_include_flats_at_end'],
                  current.smartNightIncludeFlatsAtEnd,
                )
              : null,
      smartNightUseSchedulerForMultiTarget:
          settings.containsKey('smart_night_use_scheduler_for_multi_target')
              ? _parseBool(
                  settings['smart_night_use_scheduler_for_multi_target'],
                  current.smartNightUseSchedulerForMultiTarget,
                )
              : null,
      smartNightSchedulerTargetThreshold:
          settings.containsKey('smart_night_scheduler_target_threshold')
              ? _parseInt(
                  settings['smart_night_scheduler_target_threshold'],
                  current.smartNightSchedulerTargetThreshold,
                )
              : null,
      smartNightDefaultStrategy: settings['smart_night_default_strategy'],
      smartNightPolarAlignmentStaleAfterDays:
          settings.containsKey('smart_night_polar_alignment_stale_after_days')
              ? _parseInt(
                  settings['smart_night_polar_alignment_stale_after_days'],
                  current.smartNightPolarAlignmentStaleAfterDays,
                )
              : null,
      // Wave 6 Agent 5 — Notes prompt opt-out.
      smartNightSubExposureFloorSecs:
          settings.containsKey('smart_night_sub_exposure_floor_secs')
              ? _parseDouble(
                  settings['smart_night_sub_exposure_floor_secs'],
                  current.smartNightSubExposureFloorSecs,
                )
              : null,
      smartNightSubExposureCeilingSecs:
          settings.containsKey('smart_night_sub_exposure_ceiling_secs')
              ? _parseDouble(
                  settings['smart_night_sub_exposure_ceiling_secs'],
                  current.smartNightSubExposureCeilingSecs,
                )
              : null,
      smartNightTargetSnr: settings.containsKey('smart_night_target_snr')
          ? _parseDouble(
              settings['smart_night_target_snr'],
              current.smartNightTargetSnr,
            )
          : null,
      smartNightAutoPromptEnabled:
          settings.containsKey('smart_night.auto_prompt_enabled')
              ? _parseBool(
                  settings['smart_night.auto_prompt_enabled'],
                  current.smartNightAutoPromptEnabled,
                )
              : null,
      promptForNotesAfterRun: settings.containsKey('notes.prompt_after_run')
          ? _parseBool(
              settings['notes.prompt_after_run'],
              current.promptForNotesAfterRun,
            )
          : null,
      // Wave 7 — Session lifecycle. Each key gates the field so a
      // partial patch can update one knob without resetting the others.
      sessionHandoffAutoPrompt:
          settings.containsKey('session.handoff_auto_prompt')
              ? _parseBool(
                  settings['session.handoff_auto_prompt'],
                  current.sessionHandoffAutoPrompt,
                )
              : null,
      campaignRollupSurfaceTargetsTab:
          settings.containsKey('campaign_rollup.surface_targets_tab')
              ? _parseBool(
                  settings['campaign_rollup.surface_targets_tab'],
                  current.campaignRollupSurfaceTargetsTab,
                )
              : null,
      campaignRollupGroupingMode:
          settings.containsKey('campaign_rollup.grouping_mode')
              ? _parseCampaignGroupingMode(
                  settings['campaign_rollup.grouping_mode'])
              : null,
    );
  }

  /// Pack G — string -> nullable double for the grading settings.
  /// Empty / "null" string => null (the user cleared the field); a parse
  /// failure falls back to the prior value to avoid silently zeroing a
  /// threshold.
  double? _parseNullableDouble(String? value, double? previous) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return double.tryParse(value) ?? previous;
  }

  int? _parseNullableInt(String? value, int? previous) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return int.tryParse(value) ?? previous;
  }

  /// Helper to update a single field in the current AppSettingsState.
  ///
  /// If the state hasn't loaded yet (no value), the update is silently skipped
  /// because there's nothing to patch. The database write has already succeeded,
  /// so the next full load will pick up the new value.
  void _patchState(
      AppSettingsState Function(AppSettingsState current) updater) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(updater(current));
  }

  // ========== General Settings ==========

  Future<void> setStartMinimized(bool value) async {
    await _saveSetting('start_minimized', value.toString());
    _patchState((s) => s.copyWith(startMinimized: value));
  }

  Future<void> setAutoConnectEquipment(bool value) async {
    await _saveSetting('auto_connect_equipment', value.toString());
    _patchState((s) => s.copyWith(autoConnectEquipment: value));
  }

  Future<void> setAutoSaveSequences(bool value) async {
    await _saveSetting('auto_save_sequences', value.toString());
    _patchState((s) => s.copyWith(autoSaveSequences: value));
  }

  Future<void> setConfirmBeforeClosing(bool value) async {
    await _saveSetting('confirm_before_closing', value.toString());
    _patchState((s) => s.copyWith(confirmBeforeClosing: value));
  }

  Future<void> setAutoDiscoverOnLaunch(bool value) async {
    await _saveSetting('auto_discover_on_launch', value.toString());
    _patchState((s) => s.copyWith(autoDiscoverOnLaunch: value));
  }

  // ========== Development Settings ==========

  // ========== Appearance Settings ==========

  Future<void> setTheme(String value) async {
    await _saveSetting('theme', value);
    _patchState((s) => s.copyWith(theme: value));
  }

  Future<void> setLanguage(String value) async {
    await _saveSetting('language', value);
    _patchState((s) => s.copyWith(language: value));
  }

  Future<void> setAccentColor(String value) async {
    await _saveSetting('accent_color', value);
    _patchState((s) => s.copyWith(accentColor: value));
  }

  Future<void> setFontSize(String value) async {
    await _saveSetting('font_size', value);
    _patchState((s) => s.copyWith(fontSize: value));
  }

  Future<void> setUiScale(String value) async {
    await _saveSetting('ui_scale', value);
    _patchState((s) => s.copyWith(uiScale: value));
  }

  Future<void> setSidebarCollapsed(bool value) async {
    await _saveSetting('sidebar_collapsed', value.toString());
    _patchState((s) => s.copyWith(sidebarCollapsed: value));
  }

  // ========== Location Settings ==========

  Future<void> setLatitude(double value) async {
    await _saveSetting('observer_latitude', value.toString());
    _patchState((s) => s.copyWith(latitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setLongitude(double value) async {
    await _saveSetting('observer_longitude', value.toString());
    _patchState((s) => s.copyWith(longitude: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setElevation(double value) async {
    await _saveSetting('observer_elevation', value.toString());
    _patchState((s) => s.copyWith(elevation: value));
    // Sync to planetarium provider is handled at app level in settings screen
  }

  Future<void> setTimezone(String value) async {
    await _saveSetting('timezone', value);
    _patchState((s) => s.copyWith(timezone: value));
  }

  Future<void> setUseSystemTime(bool value) async {
    await _saveSetting('use_system_time', value.toString());
    _patchState((s) => s.copyWith(useSystemTime: value));
  }

  Future<void> updateLocation({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    final settings = <String, String>{};
    if (latitude != null) settings['observer_latitude'] = latitude.toString();
    if (longitude != null) {
      settings['observer_longitude'] = longitude.toString();
    }
    if (elevation != null) {
      settings['observer_elevation'] = elevation.toString();
    }

    if (settings.isNotEmpty) {
      await _saveSettings(settings);
      _patchState((s) => s.copyWith(
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
          ));
    }
  }

  // ========== Observing Environment Settings ==========

  Future<void> setBortleClass(int value) async {
    final clamped = value.clamp(1, 9);
    await _saveSetting('bortle_class', clamped.toString());
    _patchState((s) => s.copyWith(bortleClass: clamped));
  }

  Future<void> setHorizonProfileJson(String value) async {
    await _saveSetting('horizon_profile_json', value);
    _patchState((s) => s.copyWith(horizonProfileJson: value));
  }

  /// Set the effective horizon used by Run Dashboard, scheduler, and
  /// planetarium for time-to-set calculations. Clamped to [0, 60] degrees
  /// because anything above 60° makes most of the sky unreachable and is
  /// almost certainly a typo rather than an intentional value.
  Future<void> setEffectiveHorizonDeg(double value) async {
    final clamped = value.clamp(0.0, 60.0);
    await _saveSetting('effective_horizon_deg', clamped.toString());
    _patchState((s) => s.copyWith(effectiveHorizonDeg: clamped));
  }

  Future<void> setAudibleAlertsOnCritical(bool value) async {
    await _saveSetting('audible_alerts_on_critical', value.toString());
    _patchState((s) => s.copyWith(audibleAlertsOnCritical: value));
  }

  /// Select planetarium rendering stack (v1 legacy or v2 Rust+wgpu).
  Future<void> setRenderingPlatform(RenderingPlatform value) async {
    await _saveSetting('rendering_platform', value.storageValue);
    _patchState((s) => s.copyWith(renderingPlatform: value));
  }

  /// Set which sound the audible-alert path uses. Unknown values are
  /// rejected (we don't want a misspelled string silently muting alerts).
  Future<void> setCriticalAlertSound(String value) async {
    if (value != 'systemBell' && value != 'none') {
      throw ArgumentError(
          'criticalAlertSound must be "systemBell" or "none", got: $value');
    }
    await _saveSetting('critical_alert_sound', value);
    _patchState((s) => s.copyWith(criticalAlertSound: value));
  }

  /// Toggle whether critical events are forwarded to paired mobile clients.
  Future<void> setPushCriticalAlerts(bool value) async {
    await _saveSetting('push_critical_alerts', value.toString());
    _patchState((s) => s.copyWith(pushCriticalAlerts: value));
  }

  // ========== Wave 4 Recovery Mode Settings ==========

  /// Minutes between auto-retry attempts during a recovery loop. Clamped
  /// to [1, 240] — a zero/negative interval would spin the executor at
  /// 100 % CPU, and a 4 h interval is already absurdly conservative.
  Future<void> setRecoveryDefaultRetryIntervalMins(double value) async {
    final clamped = value.clamp(1.0, 240.0);
    await _saveSetting(
        'recovery_default_retry_interval_mins', clamped.toString());
    _patchState((s) => s.copyWith(recoveryDefaultRetryIntervalMins: clamped));
  }

  /// Total minutes before the recovery loop gives up. Clamped to
  /// [1, 1440] (one full day) for the same reason as the retry interval.
  Future<void> setRecoveryDefaultMaxDurationMins(double value) async {
    final clamped = value.clamp(1.0, 1440.0);
    await _saveSetting(
        'recovery_default_max_duration_mins', clamped.toString());
    _patchState((s) => s.copyWith(recoveryDefaultMaxDurationMins: clamped));
  }

  /// Whether the mount should stop tracking on recovery entry. Defaults
  /// to true because most recoverable failures benefit from a stationary
  /// rig (guide-star loss, dew, weather, drift).
  Future<void> setRecoveryStopTrackingDuringRecovery(bool value) async {
    await _saveSetting(
        'recovery_stop_tracking_during_recovery', value.toString());
    _patchState((s) => s.copyWith(recoveryStopTrackingDuringRecovery: value));
  }

  /// Whether an imminent meridian crossing inside the recovery window
  /// aborts the loop instead of trying to retry across the flip.
  Future<void> setRecoveryAbortOnMeridian(bool value) async {
    await _saveSetting('recovery_abort_on_meridian', value.toString());
    _patchState((s) => s.copyWith(recoveryAbortOnMeridian: value));
  }

  /// Whether to ring the platform alert sound on recovery entry. Re-uses
  /// the audibleAlertsOnCritical sound selection.
  Future<void> setRecoveryAudibleAlertWhenEntered(bool value) async {
    await _saveSetting('recovery_audible_alert_when_entered', value.toString());
    _patchState((s) => s.copyWith(recoveryAudibleAlertWhenEntered: value));
  }

  // ========== Pack G — Observer / Equipment Identification ==========

  /// Observer name stamped into FITS `OBSERVER`. Empty string => keyword
  /// omitted entirely (silent fallbacks are bugs).
  Future<void> setObserverName(String value) async {
    await _saveSetting('observer_name', value);
    _patchState((s) => s.copyWith(observerName: value));
  }

  // ========== Pack G — Image Grading Settings ==========

  /// Master switch: when false, live frame Pass/Reject grading is disabled
  /// at the executor level. Per-node `quality_check` on TakeExposure
  /// nodes still wins; this only toggles the *default*.
  Future<void> setEnableImageGrading(bool value) async {
    await _saveSetting('image_grading_enabled', value.toString());
    _patchState((s) => s.copyWith(enableImageGrading: value));
  }

  /// Reject if HFR exceeds this absolute pixel value. Pass `null` to
  /// disable the check while keeping other grading enabled.
  Future<void> setImageGradingHfrThreshold(double? value) async {
    await _saveSetting(
      'image_grading_hfr_threshold_px',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingHfrThresholdPx: value));
  }

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. Pass `null`
  /// to disable.
  Future<void> setImageGradingHfrBaselinePercent(double? value) async {
    await _saveSetting(
      'image_grading_hfr_baseline_percent',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingHfrBaselinePercent: value));
  }

  /// Reject if star eccentricity exceeds this value. Typical thresholds:
  /// 0.6 catches trailed frames; 0.8 catches catastrophic tracking
  /// failure. Pass `null` to disable.
  Future<void> setImageGradingEccentricityThreshold(double? value) async {
    await _saveSetting(
      'image_grading_eccentricity_threshold',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingEccentricityThreshold: value));
  }

  /// Reject if star count drops below this value. Pass `null` to disable.
  Future<void> setImageGradingStarCountMin(int? value) async {
    await _saveSetting(
      'image_grading_star_count_min',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingStarCountMin: value));
  }

  /// Pause the sequence after this many consecutive rejects. Required;
  /// the strategic-report default is 3. Clamped to >= 1 so the safety
  /// valve is always active.
  Future<void> setImageGradingMaxConsecutiveRejects(int value) async {
    final clamped = value < 1 ? 1 : value;
    await _saveSetting(
      'image_grading_max_consecutive_rejects',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingMaxConsecutiveRejects: clamped));
  }

  /// Override for the reject folder. `null` or empty => use the default
  /// `<save_path>/Reject/`. Relative paths resolve against the run
  /// save_path; absolute paths are honoured verbatim.
  Future<void> setImageGradingRejectFolderPath(String? value) async {
    final normalised = (value == null || value.trim().isEmpty) ? null : value;
    await _saveSetting(
      'image_grading_reject_folder_path',
      normalised ?? '',
    );
    _patchState((s) => s.copyWith(imageGradingRejectFolderPath: normalised));
  }

  // ========== Wave 5 Agent 2 — Sky-Brightness Adaptive Exposure ==========

  /// Master switch for the global default sky-brightness adaptive
  /// exposure. Off => the executor's runtime default is cleared and
  /// only per-node `ExposureNode.adaptiveExposure` overrides apply.
  Future<void> setAdaptiveExposureEnabled(bool value) async {
    await _saveSetting('adaptive_exposure_enabled', value.toString());
    _patchState((s) => s.copyWith(adaptiveExposureEnabled: value));
  }

  /// Target SNR for the adaptive scaling (informational; the live
  /// math uses background flux ratio, not a direct SNR solver).
  Future<void> setAdaptiveExposureTargetSnr(double value) async {
    final clamped = value < 1.0 ? 1.0 : value;
    await _saveSetting('adaptive_exposure_target_snr', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureTargetSnr: clamped));
  }

  /// Reference sky brightness in mag/arcsec² that the nominal duration
  /// was calibrated for. Bigger = darker; a dark site is 21.5+, an
  /// urban backyard is 18-19.
  Future<void> setAdaptiveExposureReferenceMag(double value) async {
    // Sky brightness physically lives in [14, 23] mag/arcsec²; clamp
    // defensively but allow the user to type anything in that band.
    final clamped = value.clamp(14.0, 24.0);
    await _saveSetting(
      'adaptive_exposure_reference_mag',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(adaptiveExposureReferenceMag: clamped));
  }

  /// Global minimum exposure clamp in seconds.
  Future<void> setAdaptiveExposureMinSecs(double value) async {
    final clamped = value < 0.001 ? 0.001 : value;
    await _saveSetting('adaptive_exposure_min_secs', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureMinSecs: clamped));
  }

  /// Global maximum exposure clamp in seconds.
  Future<void> setAdaptiveExposureMaxSecs(double value) async {
    final clamped = value < 0.001 ? 0.001 : value;
    await _saveSetting('adaptive_exposure_max_secs', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureMaxSecs: clamped));
  }

  /// Per-filter enable map. JSON-serialised for storage.
  Future<void> setAdaptiveExposurePerFilterEnabled(
      Map<String, bool> map) async {
    await _saveSetting(
      'adaptive_exposure_per_filter_enabled',
      jsonEncode(map),
    );
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterEnabled: map));
  }

  /// Per-filter minimum exposure clamp map (seconds).
  Future<void> setAdaptiveExposurePerFilterMinSecs(
      Map<String, double> map) async {
    await _saveSetting(
      'adaptive_exposure_per_filter_min_secs',
      jsonEncode(map),
    );
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterMinSecs: map));
  }

  /// Per-filter maximum exposure clamp map (seconds).
  Future<void> setAdaptiveExposurePerFilterMaxSecs(
      Map<String, double> map) async {
    await _saveSetting(
      'adaptive_exposure_per_filter_max_secs',
      jsonEncode(map),
    );
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterMaxSecs: map));
  }

  // ========== Wave 5 Agent 3 — Pre-flight Strictness Settings ==========

  /// Pre-flight strictness mode. See [PreflightStrictness] for what each
  /// value implies for rule severities.
  Future<void> setPreflightStrictness(PreflightStrictness value) async {
    await _saveSetting('preflight_strictness', value.persistedName);
    _patchState((s) => s.copyWith(preflightStrictness: value));
  }

  /// Maximum age in days for the last polar alignment before pre-flight
  /// considers it stale. Clamped to [1, 365].
  Future<void> setPolarAlignmentMaxAgeDays(int value) async {
    final clamped = value.clamp(1, 365);
    await _saveSetting('polar_alignment_max_age_days', clamped.toString());
    _patchState((s) => s.copyWith(polarAlignmentMaxAgeDays: clamped));
  }

  /// Minimum coverage (number of dark frames) before a (gain, offset,
  /// temp, duration, binning) combination is considered "well covered".
  /// Clamped to [1, 1000].
  Future<void> setDarkLibraryMinCoverage(int value) async {
    final clamped = value.clamp(1, 1000);
    await _saveSetting('dark_library_min_coverage', clamped.toString());
    _patchState((s) => s.copyWith(darkLibraryMinCoverage: clamped));
  }

  /// Threshold for the optical-train pre-flight drift comparison. Clamped
  /// to [0.1, 1000.0]. Larger values silence the check; smaller values
  /// surface every minor reshuffle.
  Future<void> setOpticalTrainDriftThreshold(double value) async {
    final clamped = value.clamp(0.1, 1000.0);
    await _saveSetting('optical_train_drift_threshold', clamped.toString());
    _patchState((s) => s.copyWith(opticalTrainDriftThreshold: clamped));
  }

  // ========== Wave 6 Agent 1 — Smart Night Defaults ==========

  /// Maximum session wall-clock duration (hours) the Smart Night wizard
  /// uses to cap the planning window. Pass `null` to clear back to "use
  /// the full dark window".
  Future<void> setSmartNightMaxSessionHours(double? value) async {
    final clamped = value?.clamp(1.0, 14.0);
    await _saveSetting(
      'smart_night_max_session_hours',
      clamped == null ? 'null' : clamped.toString(),
    );
    _patchState((s) => s.copyWith(smartNightMaxSessionHours: clamped));
  }

  /// Default autofocus cadence (frames). Clamped to [1, 9999] for the
  /// same reasons as the standard autofocus interval knob.
  Future<void> setSmartNightDefaultAfCadenceFrames(int value) async {
    final clamped = value.clamp(1, 9999);
    await _saveSetting(
      'smart_night_default_af_cadence_frames',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(smartNightDefaultAfCadenceFrames: clamped));
  }

  /// Default integration budget per target (minutes). Clamped to one
  /// full day at the upper end — anyone asking for >24 h per target is
  /// either testing limits or mis-entering hours as minutes.
  Future<void> setSmartNightDefaultIntegrationBudgetMinsPerTarget(
      int value) async {
    final clamped = value.clamp(1, 24 * 60);
    await _saveSetting(
      'smart_night_default_integration_budget_mins_per_target',
      clamped.toString(),
    );
    _patchState((s) =>
        s.copyWith(smartNightDefaultIntegrationBudgetMinsPerTarget: clamped));
  }

  /// Whether the wizard appends end-of-session flats when the active
  /// profile has a cover calibrator.
  Future<void> setSmartNightIncludeFlatsAtEnd(bool value) async {
    await _saveSetting(
      'smart_night_include_flats_at_end',
      value.toString(),
    );
    _patchState((s) => s.copyWith(smartNightIncludeFlatsAtEnd: value));
  }

  /// Whether the wizard wraps multi-target plans in a TargetSchedulerNode.
  Future<void> setSmartNightUseSchedulerForMultiTarget(bool value) async {
    await _saveSetting(
      'smart_night_use_scheduler_for_multi_target',
      value.toString(),
    );
    _patchState((s) => s.copyWith(smartNightUseSchedulerForMultiTarget: value));
  }

  /// Minimum target count before the wizard auto-picks scheduler mode.
  /// Clamped to [2, 20] — below 2 the toggle is meaningless, above 20
  /// no one is running that many targets in one night.
  Future<void> setSmartNightSchedulerTargetThreshold(int value) async {
    final clamped = value.clamp(2, 20);
    await _saveSetting(
      'smart_night_scheduler_target_threshold',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(smartNightSchedulerTargetThreshold: clamped));
  }

  /// Default Smart Night strategy. Values are the snake_case strategy
  /// names (`auto_lrgb`, `mono_lrgb`, `narrowband_hoo`, `narrowband_sho`,
  /// `osc_one_shot`); the wizard maps them back to [SmartNightStrategy]
  /// enum values.
  Future<void> setSmartNightDefaultStrategy(String value) async {
    const allowed = {
      'auto_lrgb',
      'mono_lrgb',
      'narrowband_hoo',
      'narrowband_sho',
      'osc_one_shot',
    };
    if (!allowed.contains(value)) {
      throw ArgumentError(
          'smartNightDefaultStrategy must be one of $allowed, got: $value');
    }
    await _saveSetting('smart_night_default_strategy', value);
    _patchState((s) => s.copyWith(smartNightDefaultStrategy: value));
  }

  /// Days after which a polar alignment is "stale" enough for the Smart
  /// Night wizard to prepend an alignment node. Clamped to [1, 365].
  Future<void> setSmartNightPolarAlignmentStaleAfterDays(int value) async {
    final clamped = value.clamp(1, 365);
    await _saveSetting(
      'smart_night_polar_alignment_stale_after_days',
      clamped.toString(),
    );
    _patchState(
        (s) => s.copyWith(smartNightPolarAlignmentStaleAfterDays: clamped));
  }

  // ========== Wave 6 Agent 5 — Notes Prompt Toggle ==========

  /// Whether the auto-prompt note dialog appears after a sequence run
  /// completes. Stored under the same `notes.prompt_after_run` key the
  /// NotesService reads via [promptForNotesAfterRunProvider], so the
  /// two paths stay in sync.
  /// Smart Night sub-exposure floor in seconds. Clamped to [1, 3600].
  Future<void> setSmartNightSubExposureFloorSecs(double value) async {
    final clamped = value.clamp(1.0, 3600.0);
    await _saveSetting(
      'smart_night_sub_exposure_floor_secs',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(smartNightSubExposureFloorSecs: clamped));
  }

  /// Smart Night sub-exposure ceiling in seconds. Clamped to [1, 7200].
  Future<void> setSmartNightSubExposureCeilingSecs(double value) async {
    final clamped = value.clamp(1.0, 7200.0);
    await _saveSetting(
      'smart_night_sub_exposure_ceiling_secs',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(smartNightSubExposureCeilingSecs: clamped));
  }

  /// Smart Night exposure-planning SNR target. Clamped to [1, 500].
  Future<void> setSmartNightTargetSnr(double value) async {
    final clamped = value.clamp(1.0, 500.0);
    await _saveSetting('smart_night_target_snr', clamped.toString());
    _patchState((s) => s.copyWith(smartNightTargetSnr: clamped));
  }

  /// Whether the dashboard Smart Night auto-prompt may appear. This does
  /// not disable the manual Plan Tonight buttons.
  Future<void> setSmartNightAutoPromptEnabled(bool value) async {
    await _saveSetting('smart_night.auto_prompt_enabled', value.toString());
    _patchState((s) => s.copyWith(smartNightAutoPromptEnabled: value));
  }

  Future<void> setPromptForNotesAfterRun(bool value) async {
    await _saveSetting('notes.prompt_after_run', value.toString());
    _patchState((s) => s.copyWith(promptForNotesAfterRun: value));
  }

  // ========== Wave 7 — Session lifecycle ==========

  /// Whether the multi-night carry-over banner auto-opens at pre-flight
  /// when an unfinished session is detected for one of the sequence's
  /// targets. Consumed by `sessionHandoffAutoPromptProvider` and the
  /// preflight widget.
  Future<void> setSessionHandoffAutoPrompt(bool value) async {
    await _saveSetting('session.handoff_auto_prompt', value.toString());
    _patchState((s) => s.copyWith(sessionHandoffAutoPrompt: value));
  }

  /// Whether the Targets tab surfaces the per-target campaign rollup
  /// column. Consumed by the targets-tab widget.
  Future<void> setCampaignRollupSurfaceTargetsTab(bool value) async {
    await _saveSetting('campaign_rollup.surface_targets_tab', value.toString());
    _patchState((s) => s.copyWith(campaignRollupSurfaceTargetsTab: value));
  }

  /// Campaign grouping mode (`by_target_name`, `by_target_id`,
  /// `by_user_tag`). Unknown values fall back to `by_target_name`.
  Future<void> setCampaignRollupGroupingMode(String value) async {
    const allowed = ['by_target_name', 'by_target_id', 'by_user_tag'];
    final clamped = allowed.contains(value) ? value : 'by_target_name';
    await _saveSetting('campaign_rollup.grouping_mode', clamped);
    _patchState((s) => s.copyWith(campaignRollupGroupingMode: clamped));
  }

  // ========== Wave 8 — Adaptive sky-conditions defaults ==========

  /// Toggle whether brand-new [TargetSchedulerNode]s ship with adaptive
  /// swap enabled (`swapOnConditionsBelow` set to the default threshold).
  /// Existing nodes are NOT mutated by this setting — see
  /// [TargetSchedulerNode.swapOnConditionsBelow] for the per-node knob.
  Future<void> setAdaptiveSwapEnabledByDefault(bool value) async {
    await _saveSetting('adaptive_swap.enabled_by_default', value.toString());
    _patchState((s) => s.copyWith(adaptiveSwapEnabledByDefault: value));
  }

  /// Default conditions-score floor (0..=100) seeded into a new
  /// scheduler when [adaptiveSwapEnabledByDefault] is true.
  Future<void> setAdaptiveSwapDefaultThreshold(double value) async {
    final clamped = value.clamp(0.0, 100.0);
    await _saveSetting(
      'adaptive_swap.default_threshold',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(adaptiveSwapDefaultThreshold: clamped));
  }

  /// Default `swapHysteresisSecs` (seconds between consecutive swaps)
  /// seeded into a new scheduler.
  Future<void> setAdaptiveSwapDefaultHysteresisSecs(double value) async {
    final clamped = value.clamp(0.0, 3600.0);
    await _saveSetting(
      'adaptive_swap.default_hysteresis_secs',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(adaptiveSwapDefaultHysteresisSecs: clamped));
  }

  /// Per-axis composer weights for the live ConditionsScore. The map is
  /// JSON-encoded under `adaptive_swap.score_weights`. Unknown keys are
  /// stripped at parse time; missing axes fall back to the defaults.
  /// The caller is responsible for normalising the weights to sum to
  /// ~1.0 if they want a "pure" 0..=100 score — but the composer
  /// renormalises over the available axes so a non-normalised map still
  /// produces sane scores.
  Future<void> setConditionsScoreWeights(Map<String, double> weights) async {
    // Sanitise — drop unknown keys, clamp negatives to 0, keep positives
    // as-is so the user can experiment with weight bands > 1 if they
    // want to test the composer's renormalisation.
    const known = {'transparency', 'seeing', 'cloud', 'wind'};
    final sanitised = <String, double>{
      for (final entry in weights.entries)
        if (known.contains(entry.key) && entry.value.isFinite)
          entry.key: entry.value < 0 ? 0.0 : entry.value,
    };
    await _saveSetting(
      'adaptive_swap.score_weights',
      jsonEncode(sanitised),
    );
    _patchState((s) => s.copyWith(conditionsScoreWeights: sanitised));
  }

  // ========== Imaging Settings ==========

  Future<void> setImageFormat(String value) async {
    await _saveSetting('image_format', value);
    _patchState((s) => s.copyWith(imageFormat: value));
  }

  Future<void> setFileNamingPattern(String value) async {
    await _saveSetting('file_naming_pattern', value);
    _patchState((s) => s.copyWith(fileNamingPattern: value));
  }

  Future<void> setBitDepth(String value) async {
    await _saveSetting('bit_depth', value);
    _patchState((s) => s.copyWith(bitDepth: value));
  }

  // ========== Sequencer Settings ==========

  Future<void> setParkOnUnsafeWeather(bool value) async {
    await _saveSetting('park_on_unsafe_weather', value.toString());
    _patchState((s) => s.copyWith(parkOnUnsafeWeather: value));
  }

  Future<void> setParkBeforeDawn(bool value) async {
    await _saveSetting('park_before_dawn', value.toString());
    _patchState((s) => s.copyWith(parkBeforeDawn: value));
  }

  Future<void> setSafetyFailMode(SafetyFailMode value) async {
    await _saveSetting('safety_fail_mode', value.name);
    _patchState((s) => s.copyWith(safetyFailMode: value));
  }

  Future<void> setMeridianFlipMinutes(int value) async {
    await _saveSetting('meridian_flip_minutes', value.toString());
    _patchState((s) => s.copyWith(meridianFlipMinutes: value));
  }

  Future<void> setAutoFocusOnFilterChange(bool value) async {
    await _saveSetting('auto_focus_on_filter_change', value.toString());
    _patchState((s) => s.copyWith(autoFocusOnFilterChange: value));
  }

  Future<void> setUseFilterFocusOffsets(bool value) async {
    await _saveSetting('use_filter_focus_offsets', value.toString());
    _patchState((s) => s.copyWith(useFilterFocusOffsets: value));
  }

  Future<void> setAutoFocusEveryMinutes(int value) async {
    await _saveSetting('auto_focus_every_minutes', value.toString());
    _patchState((s) => s.copyWith(autoFocusEveryMinutes: value));
  }

  Future<void> setDitherEnabled(bool value) async {
    await _saveSetting('dither_enabled', value.toString());
    _patchState((s) => s.copyWith(ditherEnabled: value));
  }

  Future<void> setDitherEveryFrames(int value) async {
    await _saveSetting('dither_every_frames', value.toString());
    _patchState((s) => s.copyWith(ditherEveryFrames: value));
  }

  Future<void> setUseNativeExecution(bool value) async {
    await _saveSetting('use_native_execution', value.toString());
    _patchState((s) => s.copyWith(useNativeExecution: value));
  }

  Future<void> setUseSimulationMode(bool value) async {
    await _saveSetting('use_simulation_mode', value.toString());
    _patchState((s) => s.copyWith(useSimulationMode: value));
  }

  // ========== Remote Access / Web Server Settings ==========

  Future<void> setWebServerEnabled(bool value) async {
    await _saveSetting('web_server_enabled', value.toString());
    _patchState((s) => s.copyWith(webServerEnabled: value));
  }

  Future<void> setWebServerPort(int value) async {
    await _saveSetting('web_server_port', value.toString());
    _patchState((s) => s.copyWith(webServerPort: value));
  }

  // ========== Plate Solving Settings ==========

  Future<void> setPlateSolver(String value) async {
    await _saveSetting('plate_solver', value);
    _patchState((s) => s.copyWith(plateSolver: value));
  }

  Future<void> setAstapPath(String value) async {
    await _saveSetting('astap_path', value);
    _patchState((s) => s.copyWith(astapPath: value));
  }

  Future<void> setAstrometryPath(String value) async {
    await _saveSetting('astrometry_path', value);
    _patchState((s) => s.copyWith(astrometryPath: value));
  }

  Future<void> setPlateSolveTimeout(int value) async {
    await _saveSetting('plate_solve_timeout', value.toString());
    _patchState((s) => s.copyWith(plateSolveTimeout: value));
  }

  Future<void> setPlateSolveSearchRadius(double value) async {
    await _saveSetting('plate_solve_search_radius', value.toString());
    _patchState((s) => s.copyWith(plateSolveSearchRadius: value));
  }

  Future<void> setBlindSolve(bool value) async {
    await _saveSetting('blind_solve', value.toString());
    _patchState((s) => s.copyWith(blindSolve: value));
  }

  // ========== PHD2 Guiding Settings ==========

  Future<void> setPhd2Path(String value) async {
    await _saveSetting('phd2_path', value);
    _patchState((s) => s.copyWith(phd2Path: value));
  }

  Future<void> setPhd2Host(String value) async {
    await _saveSetting('phd2_host', value);
    _patchState((s) => s.copyWith(phd2Host: value));
  }

  Future<void> setPhd2Port(int value) async {
    await _saveSetting('phd2_port', value.toString());
    _patchState((s) => s.copyWith(phd2Port: value));
  }

  // ========== Notification Settings ==========

  Future<void> setNotificationsEnabled(bool value) async {
    await _saveSetting('notifications_enabled', value.toString());
    _patchState((s) => s.copyWith(notificationsEnabled: value));
  }

  Future<void> setDiscordWebhook(String value) async {
    await _saveSetting('discord_webhook', value);
    _patchState((s) => s.copyWith(discordWebhook: value));
  }

  Future<void> setPushoverKey(String value) async {
    await _saveSetting('pushover_key', value);
    _patchState((s) => s.copyWith(pushoverKey: value));
  }

  Future<void> setPushoverUser(String value) async {
    await _saveSetting('pushover_user', value);
    _patchState((s) => s.copyWith(pushoverUser: value));
  }

  Future<void> setNotifyOnSequenceComplete(bool value) async {
    await _saveSetting('notify_on_sequence_complete', value.toString());
    _patchState((s) => s.copyWith(notifyOnSequenceComplete: value));
  }

  Future<void> setNotifyOnError(bool value) async {
    await _saveSetting('notify_on_error', value.toString());
    _patchState((s) => s.copyWith(notifyOnError: value));
  }

  Future<void> setNotifyOnMeridianFlip(bool value) async {
    await _saveSetting('notify_on_meridian_flip', value.toString());
    _patchState((s) => s.copyWith(notifyOnMeridianFlip: value));
  }

  Future<void> setSoundEnabled(bool value) async {
    await _saveSetting('sound_enabled', value.toString());
    _patchState((s) => s.copyWith(soundEnabled: value));
  }

  // ========== File Path Settings ==========

  Future<void> setImageOutputPath(String value) async {
    await _saveSetting('image_output_path', value);
    _patchState((s) => s.copyWith(imageOutputPath: value));
  }

  Future<void> setSequencesPath(String value) async {
    await _saveSetting('sequences_path', value);
    _patchState((s) => s.copyWith(sequencesPath: value));
  }

  Future<void> setDatabasePath(String value) async {
    await _saveSetting('database_path', value);
    _patchState((s) => s.copyWith(databasePath: value));
  }

  Future<void> setLogsPath(String value) async {
    await _saveSetting('logs_path', value);
    _patchState((s) => s.copyWith(logsPath: value));
  }

  // ========== Network/Protocol Settings ==========

  Future<void> setIndiServerHost(String value) async {
    await _saveSetting('indi_server_host', value);
    _patchState((s) => s.copyWith(indiServerHost: value));
  }

  Future<void> setIndiServerPort(int value) async {
    await _saveSetting('indi_server_port', value.toString());
    _patchState((s) => s.copyWith(indiServerPort: value));
  }

  Future<void> setIndiAutoConnect(bool value) async {
    await _saveSetting('indi_auto_connect', value.toString());
    _patchState((s) => s.copyWith(indiAutoConnect: value));
  }

  Future<void> setAlpacaServerHost(String value) async {
    await _saveSetting('alpaca_server_host', value);
    _patchState((s) => s.copyWith(alpacaServerHost: value));
  }

  Future<void> setAlpacaServerPort(int value) async {
    await _saveSetting('alpaca_server_port', value.toString());
    _patchState((s) => s.copyWith(alpacaServerPort: value));
  }

  Future<void> setAlpacaAutoDiscover(bool value) async {
    await _saveSetting('alpaca_auto_discover', value.toString());
    _patchState((s) => s.copyWith(alpacaAutoDiscover: value));
  }

  // Equipment Settings - Camera
  Future<void> setCoolingBehavior(String value) async {
    await _saveSetting('cooling_behavior', value);
    _patchState((s) => s.copyWith(coolingBehavior: value));
  }

  Future<void> setDefaultGain(int value) async {
    await _saveSetting('default_gain', value.toString());
    _patchState((s) => s.copyWith(defaultGain: value));
  }

  Future<void> setDefaultOffset(int value) async {
    await _saveSetting('default_offset', value.toString());
    _patchState((s) => s.copyWith(defaultOffset: value));
  }

  // Equipment Settings - Mount
  Future<void> setEnableMeridianFlip(bool value) async {
    await _saveSetting('enable_meridian_flip', value.toString());
    _patchState((s) => s.copyWith(enableMeridianFlip: value));
  }

  // Equipment Settings - Focuser
  Future<void> setTempCompensation(bool value) async {
    await _saveSetting('temp_compensation', value.toString());
    _patchState((s) => s.copyWith(tempCompensation: value));
  }

  Future<void> setTempCoefficient(double value) async {
    await _saveSetting('temp_coefficient', value.toString());
    _patchState((s) => s.copyWith(tempCoefficient: value));
  }

  Future<void> setBacklashCompensation(int value) async {
    await _saveSetting('backlash_compensation', value.toString());
    _patchState((s) => s.copyWith(backlashCompensation: value));
  }

  // Equipment Settings - Guider
  Future<void> setDitherScale(String value) async {
    await _saveSetting('dither_scale', value);
    _patchState((s) => s.copyWith(ditherScale: value));
  }

  Future<void> setSettleThreshold(double value) async {
    await _saveSetting('settle_threshold', value.toString());
    _patchState((s) => s.copyWith(settleThreshold: value));
  }

  Future<void> setSettleTimeout(int value) async {
    await _saveSetting('settle_timeout', value.toString());
    _patchState((s) => s.copyWith(settleTimeout: value));
  }

  // ========== Autofocus Settings ==========

  Future<void> setAfMethod(String value) async {
    await _saveSetting('af_method', value);
    _patchState((s) => s.copyWith(afMethod: value));
  }

  Future<void> setAfCurveFitting(String value) async {
    await _saveSetting('af_curve_fitting', value);
    _patchState((s) => s.copyWith(afCurveFitting: value));
  }

  Future<void> setAfStepSize(int value) async {
    await _saveSetting('af_step_size', value.toString());
    _patchState((s) => s.copyWith(afStepSize: value));
  }

  Future<void> setAfExposureTime(double value) async {
    await _saveSetting('af_exposure_time', value.toString());
    _patchState((s) => s.copyWith(afExposureTime: value));
  }

  Future<void> setAfInitialOffsetSteps(int value) async {
    await _saveSetting('af_initial_offset_steps', value.toString());
    _patchState((s) => s.copyWith(afInitialOffsetSteps: value));
  }

  Future<void> setAfNumberOfAttempts(int value) async {
    await _saveSetting('af_number_of_attempts', value.toString());
    _patchState((s) => s.copyWith(afNumberOfAttempts: value));
  }

  Future<void> setAfUseBrightestNStars(int value) async {
    await _saveSetting('af_use_brightest_n_stars', value.toString());
    _patchState((s) => s.copyWith(afUseBrightestNStars: value));
  }

  Future<void> setAfOuterCropRatio(double value) async {
    await _saveSetting('af_outer_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afOuterCropRatio: value));
  }

  Future<void> setAfInnerCropRatio(double value) async {
    await _saveSetting('af_inner_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afInnerCropRatio: value));
  }

  Future<void> setAfBinning(int value) async {
    await _saveSetting('af_binning', value.toString());
    _patchState((s) => s.copyWith(afBinning: value));
  }

  Future<void> setAfRSquaredThreshold(double value) async {
    await _saveSetting('af_r_squared_threshold', value.toString());
    _patchState((s) => s.copyWith(afRSquaredThreshold: value));
  }

  Future<void> setAfDisableGuidingDuringAf(bool value) async {
    await _saveSetting('af_disable_guiding', value.toString());
    _patchState((s) => s.copyWith(afDisableGuidingDuringAf: value));
  }

  Future<void> setAfFocuserSettleTimeMs(int value) async {
    await _saveSetting('af_focuser_settle_time_ms', value.toString());
    _patchState((s) => s.copyWith(afFocuserSettleTimeMs: value));
  }

  Future<void> setAfExposuresPerPoint(int value) async {
    await _saveSetting('af_exposures_per_point', value.toString());
    _patchState((s) => s.copyWith(afExposuresPerPoint: value));
  }

  Future<void> setAfBacklashCompMethod(String value) async {
    await _saveSetting('af_backlash_comp_method', value);
    _patchState((s) => s.copyWith(afBacklashCompMethod: value));
  }

  Future<void> setAfBacklashIn(int value) async {
    await _saveSetting('af_backlash_in', value.toString());
    _patchState((s) => s.copyWith(afBacklashIn: value));
  }

  Future<void> setAfBacklashOut(int value) async {
    await _saveSetting('af_backlash_out', value.toString());
    _patchState((s) => s.copyWith(afBacklashOut: value));
  }

  Future<void> setAfAutofocusFilterName(String value) async {
    await _saveSetting('af_autofocus_filter_name', value);
    _patchState((s) => s.copyWith(afAutofocusFilterName: value));
  }

  Future<void> setAfFilterSettingsJson(String value) async {
    await _saveSetting('af_filter_settings', value);
    _patchState((s) => s.copyWith(afFilterSettingsJson: value));
  }

  /// Update a single filter's autofocus configuration.
  ///
  /// Loads the current filter settings map, updates the entry for [filterName],
  /// serializes back to JSON, and persists to the database.
  Future<void> setFilterAutofocusConfig(
      String filterName, FilterAutofocusConfig config) async {
    final currentJson = state.value?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map[filterName] = config;
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }

  /// Remove a filter's autofocus configuration.
  Future<void> removeFilterAutofocusConfig(String filterName) async {
    final currentJson = state.value?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map.remove(filterName);
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }
}

/// Main app settings provider
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettingsState>(() {
  return AppSettingsNotifier();
});

/// Effective horizon in degrees selected from [appSettingsProvider].
///
/// The same value is consumed by the Run Dashboard's "time-to-set"
/// statistic and by the planetarium target-card so both surfaces display
/// the same number to the second. Falls back to 0° (mathematical horizon)
/// before settings have loaded.
final effectiveHorizonDegProvider = Provider<double>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  return settings?.effectiveHorizonDeg ?? 0.0;
});

/// Focused observer-location selector derived from [appSettingsProvider].
///
/// Watching this provider avoids rebuilding weather/suggestion chains when
/// unrelated settings change.
final appObserverLocationProvider = Provider<LocationSettings?>((ref) {
  final location = ref.watch(
    appSettingsProvider.select(
      (settingsAsync) => settingsAsync.valueOrNull == null
          ? null
          : (
              latitude: settingsAsync.valueOrNull!.latitude,
              longitude: settingsAsync.valueOrNull!.longitude,
              elevation: settingsAsync.valueOrNull!.elevation,
            ),
    ),
  );

  if (location == null) {
    return null;
  }

  return LocationSettings(
    latitude: location.latitude,
    longitude: location.longitude,
    elevation: location.elevation,
  );
});

// ============================================================================
// Autofocus Settings Provider (convenience)
// ============================================================================

/// Convenience provider that derives a typed [AutofocusSettings] from the
/// persisted [AppSettingsState] autofocus fields.
///
/// This avoids every consumer needing to manually pluck out individual
/// `af_*` fields and parse the filter settings JSON.
final autofocusSettingsProvider = Provider<AutofocusSettings>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.valueOrNull;
  if (settings == null) {
    return const AutofocusSettings();
  }

  return AutofocusSettings(
    method: settings.afMethod,
    curveFitting: settings.afCurveFitting,
    stepSize: settings.afStepSize,
    exposureTime: settings.afExposureTime,
    initialOffsetSteps: settings.afInitialOffsetSteps,
    numberOfAttempts: settings.afNumberOfAttempts,
    useBrightestNStars: settings.afUseBrightestNStars,
    outerCropRatio: settings.afOuterCropRatio,
    innerCropRatio: settings.afInnerCropRatio,
    binning: settings.afBinning,
    rSquaredThreshold: settings.afRSquaredThreshold,
    disableGuidingDuringAf: settings.afDisableGuidingDuringAf,
    focuserSettleTimeMs: settings.afFocuserSettleTimeMs,
    exposuresPerPoint: settings.afExposuresPerPoint,
    backlashCompMethod: settings.afBacklashCompMethod,
    backlashIn: settings.afBacklashIn,
    backlashOut: settings.afBacklashOut,
    autofocusFilterName: settings.afAutofocusFilterName,
    filterSettings: AutofocusSettings.parseFilterSettingsJson(
        settings.afFilterSettingsJson),
  );
});

// ============================================================================
// Legacy Providers (for backwards compatibility)
// ============================================================================

/// Location settings for observer position
class LocationSettings {
  final double latitude;
  final double longitude;
  final double elevation;

  const LocationSettings({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.elevation = 0.0,
  });

  LocationSettings copyWith({
    double? latitude,
    double? longitude,
    double? elevation,
  }) {
    return LocationSettings(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
    );
  }
}

/// Location settings notifier that persists to database
class LocationSettingsNotifier extends AsyncNotifier<LocationSettings> {
  @override
  Future<LocationSettings> build() async {
    final dao = ref.read(settingsDaoProvider);
    final lat = await dao.getObserverLatitude();
    final lon = await dao.getObserverLongitude();
    final elev = await dao.getObserverElevation();

    return LocationSettings(
      latitude: lat,
      longitude: lon,
      elevation: elev,
    );
  }

  Future<void> updateLocation({
    double? latitude,
    double? longitude,
    double? elevation,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const LocationSettings();

    if (latitude != null) {
      await dao.setObserverLatitude(latitude);
    }
    if (longitude != null) {
      await dao.setObserverLongitude(longitude);
    }
    if (elevation != null) {
      await dao.setObserverElevation(elevation);
    }

    state = AsyncData(current.copyWith(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
    ));
  }
}

final locationSettingsProvider =
    AsyncNotifierProvider<LocationSettingsNotifier, LocationSettings>(() {
  return LocationSettingsNotifier();
});

// ============================================================================
// Output Settings
// ============================================================================

/// Imaging output settings
class OutputSettings {
  final String format; // FITS, XISF, TIFF
  final String bitDepth; // 16-bit, 32-bit
  final String savePath;
  final String filePattern;
  final bool includeTimestamp;
  final bool includeFilter;

  const OutputSettings({
    this.format = 'FITS',
    this.bitDepth = '16-bit',
    this.savePath = '',
    this.filePattern = r'$DATE_$TARGET_$FILTER_$EXPOSURE_###',
    this.includeTimestamp = true,
    this.includeFilter = true,
  });

  OutputSettings copyWith({
    String? format,
    String? bitDepth,
    String? savePath,
    String? filePattern,
    bool? includeTimestamp,
    bool? includeFilter,
  }) {
    return OutputSettings(
      format: format ?? this.format,
      bitDepth: bitDepth ?? this.bitDepth,
      savePath: savePath ?? this.savePath,
      filePattern: filePattern ?? this.filePattern,
      includeTimestamp: includeTimestamp ?? this.includeTimestamp,
      includeFilter: includeFilter ?? this.includeFilter,
    );
  }
}

/// Output settings notifier that persists to database
class OutputSettingsNotifier extends AsyncNotifier<OutputSettings> {
  @override
  Future<OutputSettings> build() async {
    final dao = ref.read(settingsDaoProvider);

    final format = await dao.getSetting('output_format') ?? 'FITS';
    final bitDepth = await dao.getSetting('output_bit_depth') ?? '16-bit';
    final savePath = await dao.getSetting('default_image_directory') ?? '';
    final filePattern = await dao.getSetting('file_pattern') ??
        r'$DATE_$TARGET_$FILTER_$EXPOSURE_###';
    final includeTimestamp =
        (await dao.getSetting('include_timestamp') ?? 'true') == 'true';
    final includeFilter =
        (await dao.getSetting('include_filter') ?? 'true') == 'true';

    return OutputSettings(
      format: format,
      bitDepth: bitDepth,
      savePath: savePath,
      filePattern: filePattern,
      includeTimestamp: includeTimestamp,
      includeFilter: includeFilter,
    );
  }

  Future<void> updateOutput({
    String? format,
    String? bitDepth,
    String? savePath,
    String? filePattern,
    bool? includeTimestamp,
    bool? includeFilter,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const OutputSettings();

    final settings = <String, String>{};
    if (format != null) settings['output_format'] = format;
    if (bitDepth != null) settings['output_bit_depth'] = bitDepth;
    if (savePath != null) settings['default_image_directory'] = savePath;
    if (filePattern != null) settings['file_pattern'] = filePattern;
    if (includeTimestamp != null) {
      settings['include_timestamp'] = includeTimestamp.toString();
    }
    if (includeFilter != null) {
      settings['include_filter'] = includeFilter.toString();
    }

    if (settings.isNotEmpty) {
      await dao.setSettings(settings);
    }

    state = AsyncData(current.copyWith(
      format: format,
      bitDepth: bitDepth,
      savePath: savePath,
      filePattern: filePattern,
      includeTimestamp: includeTimestamp,
      includeFilter: includeFilter,
    ));
  }
}

final outputSettingsProvider =
    AsyncNotifierProvider<OutputSettingsNotifier, OutputSettings>(() {
  return OutputSettingsNotifier();
});

// ============================================================================
// Plate Solve Settings
// ============================================================================

/// Plate solving settings
class PlateSolveSettings {
  final String solver; // ASTAP, Astrometry.net, PlateSolve2
  final String solverPath;
  final int timeoutSeconds;
  final bool autoSolve;
  final double searchRadius;

  const PlateSolveSettings({
    this.solver = 'ASTAP',
    this.solverPath = '',
    this.timeoutSeconds = 60,
    this.autoSolve = true,
    this.searchRadius = 30.0,
  });

  PlateSolveSettings copyWith({
    String? solver,
    String? solverPath,
    int? timeoutSeconds,
    bool? autoSolve,
    double? searchRadius,
  }) {
    return PlateSolveSettings(
      solver: solver ?? this.solver,
      solverPath: solverPath ?? this.solverPath,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoSolve: autoSolve ?? this.autoSolve,
      searchRadius: searchRadius ?? this.searchRadius,
    );
  }
}

/// Plate solve settings notifier that persists to database
class PlateSolveSettingsNotifier extends AsyncNotifier<PlateSolveSettings> {
  @override
  Future<PlateSolveSettings> build() async {
    final dao = ref.read(settingsDaoProvider);

    final solver = await dao.getSetting('plate_solve_solver') ?? 'ASTAP';
    final solverPath = await dao.getSetting('plate_solve_path') ?? '';
    final timeoutStr = await dao.getSetting('plate_solve_timeout') ?? '60';
    final autoSolve =
        (await dao.getSetting('plate_solve_auto') ?? 'true') == 'true';
    final searchRadiusStr =
        await dao.getSetting('plate_solve_radius') ?? '30.0';

    return PlateSolveSettings(
      solver: solver,
      solverPath: solverPath,
      timeoutSeconds: int.tryParse(timeoutStr) ?? 60,
      autoSolve: autoSolve,
      searchRadius: double.tryParse(searchRadiusStr) ?? 30.0,
    );
  }

  Future<void> updatePlateSolve({
    String? solver,
    String? solverPath,
    int? timeoutSeconds,
    bool? autoSolve,
    double? searchRadius,
  }) async {
    final dao = ref.read(settingsDaoProvider);
    final current = state.valueOrNull ?? const PlateSolveSettings();

    final settings = <String, String>{};
    if (solver != null) settings['plate_solve_solver'] = solver;
    if (solverPath != null) settings['plate_solve_path'] = solverPath;
    if (timeoutSeconds != null) {
      settings['plate_solve_timeout'] = timeoutSeconds.toString();
    }
    if (autoSolve != null) settings['plate_solve_auto'] = autoSolve.toString();
    if (searchRadius != null) {
      settings['plate_solve_radius'] = searchRadius.toString();
    }

    if (settings.isNotEmpty) {
      await dao.setSettings(settings);
    }

    state = AsyncData(current.copyWith(
      solver: solver,
      solverPath: solverPath,
      timeoutSeconds: timeoutSeconds,
      autoSolve: autoSolve,
      searchRadius: searchRadius,
    ));
  }
}

final plateSolveSettingsProvider =
    AsyncNotifierProvider<PlateSolveSettingsNotifier, PlateSolveSettings>(() {
  return PlateSolveSettingsNotifier();
});

// ============================================================================
// Theme Settings
// ============================================================================

/// Theme mode setting
class ThemeSettingsNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final dao = ref.read(settingsDaoProvider);
    return await dao.getTheme();
  }

  Future<void> setTheme(String theme) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setTheme(theme);
    state = AsyncData(theme);
  }
}

final themeSettingsProvider =
    AsyncNotifierProvider<ThemeSettingsNotifier, String>(() {
  return ThemeSettingsNotifier();
});

// ============================================================================
// Auto Connect Settings
// ============================================================================

/// Auto connect equipment setting
class AutoConnectSettingsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final dao = ref.read(settingsDaoProvider);
    return await dao.getAutoConnectEquipment();
  }

  Future<void> setAutoConnect(bool enabled) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setAutoConnectEquipment(enabled);
    state = AsyncData(enabled);
  }
}

final autoConnectSettingsProvider =
    AsyncNotifierProvider<AutoConnectSettingsNotifier, bool>(() {
  return AutoConnectSettingsNotifier();
});

// ============================================================================
// Horizon Profile Utilities
// ============================================================================

/// 8 compass directions for horizon profile definition
const List<String> horizonDirections = [
  'N',
  'NE',
  'E',
  'SE',
  'S',
  'SW',
  'W',
  'NW'
];

/// Azimuth angles corresponding to each compass direction
const List<double> horizonDirectionAzimuths = [
  0.0,
  45.0,
  90.0,
  135.0,
  180.0,
  225.0,
  270.0,
  315.0
];

/// Bortle scale descriptions and limiting magnitudes
class BortleScale {
  static const Map<int, String> descriptions = {
    1: 'Excellent dark-sky site',
    2: 'Typical truly dark site',
    3: 'Rural sky',
    4: 'Rural/suburban transition',
    5: 'Suburban sky',
    6: 'Bright suburban sky',
    7: 'Suburban/urban transition',
    8: 'City sky',
    9: 'Inner-city sky',
  };

  static const Map<int, double> limitingMagnitudes = {
    1: 7.6,
    2: 7.1,
    3: 6.6,
    4: 6.2,
    5: 5.9,
    6: 5.5,
    7: 5.0,
    8: 4.5,
    9: 4.0,
  };

  /// Get limiting magnitude for a Bortle class (1-9)
  static double limitingMagnitude(int bortleClass) {
    return limitingMagnitudes[bortleClass.clamp(1, 9)] ?? 5.9;
  }

  /// Get description for a Bortle class (1-9)
  static String description(int bortleClass) {
    return descriptions[bortleClass.clamp(1, 9)] ?? 'Unknown';
  }
}

/// Utility for parsing and interpolating horizon profiles.
///
/// A horizon profile is stored as a JSON map with 8 compass direction keys
/// (N, NE, E, SE, S, SW, W, NW) mapped to altitude values in degrees.
class HorizonProfile {
  final Map<String, double> _altitudes;

  HorizonProfile(this._altitudes);

  /// Parse a horizon profile from JSON string.
  factory HorizonProfile.fromJson(String json) {
    try {
      final decoded = Map<String, dynamic>.from(
        // Using dart:convert would require an import; parse manually for simple JSON
        _parseSimpleJson(json),
      );
      final altitudes = <String, double>{};
      for (final dir in horizonDirections) {
        final val = decoded[dir];
        if (val is num) {
          altitudes[dir] = val.toDouble().clamp(0.0, 89.0);
        } else {
          altitudes[dir] = 0.0;
        }
      }
      return HorizonProfile(altitudes);
    } catch (_) {
      // Return flat horizon on parse failure - this is a data error,
      // not something we should silently swallow. Log it.
      return HorizonProfile._default();
    }
  }

  factory HorizonProfile._default() {
    final altitudes = <String, double>{};
    for (final dir in horizonDirections) {
      altitudes[dir] = 0.0;
    }
    return HorizonProfile(altitudes);
  }

  /// Get the altitude at a specific compass direction
  double altitudeAt(String direction) => _altitudes[direction] ?? 0.0;

  /// Get interpolated horizon altitude at any azimuth (0-360 degrees).
  /// Uses cubic-like smooth interpolation between compass points.
  double altitudeAtAzimuth(double azimuthDeg) {
    // Normalize azimuth to 0-360
    var az = azimuthDeg % 360.0;
    if (az < 0) az += 360.0;

    // Find which two compass points we're between
    const segmentSize = 360.0 / 8.0; // 45 degrees per segment
    final segmentIndex = (az / segmentSize).floor() % 8;
    final nextIndex = (segmentIndex + 1) % 8;

    // Fraction within this segment (0.0 to 1.0)
    final fraction = (az - segmentIndex * segmentSize) / segmentSize;

    final alt1 = _altitudes[horizonDirections[segmentIndex]] ?? 0.0;
    final alt2 = _altitudes[horizonDirections[nextIndex]] ?? 0.0;

    // Smoothstep interpolation for natural-looking transitions
    final t = fraction * fraction * (3.0 - 2.0 * fraction);
    return alt1 + (alt2 - alt1) * t;
  }

  /// Check if a given altitude at a given azimuth is above the custom horizon
  bool isAboveHorizon(double altitudeDeg, double azimuthDeg) {
    return altitudeDeg >= altitudeAtAzimuth(azimuthDeg);
  }

  /// Encode back to JSON string
  String toJson() {
    final parts = <String>[];
    for (final dir in horizonDirections) {
      final val = _altitudes[dir] ?? 0.0;
      parts.add('"$dir":${val.toStringAsFixed(1)}');
    }
    return '{${parts.join(',')}}';
  }

  /// Simple JSON parser for flat string->number maps.
  /// Avoids importing dart:convert in this provider file.
  static Map<String, dynamic> _parseSimpleJson(String json) {
    final result = <String, dynamic>{};
    // Strip braces and split by comma
    var trimmed = json.trim();
    if (trimmed.startsWith('{')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('}')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.isEmpty) return result;

    for (final pair in trimmed.split(',')) {
      final colonIdx = pair.indexOf(':');
      if (colonIdx < 0) continue;
      var key = pair.substring(0, colonIdx).trim();
      final value = pair.substring(colonIdx + 1).trim();
      // Strip quotes from key
      if (key.startsWith('"') && key.endsWith('"')) {
        key = key.substring(1, key.length - 1);
      }
      final numVal = double.tryParse(value);
      if (numVal != null) {
        result[key] = numVal;
      }
    }
    return result;
  }

  /// Whether this profile is all zeros (flat horizon)
  bool get isFlat => _altitudes.values.every((v) => v == 0.0);
}

/// Focused provider for Bortle class.
final bortleClassProvider = Provider<int>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  return settingsAsync.valueOrNull?.bortleClass ?? 5;
});

/// Focused provider for parsed horizon profile.
final horizonProfileProvider = Provider<HorizonProfile>((ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final json = settingsAsync.valueOrNull?.horizonProfileJson ??
      '{"N":0,"NE":0,"E":0,"SE":0,"S":0,"SW":0,"W":0,"NW":0}';
  return HorizonProfile.fromJson(json);
});
