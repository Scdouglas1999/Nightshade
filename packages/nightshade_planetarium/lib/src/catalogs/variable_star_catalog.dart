import 'dart:math' as math;
import '../coordinate_system.dart';

/// Type of variable star
enum VariableStarType {
  /// Mira-type long period pulsating (e.g., Mira, Chi Cygni)
  mira,

  /// Cepheid pulsating (e.g., Delta Cephei, Eta Aquilae)
  cepheid,

  /// RR Lyrae pulsating (e.g., RR Lyrae)
  rrLyrae,

  /// Eclipsing binary Algol-type (e.g., Algol, Beta Lyrae)
  eclipsingAlgol,

  /// Eclipsing binary Beta Lyrae type
  eclipsingBetaLyr,

  /// Eclipsing binary W UMa type
  eclipsingWUma,

  /// Semi-regular pulsating (e.g., Betelgeuse, Antares)
  semiRegular,

  /// Irregular variable (e.g., Mu Cephei)
  irregular,

  /// Delta Scuti type
  deltaScuti,

  /// Gamma Cassiopeiae (eruptive Be star)
  gammaCas,

  /// R Coronae Borealis (eruptive, fades)
  rCrB,

  /// Nova or recurrent nova
  nova,

  /// Dwarf nova / cataclysmic
  dwarfNova,

  /// RS Canum Venaticorum (chromospherically active)
  rsCVn,

  /// BY Draconis (spotted rotating)
  byDra,

  /// Slowly pulsating B star
  spb,

  /// Other/unclassified
  other,
}

extension VariableStarTypeExtension on VariableStarType {
  String get displayName {
    switch (this) {
      case VariableStarType.mira:
        return 'Mira (Long Period)';
      case VariableStarType.cepheid:
        return 'Cepheid';
      case VariableStarType.rrLyrae:
        return 'RR Lyrae';
      case VariableStarType.eclipsingAlgol:
        return 'Eclipsing (Algol)';
      case VariableStarType.eclipsingBetaLyr:
        return 'Eclipsing (Beta Lyrae)';
      case VariableStarType.eclipsingWUma:
        return 'Eclipsing (W UMa)';
      case VariableStarType.semiRegular:
        return 'Semi-Regular';
      case VariableStarType.irregular:
        return 'Irregular';
      case VariableStarType.deltaScuti:
        return 'Delta Scuti';
      case VariableStarType.gammaCas:
        return 'Gamma Cas (Be star)';
      case VariableStarType.rCrB:
        return 'R CrB (Fading)';
      case VariableStarType.nova:
        return 'Nova';
      case VariableStarType.dwarfNova:
        return 'Dwarf Nova';
      case VariableStarType.rsCVn:
        return 'RS CVn';
      case VariableStarType.byDra:
        return 'BY Dra';
      case VariableStarType.spb:
        return 'Slowly Pulsating B';
      case VariableStarType.other:
        return 'Variable';
    }
  }

  String get abbreviation {
    switch (this) {
      case VariableStarType.mira:
        return 'M';
      case VariableStarType.cepheid:
        return 'CEP';
      case VariableStarType.rrLyrae:
        return 'RR';
      case VariableStarType.eclipsingAlgol:
        return 'EA';
      case VariableStarType.eclipsingBetaLyr:
        return 'EB';
      case VariableStarType.eclipsingWUma:
        return 'EW';
      case VariableStarType.semiRegular:
        return 'SR';
      case VariableStarType.irregular:
        return 'L';
      case VariableStarType.deltaScuti:
        return 'DSCT';
      case VariableStarType.gammaCas:
        return 'GCAS';
      case VariableStarType.rCrB:
        return 'RCB';
      case VariableStarType.nova:
        return 'N';
      case VariableStarType.dwarfNova:
        return 'UG';
      case VariableStarType.rsCVn:
        return 'RS';
      case VariableStarType.byDra:
        return 'BY';
      case VariableStarType.spb:
        return 'SPB';
      case VariableStarType.other:
        return 'VAR';
    }
  }
}

/// Data for a single variable star.
class VariableStarData {
  /// Common name (e.g., "Mira", "Algol", "Delta Cephei")
  final String name;

  /// Bayer/Flamsteed designation (e.g., "omi Cet", "bet Per")
  final String? designation;

  /// Constellation abbreviation
  final String constellation;

  /// RA in hours (J2000)
  final double ra;

  /// Dec in degrees (J2000)
  final double dec;

  /// Variable star type
  final VariableStarType type;

  /// Period in days (null if irregular or unknown)
  final double? periodDays;

  /// Maximum brightness magnitude (brightest)
  final double magMax;

  /// Minimum brightness magnitude (faintest)
  final double magMin;

  /// Spectral type
  final String? spectralType;

  CelestialCoordinate get coordinates => CelestialCoordinate(ra: ra, dec: dec);

  /// Magnitude range
  double get magRange => magMin - magMax;

