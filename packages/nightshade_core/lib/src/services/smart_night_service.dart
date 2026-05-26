import 'dart:math' as math;

import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/imaging/imaging_models.dart' show FrameType;
import '../models/notification/notification_categories.dart'
    show NotificationTransportKind;
import '../models/planning/target_suggestion.dart';
import '../models/scheduler/integration_goal.dart';
import '../models/sequence/sequence_models.dart';
import '../providers/profiles_provider.dart' show EquipmentProfileModel;
import 'logging_service.dart';
import 'pre_session_simulator.dart';
import 'session_optimizer_service.dart' show SmartNightExposureContext;
import 'smart_night/exposure_calculator.dart';
import 'smart_night/hardware_specs_service.dart';
import 'smart_night_models.dart';
import 'target_suggestion_service.dart';

// Re-export model classes, enums, exceptions, and pure helpers so the
// existing `package:nightshade_core/nightshade_core.dart` barrel surface
// remains stable for consumers (Smart Night dialog, plan launcher, planner
// screens, draft service, tests). The orchestration class
// [SmartNightService] stays in this file; everything else now lives in
// `smart_night_models.dart`.
export 'smart_night_models.dart';

bool _profileHasGuider(EquipmentProfileModel profile) {
  final id = profile.guiderId?.trim() ?? '';
  final name = profile.guiderName?.trim() ?? '';
  return id.isNotEmpty || name.isNotEmpty;
}

/// The auto-builder service.
///
/// Reuses (does NOT reinvent) existing services per the design doc:
///   * [TargetSuggestionService] — scores tonight's candidate targets
///   * [SmartNightExposureCalculator] — per-filter sub-length
///   * [AstronomyCalculations] (planetarium) — twilight bounds + altitude
///
/// Reads (cross-system integrations per the strategic report):
///   * weather forecast → injects CloudArrivingIn recovery on rainy nights
///   * sky brightness tracker → flags adaptive exposures recommended
///   * equipment health / polar alignment history → injects a polar
///     alignment node when stale
///   * dark library coverage → surfaces gaps as warnings
class SmartNightService {
  final TargetSuggestionService _suggestionService;
  final LoggingService _logging;
  final SmartNightExposureCalculator _exposureCalculator;
  final HardwareSpecsService _hardwareSpecs;

  static const _source = 'SmartNightService';
  static const _uuid = Uuid();

  /// Minimum dark-window slice (seconds) that's still worth slewing to.
  /// Shorter than this and we drop the target rather than spend 5 min of
  /// slew + center + focus only to take two subs.
  static const double _minTargetWindowSecs = 30 * 60; // 30 minutes

  /// Wall-clock seconds reserved between targets for slew + center +
  /// refocus + guide re-acquisition. Used by the scheduling step so we
  /// don't over-stuff the dark window.
  static const double _transitionOverheadSecs = 20 * 60; // 20 minutes

  const SmartNightService({
    required TargetSuggestionService suggestionService,
    required LoggingService logging,
    SmartNightExposureCalculator exposureCalculator =
        const SmartNightExposureCalculator(),
    HardwareSpecsService hardwareSpecs = const HardwareSpecsService(),
  })  : _suggestionService = suggestionService,
        _logging = logging,
        _exposureCalculator = exposureCalculator,
        _hardwareSpecs = hardwareSpecs;

