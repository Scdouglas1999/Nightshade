import '../database/database.dart' as db;
import '../models/optical_config.dart';
import '../models/planning/target_suggestion.dart';
import 'target_suggestion_service.dart';

/// A concrete plan for the next imaging session.
class SessionOptimizationPlan {
  final DateTime generatedAt;
  final TargetSuggestion? primaryTarget;
  final List<TargetSuggestion> alternates;
  final double recommendedExposureSeconds;
  final double estimatedUsableHours;
  final List<String> rationale;
  final List<String> riskFactors;

  const SessionOptimizationPlan({
    required this.generatedAt,
    required this.primaryTarget,
    required this.alternates,
    required this.recommendedExposureSeconds,
    required this.estimatedUsableHours,
    required this.rationale,
    required this.riskFactors,
  });

  bool get hasRecommendation => primaryTarget != null;
}

/// Produces a session-ready plan from the nightly suggestion engine.
class SessionOptimizerService {
  final TargetSuggestionService _suggestionService;

  const SessionOptimizerService({
    required TargetSuggestionService suggestionService,
  }) : _suggestionService = suggestionService;

  Future<SessionOptimizationPlan> optimizeTonight({
    required TargetSuggestionConfig config,
    required double latitude,
    required double longitude,
    required List<db.Target> targets,
    required List<db.ImagingSession> sessions,
    DateTime? observationTime,
    OpticalConfig? opticalConfig,
  }) async {
    final generatedAt = observationTime ?? DateTime.now();
    final suggestions = await _suggestionService.getSuggestionsForTonight(
      config: config,
      latitude: latitude,
      longitude: longitude,
      targets: targets,
      sessions: sessions,
      observationTime: generatedAt,
      opticalConfig: opticalConfig,
    );

    return buildPlanFromSuggestions(
      suggestions,
      generatedAt: generatedAt,
    );
  }

  /// Builds a session-ready plan from already-computed target suggestions.
  ///
  /// This lets UI surfaces share the same suggestion pipeline, including
  /// catalog-backed targets and filters, without duplicating plan scoring.
  SessionOptimizationPlan buildPlanFromSuggestions(
    List<TargetSuggestion> suggestions, {
    DateTime? generatedAt,
  }) {
    final planGeneratedAt = generatedAt ?? DateTime.now();

    if (suggestions.isEmpty) {
      return SessionOptimizationPlan(
        generatedAt: planGeneratedAt,
        primaryTarget: null,
        alternates: const [],
        recommendedExposureSeconds: 0,
        estimatedUsableHours: 0,
        rationale: const ['No viable targets matched tonight\'s constraints.'],
        riskFactors: const [
          'Check location, horizon limits, and scoring constraints.',
        ],
      );
    }

    final primary = suggestions.first;
    final alternates = suggestions.skip(1).take(3).toList(growable: false);
    final estimatedUsableHours =
        (primary.visibility.hoursAboveMinAlt ?? 0).clamp(0.0, 24.0);

    final rationale = <String>[
      primary.reasoning,
      if (primary.dataProgress < 0.25)
        'Large unfinished dataset makes this an efficient completion target.',
      if (primary.tags.contains('Mosaic recommended'))
        'Optical framing suggests a mosaic-friendly target for tonight.',
      if ((primary.visibility.peakAltitude ??
              primary.visibility.currentAltitude) >=
          60)
        'Peak altitude is excellent, which reduces atmospheric penalty.',
    ];

    final riskFactors = <String>[
      for (final warning in primary.warnings.take(3)) warning.message,
      if ((primary.visibility.moonDistance) < 45)
        'Moon separation is tight; gradients or contrast loss are more likely.',
      if (estimatedUsableHours < 2.0)
        'Usable imaging window is short; prioritize quick setup and acquisition.',
      if (primary.dataProgress > 0.85)
        'Target is nearly complete; consider alternates if you want fresh integration.',
    ];

    return SessionOptimizationPlan(
      generatedAt: planGeneratedAt,
      primaryTarget: primary,
      alternates: alternates,
      recommendedExposureSeconds: _recommendExposureSeconds(primary),
      estimatedUsableHours: estimatedUsableHours,
      rationale: rationale,
      riskFactors: riskFactors.toSet().toList(growable: false),
    );
  }

  double _recommendExposureSeconds(TargetSuggestion suggestion) {
    final objectType = (suggestion.objectType ?? '').toLowerCase();
    final magnitude = suggestion.magnitude ?? 10.0;
    final moonDistance = suggestion.visibility.moonDistance;

    var exposure = 180.0;
    if (objectType.contains('nebula')) {
      exposure = 300.0;
    } else if (objectType.contains('galaxy')) {
      exposure = 240.0;
    } else if (objectType.contains('cluster') || objectType.contains('star')) {
      exposure = 120.0;
    }

    if (magnitude > 11.0) {
      exposure += 120.0;
    } else if (magnitude < 6.0) {
      exposure -= 30.0;
    }

    if (moonDistance < 45.0) {
      exposure = exposure.clamp(120.0, 240.0);
    }

    return exposure.clamp(60.0, 600.0);
  }
}
