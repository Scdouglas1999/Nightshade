import 'dart:math' as math;

import '../../models/weather/weather_models.dart';

/// Analyzes cloud motion from radar frame sequences to predict movement
/// patterns and estimate time of arrival at user location.
class CloudMotionAnalyzer {
  /// Earth's mean radius in kilometers
  static const double _earthRadiusKm = 6371.0;

  /// Minimum number of frames required for motion analysis
  static const int _minFramesRequired = 2;

  /// Default spacing between analysis grid points in kilometers
  static const double _defaultGridSpacingKm = 10.0;

  /// Minimum cloud density threshold (opacity) to consider as significant
  static const double _defaultDensityThreshold = 0.3;

  /// Maximum reasonable cloud speed in km/h for sanity checks
  static const double _maxReasonableSpeedKmh = 200.0;

  /// Analyze cloud motion from a sequence of radar frames.
  ///
  /// Returns [CloudMotion] with speed, direction, and ETA to user location,
  /// or null if insufficient data or no clouds detected.
  ///
  /// Parameters:
  /// - [frames]: List of radar frames in chronological order (minimum 2)
  /// - [userLatitude]: User's latitude in degrees
  /// - [userLongitude]: User's longitude in degrees
  /// - [analysisRadiusKm]: Radius around user to analyze (default 100 km)
  CloudMotion? analyzeMotion({
    required List<RadarFrame> frames,
    required double userLatitude,
    required double userLongitude,
    double analysisRadiusKm = 100.0,
  }) {
    // Validate input
    if (frames.length < _minFramesRequired) {
      return null;
    }

    // Sort frames by timestamp to ensure chronological order
    final sortedFrames = List<RadarFrame>.from(frames)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Find nearest cloud mass in the most recent frame
    final cloudMassResult = findNearestCloudMass(
      frames: sortedFrames,
      userLatitude: userLatitude,
      userLongitude: userLongitude,
    );

    if (cloudMassResult == null) {
      // No significant clouds detected
      return null;
    }

    final (cloudLat, cloudLon, cloudDistance) = cloudMassResult;

    // Track cloud centroid movement across frames
    final motionVectors = <_MotionVector>[];

    for (int i = 1; i < sortedFrames.length; i++) {
      final prevFrame = sortedFrames[i - 1];
      final currentFrame = sortedFrames[i];

      // Find cloud centroids for both frames
      final prevCentroid = _findCloudCentroid(
        frame: prevFrame,
        centerLat: userLatitude,
        centerLon: userLongitude,
        radiusKm: analysisRadiusKm,
      );

      final currentCentroid = _findCloudCentroid(
        frame: currentFrame,
        centerLat: userLatitude,
        centerLon: userLongitude,
        radiusKm: analysisRadiusKm,
      );

      if (prevCentroid != null && currentCentroid != null) {
        final timeDiff = currentFrame.timestamp.difference(prevFrame.timestamp);
        if (timeDiff.inSeconds > 0) {
          final distance = calculateDistance(
            prevCentroid.$1,
            prevCentroid.$2,
            currentCentroid.$1,
            currentCentroid.$2,
          );
          final direction = calculateBearing(
            prevCentroid.$1,
            prevCentroid.$2,
            currentCentroid.$1,
            currentCentroid.$2,
          );
          final speedKmh = (distance / timeDiff.inSeconds) * 3600.0;

          // Sanity check: ignore unrealistic speeds
          if (speedKmh <= _maxReasonableSpeedKmh) {
            motionVectors.add(_MotionVector(
              speedKmh: speedKmh,
              directionDegrees: direction,
            ));
          }
        }
      }
    }

    if (motionVectors.isEmpty) {
      return null;
    }

    // Average the motion vectors to smooth out noise
    final avgSpeed = motionVectors.map((v) => v.speedKmh).reduce((a, b) => a + b) /
        motionVectors.length;

    // Average direction using circular mean to handle 0/360 wraparound
    final avgDirection = _averageDirection(
      motionVectors.map((v) => v.directionDegrees).toList(),
    );

    // Calculate ETA if clouds are approaching
    final eta = calculateEta(
      cloudDistanceKm: cloudDistance,
      cloudSpeedKmh: avgSpeed,
      cloudDirectionDeg: avgDirection,
      userLatitude: userLatitude,
      userLongitude: userLongitude,
      cloudLatitude: cloudLat,
      cloudLongitude: cloudLon,
    );

    return CloudMotion(
      speedKmh: avgSpeed,
      directionDegrees: avgDirection,
      etaToLocation: eta,
      distanceKm: cloudDistance,
      calculatedAt: DateTime.now(),
    );
  }

