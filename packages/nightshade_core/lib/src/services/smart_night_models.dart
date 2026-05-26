import 'dart:math' as math;

import '../models/planning/target_suggestion.dart';
import '../models/scheduler/integration_goal.dart';
import '../models/sequence/sequence_models.dart';
import '../providers/profiles_provider.dart' show EquipmentProfileModel;
import 'dark_library_coverage_service.dart';
import 'sequence_file_service.dart';
import 'smart_night/exposure_calculator.dart';

// ---------------------------------------------------------------------------
// Public enums
// ---------------------------------------------------------------------------

/// High-level strategy for the auto-builder.
///
/// Each strategy picks per-filter sub counts + a sane filter rotation given
/// the equipment profile's available filters. The wizard exposes this as a
/// radio group on step 4.
enum SmartNightStrategy {
  /// Auto: LRGB rotation with 2x luminance weighting for galaxies / RGB
  /// reflection nebulae and falls back to whichever broadband filters are
  /// present. Treated as the default.
  autoLrgb,

  /// Narrowband bicolor — Ha + OIII. Used by emission-nebula nights on
  /// duo/quad-band rigs and for mono shooters who only own Ha + OIII.
  narrowbandHoo,

  /// Narrowband tricolor (Hubble palette) — Ha + OIII + SII. Requires all
  /// three filters in the equipment profile.
  narrowbandSho,

  /// One-shot color cameras — single light filter with no wheel rotation.
  oscOneShot,

  /// Mono LRGB — even L/R/G/B counts without luminance over-weighting.
  monoLrgb,
}

/// AF cadence policy.
///
/// Mirrors what the executor's `AutofocusOnFilterChange` /
/// `AutofocusEveryNExposures` / temp-delta gates already implement; the
/// wizard surfaces one toggle group and SmartNightService maps it to the
/// per-target sub-tree the executor understands.
enum SmartNightAfCadence {
  /// Autofocus after every N exposures.
  everyNFrames,

  /// Autofocus every N minutes of wall-clock time.
  everyNMinutes,

  /// Autofocus when ambient temperature has drifted by `tempDeltaC` since
  /// the last successful AF run.
  onTempDelta,
}

// ---------------------------------------------------------------------------
// Public model classes
// ---------------------------------------------------------------------------

/// Compact "user prefs" envelope owned by the wizard. The wizard initialises
/// it from per-profile defaults if available; otherwise from these sane
/// values. Not stored in a DB table — the wizard mutates a copy per build
/// and the resulting tree is what gets persisted to the sequence library.
class SmartNightSettings {
  /// Maximum session wall-clock duration (hours). When the dark window is
  /// longer than this, the auto-builder caps the planning window.
  final double maxSessionHours;

  /// Autofocus cadence policy.
  final SmartNightAfCadence afCadence;

  /// When [afCadence] is [SmartNightAfCadence.everyNFrames] this is the N.
  final int afEveryFrames;

  /// When [afCadence] is [SmartNightAfCadence.everyNMinutes] this is the N.
  final int afEveryMinutes;

  /// When [afCadence] is [SmartNightAfCadence.onTempDelta] this is the
  /// temperature delta (°C) above the last successful AF that triggers a
  /// new run.
  final double afTempDeltaC;

  /// Minimum integration time per target (hours). Targets that can't fit
  /// this much usable sky time inside the dark window are dropped.
  final double defaultIntegrationBudgetHours;

  /// Default per-filter sub-duration (seconds) if the exposure calculator
  /// has no opinion for a given filter (e.g. user is at default Bortle
  /// with an unknown camera).
  final Map<String, double> defaultFrameDurationSecs;

  /// Whether to append automatic flats at end-of-session when the profile
  /// has a cover calibrator.
  final bool includeFlatsAtEnd;

  /// Number of flats per filter when [includeFlatsAtEnd] is true.
  final int flatCountPerFilter;

  /// Whether to wrap multi-target sessions in a [TargetSchedulerNode]
  /// (scheduler mode) or to chain them linearly. The wizard auto-picks
  /// scheduler when target count >= [schedulerTargetThreshold].
  final bool useSchedulerForMultiTarget;
  final int schedulerTargetThreshold;

  /// Minimum altitude (deg) below which a target is considered "not usable".
  /// Drives the per-target start/end altitude triggers and the schedule
  /// window math.
  final double minAltitudeDeg;

  /// Hard ceiling on a single sub-exposure (seconds). Surfaced into the
  /// exposure calculator.
  final double subExposureCeilingSecs;

  /// Hard floor on a single sub-exposure (seconds).
  final double subExposureFloorSecs;

  /// Planning SNR target used by the Smart Night exposure calculator.
  /// 30 preserves the historical calculator behavior; higher values bias
  /// the sky-limited recommendation longer, lower values shorter.
  final double targetSnr;

  /// Settle/dither cadence for SmartExposure rotation (every N frames).
  final int ditherEveryFrames;

  /// Whether to prepend a polar alignment instruction when the equipment
  /// health service reports the rig's last polar alignment is stale.
  final bool prependPolarAlignmentIfStale;

  /// Days after which a polar alignment is "stale" enough to warrant
  /// prepending an alignment node.
  final int polarAlignmentStaleAfterDays;

  /// Whether the rig has a flat panel / cover calibrator. The wizard
  /// pre-fills this from the EquipmentProfile but the user can override.
  final bool hasCoverCalibrator;

  /// Cooling target temperature for the initial CoolCamera node. Pulled
  /// from the profile if available.
  final double coolDownTargetC;

  /// Opt-in: when true and the [SmartNightContext.missingDarkRequirements]
  /// list is non-empty, the builder appends a "Dark Library Refresh"
  /// instruction group at the end of the lights/flats tree that captures
  /// the missing dark combinations (count = [darkFramesPerRequirement]
  /// per missing combo).
  ///
  /// Defaults to `false` because the historical Smart Night design (see
  /// `docs/plans/2026-05-17-smart-night-design.md` §7.1) intentionally
  /// shipped warning-only — auto-scheduling dark capture surprises users
  /// who only wanted lights tonight. The audit (item #9) flagged this as
  /// outstanding work and we expose it behind the flag so opt-in users
  /// can refresh their dark library inline without breaking the default
  /// behavior for everyone else.
  final bool autoScheduleMissingDarks;

