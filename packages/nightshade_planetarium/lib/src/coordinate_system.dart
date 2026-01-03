import 'dart:math' as math;

/// Celestial coordinate in RA/Dec (J2000)
class CelestialCoordinate {
  /// Right Ascension in hours (0-24)
  final double ra;
  
  /// Declination in degrees (-90 to +90)
  final double dec;

  const CelestialCoordinate({
    required this.ra,
    required this.dec,
  });

  /// RA in degrees
  double get raDegrees => ra * 15;
  
  /// RA in radians
  double get raRadians => raDegrees * math.pi / 180;
  
  /// Dec in radians
  double get decRadians => dec * math.pi / 180;

  /// Convert to Alt/Az for given location and time
  HorizontalCoordinate toHorizontal({
    required double latitude,
    required double longitude,
    required DateTime time,
  }) {
    // Calculate Local Sidereal Time
    final jd = _julianDate(time);
    final lst = _localSiderealTime(jd, longitude);
    
    // Hour angle
    final ha = (lst - ra) * 15 * math.pi / 180;
    
    // Convert to horizontal
    final latRad = latitude * math.pi / 180;
    
    final sinAlt = math.sin(decRadians) * math.sin(latRad) +
                   math.cos(decRadians) * math.cos(latRad) * math.cos(ha);
    final alt = math.asin(sinAlt);
    
    final cosAz = (math.sin(decRadians) - math.sin(alt) * math.sin(latRad)) /
                  (math.cos(alt) * math.cos(latRad));
    var az = math.acos(cosAz.clamp(-1, 1));
    
    if (math.sin(ha) > 0) {
      az = 2 * math.pi - az;
    }
    
    return HorizontalCoordinate(
      altitude: alt * 180 / math.pi,
      azimuth: az * 180 / math.pi,
    );
  }
  
  double _julianDate(DateTime dt) {
    final y = dt.year;
    final m = dt.month;
    final d = dt.day + dt.hour / 24 + dt.minute / 1440 + dt.second / 86400;
    
    final a = ((14 - m) / 12).floor();
    final y2 = y + 4800 - a;
    final m2 = m + 12 * a - 3;
    
    return d + ((153 * m2 + 2) / 5).floor() + 365 * y2 +
           (y2 / 4).floor() - (y2 / 100).floor() + (y2 / 400).floor() - 32045;
  }
  
  double _localSiderealTime(double jd, double longitude) {
    final t = (jd - 2451545.0) / 36525;
    var lst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) +
              0.000387933 * t * t - t * t * t / 38710000;
    lst = lst + longitude;
    lst = lst % 360;
    if (lst < 0) lst += 360;
    return lst / 15; // Convert to hours
  }

  @override
  String toString() => 'RA: ${formatRA()}, Dec: ${formatDec()}';

  /// Format RA as hours, minutes, seconds string
  String formatRA({bool compact = false}) {
    final h = ra.floor();
    final m = ((ra - h) * 60).floor();
    final s = ((ra - h - m / 60) * 3600);
    if (compact) {
      return '${h.toString().padLeft(2, '0')}h${m.toString().padLeft(2, '0')}m';
    }
    return '${h}h ${m}m ${s.toStringAsFixed(1)}s';
  }

  /// Format Dec as degrees, arcminutes, arcseconds string
  String formatDec({bool compact = false}) {
    final sign = dec >= 0 ? '+' : '-';
    final d = dec.abs().floor();
    final m = ((dec.abs() - d) * 60).floor();
    final s = ((dec.abs() - d - m / 60) * 3600);
    if (compact) {
      return "$sign${d.toString().padLeft(2, '0')}°${m.toString().padLeft(2, '0')}'";
    }
    return "$sign$d° $m' ${s.toStringAsFixed(1)}\"";
  }

  /// Get RA in HMS format suitable for sequencer/equipment
  String get raHms => formatRA();

  /// Get Dec in DMS format suitable for sequencer/equipment
  String get decDms => formatDec();

  /// Get short form for display (e.g., "12h 30m, +45° 15'")
  String get shortForm => '${formatRA(compact: true)}, ${formatDec(compact: true)}';
}

/// Horizontal coordinate (Alt/Az)
class HorizontalCoordinate {
  /// Altitude in degrees (0 = horizon, 90 = zenith)
  final double altitude;
  
  /// Azimuth in degrees (0 = North, 90 = East)
  final double azimuth;

  const HorizontalCoordinate({
    required this.altitude,
    required this.azimuth,
  });
  
  bool get isAboveHorizon => altitude > 0;

  @override
  String toString() => 'Alt: ${altitude.toStringAsFixed(1)}°, Az: ${azimuth.toStringAsFixed(1)}°';
}





