import 'dart:math' as math;

/// Comprehensive astronomy calculations for astrophotography planning
class AstronomyCalculations {
  AstronomyCalculations._();

  // ============================================================================
  // Constants
  // ============================================================================
  
  static const double _deg2rad = math.pi / 180;
  static const double _rad2deg = 180 / math.pi;
  static const double _j2000 = 2451545.0;
  
  // Obliquity of ecliptic at J2000 (degrees)
  static const double _obliquityJ2000 = 23.439291111;

  // ============================================================================
  // Julian Date Calculations
  // ============================================================================
  
  /// Convert DateTime to Julian Date
  static double julianDate(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year;
    final m = utc.month;
    final d = utc.day + utc.hour / 24 + utc.minute / 1440 + 
              utc.second / 86400 + utc.millisecond / 86400000;
    
    final a = ((14 - m) / 12).floor();
    final y2 = y + 4800 - a;
    final m2 = m + 12 * a - 3;
    
    return d + ((153 * m2 + 2) / 5).floor() + 365 * y2 +
           (y2 / 4).floor() - (y2 / 100).floor() + (y2 / 400).floor() - 32045 - 0.5;
  }
  
  /// Convert Julian Date to DateTime
  static DateTime fromJulianDate(double jd) {
    final z = (jd + 0.5).floor();
    final f = jd + 0.5 - z;
    
    int a;
    if (z < 2299161) {
      a = z;
    } else {
      final alpha = ((z - 1867216.25) / 36524.25).floor();
      a = z + 1 + alpha - (alpha / 4).floor();
    }
    
    final b = a + 1524;
    final c = ((b - 122.1) / 365.25).floor();
    final d = (365.25 * c).floor();
    final e = ((b - d) / 30.6001).floor();
    
    final day = b - d - (30.6001 * e).floor();
    final month = e < 14 ? e - 1 : e - 13;
    final year = month > 2 ? c - 4716 : c - 4715;
    
    final hours = f * 24;
    final hour = hours.floor();
    final minutes = (hours - hour) * 60;
    final minute = minutes.floor();
    final seconds = (minutes - minute) * 60;
    final second = seconds.floor();
    final millisecond = ((seconds - second) * 1000).round();
    
    return DateTime.utc(year, month, day, hour, minute, second, millisecond);
  }
  
  /// Modified Julian Date
  static double modifiedJulianDate(DateTime dt) => julianDate(dt) - 2400000.5;

  // ============================================================================
  // Sidereal Time
  // ============================================================================
  
  /// Greenwich Mean Sidereal Time in hours
  static double greenwichMeanSiderealTime(DateTime dt) {
    final jd = julianDate(dt);
    final t = (jd - _j2000) / 36525;
    
    var gmst = 280.46061837 + 360.98564736629 * (jd - _j2000) +
               0.000387933 * t * t - t * t * t / 38710000;
    
    gmst = gmst % 360;
    if (gmst < 0) gmst += 360;
    return gmst / 15; // Convert to hours
  }
  
  /// Local Sidereal Time in hours
  static double localSiderealTime(DateTime dt, double longitudeDeg) {
    final gmst = greenwichMeanSiderealTime(dt);
    var lst = gmst + longitudeDeg / 15;
    lst = lst % 24;
    if (lst < 0) lst += 24;
    return lst;
  }

  // ============================================================================
  // Atmospheric Refraction
  // ============================================================================
  
  /// Calculate atmospheric refraction correction using Bennett (1982) formula
  /// This is the standard formula used by the USNO
  /// 
  /// Assumes standard atmospheric conditions:
  /// - Temperature: 10°C
  /// - Pressure: 1010 mbar
  /// - Humidity: Standard
  /// 
  /// Accuracy: ~0.1 arcmin for altitudes > 15°, ~1 arcmin near horizon
  /// 
  /// Returns refraction in degrees (always positive, adds to apparent altitude)
  static double atmosphericRefraction(double trueAltitudeDeg) {
    // No refraction for objects well below horizon
    if (trueAltitudeDeg < -2.0) return 0.0;
    
    // Bennett (1982) improved formula
    // R = 1.02 / tan(h + 10.3/(h + 5.11)) arcminutes
    final h = trueAltitudeDeg;
    final correctionArcmin = 1.02 / math.tan((h + 10.3/(h + 5.11)) * _deg2rad);
    
    return correctionArcmin / 60.0;  // Convert arcminutes to degrees
  }
  