  /// Frames captured per missing-dark combination when
  /// [autoScheduleMissingDarks] is true. Defaults to 20 — the same
  /// quorum the dark-library wizard's "Capture missing darks" deep-link
  /// uses and the typical master-dark sample size for modern CMOS.
  final int darkFramesPerRequirement;

  const SmartNightSettings({
    this.maxSessionHours = 12.0,
    this.afCadence = SmartNightAfCadence.everyNFrames,
    this.afEveryFrames = 25,
    this.afEveryMinutes = 60,
    this.afTempDeltaC = 1.5,
    this.defaultIntegrationBudgetHours = 4.0,
    this.defaultFrameDurationSecs = const {
      'L': 120,
      'R': 180,
      'G': 180,
      'B': 180,
      'Ha': 300,
      'OIII': 300,
      'SII': 300,
      'OSC': 180,
    },
    this.includeFlatsAtEnd = true,
    this.flatCountPerFilter = 20,
    this.useSchedulerForMultiTarget = true,
    this.schedulerTargetThreshold = 3,
    this.minAltitudeDeg = 30.0,
    this.subExposureCeilingSecs = 300.0,
    this.subExposureFloorSecs = 30.0,
    this.targetSnr = 30.0,
    this.ditherEveryFrames = 3,
    this.prependPolarAlignmentIfStale = true,
    this.polarAlignmentStaleAfterDays = 7,
    this.hasCoverCalibrator = false,
    this.coolDownTargetC = -10.0,
    this.autoScheduleMissingDarks = false,
    this.darkFramesPerRequirement = 20,
  });

  SmartNightSettings copyWith({
    double? maxSessionHours,
    SmartNightAfCadence? afCadence,
    int? afEveryFrames,
    int? afEveryMinutes,
    double? afTempDeltaC,
    double? defaultIntegrationBudgetHours,
    Map<String, double>? defaultFrameDurationSecs,
    bool? includeFlatsAtEnd,
    int? flatCountPerFilter,
    bool? useSchedulerForMultiTarget,
    int? schedulerTargetThreshold,
    double? minAltitudeDeg,
    double? subExposureCeilingSecs,
    double? subExposureFloorSecs,
    double? targetSnr,
    int? ditherEveryFrames,
    bool? prependPolarAlignmentIfStale,
    int? polarAlignmentStaleAfterDays,
    bool? hasCoverCalibrator,
    double? coolDownTargetC,
    bool? autoScheduleMissingDarks,
    int? darkFramesPerRequirement,
  }) {
    return SmartNightSettings(
      maxSessionHours: maxSessionHours ?? this.maxSessionHours,
      afCadence: afCadence ?? this.afCadence,
      afEveryFrames: afEveryFrames ?? this.afEveryFrames,
      afEveryMinutes: afEveryMinutes ?? this.afEveryMinutes,
      afTempDeltaC: afTempDeltaC ?? this.afTempDeltaC,
      defaultIntegrationBudgetHours:
          defaultIntegrationBudgetHours ?? this.defaultIntegrationBudgetHours,
      defaultFrameDurationSecs:
          defaultFrameDurationSecs ?? this.defaultFrameDurationSecs,
      includeFlatsAtEnd: includeFlatsAtEnd ?? this.includeFlatsAtEnd,
      flatCountPerFilter: flatCountPerFilter ?? this.flatCountPerFilter,
      useSchedulerForMultiTarget:
          useSchedulerForMultiTarget ?? this.useSchedulerForMultiTarget,
      schedulerTargetThreshold:
          schedulerTargetThreshold ?? this.schedulerTargetThreshold,
      minAltitudeDeg: minAltitudeDeg ?? this.minAltitudeDeg,
      subExposureCeilingSecs:
          subExposureCeilingSecs ?? this.subExposureCeilingSecs,
      subExposureFloorSecs: subExposureFloorSecs ?? this.subExposureFloorSecs,
      targetSnr: targetSnr ?? this.targetSnr,
      ditherEveryFrames: ditherEveryFrames ?? this.ditherEveryFrames,
      prependPolarAlignmentIfStale:
          prependPolarAlignmentIfStale ?? this.prependPolarAlignmentIfStale,
      polarAlignmentStaleAfterDays:
          polarAlignmentStaleAfterDays ?? this.polarAlignmentStaleAfterDays,
      hasCoverCalibrator: hasCoverCalibrator ?? this.hasCoverCalibrator,
      coolDownTargetC: coolDownTargetC ?? this.coolDownTargetC,
      autoScheduleMissingDarks:
          autoScheduleMissingDarks ?? this.autoScheduleMissingDarks,
      darkFramesPerRequirement:
          darkFramesPerRequirement ?? this.darkFramesPerRequirement,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxSessionHours': maxSessionHours,
        'afCadence': afCadence.name,
        'afEveryFrames': afEveryFrames,
        'afEveryMinutes': afEveryMinutes,
        'afTempDeltaC': afTempDeltaC,
        'defaultIntegrationBudgetHours': defaultIntegrationBudgetHours,
        'defaultFrameDurationSecs': defaultFrameDurationSecs,
        'includeFlatsAtEnd': includeFlatsAtEnd,
        'flatCountPerFilter': flatCountPerFilter,
        'useSchedulerForMultiTarget': useSchedulerForMultiTarget,
        'schedulerTargetThreshold': schedulerTargetThreshold,
        'minAltitudeDeg': minAltitudeDeg,
        'subExposureCeilingSecs': subExposureCeilingSecs,
        'subExposureFloorSecs': subExposureFloorSecs,
        'targetSnr': targetSnr,
        'ditherEveryFrames': ditherEveryFrames,
        'prependPolarAlignmentIfStale': prependPolarAlignmentIfStale,
        'polarAlignmentStaleAfterDays': polarAlignmentStaleAfterDays,
        'hasCoverCalibrator': hasCoverCalibrator,
        'coolDownTargetC': coolDownTargetC,
        'autoScheduleMissingDarks': autoScheduleMissingDarks,
        'darkFramesPerRequirement': darkFramesPerRequirement,
      };

  factory SmartNightSettings.fromJson(Map<String, dynamic> json) {
    return SmartNightSettings(
      maxSessionHours: _jsonDouble(json['maxSessionHours'], 12.0),
      afCadence: _enumByName(
        SmartNightAfCadence.values,
        json['afCadence'],
        SmartNightAfCadence.everyNFrames,
      ),
      afEveryFrames: _jsonInt(json['afEveryFrames'], 25),
      afEveryMinutes: _jsonInt(json['afEveryMinutes'], 60),
      afTempDeltaC: _jsonDouble(json['afTempDeltaC'], 1.5),
      defaultIntegrationBudgetHours:
          _jsonDouble(json['defaultIntegrationBudgetHours'], 4.0),
      defaultFrameDurationSecs:
          _stringDoubleMap(json['defaultFrameDurationSecs']),
      includeFlatsAtEnd: json['includeFlatsAtEnd'] as bool? ?? true,
      flatCountPerFilter: _jsonInt(json['flatCountPerFilter'], 20),
      useSchedulerForMultiTarget:
          json['useSchedulerForMultiTarget'] as bool? ?? true,
      schedulerTargetThreshold: _jsonInt(json['schedulerTargetThreshold'], 3),
      minAltitudeDeg: _jsonDouble(json['minAltitudeDeg'], 30.0),
      subExposureCeilingSecs:
          _jsonDouble(json['subExposureCeilingSecs'], 300.0),
      subExposureFloorSecs: _jsonDouble(json['subExposureFloorSecs'], 30.0),
      targetSnr: _jsonDouble(json['targetSnr'], 30.0),
      ditherEveryFrames: _jsonInt(json['ditherEveryFrames'], 3),
      prependPolarAlignmentIfStale:
          json['prependPolarAlignmentIfStale'] as bool? ?? true,
      polarAlignmentStaleAfterDays:
          _jsonInt(json['polarAlignmentStaleAfterDays'], 7),
      hasCoverCalibrator: json['hasCoverCalibrator'] as bool? ?? false,
      coolDownTargetC: _jsonDouble(json['coolDownTargetC'], -10.0),
      autoScheduleMissingDarks:
          json['autoScheduleMissingDarks'] as bool? ?? false,
      darkFramesPerRequirement: _jsonInt(json['darkFramesPerRequirement'], 20),
    );
  }
}

/// Snapshot of cross-system inputs the auto-builder consumes. Each field
/// has a sensible "missing" fallback so the wizard can run end-to-end even
/// before all data sources have warmed up.
class SmartNightContext {
  /// Tonight's dark window — astronomical dusk → dawn at the observer's
  /// site. When polar latitudes prevent astronomical darkness, this falls
  /// back to nautical / civil twilight (see [SmartNightService.calculateWindow]).
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Probability (0..1) of rain or cloud cover within the planning
  /// window. When `null` the builder skips the weather-arriving recovery
  /// node. When > 0.4 the builder prepends a `CloudArrivingIn` recovery
  /// trigger (Wave 5 cross-system integration).
  final double? rainOrCloudProbability;