  /// Find the nearest significant cloud mass to user location.
  ///
  /// Returns (latitude, longitude, distanceKm) or null if no significant
  /// clouds detected within analysis area.
  ///
  /// Uses the most recent non-forecast frame for analysis.
  (double lat, double lon, double distance)? findNearestCloudMass({
    required List<RadarFrame> frames,
    required double userLatitude,
    required double userLongitude,
    double densityThreshold = _defaultDensityThreshold,
  }) {
    if (frames.isEmpty) {
      return null;
    }

    // Use the most recent frame, preferring non-forecast data
    final sortedFrames = List<RadarFrame>.from(frames)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final recentFrame = sortedFrames.firstWhere(
      (f) => !f.isForecast,
      orElse: () => sortedFrames.first,
    );

    // Sample grid points in a circular pattern around user
    final gridPoints = _generateGridPoints(
      centerLat: userLatitude,
      centerLon: userLongitude,
      radiusKm: 100.0,
      spacingKm: _defaultGridSpacingKm,
    );

    // Find grid points with significant cloud density
    final cloudPoints = <({double lat, double lon, double distance})>[];

    for (final point in gridPoints) {
      // Use frame opacity as proxy for cloud density
      // In real implementation, would fetch and analyze tile pixels
      final density = _estimateCloudDensity(recentFrame, point.$1, point.$2);

      if (density >= densityThreshold) {
        final distance = calculateDistance(
          userLatitude,
          userLongitude,
          point.$1,
          point.$2,
        );
        cloudPoints.add((lat: point.$1, lon: point.$2, distance: distance));
      }
    }

    if (cloudPoints.isEmpty) {
      return null;
    }

    // Return the nearest cloud point
    cloudPoints.sort((a, b) => a.distance.compareTo(b.distance));
    final nearest = cloudPoints.first;
    return (nearest.lat, nearest.lon, nearest.distance);
  }

  /// Calculate estimated time of arrival for clouds at user location.
  ///
  /// Returns null if clouds are moving away, stationary, or not approaching
  /// the user's location.
  Duration? calculateEta({
    required double cloudDistanceKm,
    required double cloudSpeedKmh,
    required double cloudDirectionDeg,
    required double userLatitude,
    required double userLongitude,
    required double cloudLatitude,
    required double cloudLongitude,
  }) {
    // Check for stationary clouds
    if (cloudSpeedKmh < 0.1) {
      return null;
    }

    // Calculate bearing from cloud to user
    final bearingToUser = calculateBearing(
      cloudLatitude,
      cloudLongitude,
      userLatitude,
      userLongitude,
    );

    // Check if clouds are approaching
    if (!areCloudsApproaching(
      cloudDirectionDeg: cloudDirectionDeg,
      bearingToUser: bearingToUser,
    )) {
      return null;
    }

    // Calculate effective approach speed using dot product
    // This accounts for clouds moving at an angle
    final angleDiff = _normalizeAngle(cloudDirectionDeg - bearingToUser);
    final approachSpeed = cloudSpeedKmh * math.cos(_degreesToRadians(angleDiff));

    if (approachSpeed <= 0) {
      return null;
    }

    // Calculate time = distance / speed
    final hoursToArrival = cloudDistanceKm / approachSpeed;
    final minutesToArrival = (hoursToArrival * 60).round();

    return Duration(minutes: minutesToArrival);
  }

  /// Calculate distance between two lat/lon points using Haversine formula.
  ///
  /// Returns distance in kilometers.
  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final deltaLatRad = _degreesToRadians(lat2 - lat1);
    final deltaLonRad = _degreesToRadians(lon2 - lon1);

