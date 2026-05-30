import 'dart:convert';

import '../../database/database.dart' as db;
import '../../models/imaging/imaging_models.dart' show ImageStats;

/// Thresholds for automatic or bulk frame rejection.
///
/// A `null` field means "do not grade on this dimension". This is shared by
/// the interactive Image Grader dialog and the capture-time auto-grader so
/// both paths enforce identical rules.
class FrameGradeRules {
  final double? maxHfr;
  final double? maxFwhm;
  final double? maxEccentricity;
  final int? minStars;
  final double? maxGuidingRmsTotalArcsec;

  const FrameGradeRules({
    this.maxHfr,
    this.maxFwhm,
    this.maxEccentricity,
    this.minStars,
    this.maxGuidingRmsTotalArcsec,
  });

  /// Conservative defaults used when auto-grading is enabled but the user has
  /// not opened the grader to customise thresholds yet.
  static const conservativeDefaults = FrameGradeRules(
    maxHfr: 3.2,
    minStars: 25,
    maxGuidingRmsTotalArcsec: 1.2,
  );

  bool get isEmpty =>
      maxHfr == null &&
      maxFwhm == null &&
      maxEccentricity == null &&
      minStars == null &&
      maxGuidingRmsTotalArcsec == null;

  /// Whether any rule is active. Convenience inverse of [isEmpty] so callers
  /// (e.g. the live per-sub badge) can cheaply skip grading work entirely when
  /// no thresholds are configured.
  bool get hasActiveRules => !isEmpty;

  FrameGradeRules copyWith({
    double? maxHfr,
    bool clearHfr = false,
    double? maxFwhm,
    bool clearFwhm = false,
    double? maxEccentricity,
    bool clearEccentricity = false,
    int? minStars,
    bool clearStars = false,
    double? maxGuidingRmsTotalArcsec,
    bool clearGuiding = false,
  }) {
    return FrameGradeRules(
      maxHfr: clearHfr ? null : (maxHfr ?? this.maxHfr),
      maxFwhm: clearFwhm ? null : (maxFwhm ?? this.maxFwhm),
      maxEccentricity:
          clearEccentricity ? null : (maxEccentricity ?? this.maxEccentricity),
      minStars: clearStars ? null : (minStars ?? this.minStars),
      maxGuidingRmsTotalArcsec: clearGuiding
          ? null
          : (maxGuidingRmsTotalArcsec ?? this.maxGuidingRmsTotalArcsec),
    );
  }

  /// Returns a rejection reason when the frame fails any active rule.
  String? gradeFrame(db.CapturedImage img) {
    final reasons = <String>[];
    if (maxHfr != null && img.hfr != null && img.hfr! > maxHfr!) {
      reasons.add(
          'HFR ${img.hfr!.toStringAsFixed(2)} > ${maxHfr!.toStringAsFixed(2)}');
    }
    if (maxFwhm != null) {
      final fwhm = _fwhmOf(img);
      if (fwhm != null && fwhm > maxFwhm!) {
        reasons.add(
            'FWHM ${fwhm.toStringAsFixed(2)} > ${maxFwhm!.toStringAsFixed(2)}');
      }
    }
    if (maxEccentricity != null) {
      final ecc = _eccOf(img);
      if (ecc != null && ecc > maxEccentricity!) {
        reasons.add(
            'Eccentricity ${ecc.toStringAsFixed(2)} > ${maxEccentricity!.toStringAsFixed(2)}');
      }
    }
    if (minStars != null &&
        img.starCount != null &&
        img.starCount! < minStars!) {
      reasons.add('Stars ${img.starCount} < $minStars');
    }
    if (maxGuidingRmsTotalArcsec != null &&
        img.guidingRmsTotal != null &&
        img.guidingRmsTotal! > maxGuidingRmsTotalArcsec!) {
      reasons.add(
          'Guiding ${img.guidingRmsTotal!.toStringAsFixed(2)}" > ${maxGuidingRmsTotalArcsec!.toStringAsFixed(2)}"');
    }
    return reasons.isEmpty ? null : 'Auto-grade: ${reasons.join('; ')}';
  }

