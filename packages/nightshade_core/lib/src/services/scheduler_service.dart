import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sequence/sequence_models.dart';

/// Provider for the scheduler service
final schedulerServiceProvider = Provider<SchedulerService>((ref) {
  return SchedulerService(ref);
});

/// Result of altitude calculation for a target
class AltitudeData {
  final String targetId;
  final String targetName;
  final double raHours;
  final double decDegrees;
  final DateTime transitTime;
  final double transitAltitude;
  final double currentAltitude;
  final bool isRising;
  final DateTime? riseTime;
  final DateTime? setTime;
  final double hoursAboveHorizon;

  AltitudeData({
    required this.targetId,
    required this.targetName,
    required this.raHours,
    required this.decDegrees,
    required this.transitTime,
    required this.transitAltitude,
    required this.currentAltitude,
    required this.isRising,
    this.riseTime,
    this.setTime,
    required this.hoursAboveHorizon,
  });
}

/// Optimization strategy for target ordering
enum OptimizationStrategy {
  transitTime,      // Order by when targets cross meridian
  currentAltitude,  // Order by current altitude (highest first for setting targets)
  risingFirst,      // Image rising targets first
  settingFirst,     // Image setting targets first
  priority,         // Use user-defined priorities
}

/// Service for intelligent target scheduling
class SchedulerService {
  final Ref _ref;

  SchedulerService(this._ref);

