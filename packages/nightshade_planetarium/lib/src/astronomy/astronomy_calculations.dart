// ignore_for_file: unused_field

import 'dart:math' as math;

/// Signature for a body's apparent equatorial position (RA/Dec, degrees) at a
/// given instant. Used by [AstronomyCalculations.calculateObjectVisibility] to
/// track moving bodies (Sun/Moon/planets) across the night. Fixed catalog
/// objects simply omit this callback and their J2000 RA/Dec is used directly.
typedef EquatorialPositionAt =
    (double raDeg, double decDeg) Function(DateTime dt);

/// Canonical airmass model shared by planning and science exports.
///
/// Uses Pickering (2002) at true altitude >= 10 degrees and Young (1994) down
/// to the horizon, matching `nightshade_imaging::calculate_airmass` in the FITS
/// writer. [altitudeDegrees] is geometric altitude. Non-finite and
/// below-horizon values return `null`; valid values are not artificially
/// clamped.
double? airmassForTrueAltitude(double altitudeDegrees) {
  if (!altitudeDegrees.isFinite || altitudeDegrees < 0.0) {
    return null;
  }
  // Guard numerical noise like 90.000001, which would push sin() past 1.
  final alt = altitudeDegrees > 90.0 ? 90.0 : altitudeDegrees;
  if (alt >= 89.9) {
    // Both formulas converge to 1.0 here; short-circuit so floating-point
    // jitter cannot report 0.99999999 airmass at the zenith.
    return 1.0;
  }

  const degToRad = math.pi / 180.0;
  final double airmass;
  if (alt >= 10.0) {
    final correctionDeg = 244.0 / (165.0 + 47.0 * math.pow(alt, 1.1));
    airmass = 1.0 / math.sin((alt + correctionDeg) * degToRad);
  } else {
    // Young 1994, in true zenith angle z = 90 - h:
    //   X = (1.002432 cos^2 z + 0.148386 cos z + 0.0096467) /
    //       (cos^3 z + 0.149864 cos^2 z + 0.0102963 cos z + 0.000303978)
    final cosZ = math.cos((90.0 - alt) * degToRad);
    final cos2 = cosZ * cosZ;
    final cos3 = cos2 * cosZ;
    airmass =
        (1.002432 * cos2 + 0.148386 * cosZ + 0.0096467) /
        (cos3 + 0.149864 * cos2 + 0.0102963 * cosZ + 0.000303978);
  }

  return airmass.isFinite ? airmass : null;
}

/// Comprehensive astronomy calculations for astrophotography planning
class AstronomyCalculations {
  AstronomyCalculations._();

  // ============================================================================
  // Constants
  // ============================================================================

  static const double _deg2rad = math.pi / 180;
  static const double _rad2deg = 180 / math.pi;
  static const double _epsilon = 1e-12;
  static const double _j2000 = 2451545.0;

  // Obliquity of ecliptic at J2000 (degrees)
  static const double _obliquityJ2000 = 23.439291111;

  // ============================================================================
  // Julian Date Calculations
  // ============================================================================

  /// Convert DateTime to Julian Date.
  ///
  /// Fliegel–Van Flandern day-number form. This is the Julian Date the whole
  /// planetarium package uses; `PlanetaryPositions.julianDate`,
  /// `MinorPlanetCatalog._julianDate` and `VariableStarCatalog._julianDate`
  /// were byte-for-byte re-typings of it and now call through here.
  ///
  /// [includeMilliseconds] reproduces the one real difference between those
  /// copies: the variable-star catalog stopped its day fraction at whole
  /// seconds. Passing `false` makes the sub-second term a literal `0`, and
  /// `x + 0` is exact, so that catalog's phase numbers are unchanged.
  ///
  /// This is NOT the same function as `SkyCalculations.julianDate` in
  /// `nightshade_core`, which uses Meeus' Gregorian form. Both are correct
  /// Julian Dates and they agree to ~5e-10 d, but they are not the same
  /// doubles, and each side's goldens are pinned to its own. Merging them
  /// would move one set of numbers for no gain; `nightshade_planetarium` is a
  /// leaf package that cannot see `nightshade_core` anyway (the dependency
  /// runs the other way).
  static double julianDate(DateTime dt, {bool includeMilliseconds = true}) {
    final utc = dt.toUtc();
    final y = utc.year;
    final m = utc.month;
    final d =
        utc.day +
        utc.hour / 24 +
        utc.minute / 1440 +
        utc.second / 86400 +
        (includeMilliseconds ? utc.millisecond / 86400000 : 0);

    final a = ((14 - m) / 12).floor();
    final y2 = y + 4800 - a;
    final m2 = m + 12 * a - 3;

    return d +
        ((153 * m2 + 2) / 5).floor() +
        365 * y2 +
        (y2 / 4).floor() -
        (y2 / 100).floor() +
        (y2 / 400).floor() -
        32045 -
        0.5;
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

    var gmst =
        280.46061837 +
        360.98564736629 * (jd - _j2000) +
        0.000387933 * t * t -
        t * t * t / 38710000;

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
    final correctionArcmin =
        1.02 / math.tan((h + 10.3 / (h + 5.11)) * _deg2rad);

    return correctionArcmin / 60.0; // Convert arcminutes to degrees
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
    final sinAlt =
        math.sin(dec) * math.sin(lat) +
        math.cos(dec) * math.cos(lat) * math.cos(ha);
    final alt = math.asin(sinAlt.clamp(-1.0, 1.0));

    // Calculate azimuth with atan2 to stay finite at zenith/nadir and
    // near the poles, where acos-based forms divide by cos(alt) * cos(lat).
    final y = -math.sin(ha) * math.cos(dec);
    final x =
        math.sin(dec) * math.cos(lat) -
        math.cos(dec) * math.sin(lat) * math.cos(ha);
    var az = math.atan2(y, x);
    if (az < 0) az += 2 * math.pi;

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
    final sinDec =
        math.sin(alt) * math.sin(lat) +
        math.cos(alt) * math.cos(lat) * math.cos(az);
    final dec = math.asin(sinDec.clamp(-1.0, 1.0));

    // Calculate hour angle with atan2 so azimuths near zenith/nadir do not
    // produce NaN from tiny denominators.
    final y = -math.sin(az) * math.cos(alt);
    final x =
        math.sin(alt) * math.cos(lat) -
        math.cos(alt) * math.sin(lat) * math.cos(az);
    final ha = math.atan2(y, x);

    // Convert to RA, normalizing to [0, 360).
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

    final sinDec =
        math.sin(lat) * math.cos(eps) +
        math.cos(lat) * math.sin(eps) * math.sin(lon);
    final dec = math.asin(sinDec.clamp(-1.0, 1.0));

    final y = math.sin(lon) * math.cos(eps) - math.tan(lat) * math.sin(eps);
    final x = math.cos(lon);
    var ra = math.atan2(y, x) * _rad2deg;
    ra = ra % 360; // Ensure proper modulo
    if (ra < 0) ra += 360;

    return (ra, dec * _rad2deg);
  }