  /// Convert true (geometric) altitude to apparent (observed) altitude
  /// by adding atmospheric refraction
  static double trueToApparentAltitude(double trueAltDeg) {
    return trueAltDeg + atmosphericRefraction(trueAltDeg);
  }
  
  /// Convert apparent (observed) altitude to true (geometric) altitude
  /// by removing atmospheric refraction
  /// 
  /// Uses iterative method since refraction depends on altitude
  /// 3 iterations provide sub-arcsecond accuracy
  static double apparentToTrueAltitude(double apparentAltDeg) {
    if (apparentAltDeg < -2.0) return apparentAltDeg;
    
    // Iterative refinement
    var trueAlt = apparentAltDeg;
    for (var i = 0; i < 3; i++) {
      final refraction = atmosphericRefraction(trueAlt);
      trueAlt = apparentAltDeg - refraction;
    }
    return trueAlt;
  }

  // ============================================================================
  // Coordinate Transformations
  // ============================================================================
  
  /// Convert equatorial (RA/Dec) to horizontal (Alt/Az) coordinates
  /// Returns (altitude, azimuth) in degrees
  static (double alt, double az) equatorialToHorizontal({
    required double raDeg,
    required double decDeg,
    required double latitudeDeg,
    required double lstHours,
  }) {
    // Hour angle in degrees
    final ha = (lstHours * 15 - raDeg) * _deg2rad;
    final dec = decDeg * _deg2rad;
    final lat = latitudeDeg * _deg2rad;
    
    // Calculate altitude
    final sinAlt = math.sin(dec) * math.sin(lat) + 
                   math.cos(dec) * math.cos(lat) * math.cos(ha);
    final alt = math.asin(sinAlt.clamp(-1.0, 1.0));
    
    // Calculate azimuth
    final cosAz = (math.sin(dec) - math.sin(alt) * math.sin(lat)) / 
                  (math.cos(alt) * math.cos(lat));
    var az = math.acos(cosAz.clamp(-1.0, 1.0));
    
    // Correct for quadrant
    if (math.sin(ha) > 0) {
      az = 2 * math.pi - az;
    }
    
    return (alt * _rad2deg, az * _rad2deg);
  }
  
  /// Convert horizontal (Alt/Az) to equatorial (RA/Dec) coordinates
  /// Returns (ra, dec) in degrees
  static (double ra, double dec) horizontalToEquatorial({
    required double altDeg,
    required double azDeg,
    required double latitudeDeg,
    required double lstHours,
  }) {
    final alt = altDeg * _deg2rad;
    final az = azDeg * _deg2rad;
    final lat = latitudeDeg * _deg2rad;
    
    // Calculate declination
    final sinDec = math.sin(alt) * math.sin(lat) + 
                   math.cos(alt) * math.cos(lat) * math.cos(az);
    final dec = math.asin(sinDec.clamp(-1.0, 1.0));
    
    // Calculate hour angle
    final cosHa = (math.sin(alt) - math.sin(dec) * math.sin(lat)) / 
                  (math.cos(dec) * math.cos(lat));
    var ha = math.acos(cosHa.clamp(-1.0, 1.0));
    
    if (math.sin(az) > 0) {
      ha = 2 * math.pi - ha;
    }
    
    // Convert to RA
    var ra = lstHours * 15 - ha * _rad2deg;
    ra = ra % 360;
    if (ra < 0) ra += 360;
    
    return (ra, dec * _rad2deg);
  }
  