  /// Lead time (minutes) before the storm arrival when the recovery
  /// trigger should fire. Pulled from the weather alert settings.
  final int cloudArrivalLeadTimeMinutes;

  /// Site Bortle class (1..9). The exposure calculator's sky electron
  /// rate scales off this. Falls back to Bortle 5 (the historic default)
  /// when unknown.
  final int bortleClass;

  /// Most recent guide RMS for the active mount (arcsec) — pulled from
  /// the SkyBrightnessTracker / PHD2 history. `null` until we have at
  /// least one guided session for this mount.
  final double? recentGuideRmsArcsec;
  final int recentGuideSamples;

  /// Number of days since the last successful polar alignment for the
  /// active profile. `null` when no record exists. The builder injects a
  /// [PolarAlignmentNode] when this exceeds
  /// `settings.polarAlignmentStaleAfterDays`.
  final int? daysSinceLastPolarAlignment;

  /// Coverage gaps in the dark library — set of `(gain, durationSecs)`
  /// pairs that the wizard found no master dark for. When non-empty the
  /// builder surfaces a warning in [SmartNightPlan.warnings]. When
  /// [SmartNightSettings.autoScheduleMissingDarks] is true AND
  /// [missingDarkRequirements] is non-empty, the builder ALSO appends a
  /// "Dark Library Refresh" instruction group at the end of the lights
  /// tree that captures the missing combinations.
  final List<String> missingDarkLibraryNotes;

  /// Structured form of the same gaps surfaced in
  /// [missingDarkLibraryNotes]. The wizard's coverage analyzer populates
  /// this with the (gain, offset, exposure, binning, temperature)
  /// tuples representing missing dark combinations. The builder only
  /// consumes this list when [SmartNightSettings.autoScheduleMissingDarks]
  /// is true — otherwise it is informational metadata round-tripped
  /// through draft persistence.
  final List<DarkFrameRequirement> missingDarkRequirements;

  /// Whether the SkyBrightnessTracker reports the site is currently
  /// brighter than the camera/filter's "adaptive" reference, indicating
  /// the user should enable the per-target adaptive exposure config.
  final bool adaptiveExposuresRecommended;

  const SmartNightContext({
    required this.windowStart,
    required this.windowEnd,
    this.rainOrCloudProbability,
    this.cloudArrivalLeadTimeMinutes = 30,
    this.bortleClass = 5,
    this.recentGuideRmsArcsec,
    this.recentGuideSamples = 0,
    this.daysSinceLastPolarAlignment,
    this.missingDarkLibraryNotes = const [],
    this.missingDarkRequirements = const [],
    this.adaptiveExposuresRecommended = false,
  });