  /// Convert galactic coordinates to equatorial (J2000) coordinates.
  /// Uses the IAU 1958 galactic coordinate system:
  ///   - North galactic pole at RA 12h51m26.28s, Dec +27°07'41.7" (J2000)
  ///   - Galactic center direction at RA 17h45m37.2s, Dec -28°56'10.2" (J2000)
  ///   - Ascending node of galactic plane on equator at RA 282.8595°
  /// Returns (ra, dec) in degrees.
  static (double ra, double dec) galacticToEquatorial({
    required double lonDeg,
    required double latDeg,
  }) {
    // IAU galactic pole and ascending node constants (J2000)
    const double alphaGP = 192.85948; // RA of north galactic pole (degrees)
    const double deltaGP = 27.12825; // Dec of north galactic pole (degrees)
    const double lOmega = 32.93192; // Galactic longitude of ascending node

    final l = lonDeg * _deg2rad;
    final b = latDeg * _deg2rad;
    const dGP = deltaGP * _deg2rad;
    const lO = lOmega * _deg2rad;

    // Declination
    final sinDec =
        math.sin(b) * math.sin(dGP) +
        math.cos(b) * math.cos(dGP) * math.sin(l - lO);
    final dec = math.asin(sinDec.clamp(-1.0, 1.0));

    // Right ascension
    final y = math.cos(b) * math.cos(l - lO);
    final x =
        math.sin(b) * math.cos(dGP) -
        math.cos(b) * math.sin(dGP) * math.sin(l - lO);
    var ra = math.atan2(y, x) * _rad2deg + alphaGP;
    ra = ra % 360;
    if (ra < 0) ra += 360;

    return (ra, dec * _rad2deg);
  }

  // ============================================================================
  // Precession & Nutation
  // ============================================================================

  /// Nutation in longitude and obliquity (degrees) for a given Julian Date.
  ///
  /// Uses the four dominant terms of the IAU 1980 nutation series (the 18.6-yr
  /// lunar-node term plus the principal solar/lunar terms), accurate to within
  /// roughly an arcsecond — far finer than the ~1-arcminute target of the
  /// rise/set and grid work this feeds. Returns (dPsi, dEps) in degrees.
  static (double dPsiDeg, double dEpsDeg) nutation(double jd) {
    final t = (jd - _j2000) / 36525;

    // Longitude of the ascending node of the Moon's mean orbit.
    final omega = (125.04452 - 1934.136261 * t) * _deg2rad;
    // Mean longitude of the Sun and the Moon.
    final lSun = (280.4665 + 36000.7698 * t) * _deg2rad;
    final lMoon = (218.3165 + 481267.8813 * t) * _deg2rad;

    // Nutation in longitude (arcseconds).
    final dPsiArcsec =
        -17.20 * math.sin(omega) -
        1.32 * math.sin(2 * lSun) -
        0.23 * math.sin(2 * lMoon) +
        0.21 * math.sin(2 * omega);

    // Nutation in obliquity (arcseconds).
    final dEpsArcsec =
        9.20 * math.cos(omega) +
        0.57 * math.cos(2 * lSun) +
        0.10 * math.cos(2 * lMoon) -
        0.09 * math.cos(2 * omega);

    return (dPsiArcsec / 3600.0, dEpsArcsec / 3600.0);
  }

