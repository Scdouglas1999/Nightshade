import 'dart:math' as math;

/// J2000 celestial coordinate in RA hours / Dec degrees.
///
/// Plain value type for catalog and overlay data. Astrometric reduction
/// (precession, nutation, aberration, refraction, alt/az conversion) lives
/// in the Rust planetarium crate per the v2 design — Dart MUST NOT duplicate
/// it here. Use `viewPose`/`SceneSnapshot` for view-aligned coordinates that
/// already reflect frame-correct astrometry.
class CelestialCoordinate {
  const CelestialCoordinate({
    required this.ra,
    required this.dec,
  });

  /// Right Ascension in hours (0–24).
  final double ra;

  /// Declination in degrees (−90..+90).
  final double dec;

  /// RA in degrees.
  double get raDegrees => ra * 15;

  /// RA in radians.
  double get raRadians => raDegrees * math.pi / 180;

  /// Dec in radians.
  double get decRadians => dec * math.pi / 180;

  @override
  String toString() => 'RA: ${formatRA()}, Dec: ${formatDec()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelestialCoordinate && ra == other.ra && dec == other.dec;

  @override
  int get hashCode => Object.hash(ra, dec);

  /// Formats RA as hours, minutes, seconds.
  String formatRA({bool compact = false}) {
    final h = ra.floor();
    final m = ((ra - h) * 60).floor();
    final s = (ra - h - m / 60) * 3600;
    if (compact) {
      return '${h.toString().padLeft(2, '0')}h'
          '${m.toString().padLeft(2, '0')}m';
    }
    return '${h}h ${m}m ${s.toStringAsFixed(1)}s';
  }

  /// Formats Dec as degrees, arcminutes, arcseconds.
  String formatDec({bool compact = false}) {
    final sign = dec >= 0 ? '+' : '-';
    final d = dec.abs().floor();
    final m = ((dec.abs() - d) * 60).floor();
    final s = (dec.abs() - d - m / 60) * 3600;
    if (compact) {
      return "$sign${d.toString().padLeft(2, '0')}°"
          "${m.toString().padLeft(2, '0')}'";
    }
    return "$sign$d° $m' ${s.toStringAsFixed(1)}\"";
  }

  /// RA in HMS format suitable for sequencer/equipment.
  String get raHms => formatRA();

  /// Dec in DMS format suitable for sequencer/equipment.
  String get decDms => formatDec();

  /// Short form for display (e.g., `12h 30m, +45° 15'`).
  String get shortForm =>
      '${formatRA(compact: true)}, ${formatDec(compact: true)}';
}