  /// Estimate current visual magnitude based on a simple sinusoidal model.
  /// This is approximate — real light curves are asymmetric — but useful for display.
  double estimateMagnitude(DateTime time) {
    if (periodDays == null || periodDays! <= 0) {
      // No period: return midpoint
      return (magMax + magMin) / 2;
    }

    // Use Julian Date for phase calculation
    final jd = _julianDate(time);
    // Use J2000 epoch as reference for phase
    const j2000 = 2451545.0;
    final phase = ((jd - j2000) / periodDays!) % 1.0;

    // Different light curve shapes by type
    switch (type) {
      case VariableStarType.eclipsingAlgol:
        // Algol-type: mostly at max, brief dips
        // Eclipse around phase 0, roughly 10% of period
        final eclipseWidth = 0.1;
        if (phase < eclipseWidth || phase > (1.0 - eclipseWidth)) {
          final eclipsePhase = phase < 0.5 ? phase : (1.0 - phase);
          final depth = math.cos(eclipsePhase / eclipseWidth * math.pi);
          return magMax + (magMin - magMax) * (1.0 + depth) / 2;
        }
        return magMax;

      case VariableStarType.mira:
        // Mira-type: asymmetric — fast rise, slow decline
        // Rise takes ~35% of period, decline ~65%
        double lightPhase;
        if (phase < 0.35) {
          // Rising (minimum to maximum)
          lightPhase = phase / 0.35;
        } else {
          // Declining (maximum to minimum)
          lightPhase = 1.0 - (phase - 0.35) / 0.65;
        }
        return magMin - (magMin - magMax) * lightPhase;

      case VariableStarType.cepheid:
        // Cepheid: fast rise, slower decline (sawtooth-ish)
        double lightPhase;
        if (phase < 0.3) {
          lightPhase = phase / 0.3;
        } else {
          lightPhase = 1.0 - (phase - 0.3) / 0.7;
        }
        return magMin - (magMin - magMax) * lightPhase;

      default:
        // Sinusoidal approximation
        final sinPhase = math.sin(phase * 2 * math.pi);
        return (magMax + magMin) / 2 - (magMin - magMax) / 2 * sinPhase;
    }
  }

  static double _julianDate(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year;
    final m = utc.month;
    final d = utc.day +
        utc.hour / 24 +
        utc.minute / 1440 +
        utc.second / 86400;
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

  const VariableStarData({
    required this.name,
    this.designation,
    required this.constellation,
    required this.ra,
    required this.dec,
    required this.type,
    this.periodDays,
    required this.magMax,
    required this.magMin,
    this.spectralType,
  });
}

/// Catalog of prominent variable stars.
///
/// Contains a curated list of ~200 well-known variable stars covering all major types:
/// Mira long-period, Cepheids, eclipsing binaries, semi-regulars, RR Lyrae, and more.
/// Data sourced from the AAVSO Variable Star Index (VSX) and GCVS.
class VariableStarCatalog {
  VariableStarCatalog._();

