import '../astronomy/astronomy_calculations.dart';
import '../celestial_object.dart';

/// Scoring criteria weights for target prioritization
class ScoringWeights {
  final double altitudeWeight;
  final double moonDistanceWeight;
  final double transitProximityWeight;
  final double darknessWeight;
  final double airmassWeight;

  const ScoringWeights({
    this.altitudeWeight = 0.25,
    this.moonDistanceWeight = 0.25,
    this.transitProximityWeight = 0.20,
    this.darknessWeight = 0.15,
    this.airmassWeight = 0.15,
  });
}

/// Result of scoring a target
class TargetScore {
  final CelestialObject target;
  final double totalScore; // 0-100
  final double altitudeScore;
  final double moonDistanceScore;
  final double transitProximityScore;
  final double darknessScore;
  final double airmassScore;
  final List<TargetWarning> warnings;
  final TargetVisibilityInfo visibility;

  const TargetScore({
    required this.target,
    required this.totalScore,
    required this.altitudeScore,
    required this.moonDistanceScore,
    required this.transitProximityScore,
    required this.darknessScore,
    required this.airmassScore,
    required this.warnings,
    required this.visibility,
  });
}

/// Target visibility information
class TargetVisibilityInfo {
  final double currentAltitude;
  final double currentAzimuth;
  final double? transitAltitude;
  final DateTime? riseTime;
  final DateTime? transitTime;
  final DateTime? setTime;
  final bool isCircumpolar;
  final bool neverRises;
  final double airmass;
  final double moonDistance;

  const TargetVisibilityInfo({
    required this.currentAltitude,
    required this.currentAzimuth,
    this.transitAltitude,
    this.riseTime,
    this.transitTime,
    this.setTime,
    this.isCircumpolar = false,
    this.neverRises = false,
    required this.airmass,
    required this.moonDistance,
  });
}

/// Warning types for targets
enum WarningType {
  lowAltitude,
  highAirmass,
  moonProximity,
  settingSoon,
  notYetRisen,
  belowHorizon,
  twilight,
}

/// Warning severity levels
enum WarningSeverity {
  info,
  caution,
  warning,
  critical,
}

/// A warning about target conditions
class TargetWarning {
  final WarningType type;
  final WarningSeverity severity;
  final String message;
  final String? suggestion;

  const TargetWarning({
    required this.type,
    required this.severity,
    required this.message,
    this.suggestion,
  });
}

/// Service for scoring and analyzing imaging targets
class TargetScoringService {
  final double latitude;
  final double longitude;
  final DateTime observationTime;
  final ScoringWeights weights;

  // Moon position (ra, dec in degrees)
  final (double ra, double dec)? moonPosition;
  final double moonIllumination;

  // Twilight info
  final TwilightTimes? twilight;

  const TargetScoringService({
    required this.latitude,
    required this.longitude,
    required this.observationTime,
    this.weights = const ScoringWeights(),
    this.moonPosition,
    this.moonIllumination = 0,
    this.twilight,
  });