  SmartNightContext copyWith({
    DateTime? windowStart,
    DateTime? windowEnd,
    double? rainOrCloudProbability,
    int? cloudArrivalLeadTimeMinutes,
    int? bortleClass,
    double? recentGuideRmsArcsec,
    int? recentGuideSamples,
    int? daysSinceLastPolarAlignment,
    List<String>? missingDarkLibraryNotes,
    List<DarkFrameRequirement>? missingDarkRequirements,
    bool? adaptiveExposuresRecommended,
  }) {
    return SmartNightContext(
      windowStart: windowStart ?? this.windowStart,
      windowEnd: windowEnd ?? this.windowEnd,
      rainOrCloudProbability:
          rainOrCloudProbability ?? this.rainOrCloudProbability,
      cloudArrivalLeadTimeMinutes:
          cloudArrivalLeadTimeMinutes ?? this.cloudArrivalLeadTimeMinutes,
      bortleClass: bortleClass ?? this.bortleClass,
      recentGuideRmsArcsec: recentGuideRmsArcsec ?? this.recentGuideRmsArcsec,
      recentGuideSamples: recentGuideSamples ?? this.recentGuideSamples,
      daysSinceLastPolarAlignment:
          daysSinceLastPolarAlignment ?? this.daysSinceLastPolarAlignment,
      missingDarkLibraryNotes:
          missingDarkLibraryNotes ?? this.missingDarkLibraryNotes,
      missingDarkRequirements:
          missingDarkRequirements ?? this.missingDarkRequirements,
      adaptiveExposuresRecommended:
          adaptiveExposuresRecommended ?? this.adaptiveExposuresRecommended,
    );
  }

  Map<String, dynamic> toJson() => {
        'windowStart': windowStart.toIso8601String(),
        'windowEnd': windowEnd.toIso8601String(),
        'rainOrCloudProbability': rainOrCloudProbability,
        'cloudArrivalLeadTimeMinutes': cloudArrivalLeadTimeMinutes,
        'bortleClass': bortleClass,
        'recentGuideRmsArcsec': recentGuideRmsArcsec,
        'recentGuideSamples': recentGuideSamples,
        'daysSinceLastPolarAlignment': daysSinceLastPolarAlignment,
        'missingDarkLibraryNotes': missingDarkLibraryNotes,
        'missingDarkRequirements':
            missingDarkRequirements.map(_darkRequirementToJson).toList(),
        'adaptiveExposuresRecommended': adaptiveExposuresRecommended,
      };

  factory SmartNightContext.fromJson(Map<String, dynamic> json) {
    return SmartNightContext(
      windowStart: DateTime.parse(json['windowStart'] as String),
      windowEnd: DateTime.parse(json['windowEnd'] as String),
      rainOrCloudProbability:
          (json['rainOrCloudProbability'] as num?)?.toDouble(),
      cloudArrivalLeadTimeMinutes:
          _jsonInt(json['cloudArrivalLeadTimeMinutes'], 30),
      bortleClass: _jsonInt(json['bortleClass'], 5),
      recentGuideRmsArcsec: (json['recentGuideRmsArcsec'] as num?)?.toDouble(),
      recentGuideSamples: _jsonInt(json['recentGuideSamples'], 0),
      daysSinceLastPolarAlignment: json['daysSinceLastPolarAlignment'] as int?,
      missingDarkLibraryNotes: _stringList(json['missingDarkLibraryNotes']),
      missingDarkRequirements: _darkRequirementsFromJson(
        json['missingDarkRequirements'],
      ),
      adaptiveExposuresRecommended:
          json['adaptiveExposuresRecommended'] as bool? ?? false,
    );
  }
}

/// Container for the wizard's "preview" step: the [Sequence] that will be
/// loaded into the editor, plus per-target rationale and any warnings the
/// service surfaced while building.
class SmartNightPlan {
  final Sequence sequence;

  /// Targets the scheduler / linear chain will image, in the order they
  /// were placed into the tree.
  final List<SmartNightPlannedTarget> plannedTargets;

  /// Total integration time across all targets, in seconds. The wizard
  /// renders this on the preview screen as "Total integration: Xh Ym".
  final double totalIntegrationSecs;

  /// Estimated wall-clock duration (with overhead) of the generated
  /// sequence. The wizard compares this to the dark window length and
  /// warns if it doesn't fit.
  final double estimatedWallClockSecs;

  /// Soft-warnings to surface in the wizard preview. Examples:
  /// - "Dark library missing 120s @ G100 — consider a dark night."
  /// - "Polar alignment last ran 14 days ago — running a fresh
  ///   alignment is recommended."
  /// - "Rain probability 60% within the next 3h — Cloud Arriving
  ///   recovery added."
  final List<String> warnings;

  /// Strategy that was selected — surfaced in the wizard summary.
  final SmartNightStrategy strategy;

  /// The settings actually used (after wizard overrides).
  final SmartNightSettings settings;

  /// The cross-system context that drove the build.
  final SmartNightContext context;

  const SmartNightPlan({
    required this.sequence,
    required this.plannedTargets,
    required this.totalIntegrationSecs,
    required this.estimatedWallClockSecs,
    required this.warnings,
    required this.strategy,
    required this.settings,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'sequence': SequenceFileService().sequenceToMap(sequence),
        'plannedTargets': plannedTargets.map((t) => t.toJson()).toList(),
        'totalIntegrationSecs': totalIntegrationSecs,
        'estimatedWallClockSecs': estimatedWallClockSecs,
        'warnings': warnings,
        'strategy': strategy.name,
        'settings': settings.toJson(),
        'context': context.toJson(),
      };

  factory SmartNightPlan.fromJson(Map<String, dynamic> json) {
    final sequenceJson = (json['sequence'] as Map).cast<String, dynamic>();
    return SmartNightPlan(
      sequence: SequenceFileService().parseFromMap(sequenceJson),
      plannedTargets: (json['plannedTargets'] as List? ?? const [])
          .map((e) => SmartNightPlannedTarget.fromJson(
              (e as Map).cast<String, dynamic>()))
          .toList(),
      totalIntegrationSecs: _jsonDouble(json['totalIntegrationSecs'], 0.0),
      estimatedWallClockSecs: _jsonDouble(json['estimatedWallClockSecs'], 0.0),
      warnings: _stringList(json['warnings']),
      strategy: _enumByName(
        SmartNightStrategy.values,
        json['strategy'],
        SmartNightStrategy.autoLrgb,
      ),
      settings: SmartNightSettings.fromJson(
          (json['settings'] as Map).cast<String, dynamic>()),
      context: SmartNightContext.fromJson(
          (json['context'] as Map).cast<String, dynamic>()),
    );
  }
}

/// One target placed onto the night's tree — captured here so the wizard
/// preview can render a Gantt-style timeline without re-running the
/// scoring pipeline.
class SmartNightPlannedTarget {
  final TargetSuggestion suggestion;

