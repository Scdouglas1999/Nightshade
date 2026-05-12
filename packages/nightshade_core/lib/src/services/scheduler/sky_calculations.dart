import 'dart:math' as math;

/// Pure astronomical helpers shared by the scheduler engine.
///
/// Altitude / azimuth / moon-position / great-circle separation already live
/// in `services/scheduler_service.dart` (the static scheduler). The dynamic
/// scheduler reuses those via composition and adds the twilight calculations
/// it needs, which the static service does not provide.

enum TwilightKind {
  civil, // sun -6°
  nautical, // sun -12°
  astronomical, // sun -18°
}

/// Sun altitude (degrees) corresponding to each twilight boundary.
const Map<TwilightKind, double> _twilightAltitudes = {
  TwilightKind.civil: -6.0,
  TwilightKind.nautical: -12.0,
  TwilightKind.astronomical: -18.0,
};

/// Result of computing twilight for a given local date and site.
///
/// `morningStart` is the instant the sun rises above the twilight altitude
/// (becoming brighter); `eveningEnd` is the instant the sun sinks below it
/// (becoming darker). Either field may be null when the sun never crosses
/// the threshold on that date (polar day/night).
class TwilightTimes {
  final TwilightKind kind;
  final DateTime? eveningEnd;
  final DateTime? morningStart;

  const TwilightTimes({
    required this.kind,
    required this.eveningEnd,
    required this.morningStart,
  });
}

/// Astronomical helpers wrapped in a small namespace.
class SkyCalculations {
  SkyCalculations._();

  /// Julian Date for the given DateTime (treated as UTC).
  static double julianDate(DateTime dt) {
    final utc = dt.toUtc();
    int y = utc.year;
    int m = utc.month;
    final d = utc.day +
        utc.hour / 24.0 +
        utc.minute / 1440.0 +
        utc.second / 86400.0 +
        utc.millisecond / 86400000.0;

    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        d +
        b -
        1524.5;
  }

  /// NREL Solar Position Algorithm (Reda & Andreas, 2003), simplified
  /// implementation accurate to <0.01° in solar position. Returns the
  /// sun's apparent (alt, az) in degrees at `time` for the given site.
  ///
  /// The full SPA paper performs nutation and aberration to arc-second
  /// precision; for twilight-boundary use (1-minute precision) we keep
  /// the higher-order corrections but skip the full nutation series.
  static (double altitude, double azimuth) sunAltAz({
    required DateTime time,
    required double latitudeDegrees,
    required double longitudeDegrees,
  }) {
    final jd = julianDate(time);
    final t = (jd - 2451545.0) / 36525.0;

    // Mean longitude (deg).
    var l0 = 280.46646 + t * (36000.76983 + t * 0.0003032);
    l0 = _wrap360(l0);

    // Mean anomaly (deg).
    var m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    m = _wrap360(m);
    final mRad = _deg2rad(m);

    // Equation of center (deg).
    final c = (1.914602 - t * (0.004817 + 0.000014 * t)) * math.sin(mRad) +
        (0.019993 - 0.000101 * t) * math.sin(2 * mRad) +
        0.000289 * math.sin(3 * mRad);

    // True longitude / apparent longitude (deg). Approximate aberration
    // by subtracting 0.00569° + 0.00478°·sin(omega).
    final trueLon = l0 + c;
    final omegaDeg = 125.04 - 1934.136 * t;
    final apparentLon =
        trueLon - 0.00569 - 0.00478 * math.sin(_deg2rad(omegaDeg));
    final apparentLonRad = _deg2rad(apparentLon);

    // Mean obliquity of ecliptic (deg) with nutation correction.
    final seconds = 21.448 -
        t * (46.8150 + t * (0.00059 - t * 0.001813));
    final meanObliquity = 23.0 + (26.0 + (seconds / 60.0)) / 60.0;
    final obliquity =
        meanObliquity + 0.00256 * math.cos(_deg2rad(omegaDeg));
    final obliquityRad = _deg2rad(obliquity);

    // Right ascension (rad), declination (rad).
    final ra = math.atan2(
      math.cos(obliquityRad) * math.sin(apparentLonRad),
      math.cos(apparentLonRad),
    );
    final dec = math.asin(math.sin(obliquityRad) * math.sin(apparentLonRad));

    // Greenwich mean sidereal time (deg) at time.
    var gmst = 280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000.0;
    gmst = _wrap360(gmst);

    // Local sidereal time, then local hour angle.
    final lst = _wrap360(gmst + longitudeDegrees);
    final raDeg = _wrap360(_rad2deg(ra));
    final hourAngleDeg = _wrap180(lst - raDeg);
    final haRad = _deg2rad(hourAngleDeg);

    final latRad = _deg2rad(latitudeDegrees);
    final sinAlt = math.sin(latRad) * math.sin(dec) +
        math.cos(latRad) * math.cos(dec) * math.cos(haRad);
    final altRad = math.asin(sinAlt.clamp(-1.0, 1.0));

    // Azimuth measured east of north.
    final y = -math.sin(haRad);
    final x = math.tan(dec) * math.cos(latRad) -
        math.sin(latRad) * math.cos(haRad);
    var az = math.atan2(y, x);
    if (az < 0) az += 2 * math.pi;

    return (_rad2deg(altRad), _rad2deg(az));
  }