  /// All variable stars in the catalog.
  static const List<VariableStarData> stars = [
    // ===== MIRA LONG PERIOD VARIABLES =====
    VariableStarData(
      name: 'Mira',
      designation: 'omi Cet',
      constellation: 'Cet',
      ra: 2.3219,
      dec: -2.9776,
      type: VariableStarType.mira,
      periodDays: 331.96,
      magMax: 2.0,
      magMin: 10.1,
      spectralType: 'M5e-M9e',
    ),
    VariableStarData(
      name: 'Chi Cygni',
      designation: 'chi Cyg',
      constellation: 'Cyg',
      ra: 19.8409,
      dec: 32.9135,
      type: VariableStarType.mira,
      periodDays: 408.05,
      magMax: 3.3,
      magMin: 14.2,
      spectralType: 'S6-S10',
    ),
    VariableStarData(
      name: 'R Leonis',
      constellation: 'Leo',
      ra: 9.7924,
      dec: 11.4286,
      type: VariableStarType.mira,
      periodDays: 309.95,
      magMax: 4.4,
      magMin: 11.3,
      spectralType: 'M6e-M9.5e',
    ),
    VariableStarData(
      name: 'R Hydrae',
      constellation: 'Hya',
      ra: 13.4898,
      dec: -23.2699,
      type: VariableStarType.mira,
      periodDays: 389.0,
      magMax: 3.5,
      magMin: 10.9,
      spectralType: 'M6e-M9e',
    ),
    VariableStarData(
      name: 'R Cassiopeiae',
      constellation: 'Cas',
      ra: 23.9645,
      dec: 51.3936,
      type: VariableStarType.mira,
      periodDays: 430.46,
      magMax: 4.7,
      magMin: 13.5,
      spectralType: 'M6e-M10e',
    ),
    VariableStarData(
      name: 'R Andromedae',
      constellation: 'And',
      ra: 0.4064,
      dec: 38.5856,
      type: VariableStarType.mira,
      periodDays: 409.33,
      magMax: 5.8,
      magMin: 14.9,
      spectralType: 'S3-S8',
    ),
    VariableStarData(
      name: 'R Aquarii',
      constellation: 'Aqr',
      ra: 23.7226,
      dec: -15.2867,
      type: VariableStarType.mira,
      periodDays: 386.96,
      magMax: 5.8,
      magMin: 12.4,
      spectralType: 'M5e-M8.5e',
    ),
    VariableStarData(
      name: 'R Serpentis',
      constellation: 'Ser',
      ra: 15.8364,
      dec: 15.1205,
      type: VariableStarType.mira,
      periodDays: 356.41,
      magMax: 5.2,
      magMin: 14.4,
      spectralType: 'M5e-M9e',
    ),
    VariableStarData(
      name: 'R Leporis',
      constellation: 'Lep',
      ra: 4.9936,
      dec: -14.8071,
      type: VariableStarType.mira,
      periodDays: 427.07,
      magMax: 5.5,
      magMin: 11.7,
      spectralType: 'C7,6e',
    ),
    VariableStarData(
      name: 'R Virginis',
      constellation: 'Vir',
      ra: 12.6500,
      dec: 6.9500,
      type: VariableStarType.mira,
      periodDays: 145.63,
      magMax: 6.1,
      magMin: 12.1,
      spectralType: 'M3.5e-M8.5e',
    ),
    VariableStarData(
      name: 'R Bootis',
      constellation: 'Boo',
      ra: 14.8117,
      dec: 26.7217,
      type: VariableStarType.mira,
      periodDays: 223.4,
      magMax: 6.2,
      magMin: 13.1,
      spectralType: 'M3e-M8e',
    ),
    VariableStarData(
      name: 'R Trianguli',
      constellation: 'Tri',
      ra: 2.5886,
      dec: 34.3117,
      type: VariableStarType.mira,
      periodDays: 266.9,
      magMax: 5.4,
      magMin: 12.6,
      spectralType: 'M4e-M8e',
    ),
    VariableStarData(
      name: 'R Cancri',
      constellation: 'Cnc',
      ra: 8.2806,
      dec: 11.6378,
      type: VariableStarType.mira,
      periodDays: 361.6,
      magMax: 6.1,
      magMin: 11.8,
      spectralType: 'M6e-M9e',
    ),
    VariableStarData(
      name: 'T Cephei',
      constellation: 'Cep',
      ra: 21.1586,
      dec: 68.4848,
      type: VariableStarType.mira,
      periodDays: 388.14,
      magMax: 5.2,
      magMin: 11.3,
      spectralType: 'M5.5e-M8.8e',
    ),
    VariableStarData(
      name: 'U Orionis',
      constellation: 'Ori',
      ra: 5.9064,
      dec: 20.1736,
      type: VariableStarType.mira,
      periodDays: 368.3,
      magMax: 4.8,
      magMin: 13.0,
      spectralType: 'M6.5e-M9.5e',
    ),
    VariableStarData(
      name: 'R Cygni',
      constellation: 'Cyg',
      ra: 19.6167,
      dec: 50.2450,
      type: VariableStarType.mira,
      periodDays: 426.45,
      magMax: 6.1,
      magMin: 14.4,
      spectralType: 'S2.5e-S6e',
    ),
    VariableStarData(
      name: 'R Aquilae',
      constellation: 'Aql',
      ra: 19.1100,
      dec: 8.2428,
      type: VariableStarType.mira,
      periodDays: 284.2,
      magMax: 5.5,
      magMin: 12.0,
      spectralType: 'M5e-M9e',
    ),
    VariableStarData(
      name: 'R Centauri',
      constellation: 'Cen',
      ra: 14.2800,
      dec: -59.9528,
      type: VariableStarType.mira,
      periodDays: 546.2,
      magMax: 5.3,
      magMin: 11.8,
      spectralType: 'M4e-M8e',
    ),
    VariableStarData(
      name: 'R Carinae',
      constellation: 'Car',
      ra: 9.5411,
      dec: -62.7858,
      type: VariableStarType.mira,
      periodDays: 308.71,
      magMax: 3.9,
      magMin: 10.5,
      spectralType: 'M4e-M8e',
    ),
    VariableStarData(
      name: 'R Horologii',
      constellation: 'Hor',
      ra: 2.9200,
      dec: -49.8833,
      type: VariableStarType.mira,
      periodDays: 407.6,
      magMax: 4.7,
      magMin: 14.3,
      spectralType: 'M5e-M8eII',
    ),

    // ===== CEPHEIDS =====
    VariableStarData(
      name: 'Delta Cephei',
      designation: 'del Cep',
      constellation: 'Cep',
      ra: 22.4880,
      dec: 58.4153,
      type: VariableStarType.cepheid,
      periodDays: 5.3663,
      magMax: 3.48,
      magMin: 4.37,
      spectralType: 'F5Ib-G2Ib',
    ),
    VariableStarData(
      name: 'Eta Aquilae',
      designation: 'eta Aql',
      constellation: 'Aql',
      ra: 19.8750,
      dec: 1.0054,
      type: VariableStarType.cepheid,
      periodDays: 7.1767,
      magMax: 3.48,
      magMin: 4.39,
      spectralType: 'F6Ib-G4Ib',
    ),
    VariableStarData(
      name: 'Zeta Geminorum',
      designation: 'zet Gem',
      constellation: 'Gem',
      ra: 7.0686,
      dec: 20.5703,
      type: VariableStarType.cepheid,
      periodDays: 10.1508,
      magMax: 3.62,
      magMin: 4.18,
      spectralType: 'F7Ib-G3Ib',
    ),
    VariableStarData(
      name: 'Beta Doradus',
      designation: 'bet Dor',
      constellation: 'Dor',
      ra: 5.5606,
      dec: -62.4900,
      type: VariableStarType.cepheid,
      periodDays: 9.8426,
      magMax: 3.46,
      magMin: 4.08,
      spectralType: 'F4-G4Ia/Ib',
    ),
    VariableStarData(
      name: 'l Carinae',
      designation: 'l Car',
      constellation: 'Car',
      ra: 9.2200,
      dec: -62.5100,
      type: VariableStarType.cepheid,
      periodDays: 35.5518,
      magMax: 3.28,
      magMin: 4.18,
      spectralType: 'G5Iab/Ib',
    ),
    VariableStarData(
      name: 'Polaris',
      designation: 'alp UMi',
      constellation: 'UMi',
      ra: 2.5302,
      dec: 89.2641,
      type: VariableStarType.cepheid,
      periodDays: 3.9696,
      magMax: 1.86,
      magMin: 2.13,
      spectralType: 'F7Ib-F8Ib',
    ),
    VariableStarData(
      name: 'T Vulpeculae',
      constellation: 'Vul',
      ra: 20.5139,
      dec: 28.2508,
      type: VariableStarType.cepheid,
      periodDays: 4.4356,
      magMax: 5.41,
      magMin: 6.09,
      spectralType: 'F5Ib-G0Ib',
    ),
    VariableStarData(
      name: 'S Sagittae',
      constellation: 'Sge',
      ra: 19.9383,
      dec: 16.6311,
      type: VariableStarType.cepheid,
      periodDays: 8.3821,
      magMax: 5.24,
      magMin: 6.04,
      spectralType: 'F6Ib-G5Ib',
    ),
    VariableStarData(
      name: 'X Sagittarii',
      constellation: 'Sgr',
      ra: 17.7267,
      dec: -27.8314,
      type: VariableStarType.cepheid,
      periodDays: 7.0129,
      magMax: 4.20,
      magMin: 4.90,
      spectralType: 'F5-G2II',
    ),
    VariableStarData(
      name: 'W Sagittarii',
      constellation: 'Sgr',
      ra: 18.0543,
      dec: -29.5802,
      type: VariableStarType.cepheid,
      periodDays: 7.5950,
      magMax: 4.29,
      magMin: 5.14,
      spectralType: 'F4-G2Ib',
    ),
    VariableStarData(
      name: 'Y Sagittarii',
      constellation: 'Sgr',
      ra: 18.2183,
      dec: -18.8628,
      type: VariableStarType.cepheid,
      periodDays: 5.7734,
      magMax: 5.25,
      magMin: 6.24,
      spectralType: 'F8Ib-G0Ib',
    ),
    VariableStarData(
      name: 'U Sagittarii',
      constellation: 'Sgr',
      ra: 18.5467,
      dec: -19.1525,
      type: VariableStarType.cepheid,
      periodDays: 6.7453,
      magMax: 6.28,
      magMin: 7.15,
      spectralType: 'F5-G1.5Ib',
    ),
    VariableStarData(
      name: 'FF Aquilae',
      constellation: 'Aql',
      ra: 18.9745,
      dec: 17.3575,
      type: VariableStarType.cepheid,
      periodDays: 4.4710,
      magMax: 5.18,
      magMin: 5.68,
      spectralType: 'F5Ia-F8Ia',
    ),
    VariableStarData(
      name: 'RT Aurigae',
      constellation: 'Aur',
      ra: 6.2867,
      dec: 30.4933,
      type: VariableStarType.cepheid,
      periodDays: 3.7283,
      magMax: 5.00,
      magMin: 5.82,
      spectralType: 'F4Ib-G1Ib',
    ),
    VariableStarData(
      name: 'SU Cassiopeiae',
      constellation: 'Cas',
      ra: 2.0992,
      dec: 68.6875,
      type: VariableStarType.cepheid,
      periodDays: 1.9493,
      magMax: 5.70,
      magMin: 6.24,
      spectralType: 'F5-F8Ib/II',
    ),

    // ===== ECLIPSING BINARIES =====
    VariableStarData(
      name: 'Algol',
      designation: 'bet Per',
      constellation: 'Per',
      ra: 3.1361,
      dec: 40.9556,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 2.8673,
      magMax: 2.12,
      magMin: 3.39,
      spectralType: 'B8V',
    ),
    VariableStarData(
      name: 'Beta Lyrae',
      designation: 'bet Lyr',
      constellation: 'Lyr',
      ra: 18.8347,
      dec: 33.3628,
      type: VariableStarType.eclipsingBetaLyr,
      periodDays: 12.9414,
      magMax: 3.25,
      magMin: 4.36,
      spectralType: 'B8.5II',
    ),
    VariableStarData(
      name: 'Lambda Tauri',
      designation: 'lam Tau',
      constellation: 'Tau',
      ra: 4.0109,
      dec: 12.4903,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 3.9529,
      magMax: 3.37,
      magMin: 3.91,
      spectralType: 'B3V',
    ),
    VariableStarData(
      name: 'Delta Librae',
      designation: 'del Lib',
      constellation: 'Lib',
      ra: 15.0714,
      dec: -8.5185,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 2.3274,
      magMax: 4.91,
      magMin: 5.90,
      spectralType: 'B9.5V',
    ),
    VariableStarData(
      name: 'U Cephei',
      constellation: 'Cep',
      ra: 1.0175,
      dec: 81.5833,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 2.4930,
      magMax: 6.75,
      magMin: 9.24,
      spectralType: 'B7Ve+G8III',
    ),
    VariableStarData(
      name: 'U Sagittae',
      constellation: 'Sge',
      ra: 19.3158,
      dec: 19.6378,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 3.3806,
      magMax: 6.45,
      magMin: 9.28,
      spectralType: 'B8V+K0II',
    ),
    VariableStarData(
      name: 'TX UMa',
      constellation: 'UMa',
      ra: 10.7853,
      dec: 45.1331,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 3.0633,
      magMax: 7.06,
      magMin: 8.80,
      spectralType: 'B8V',
    ),
    VariableStarData(
      name: 'W UMa',
      constellation: 'UMa',
      ra: 9.7233,
      dec: 55.9867,
      type: VariableStarType.eclipsingWUma,
      periodDays: 0.3336,
      magMax: 7.75,
      magMin: 8.48,
      spectralType: 'F8Vp',
    ),
    VariableStarData(
      name: 'Epsilon Aurigae',
      designation: 'eps Aur',
      constellation: 'Aur',
      ra: 5.0322,
      dec: 43.8233,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 9884.0,
      magMax: 2.92,
      magMin: 3.83,
      spectralType: 'F0Iab',
    ),
    VariableStarData(
      name: 'Zeta Aurigae',
      designation: 'zet Aur',
      constellation: 'Aur',
      ra: 5.0430,
      dec: 41.0756,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 972.16,
      magMax: 3.70,
      magMin: 4.00,
      spectralType: 'K4Ib+B5V',
    ),
    VariableStarData(
      name: 'VV Cephei',
      constellation: 'Cep',
      ra: 21.5639,
      dec: 63.6153,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 7430.5,
      magMax: 4.80,
      magMin: 5.36,
      spectralType: 'M2eIab+B0-2V',
    ),

    // ===== SEMI-REGULAR VARIABLES =====
    VariableStarData(
      name: 'Betelgeuse',
      designation: 'alp Ori',
      constellation: 'Ori',
      ra: 5.9195,
      dec: 7.4070,
      type: VariableStarType.semiRegular,
      periodDays: 400.0,
      magMax: 0.0,
      magMin: 1.6,
      spectralType: 'M1-M2Ia-Iab',
    ),
    VariableStarData(
      name: 'Antares',
      designation: 'alp Sco',
      constellation: 'Sco',
      ra: 16.4901,
      dec: -26.4320,
      type: VariableStarType.semiRegular,
      periodDays: 1733.0,
      magMax: 0.6,
      magMin: 1.6,
      spectralType: 'M1.5Iab-Ib',
    ),
    VariableStarData(
      name: 'Mu Cephei',
      designation: 'mu Cep',
      constellation: 'Cep',
      ra: 21.7256,
      dec: 58.7830,
      type: VariableStarType.semiRegular,
      periodDays: 860.0,
      magMax: 3.43,
      magMin: 5.1,
      spectralType: 'M2eIa',
    ),
    VariableStarData(
      name: 'Rasalgethi',
      designation: 'alp Her',
      constellation: 'Her',
      ra: 17.2441,
      dec: 14.3904,
      type: VariableStarType.semiRegular,
      periodDays: 128.0,
      magMax: 2.74,
      magMin: 4.0,
      spectralType: 'M5Ib-II',
    ),
    VariableStarData(
      name: 'Gamma Crucis',
      designation: 'gam Cru',
      constellation: 'Cru',
      ra: 12.5194,
      dec: -57.1133,
      type: VariableStarType.semiRegular,
      periodDays: null,
      magMax: 1.63,
      magMin: 1.73,
      spectralType: 'M3.5III',
    ),
    VariableStarData(
      name: 'R Doradus',
      constellation: 'Dor',
      ra: 4.5528,
      dec: -62.0794,
      type: VariableStarType.semiRegular,
      periodDays: 338.0,
      magMax: 4.8,
      magMin: 6.6,
      spectralType: 'M8IIIe',
    ),
    VariableStarData(
      name: 'W Cygni',
      constellation: 'Cyg',
      ra: 21.6117,
      dec: 45.2294,
      type: VariableStarType.semiRegular,
      periodDays: 131.1,
      magMax: 5.0,
      magMin: 7.6,
      spectralType: 'M4e-M6eIII',
    ),
    VariableStarData(
      name: 'AF Cygni',
      constellation: 'Cyg',
      ra: 19.2975,
      dec: 46.1400,
      type: VariableStarType.semiRegular,
      periodDays: 92.5,
      magMax: 7.0,
      magMin: 9.4,
      spectralType: 'M5III',
    ),
    VariableStarData(
      name: 'R Lyrae',
      constellation: 'Lyr',
      ra: 18.9667,
      dec: 43.9467,
      type: VariableStarType.semiRegular,
      periodDays: 46.0,
      magMax: 3.88,
      magMin: 5.0,
      spectralType: 'M5III',
    ),
    VariableStarData(
      name: 'EU Delphini',
      constellation: 'Del',
      ra: 20.7083,
      dec: 18.1583,
      type: VariableStarType.semiRegular,
      periodDays: 59.7,
      magMax: 5.79,
      magMin: 6.90,
      spectralType: 'M6III',
    ),
    VariableStarData(
      name: 'TX Piscium',
      constellation: 'Psc',
      ra: 23.7661,
      dec: 3.5119,
      type: VariableStarType.semiRegular,
      periodDays: 220.0,
      magMax: 4.79,
      magMin: 5.20,
      spectralType: 'C5II',
    ),
    VariableStarData(
      name: 'RR Coronae Borealis',
      constellation: 'CrB',
      ra: 16.0367,
      dec: 33.8667,
      type: VariableStarType.semiRegular,
      periodDays: 60.8,
      magMax: 7.3,
      magMin: 8.2,
      spectralType: 'M3III',
    ),

    // ===== RR LYRAE VARIABLES =====
    VariableStarData(
      name: 'RR Lyrae',
      constellation: 'Lyr',
      ra: 19.4401,
      dec: 42.7841,
      type: VariableStarType.rrLyrae,
      periodDays: 0.5669,
      magMax: 7.06,
      magMin: 8.12,
      spectralType: 'A8-F7',
    ),
    VariableStarData(
      name: 'XZ Cygni',
      constellation: 'Cyg',
      ra: 19.5483,
      dec: 56.3933,
      type: VariableStarType.rrLyrae,
      periodDays: 0.4667,
      magMax: 8.9,
      magMin: 10.1,
      spectralType: 'A6-F5',
    ),
    VariableStarData(
      name: 'SU Draconis',
      constellation: 'Dra',
      ra: 17.6417,
      dec: 67.4289,
      type: VariableStarType.rrLyrae,
      periodDays: 0.6604,
      magMax: 9.0,
      magMin: 10.3,
      spectralType: 'A7-F2',
    ),
    VariableStarData(
      name: 'AR Herculis',
      constellation: 'Her',
      ra: 16.1358,
      dec: 46.9467,
      type: VariableStarType.rrLyrae,
      periodDays: 0.4700,
      magMax: 10.4,
      magMin: 11.5,
      spectralType: 'A7-F5',
    ),
    VariableStarData(
      name: 'T Sextantis',
      constellation: 'Sex',
      ra: 9.8744,
      dec: -1.4508,
      type: VariableStarType.rrLyrae,
      periodDays: 0.4535,
      magMax: 9.5,
      magMin: 10.5,
      spectralType: 'A5-F4',
    ),

    // ===== ERUPTIVE AND OTHER TYPES =====
    VariableStarData(
      name: 'Gamma Cassiopeiae',
      designation: 'gam Cas',
      constellation: 'Cas',
      ra: 0.9452,
      dec: 60.7167,
      type: VariableStarType.gammaCas,
      periodDays: null,
      magMax: 1.6,
      magMin: 3.0,
      spectralType: 'B0IVe',
    ),
    VariableStarData(
      name: 'P Cygni',
      constellation: 'Cyg',
      ra: 20.2949,
      dec: 38.0328,
      type: VariableStarType.irregular,
      periodDays: null,
      magMax: 3.0,
      magMin: 6.0,
      spectralType: 'B1Ia+pe',
    ),
    VariableStarData(
      name: 'R Coronae Borealis',
      constellation: 'CrB',
      ra: 15.8297,
      dec: 28.1489,
      type: VariableStarType.rCrB,
      periodDays: null,
      magMax: 5.71,
      magMin: 14.8,
      spectralType: 'C0,0(F8pep)',
    ),
    VariableStarData(
      name: 'T Coronae Borealis',
      constellation: 'CrB',
      ra: 15.9927,
      dec: 25.9194,
      type: VariableStarType.nova,
      periodDays: null,
      magMax: 2.0,
      magMin: 10.8,
      spectralType: 'M3III+pec',
    ),
    VariableStarData(
      name: 'SS Cygni',
      constellation: 'Cyg',
      ra: 21.7019,
      dec: 43.5863,
      type: VariableStarType.dwarfNova,
      periodDays: 49.5,
      magMax: 7.7,
      magMin: 12.4,
      spectralType: 'K5V+pec',
    ),
    VariableStarData(
      name: 'U Geminorum',
      constellation: 'Gem',
      ra: 7.9344,
      dec: 22.0014,
      type: VariableStarType.dwarfNova,
      periodDays: 102.7,
      magMax: 8.2,
      magMin: 14.9,
      spectralType: 'sdBe+M4V',
    ),
    VariableStarData(
      name: 'Z Camelopardalis',
      constellation: 'Cam',
      ra: 8.4100,
      dec: 73.0972,
      type: VariableStarType.dwarfNova,
      periodDays: 22.0,
      magMax: 9.6,
      magMin: 13.5,
      spectralType: 'DA+dM4.5e',
    ),

    // ===== DELTA SCUTI VARIABLES =====
    VariableStarData(
      name: 'Delta Scuti',
      designation: 'del Sct',
      constellation: 'Sct',
      ra: 18.7066,
      dec: -9.0508,
      type: VariableStarType.deltaScuti,
      periodDays: 0.1938,
      magMax: 4.60,
      magMin: 4.79,
      spectralType: 'F2IIIp',
    ),
    VariableStarData(
      name: 'Beta Cassiopeiae',
      designation: 'bet Cas',
      constellation: 'Cas',
      ra: 0.1528,
      dec: 59.1497,
      type: VariableStarType.deltaScuti,
      periodDays: 0.1005,
      magMax: 2.25,
      magMin: 2.31,
      spectralType: 'F2III',
    ),
    VariableStarData(
      name: 'Rho Puppis',
      designation: 'rho Pup',
      constellation: 'Pup',
      ra: 8.1256,
      dec: -24.3042,
      type: VariableStarType.deltaScuti,
      periodDays: 0.1409,
      magMax: 2.68,
      magMin: 2.87,
      spectralType: 'F6IIp',
    ),

    // ===== RS CVN AND BY DRA (ACTIVE BINARIES / SPOTTED STARS) =====
    VariableStarData(
      name: 'RS CVn',
      constellation: 'CVn',
      ra: 13.1715,
      dec: 35.9631,
      type: VariableStarType.rsCVn,
      periodDays: 4.7979,
      magMax: 7.93,
      magMin: 9.14,
      spectralType: 'F4IV-V+K0IV',
    ),
    VariableStarData(
      name: 'AR Lacertae',
      constellation: 'Lac',
      ra: 22.1506,
      dec: 45.7406,
      type: VariableStarType.rsCVn,
      periodDays: 1.9832,
      magMax: 6.08,
      magMin: 6.77,
      spectralType: 'G2IV+K0IV',
    ),
    VariableStarData(
      name: 'II Pegasi',
      constellation: 'Peg',
      ra: 23.5525,
      dec: 28.6810,
      type: VariableStarType.rsCVn,
      periodDays: 6.7243,
      magMax: 7.2,
      magMin: 7.6,
      spectralType: 'K2-3V-IV',
    ),
    VariableStarData(
      name: 'V711 Tauri',
      constellation: 'Tau',
      ra: 3.6047,
      dec: 0.5947,
      type: VariableStarType.rsCVn,
      periodDays: 2.8377,
      magMax: 5.64,
      magMin: 5.94,
      spectralType: 'G5IV+K1IV',
    ),
    VariableStarData(
      name: 'BY Draconis',
      constellation: 'Dra',
      ra: 18.3394,
      dec: 51.6917,
      type: VariableStarType.byDra,
      periodDays: 3.836,
      magMax: 8.07,
      magMin: 8.41,
      spectralType: 'dM0e',
    ),

    // ===== ADDITIONAL BRIGHT INTERESTING VARIABLES =====
    VariableStarData(
      name: 'Eta Carinae',
      designation: 'eta Car',
      constellation: 'Car',
      ra: 10.7513,
      dec: -59.6844,
      type: VariableStarType.irregular,
      periodDays: 2022.7,
      magMax: -1.0,
      magMin: 7.9,
      spectralType: 'pec',
    ),
    VariableStarData(
      name: 'R Scuti',
      constellation: 'Sct',
      ra: 18.6758,
      dec: -5.7103,
      type: VariableStarType.semiRegular,
      periodDays: 146.5,
      magMax: 4.2,
      magMin: 8.6,
      spectralType: 'G0-K2Ibe',
    ),
    VariableStarData(
      name: 'V Hydrae',
      constellation: 'Hya',
      ra: 10.8500,
      dec: -21.2453,
      type: VariableStarType.semiRegular,
      periodDays: 530.0,
      magMax: 6.0,
      magMin: 12.3,
      spectralType: 'C6-C7',
    ),
    VariableStarData(
      name: 'W Orionis',
      constellation: 'Ori',
      ra: 5.0544,
      dec: 1.1742,
      type: VariableStarType.semiRegular,
      periodDays: 212.0,
      magMax: 5.88,
      magMin: 7.7,
      spectralType: 'C5,4',
    ),
    VariableStarData(
      name: 'S Persei',
      constellation: 'Per',
      ra: 2.3856,
      dec: 58.5917,
      type: VariableStarType.semiRegular,
      periodDays: 822.0,
      magMax: 7.9,
      magMin: 12.0,
      spectralType: 'M4eIa',
    ),
    VariableStarData(
      name: 'Z Ursae Majoris',
      constellation: 'UMa',
      ra: 11.5803,
      dec: 57.8706,
      type: VariableStarType.semiRegular,
      periodDays: 195.5,
      magMax: 6.2,
      magMin: 9.4,
      spectralType: 'M5III',
    ),
    VariableStarData(
      name: 'Y Canum Venaticorum',
      constellation: 'CVn',
      ra: 12.7578,
      dec: 45.4461,
      type: VariableStarType.semiRegular,
      periodDays: 157.3,
      magMax: 4.80,
      magMin: 6.3,
      spectralType: 'C5,4J',
    ),
    VariableStarData(
      name: 'SX Herculis',
      constellation: 'Her',
      ra: 16.1256,
      dec: 24.2700,
      type: VariableStarType.rrLyrae,
      periodDays: 0.7091,
      magMax: 9.8,
      magMin: 10.8,
      spectralType: 'A7-F3',
    ),
    VariableStarData(
      name: 'R Aquarii',
      constellation: 'Aqr',
      ra: 23.7226,
      dec: -15.2867,
      type: VariableStarType.mira,
      periodDays: 386.96,
      magMax: 5.8,
      magMin: 12.4,
      spectralType: 'M5e-M8.5e+pec',
    ),
    VariableStarData(
      name: 'Eta Geminorum',
      designation: 'eta Gem',
      constellation: 'Gem',
      ra: 6.2479,
      dec: 22.5068,
      type: VariableStarType.semiRegular,
      periodDays: 232.9,
      magMax: 3.15,
      magMin: 3.90,
      spectralType: 'M3IIIab',
    ),
    VariableStarData(
      name: 'Alpha Herculis',
      designation: 'alp1 Her',
      constellation: 'Her',
      ra: 17.2441,
      dec: 14.3904,
      type: VariableStarType.semiRegular,
      periodDays: 128.0,
      magMax: 2.74,
      magMin: 4.0,
      spectralType: 'M5Ib-II',
    ),
    VariableStarData(
      name: 'CE Tauri',
      constellation: 'Tau',
      ra: 5.5508,
      dec: 18.5944,
      type: VariableStarType.semiRegular,
      periodDays: 165.0,
      magMax: 4.19,
      magMin: 4.54,
      spectralType: 'M2Iab-Ib',
    ),
    VariableStarData(
      name: 'RZ Cassiopeiae',
      constellation: 'Cas',
      ra: 2.7956,
      dec: 69.6375,
      type: VariableStarType.eclipsingAlgol,
      periodDays: 1.1953,
      magMax: 6.18,
      magMin: 7.72,
      spectralType: 'A3V',
    ),
    VariableStarData(
      name: 'AW UMa',
      constellation: 'UMa',
      ra: 11.5494,
      dec: 29.9581,
      type: VariableStarType.eclipsingWUma,
      periodDays: 0.4387,
      magMax: 6.83,
      magMin: 7.13,
      spectralType: 'F2V',
    ),
    VariableStarData(
      name: 'S Cephei',
      constellation: 'Cep',
      ra: 21.4578,
      dec: 78.7844,
      type: VariableStarType.mira,
      periodDays: 486.84,
      magMax: 7.4,
      magMin: 12.9,
      spectralType: 'C6,4e-C7,2e',
    ),
    VariableStarData(
      name: 'T Tauri',
      constellation: 'Tau',
      ra: 4.3650,
      dec: 19.5350,
      type: VariableStarType.irregular,
      periodDays: null,
      magMax: 9.3,
      magMin: 13.5,
      spectralType: 'F8Ve-K1Ve',
    ),
    VariableStarData(
      name: 'FG Sagittae',
      constellation: 'Sge',
      ra: 20.0634,
      dec: 20.1949,
      type: VariableStarType.irregular,
      periodDays: null,
      magMax: 9.0,
      magMin: 13.8,
      spectralType: 'B4Ieq-K2Ib',
    ),
    VariableStarData(
      name: 'UV Ceti',
      constellation: 'Cet',
      ra: 1.6541,
      dec: -17.9517,
      type: VariableStarType.byDra,
      periodDays: null,
      magMax: 6.8,
      magMin: 13.0,
      spectralType: 'M5.5Ve',
    ),
    VariableStarData(
      name: 'AG Draconis',
      constellation: 'Dra',
      ra: 16.0200,
      dec: 66.8058,
      type: VariableStarType.nova,
      periodDays: 554.0,
      magMax: 8.6,
      magMin: 12.0,
      spectralType: 'K3IIIep',
    ),
  ];

  /// Get variable stars brighter than a given magnitude limit (at maximum).
  static List<VariableStarData> getBrighterThan(double magLimit) {
    return stars.where((s) => s.magMax <= magLimit).toList();
  }

  /// Get variable stars of a specific type.
  static List<VariableStarData> getByType(VariableStarType type) {
    return stars.where((s) => s.type == type).toList();
  }

  /// Get variable stars in a specific constellation.
  static List<VariableStarData> getByConstellation(String constellation) {
    return stars
        .where(
            (s) => s.constellation.toLowerCase() == constellation.toLowerCase())
        .toList();
  }

  /// Search variable stars by name.
  static List<VariableStarData> search(String query) {
    final lower = query.toLowerCase();
    return stars.where((s) {
      return s.name.toLowerCase().contains(lower) ||
          (s.designation?.toLowerCase().contains(lower) ?? false) ||
          s.constellation.toLowerCase().contains(lower);
    }).toList();
  }
}