  /// Wall-clock start/end inside the dark window — clipped by the
  /// scheduler so transitions between targets don't overlap.
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Per-filter exposure plan (count + duration + rationale).
  final List<SmartNightFilterPlan> filterPlans;

  /// Total integration for this target across all filters (seconds).
  final double integrationSecs;

  /// Rationale string surfaced to the user: `"Picked because (reason)"`.
  final String rationale;

  const SmartNightPlannedTarget({
    required this.suggestion,
    required this.windowStart,
    required this.windowEnd,
    required this.filterPlans,
    required this.integrationSecs,
    required this.rationale,
  });

  Map<String, dynamic> toJson() => {
        'suggestion': suggestion.toJson(),
        'windowStart': windowStart.toIso8601String(),
        'windowEnd': windowEnd.toIso8601String(),
        'filterPlans': filterPlans.map((p) => p.toJson()).toList(),
        'integrationSecs': integrationSecs,
        'rationale': rationale,
      };

  factory SmartNightPlannedTarget.fromJson(Map<String, dynamic> json) {
    return SmartNightPlannedTarget(
      suggestion: TargetSuggestion.fromJson(
          (json['suggestion'] as Map).cast<String, dynamic>()),
      windowStart: DateTime.parse(json['windowStart'] as String),
      windowEnd: DateTime.parse(json['windowEnd'] as String),
      filterPlans: (json['filterPlans'] as List? ?? const [])
          .map((e) =>
              SmartNightFilterPlan.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      integrationSecs: _jsonDouble(json['integrationSecs'], 0.0),
      rationale: json['rationale'] as String? ?? '',
    );
  }
}

/// One filter row inside a planned target. Maps 1:1 to a [FilterPlan]
/// on the emitted [SmartExposureNode].
class SmartNightFilterPlan {
  final String filterName;
  final int count;
  final double durationSecs;
  final ExposureRecommendation? recommendation;

  const SmartNightFilterPlan({
    required this.filterName,
    required this.count,
    required this.durationSecs,
    this.recommendation,
  });

  double get integrationSecs => count * durationSecs;

  Map<String, dynamic> toJson() => {
        'filterName': filterName,
        'count': count,
        'durationSecs': durationSecs,
        'recommendation': _recommendationToJson(recommendation),
      };

  factory SmartNightFilterPlan.fromJson(Map<String, dynamic> json) {
    return SmartNightFilterPlan(
      filterName: json['filterName'] as String? ?? 'L',
      count: _jsonInt(json['count'], 0),
      durationSecs: _jsonDouble(json['durationSecs'], 0.0),
      recommendation: _recommendationFromJson(json['recommendation']),
    );
  }
}

/// Result of [SmartNightService.buildSingleTargetSequence].
class SingleTargetSequenceResult {
  final Sequence sequence;
  final SmartNightStrategy strategy;
  final List<SmartNightFilterPlan> filterPlans;
  final SmartNightPlannedTarget plannedTarget;

  const SingleTargetSequenceResult({
    required this.sequence,
    required this.strategy,
    required this.filterPlans,
    required this.plannedTarget,
  });
}

/// Filter-aware integration estimate for Plan Tonight list rows.
class TargetIntegrationPreview {
  /// Total light-frame integration (all filters) that fits the window.
  final double estimatedIntegrationHours;

  /// Hours the target is above [SmartNightSettings.minAltitudeDeg] tonight.
  final double usableWindowHours;

  /// Representative sub-exposure length from the exposure calculator.
  final double subExposureSecs;

  /// Filters included in the estimate (strategy + equipment profile).
  final List<String> filterNames;