  /// Score a single target
  TargetScore scoreTarget(CelestialObject target) {
    final coord = target.coordinates;
    final raDeg = coord.raDegrees;
    final decDeg = coord.dec;

    // Calculate current position
    final (alt, az) = AstronomyCalculations.objectAltAz(
      raDeg: raDeg,
      decDeg: decDeg,
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Calculate visibility
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: raDeg,
      decDeg: decDeg,
      date: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Calculate airmass
    final airmass = AstronomyCalculations.airmass(alt);

    // Calculate moon distance
    double moonDist = 180;
    if (moonPosition != null) {
      moonDist = AstronomyCalculations.angularSeparation(
        ra1Deg: raDeg,
        dec1Deg: decDeg,
        ra2Deg: moonPosition!.$1,
        dec2Deg: moonPosition!.$2,
      );
    }

    // Create visibility info
    final visibilityInfo = TargetVisibilityInfo(
      currentAltitude: alt,
      currentAzimuth: az,
      transitAltitude: visibility.transitAltitude,
      riseTime: visibility.riseTime,
      transitTime: visibility.transitTime,
      setTime: visibility.setTime,
      isCircumpolar: visibility.isCircumpolar,
      neverRises: visibility.neverRises,
      airmass: airmass,
      moonDistance: moonDist,
    );

    // Calculate individual scores (0-100)
    final altScore = _scoreAltitude(alt);
    final moonScore = _scoreMoonDistance(moonDist, moonIllumination);
    final transitScore = _scoreTransitProximity(visibility, observationTime);
    final darknessScore = _scoreDarkness();
    final airmassScore = _scoreAirmass(airmass);

    // Generate warnings
    final warnings = _generateWarnings(
      alt: alt,
      airmass: airmass,
      moonDist: moonDist,
      visibility: visibility,
    );

    // Calculate weighted total score
    final totalScore = (altScore * weights.altitudeWeight +
            moonScore * weights.moonDistanceWeight +
            transitScore * weights.transitProximityWeight +
            darknessScore * weights.darknessWeight +
            airmassScore * weights.airmassWeight) /
        (weights.altitudeWeight +
            weights.moonDistanceWeight +
            weights.transitProximityWeight +
            weights.darknessWeight +
            weights.airmassWeight);

    return TargetScore(
      target: target,
      totalScore: totalScore,
      altitudeScore: altScore,
      moonDistanceScore: moonScore,
      transitProximityScore: transitScore,
      darknessScore: darknessScore,
      airmassScore: airmassScore,
      warnings: warnings,
      visibility: visibilityInfo,
    );
  }

  /// Score multiple targets and return sorted by score
  List<TargetScore> scoreTargets(List<CelestialObject> targets) {
    final scores = targets.map((t) => scoreTarget(t)).toList();
    scores.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return scores;
  }

  /// Get the best targets above a minimum score threshold
  List<TargetScore> getBestTargets(
    List<CelestialObject> targets, {
    double minScore = 50,
    int maxResults = 10,
  }) {
    return scoreTargets(targets)
        .where((s) => s.totalScore >= minScore)
        .take(maxResults)
        .toList();
  }

  double _scoreAltitude(double altitude) {
    if (altitude < 0) return 0;
    if (altitude < 15) return altitude * 2; // 0-30 for 0-15°
    if (altitude < 30) return 30 + (altitude - 15) * 2; // 30-60 for 15-30°
    if (altitude < 60) return 60 + (altitude - 30) * 1.33; // 60-100 for 30-60°
    return 100; // Above 60° is perfect
  }

  double _scoreMoonDistance(double distance, double illumination) {
    // Moon distance matters more when moon is bright
    final moonFactor = illumination / 100;

    if (illumination < 10) {
      // New moon - distance doesn't matter much
      return 90 + (distance / 180) * 10;
    }

    // Scale by illumination
    final minGoodDist = 30 + (70 * moonFactor); // 30-100° depending on moon

    if (distance >= minGoodDist) return 100;
    if (distance < 10) return 10 * (1 - moonFactor * 0.8);

    return (distance / minGoodDist) * 100;
  }

  double _scoreTransitProximity(ObjectVisibility visibility, DateTime time) {
    if (visibility.neverRises) return 0;
    if (visibility.transitTime == null) return 50; // Unknown

    final minutesToTransit =
        visibility.transitTime!.difference(time).inMinutes.abs();

    // Best score when close to transit (within 2 hours)
    if (minutesToTransit < 30) return 100;
    if (minutesToTransit < 60) return 90;
    if (minutesToTransit < 120) return 80;
    if (minutesToTransit < 240) return 60;
    if (minutesToTransit < 360) return 40;
    return 20;
  }

  double _scoreDarkness() {
    if (twilight == null) return 70; // Unknown

    // Best during astronomical darkness
    if (twilight!.astronomicalDusk != null &&
        twilight!.astronomicalDawn != null) {
      if (observationTime.isAfter(twilight!.astronomicalDusk!) &&
          observationTime.isBefore(twilight!.astronomicalDawn!)) {
        return 100; // Full darkness
      }
    }

    // During nautical twilight
    if (twilight!.nauticalDusk != null && twilight!.nauticalDawn != null) {
      if (observationTime.isAfter(twilight!.nauticalDusk!) &&
          observationTime.isBefore(twilight!.nauticalDawn!)) {
        return 70;
      }
    }

    // During civil twilight
    if (twilight!.civilDusk != null && twilight!.civilDawn != null) {
      if (observationTime.isAfter(twilight!.civilDusk!) &&
          observationTime.isBefore(twilight!.civilDawn!)) {
        return 40;
      }
    }

    // Daytime
    return 10;
  }

  double _scoreAirmass(double airmass) {
    if (airmass.isInfinite) return 0;
    if (airmass <= 1.0) return 100;
    if (airmass <= 1.5) return 90;
    if (airmass <= 2.0) return 70;
    if (airmass <= 2.5) return 50;
    if (airmass <= 3.0) return 30;
    return 10;
  }

  List<TargetWarning> _generateWarnings({
    required double alt,
    required double airmass,
    required double moonDist,
    required ObjectVisibility visibility,
  }) {
    final warnings = <TargetWarning>[];

    // Below horizon
    if (alt < 0) {
      warnings.add(TargetWarning(
        type: WarningType.belowHorizon,
        severity: WarningSeverity.critical,
        message: 'Target is below the horizon (${alt.toStringAsFixed(1)}°)',
        suggestion: visibility.riseTime != null
            ? 'Will rise at ${_formatTime(visibility.riseTime!)}'
            : null,
      ));
    }
    // Very low altitude
    else if (alt < 15) {
      warnings.add(TargetWarning(
        type: WarningType.lowAltitude,
        severity: WarningSeverity.warning,
        message: 'Low altitude (${alt.toStringAsFixed(1)}°) - poor seeing expected',
        suggestion: 'Consider waiting for higher altitude',
      ));
    }
    // Low altitude
    else if (alt < 30) {
      warnings.add(TargetWarning(
        type: WarningType.lowAltitude,
        severity: WarningSeverity.caution,
        message: 'Moderate altitude (${alt.toStringAsFixed(1)}°)',
        suggestion: visibility.transitTime != null
            ? 'Best at transit: ${visibility.transitAltitude?.toStringAsFixed(0)}°'
            : null,
      ));
    }

    // High airmass
    if (airmass > 2.5 && airmass.isFinite) {
      warnings.add(TargetWarning(
        type: WarningType.highAirmass,
        severity: WarningSeverity.warning,
        message: 'High airmass (${airmass.toStringAsFixed(2)}) - atmospheric extinction',
        suggestion: 'Image quality may be degraded',
      ));
    } else if (airmass > 2.0 && airmass.isFinite) {
      warnings.add(TargetWarning(
        type: WarningType.highAirmass,
        severity: WarningSeverity.caution,
        message: 'Elevated airmass (${airmass.toStringAsFixed(2)})',
      ));
    }

    // Moon proximity
    if (moonIllumination > 20) {
      if (moonDist < 15) {
        warnings.add(TargetWarning(
          type: WarningType.moonProximity,
          severity: WarningSeverity.critical,
          message:
              'Very close to Moon (${moonDist.toStringAsFixed(0)}°) - ${moonIllumination.toStringAsFixed(0)}% illuminated',
          suggestion: 'Consider narrowband filters or a different target',
        ));
      } else if (moonDist < 30 && moonIllumination > 50) {
        warnings.add(TargetWarning(
          type: WarningType.moonProximity,
          severity: WarningSeverity.warning,
          message:
              'Near bright Moon (${moonDist.toStringAsFixed(0)}°) - ${moonIllumination.toStringAsFixed(0)}% illuminated',
          suggestion: 'Use narrowband filters to reduce sky glow',
        ));
      } else if (moonDist < 45 && moonIllumination > 70) {
        warnings.add(TargetWarning(
          type: WarningType.moonProximity,
          severity: WarningSeverity.caution,
          message: 'Moon is ${moonDist.toStringAsFixed(0)}° away',
          suggestion: 'Some sky glow may be present',
        ));
      }
    }

    // Setting soon
    if (visibility.setTime != null && alt > 0) {
      final minutesToSet =
          visibility.setTime!.difference(observationTime).inMinutes;
      if (minutesToSet > 0 && minutesToSet < 60) {
        warnings.add(TargetWarning(
          type: WarningType.settingSoon,
          severity: WarningSeverity.warning,
          message: 'Setting in ${minutesToSet} minutes',
          suggestion: 'Start imaging soon or wait for tomorrow',
        ));
      } else if (minutesToSet > 0 && minutesToSet < 120) {
        warnings.add(TargetWarning(
          type: WarningType.settingSoon,
          severity: WarningSeverity.caution,
          message: 'Setting in ${(minutesToSet / 60).toStringAsFixed(1)} hours',
        ));
      }
    }

    // Not yet risen
    if (alt < 0 && visibility.riseTime != null) {
      final minutesToRise =
          visibility.riseTime!.difference(observationTime).inMinutes;
      if (minutesToRise > 0) {
        warnings.add(TargetWarning(
          type: WarningType.notYetRisen,
          severity: WarningSeverity.info,
          message: 'Rises in ${(minutesToRise / 60).toStringAsFixed(1)} hours',
        ));
      }
    }

    // Check if during twilight
    if (twilight != null) {
      final inAstroDark = (twilight!.astronomicalDusk != null &&
              twilight!.astronomicalDawn != null &&
              observationTime.isAfter(twilight!.astronomicalDusk!) &&
              observationTime.isBefore(twilight!.astronomicalDawn!));

      if (!inAstroDark) {
        final inNautical = (twilight!.nauticalDusk != null &&
            twilight!.nauticalDawn != null &&
            observationTime.isAfter(twilight!.nauticalDusk!) &&
            observationTime.isBefore(twilight!.nauticalDawn!));

        if (inNautical) {
          warnings.add(const TargetWarning(
            type: WarningType.twilight,
            severity: WarningSeverity.caution,
            message: 'Nautical twilight - not fully dark',
            suggestion: 'Wait for astronomical darkness for best results',
          ));
        } else {
          final inCivil = (twilight!.civilDusk != null &&
              twilight!.civilDawn != null &&
              observationTime.isAfter(twilight!.civilDusk!) &&
              observationTime.isBefore(twilight!.civilDawn!));

          if (inCivil) {
            warnings.add(const TargetWarning(
              type: WarningType.twilight,
              severity: WarningSeverity.warning,
              message: 'Civil twilight - sky is still bright',
              suggestion: 'Use for flats or calibration only',
            ));
          }
        }
      }
    }

    return warnings;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Quick helper methods for common checks
extension TargetCheckExtensions on TargetScoringService {
  /// Check if a target is currently observable (above horizon, reasonable altitude)
  bool isObservable(CelestialObject target, {double minAltitude = 15}) {
    final (alt, _) = AstronomyCalculations.objectAltAz(
      raDeg: target.coordinates.raDegrees,
      decDeg: target.coordinates.dec,
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );
    return alt >= minAltitude;
  }

  /// Get moon distance in degrees
  double getMoonDistance(CelestialObject target) {
    if (moonPosition == null) return 180;
    return AstronomyCalculations.angularSeparation(
      ra1Deg: target.coordinates.raDegrees,
      dec1Deg: target.coordinates.dec,
      ra2Deg: moonPosition!.$1,
      dec2Deg: moonPosition!.$2,
    );
  }

  /// Check if moon is too close (returns true if problematic)
  bool isMoonTooClose(CelestialObject target, {double minDistance = 30}) {
    if (moonIllumination < 20) return false; // New moon is fine
    final dist = getMoonDistance(target);
    // Adjust minimum distance based on moon brightness
    final adjustedMin = minDistance * (moonIllumination / 100);
    return dist < adjustedMin;
  }
}