  /// Grades an in-memory [ImageStats] snapshot using the identical thresholds
  /// and reason-string format as [gradeFrame], so the live per-sub badge and
  /// the persisted auto-grader never disagree (there is exactly one rule
  /// engine).
  ///
  /// Unlike a database row, [ImageStats] carries neither eccentricity nor
  /// guiding RMS, so those two metrics are supplied by the caller:
  /// [eccentricity] from the science row when one exists, [guidingRmsTotal]
  /// from the live guiding telemetry. As in [gradeFrame], a `null` metric
  /// means "cannot grade this dimension" and that rule is skipped — passing
  /// `null` for either argument simply omits the corresponding check.
  String? gradeStats(
    ImageStats stats, {
    double? guidingRmsTotal,
    double? eccentricity,
  }) {
    final reasons = <String>[];
    if (maxHfr != null && stats.hfr != null && stats.hfr! > maxHfr!) {
      reasons.add(
          'HFR ${stats.hfr!.toStringAsFixed(2)} > ${maxHfr!.toStringAsFixed(2)}');
    }
    if (maxFwhm != null && stats.fwhm != null && stats.fwhm! > maxFwhm!) {
      reasons.add(
          'FWHM ${stats.fwhm!.toStringAsFixed(2)} > ${maxFwhm!.toStringAsFixed(2)}');
    }
    if (maxEccentricity != null &&
        eccentricity != null &&
        eccentricity > maxEccentricity!) {
      reasons.add(
          'Eccentricity ${eccentricity.toStringAsFixed(2)} > ${maxEccentricity!.toStringAsFixed(2)}');
    }
    if (minStars != null &&
        stats.starCount != null &&
        stats.starCount! < minStars!) {
      reasons.add('Stars ${stats.starCount} < $minStars');
    }
    if (maxGuidingRmsTotalArcsec != null &&
        guidingRmsTotal != null &&
        guidingRmsTotal > maxGuidingRmsTotalArcsec!) {
      reasons.add(
          'Guiding ${guidingRmsTotal.toStringAsFixed(2)}" > ${maxGuidingRmsTotalArcsec!.toStringAsFixed(2)}"');
    }
    return reasons.isEmpty ? null : 'Auto-grade: ${reasons.join('; ')}';
  }

  Map<String, dynamic> toJson() => {
        if (maxHfr != null) 'maxHfr': maxHfr,
        if (maxFwhm != null) 'maxFwhm': maxFwhm,
        if (maxEccentricity != null) 'maxEccentricity': maxEccentricity,
        if (minStars != null) 'minStars': minStars,
        if (maxGuidingRmsTotalArcsec != null)
          'maxGuidingRmsTotalArcsec': maxGuidingRmsTotalArcsec,
      };

  static FrameGradeRules? fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return FrameGradeRules(
        maxHfr: (map['maxHfr'] as num?)?.toDouble(),
        maxFwhm: (map['maxFwhm'] as num?)?.toDouble(),
        maxEccentricity: (map['maxEccentricity'] as num?)?.toDouble(),
        minStars: (map['minStars'] as num?)?.toInt(),
        maxGuidingRmsTotalArcsec:
            (map['maxGuidingRmsTotalArcsec'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  String toJsonString() => jsonEncode(toJson());

  /// Suggest thresholds from session statistics (75th percentile for max
  /// metrics, 25th for min stars).
  static FrameGradeRules suggestFrom(List<db.CapturedImage> frames) {
    final hfrs = frames
        .map((f) => f.hfr)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList()
      ..sort();
    final stars = frames.map((f) => f.starCount).whereType<int>().toList()
      ..sort();
    final gd = frames
        .map((f) => f.guidingRmsTotal)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList()
      ..sort();

    double? p75d(List<double> xs) => xs.isEmpty
        ? null
        : xs[(xs.length * 0.75).floor().clamp(0, xs.length - 1)];
    int? p25i(List<int> xs) => xs.isEmpty
        ? null
        : xs[(xs.length * 0.25).floor().clamp(0, xs.length - 1)];

    return FrameGradeRules(
      maxHfr: p75d(hfrs),
      minStars: p25i(stars),
      maxGuidingRmsTotalArcsec: p75d(gd),
    );
  }
}

double? _fwhmOf(db.CapturedImage img) {
  try {
    final v = (img as dynamic).fwhm;
    if (v is double && v.isFinite) return v;
  } on NoSuchMethodError {
    // Why: legacy schema rows lack the `fwhm` column; dynamic dispatch raises
    // NoSuchMethodError. Treat as "no FWHM available" and let the caller use
    // a fallback grader. Any other exception is genuinely unexpected and
    // bubbles up rather than being silently swallowed.
    return null;
  }
  return null;
}

double? _eccOf(db.CapturedImage img) {
  try {
    final v = (img as dynamic).eccentricity;
    if (v is double && v.isFinite) return v;
  } on NoSuchMethodError {
    // Why: see _fwhmOf — legacy rows lack the `eccentricity` column.
    return null;
  }
  return null;
}