  /// Convert ecliptic to equatorial coordinates
  /// Returns (ra, dec) in degrees
  static (double ra, double dec) eclipticToEquatorial({
    required double lonDeg,
    required double latDeg,
    required double obliquityDeg,
  }) {
    final lon = lonDeg * _deg2rad;
    final lat = latDeg * _deg2rad;
    final eps = obliquityDeg * _deg2rad;
    
    final sinDec = math.sin(lat) * math.cos(eps) + 
                   math.cos(lat) * math.sin(eps) * math.sin(lon);
    final dec = math.asin(sinDec.clamp(-1.0, 1.0));
    
    final y = math.sin(lon) * math.cos(eps) - math.tan(lat) * math.sin(eps);
    final x = math.cos(lon);
    var ra = math.atan2(y, x) * _rad2deg;
    ra = ra % 360;  // Ensure proper modulo
    if (ra < 0) ra += 360;
    
    return (ra, dec * _rad2deg);
  }

  // ============================================================================
  // Sun Calculations
  // ============================================================================
  
  /// Calculate Sun position for given DateTime
  /// Returns (ra, dec) in degrees
  static (double ra, double dec) sunPosition(DateTime dt) {
    final jd = julianDate(dt);
    final t = (jd - _j2000) / 36525;
    
    // Mean longitude of the Sun
    var l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    l0 = l0 % 360;
    
    // Mean anomaly of the Sun
    var m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
    m = m % 360;
    final mRad = m * _deg2rad;
    
    // Equation of center
    final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(mRad) +
              (0.019993 - 0.000101 * t) * math.sin(2 * mRad) +
              0.000289 * math.sin(3 * mRad);
    
    // True longitude of the Sun
    final sunLon = l0 + c;
    
    // Obliquity of ecliptic
    final eps = _obliquityJ2000 - 0.0130042 * t;
    
    return eclipticToEquatorial(lonDeg: sunLon, latDeg: 0, obliquityDeg: eps);
  }
  
  /// Calculate Sun altitude at given time and location
  /// 
  /// If [apparent] is true (default), returns apparent altitude including
  /// atmospheric refraction. If false, returns true geometric altitude.
  static double sunAltitude({
    required DateTime dt,
    required double latitudeDeg,
    required double longitudeDeg,
    bool apparent = true,
  }) {
    final (ra, dec) = sunPosition(dt);
    final lst = localSiderealTime(dt, longitudeDeg);
    final (trueAlt, _) = equatorialToHorizontal(
      raDeg: ra,
      decDeg: dec,
      latitudeDeg: latitudeDeg,
      lstHours: lst,
    );
    return apparent ? trueToApparentAltitude(trueAlt) : trueAlt;
  }

  // ============================================================================
  // Twilight Calculations
  // ============================================================================
  
  // Rise/set altitude adjustments (all in degrees, negative = below horizon)
  /// Standard refraction at horizon: ~34 arcminutes
  static const double _refractionAtHorizon = -0.5667;  // -34/60
  
  /// Sun rise/set altitude: -34' (refraction) - 16' (semi-diameter) = -50'
  static const double _sunRiseSetAltitude = -0.8333;  // -50/60
  
  /// Moon rise/set altitude: -34' (refraction) - 16' (semi-diameter) + 8' (parallax) ≈ -42'
  static const double _moonRiseSetAltitude = -0.7;  // Approximate
  
  /// Twilight type enumeration
  static const double civilTwilightAngle = -6.0;
  static const double nauticalTwilightAngle = -12.0;
  static const double astronomicalTwilightAngle = -18.0;
  