  /// Find evening end (sun sinks below `targetAltitude`) and morning start
  /// (sun climbs back above it) for the local calendar date implied by
  /// `noonLocal`. Uses 1-minute bisection over the 24-hour window centered
  /// on the local solar transit.
  ///
  /// Returns nulls when the sun does not cross the threshold (polar
  /// regions in summer / winter).
  static TwilightTimes computeTwilight({
    required DateTime noonLocal,
    required double latitudeDegrees,
    required double longitudeDegrees,
    required TwilightKind kind,
  }) {
    final targetAlt = _twilightAltitudes[kind]!;
    final searchStart = noonLocal.toUtc();
    final searchEnd = searchStart.add(const Duration(hours: 24));

    DateTime? eveningEnd;
    DateTime? morningStart;

    // Sample every minute over 24h, looking for sign changes.
    DateTime prevT = searchStart;
    var (prevAlt, _) = sunAltAz(
      time: prevT,
      latitudeDegrees: latitudeDegrees,
      longitudeDegrees: longitudeDegrees,
    );
    for (var minute = 1; minute <= 24 * 60; minute++) {
      final t = searchStart.add(Duration(minutes: minute));
      final (alt, _) = sunAltAz(
        time: t,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: longitudeDegrees,
      );
      // Descending crossing -> evening end.
      if (prevAlt > targetAlt && alt <= targetAlt && eveningEnd == null) {
        eveningEnd = _bisectCrossing(
          t0: prevT,
          t1: t,
          alt0: prevAlt,
          alt1: alt,
          targetAlt: targetAlt,
          latitudeDegrees: latitudeDegrees,
          longitudeDegrees: longitudeDegrees,
        );
      }
      // Ascending crossing -> morning start.
      if (prevAlt < targetAlt && alt >= targetAlt && morningStart == null) {
        morningStart = _bisectCrossing(
          t0: prevT,
          t1: t,
          alt0: prevAlt,
          alt1: alt,
          targetAlt: targetAlt,
          latitudeDegrees: latitudeDegrees,
          longitudeDegrees: longitudeDegrees,
        );
      }
      prevAlt = alt;
      prevT = t;
      if (eveningEnd != null &&
          morningStart != null &&
          t.isAfter(searchEnd)) break;
    }

    return TwilightTimes(
      kind: kind,
      eveningEnd: eveningEnd,
      morningStart: morningStart,
    );
  }

  static DateTime _bisectCrossing({
    required DateTime t0,
    required DateTime t1,
    required double alt0,
    required double alt1,
    required double targetAlt,
    required double latitudeDegrees,
    required double longitudeDegrees,
  }) {
    var lo = t0;
    var hi = t1;
    var loAlt = alt0;
    var hiAlt = alt1;
    while (hi.difference(lo).inSeconds > 30) {
      final mid = lo.add(Duration(seconds: hi.difference(lo).inSeconds ~/ 2));
      final (midAlt, _) = sunAltAz(
        time: mid,
        latitudeDegrees: latitudeDegrees,
        longitudeDegrees: longitudeDegrees,
      );
      final loSign = (loAlt - targetAlt).sign;
      final midSign = (midAlt - targetAlt).sign;
      if (loSign == midSign) {
        lo = mid;
        loAlt = midAlt;
      } else {
        hi = mid;
        hiAlt = midAlt;
      }
    }
    return lo.add(Duration(seconds: hi.difference(lo).inSeconds ~/ 2));
  }

  /// Convenience: hours of darkness available between now and morning
  /// astronomical twilight (or evening end if night hasn't started).
  /// Returns 0 if the sun is up and the night has not yet begun, or if
  /// astronomical night never occurs at this site.
  static Duration darknessRemaining({
    required DateTime now,
    required double latitudeDegrees,
    required double longitudeDegrees,
  }) {
    final localNoon = DateTime(now.year, now.month, now.day, 12).toUtc();
    final tonight = computeTwilight(
      noonLocal: localNoon,
      latitudeDegrees: latitudeDegrees,
      longitudeDegrees: longitudeDegrees,
      kind: TwilightKind.astronomical,
    );
    final end = tonight.morningStart;
    if (end == null) return Duration.zero;
    final delta = end.difference(now.toUtc());
    if (delta.isNegative) return Duration.zero;
    return delta;
  }

  static double _wrap360(double d) {
    var v = d % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }

  static double _wrap180(double d) {
    var v = ((d + 180.0) % 360.0) - 180.0;
    if (v < -180.0) v += 360.0;
    return v;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
  static double _rad2deg(double r) => r * 180.0 / math.pi;
}