  /// Mean obliquity of the ecliptic (degrees) for a Julian Date, per the
  /// IAU 1980 polynomial (Meeus eq. 22.2).
  static double meanObliquity(double jd) {
    final t = (jd - _j2000) / 36525;
    // Coefficients in arcseconds, expressed about epsilon0 = 23°26'21.448".
    const eps0 = 23.0 + 26.0 / 60.0 + 21.448 / 3600.0;
    return eps0 -
        (46.8150 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3600.0;
  }

  /// Precess equatorial coordinates from J2000.0 to the equinox of [dt],
  /// then apply nutation, yielding apparent RA/Dec referred to the true
  /// equator and equinox of date.
  ///
  /// Uses the rigorous IAU 1976 precession angles (Lieske) followed by the
  /// classic nutation rotation. Inputs and outputs are degrees. This is what
  /// the coordinate grid and rise/set logic should use to place J2000 catalog
  /// positions in the sky of the requested instant.
  static (double raDeg, double decDeg) precessFromJ2000ToDate({
    required double raDeg,
    required double decDeg,
    required DateTime dt,
  }) {
    final jd = julianDate(dt);
    final t = (jd - _j2000) / 36525;

    // IAU 1976 precession angles (arcseconds), accumulated since J2000.
    final zeta =
        (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) /
        3600.0 *
        _deg2rad;
    final z =
        (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) /
        3600.0 *
        _deg2rad;
    final theta =
        (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) /
        3600.0 *
        _deg2rad;

    final ra0 = raDeg * _deg2rad;
    final dec0 = decDeg * _deg2rad;

    // Precession rotation (Meeus eq. 21.4).
    final a = math.cos(dec0) * math.sin(ra0 + zeta);
    final b =
        math.cos(theta) * math.cos(dec0) * math.cos(ra0 + zeta) -
        math.sin(theta) * math.sin(dec0);
    final c =
        math.sin(theta) * math.cos(dec0) * math.cos(ra0 + zeta) +
        math.cos(theta) * math.sin(dec0);

    var raDate = math.atan2(a, b) + z;
    final decDate = math.asin(c.clamp(-1.0, 1.0));

    // Apply nutation (rotate by dPsi about the ecliptic pole, working in the
    // equatorial frame via the standard first-order correction).
    final (dPsi, dEps) = nutation(jd);
    final eps = (meanObliquity(jd) + dEps) * _deg2rad;
    final dPsiRad = dPsi * _deg2rad;
    final dEpsRad = dEps * _deg2rad;

    final dRa =
        (math.cos(eps) + math.sin(eps) * math.sin(raDate) * math.tan(decDate)) *
            dPsiRad -
        (math.cos(raDate) * math.tan(decDate)) * dEpsRad;
    final dDec =
        (math.sin(eps) * math.cos(raDate)) * dPsiRad +
        math.sin(raDate) * dEpsRad;

    raDate += dRa;
    var raOut = raDate * _rad2deg;
    raOut = raOut % 360;
    if (raOut < 0) raOut += 360;

    return (raOut, (decDate + dDec) * _rad2deg);
  }

  /// Exact inverse of [precessFromJ2000ToDate]: takes apparent RA/Dec referred
  /// to the true equator and equinox of [dt] and returns the mean J2000 place.
  ///
  /// The planetarium draws EVERYTHING in one frame, and that frame is J2000 —
  /// the frame the star and DSO catalogues are published in. Ephemerides
  /// (VSOP87D planets, the Sun, the Moon) naturally come out referred to the
  /// equinox of date, so they are brought here before they reach the chart.
  /// Without it the two families were drawn ~22 arcmin apart in 2026 — Jupiter
  /// sat two thirds of a Moon diameter away from where it really is against
  /// M44 — which is worse than either frame chosen consistently.
  ///
  /// Nutation is removed first (the forward transform applies it last), then
  /// the precession rotation is inverted with Meeus eq. 21.5. Inputs and
  /// outputs are degrees.
  static (double raDeg, double decDeg) precessFromDateToJ2000({
    required double raDeg,
    required double decDeg,
    required DateTime dt,
  }) {
    final jd = julianDate(dt);
    final t = (jd - _j2000) / 36525;

    // Undo nutation. The forward correction is evaluated at the MEAN place, so
    // simply subtracting it evaluated at the apparent place leaves a
    // second-order residual — a few milliarcseconds, amplified by tan(dec) near
    // the pole. One fixed-point refinement (re-evaluate at the recovered mean
    // place) drives it below a microarcsecond, which is what makes this the
    // exact inverse of [precessFromJ2000ToDate] rather than an approximation
    // that quietly drifts.
    final (dPsi, dEps) = nutation(jd);
    final eps = (meanObliquity(jd) + dEps) * _deg2rad;
    final dPsiRad = dPsi * _deg2rad;
    final dEpsRad = dEps * _deg2rad;

    (double, double) nutationOffset(double ra, double dec) => (
      (math.cos(eps) + math.sin(eps) * math.sin(ra) * math.tan(dec)) * dPsiRad -
          (math.cos(ra) * math.tan(dec)) * dEpsRad,
      (math.sin(eps) * math.cos(ra)) * dPsiRad + math.sin(ra) * dEpsRad,
    );

    final raApp = raDeg * _deg2rad;
    final decApp = decDeg * _deg2rad;

    var (dRa, dDec) = nutationOffset(raApp, decApp);
    (dRa, dDec) = nutationOffset(raApp - dRa, decApp - dDec);

    final raDate = raApp - dRa;
    final decDate = decApp - dDec;

    // Same IAU 1976 angles as the forward transform.
    final zeta =
        (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) /
        3600.0 *
        _deg2rad;
    final z =
        (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) /
        3600.0 *
        _deg2rad;
    final theta =
        (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) /
        3600.0 *
        _deg2rad;

    // Meeus eq. 21.5 — the reverse rotation.
    final a = math.cos(decDate) * math.sin(raDate - z);
    final b =
        math.cos(theta) * math.cos(decDate) * math.cos(raDate - z) +
        math.sin(theta) * math.sin(decDate);
    final c =
        math.cos(theta) * math.sin(decDate) -
        math.sin(theta) * math.cos(decDate) * math.cos(raDate - z);

    var raOut = (math.atan2(a, b) - zeta) * _rad2deg;
    raOut = raOut % 360;
    if (raOut < 0) raOut += 360;

    return (raOut, math.asin(c.clamp(-1.0, 1.0)) * _rad2deg);
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
    final c =
        (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(mRad) +
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
  static const double _refractionAtHorizon = -0.5667; // -34/60

  /// Sun rise/set altitude: -34' (refraction) - 16' (semi-diameter) = -50'
  ///
  /// GEOMETRIC (unrefracted) altitude of the Sun's CENTRE, the USNO/NOAA
  /// convention — the -34' term is the refraction allowance, it is not a value
  /// to be compared against an already-refracted altitude. See [_apparentLimb].
  static const double _sunRiseSetAltitude = -0.8333; // -50/60

  /// Moon rise/set altitude: -34' (refraction) - 16' (semi-diameter) + 8' (parallax) ≈ -42'
  ///
  /// Geometric, on the same footing as [_sunRiseSetAltitude].
  static const double _moonRiseSetAltitude = -0.7; // Approximate

  /// Twilight type enumeration
  static const double civilTwilightAngle = -6.0;
  static const double nauticalTwilightAngle = -12.0;
  static const double astronomicalTwilightAngle = -18.0;

  /// The APPARENT altitude a body shows when its GEOMETRIC centre altitude is
  /// [geometricAltDeg].
  ///
  /// Every crossing search in this file evaluates apparent altitude
  /// ([sunAltitude] and `_apparentAltitudeOf` both add Sæmundsson refraction),
  /// but [_sunRiseSetAltitude] / [_moonRiseSetAltitude] are geometric
  /// conventions that already spend -34' on refraction. Comparing the two
  /// directly counted refraction twice: sunset came out ~3.5 min late and
  /// sunrise ~4.5 min early (symmetric, ~7.5 min of daylight invented), while
  /// the twilight angles were unharmed only because [atmosphericRefraction] is
  /// suppressed below -2°. Refraction is monotonic in altitude here, so
  /// crossing `apparent == _apparentLimb(x)` is exactly crossing
  /// `geometric == x` — which is what USNO/NOAA publish.
  static double _apparentLimb(double geometricAltDeg) =>
      trueToApparentAltitude(geometricAltDeg);

  /// Find time when sun crosses given altitude.
  ///
  /// A coarse 10-minute scan first brackets the FIRST crossing in the
  /// requested direction, then bisection refines inside that bracket.
  /// The previous implementation compared only the window's endpoint
  /// altitudes and bailed when their signs matched — which silently
  /// returns null whenever the window contains zero OR two crossings.
  /// That is exactly what happens at high latitudes / west-of-meridian
  /// timezones where sunset slips past local midnight, and what would
  /// happen everywhere once the search windows are widened to cover
  /// those sites. Direction-aware bracketing makes wide windows safe.
  static DateTime? _findSunAltitudeCrossing({
    required DateTime startTime,
    required DateTime endTime,
    required double targetAlt,
    required double latitudeDeg,
    required double longitudeDeg,
    required bool rising,
  }) {
    const step = Duration(minutes: 10);
    double altAt(DateTime t) => sunAltitude(
      dt: t,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );

    var t = startTime;
    var delta = altAt(t) - targetAlt;
    if (delta.abs() < 0.001) return t;

    DateTime? bracketLo;
    DateTime? bracketHi;
    while (t.isBefore(endTime)) {
      var next = t.add(step);
      if (next.isAfter(endTime)) next = endTime;
      final nextDelta = altAt(next) - targetAlt;
      if (nextDelta.abs() < 0.001) return next;

      final crossesDown = delta > 0 && nextDelta < 0;
      final crossesUp = delta < 0 && nextDelta > 0;
      if ((rising && crossesUp) || (!rising && crossesDown)) {
        bracketLo = t;
        bracketHi = next;
        break;
      }
      t = next;
      delta = nextDelta;
    }
    if (bracketLo == null || bracketHi == null) {
      // No crossing in the requested direction — legitimately null at
      // polar latitudes (sun never reaches the target altitude tonight).
      return null;
    }

    var t1 = bracketLo;
    var t2 = bracketHi;
    for (var i = 0; i < 50; i++) {
      final tMid = t1.add(
        Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
      );
      final alt = altAt(tMid);

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

    return t1.add(
      Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
    );
  }

  /// Calculate twilight times for a given date and location
  static TwilightTimes calculateTwilightTimes({
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    // Anchor the search on the SITE's solar noon, not the machine's
    // civil noon. Each event below is found independently as "first
    // crossing in its window" — if the windows were cut on the machine's
    // civil day, a site far from the machine's timezone (remote/headless
    // rig, or simply a high-latitude site where sunset slips past local
    // midnight) gets events from different solar days mixed into one
    // "night" (dusk before sunset, dawn after sunrise). Anchoring on the
    // site's solar day keeps every event on the same night for any
    // machine-TZ/site combination.
    final localNoon = DateTime(date.year, date.month, date.day, 12);
    final tzOffsetHours = localNoon.timeZoneOffset.inMinutes / 60.0;
    final siteSolarNoon = localNoon.add(
      Duration(minutes: ((tzOffsetHours - longitudeDeg / 15.0) * 60).round()),
    );

    // Evening events: first DESCENDING crossing after the site's solar
    // noon. Morning events: first RISING crossing after the site's solar
    // midnight. The generous spans are safe because the direction-aware
    // bracketing in [_findSunAltitudeCrossing] cannot latch onto the
    // wrong crossing.
    final eveningStart = siteSolarNoon;
    final eveningEnd = siteSolarNoon.add(const Duration(hours: 24));
    final morningStart = siteSolarNoon.subtract(const Duration(hours: 12));
    final morningEnd = siteSolarNoon.add(const Duration(hours: 6));

    return TwilightTimes(
      sunset: _findSunAltitudeCrossing(
        startTime: eveningStart,
        endTime: eveningEnd,
        // Geometric -0.8333° expressed on the apparent scale the search
        // runs on, so refraction is not counted twice.
        targetAlt: _apparentLimb(_sunRiseSetAltitude),
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
        // Geometric -0.8333° expressed on the apparent scale the search
        // runs on, so refraction is not counted twice.
        targetAlt: _apparentLimb(_sunRiseSetAltitude),
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
        rising: true,
      ),
    );
  }

  /// Calculate darkness hours between astronomical dusk and dawn
  static Duration? darknessHours(TwilightTimes twilight) {
    if (twilight.astronomicalDusk != null &&
        twilight.astronomicalDawn != null) {
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
    final (ra, dec) = eclipticToEquatorial(
      lonDeg: lon,
      latDeg: lat,
      obliquityDeg: eps,
    );

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

    final cosE =
        math.sin(sunDecRad) * math.sin(moonDecRad) +
        math.cos(sunDecRad) *
            math.cos(moonDecRad) *
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
    var prevAlt = moonAltitude(
      dt: searchStart,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );

    for (
      var t = searchStart;
      t.isBefore(searchEnd);
      t = t.add(const Duration(minutes: 30))
    ) {
      final alt = moonAltitude(
        dt: t,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
      );

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
      final tMid = t1.add(
        Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
      );
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
    return t1.add(
      Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
    );
  }

  // ============================================================================
  // Object Rise/Set/Transit Calculations
  // ============================================================================

  /// Apparent altitude (degrees, including refraction) of a body at [dt].
  ///
  /// [positionAt] supplies the body's RA/Dec; for a fixed object pass a closure
  /// that ignores its argument and returns the constant J2000 (or precessed)
  /// coordinates.
  static double _apparentAltitudeOf(
    DateTime dt,
    EquatorialPositionAt positionAt,
    double latitudeDeg,
    double longitudeDeg,
  ) {
    final (ra, dec) = positionAt(dt);
    final lst = localSiderealTime(dt, longitudeDeg);
    final (trueAlt, _) = equatorialToHorizontal(
      raDeg: ra,
      decDeg: dec,
      latitudeDeg: latitudeDeg,
      lstHours: lst,
    );
    return trueToApparentAltitude(trueAlt);
  }

  /// Find the instant within [start, end] where the body's apparent altitude
  /// crosses [targetAlt]. Requires the endpoints to straddle the target (their
  /// `altitude - targetAlt` signs differ); returns null otherwise. Bisection
  /// recomputes the body position each step, so it tracks moving bodies and
  /// converges to well under one minute.
  static DateTime? _refineAltitudeCrossing({
    required DateTime start,
    required DateTime end,
    required double targetAlt,
    required EquatorialPositionAt positionAt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    var t1 = start;
    var t2 = end;
    var d1 =
        _apparentAltitudeOf(t1, positionAt, latitudeDeg, longitudeDeg) -
        targetAlt;
    final d2 =
        _apparentAltitudeOf(t2, positionAt, latitudeDeg, longitudeDeg) -
        targetAlt;
    if (d1.sign == d2.sign) return null;

    while (t2.difference(t1).inSeconds.abs() > 1) {
      final tMid = t1.add(
        Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
      );
      final dMid =
          _apparentAltitudeOf(tMid, positionAt, latitudeDeg, longitudeDeg) -
          targetAlt;
      if (dMid == 0) return tMid;
      if (dMid.sign == d1.sign) {
        t1 = tMid;
        d1 = dMid;
      } else {
        t2 = tMid;
      }
    }
    return t1.add(
      Duration(milliseconds: t2.difference(t1).inMilliseconds ~/ 2),
    );
  }

  /// The rise that began the up-period already in progress at [windowStart].
  ///
  /// Samples backwards from [windowStart] (up to a day) for the last instant
  /// the body was below [targetAlt], then refines the crossing. Returns null if
  /// it never was — a circumpolar body has no rise to report.
  static DateTime? _findRiseBefore({
    required DateTime windowStart,
    required Duration step,
    required double targetAlt,
    required EquatorialPositionAt positionAt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    if (_apparentAltitudeOf(
          windowStart,
          positionAt,
          latitudeDeg,
          longitudeDeg,
        ) <
        targetAlt) {
      return null;
    }
    final searchStart = windowStart.subtract(const Duration(hours: 24));
    var later = windowStart;
    for (
      var t = windowStart.subtract(step);
      !t.isBefore(searchStart);
      t = t.subtract(step)
    ) {
      if (_apparentAltitudeOf(t, positionAt, latitudeDeg, longitudeDeg) <
          targetAlt) {
        return _refineAltitudeCrossing(
          start: t,
          end: later,
          targetAlt: targetAlt,
          positionAt: positionAt,
          latitudeDeg: latitudeDeg,
          longitudeDeg: longitudeDeg,
        );
      }
      later = t;
    }
    return null;
  }

  /// The calendar date of the night that CONTAINS [instant] — the value to pass
  /// as `date` to [calculateObjectVisibility] when all you hold is a timestamp.
  ///
  /// The observing night runs local noon to local noon, so anything before noon
  /// belongs to the night that started the previous day. Callers that handed an
  /// instant straight to `date` silently described the FOLLOWING night whenever
  /// that instant had crossed midnight, which is a whole sidereal day (~4 min)
  /// of error in every rise/transit/set time they reported.
  static DateTime nightDateOf(DateTime instant) {
    final d = instant.hour < 12
        ? instant.subtract(const Duration(days: 1))
        : instant;
    return instant.isUtc
        ? DateTime.utc(d.year, d.month, d.day)
        : DateTime(d.year, d.month, d.day);
  }

  /// Calculate rise, transit, and set times for an object.
  ///
  /// The window scanned is the local day of [date] from noon to the following
  /// noon (the natural span for "tonight"). [date] is therefore the DATE of the
  /// night, not an instant within it — only its calendar day is read. Passing a
  /// timestamp that has already crossed local midnight (astronomical dusk in
  /// mid-summer, say) selects the NEXT night, which is how the planetarium's
  /// "Best Targets Tonight" list came to report transit times a sidereal day
  /// out while the same screen's Info tab reported them correctly. Convert an
  /// instant with [nightDateOf].
  ///
  /// The three times describe ONE pass of the sky: rise < transit < set, and
  /// the rise may fall before the window when the body is already up as it
  /// opens. Which pass is reported is decided by the transit — the window's
  /// altitude maximum — so it is the culmination the window was opened for.
  ///
  /// The algorithm samples apparent
  /// altitude at a fine step, brackets each rise/set crossing, then bisects to
  /// sub-minute accuracy. Transit is located by sampling for the altitude
  /// maximum and refining it. All steps recompute the body's position via
  /// [positionAt], so Sun/Moon/planets are handled correctly across the night;
  /// fixed catalog objects omit [positionAt] and use their constant RA/Dec.
  ///
  /// [minAltitude] is the altitude that defines "up" for rise/set (default 0°,
  /// i.e. the geometric horizon). [standardAltitude] overrides the altitude
  /// actually used for the crossing search — pass e.g. -0.833° for the Sun/Moon
  /// limb (refraction + semi-diameter). When omitted it follows [minAltitude].
  static ObjectVisibility calculateObjectVisibility({
    required double raDeg,
    required double decDeg,
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
    double minAltitude = 0,
    double? standardAltitude,
    EquatorialPositionAt? positionAt,
  }) {
    final localNoon = DateTime(date.year, date.month, date.day, 12);
    final windowEnd = localNoon.add(const Duration(hours: 24));
    final crossingAlt = standardAltitude ?? minAltitude;

    // Position source: moving body or constant catalog coordinates.
    final posAt = positionAt ?? ((DateTime _) => (raDeg, decDeg));

    // Sample altitude every 5 minutes across the window. A 5-min step is fine
    // enough that even the Moon (~0.5°/hr in altitude near the horizon) cannot
    // skip a crossing, while keeping the loop cheap.
    const step = Duration(minutes: 5);
    final samples = <(DateTime, double)>[];
    for (var t = localNoon; !t.isAfter(windowEnd); t = t.add(step)) {
      samples.add((
        t,
        _apparentAltitudeOf(t, posAt, latitudeDeg, longitudeDeg),
      ));
    }

    DateTime? riseTime;
    DateTime? setTime;
    DateTime? transitTime;
    var maxAlt = -91.0;
    var minSampledAlt = 91.0;

    for (var i = 0; i < samples.length; i++) {
      final (t, alt) = samples[i];
      if (alt > maxAlt) {
        maxAlt = alt;
        transitTime = t;
      }
      if (alt < minSampledAlt) minSampledAlt = alt;

      if (i == 0) continue;
      final (prevT, prevAlt) = samples[i - 1];

      // Rising crossing.
      if (riseTime == null && prevAlt < crossingAlt && alt >= crossingAlt) {
        riseTime = _refineAltitudeCrossing(
          start: prevT,
          end: t,
          targetAlt: crossingAlt,
          positionAt: posAt,
          latitudeDeg: latitudeDeg,
          longitudeDeg: longitudeDeg,
        );
      }
      // Setting crossing (prefer one after rise when both exist in window).
      if (prevAlt >= crossingAlt && alt < crossingAlt) {
        final candidate = _refineAltitudeCrossing(
          start: prevT,
          end: t,
          targetAlt: crossingAlt,
          positionAt: posAt,
          latitudeDeg: latitudeDeg,
          longitudeDeg: longitudeDeg,
        );
        if (candidate != null &&
            (setTime == null ||
                (riseTime != null && candidate.isAfter(riseTime)))) {
          setTime = candidate;
        }
      }
    }

    // When the object is already above the threshold at local noon, the first
    // crossing in this 24-hour window is a SET and the next RISE occurs near
    // the end of the window. Returning those two timestamps made
    // durationAboveHorizon negative and exposed an impossible negative-hours
    // result through the scheduler API.
    //
    // Two different objects land in that ordering, and they need opposite
    // repairs. The transit says which: it is the window's altitude maximum, so
    // it belongs to whichever up-period actually culminates inside the window.
    //
    //  * Transit BEFORE the late rise — an object that culminates in the
    //    afternoon and sets in the evening. The set found in the window is the
    //    right one; the rise that began this period lies BEFORE the window.
    //    Pair that set with the rise before the window.
    //  * Transit AFTER the late rise — an object whose up-period starts late in
    //    the window. That rise is the right one and its set lies beyond the
    //    window, so sample forward for it.
    if (riseTime != null &&
        setTime != null &&
        !setTime.isAfter(riseTime) &&
        transitTime != null &&
        transitTime.isBefore(riseTime)) {
      riseTime =
          _findRiseBefore(
            windowStart: localNoon,
            step: step,
            targetAlt: crossingAlt,
            positionAt: posAt,
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
          ) ??
          riseTime;
    } else if (riseTime != null &&
        setTime != null &&
        !setTime.isAfter(riseTime)) {
      final searchEnd = riseTime.add(const Duration(hours: 24));
      var previousTime = riseTime;
      var previousAltitude = _apparentAltitudeOf(
        previousTime,
        posAt,
        latitudeDeg,
        longitudeDeg,
      );
      DateTime? followingSet;
      for (
        var t = previousTime.add(step);
        !t.isAfter(searchEnd);
        t = t.add(step)
      ) {
        final altitude = _apparentAltitudeOf(
          t,
          posAt,
          latitudeDeg,
          longitudeDeg,
        );
        if (previousAltitude >= crossingAlt && altitude < crossingAlt) {
          followingSet = _refineAltitudeCrossing(
            start: previousTime,
            end: t,
            targetAlt: crossingAlt,
            positionAt: posAt,
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
          );
          break;
        }
        previousTime = t;
        previousAltitude = altitude;
      }
      if (followingSet != null) {
        setTime = followingSet;
      }
    }

    // Refine the transit by maximising apparent altitude in the interval
    // bracketing the coarse peak sample (ternary search, sub-minute).
    if (transitTime != null) {
      transitTime = _refineTransit(
        peak: transitTime,
        step: step,
        windowStart: localNoon,
        windowEnd: windowEnd,
        positionAt: posAt,
        latitudeDeg: latitudeDeg,
        longitudeDeg: longitudeDeg,
      );
    }

    // Transit altitude from the precessed/peak position (not the lat/dec
    // shortcut, which ignores both refraction and the body's motion).
    final transitAltitude = transitTime != null
        ? _apparentAltitudeOf(transitTime, posAt, latitudeDeg, longitudeDeg)
        : maxAlt;

    final isCircumpolar =
        riseTime == null && setTime == null && minSampledAlt >= crossingAlt;
    final neverRises =
        riseTime == null && setTime == null && maxAlt < crossingAlt;

    return ObjectVisibility(
      riseTime: riseTime,
      transitTime: neverRises ? null : transitTime,
      setTime: setTime,
      transitAltitude: transitAltitude,
      isCircumpolar: isCircumpolar,
      neverRises: neverRises,
    );
  }

  /// Refine the meridian transit near a coarse [peak] sample by maximising
  /// apparent altitude with a ternary search over the bracketing interval.
  static DateTime _refineTransit({
    required DateTime peak,
    required Duration step,
    required DateTime windowStart,
    required DateTime windowEnd,
    required EquatorialPositionAt positionAt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    var lo = peak.subtract(step);
    if (lo.isBefore(windowStart)) lo = windowStart;
    var hi = peak.add(step);
    if (hi.isAfter(windowEnd)) hi = windowEnd;

    double altAt(DateTime t) =>
        _apparentAltitudeOf(t, positionAt, latitudeDeg, longitudeDeg);

    while (hi.difference(lo).inSeconds > 1) {
      final third = hi.difference(lo).inMilliseconds ~/ 3;
      final m1 = lo.add(Duration(milliseconds: third));
      final m2 = hi.subtract(Duration(milliseconds: third));
      if (altAt(m1) < altAt(m2)) {
        lo = m1;
      } else {
        hi = m2;
      }
    }
    return lo.add(
      Duration(milliseconds: hi.difference(lo).inMilliseconds ~/ 2),
    );
  }

  /// Sun rise/transit/set for the local day of [date], tracking the Sun's
  /// motion and using the standard -0.833° limb altitude.
  ///
  /// One daytime pass: rise, culmination and set all belong to [date]. For the
  /// dusk-tonight → dawn-tomorrow span the night strip draws, use
  /// [calculateTwilightTimes] — that pairs this sunset with the NEXT sunrise.
  static ObjectVisibility calculateSunVisibility({
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final (ra0, dec0) = sunPosition(date);
    return calculateObjectVisibility(
      raDeg: ra0,
      decDeg: dec0,
      date: date,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      standardAltitude: _apparentLimb(_sunRiseSetAltitude),
      positionAt: (dt) => sunPosition(dt),
    );
  }

  /// Moon rise/transit/set for the local day of [date], tracking the Moon's
  /// fast motion and using the approximate -0.7° limb altitude.
  static ObjectVisibility calculateMoonVisibility({
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final (ra0, dec0, _) = moonPosition(date);
    return calculateObjectVisibility(
      raDeg: ra0,
      decDeg: dec0,
      date: date,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      standardAltitude: _apparentLimb(_moonRiseSetAltitude),
      positionAt: (dt) {
        final (ra, dec, _) = moonPosition(dt);
        return (ra, dec);
      },
    );
  }

  /// True (geometric) altitude and azimuth of a catalog object at [dt].
  ///
  /// [raDeg]/[decDeg] are J2000 catalog coordinates — what every Nightshade
  /// catalog and target row stores — and are precessed (and nutated) to the
  /// equinox of [dt] before the hour angle is formed, because the hour angle is
  /// measured from the equinox of DATE. Skipping that step is not a rounding
  /// error: a quarter-century past J2000 the equinox has moved ~22 arcmin, and
  /// because the azimuth error is amplified by 1/cos(altitude) it reached 1.4
  /// degrees for a near-zenith target in the audited case — enough to mis-call
  /// an obstruction check or a meridian flip. [precessFromJ2000ToDate] existed
  /// for exactly this and had no callers.
  ///
  /// Refraction is deliberately NOT applied: callers use this for pointing and
  /// altitude limits, which are geometric. Use [trueToApparentAltitude] on the
  /// result where the observed (refracted) altitude is what is wanted.
  static (double alt, double az) objectAltAz({
    required double raDeg,
    required double decDeg,
    required DateTime dt,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    final (raOfDate, decOfDate) = precessFromJ2000ToDate(
      raDeg: raDeg,
      decDeg: decDeg,
      dt: dt,
    );
    final lst = localSiderealTime(dt, longitudeDeg);
    return equatorialToHorizontal(
      raDeg: raOfDate,
      decDeg: decOfDate,
      latitudeDeg: latitudeDeg,
      lstHours: lst,
    );
  }

  // ============================================================================
  // Meridian / Meridian-Flip Geometry
  // ============================================================================

  /// Hour angle of a target (degrees) for the given instant and location.
  ///
  /// HA = LST - RA, normalised to (-180, 180]. Negative means the target is
  /// east of the local meridian (rising side); positive means west (setting
  /// side); zero is the meridian transit. This is the quantity a German
  /// equatorial mount uses to decide which side of the pier it must sit on, so
  /// it is the geometric basis of the meridian-flip marker.
  static double hourAngleDeg({
    required double raDeg,
    required DateTime dt,
    required double longitudeDeg,
  }) {
    final lst = localSiderealTime(dt, longitudeDeg);
    var ha = lst * 15 - raDeg;
    ha = ha % 360;
    if (ha > 180) ha -= 360;
    if (ha <= -180) ha += 360;
    return ha;
  }

  /// The meridian-flip window for a target on the local day of [date].
  ///
  /// The flip itself happens at the target's meridian transit (hour angle 0),
  /// which is exactly the transit returned by [calculateObjectVisibility]. A
  /// real GEM is usually allowed to track a little past the meridian before the
  /// flip is forced; [pastMeridianMinutes] expresses that limit as the latest
  /// time imaging can continue on the east side before the flip is required.
  ///
  /// Returns null when the target never transits on this day (never rises), so
  /// callers can skip the marker entirely rather than draw a meaningless one.
  static MeridianFlipWindow? calculateMeridianFlip({
    required double raDeg,
    required double decDeg,
    required DateTime date,
    required double latitudeDeg,
    required double longitudeDeg,
    double pastMeridianMinutes = 0,
  }) {
    final visibility = calculateObjectVisibility(
      raDeg: raDeg,
      decDeg: decDeg,
      date: date,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
    );
    final transit = visibility.transitTime;
    if (transit == null) return null;
    return MeridianFlipWindow(
      transitTime: transit,
      flipDeadline: transit.add(Duration(minutes: pastMeridianMinutes.round())),
      transitAltitude: visibility.transitAltitude,
    );
  }

  // ============================================================================
  // Airmass Calculation
  // ============================================================================

  /// Airmass for planning surfaces, with the scheduler's convention applied.
  ///
  /// The number itself comes from [airmassForTrueAltitude] — the product's one
  /// model — so the altitude chart, the target score and the FITS `AIRMASS`
  /// card of the frame that gets captured all describe the same atmosphere.
  ///
  /// The one thing layered on top is a deliberate, named CONVENTION: an object
  /// at or below the horizon scores as `infinity` rather than "unknown", so
  /// weighted target scoring drives it to zero instead of having to special-case
  /// a null. This mirrors `nightshade_sequencer::scheduling::astronomy::airmass`
  /// on the Rust side, which does the same for the same reason.
  static double airmass(double altitudeDeg) {
    if (altitudeDeg <= 0) return double.infinity;
    return airmassForTrueAltitude(altitudeDeg) ?? double.infinity;
  }

  // ============================================================================
  // Angular Separation
  // ============================================================================

  /// Calculate angular separation between two sky coordinates (degrees).
  ///
  /// The haversine form is used rather than the spherical law of cosines
  /// because the app compares separations at arcsecond scale — coincident-star
  /// merging, catalog cone search, guide-star matching. At those separations
  /// `acos` of a cosine within ~1e-16 of 1 loses roughly half the mantissa,
  /// which is the difference between two distinct stars and one.
  static double angularSeparation({
    required double ra1Deg,
    required double dec1Deg,
    required double ra2Deg,
    required double dec2Deg,
  }) {
    final dec1 = dec1Deg * _deg2rad;
    final dec2 = dec2Deg * _deg2rad;
    final dRa = (ra2Deg - ra1Deg) * _deg2rad;
    final dDec = dec2 - dec1;

    final sinHalfDec = math.sin(dDec / 2);
    final sinHalfRa = math.sin(dRa / 2);
    final a =
        sinHalfDec * sinHalfDec +
        math.cos(dec1) * math.cos(dec2) * sinHalfRa * sinHalfRa;

    return 2 *
        math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1 - a))) *
        _rad2deg;
  }

  /// Position angle of the second point as seen from the first, measured at the
  /// first point from celestial North through East (degrees, 0–360).
  ///
  /// This is the standard astronomical convention used for double-star and
  /// reference-frame measurements: 0° = the companion lies due north of the
  /// primary, 90° = due east, 180° = south, 270° = west. The angle is computed
  /// on the sphere (great-circle bearing), so it is exact for any separation
  /// rather than a flat-sky approximation.
  ///
  /// Returns 0 when the two points coincide (degenerate, undefined PA).
  static double positionAngle({
    required double ra1Deg,
    required double dec1Deg,
    required double ra2Deg,
    required double dec2Deg,
  }) {
    final dec1 = dec1Deg * _deg2rad;
    final dec2 = dec2Deg * _deg2rad;
    final deltaRa = (ra2Deg - ra1Deg) * _deg2rad;

    final y = math.sin(deltaRa) * math.cos(dec2);
    final x =
        math.cos(dec1) * math.sin(dec2) -
        math.sin(dec1) * math.cos(dec2) * math.cos(deltaRa);

    if (x.abs() < _epsilon && y.abs() < _epsilon) return 0;

    var pa = math.atan2(y, x) * _rad2deg;
    if (pa < 0) pa += 360;
    return pa;
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

/// Meridian-flip planning window for a target.
///
/// [transitTime] is the instant the target crosses the local meridian (hour
/// angle 0) — the moment a German equatorial mount must flip. [flipDeadline]
/// is the latest time tracking may continue past the meridian before the flip
/// is forced (equal to [transitTime] when no past-meridian limit is given).
class MeridianFlipWindow {
  final DateTime transitTime;
  final DateTime flipDeadline;
  final double? transitAltitude;

  const MeridianFlipWindow({
    required this.transitTime,
    required this.flipDeadline,
    this.transitAltitude,
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