  /// Find time when sun crosses given altitude (binary search)
  static DateTime? _findSunAltitudeCrossing({
    required DateTime startTime,
    required DateTime endTime,
    required double targetAlt,
    required double latitudeDeg,
    required double longitudeDeg,
    required bool rising,
  }) {
    var t1 = startTime;
    var t2 = endTime;
    
    for (var i = 0; i < 50; i++) {
      final tMid = t1.add(Duration(milliseconds: 
        t2.difference(t1).inMilliseconds ~/ 2));
      final alt = sunAltitude(dt: tMid, latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg);
      
      if ((alt - targetAlt).abs() < 0.001) {
        return tMid;
      }
      
      if (rising) {
        if (alt < targetAlt) {
          t1 = tMid;
        } else {
          t2 = tMid;
        }
      } else {
        if (alt > targetAlt) {
          t1 = tMid;
        } else {
          t2 = tMid;
        }
      }
    }
    
    return t1.add(Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2));
  }
  
  /// Calculate twilight times for a given date and location
  static TwilightTimes calculateTwilightTimes({
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    // Start from noon local time
    final localNoon = DateTime(date.year, date.month, date.day, 12);
    
    // Search windows
    final eveningStart = localNoon;
    final eveningEnd = localNoon.add(const Duration(hours: 12));
    final morningStart = localNoon.subtract(const Duration(hours: 12));
    final morningEnd = localNoon;
    
    return TwilightTimes(
      sunset: _findSunAltitudeCrossing(
        startTime: eveningStart,
        endTime: eveningEnd,
        targetAlt: _sunRiseSetAltitude,  // -0.8333° (refraction + SD)
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: false,
      ),
      civilDusk: _findSunAltitudeCrossing(
        startTime: eveningStart,
        endTime: eveningEnd,
        targetAlt: civilTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: false,
      ),
      nauticalDusk: _findSunAltitudeCrossing(
        startTime: eveningStart,
        endTime: eveningEnd,
        targetAlt: nauticalTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: false,
      ),
      astronomicalDusk: _findSunAltitudeCrossing(
        startTime: eveningStart,
        endTime: eveningEnd,
        targetAlt: astronomicalTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: false,
      ),
      astronomicalDawn: _findSunAltitudeCrossing(
        startTime: morningStart.add(const Duration(hours: 24)),
        endTime: morningEnd.add(const Duration(hours: 24)),
        targetAlt: astronomicalTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: true,
      ),
      nauticalDawn: _findSunAltitudeCrossing(
        startTime: morningStart.add(const Duration(hours: 24)),
        endTime: morningEnd.add(const Duration(hours: 24)),
        targetAlt: nauticalTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: true,
      ),
      civilDawn: _findSunAltitudeCrossing(
        startTime: morningStart.add(const Duration(hours: 24)),
        endTime: morningEnd.add(const Duration(hours: 24)),
        targetAlt: civilTwilightAngle,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: true,
      ),
      sunrise: _findSunAltitudeCrossing(
        startTime: morningStart.add(const Duration(hours: 24)),
        endTime: morningEnd.add(const Duration(hours: 24)),
        targetAlt: _sunRiseSetAltitude,  // -0.8333° (refraction + SD)
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: true,
      ),
    );
  }
  
  /// Calculate darkness hours between astronomical dusk and dawn
  static Duration? darknessHours(TwilightTimes twilight) {
    if (twilight.astronomicalDusk != null && twilight.astronomicalDawn != null) {
      return twilight.astronomicalDawn!.difference(twilight.astronomicalDusk!);
    }
    return null;
  }

  // ============================================================================
  // Moon Calculations
  // ============================================================================
  
  /// Calculate Moon position for given DateTime
  /// Returns (ra, dec, distance) - ra/dec in degrees, distance in km
  static (double ra, double dec, double distance) moonPosition(DateTime dt) {
    final jd = julianDate(dt);
    final t = (jd - _j2000) / 36525;
    
    // Moon's mean longitude
    var l0 = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t;
    l0 = l0 % 360;
    if (l0 < 0) l0 += 360;
    
    // Moon's mean anomaly
    var m = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t;
    m = m % 360;
    
    // Moon's mean elongation
    var d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t;
    d = d % 360;
    
    // Moon's argument of latitude
    var f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t;
    f = f % 360;
    
    // Sun's mean anomaly
    var mSun = 357.5291092 + 35999.0502909 * t;
    mSun = mSun % 360;
    
    // Convert to radians
    // Note: lRad not needed for simplified calculation
    final mRad = m * _deg2rad;
    final dRad = d * _deg2rad;
    final fRad = f * _deg2rad;
    final msRad = mSun * _deg2rad;
    
    // Longitude corrections (simplified)
    var lon = l0;
    lon += 6.289 * math.sin(mRad);
    lon += 1.274 * math.sin(2 * dRad - mRad);
    lon += 0.658 * math.sin(2 * dRad);
    lon += 0.214 * math.sin(2 * mRad);
    lon -= 0.186 * math.sin(msRad);
    lon -= 0.114 * math.sin(2 * fRad);
    
    // Latitude corrections (simplified)
    var lat = 0.0;
    lat += 5.128 * math.sin(fRad);
    lat += 0.281 * math.sin(mRad + fRad);
    lat += 0.278 * math.sin(mRad - fRad);
    lat += 0.173 * math.sin(2 * dRad - fRad);
    
    // Distance corrections (simplified)
    var r = 385000.56;
    r -= 20905.35 * math.cos(mRad);
    r -= 3699.11 * math.cos(2 * dRad - mRad);
    r -= 2955.97 * math.cos(2 * dRad);
    
    // Obliquity
    final eps = _obliquityJ2000 - 0.0130042 * t;
    
    // Convert to equatorial
    final (ra, dec) = eclipticToEquatorial(lonDeg: lon, latDeg: lat, obliquityDeg: eps);
    
    return (ra, dec, r);
  }
  
  /// Calculate Moon illumination percentage (0-100)
  static double moonIllumination(DateTime dt) {
    final (moonRa, moonDec, _) = moonPosition(dt);
    final (sunRa, sunDec) = sunPosition(dt);
    
    // Calculate elongation (angle between Moon and Sun)
    final moonRaRad = moonRa * _deg2rad;
    final moonDecRad = moonDec * _deg2rad;
    final sunRaRad = sunRa * _deg2rad;
    final sunDecRad = sunDec * _deg2rad;
    
    final cosE = math.sin(sunDecRad) * math.sin(moonDecRad) +
                 math.cos(sunDecRad) * math.cos(moonDecRad) * 
                 math.cos(sunRaRad - moonRaRad);
    final elongation = math.acos(cosE.clamp(-1.0, 1.0));
    
    // Phase angle (simplified - assumes Moon at same distance as Sun)
    final phaseAngle = math.pi - elongation;
    
    // Illuminated fraction
    final illumination = (1 + math.cos(phaseAngle)) / 2 * 100;
    
    return illumination;
  }
  
  /// Calculate Moon phase name
  static String moonPhaseName(DateTime dt) {
    final illumination = moonIllumination(dt);
    final (moonRa, _, _) = moonPosition(dt);
    final (sunRa, _) = sunPosition(dt);
    
    // Calculate phase angle for waxing/waning
    var phaseDiff = moonRa - sunRa;
    if (phaseDiff < 0) phaseDiff += 360;
    
    if (illumination < 3) {
      return 'New Moon';
    } else if (illumination < 47) {
      return phaseDiff < 180 ? 'Waxing Crescent' : 'Waning Crescent';
    } else if (illumination < 53) {
      return phaseDiff < 180 ? 'First Quarter' : 'Last Quarter';
    } else if (illumination < 97) {
      return phaseDiff < 180 ? 'Waxing Gibbous' : 'Waning Gibbous';
    } else {
      return 'Full Moon';
    }
  }
  
  /// Calculate Moon altitude at given time and location
  /// 
  /// If [apparent] is true (default), returns apparent altitude including
  /// atmospheric refraction. If false, returns true geometric altitude.
  static double moonAltitude({
    required DateTime dt,
    required double latitudeDeg,
    required double longitudeDeg,
    bool apparent = true,
  }) {
    final (ra, dec, _) = moonPosition(dt);
    final lst = localSiderealTime(dt, longitudeDeg);
    final (trueAlt, _) = equatorialToHorizontal(
      raDeg: ra,
      decDeg: dec,
      latitudeDeg: latitudeDeg,
      lstHours: lst,
    );
    return apparent ? trueToApparentAltitude(trueAlt) : trueAlt;
  }
  
  /// Find Moon rise/set times
  static MoonTimes calculateMoonTimes({
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    // Similar algorithm to Sun but accounting for Moon's faster motion
    final localNoon = DateTime(date.year, date.month, date.day, 12);
    final searchStart = localNoon.subtract(const Duration(hours: 12));
    final searchEnd = localNoon.add(const Duration(hours: 36));
    
    DateTime? moonrise;
    DateTime? moonset;
    
    // Step through time in 30-minute increments
    var prevAlt = moonAltitude(dt: searchStart, latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg);
    
    for (var t = searchStart; t.isBefore(searchEnd); t = t.add(const Duration(minutes: 30))) {
      final alt = moonAltitude(dt: t, latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg);
      
      if (prevAlt < 0 && alt >= 0 && moonrise == null) {
        // Moon is rising - refine with binary search
        moonrise = _refineMoonCrossing(
          t.subtract(const Duration(minutes: 30)),
          t,
          latitudeDeg,
          longitudeDeg,
          true,
        );
      } else if (prevAlt >= 0 && alt < 0 && moonset == null) {
        // Moon is setting - refine with binary search
        moonset = _refineMoonCrossing(
          t.subtract(const Duration(minutes: 30)),
          t,
          latitudeDeg,
          longitudeDeg,
          false,
        );
      }
      
      prevAlt = alt;
      
      if (moonrise != null && moonset != null) break;
    }
    
    return MoonTimes(
      moonrise: moonrise,
      moonset: moonset,
      illumination: moonIllumination(localNoon),
      phaseName: moonPhaseName(localNoon),
    );
  }
  
  static DateTime _refineMoonCrossing(
    DateTime t1,
    DateTime t2,
    double lat,
    double lon,
    bool rising,
  ) {
    for (var i = 0; i < 20; i++) {
      final tMid = t1.add(Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2));
      final alt = moonAltitude(dt: tMid, latitudeDeg: lat, longitudeDeg: lon);
      
      if (alt.abs() < 0.01) return tMid;
      
      if (rising) {
        if (alt < 0) {
          t1 = tMid;
        } else {
          t2 = tMid;
        }
      } else {
        if (alt > 0) {
          t1 = tMid;
        } else {
          t2 = tMid;
        }
      }
    }
    return t1.add(Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2));
  }

  // ============================================================================
  // Object Rise/Set/Transit Calculations
  // ============================================================================
  
  /// Calculate rise, transit, and set times for an object
  static ObjectVisibility calculateObjectVisibility({
    required double raDeg,
    required double decDeg,
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
    double minAltitude = 0,
  }) {
    final localNoon = DateTime(date.year, date.month, date.day, 12);
    
    // Check if object is circumpolar or never rises
    final cosDec = math.cos(decDeg * _deg2rad);
    final sinDec = math.sin(decDeg * _deg2rad);
    final cosLat = math.cos(latitudeDeg * _deg2rad);
    final sinLat = math.sin(latitudeDeg * _deg2rad);
    
    final cosH0 = (math.sin(minAltitude * _deg2rad) - sinDec * sinLat) / (cosDec * cosLat);
    
    bool isCircumpolar = false;
    bool neverRises = false;
    
    if (cosH0 < -1) {
      isCircumpolar = true;
    } else if (cosH0 > 1) {
      neverRises = true;
    }
    
    // Calculate transit time (when object crosses meridian)
    DateTime? transitTime;
    double? transitAltitude;
    
    // Transit occurs when LST = RA
    final lst0 = localSiderealTime(localNoon, longitudeDeg);
    var hoursTillTransit = (raDeg / 15) - lst0;
    if (hoursTillTransit < -12) hoursTillTransit += 24;
    if (hoursTillTransit > 12) hoursTillTransit -= 24;
    
    transitTime = localNoon.add(Duration(
      seconds: (hoursTillTransit * 3600).round(),
    ));
    
    // Transit altitude
    transitAltitude = 90 - (latitudeDeg - decDeg).abs();
    
    DateTime? riseTime;
    DateTime? setTime;
    
    if (!isCircumpolar && !neverRises) {
      // Calculate rise/set
      final h0 = math.acos(cosH0) * _rad2deg / 15; // In hours
      
      riseTime = transitTime.subtract(Duration(
        seconds: (h0 * 3600).round(),
      ));
      setTime = transitTime.add(Duration(
        seconds: (h0 * 3600).round(),
      ));
    }
    
    return ObjectVisibility(
      riseTime: riseTime,
      transitTime: transitTime,
      setTime: setTime,
      transitAltitude: transitAltitude,
      isCircumpolar: isCircumpolar,
      neverRises: neverRises,
    );
  }
  
  /// Calculate current altitude and azimuth of an object
  static (double alt, double az) objectAltAz({
    required double raDeg,
    required double decDeg,
    required DateTime dt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final lst = localSiderealTime(dt, longitudeDeg);
    return equatorialToHorizontal(
      raDeg: raDeg,
      decDeg: decDeg,
      latitudeDeg: latitudeDeg,
      lstHours: lst,
    );
  }

  // ============================================================================
  // Airmass Calculation
  // ============================================================================
  
  /// Calculate airmass for given altitude
  /// Uses Pickering (2002) formula
  static double airmass(double altitudeDeg) {
    if (altitudeDeg <= 0) return double.infinity;
    
    // Pickering (2002) formula
    final h = altitudeDeg;
    return 1 / math.sin((h + 244 / (165 + 47 * math.pow(h, 1.1))) * _deg2rad);
  }

  // ============================================================================
  // Angular Separation
  // ============================================================================
  
  /// Calculate angular separation between two sky coordinates (degrees)
  static double angularSeparation({
    required double ra1Deg,
    required double dec1Deg,
    required double ra2Deg,
    required double dec2Deg,
  }) {
    final ra1 = ra1Deg * _deg2rad;
    final dec1 = dec1Deg * _deg2rad;
    final ra2 = ra2Deg * _deg2rad;
    final dec2 = dec2Deg * _deg2rad;
    
    final cosSep = math.sin(dec1) * math.sin(dec2) +
                   math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);
    
    return math.acos(cosSep.clamp(-1.0, 1.0)) * _rad2deg;
  }
}

