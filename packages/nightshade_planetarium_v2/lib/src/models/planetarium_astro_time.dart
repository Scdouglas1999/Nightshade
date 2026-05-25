import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Planetarium v2 astronomical time (Julian dates for the Rust renderer).
class PlanetariumAstroTime {
  const PlanetariumAstroTime({
    required this.jdUtc,
    required this.jdUt1,
    required this.jdTt,
  });

  final double jdUtc;
  final double jdUt1;
  final double jdTt;

  /// Builds TT/UT1-corrected Julian dates from a UTC [DateTime].
  ///
  /// Leap-second table and ΔUT1 policy mirror
  /// `native/nightshade_native/planetarium/src/astrometry/time.rs`.
  factory PlanetariumAstroTime.fromDateTime(DateTime dateTime) {
    final utc = dateTime.toUtc();
    final jdUtc = SkyCalculations.julianDate(utc);
    final ttOffsetDays = _ttMinusUtcSeconds(jdUtc) / _secondsPerDay;
    const ut1OffsetDays = 0.0; // ΔUT1 spline not loaded yet (Rust parity).
    return PlanetariumAstroTime(
      jdUtc: jdUtc,
      jdUt1: jdUtc + ut1OffsetDays,
      jdTt: jdUtc + ttOffsetDays,
    );
  }

  AstroTimeDto toDto() => AstroTimeDto(
        jdUtc: jdUtc,
        jdUt1: jdUt1,
        jdTt: jdTt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanetariumAstroTime &&
          jdUtc == other.jdUtc &&
          jdUt1 == other.jdUt1 &&
          jdTt == other.jdTt;

  @override
  int get hashCode => Object.hash(jdUtc, jdUt1, jdTt);
}

const double _secondsPerDay = 86400.0;
const double _ttMinusTaiSec = 32.184;

class _LeapSecondEpoch {
  const _LeapSecondEpoch({required this.jdUtc, required this.taiMinusUtc});

  final double jdUtc;
  final int taiMinusUtc;
}

/// IERS TAI−UTC step table (1972-01-01 through 2017-01-01; final offset 37 s).
const List<_LeapSecondEpoch> _leapSeconds = [
  _LeapSecondEpoch(jdUtc: 2441317.5, taiMinusUtc: 10),
  _LeapSecondEpoch(jdUtc: 2441485.5, taiMinusUtc: 11),
  _LeapSecondEpoch(jdUtc: 2441786.5, taiMinusUtc: 12),
  _LeapSecondEpoch(jdUtc: 2442351.5, taiMinusUtc: 13),
  _LeapSecondEpoch(jdUtc: 2442717.5, taiMinusUtc: 14),
  _LeapSecondEpoch(jdUtc: 2443082.5, taiMinusUtc: 15),
  _LeapSecondEpoch(jdUtc: 2443448.5, taiMinusUtc: 16),
  _LeapSecondEpoch(jdUtc: 2443813.5, taiMinusUtc: 17),
  _LeapSecondEpoch(jdUtc: 2444179.5, taiMinusUtc: 18),
  _LeapSecondEpoch(jdUtc: 2444544.5, taiMinusUtc: 19),
  _LeapSecondEpoch(jdUtc: 2445377.5, taiMinusUtc: 20),
  _LeapSecondEpoch(jdUtc: 2445743.5, taiMinusUtc: 21),
  _LeapSecondEpoch(jdUtc: 2446108.5, taiMinusUtc: 22),
  _LeapSecondEpoch(jdUtc: 2446839.5, taiMinusUtc: 23),
  _LeapSecondEpoch(jdUtc: 2447669.5, taiMinusUtc: 24),
  _LeapSecondEpoch(jdUtc: 2448400.5, taiMinusUtc: 25),
  _LeapSecondEpoch(jdUtc: 2448765.5, taiMinusUtc: 26),
  _LeapSecondEpoch(jdUtc: 2449232.5, taiMinusUtc: 27),
  _LeapSecondEpoch(jdUtc: 2449597.5, taiMinusUtc: 28),
  _LeapSecondEpoch(jdUtc: 2449962.5, taiMinusUtc: 29),
  _LeapSecondEpoch(jdUtc: 2450630.5, taiMinusUtc: 30),
  _LeapSecondEpoch(jdUtc: 2451098.5, taiMinusUtc: 31),
  _LeapSecondEpoch(jdUtc: 2451179.5, taiMinusUtc: 32),
  _LeapSecondEpoch(jdUtc: 2453737.5, taiMinusUtc: 33),
  _LeapSecondEpoch(jdUtc: 2455319.5, taiMinusUtc: 34),
  _LeapSecondEpoch(jdUtc: 2456109.5, taiMinusUtc: 35),
  _LeapSecondEpoch(jdUtc: 2456774.5, taiMinusUtc: 36),
  _LeapSecondEpoch(jdUtc: 2457663.5, taiMinusUtc: 37),
];

int _taiMinusUtcAtJdUtc(double jdUtc) {
  var offset = _leapSeconds.first.taiMinusUtc;
  for (final epoch in _leapSeconds) {
    if (jdUtc >= epoch.jdUtc) {
      offset = epoch.taiMinusUtc;
    } else {
      break;
    }
  }
  return offset;
}

double _ttMinusUtcSeconds(double jdUtc) =>
    _taiMinusUtcAtJdUtc(jdUtc) + _ttMinusTaiSec;
