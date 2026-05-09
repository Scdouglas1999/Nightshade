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

  /// Peak altitude during the night window (populated by scoreTargetForNight)
  final double? peakAltitude;

  /// Azimuth at peak altitude during the night (populated by scoreTargetForNight)
  final double? peakAzimuth;

  /// Time when peak altitude occurs during the night (populated by scoreTargetForNight)
  final DateTime? peakAltitudeTime;

  /// Hours the target is above minimum imaging altitude during the night
  final double? hoursAboveMinAlt;

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
    this.peakAltitude,
    this.peakAzimuth,
    this.peakAltitudeTime,
    this.hoursAboveMinAlt,
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

  /// Score a target based on the entire night window rather than a single moment.
  ///
  /// Samples the target's position at 15-minute intervals throughout the night
  /// (from [nightStart] to [nightEnd]) and scores based on peak conditions:
  /// - Altitude score uses the peak altitude during the night
  /// - Airmass score uses the best (lowest) airmass during the night
  /// - Transit proximity scores whether transit falls within the night window
  /// - Darkness score is replaced by imaging window duration
  /// - Moon distance is evaluated at the time of peak altitude
  ///
  /// Targets that never rise above [minAltitude] during the night receive a
  /// total score of 0.
  TargetScore scoreTargetForNight({
    required CelestialObject target,
    required DateTime nightStart,
    required DateTime nightEnd,
    double minAltitude = 0,
  }) {
    final coord = target.coordinates;
    final raDeg = coord.raDegrees;
    final decDeg = coord.dec;

    // Calculate current position (for display purposes)
    final (currentAlt, currentAz) = AstronomyCalculations.objectAltAz(
      raDeg: raDeg,
      decDeg: decDeg,
      dt: observationTime,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Sample positions throughout the night at 15-minute intervals
    const sampleInterval = Duration(minutes: 15);
    double peakAlt = -90;
    double peakAz = 0;
    DateTime peakTime = nightStart;
    double bestAirmass = double.infinity;
    int samplesAboveMin = 0;
    int totalSamples = 0;

    var sampleTime = nightStart;
    while (!sampleTime.isAfter(nightEnd)) {
      final (alt, az) = AstronomyCalculations.objectAltAz(
        raDeg: raDeg,
        decDeg: decDeg,
        dt: sampleTime,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );
      final am = AstronomyCalculations.airmass(alt);

      if (alt > peakAlt) {
        peakAlt = alt;
        peakAz = az;
        peakTime = sampleTime;
      }
      if (am < bestAirmass) {
        bestAirmass = am;
      }
      if (alt >= minAltitude) {
        samplesAboveMin++;
      }
      totalSamples++;

      sampleTime = sampleTime.add(sampleInterval);
    }

    final hoursAboveMin = totalSamples > 0
        ? (samplesAboveMin * sampleInterval.inMinutes / 60.0)
        : 0.0;

    // Calculate visibility (rise/transit/set) relative to the night's midpoint
    final nightMid = nightStart.add(
      Duration(
        seconds: nightEnd.difference(nightStart).inSeconds ~/ 2,
      ),
    );
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: raDeg,
      decDeg: decDeg,
      date: nightMid,
      latitudeDeg: latitude,
      longitudeDeg: longitude,
    );

    // Moon distance at peak altitude time
    double moonDist = 180;
    if (moonPosition != null) {
      moonDist = AstronomyCalculations.angularSeparation(
        ra1Deg: raDeg,
        dec1Deg: decDeg,
        ra2Deg: moonPosition!.$1,
        dec2Deg: moonPosition!.$2,
      );
    }

    // Current airmass (for display)
    final currentAirmass = AstronomyCalculations.airmass(currentAlt);

    // Create visibility info with both current and peak data
    final visibilityInfo = TargetVisibilityInfo(
      currentAltitude: currentAlt,
      currentAzimuth: currentAz,
      transitAltitude: visibility.transitAltitude,
      riseTime: visibility.riseTime,
      transitTime: visibility.transitTime,
      setTime: visibility.setTime,
      isCircumpolar: visibility.isCircumpolar,
      neverRises: visibility.neverRises,
      airmass: currentAirmass,
      moonDistance: moonDist,
      peakAltitude: peakAlt,
      peakAzimuth: peakAz,
      peakAltitudeTime: peakTime,
      hoursAboveMinAlt: hoursAboveMin,
    );

    // Calculate individual scores based on night conditions
    final altScore = _scoreAltitude(peakAlt);
    final moonScore = _scoreMoonDistance(moonDist, moonIllumination);
    final transitScore = _scoreTransitProximityForNight(
      visibility,
      nightStart,
      nightEnd,
    );
    final darknessScore = _scoreImagingWindow(
      hoursAboveMin,
      nightStart,
      nightEnd,
    );
    final airmassScore = _scoreAirmass(bestAirmass);

    // Generate warnings based on night conditions
    final warnings = _generateNightWarnings(
      peakAlt: peakAlt,
      bestAirmass: bestAirmass,
      moonDist: moonDist,
      visibility: visibility,
      hoursAboveMin: hoursAboveMin,
      nightStart: nightStart,
      nightEnd: nightEnd,
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

  /// Score transit proximity relative to the night window.
  ///
  /// Targets whose transit falls during the night score highest, with a bonus
  /// for transits near the middle of the night. Targets whose transit is just
  /// outside the night window still score moderately.
  double _scoreTransitProximityForNight(
    ObjectVisibility visibility,
    DateTime nightStart,
    DateTime nightEnd,
  ) {
    if (visibility.neverRises) return 0;
    if (visibility.transitTime == null) return 50;

    final transitTime = visibility.transitTime!;
    final nightMid = nightStart.add(
      Duration(
        seconds: nightEnd.difference(nightStart).inSeconds ~/ 2,
      ),
    );
    final halfNightMinutes = nightEnd.difference(nightStart).inMinutes / 2;

    // Is transit during the night?
    if (transitTime.isAfter(nightStart) && transitTime.isBefore(nightEnd)) {
      // Transit is during the night - score based on how centered it is
      final offsetFromMid = transitTime.difference(nightMid).inMinutes.abs();
      if (halfNightMinutes <= 0) return 100;
      final centeredness =
          1.0 - (offsetFromMid / halfNightMinutes).clamp(0.0, 1.0);
      return 70 + centeredness * 30; // 70-100 for transits during the night
    }

    // Transit is outside the night - score based on proximity to the window
    final minutesToStart = transitTime.difference(nightStart).inMinutes.abs();
    final minutesToEnd = transitTime.difference(nightEnd).inMinutes.abs();
    final closestMinutes =
        minutesToStart < minutesToEnd ? minutesToStart : minutesToEnd;

    if (closestMinutes < 60) return 60;
    if (closestMinutes < 120) return 40;
    if (closestMinutes < 240) return 20;
    return 10;
  }

  /// Score based on available imaging hours during the night.
  ///
  /// Replaces the real-time darkness check with a measure of how much of the
  /// night the target is above minimum altitude -- more useful for planning.
  double _scoreImagingWindow(
    double hoursAboveMin,
    DateTime nightStart,
    DateTime nightEnd,
  ) {
    final nightHours = nightEnd.difference(nightStart).inMinutes / 60.0;
    if (nightHours <= 0) return 10;
    if (hoursAboveMin <= 0) return 0;

    final fraction = (hoursAboveMin / nightHours).clamp(0.0, 1.0);

    if (fraction >= 0.8) return 100; // Available most of the night
    if (fraction >= 0.6) return 90;
    if (fraction >= 0.4) return 75;
    if (fraction >= 0.2) return 55;
    return 30;
  }

  /// Generate warnings based on conditions across the full night window.
  List<TargetWarning> _generateNightWarnings({
    required double peakAlt,
    required double bestAirmass,
    required double moonDist,
    required ObjectVisibility visibility,
    required double hoursAboveMin,
    required DateTime nightStart,
    required DateTime nightEnd,
  }) {
    final warnings = <TargetWarning>[];

    // Peak altitude warnings
    if (peakAlt < 0) {
      warnings.add(const TargetWarning(
        type: WarningType.belowHorizon,
        severity: WarningSeverity.critical,
        message: 'Below horizon all night',
        suggestion: 'Target is not visible during this night',
      ));
    } else if (peakAlt < 15) {
      warnings.add(TargetWarning(
        type: WarningType.lowAltitude,
        severity: WarningSeverity.warning,
        message:
            'Low peak altitude (${peakAlt.toStringAsFixed(0)}°) - poor seeing expected',
        suggestion: 'Consider imaging on a different night',
      ));
    } else if (peakAlt < 30) {
      warnings.add(TargetWarning(
        type: WarningType.lowAltitude,
        severity: WarningSeverity.caution,
        message: 'Moderate peak altitude (${peakAlt.toStringAsFixed(0)}°)',
        suggestion: visibility.transitAltitude != null
            ? 'Max altitude: ${visibility.transitAltitude?.toStringAsFixed(0)}°'
            : null,
      ));
    }

    // Airmass (best during the night)
    if (bestAirmass > 2.5 && bestAirmass.isFinite) {
      warnings.add(TargetWarning(
        type: WarningType.highAirmass,
        severity: WarningSeverity.warning,
        message:
            'Best airmass ${bestAirmass.toStringAsFixed(2)} - atmospheric extinction',
        suggestion: 'Image quality may be degraded all night',
      ));
    } else if (bestAirmass > 2.0 && bestAirmass.isFinite) {
      warnings.add(TargetWarning(
        type: WarningType.highAirmass,
        severity: WarningSeverity.caution,
        message: 'Elevated best airmass (${bestAirmass.toStringAsFixed(2)})',
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

    // Short imaging window
    final nightHours = nightEnd.difference(nightStart).inMinutes / 60.0;
    if (hoursAboveMin > 0 && hoursAboveMin < 2.0 && nightHours > 0) {
      warnings.add(TargetWarning(
        type: WarningType.settingSoon,
        severity: WarningSeverity.warning,
        message:
            'Short imaging window (${hoursAboveMin.toStringAsFixed(1)} hours)',
        suggestion: 'Limited time above minimum altitude tonight',
      ));
    } else if (hoursAboveMin >= 2.0 && hoursAboveMin < 4.0 && nightHours > 4) {
      warnings.add(TargetWarning(
        type: WarningType.settingSoon,
        severity: WarningSeverity.caution,
        message:
            'Moderate imaging window (${hoursAboveMin.toStringAsFixed(1)} hours)',
      ));
    }

    // Rises late in the night
    if (visibility.riseTime != null && peakAlt >= 0) {
      final riseTime = visibility.riseTime!;
      if (riseTime.isAfter(nightStart)) {
        final nightDuration = nightEnd.difference(nightStart);
        final riseOffset = riseTime.difference(nightStart);
        // If the target rises in the last third of the night
        if (riseOffset > nightDuration * 0.66) {
          warnings.add(TargetWarning(
            type: WarningType.notYetRisen,
            severity: WarningSeverity.info,
            message: 'Rises late at ${_formatTime(riseTime)}',
            suggestion: 'Target becomes available late in the night',
          ));
        }
      }
    }

    // Sets early in the night
    if (visibility.setTime != null && peakAlt >= 0) {
      final setTime = visibility.setTime!;
      if (setTime.isBefore(nightEnd) && setTime.isAfter(nightStart)) {
        final nightDuration = nightEnd.difference(nightStart);
        final setOffset = setTime.difference(nightStart);
        // If the target sets in the first third of the night
        if (setOffset < nightDuration * 0.33) {
          warnings.add(TargetWarning(
            type: WarningType.settingSoon,
            severity: WarningSeverity.caution,
            message: 'Sets early at ${_formatTime(setTime)}',
            suggestion: 'Image this target early in the session',
          ));
        }
      }
    }

    return warnings;
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