/// Twilight times container
class TwilightTimes {
  final DateTime? sunset;
  final DateTime? civilDusk;
  final DateTime? nauticalDusk;
  final DateTime? astronomicalDusk;
  final DateTime? astronomicalDawn;
  final DateTime? nauticalDawn;
  final DateTime? civilDawn;
  final DateTime? sunrise;
  
  const TwilightTimes({
    this.sunset,
    this.civilDusk,
    this.nauticalDusk,
    this.astronomicalDusk,
    this.astronomicalDawn,
    this.nauticalDawn,
    this.civilDawn,
    this.sunrise,
  });
  
  /// Get darkness period (astronomical dusk to dawn)
  Duration? get darknessDuration {
    if (astronomicalDusk != null && astronomicalDawn != null) {
      return astronomicalDawn!.difference(astronomicalDusk!);
    }
    return null;
  }
}

/// Moon times and phase container
class MoonTimes {
  final DateTime? moonrise;
  final DateTime? moonset;
  final double illumination;
  final String phaseName;
  
  const MoonTimes({
    this.moonrise,
    this.moonset,
    required this.illumination,
    required this.phaseName,
  });
}

/// Object visibility information
class ObjectVisibility {
  final DateTime? riseTime;
  final DateTime? transitTime;
  final DateTime? setTime;
  final double? transitAltitude;
  final bool isCircumpolar;
  final bool neverRises;
  
  const ObjectVisibility({
    this.riseTime,
    this.transitTime,
    this.setTime,
    this.transitAltitude,
    this.isCircumpolar = false,
    this.neverRises = false,
  });
  
  /// Get duration object is above horizon
  Duration? get durationAboveHorizon {
    if (isCircumpolar) return const Duration(hours: 24);
    if (neverRises) return Duration.zero;
    if (riseTime != null && setTime != null) {
      return setTime!.difference(riseTime!);
    }
    return null;
  }
}