  /// Compute tonight's dark window from the observer location. Falls back
  /// to nautical / civil twilight at high latitudes, and finally to a
  /// 21:00 → 05:00 default when no twilight period exists (e.g. polar
  /// midnight sun).
  ///
  /// [now] is exposed for testability — production code passes
  /// `DateTime.now()`.
  ({DateTime start, DateTime end, TwilightTimes twilight}) calculateWindow({
    required double latitudeDeg,
    required double longitudeDeg,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    // If we're already past midnight but before dawn, use last night's
    // twilight. Mirrors the heuristic in [TargetSuggestionService].
    final prevDate = DateTime(reference.year, reference.month, reference.day)
        .subtract(const Duration(days: 1));
    final prevTwilight = AstronomyCalculations.calculateTwilightTimes(
      date: prevDate,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );
    final prevBounds = _extractNightBounds(prevTwilight);
    if (prevBounds != null &&
        reference.isAfter(prevBounds.$1) &&
        reference.isBefore(prevBounds.$2)) {
      return (
        start: prevBounds.$1,
        end: prevBounds.$2,
        twilight: prevTwilight,
      );
    }

    final todayDate = DateTime(reference.year, reference.month, reference.day);
    final todayTwilight = AstronomyCalculations.calculateTwilightTimes(
      date: todayDate,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );
    final todayBounds = _extractNightBounds(todayTwilight);
    if (todayBounds != null) {
      return (
        start: todayBounds.$1,
        end: todayBounds.$2,
        twilight: todayTwilight,
      );
    }

    // Polar midnight sun fallback — fail loudly through the log so the
    // user knows we couldn't compute astronomical darkness, but still
    // return *something* so the wizard isn't blocked.
    _logging.warning(
      'No astronomical/nautical/civil twilight at lat=$latitudeDeg lon=$longitudeDeg; '
      'falling back to 21:00 → 05:00 local default.',
      source: _source,
    );
    final fallbackStart =
        DateTime(reference.year, reference.month, reference.day, 21);
    var fallbackEnd = fallbackStart.add(const Duration(hours: 8));
    if (reference.isAfter(fallbackEnd)) {
      fallbackEnd = fallbackEnd.add(const Duration(days: 1));
    }
    return (
      start: fallbackStart,
      end: fallbackEnd,
      twilight: todayTwilight,
    );
  }

  (DateTime, DateTime)? _extractNightBounds(TwilightTimes tw) {
    if (tw.astronomicalDusk != null && tw.astronomicalDawn != null) {
      return (tw.astronomicalDusk!, tw.astronomicalDawn!);
    }
    if (tw.nauticalDusk != null && tw.nauticalDawn != null) {
      return (tw.nauticalDusk!, tw.nauticalDawn!);
    }
    if (tw.civilDusk != null && tw.civilDawn != null) {
      return (tw.civilDusk!, tw.civilDawn!);
    }
    if (tw.sunset != null && tw.sunrise != null) {
      return (tw.sunset!, tw.sunrise!);
    }
    return null;
  }

  /// Score and rank the catalogue of saved targets for tonight using the
  /// existing TargetSuggestionService — no reinvention.
  Future<List<TargetSuggestion>> rankCandidates({
    required EquipmentProfileModel profile,
    required double latitudeDeg,
    required double longitudeDeg,
    required List<db.Target> targets,
    required List<db.ImagingSession> sessions,
    DateTime? observationTime,
    double minAltitude = 30.0,
    double minScore = 30.0,
  }) async {
    if (targets.isEmpty) return const [];
    return _suggestionService.getSuggestionsForTonight(
      config: TargetSuggestionConfig(
        minAltitude: minAltitude,
        minScore: minScore,
      ),
      latitude: latitudeDeg,
      longitude: longitudeDeg,
      targets: targets,
      sessions: sessions,
      observationTime: observationTime,
    );
  }

  /// Build the night's [Sequence].
  ///
  /// `selectedSuggestions` is the user's chosen target list — either
  /// hand-picked from the wizard step 3 list, or the top-N picks of
  /// [rankCandidates]. The service does NOT re-rank; the wizard
  /// composes that pipeline.
  ///
  /// Validates required inputs and throws [SmartNightBuildException]
  /// when an essential field is missing. Silent fallback would hide
  /// bugs for months — errors are a feature.
  SmartNightPlan build({
    required EquipmentProfileModel profile,
    required double latitudeDeg,
    required double longitudeDeg,
    required SmartNightContext context,
    required List<TargetSuggestion> selectedSuggestions,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    SmartNightExposureContext? exposureContext,
  }) {
    _validateInputs(
      profile: profile,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      selectedSuggestions: selectedSuggestions,
      context: context,
    );

    // Bound the planning window by max session hours.
    final effectiveWindowEnd = _capWindowToMaxHours(
      windowStart: context.windowStart,
      windowEnd: context.windowEnd,
      maxHours: settings.maxSessionHours,
    );

    final activeFilters = _resolveFilterSet(
      strategy: strategy,
      availableFilters: profile.filterNames,
    );
    if (activeFilters.isEmpty) {
      throw SmartNightBuildException(
        'No filters from strategy "${strategy.name}" matched profile '
        '"${profile.name}" (available filters: '
        '${profile.filterNames.isEmpty ? "<none>" : profile.filterNames.join(", ")}). '
        'Either switch strategies (the OSC One-Shot strategy works without '
        'a wheel) or add the required filters to the equipment profile.',
      );
    }

    final pixelSizeUm =
        exposureContext?.pixelSizeMicrons ?? _pixelSize(profile);
    final focalLength = profile.focalLength > 0
        ? profile.focalLength
        : (exposureContext?.focalLengthMm ?? profile.telescopeFocalLength ?? 0);
    final aperture = profile.aperture > 0
        ? profile.aperture
        : (exposureContext?.apertureMm ?? profile.telescopeAperture ?? 0);
    final cameraSpec =
        exposureContext?.camera ?? _cameraSpecFromProfile(profile);

    if (focalLength <= 0 || aperture <= 0 || pixelSizeUm <= 0) {
      throw SmartNightBuildException(
        'Equipment profile "${profile.name}" is missing aperture, focal '
        'length, or pixel size — these are required to compute exposure '
        'recommendations. Aperture=$aperture mm, '
        'focal length=$focalLength mm, '
        'pixel size=$pixelSizeUm µm.',
      );
    }

    // Schedule targets into the dark window. We use a deep-first
    // chaining strategy: take the highest-scoring target until its
    // usable window inside the dark window is exhausted, then move to
    // the next, accounting for the slew/center/refocus overhead.
    final planned = <SmartNightPlannedTarget>[];
    DateTime cursor = context.windowStart;
    var first = true;
    for (final suggestion in selectedSuggestions) {
      if (cursor.isAfter(effectiveWindowEnd) ||
          !cursor.isBefore(effectiveWindowEnd)) {
        break;
      }
      // Reserve transition overhead between targets so we don't claim
      // the same minute twice.
      if (!first) {
        cursor = cursor.add(Duration(seconds: _transitionOverheadSecs.round()));
      }
      if (!cursor.isBefore(effectiveWindowEnd)) break;

      final usable = _usableTargetWindow(
        suggestion: suggestion,
        intervalStart: cursor,
        intervalEnd: effectiveWindowEnd,
        minAltitude: settings.minAltitudeDeg,
      );
      if (usable == null) {
        _logging.debug(
          'Skipping ${suggestion.targetName}: no usable window inside '
          '$cursor..$effectiveWindowEnd at min alt ${settings.minAltitudeDeg}°',
          source: _source,
        );
        continue;
      }

      final intervalWindowSecs =
          usable.$2.difference(usable.$1).inSeconds.toDouble();
      final windowSecs = _integrationWindowSecs(
        suggestion: suggestion,
        intervalWindowSecs: intervalWindowSecs,
        integrationBudgetHours: null,
        settings: settings,
      );
      if (windowSecs < _minTargetWindowSecs) {
        _logging.debug(
          'Skipping ${suggestion.targetName}: usable window '
          '${(windowSecs / 60).toStringAsFixed(0)} min < '
          '${(_minTargetWindowSecs / 60).toStringAsFixed(0)} min minimum.',
          source: _source,
        );
        continue;
      }

      final filterPlans = _composeFilterPlans(
        suggestion: suggestion,
        strategy: strategy,
        activeFilters: activeFilters,
        windowSecs: windowSecs,
        profile: profile,
        cameraSpec: cameraSpec,
        focalLengthMm: focalLength,
        apertureMm: aperture,
        pixelSizeUm: pixelSizeUm,
        bortleClass: context.bortleClass,
        recentGuideRmsArcsec: context.recentGuideRmsArcsec,
        recentGuideSamples: context.recentGuideSamples,
        settings: settings,
      );
      if (filterPlans.isEmpty) continue;

      final integrationSecs = filterPlans.fold<double>(
        0,
        (sum, plan) => sum + plan.integrationSecs,
      );
      final actualEnd = usable.$1.add(
        Duration(seconds: integrationSecs.round()),
      );
      final clampedEnd = actualEnd.isBefore(usable.$2) ? actualEnd : usable.$2;

      planned.add(SmartNightPlannedTarget(
        suggestion: suggestion,
        windowStart: usable.$1,
        windowEnd: clampedEnd,
        filterPlans: filterPlans,
        integrationSecs: integrationSecs,
        rationale: _composeTargetRationale(
          suggestion: suggestion,
          filterPlans: filterPlans,
          windowSecs: clampedEnd.difference(usable.$1).inSeconds.toDouble(),
        ),
      ));
      cursor = clampedEnd;
      first = false;
    }

    if (planned.isEmpty) {
      throw SmartNightBuildException(
        'None of the selected targets had a usable imaging window inside '
        'the dark window (sunset → sunrise) with current settings. Try '
        'lowering the minimum altitude (currently '
        '${settings.minAltitudeDeg.toStringAsFixed(0)}°) or selecting '
        'different targets.',
      );
    }

    final warnings = <String>[];
    final autoDarksActive = settings.autoScheduleMissingDarks &&
        context.missingDarkRequirements.isNotEmpty;
    if (context.missingDarkLibraryNotes.isNotEmpty && !autoDarksActive) {
      warnings.add(
        'Dark library is missing matching frames for: '
        '${context.missingDarkLibraryNotes.join(", ")}. '
        'Smart Night does not auto-schedule dark capture — consider a '
        'cloudy night for a dark library run.',
      );
    } else if (autoDarksActive) {
      final framesPerCombo = math.max(1, settings.darkFramesPerRequirement);
      final totalFrames =
          context.missingDarkRequirements.length * framesPerCombo;
      warnings.add(
        'Dark library refresh scheduled — $totalFrames dark frames '
        '(${context.missingDarkRequirements.length} combinations × '
        '$framesPerCombo frames each) will be captured after lights '
        'because auto-schedule is enabled.',
      );
    }
    if (context.daysSinceLastPolarAlignment != null &&
        context.daysSinceLastPolarAlignment! >
            settings.polarAlignmentStaleAfterDays) {
      warnings.add(
        'Last polar alignment was '
        '${context.daysSinceLastPolarAlignment} days ago '
        '(threshold: ${settings.polarAlignmentStaleAfterDays} days). '
        'A polar alignment instruction has been prepended.',
      );
    }
    if (context.rainOrCloudProbability != null &&
        context.rainOrCloudProbability! > 0.4) {
      warnings.add(
        'Cloud / rain probability '
        '${(context.rainOrCloudProbability! * 100).toStringAsFixed(0)}% '
        'within tonight\'s window — a Cloud Arriving recovery node was '
        'added so the executor can safely park if the storm rolls in.',
      );
    }
    if (context.adaptiveExposuresRecommended) {
      warnings.add(
        'Sky brightness tracker reports your site is brighter than '
        'reference — adaptive exposures will be enabled on each target.',
      );
    }
    if (context.recentGuideRmsArcsec == null ||
        context.recentGuideSamples < 3) {
      warnings.add(
        'Mount guide-RMS history is sparse — exposure recommendations '
        'use the user cap rather than the mount-tracking ceiling. The '
        'ceiling becomes active after ~3 guided sessions on this mount.',
      );
    }

    final sequence = _emitSequence(
      profile: profile,
      strategy: strategy,
      settings: settings,
      context: context,
      planned: planned,
    );
    final simulation = const PreSessionSimulator().simulate(
      sequence,
      start: context.windowStart,
      latitude: latitudeDeg,
      longitude: longitudeDeg,
      minAltitude: settings.minAltitudeDeg,
      darkWindowStart: context.windowStart,
      darkWindowEnd: context.windowEnd,
    );
    for (final issue in simulation.issues) {
      if (!warnings.contains(issue.message)) {
        warnings.add(issue.message);
      }
    }

    final integrationSecs = planned.fold<double>(
      0,
      (sum, p) => sum + p.integrationSecs,
    );

    return SmartNightPlan(
      sequence: sequence,
      plannedTargets: planned,
      totalIntegrationSecs: integrationSecs,
      estimatedWallClockSecs: simulation.duration.inSeconds.toDouble(),
      warnings: warnings,
      strategy: strategy,
      settings: settings,
      context: context,
    );
  }

  /// Estimates per-target integration time for Plan Tonight without building
  /// a sequence. Returns null when the rig lacks the data Smart Night needs.
  TargetIntegrationPreview? previewTargetIntegration({
    required EquipmentProfileModel profile,
    required TargetSuggestion suggestion,
    required DateTime windowStart,
    required DateTime windowEnd,
    required List<String> availableFilters,
    SmartNightExposureContext? exposureContext,
    SmartNightSettings settings = const SmartNightSettings(),
    List<IntegrationGoalProgress>? integrationGoalProgress,
    SmartNightStrategy? strategy,
  }) {
    if (availableFilters.isEmpty) return null;

    final resolvedStrategy =
        strategy ?? inferSmartNightStrategy(suggestion, availableFilters);
    final activeFilters = _resolveFilterSet(
      strategy: resolvedStrategy,
      availableFilters: availableFilters,
    );
    if (activeFilters.isEmpty) return null;

    final pixelSizeUm =
        exposureContext?.pixelSizeMicrons ?? _pixelSize(profile);
    final focalLength = profile.focalLength > 0
        ? profile.focalLength
        : (exposureContext?.focalLengthMm ?? profile.telescopeFocalLength ?? 0);
    final aperture = profile.aperture > 0
        ? profile.aperture
        : (exposureContext?.apertureMm ?? profile.telescopeAperture ?? 0);
    final cameraSpec =
        exposureContext?.camera ?? _cameraSpecFromProfile(profile);

    if (focalLength <= 0 || aperture <= 0 || pixelSizeUm <= 0) {
      return null;
    }

    final usable = _usableTargetWindow(
      suggestion: suggestion,
      intervalStart: windowStart,
      intervalEnd: windowEnd,
      minAltitude: settings.minAltitudeDeg,
    );
    if (usable == null) return null;

    final intervalWindowSecs =
        usable.$2.difference(usable.$1).inSeconds.toDouble();
    final windowSecs = _integrationWindowSecs(
      suggestion: suggestion,
      intervalWindowSecs: intervalWindowSecs,
      integrationBudgetHours: null,
      settings: settings,
    );
    if (windowSecs <= 0) return null;

    final filterPlans = _composeFilterPlans(
      suggestion: suggestion,
      strategy: resolvedStrategy,
      activeFilters: activeFilters,
      windowSecs: windowSecs,
      profile: profile,
      cameraSpec: cameraSpec,
      focalLengthMm: focalLength,
      apertureMm: aperture,
      pixelSizeUm: pixelSizeUm,
      bortleClass: exposureContext?.bortleClass ?? 5,
      recentGuideRmsArcsec: exposureContext?.guideRmsArcsec,
      recentGuideSamples: exposureContext?.guideSampleCount ?? 0,
      settings: settings,
      integrationGoalProgress: integrationGoalProgress,
      availableFiltersForGoals: availableFilters,
    );
    if (filterPlans.isEmpty) return null;

    final integrationSecs = filterPlans.fold<double>(
      0,
      (sum, plan) => sum + plan.integrationSecs,
    );
    final usableWindowHours = (suggestion.visibility.hoursAboveMinAlt ??
            (windowSecs / 3600))
        .clamp(0.0, 24.0);

    return TargetIntegrationPreview(
      estimatedIntegrationHours: integrationSecs / 3600,
      usableWindowHours: usableWindowHours,
      subExposureSecs: filterPlans.first.durationSecs,
      filterNames: filterPlans.map((p) => p.filterName).toList(),
    );
  }

  /// Build a single-target sequence for Plan Tonight / dashboard "Add to
  /// Sequencer". Emits a TargetHeader sub-tree with SmartExposureNode filter
  /// rotation matching Smart Night per-target semantics.
  SingleTargetSequenceResult buildSingleTargetSequence({
    required EquipmentProfileModel profile,
    required TargetSuggestion suggestion,
    required DateTime windowStart,
    required DateTime windowEnd,
    required List<String> availableFilters,
    SmartNightExposureContext? exposureContext,
    SmartNightSettings settings = const SmartNightSettings(),
    SmartNightStrategy? strategy,
    double? integrationBudgetHours,
    List<IntegrationGoalProgress>? integrationGoalProgress,
    bool includeSessionPreamble = false,
  }) {
    if (availableFilters.isEmpty) {
      throw const SmartNightBuildException(
        'No filters configured on the equipment profile or connected filter '
        'wheel. Add filter names to your profile or connect a filter wheel '
        'before building a sequence.',
      );
    }

    final resolvedStrategy =
        strategy ?? inferSmartNightStrategy(suggestion, availableFilters);
    final activeFilters = _resolveFilterSet(
      strategy: resolvedStrategy,
      availableFilters: availableFilters,
    );
    if (activeFilters.isEmpty) {
      throw SmartNightBuildException(
        'No filters from strategy "${resolvedStrategy.name}" matched the '
        'available filter list (${availableFilters.join(", ")}).',
      );
    }

    final pixelSizeUm =
        exposureContext?.pixelSizeMicrons ?? _pixelSize(profile);
    final focalLength = profile.focalLength > 0
        ? profile.focalLength
        : (exposureContext?.focalLengthMm ?? profile.telescopeFocalLength ?? 0);
    final aperture = profile.aperture > 0
        ? profile.aperture
        : (exposureContext?.apertureMm ?? profile.telescopeAperture ?? 0);
    final cameraSpec =
        exposureContext?.camera ?? _cameraSpecFromProfile(profile);

    if (focalLength <= 0 || aperture <= 0 || pixelSizeUm <= 0) {
      throw SmartNightBuildException(
        'Equipment profile "${profile.name}" is missing aperture, focal '
        'length, or pixel size — these are required to compute exposure '
        'recommendations.',
      );
    }

    final usable = _usableTargetWindow(
      suggestion: suggestion,
      intervalStart: windowStart,
      intervalEnd: windowEnd,
      minAltitude: settings.minAltitudeDeg,
    );
    if (usable == null) {
      throw SmartNightBuildException(
        'Target "${suggestion.targetName}" has no usable imaging window '
        'between ${windowStart.toIso8601String()} and '
        '${windowEnd.toIso8601String()} at min altitude '
        '${settings.minAltitudeDeg.toStringAsFixed(0)}°.',
      );
    }

    final intervalWindowSecs =
        usable.$2.difference(usable.$1).inSeconds.toDouble();
    final windowSecs = _integrationWindowSecs(
      suggestion: suggestion,
      intervalWindowSecs: intervalWindowSecs,
      integrationBudgetHours: integrationBudgetHours,
      settings: settings,
    );

    final filterPlans = _composeFilterPlans(
      suggestion: suggestion,
      strategy: resolvedStrategy,
      activeFilters: activeFilters,
      windowSecs: windowSecs,
      profile: profile,
      cameraSpec: cameraSpec,
      focalLengthMm: focalLength,
      apertureMm: aperture,
      pixelSizeUm: pixelSizeUm,
      bortleClass: exposureContext?.bortleClass ?? 5,
      recentGuideRmsArcsec: exposureContext?.guideRmsArcsec,
      recentGuideSamples: exposureContext?.guideSampleCount ?? 0,
      settings: settings,
      integrationGoalProgress: integrationGoalProgress,
      availableFiltersForGoals: availableFilters,
    );
    if (filterPlans.isEmpty) {
      throw SmartNightBuildException(
        'Could not compose filter plans for "${suggestion.targetName}".',
      );
    }

    final integrationSecs = filterPlans.fold<double>(
      0,
      (sum, plan) => sum + plan.integrationSecs,
    );
    final actualEnd = usable.$1.add(
      Duration(seconds: integrationSecs.round()),
    );
    final clampedEnd = actualEnd.isBefore(usable.$2) ? actualEnd : usable.$2;

    final planned = SmartNightPlannedTarget(
      suggestion: suggestion,
      windowStart: usable.$1,
      windowEnd: clampedEnd,
      filterPlans: filterPlans,
      integrationSecs: integrationSecs,
      rationale: _composeTargetRationale(
        suggestion: suggestion,
        filterPlans: filterPlans,
        windowSecs: clampedEnd.difference(usable.$1).inSeconds.toDouble(),
      ),
    );

    final context = SmartNightContext(
      windowStart: usable.$1,
      windowEnd: clampedEnd,
      bortleClass: exposureContext?.bortleClass ?? 5,
      recentGuideRmsArcsec: exposureContext?.guideRmsArcsec,
      recentGuideSamples: exposureContext?.guideSampleCount ?? 0,
    );

    final sequence = _emitSingleTargetSequence(
      profile: profile,
      planned: planned,
      strategy: resolvedStrategy,
      settings: settings,
      context: context,
      includeSessionPreamble: includeSessionPreamble,
    );

    return SingleTargetSequenceResult(
      sequence: sequence,
      strategy: resolvedStrategy,
      filterPlans: filterPlans,
      plannedTarget: planned,
    );
  }

  /// Validate the hard requirements. Failing fast at the input boundary
  /// keeps the rest of the code free of "what if profile is null" branches.
  void _validateInputs({
    required EquipmentProfileModel profile,
    required double latitudeDeg,
    required double longitudeDeg,
    required List<TargetSuggestion> selectedSuggestions,
    required SmartNightContext context,
  }) {
    if (profile.name.trim().isEmpty) {
      throw const SmartNightBuildException(
        'No equipment profile selected — Smart Night needs to know which '
        'rig you\'re using so it can compose filter rotation, gain, and '
        'cooling sub-trees.',
      );
    }
    if (!latitudeDeg.isFinite ||
        !longitudeDeg.isFinite ||
        (latitudeDeg == 0.0 && longitudeDeg == 0.0)) {
      throw const SmartNightBuildException(
        'No observer location set — Smart Night needs your latitude / '
        'longitude to compute the dark window and target altitudes.',
      );
    }
    if (selectedSuggestions.isEmpty) {
      throw const SmartNightBuildException(
        'No targets selected — pick at least one target on step 3 or let '
        'Smart Night auto-select the top-scoring candidates.',
      );
    }
    if (!context.windowEnd.isAfter(context.windowStart)) {
      throw SmartNightBuildException(
        'Observation window is invalid: windowEnd '
        '(${context.windowEnd.toIso8601String()}) is not after '
        'windowStart (${context.windowStart.toIso8601String()}).',
      );
    }
  }

  DateTime _capWindowToMaxHours({
    required DateTime windowStart,
    required DateTime windowEnd,
    required double maxHours,
  }) {
    final maxEnd = windowStart.add(
      Duration(seconds: (maxHours * 3600).round()),
    );
    return maxEnd.isBefore(windowEnd) ? maxEnd : windowEnd;
  }

  double _pixelSize(EquipmentProfileModel profile) {
    // The DB-friendly EquipmentProfileModel doesn't carry pixel size
    // directly; we fall back to a typical CMOS pixel pitch when it's
    // missing. The exposure calculator will surface this in caveats.
    // 3.76µm is the canonical "ASI2600 / IMX571" pitch — a reasonable
    // mid-point until the user sets a real value in the bridge profile.
    return 3.76;
  }

  /// Map the strategy to the filter rotation that matters for this rig.
  List<String> _resolveFilterSet({
    required SmartNightStrategy strategy,
    required List<String> availableFilters,
  }) {
    return resolveSmartNightFilterSet(
      strategy: strategy,
      availableFilters: availableFilters,
    );
  }

  /// Compose per-filter plans — delegates to the public helper.
  List<SmartNightFilterPlan> _composeFilterPlans({
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
  }) {
    return composeSmartNightFilterPlans(
      suggestion: suggestion,
      strategy: strategy,
      activeFilters: activeFilters,
      windowSecs: windowSecs,
      profile: profile,
      cameraSpec: cameraSpec,
      focalLengthMm: focalLengthMm,
      apertureMm: apertureMm,
      pixelSizeUm: pixelSizeUm,
      bortleClass: bortleClass,
      recentGuideRmsArcsec: recentGuideRmsArcsec,
      recentGuideSamples: recentGuideSamples,
      settings: settings,
      integrationGoalProgress: integrationGoalProgress,
      availableFiltersForGoals: availableFiltersForGoals,
      exposureCalculator: _exposureCalculator,
    );
  }

  Sequence _emitSingleTargetSequence({
    required EquipmentProfileModel profile,
    required SmartNightPlannedTarget planned,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    required SmartNightContext context,
    required bool includeSessionPreamble,
  }) {
    final nodes = <String, SequenceNode>{};
    final childOrder = <String>[];
    final rootId = _uuid.v4();

    SequenceNode addRootChild(SequenceNode node) {
      childOrder.add(node.id);
      nodes[node.id] = node;
      return node;
    }

    if (includeSessionPreamble) {
      addRootChild(CoolCameraNode(
        id: _uuid.v4(),
        name: 'Cool camera to ${settings.coolDownTargetC.toStringAsFixed(0)}°C',
        targetTemp: settings.coolDownTargetC,
        durationMins: 10.0,
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
      addRootChild(UnparkNode(
        id: _uuid.v4(),
        name: 'Unpark mount',
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
    }

    final header = _emitTargetHeaderSubtree(
      profile: profile,
      planned: planned,
      strategy: strategy,
      settings: settings,
      context: context,
      nodesAccumulator: nodes,
    );
    final updatedHeader = header.copyWith(
      parentId: rootId,
      orderIndex: childOrder.length,
    );
    nodes[updatedHeader.id] = updatedHeader;
    childOrder.add(updatedHeader.id);

    if (includeSessionPreamble) {
      addRootChild(WarmCameraNode(
        id: _uuid.v4(),
        name: 'Warm camera',
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
      addRootChild(ParkNode(
        id: _uuid.v4(),
        name: 'Park mount',
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
    }

    final root = InstructionSetNode(
      id: rootId,
      name: '${planned.suggestion.targetName} Plan',
      childIds: childOrder,
    );
    nodes[rootId] = root;

    return Sequence.create(
      name: '${planned.suggestion.targetName} Plan',
      description: _composeSequenceDescription([planned], strategy, settings),
      nodes: nodes,
      rootNodeId: rootId,
    );
  }

  /// Build a CameraExposureSpec from the bundled hardware catalog. If the
  /// profile camera is unknown, fall back to the same conservative planning
  /// estimate used by the shared exposure context.
  CameraExposureSpec _cameraSpecFromProfile(EquipmentProfileModel profile) {
    final match = _hardwareSpecs.matchCamera(
      cameraName: profile.cameraName,
      cameraId: profile.cameraId,
      gain: profile.defaultGain,
    );
    if (match != null) return match.exposureSpec;

    // The EquipmentProfileModel doesn't carry per-gain noise data —
    // Unknown cameras use conservative fallback values below.
    return const CameraExposureSpec(
      readNoiseE: 3.5,
      fullWellE: 18000,
      qePeak: 0.65,
    );
  }

  /// Seconds of integration budget for one target: sampled time above
  /// [minAltitude] during tonight, capped by rise/set and optional budget.
  double _integrationWindowSecs({
    required TargetSuggestion suggestion,
    required double intervalWindowSecs,
    required double? integrationBudgetHours,
    required SmartNightSettings settings,
  }) {
    final sampledSecs =
        (suggestion.visibility.hoursAboveMinAlt ?? 0) * 3600;
    final naturalSecs = sampledSecs > 0
        ? math.min(sampledSecs, intervalWindowSecs)
        : intervalWindowSecs;
    final budgetSecs =
        (integrationBudgetHours ?? settings.defaultIntegrationBudgetHours) *
            3600;
    return math.min(naturalSecs, budgetSecs);
  }

  /// Compute the usable window inside `[intervalStart, intervalEnd]`
  /// where the target is above [minAltitude]. Returns null if the
  /// target never reaches that altitude during the interval.
  (DateTime, DateTime)? _usableTargetWindow({
    required TargetSuggestion suggestion,
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required double minAltitude,
  }) {
    final v = suggestion.visibility;
    final rise = v.riseTime;
    final set = v.setTime;
    DateTime usableStart = intervalStart;
    DateTime usableEnd = intervalEnd;
    if (rise != null && rise.isAfter(usableStart)) {
      usableStart = rise;
    }
    if (set != null && set.isBefore(usableEnd)) {
      usableEnd = set;
    }
    if (!usableStart.isBefore(usableEnd)) return null;
    final peakAlt = v.peakAltitude ?? v.currentAltitude;
    if (peakAlt < minAltitude) return null;
    return (usableStart, usableEnd);
  }

  String _composeTargetRationale({
    required TargetSuggestion suggestion,
    required List<SmartNightFilterPlan> filterPlans,
    required double windowSecs,
  }) {
    final hours = (windowSecs / 3600).toStringAsFixed(1);
    final filters = filterPlans.map((p) => p.filterName).join('+');
    final integrationHours =
        (filterPlans.fold<double>(0, (s, p) => s + p.integrationSecs) / 3600)
            .toStringAsFixed(1);
    return 'Selected ${suggestion.targetName} '
        '(score ${suggestion.totalScore.toStringAsFixed(0)}/100, '
        'window ${hours}h). '
        'Imaging $filters for ${integrationHours}h total.';
  }

  /// Compose the actual Sequence object — a complete tree the executor
  /// can run end-to-end:
  ///
  ///   Sequence
  ///   └─ InstructionSet root
  ///      ├─ CoolCamera
  ///      ├─ Unpark
  ///      ├─ PolarAlignment      (optional, only if stale)
  ///      ├─ [TargetScheduler | linear]
  ///      │  └─ TargetHeader … N
  ///      │     ├─ Slew + Center
  ///      │     ├─ StartGuiding
  ///      │     ├─ Autofocus (initial)
  ///      │     ├─ SmartExposure (per strategy filter rotation)
  ///      │     │   carries integration budget + AF cadence triggers
  ///      │     └─ MeridianFlip   (auto-enabled per profile setting)
  ///      ├─ Flats               (optional; cover calibrator path)
  ///      ├─ WarmCamera
  ///      ├─ Park
  ///      └─ WeatherRecovery     (parallel; optional)
  Sequence _emitSequence({
    required EquipmentProfileModel profile,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    required SmartNightContext context,
    required List<SmartNightPlannedTarget> planned,
  }) {
    final nodes = <String, SequenceNode>{};
    final childOrder = <String>[];

    final rootId = _uuid.v4();
    SequenceNode addRootChild(SequenceNode node) {
      childOrder.add(node.id);
      nodes[node.id] = node;
      return node;
    }

    // -- 1. Cool camera (always — needed before any imaging)
    addRootChild(CoolCameraNode(
      id: _uuid.v4(),
      name: 'Cool camera to ${settings.coolDownTargetC.toStringAsFixed(0)}°C',
      targetTemp: settings.coolDownTargetC,
      durationMins: 10.0,
      parentId: rootId,
      orderIndex: childOrder.length - 1,
    ));

    // -- 2. Unpark mount
    addRootChild(UnparkNode(
      id: _uuid.v4(),
      name: 'Unpark mount',
      parentId: rootId,
      orderIndex: childOrder.length - 1,
    ));

    // -- 3. Polar alignment if stale
    if (settings.prependPolarAlignmentIfStale &&
        context.daysSinceLastPolarAlignment != null &&
        context.daysSinceLastPolarAlignment! >
            settings.polarAlignmentStaleAfterDays) {
      addRootChild(PolarAlignmentNode(
        id: _uuid.v4(),
        name: 'Polar alignment '
            '(${context.daysSinceLastPolarAlignment} days since last)',
        startFromCurrent: true,
        isNorth: latitudeSign(profile),
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
    }

    // -- 4. Targets
    final targetHeaders = <TargetHeaderNode>[];
    for (final p in planned) {
      final targetHeader = _emitTargetHeaderSubtree(
        profile: profile,
        planned: p,
        strategy: strategy,
        settings: settings,
        context: context,
        nodesAccumulator: nodes,
      );
      targetHeaders.add(targetHeader);
    }
    if (targetHeaders.length > 1 &&
        settings.useSchedulerForMultiTarget &&
        targetHeaders.length >= settings.schedulerTargetThreshold) {
      // Wrap in a TargetSchedulerNode for >=3 targets so the executor
      // can swap between them based on score / altitude during the
      // night.
      final schedulerId = _uuid.v4();
      final scheduler = TargetSchedulerNode(
        id: schedulerId,
        name: 'Target scheduler (${targetHeaders.length} targets)',
        childIds: targetHeaders.map((h) => h.id).toList(),
        parentId: rootId,
        orderIndex: childOrder.length,
      );
      // Re-parent the headers to the scheduler.
      for (var i = 0; i < targetHeaders.length; i++) {
        final updated = targetHeaders[i].copyWith(
          parentId: schedulerId,
          orderIndex: i,
        );
        nodes[updated.id] = updated;
      }
      childOrder.add(schedulerId);
      nodes[schedulerId] = scheduler;
    } else {
      // Linear chain — append each TargetHeader directly under the root.
      for (var i = 0; i < targetHeaders.length; i++) {
        final updated = targetHeaders[i].copyWith(
          parentId: rootId,
          orderIndex: childOrder.length,
        );
        nodes[updated.id] = updated;
        childOrder.add(updated.id);
      }
    }

    // -- 5. Flats (if user has a cover calibrator AND opted in)
    if (settings.includeFlatsAtEnd && settings.hasCoverCalibrator) {
      final filtersForFlats = <String>{};
      for (final pt in planned) {
        for (final fp in pt.filterPlans) {
          filtersForFlats.add(fp.filterName);
        }
      }
      final flatGroupId = _uuid.v4();
      final flatGroup = InstructionSetNode(
        id: flatGroupId,
        name: 'Flats — ${filtersForFlats.length} filters',
        parentId: rootId,
        orderIndex: childOrder.length,
        childIds: const [],
      );
      final flatChildren = <SequenceNode>[];
      // CloseCover -> CalibratorOn(brightness) -> per-filter (Change +
      // Expose flat) -> CalibratorOff -> OpenCover keeps the executor's
      // existing "panel-based flats" path. The user can edit the
      // brightness / target ADU in the editor before run.
      flatChildren.add(CloseCoverNode(
        id: _uuid.v4(),
        name: 'Close cover',
        parentId: flatGroupId,
      ));
      flatChildren.add(CalibratorOnNode(
        id: _uuid.v4(),
        name: 'Calibrator on',
        brightness: 128,
        parentId: flatGroupId,
      ));
      for (final filter in filtersForFlats) {
        flatChildren.add(FilterChangeNode(
          id: _uuid.v4(),
          name: 'Change filter → $filter',
          filterName: filter,
          parentId: flatGroupId,
        ));
        flatChildren.add(ExposureNode(
          id: _uuid.v4(),
          name: 'Flats — $filter',
          durationSecs: 3.0,
          count: settings.flatCountPerFilter,
          frameType: FrameType.flat,
          filter: filter,
          gain: profile.defaultGain,
          offset: profile.defaultOffset,
          ditherEvery: 0, // no dither for flats
          parentId: flatGroupId,
        ));
      }
      flatChildren.add(CalibratorOffNode(
        id: _uuid.v4(),
        name: 'Calibrator off',
        parentId: flatGroupId,
      ));
      flatChildren.add(OpenCoverNode(
        id: _uuid.v4(),
        name: 'Open cover',
        parentId: flatGroupId,
      ));
      for (var i = 0; i < flatChildren.length; i++) {
        final reparented = _reparented(flatChildren[i], flatGroupId, i);
        nodes[reparented.id] = reparented;
      }
      nodes[flatGroupId] = flatGroup.copyWith(
        childIds: flatChildren.map((n) => n.id).toList(),
      );
      childOrder.add(flatGroupId);
    } else if (settings.includeFlatsAtEnd && !settings.hasCoverCalibrator) {
      // No panel → leave a NotificationNode reminder; we never schedule
      // unattended sky-flats. The user gets a heads-up at session end.
      addRootChild(NotificationNode(
        id: _uuid.v4(),
        name: 'Flats reminder',
        title: 'No flat panel detected',
        message: 'No flat panel detected — remember to shoot manual flats next '
            'session for this equipment profile.',
        level: NotificationLevel.info,
        explicitTransports: const [NotificationTransportKind.inApp],
        parentId: rootId,
        orderIndex: childOrder.length - 1,
      ));
    }

    // -- 5b. Dark Library Refresh (opt-in; only when settings flag set AND
    // structured requirements are present). The camera is still at its
    // cooling target at this point, which matches the lights' temperature
    // bucket — so the captured darks calibrate the lights we just shot.
    // Placed AFTER flats (when flats run) so the cover sequencing is
    // not interleaved, and BEFORE warm/park so the cooled sensor state
    // is preserved.
    if (settings.autoScheduleMissingDarks &&
        context.missingDarkRequirements.isNotEmpty) {
      final framesPerCombo = math.max(1, settings.darkFramesPerRequirement);
      final darkGroupId = _uuid.v4();
      final darkChildren = <SequenceNode>[];
      final coverAvailable = settings.hasCoverCalibrator;
      if (coverAvailable) {
        darkChildren.add(CloseCoverNode(
          id: _uuid.v4(),
          name: 'Close cover for darks',
          parentId: darkGroupId,
        ));
      } else {
        // No cover → the executor can't physically block light; emit a
        // notification so the user covers the OTA manually before the
        // dark run begins. We do NOT silently skip — capturing "darks"
        // with the sensor still seeing sky light would corrupt the
        // library.
        darkChildren.add(NotificationNode(
          id: _uuid.v4(),
          name: 'Cover OTA for darks',
          title: 'Cover the OTA',
          message: 'Dark library refresh is about to start. Cover the OTA '
              'to block all stray light before continuing — uncovered '
              '"darks" will corrupt the library.',
          level: NotificationLevel.warning,
          explicitTransports: const [NotificationTransportKind.inApp],
          parentId: darkGroupId,
        ));
      }
      for (final req in context.missingDarkRequirements) {
        final tempLabel = req.targetTemp == null
            ? 'any'
            : '${req.targetTemp!.toStringAsFixed(0)}°C';
        darkChildren.add(ExposureNode(
          id: _uuid.v4(),
          name: 'Darks — ${req.durationSecs.toStringAsFixed(0)}s '
              '@ G${req.gain} ($tempLabel, bin ${req.binX}x${req.binY})',
          durationSecs: req.durationSecs,
          count: framesPerCombo,
          frameType: FrameType.dark,
          gain: req.gain,
          offset: req.offset,
          binning: _binningModeForInt(req.binX),
          ditherEvery: 0,
          parentId: darkGroupId,
        ));
      }
      if (coverAvailable) {
        darkChildren.add(OpenCoverNode(
          id: _uuid.v4(),
          name: 'Open cover after darks',
          parentId: darkGroupId,
        ));
      }
      for (var i = 0; i < darkChildren.length; i++) {
        final reparented = _reparented(darkChildren[i], darkGroupId, i);
        nodes[reparented.id] = reparented;
      }
      final darkGroup = InstructionSetNode(
        id: darkGroupId,
        name: 'Dark Library Refresh — '
            '${context.missingDarkRequirements.length} combinations',
        parentId: rootId,
        orderIndex: childOrder.length,
        childIds: darkChildren.map((n) => n.id).toList(),
      );
      nodes[darkGroupId] = darkGroup;
      childOrder.add(darkGroupId);
    }

    // -- 6. Warm camera + park (always — clean shutdown)
    addRootChild(WarmCameraNode(
      id: _uuid.v4(),
      name: 'Warm camera',
      parentId: rootId,
      orderIndex: childOrder.length - 1,
    ));
    addRootChild(ParkNode(
      id: _uuid.v4(),
      name: 'Park mount',
      parentId: rootId,
      orderIndex: childOrder.length - 1,
    ));

    // -- 7. Weather recovery (optional, prepended as a sibling under
    // the root so the executor's parallel watchdog can interrupt the
    // imaging branch when the storm arrives).
    if (context.rainOrCloudProbability != null &&
        context.rainOrCloudProbability! > 0.4) {
      addRootChild(RecoveryNode(
        id: _uuid.v4(),
        name: 'Cloud arriving — auto-park',
        triggerType: TriggerType.weatherUnsafe,
        recoveryAction: RecoveryActionType.parkAndAbort,
        maxRetries: 1,
        parentId: rootId,
        orderIndex: childOrder.length - 1,
        comment: 'Cloud forecast probability '
            '${(context.rainOrCloudProbability! * 100).toStringAsFixed(0)}% '
            'within next ${context.cloudArrivalLeadTimeMinutes} min',
      ));
    }

    // Compose the root.
    final root = InstructionSetNode(
      id: rootId,
      name: 'Smart Night — '
          '${planned.map((p) => p.suggestion.targetName).join(", ")}',
      childIds: childOrder,
    );
    nodes[rootId] = root;

    return Sequence.create(
      name: _composeSequenceName(planned, strategy),
      description: _composeSequenceDescription(planned, strategy, settings),
      nodes: nodes,
      rootNodeId: rootId,
    );
  }

  /// Build the per-target sub-tree under a TargetHeaderNode and write
  /// each node into [nodesAccumulator]. Returns the header itself so
  /// the caller can re-parent it under the scheduler / root.
  TargetHeaderNode _emitTargetHeaderSubtree({
    required EquipmentProfileModel profile,
    required SmartNightPlannedTarget planned,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    required SmartNightContext context,
    required Map<String, SequenceNode> nodesAccumulator,
  }) {
    final headerId = _uuid.v4();
    final children = <SequenceNode>[];

    // 1. Slew to target
    children.add(SlewNode(
      id: _uuid.v4(),
      name: 'Slew → ${planned.suggestion.targetName}',
      useTargetCoords: true,
      parentId: headerId,
    ));

    // 2. Center via plate solve
    children.add(CenterNode(
      id: _uuid.v4(),
      name: 'Center via plate solve',
      accuracyArcsec: 5.0,
      maxAttempts: 5,
      useTargetCoords: true,
      parentId: headerId,
    ));

    // 3. Start guiding when profile has a guider and target is usable.
    if (_profileHasGuider(profile) &&
        (planned.suggestion.visibility.peakAltitude ??
                planned.suggestion.visibility.currentAltitude) >=
            settings.minAltitudeDeg) {
      children.add(StartGuidingNode(
        id: _uuid.v4(),
        name: 'Start guiding',
        autoSelectStar: true,
        parentId: headerId,
      ));
    }

    // 4. Initial autofocus
    children.add(AutofocusNode(
      id: _uuid.v4(),
      name: 'Initial autofocus',
      useSettingsDefaults: true,
      parentId: headerId,
    ));

    // 5. Smart Exposure — the heart of the night
    final smartExposure = _emitSmartExposure(
      planned: planned,
      settings: settings,
      context: context,
      parentId: headerId,
    );
    children.add(smartExposure);

    // 6. Optional meridian flip recovery — only inject when the target
    // crosses the meridian during its imaging window. The executor's
    // meridian-flip path is already enabled at the profile level; this
    // node makes the flip explicit on the timeline so Run Dashboard
    // shows it.
    final transit = planned.suggestion.visibility.transitTime;
    if (transit != null &&
        transit.isAfter(planned.windowStart) &&
        transit.isBefore(planned.windowEnd)) {
      children.add(MeridianFlipNode(
        id: _uuid.v4(),
        name: 'Meridian flip',
        autoCenter: true,
        refocusAfter: true,
        resumeGuiding: true,
        parentId: headerId,
        useGlobalDefaults: false,
      ));
    }

    final integrationSecsTotal = planned.filterPlans.fold<double>(
      0,
      (sum, fp) => sum + fp.integrationSecs,
    );
    final perFilterBudget = <String, FilterBudgetEntry>{
      for (final fp in planned.filterPlans)
        fp.filterName: FilterBudgetEntry.absolute(fp.integrationSecs),
    };
    final integrationBudget = IntegrationBudget(
      totalSecs: integrationSecsTotal,
      perFilter: perFilterBudget,
      stopOnBudgetMet: true,
    );

    final header = TargetHeaderNode(
      id: headerId,
      name: 'Target — ${planned.suggestion.targetName}',
      targetName: planned.suggestion.targetName,
      raHours: planned.suggestion.raHours,
      decDegrees: planned.suggestion.decDegrees,
      priority: 0,
      minAltitude: settings.minAltitudeDeg,
      startAfter: planned.windowStart,
      endBefore: planned.windowEnd,
      integrationBudget: integrationBudget,
      // Wave 4 start/end altitude crossings give the executor a real
      // gate to wait on. We add the altitude-above trigger as a soft
      // window override too — when minAltitude is exceeded the target
      // starts; when it dips below, it ends. The plan's wall-clock
      // bounds are also respected via startAfter / endBefore.
      startWhen: AltitudeAboveTrigger(settings.minAltitudeDeg),
      endWhen: AltitudeBelowTrigger(settings.minAltitudeDeg),
      childIds: children.map((c) => c.id).toList(),
    );

    for (var i = 0; i < children.length; i++) {
      final reparented = _reparented(children[i], headerId, i);
      nodesAccumulator[reparented.id] = reparented;
    }
    nodesAccumulator[headerId] = header;
    return header;
  }

  /// Build the SmartExposureNode for a target — rotates filters per
  /// the strategy, applies the AF cadence trigger, optionally toggles
  /// adaptive exposures, and clamps the total integration to the per-
  /// target budget.
  SmartExposureNode _emitSmartExposure({
    required SmartNightPlannedTarget planned,
    required SmartNightSettings settings,
    required SmartNightContext context,
    required String parentId,
  }) {
    final plans = planned.filterPlans.map((fp) {
      return FilterPlan(
        filterName: fp.filterName,
        count: fp.count,
        durationSecs: fp.durationSecs,
        ditherEvery: settings.ditherEveryFrames,
      );
    }).toList();
    return SmartExposureNode(
      id: _uuid.v4(),
      name: 'Smart Exposure — '
          '${planned.filterPlans.map((p) => p.filterName).join("+")}',
      plans: plans,
      rotateFilters: true,
      ditherOnFilterChange: false,
      integrationBudgetSecs: planned.integrationSecs,
      batchSize: 1,
      parentId: parentId,
    );
  }

  /// Re-parent a node and update its orderIndex. Uses copyWith so we
  /// stay polymorphic across SequenceNode subclasses.
  SequenceNode _reparented(SequenceNode node, String parentId, int orderIndex) {
    return node.copyWith(parentId: parentId, orderIndex: orderIndex);
  }

  /// Map a numeric binning factor (1..4) onto its [BinningMode] enum value.
  /// Used when materialising dark-library [DarkFrameRequirement]s into
  /// [ExposureNode]s — the requirement stores binX/binY as ints, the
  /// node stores a [BinningMode]. Anything outside 1..4 falls back to 1x1
  /// because the executor cannot drive non-square / >4× binning paths.
  BinningMode _binningModeForInt(int bin) {
    switch (bin) {
      case 2:
        return BinningMode.two;
      case 3:
        return BinningMode.three;
      case 4:
        return BinningMode.four;
      case 1:
      default:
        return BinningMode.one;
    }
  }

  String _composeSequenceName(
    List<SmartNightPlannedTarget> planned,
    SmartNightStrategy strategy,
  ) {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final names = planned.map((p) => p.suggestion.targetName).join(' · ');
    return 'Smart Night $dateStr — $names (${_strategyLabel(strategy)})';
  }

  String _composeSequenceDescription(
    List<SmartNightPlannedTarget> planned,
    SmartNightStrategy strategy,
    SmartNightSettings settings,
  ) {
    final integrationHours = planned.fold<double>(
          0,
          (s, p) => s + p.integrationSecs,
        ) /
        3600;
    final filters = planned
        .expand((p) => p.filterPlans.map((fp) => fp.filterName))
        .toSet()
        .toList();
    return 'Auto-built by Smart Night using the '
        '${_strategyLabel(strategy)} strategy. '
        '${planned.length} target(s), '
        '${integrationHours.toStringAsFixed(1)}h integration, '
        'filters: ${filters.join(", ")}. '
        'AF cadence: ${_afCadenceLabel(settings)}. '
        'Min altitude: ${settings.minAltitudeDeg.toStringAsFixed(0)}°.';
  }

  String _strategyLabel(SmartNightStrategy s) {
    switch (s) {
      case SmartNightStrategy.autoLrgb:
        return 'Auto-balance LRGB';
      case SmartNightStrategy.monoLrgb:
        return 'Mono LRGB';
      case SmartNightStrategy.narrowbandHoo:
        return 'Narrowband HOO';
      case SmartNightStrategy.narrowbandSho:
        return 'Narrowband SHO';
      case SmartNightStrategy.oscOneShot:
        return 'OSC One-Shot';
    }
  }

  String _afCadenceLabel(SmartNightSettings s) {
    switch (s.afCadence) {
      case SmartNightAfCadence.everyNFrames:
        return 'every ${s.afEveryFrames} frames';
      case SmartNightAfCadence.everyNMinutes:
        return 'every ${s.afEveryMinutes} min';
      case SmartNightAfCadence.onTempDelta:
        return 'on Δtemp ${s.afTempDeltaC.toStringAsFixed(1)}°C';
    }
  }
}

/// Northern hemisphere → true (PolarAlignmentNode.isNorth). Falls back
/// to true when no latitude info is on the profile (the user should
/// flip the toggle in the polar-alignment dialog anyway).
bool latitudeSign(EquipmentProfileModel profile) {
  // EquipmentProfileModel doesn't carry latitude — use a heuristic:
  // most installs are northern hemisphere. The polar-alignment dialog
  // also exposes a North/South toggle the user can flip on Step 5
  // before run.
  return true;
}