    final a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLonRad / 2) *
            math.sin(deltaLonRad / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return _earthRadiusKm * c;
  }

  /// Calculate bearing from point 1 to point 2.
  ///
  /// Returns bearing in degrees (0-360, where 0=N, 90=E, 180=S, 270=W).
  double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);
    final deltaLonRad = _degreesToRadians(lon2 - lon1);

    final y = math.sin(deltaLonRad) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLonRad);

    final bearingRad = math.atan2(y, x);
    final bearingDeg = _radiansToDegrees(bearingRad);

    // Normalize to 0-360
    return (bearingDeg + 360) % 360;
  }

  /// Check if clouds are approaching user (vs moving away).
  ///
  /// Clouds are considered approaching if their direction of movement is
  /// within 90 degrees of the bearing to the user.
  bool areCloudsApproaching({
    required double cloudDirectionDeg,
    required double bearingToUser,
  }) {
    final angleDiff = _normalizeAngle(cloudDirectionDeg - bearingToUser).abs();
    // Within 90 degrees means approaching (cos > 0)
    return angleDiff <= 90;
  }

  // Private helper methods

  /// Generate grid of sampling points in a circular pattern.
  List<(double lat, double lon)> _generateGridPoints({
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    required double spacingKm,
  }) {
    final points = <(double, double)>[];
    final numRings = (radiusKm / spacingKm).ceil();

    // Center point
    points.add((centerLat, centerLon));

    // Concentric rings
    for (int ring = 1; ring <= numRings; ring++) {
      final ringRadiusKm = ring * spacingKm;
      if (ringRadiusKm > radiusKm) break;

      // Number of points in this ring (proportional to circumference)
      final numPoints = math.max(8, (2 * math.pi * ring).round());

      for (int i = 0; i < numPoints; i++) {
        final bearing = (i * 360.0) / numPoints;
        final point = _destinationPoint(
          centerLat,
          centerLon,
          ringRadiusKm,
          bearing,
        );
        points.add(point);
      }
    }

    return points;
  }

  /// Calculate destination point given start point, distance, and bearing.
  (double lat, double lon) _destinationPoint(
    double lat,
    double lon,
    double distanceKm,
    double bearingDeg,
  ) {
    final latRad = _degreesToRadians(lat);
    final lonRad = _degreesToRadians(lon);
    final bearingRad = _degreesToRadians(bearingDeg);
    final angularDistance = distanceKm / _earthRadiusKm;

    final destLatRad = math.asin(
      math.sin(latRad) * math.cos(angularDistance) +
          math.cos(latRad) * math.sin(angularDistance) * math.cos(bearingRad),
    );

    final destLonRad = lonRad +
        math.atan2(
          math.sin(bearingRad) * math.sin(angularDistance) * math.cos(latRad),
          math.cos(angularDistance) - math.sin(latRad) * math.sin(destLatRad),
        );

    return (
      _radiansToDegrees(destLatRad),
      _radiansToDegrees(destLonRad),
    );
  }

  /// Find the centroid of cloud mass within analysis area.
  (double lat, double lon)? _findCloudCentroid({
    required RadarFrame frame,
    required double centerLat,
    required double centerLon,
    required double radiusKm,
  }) {
    final gridPoints = _generateGridPoints(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: radiusKm,
      spacingKm: _defaultGridSpacingKm,
    );

    double sumLat = 0.0;
    double sumLon = 0.0;
    double sumDensity = 0.0;

    for (final point in gridPoints) {
      final density = _estimateCloudDensity(frame, point.$1, point.$2);
      if (density > _defaultDensityThreshold) {
        sumLat += point.$1 * density;
        sumLon += point.$2 * density;
        sumDensity += density;
      }
    }

    if (sumDensity == 0.0) {
      return null;
    }

    return (sumLat / sumDensity, sumLon / sumDensity);
  }

  /// Estimate cloud density at a specific location.
  ///
  /// This is a simplified implementation using frame opacity as a proxy.
  /// In a full implementation, this would fetch the actual tile at the
  /// given lat/lon and analyze pixel values.
  double _estimateCloudDensity(RadarFrame frame, double lat, double lon) {
    // Check if point is within frame bounds
    if (lat < frame.south || lat > frame.north ||
        lon < frame.west || lon > frame.east) {
      return 0.0;
    }

    // Use frame opacity as density proxy
    // In reality, would need to fetch and analyze actual radar tile pixels
    return frame.opacity;
  }

  /// Calculate circular mean of angles to handle 0/360 wraparound.
  double _averageDirection(List<double> directions) {
    if (directions.isEmpty) {
      return 0.0;
    }

    double sumSin = 0.0;
    double sumCos = 0.0;

    for (final dir in directions) {
      final rad = _degreesToRadians(dir);
      sumSin += math.sin(rad);
      sumCos += math.cos(rad);
    }

    final avgRad = math.atan2(sumSin / directions.length, sumCos / directions.length);
    final avgDeg = _radiansToDegrees(avgRad);

    return (avgDeg + 360) % 360;
  }

  /// Normalize angle to -180 to +180 range.
  double _normalizeAngle(double degrees) {
    double normalized = degrees % 360;
    if (normalized > 180) {
      normalized -= 360;
    } else if (normalized < -180) {
      normalized += 360;
    }
    return normalized;
  }

  /// Convert degrees to radians.
  double _degreesToRadians(double degrees) => degrees * math.pi / 180.0;

  /// Convert radians to degrees.
  double _radiansToDegrees(double radians) => radians * 180.0 / math.pi;
}

/// Internal motion vector representation.
class _MotionVector {
  final double speedKmh;
  final double directionDegrees;

  _MotionVector({
    required this.speedKmh,
    required this.directionDegrees,
  });
}
