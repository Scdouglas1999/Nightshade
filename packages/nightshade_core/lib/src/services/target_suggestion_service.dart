import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../database/database.dart';
import '../models/planning/target_suggestion.dart';
import 'logging_service.dart';

/// Service for generating target suggestions for tonight's imaging session.
///
/// Uses [TargetScoringService] from nightshade_planetarium to score targets
/// based on altitude, moon distance, transit proximity, darkness, and airmass.
/// Also factors in data collection progress to prioritize incomplete targets.
class TargetSuggestionService {
  final LoggingService _logging;

  static const String _source = 'TargetSuggestionService';

  /// Typical sub-exposure time in seconds for progress estimation.
  /// Used when calculating data progress from session integration time.
  static const double _typicalExposureSecs = 300.0;

  TargetSuggestionService({required LoggingService loggingService})
      : _logging = loggingService;

  /// Generate target suggestions for tonight based on current conditions.
  ///
  /// Parameters:
  /// - [config]: Configuration for filtering and sorting suggestions
  /// - [latitude]: Observer latitude in degrees
  /// - [longitude]: Observer longitude in degrees
  /// - [targets]: List of database targets to score
  /// - [sessions]: List of imaging sessions for progress calculation
  /// - [observationTime]: Time to calculate positions for (defaults to now)
  ///
  /// Returns a sorted list of [TargetSuggestion] objects matching the config criteria.
  Future<List<TargetSuggestion>> getSuggestionsForTonight({
    required TargetSuggestionConfig config,
    required double latitude,
    required double longitude,
    required List<Target> targets,
    required List<ImagingSession> sessions,
    DateTime? observationTime,
  }) async {
    final now = observationTime ?? DateTime.now();
    _logging.debug(
      'Generating suggestions for ${targets.length} targets at lat=$latitude, lon=$longitude',
      source: _source,
    );

    if (targets.isEmpty) {
      _logging.info('No targets provided for suggestion generation', source: _source);
      return [];
    }

    // Get moon position and illumination
    final moonPos = AstronomyCalculations.moonPosition(now);
    final moonRaDeg = moonPos.$1;
    final moonDecDeg = moonPos.$2;
    final moonIllumination = AstronomyCalculations.moonIllumination(now);

    _logging.debug(
      'Moon position: RA=${moonRaDeg.toStringAsFixed(2)}, Dec=${moonDecDeg.toStringAsFixed(2)}, '
      'illumination=${moonIllumination.toStringAsFixed(1)}%',
      source: _source,
    );

    // Get twilight times for today
    final twilight = AstronomyCalculations.calculateTwilightTimes(
      date: now,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    _logging.debug(
      'Twilight times - astro dusk: ${twilight.astronomicalDusk}, astro dawn: ${twilight.astronomicalDawn}',
      source: _source,
    );

    // Create the scoring service with current conditions
    final scoringService = TargetScoringService(
      latitude: latitude,
      longitude: longitude,
      observationTime: now,
      moonPosition: (moonRaDeg, moonDecDeg),
      moonIllumination: moonIllumination,
      twilight: twilight,
    );

    final suggestions = <TargetSuggestion>[];

    for (final target in targets) {
      // Convert database target to CelestialObject for scoring
      final celestialObj = _targetToCelestialObject(target);

      // Score the target
      final score = scoringService.scoreTarget(celestialObj);

      // Skip targets below horizon
      if (score.visibility.currentAltitude < 0) {
        _logging.debug(
          'Skipping ${target.name}: below horizon (${score.visibility.currentAltitude.toStringAsFixed(1)}°)',
          source: _source,
        );
        continue;
      }

      // Skip targets below minimum altitude
      if (score.visibility.currentAltitude < config.minAltitude) {
        _logging.debug(
          'Skipping ${target.name}: altitude ${score.visibility.currentAltitude.toStringAsFixed(1)}° '
          'below minimum ${config.minAltitude}°',
          source: _source,
        );
        continue;
      }

      // Skip targets below minimum score
      if (score.totalScore < config.minScore) {
        _logging.debug(
          'Skipping ${target.name}: score ${score.totalScore.toStringAsFixed(1)} '
          'below minimum ${config.minScore}',
          source: _source,
        );
        continue;
      }

      // Filter by preferred object types if specified
      if (config.preferredObjectTypes.isNotEmpty) {
        final objectType = target.objectType?.toLowerCase() ?? '';
        final matches = config.preferredObjectTypes.any(
          (type) => objectType.contains(type.toLowerCase()),
        );
        if (!matches) {
          _logging.debug(
            'Skipping ${target.name}: object type "$objectType" not in preferred types',
            source: _source,
          );
          continue;
        }
      }

      // Calculate data progress
      final dataProgress = _calculateDataProgress(target.id, target, sessions);

      // Generate human-readable reasoning
      final reasoning = _generateReasoning(score, dataProgress);

      // Build score breakdown map
      final scoreBreakdown = <String, double>{
        'altitude': score.altitudeScore,
        'moonDistance': score.moonDistanceScore,
        'transitProximity': score.transitProximityScore,
        'darkness': score.darknessScore,
        'airmass': score.airmassScore,
      };

      final suggestion = TargetSuggestion(
        targetId: target.id,
        targetName: target.name,
        catalogId: target.catalogId,
        raHours: target.ra,
        decDegrees: target.dec,
        totalScore: score.totalScore,
        scoreBreakdown: scoreBreakdown,
        warnings: score.warnings,
        visibility: score.visibility,
        reasoning: reasoning,
        dataProgress: dataProgress,
        objectType: target.objectType,
        magnitude: target.magnitude,
        sizeArcmin: target.sizeArcmin,
        constellation: target.constellation,
      );

      suggestions.add(suggestion);
    }

    _logging.info(
      'Generated ${suggestions.length} suggestions from ${targets.length} targets',
      source: _source,
    );

    // Sort by configured mode
    _sortSuggestions(suggestions, config.sortMode, config.prioritizeIncomplete);

    return suggestions;
  }

  /// Convert a database Target to a CelestialObject for scoring.
  CelestialObject _targetToCelestialObject(Target target) {
    // Target.ra is in decimal hours, Target.dec is in decimal degrees
    final coordinate = CelestialCoordinate(
      ra: target.ra,
      dec: target.dec,
    );

    // Determine DSO type from object type string
    final dsoType = _parseDsoType(target.objectType);

    return DeepSkyObject(
      id: target.id.toString(),
      name: target.name,
      coordinates: coordinate,
      type: dsoType,
      magnitude: target.magnitude,
      sizeArcMin: target.sizeArcmin,
      constellation: target.constellation,
      catalogIds: target.catalogId != null ? [target.catalogId!] : [],
    );
  }

  /// Parse object type string to DsoType enum.
  DsoType _parseDsoType(String? objectType) {
    if (objectType == null || objectType.isEmpty) {
      return DsoType.other;
    }

    final type = objectType.toLowerCase();

    if (type.contains('galaxy')) return DsoType.galaxy;
    if (type.contains('nebula')) {
      if (type.contains('planetary')) return DsoType.planetaryNebula;
      if (type.contains('emission')) return DsoType.emissionNebula;
      if (type.contains('reflection')) return DsoType.reflectionNebula;
      if (type.contains('dark')) return DsoType.darkNebula;
      return DsoType.nebula;
    }
    if (type.contains('cluster')) {
      if (type.contains('globular')) return DsoType.globularCluster;
      if (type.contains('open')) return DsoType.openCluster;
      return DsoType.openCluster;
    }
    if (type.contains('hii') || type.contains('h ii')) return DsoType.hiiRegion;
    if (type.contains('supernova')) return DsoType.supernova;
    if (type.contains('star')) return DsoType.star;

    return DsoType.other;
  }

  /// Calculate data collection progress for a target.
  ///
  /// Returns a value from 0.0 (no data) to 1.0 (complete).
  double _calculateDataProgress(
    int targetId,
    Target target,
    List<ImagingSession> sessions,
  ) {
    // Sum total integration time from all sessions for this target
    double totalIntegrationSecs = 0;
    for (final session in sessions) {
      if (session.targetId == targetId) {
        totalIntegrationSecs += session.totalIntegrationSecs;
      }
    }

    // Also include any integration time already stored on the target itself
    totalIntegrationSecs += target.totalIntegrationSecs;

    // Calculate expected total integration time
    final plannedSubs = target.totalPlannedSubs;
    if (plannedSubs <= 0) {
      // If no planned subs, we can't calculate progress
      // Return 0 if no data, or a small value if we have some data
      if (totalIntegrationSecs > 0) {
        // We have data but no plan - show as partially complete
        return 0.1; // 10% to indicate some data exists
      }
      return 0.0;
    }

    final expectedTotalSecs = plannedSubs * _typicalExposureSecs;
    final progress = totalIntegrationSecs / expectedTotalSecs;

    // Clamp to 0-1 range
    return progress.clamp(0.0, 1.0);
  }

  /// Generate a human-readable reasoning string for the suggestion.
  String _generateReasoning(TargetScore score, double dataProgress) {
    final parts = <String>[];

    // Altitude assessment
    final alt = score.visibility.currentAltitude;
    if (alt >= 60) {
      parts.add('Excellent altitude (${alt.toStringAsFixed(0)}°)');
    } else if (alt >= 45) {
      parts.add('High altitude (${alt.toStringAsFixed(0)}°)');
    } else if (alt >= 30) {
      parts.add('Good altitude (${alt.toStringAsFixed(0)}°)');
    } else {
      parts.add('Low altitude (${alt.toStringAsFixed(0)}°)');
    }

    // Moon distance
    final moonDist = score.visibility.moonDistance;
    if (moonDist >= 90) {
      parts.add('far from moon (${moonDist.toStringAsFixed(0)}°)');
    } else if (moonDist >= 60) {
      parts.add('good moon distance (${moonDist.toStringAsFixed(0)}°)');
    } else if (moonDist >= 30) {
      parts.add('moon nearby (${moonDist.toStringAsFixed(0)}°)');
    } else {
      parts.add('close to moon (${moonDist.toStringAsFixed(0)}°)');
    }

    // Transit proximity
    final transitTime = score.visibility.transitTime;
    if (transitTime != null) {
      final minutesToTransit = transitTime.difference(DateTime.now()).inMinutes;
      if (minutesToTransit.abs() < 60) {
        parts.add('near transit');
      } else if (minutesToTransit > 0 && minutesToTransit < 180) {
        parts.add('transits in ${(minutesToTransit / 60).toStringAsFixed(1)}h');
      }
    }

    // Build first sentence
    var reasoning = parts.join(', ');
    if (reasoning.isNotEmpty) {
      reasoning = '${reasoning[0].toUpperCase()}${reasoning.substring(1)}.';
    }

    // Data progress
    if (dataProgress > 0) {
      final pct = (dataProgress * 100).toStringAsFixed(0);
      reasoning += ' $pct% of planned data collected.';
    } else {
      reasoning += ' No data collected yet.';
    }

    // Add warning summary if any significant warnings
    final criticalWarnings = score.warnings
        .where((w) => w.severity == WarningSeverity.critical || w.severity == WarningSeverity.warning)
        .toList();
    if (criticalWarnings.isNotEmpty) {
      final warningMsg = criticalWarnings.first.message;
      reasoning += ' Note: $warningMsg';
    }

    return reasoning;
  }

  /// Sort suggestions according to the configured mode.
  void _sortSuggestions(
    List<TargetSuggestion> suggestions,
    SuggestionSortMode sortMode,
    bool prioritizeIncomplete,
  ) {
    suggestions.sort((a, b) {
      // If prioritizing incomplete, put targets with less data first
      if (prioritizeIncomplete) {
        // Only prioritize if one is significantly more complete than the other
        if ((a.dataProgress - b.dataProgress).abs() > 0.2) {
          // Less complete targets get priority
          final progressComparison = a.dataProgress.compareTo(b.dataProgress);
          if (progressComparison != 0) {
            return progressComparison;
          }
        }
      }

      // Then apply the configured sort mode
      switch (sortMode) {
        case SuggestionSortMode.bestScore:
          return b.totalScore.compareTo(a.totalScore);

        case SuggestionSortMode.highestAltitude:
          return b.visibility.currentAltitude.compareTo(a.visibility.currentAltitude);

        case SuggestionSortMode.nearestTransit:
          final aTransit = a.visibility.transitTime;
          final bTransit = b.visibility.transitTime;
          if (aTransit == null && bTransit == null) return 0;
          if (aTransit == null) return 1;
          if (bTransit == null) return -1;
          final now = DateTime.now();
          return aTransit.difference(now).inMinutes.abs().compareTo(
                bTransit.difference(now).inMinutes.abs(),
              );

        case SuggestionSortMode.leastDataCollected:
          return a.dataProgress.compareTo(b.dataProgress);
      }
    });
  }
}