  const TargetIntegrationPreview({
    required this.estimatedIntegrationHours,
    required this.usableWindowHours,
    required this.subExposureSecs,
    required this.filterNames,
  });
}

/// Errors the builder throws when an input is missing or invalid. The
/// wizard catches these and surfaces them as blocking error states
/// (rather than silently skipping the rule — errors are a feature).
class SmartNightBuildException implements Exception {
  final String message;
  const SmartNightBuildException(this.message);
  @override
  String toString() => 'SmartNightBuildException: $message';
}

// ---------------------------------------------------------------------------
// Public strategy / filter / exposure-plan helpers
//
// These functions operate purely on the model types above (settings, plans,
// strategies, target suggestions, equipment profiles). They are colocated
// with the models because [SmartNightService] and other call sites (Plan
// Tonight integration goals, tests) consume them as a public API surface —
// keeping them with their domain types avoids a circular service ↔ models
// import.
// ---------------------------------------------------------------------------

/// Map a Smart Night strategy to the actual filter slots present on a rig.
///
/// This is intentionally public because the sequence builder and pre-build
/// integrations, such as dark-library coverage, must agree on the exact
/// filter set before the plan is emitted.
List<String> resolveSmartNightFilterSet({
  required SmartNightStrategy strategy,
  required List<String> availableFilters,
}) {
  final lookup = {for (final f in availableFilters) f.toLowerCase(): f};
  String? present(String wanted) => lookup[wanted.toLowerCase()];

  switch (strategy) {
    case SmartNightStrategy.autoLrgb:
    case SmartNightStrategy.monoLrgb:
      final out = <String>[];
      final l = present('L') ?? present('Lum') ?? present('Luminance');
      final r = present('R') ?? present('Red');
      final g = present('G') ?? present('Green');
      final b = present('B') ?? present('Blue');
      if (l != null) out.add(l);
      if (r != null) out.add(r);
      if (g != null) out.add(g);
      if (b != null) out.add(b);
      return out;
    case SmartNightStrategy.narrowbandHoo:
      final out = <String>[];
      final ha = present('Ha') ?? present('H-alpha') ?? present('Halpha');
      final oiii = present('OIII') ?? present('O3');
      if (ha != null) out.add(ha);
      if (oiii != null) out.add(oiii);
      return out;
    case SmartNightStrategy.narrowbandSho:
      final out = <String>[];
      final ha = present('Ha') ?? present('H-alpha') ?? present('Halpha');
      final oiii = present('OIII') ?? present('O3');
      final sii = present('SII') ?? present('S2');
      if (ha != null) out.add(ha);
      if (oiii != null) out.add(oiii);
      if (sii != null) out.add(sii);
      return out;
    case SmartNightStrategy.oscOneShot:
      final preferred = present('L-eXtreme') ??
          present('L-uLtimate') ??
          present('L-Pro') ??
          present('L') ??
          present('UV/IR') ??
          present('UVIR') ??
          present('Light');
      if (preferred != null) return [preferred];
      if (availableFilters.isNotEmpty) return [availableFilters.first];
      return ['OSC'];
  }
}

/// Strategy-specific ratio weighting. Keys are lowercased filter names; values
/// are weight units normalised against the integration window in
/// [composeSmartNightFilterPlans].
Map<String, double> smartNightFilterRatios(SmartNightStrategy strategy) {
  switch (strategy) {
    case SmartNightStrategy.autoLrgb:
      return const {
        'l': 2.0,
        'lum': 2.0,
        'luminance': 2.0,
        'r': 1.0,
        'g': 1.0,
        'b': 1.0,
      };
    case SmartNightStrategy.monoLrgb:
      return const {
        'l': 1.0,
        'lum': 1.0,
        'luminance': 1.0,
        'r': 1.0,
        'g': 1.0,
        'b': 1.0,
      };
    case SmartNightStrategy.narrowbandHoo:
      return const {
        'ha': 1.0,
        'h-alpha': 1.0,
        'halpha': 1.0,
        'oiii': 1.0,
        'o3': 1.0,
      };
    case SmartNightStrategy.narrowbandSho:
      return const {
        'ha': 1.0,
        'h-alpha': 1.0,
        'halpha': 1.0,
        'oiii': 1.0,
        'o3': 1.0,
        'sii': 1.0,
        's2': 1.0,
      };
    case SmartNightStrategy.oscOneShot:
      return const {
        'osc': 1.0,
        'l': 1.0,
        'lum': 1.0,
        'uv/ir': 1.0,
        'uvir': 1.0,
        'light': 1.0,
      };
  }
}

/// True for emission / HII targets that benefit from narrowband rotation.
bool isEmissionNebulaTarget(TargetSuggestion suggestion) {
  final type = suggestion.objectType?.toLowerCase().trim() ?? '';
  if (type.isEmpty) return false;
  return type.contains('emission') ||
      type.contains('hii') ||
      type.contains('h ii') ||
      type == 'emission nebula';
}

/// Infer the Smart Night filter strategy from target type and wheel/profile
/// filters. Broadband galaxies pick LRGB when available; emission nebulae
/// prefer SHO or HOO; single-filter / OSC rigs fall back to one-shot.
SmartNightStrategy inferSmartNightStrategy(
  TargetSuggestion suggestion,
  List<String> availableFilters,
) {
  if (availableFilters.isEmpty) return SmartNightStrategy.oscOneShot;

  final lookup = {for (final f in availableFilters) f.toLowerCase(): f};
  final hasHa = _filterAliasPresent(lookup, ['Ha', 'H-alpha', 'Halpha']);
  final hasOiii = _filterAliasPresent(lookup, ['OIII', 'O3']);
  final hasSii = _filterAliasPresent(lookup, ['SII', 'S2']);

  final lrgbFilters = resolveSmartNightFilterSet(
    strategy: SmartNightStrategy.autoLrgb,
    availableFilters: availableFilters,
  );

  if (isEmissionNebulaTarget(suggestion)) {
    if (hasHa && hasOiii && hasSii) return SmartNightStrategy.narrowbandSho;
    if (hasHa && hasOiii) return SmartNightStrategy.narrowbandHoo;
  }

  // Galaxies, planetary/reflection nebulae, and SNRs prefer broadband LRGB.
  if (lrgbFilters.length >= 4) return SmartNightStrategy.autoLrgb;
  if (lrgbFilters.isNotEmpty) return SmartNightStrategy.autoLrgb;

  if (hasHa && hasOiii && hasSii) return SmartNightStrategy.narrowbandSho;
  if (hasHa && hasOiii) return SmartNightStrategy.narrowbandHoo;

  return SmartNightStrategy.oscOneShot;
}

/// Compose per-filter (count, durationSecs) using the exposure calculator,
/// strategy ratios, and integration window budget.
///
/// When [integrationGoalProgress] contains goals with remaining frames, those
/// rows take precedence for matching filters. Other strategy filters without
/// goals (or with zero remaining) are filled from the leftover window budget.
List<SmartNightFilterPlan> composeSmartNightFilterPlans({
  required TargetSuggestion suggestion,
  required SmartNightStrategy strategy,
  required List<String> activeFilters,
  required double windowSecs,
  required EquipmentProfileModel profile,
  required CameraExposureSpec cameraSpec,
  required double focalLengthMm,
  required double apertureMm,
  required double pixelSizeUm,
  required int bortleClass,
  required double? recentGuideRmsArcsec,
  required int recentGuideSamples,
  required SmartNightSettings settings,
  List<IntegrationGoalProgress>? integrationGoalProgress,
  List<String>? availableFiltersForGoals,
  SmartNightExposureCalculator exposureCalculator =
      const SmartNightExposureCalculator(),
}) {
  final availableForGoals = availableFiltersForGoals ?? activeFilters;
  final goalPlans = _composeFilterPlansFromIntegrationGoals(
    availableFilters: availableForGoals,
    integrationGoalProgress: integrationGoalProgress,
    cameraSpec: cameraSpec,
    focalLengthMm: focalLengthMm,
    apertureMm: apertureMm,
    pixelSizeUm: pixelSizeUm,
    bortleClass: bortleClass,
    recentGuideRmsArcsec: recentGuideRmsArcsec,
    recentGuideSamples: recentGuideSamples,
    settings: settings,
    exposureCalculator: exposureCalculator,
  );

  if (goalPlans != null &&
      goalPlans.isNotEmpty &&
      _allStrategyFiltersHaveRemainingGoals(
        activeFilters: activeFilters,
        integrationGoalProgress: integrationGoalProgress,
        availableFilters: availableForGoals,
      )) {
    return goalPlans;
  }

  if (goalPlans != null && goalPlans.isNotEmpty) {
    final goalIntegrationSecs = goalPlans.fold<double>(
      0,
      (sum, plan) => sum + plan.integrationSecs,
    );
    final remainingWindowSecs =
        math.max(0.0, windowSecs - goalIntegrationSecs).toDouble();
    final goalNames =
        goalPlans.map((p) => p.filterName.toLowerCase()).toSet();
    final budgetFilters = activeFilters
        .where((f) => !goalNames.contains(f.toLowerCase()))
        .toList();

    final budgetPlans = budgetFilters.isEmpty || remainingWindowSecs <= 0
        ? const <SmartNightFilterPlan>[]
        : _composeBudgetFilterPlans(
            strategy: strategy,
            activeFilters: budgetFilters,
            windowSecs: remainingWindowSecs,
            cameraSpec: cameraSpec,
            focalLengthMm: focalLengthMm,
            apertureMm: apertureMm,
            pixelSizeUm: pixelSizeUm,
            bortleClass: bortleClass,
            recentGuideRmsArcsec: recentGuideRmsArcsec,
            recentGuideSamples: recentGuideSamples,
            settings: settings,
            exposureCalculator: exposureCalculator,
          );

    return _mergeFilterPlansInStrategyOrder(
      activeFilters: activeFilters,
      goalPlans: goalPlans,
      budgetPlans: budgetPlans,
    );
  }

  return _composeBudgetFilterPlans(
    strategy: strategy,
    activeFilters: activeFilters,
    windowSecs: windowSecs,
    cameraSpec: cameraSpec,
    focalLengthMm: focalLengthMm,
    apertureMm: apertureMm,
    pixelSizeUm: pixelSizeUm,
    bortleClass: bortleClass,
    recentGuideRmsArcsec: recentGuideRmsArcsec,
    recentGuideSamples: recentGuideSamples,
    settings: settings,
    exposureCalculator: exposureCalculator,
  );
}

// ---------------------------------------------------------------------------
// Private helpers — used exclusively by the model classes / public helpers
// above. Kept in this file so model JSON serde + filter-plan composition
// stay self-contained.
// ---------------------------------------------------------------------------

bool _filterAliasPresent(
  Map<String, String> lookup,
  Iterable<String> aliases,
) {
  for (final alias in aliases) {
    if (lookup.containsKey(alias.toLowerCase())) return true;
  }
  return false;
}

bool _allStrategyFiltersHaveRemainingGoals({
  required List<String> activeFilters,
  required List<IntegrationGoalProgress>? integrationGoalProgress,
  required List<String> availableFilters,
}) {
  if (activeFilters.isEmpty) return false;
  if (integrationGoalProgress == null || integrationGoalProgress.isEmpty) {
    return false;
  }

  final lookup = {for (final f in availableFilters) f.toLowerCase(): f};
  for (final filter in activeFilters) {
    final key = filter.toLowerCase();
    final hasRemaining = integrationGoalProgress.any((progress) {
      if (progress.remainingFrames <= 0) return false;
      final matched = lookup[progress.goal.filter.toLowerCase()];
      return matched != null && matched.toLowerCase() == key;
    });
    if (!hasRemaining) return false;
  }
  return true;
}

List<SmartNightFilterPlan> _mergeFilterPlansInStrategyOrder({
  required List<String> activeFilters,
  required List<SmartNightFilterPlan> goalPlans,
  required List<SmartNightFilterPlan> budgetPlans,
}) {
  final byName = {
    for (final plan in [...goalPlans, ...budgetPlans])
      plan.filterName.toLowerCase(): plan,
  };
  return [
    for (final filter in activeFilters)
      if (byName.containsKey(filter.toLowerCase())) byName[filter.toLowerCase()]!,
  ];
}

List<SmartNightFilterPlan> _composeBudgetFilterPlans({
  required SmartNightStrategy strategy,
  required List<String> activeFilters,
  required double windowSecs,
  required CameraExposureSpec cameraSpec,
  required double focalLengthMm,
  required double apertureMm,
  required double pixelSizeUm,
  required int bortleClass,
  required double? recentGuideRmsArcsec,
  required int recentGuideSamples,
  required SmartNightSettings settings,
  required SmartNightExposureCalculator exposureCalculator,
}) {
  if (activeFilters.isEmpty) return const [];

  final ratios = smartNightFilterRatios(strategy);
  final sumRatios = activeFilters.fold<double>(
    0,
    (sum, f) => sum + (ratios[f.toLowerCase()] ?? 1.0),
  );
  final perFilterBudget = sumRatios <= 0
      ? <String, double>{}
      : {
          for (final f in activeFilters)
            f: windowSecs * (ratios[f.toLowerCase()] ?? 1.0) / sumRatios,
        };

  final out = <SmartNightFilterPlan>[];
  for (final filterName in activeFilters) {
    final recommendation = exposureCalculator.recommend(
      ExposureCalculatorInput(
        camera: cameraSpec,
        filter: FilterExposureSpec.fromName(filterName),
        bortleClass: bortleClass,
        focalLengthMm: focalLengthMm,
        apertureMm: apertureMm,
        pixelSizeMicrons: pixelSizeUm,
        guideRmsArcsec: recentGuideRmsArcsec,
        guideSampleCount: recentGuideSamples,
        gloverKFactor: 10,
        targetSnr: settings.targetSnr,
        userCapSeconds: settings.subExposureCeilingSecs,
        floorSeconds: settings.subExposureFloorSecs,
      ),
    );
    final pickedSecs = recommendation.seconds > 0
        ? recommendation.seconds
        : settings.defaultFrameDurationSecs[filterName.toUpperCase()] ??
            settings.defaultFrameDurationSecs[filterName] ??
            180.0;
    final budgetSecs = perFilterBudget[filterName] ?? 0;
    final count =
        budgetSecs <= 0 ? 1 : math.max(1, (budgetSecs / pickedSecs).floor());
    out.add(SmartNightFilterPlan(
      filterName: filterName,
      count: count,
      durationSecs: pickedSecs,
      recommendation: recommendation,
    ));
  }
  return out;
}

List<SmartNightFilterPlan>? _composeFilterPlansFromIntegrationGoals({
  required List<String> availableFilters,
  required List<IntegrationGoalProgress>? integrationGoalProgress,
  required CameraExposureSpec cameraSpec,
  required double focalLengthMm,
  required double apertureMm,
  required double pixelSizeUm,
  required int bortleClass,
  required double? recentGuideRmsArcsec,
  required int recentGuideSamples,
  required SmartNightSettings settings,
  required SmartNightExposureCalculator exposureCalculator,
}) {
  if (integrationGoalProgress == null || integrationGoalProgress.isEmpty) {
    return null;
  }

  final lookup = {for (final f in availableFilters) f.toLowerCase(): f};
  final out = <SmartNightFilterPlan>[];

  for (final progress in integrationGoalProgress) {
    if (progress.remainingFrames <= 0) continue;
    final matched = lookup[progress.goal.filter.toLowerCase()];
    if (matched == null) continue;

    final goalSecs = progress.goal.exposureSeconds;
    ExposureRecommendation? recommendation;
    var durationSecs = goalSecs;
    if (goalSecs <= 0) {
      recommendation = exposureCalculator.recommend(
        ExposureCalculatorInput(
          camera: cameraSpec,
          filter: FilterExposureSpec.fromName(matched),
          bortleClass: bortleClass,
          focalLengthMm: focalLengthMm,
          apertureMm: apertureMm,
          pixelSizeMicrons: pixelSizeUm,
          guideRmsArcsec: recentGuideRmsArcsec,
          guideSampleCount: recentGuideSamples,
          gloverKFactor: 10,
          targetSnr: settings.targetSnr,
          userCapSeconds: settings.subExposureCeilingSecs,
          floorSeconds: settings.subExposureFloorSecs,
        ),
      );
      durationSecs = recommendation.seconds > 0
          ? recommendation.seconds
          : settings.defaultFrameDurationSecs[matched.toUpperCase()] ??
              settings.defaultFrameDurationSecs[matched] ??
              180.0;
    }

    out.add(SmartNightFilterPlan(
      filterName: matched,
      count: progress.remainingFrames,
      durationSecs: durationSecs,
      recommendation: recommendation,
    ));
  }

  return out.isEmpty ? null : out;
}

// JSON serde helpers — used exclusively by the model classes above.

Map<String, dynamic> _darkRequirementToJson(DarkFrameRequirement req) => {
      'gain': req.gain,
      'offset': req.offset,
      'durationSecs': req.durationSecs,
      'binX': req.binX,
      'binY': req.binY,
      'targetTemp': req.targetTemp,
    };

List<DarkFrameRequirement> _darkRequirementsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final out = <DarkFrameRequirement>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final m = entry.cast<String, dynamic>();
    final gain = _jsonInt(m['gain'], 0);
    final offset = _jsonInt(m['offset'], 0);
    final durationSecs = _jsonDouble(m['durationSecs'], 0.0);
    final binX = _jsonInt(m['binX'], 1);
    final binY = _jsonInt(m['binY'], 1);
    final temp = m['targetTemp'];
    final targetTemp = temp is num ? temp.toDouble() : null;
    if (durationSecs <= 0) continue;
    out.add(DarkFrameRequirement(
      gain: gain,
      offset: offset,
      durationSecs: durationSecs,
      binX: binX,
      binY: binY,
      targetTemp: targetTemp,
    ));
  }
  return List.unmodifiable(out);
}

Map<String, dynamic>? _recommendationToJson(ExposureRecommendation? value) {
  if (value == null) return null;
  return {
    'seconds': value.seconds,
    'limitingFactor': value.limitingFactor.name,
    'allCeilings': value.allCeilings.map((k, v) => MapEntry(k.name, v)),
    'rationale': value.rationale,
    'caveats': value.caveats,
  };
}

ExposureRecommendation? _recommendationFromJson(Object? raw) {
  if (raw == null) return null;
  final json = (raw as Map).cast<String, dynamic>();
  final ceilingsRaw =
      (json['allCeilings'] as Map?)?.cast<String, dynamic>() ?? const {};
  final ceilings = <ExposureLimitingFactor, double>{
    for (final entry in ceilingsRaw.entries)
      _enumByName(
        ExposureLimitingFactor.values,
        entry.key,
        ExposureLimitingFactor.glover,
      ): (entry.value as num).toDouble(),
  };
  return ExposureRecommendation(
    seconds: _jsonDouble(json['seconds'], 0.0),
    limitingFactor: _enumByName(
      ExposureLimitingFactor.values,
      json['limitingFactor'],
      ExposureLimitingFactor.glover,
    ),
    allCeilings: Map.unmodifiable(ceilings),
    rationale: json['rationale'] as String? ?? '',
    caveats: List.unmodifiable(_stringList(json['caveats'])),
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw as String?;
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

double _jsonDouble(Object? raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;

int _jsonInt(Object? raw, int fallback) => raw is num ? raw.toInt() : fallback;

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList(growable: false);
}

Map<String, double> _stringDoubleMap(Object? raw) {
  if (raw is! Map) {
    return const SmartNightSettings().defaultFrameDurationSecs;
  }
  return raw.map(
    (key, value) => MapEntry(
      key.toString(),
      value is num ? value.toDouble() : 0.0,
    ),
  );
}