  /// Calculate altitude for a celestial object at a given time
  ///
  /// Uses standard spherical astronomy formulas
  double calculateAltitude({
    required double raHours,
    required double decDegrees,
    required DateTime time,
    required double latitudeDegrees,
    required double longitudeDegrees,
  }) {
    // Convert to radians
    final dec = decDegrees * math.pi / 180.0;
    final lat = latitudeDegrees * math.pi / 180.0;

    // Calculate Local Sidereal Time
    final lst = _calculateLST(time, longitudeDegrees);

    // Hour Angle = LST - RA
    final ha = (lst - raHours) * 15.0 * math.pi / 180.0; // Convert to radians

    // Calculate altitude using spherical formula
    // sin(alt) = sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(ha)
    final sinAlt = math.sin(dec) * math.sin(lat) +
                   math.cos(dec) * math.cos(lat) * math.cos(ha);

    final altitude = math.asin(sinAlt.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    return altitude;
  }

  /// Calculate Local Sidereal Time in hours
  double _calculateLST(DateTime utcTime, double longitudeDegrees) {
    // Calculate Julian Date
    final jd = _julianDate(utcTime);

    // Calculate centuries since J2000.0
    final t = (jd - 2451545.0) / 36525.0;

    // Greenwich Mean Sidereal Time at 0h UT1
    double gmst = 280.46061837 +
                  360.98564736629 * (jd - 2451545.0) +
                  0.000387933 * t * t -
                  t * t * t / 38710000.0;

    // Normalize to 0-360
    gmst = gmst % 360.0;
    if (gmst < 0) gmst += 360.0;

    // Convert to hours and add longitude
    double lst = gmst / 15.0 + longitudeDegrees / 15.0;

    // Normalize to 0-24
    while (lst < 0) lst += 24.0;
    while (lst >= 24) lst -= 24.0;

    return lst;
  }

  /// Calculate Julian Date from DateTime
  double _julianDate(DateTime dt) {
    final utc = dt.toUtc();
    int y = utc.year;
    int m = utc.month;
    final d = utc.day +
              utc.hour / 24.0 +
              utc.minute / 1440.0 +
              utc.second / 86400.0;

    if (m <= 2) {
      y -= 1;
      m += 12;
    }

    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();

    return (365.25 * (y + 4716)).floor() +
           (30.6001 * (m + 1)).floor() +
           d + b - 1524.5;
  }

  /// Calculate transit time for a target
  DateTime calculateTransitTime({
    required double raHours,
    required DateTime date,
    required double longitudeDegrees,
  }) {
    // Transit occurs when hour angle = 0, i.e., LST = RA
    // We need to find the time when this occurs

    // Start at midnight UTC on the given date
    final midnight = DateTime.utc(date.year, date.month, date.day);

    // Calculate LST at midnight
    final lstMidnight = _calculateLST(midnight, longitudeDegrees);

    // Time until transit in sidereal hours
    double hoursUntilTransit = raHours - lstMidnight;
    if (hoursUntilTransit < 0) hoursUntilTransit += 24.0;
    if (hoursUntilTransit > 24) hoursUntilTransit -= 24.0;

    // Convert sidereal time to solar time (sidereal day is ~23h 56m 4s)
    final solarHours = hoursUntilTransit * 0.9972695663;

    return midnight.add(Duration(
      hours: solarHours.floor(),
      minutes: ((solarHours % 1) * 60).floor(),
      seconds: (((solarHours * 60) % 1) * 60).floor(),
    ));
  }

  /// Get altitude data for all targets in the sequence
  List<AltitudeData> calculateTargetAltitudes({
    required List<TargetGroupNode> targets,
    required DateTime observationTime,
    required double latitudeDegrees,
    required double longitudeDegrees,
    double minAltitude = 0.0,
  }) {
    final results = <AltitudeData>[];

    for (final target in targets) {
      final currentAlt = calculateAltitude(
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        time: observationTime,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: longitudeDegrees,
      );

      // Check altitude 10 minutes later to determine if rising or setting
      final futureAlt = calculateAltitude(
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        time: observationTime.add(const Duration(minutes: 10)),
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: longitudeDegrees,
      );

      final isRising = futureAlt > currentAlt;

      final transitTime = calculateTransitTime(
        raHours: target.raHours,
        date: observationTime,
        longitudeDegrees: longitudeDegrees,
      );

      final transitAlt = calculateAltitude(
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        time: transitTime,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: longitudeDegrees,
      );

      // Calculate approximate rise/set times and hours above horizon
      final hoursAbove = _calculateHoursAboveHorizon(
        decDegrees: target.decDegrees,
        latitudeDegrees: latitudeDegrees,
        minAltitude: minAltitude,
      );

      results.add(AltitudeData(
        targetId: target.id,
        targetName: target.targetName,
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        transitTime: transitTime,
        transitAltitude: transitAlt,
        currentAltitude: currentAlt,
        isRising: isRising,
        hoursAboveHorizon: hoursAbove,
      ));
    }

    return results;
  }

  /// Calculate hours above minimum altitude
  double _calculateHoursAboveHorizon({
    required double decDegrees,
    required double latitudeDegrees,
    required double minAltitude,
  }) {
    // Use spherical trig to calculate hour angle at horizon
    final dec = decDegrees * math.pi / 180.0;
    final lat = latitudeDegrees * math.pi / 180.0;
    final alt = minAltitude * math.pi / 180.0;

    // cos(H) = (sin(alt) - sin(dec) * sin(lat)) / (cos(dec) * cos(lat))
    final cosH = (math.sin(alt) - math.sin(dec) * math.sin(lat)) /
                 (math.cos(dec) * math.cos(lat));

    if (cosH <= -1.0) {
      // Circumpolar - always visible
      return 24.0;
    } else if (cosH >= 1.0) {
      // Never rises above minimum altitude
      return 0.0;
    }

    // Hour angle at rise/set
    final hourAngle = math.acos(cosH) * 180.0 / math.pi / 15.0; // Convert to hours
    return hourAngle * 2.0; // Total hours above horizon
  }

  /// Optimize target order based on selected strategy
  List<TargetGroupNode> optimizeTargetOrder({
    required List<TargetGroupNode> targets,
    required OptimizationStrategy strategy,
    required DateTime observationTime,
    required double latitudeDegrees,
    required double longitudeDegrees,
    double minAltitude = 30.0,
  }) {
    if (targets.isEmpty) return [];

    final altitudeData = calculateTargetAltitudes(
      targets: targets,
      observationTime: observationTime,
      latitudeDegrees: latitudeDegrees,
      longitudeDegrees: longitudeDegrees,
      minAltitude: minAltitude,
    );

    // Create a map for quick lookup
    final dataMap = <String, AltitudeData>{};
    for (final data in altitudeData) {
      dataMap[data.targetId] = data;
    }

    final sortedTargets = List<TargetGroupNode>.from(targets);

    switch (strategy) {
      case OptimizationStrategy.transitTime:
        // Sort by transit time (earliest first)
        sortedTargets.sort((a, b) {
          final dataA = dataMap[a.id]!;
          final dataB = dataMap[b.id]!;
          return dataA.transitTime.compareTo(dataB.transitTime);
        });
        break;

      case OptimizationStrategy.currentAltitude:
        // Sort by current altitude (highest first for setting, lowest first for rising)
        sortedTargets.sort((a, b) {
          final dataA = dataMap[a.id]!;
          final dataB = dataMap[b.id]!;

          // Setting targets should be imaged first (higher altitude first)
          if (!dataA.isRising && !dataB.isRising) {
            return dataB.currentAltitude.compareTo(dataA.currentAltitude);
          }
          // Rising targets can wait (lower altitude first, as they're getting higher)
          if (dataA.isRising && dataB.isRising) {
            return dataA.currentAltitude.compareTo(dataB.currentAltitude);
          }
          // Setting targets before rising targets
          if (!dataA.isRising) return -1;
          return 1;
        });
        break;

      case OptimizationStrategy.risingFirst:
        // Image rising targets first
        sortedTargets.sort((a, b) {
          final dataA = dataMap[a.id]!;
          final dataB = dataMap[b.id]!;
          if (dataA.isRising == dataB.isRising) {
            // Within same category, sort by altitude
            return dataA.currentAltitude.compareTo(dataB.currentAltitude);
          }
          return dataA.isRising ? -1 : 1;
        });
        break;

      case OptimizationStrategy.settingFirst:
        // Image setting targets first (they're going below horizon)
        sortedTargets.sort((a, b) {
          final dataA = dataMap[a.id]!;
          final dataB = dataMap[b.id]!;
          if (dataA.isRising == dataB.isRising) {
            // Within same category, setting: highest first; rising: lowest first
            if (!dataA.isRising) {
              return dataB.currentAltitude.compareTo(dataA.currentAltitude);
            }
            return dataA.currentAltitude.compareTo(dataB.currentAltitude);
          }
          return dataA.isRising ? 1 : -1;
        });
        break;

      case OptimizationStrategy.priority:
        // Use user-defined priorities
        sortedTargets.sort((a, b) => a.priority.compareTo(b.priority));
        break;
    }

    return sortedTargets;
  }

  /// Calculate moon position (simplified)
  ({double raHours, double decDegrees, double illumination}) calculateMoonPosition(DateTime time) {
    // Simplified lunar ephemeris
    final jd = _julianDate(time);
    final t = (jd - 2451545.0) / 36525.0;

    // Mean longitude of moon
    final l = (218.3164477 + 481267.88123421 * t) % 360.0;

    // Mean elongation of moon
    final d = (297.8501921 + 445267.1114034 * t) % 360.0;

    // Sun's mean anomaly
    final m = (357.5291092 + 35999.0502909 * t) % 360.0;

    // Moon's mean anomaly
    final mp = (134.9633964 + 477198.8675055 * t) % 360.0;

    // Simplified calculation for RA and Dec
    final lRad = l * math.pi / 180.0;
    final dRad = d * math.pi / 180.0;
    final mpRad = mp * math.pi / 180.0;

    // Approximate ecliptic longitude
    final lambda = l + 6.289 * math.sin(mpRad);
    final lambdaRad = lambda * math.pi / 180.0;

    // Ecliptic latitude (simplified)
    final beta = 5.128 * math.sin(mpRad);
    final betaRad = beta * math.pi / 180.0;

    // Obliquity of ecliptic
    const epsilon = 23.439;
    final epsRad = epsilon * math.pi / 180.0;

    // Convert to equatorial coordinates
    final ra = math.atan2(
      math.sin(lambdaRad) * math.cos(epsRad) - math.tan(betaRad) * math.sin(epsRad),
      math.cos(lambdaRad),
    );
    final dec = math.asin(
      math.sin(betaRad) * math.cos(epsRad) + math.cos(betaRad) * math.sin(epsRad) * math.sin(lambdaRad),
    );

    // Convert RA to hours (0-24)
    var raHours = (ra * 180.0 / math.pi) / 15.0;
    if (raHours < 0) raHours += 24.0;

    // Calculate illumination (simplified, based on phase angle)
    final illumination = (1.0 - math.cos(dRad * math.pi / 180.0)) / 2.0;

    return (
      raHours: raHours,
      decDegrees: dec * 180.0 / math.pi,
      illumination: illumination,
    );
  }

  /// Calculate angular separation between two celestial objects
  double calculateSeparation({
    required double ra1Hours,
    required double dec1Degrees,
    required double ra2Hours,
    required double dec2Degrees,
  }) {
    final ra1 = ra1Hours * 15.0 * math.pi / 180.0;
    final ra2 = ra2Hours * 15.0 * math.pi / 180.0;
    final dec1 = dec1Degrees * math.pi / 180.0;
    final dec2 = dec2Degrees * math.pi / 180.0;

    // Haversine formula
    final cosSep = math.sin(dec1) * math.sin(dec2) +
                   math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);

    return math.acos(cosSep.clamp(-1.0, 1.0)) * 180.0 / math.pi;
  }

  /// Check if target is too close to moon
  bool isNearMoon({
    required double targetRaHours,
    required double targetDecDegrees,
    required DateTime time,
    double minSeparationDegrees = 30.0,
  }) {
    final moon = calculateMoonPosition(time);
    final separation = calculateSeparation(
      ra1Hours: targetRaHours,
      dec1Degrees: targetDecDegrees,
      ra2Hours: moon.raHours,
      dec2Degrees: moon.decDegrees,
    );
    return separation < minSeparationDegrees;
  }
}
