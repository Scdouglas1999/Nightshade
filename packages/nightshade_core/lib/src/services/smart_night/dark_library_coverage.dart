import '../../models/calibration/dark_library_match_tolerances.dart';
import '../../providers/profiles_provider.dart' show EquipmentProfileModel;
import '../dark_library_coverage_service.dart';
import '../dark_library_service.dart';
import '../session_optimizer_service.dart' show SmartNightExposureContext;
import '../smart_night_service.dart';

/// Builds Smart Night dark-library requirements from the same strategy and
/// exposure recommendation inputs used by the sequence builder.
class SmartNightDarkLibraryCoverage {
  final DarkLibraryService darkLibraryService;
  final DarkLibraryCoverageService coverageService;

  const SmartNightDarkLibraryCoverage({
    required this.darkLibraryService,
    this.coverageService = const DarkLibraryCoverageService(),
  });

  /// Convenience wrapper that returns only the human-readable warning
  /// strings — retained for callers that just want to surface a soft
  /// warning. Use [missing] when you also need the structured
  /// requirements (e.g. to opt in to auto-scheduling dark capture).
  Future<List<String>> missingNotes({
    required EquipmentProfileModel profile,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    required SmartNightExposureContext exposureContext,
    required int minCoverage,
    DarkLibraryMatchTolerances tolerances =
        DarkLibraryMatchTolerances.defaults,
  }) async {
    final result = await missing(
      profile: profile,
      strategy: strategy,
      settings: settings,
      exposureContext: exposureContext,
      minCoverage: minCoverage,
      tolerances: tolerances,
    );
    return result.notes;
  }

  /// Compute both the structured [DarkFrameRequirement]s missing from
  /// the library AND the human-readable note strings, sharing the same
  /// underlying coverage evaluation so the two views never disagree.
  Future<SmartNightDarkLibraryMissing> missing({
    required EquipmentProfileModel profile,
    required SmartNightStrategy strategy,
    required SmartNightSettings settings,
    required SmartNightExposureContext exposureContext,
    required int minCoverage,
    DarkLibraryMatchTolerances tolerances =
        DarkLibraryMatchTolerances.defaults,
  }) async {
    final filters = resolveSmartNightFilterSet(
      strategy: strategy,
      availableFilters: profile.filterNames,
    );
    if (filters.isEmpty) return const SmartNightDarkLibraryMissing.empty();

    final targetTemp = profile.defaultCoolingTemp ?? settings.coolDownTargetC;
    final requirements = filters.map((filter) {
      final recommendation = exposureContext.recommendForFilter(filter);
      return DarkFrameRequirement(
        gain: profile.defaultGain ?? 0,
        offset: profile.defaultOffset ?? 0,
        durationSecs: recommendation.seconds,
        binX: profile.defaultBinX,
        binY: profile.defaultBinY,
        targetTemp: targetTemp,
      );
    }).toSet();

    final report = coverageService.evaluate(
      requirements: requirements,
      entries: await darkLibraryService.getAllEntries(),
      minCoverage: minCoverage,
      tolerances: tolerances,
    );
    if (report.isCovered) return const SmartNightDarkLibraryMissing.empty();

    final notes = <String>[
      for (final req in report.missing) req.describe(),
      for (final entry in report.underCovered.entries)
        '${entry.key.describe()} (${entry.value} of $minCoverage raw darks)',
    ];
    notes.sort();
    final missingRequirements = <DarkFrameRequirement>[
      ...report.missing,
      ...report.underCovered.keys,
    ];
    return SmartNightDarkLibraryMissing(
      notes: List.unmodifiable(notes),
      requirements: List.unmodifiable(missingRequirements),
    );
  }
}

/// Pair of (notes, requirements) returned by
/// [SmartNightDarkLibraryCoverage.missing]. The two views are computed
/// from the same coverage evaluation so they stay in sync.
class SmartNightDarkLibraryMissing {
  final List<String> notes;
  final List<DarkFrameRequirement> requirements;

  const SmartNightDarkLibraryMissing({
    required this.notes,
    required this.requirements,
  });

  const SmartNightDarkLibraryMissing.empty()
      : notes = const [],
        requirements = const [];

  bool get isEmpty => notes.isEmpty && requirements.isEmpty;
}
