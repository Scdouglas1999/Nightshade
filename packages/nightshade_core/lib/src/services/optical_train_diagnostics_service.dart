import '../database/database.dart'
    show AstrometryResidualVectorRow, PsfFieldTileRow;

enum OpticalIssueSeverity { info, warning, critical }

class OpticalDiagnosticIssue {
  final String title;
  final String detail;
  final OpticalIssueSeverity severity;

  const OpticalDiagnosticIssue({
    required this.title,
    required this.detail,
    required this.severity,
  });
}

class OpticalTrainDiagnostics {
  final double tiltScore;
  final double collimationScore;
  final String dominantTiltDirection;
  final List<OpticalDiagnosticIssue> issues;

  const OpticalTrainDiagnostics({
    required this.tiltScore,
    required this.collimationScore,
    required this.dominantTiltDirection,
    required this.issues,
  });

  bool get hasIssues => issues.isNotEmpty;

  /// Single source of truth for the A/B/C/D/F grade derived from this run.
  OpticalHealthScore get healthScore => OpticalHealthScore.fromDiagnostics(this);
}

/// Letter grade buckets shared by the diagnostics screen and any analytics
/// surface that needs to summarise optical-train quality. Defined here so two
/// views never disagree about whether an 80/100 score is a "B" or a "C".
enum OpticalHealthGrade { a, b, c, d, f }

extension OpticalHealthGradeLabel on OpticalHealthGrade {
  String get letter {
    switch (this) {
      case OpticalHealthGrade.a:
        return 'A';
      case OpticalHealthGrade.b:
        return 'B';
      case OpticalHealthGrade.c:
        return 'C';
      case OpticalHealthGrade.d:
        return 'D';
      case OpticalHealthGrade.f:
        return 'F';
    }
  }

  String get qualityLabel {
    switch (this) {
      case OpticalHealthGrade.a:
        return 'Excellent';
      case OpticalHealthGrade.b:
        return 'Good';
      case OpticalHealthGrade.c:
        return 'Fair';
      case OpticalHealthGrade.d:
        return 'Poor';
      case OpticalHealthGrade.f:
        return 'Critical';
    }
  }
}

/// Shared optical-train health summary. Centralises the score → grade mapping
/// AND the per-axis severity thresholds so the diagnostics letter grade and
/// the per-card severity chips never drift apart. `tiltScore` and
/// `collimationScore` are penalties (lower is better, 0..100).
class OpticalHealthScore {
  final double tiltScore;
  final double collimationScore;
  final double overallScore;
  final OpticalHealthGrade grade;
  final OpticalIssueSeverity tiltSeverity;
  final OpticalIssueSeverity collimationSeverity;

  // Penalty thresholds per axis. Kept here (not inlined in widgets) so the
  // diagnostics cards, KPI strips, and any future analytics view all bucket
  // identical raw numbers into identical ratings.
  static const double tiltWarnThreshold = 18.0;
  static const double tiltCriticalThreshold = 30.0;
  static const double collimationWarnThreshold = 15.0;
  static const double collimationCriticalThreshold = 25.0;

  // Letter-grade bands on the inverted overall score (higher is better).
  static const double aThreshold = 90.0;
  static const double bThreshold = 75.0;
  static const double cThreshold = 55.0;
  static const double dThreshold = 35.0;

  const OpticalHealthScore._({
    required this.tiltScore,
    required this.collimationScore,
    required this.overallScore,
    required this.grade,
    required this.tiltSeverity,
    required this.collimationSeverity,
  });

  factory OpticalHealthScore.fromDiagnostics(OpticalTrainDiagnostics d) {
    return OpticalHealthScore.fromScores(
      tiltScore: d.tiltScore,
      collimationScore: d.collimationScore,
    );
  }

  factory OpticalHealthScore.fromScores({
    required double tiltScore,
    required double collimationScore,
  }) {
    final tiltPenalty = tiltScore.clamp(0.0, 100.0);
    final collPenalty = collimationScore.clamp(0.0, 100.0);
    // Equal-weight blend: tilt and spacing both contribute to field shape.
    final overall =
        (100.0 - (tiltPenalty * 0.5 + collPenalty * 0.5)).clamp(0.0, 100.0);
    return OpticalHealthScore._(
      tiltScore: tiltPenalty,
      collimationScore: collPenalty,
      overallScore: overall,
      grade: _gradeForOverall(overall),
      tiltSeverity: _severityFor(
        tiltPenalty,
        warnAt: tiltWarnThreshold,
        criticalAt: tiltCriticalThreshold,
      ),
      collimationSeverity: _severityFor(
        collPenalty,
        warnAt: collimationWarnThreshold,
        criticalAt: collimationCriticalThreshold,
      ),
    );
  }

  String get letterGrade => grade.letter;
  String get qualityLabel => grade.qualityLabel;

  static OpticalHealthGrade _gradeForOverall(double score) {
    if (score >= aThreshold) return OpticalHealthGrade.a;
    if (score >= bThreshold) return OpticalHealthGrade.b;
    if (score >= cThreshold) return OpticalHealthGrade.c;
    if (score >= dThreshold) return OpticalHealthGrade.d;
    return OpticalHealthGrade.f;
  }

  static OpticalIssueSeverity _severityFor(
    double penalty, {
    required double warnAt,
    required double criticalAt,
  }) {
    if (penalty >= criticalAt) return OpticalIssueSeverity.critical;
    if (penalty >= warnAt) return OpticalIssueSeverity.warning;
    return OpticalIssueSeverity.info;
  }
}

/// Converts science PSF and residual maps into imaging-train guidance.
class OpticalTrainDiagnosticsService {
  const OpticalTrainDiagnosticsService();

  OpticalTrainDiagnostics analyze({
    required List<PsfFieldTileRow> psfTiles,
    required List<AstrometryResidualVectorRow> residualVectors,
  }) {
    if (psfTiles.isEmpty) {
      return const OpticalTrainDiagnostics(
        tiltScore: 0,
        collimationScore: 0,
        dominantTiltDirection: 'unknown',
        issues: [
          OpticalDiagnosticIssue(
            title: 'No diagnostics data',
            detail: 'Capture more solved frames to estimate field tilt and collimation.',
            severity: OpticalIssueSeverity.info,
          ),
        ],
      );
    }

    final left = _mean(psfTiles
        .where((tile) => tile.tileCol < _midCol(psfTiles))
        .map((tile) => tile.medianHfr));
    final right = _mean(psfTiles
        .where((tile) => tile.tileCol >= _midCol(psfTiles))
        .map((tile) => tile.medianHfr));
    final top = _mean(psfTiles
        .where((tile) => tile.tileRow < _midRow(psfTiles))
        .map((tile) => tile.medianHfr));
    final bottom = _mean(psfTiles
        .where((tile) => tile.tileRow >= _midRow(psfTiles))
        .map((tile) => tile.medianHfr));
    final global = _mean(psfTiles.map((tile) => tile.medianHfr)).clamp(0.1, 100.0);

    final horizontalTilt = (left - right).abs() / global;
    final verticalTilt = (top - bottom).abs() / global;
    final tiltScore = ((horizontalTilt > verticalTilt ? horizontalTilt : verticalTilt) * 100)
        .clamp(0.0, 100.0);

    final edgeResidual = _mean(
      residualVectors.where((row) => row.x < 0.25 || row.x > 0.75 || row.y < 0.25 || row.y > 0.75).map(
            (row) => row.magnitudeArcsec,
          ),
    );
    final centerResidual = _mean(
      residualVectors.where((row) => row.x >= 0.25 && row.x <= 0.75 && row.y >= 0.25 && row.y <= 0.75).map(
            (row) => row.magnitudeArcsec,
          ),
    ).clamp(0.1, 1000.0);
    final collimationScore = ((edgeResidual / centerResidual - 1.0).clamp(0.0, 2.0) * 50.0)
        .clamp(0.0, 100.0);

    final dominantTiltDirection = _dominantTiltDirection(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
    );

    final issues = <OpticalDiagnosticIssue>[
      if (tiltScore >= 18)
        OpticalDiagnosticIssue(
          title: 'Field tilt detected',
          detail:
              'PSF size is uneven across the frame. Strongest degradation is toward $dominantTiltDirection.',
          severity: tiltScore >= 30
              ? OpticalIssueSeverity.critical
              : OpticalIssueSeverity.warning,
        ),
      if (collimationScore >= 15)
        OpticalDiagnosticIssue(
          title: 'Collimation or spacing mismatch',
          detail:
              'Astrometric residuals grow toward the field edge. Inspect backfocus spacing and primary/secondary alignment.',
          severity: collimationScore >= 25
              ? OpticalIssueSeverity.critical
              : OpticalIssueSeverity.warning,
        ),
      if (tiltScore < 18 && collimationScore < 15)
        const OpticalDiagnosticIssue(
          title: 'Optical train looks stable',
          detail: 'Field HFR and residual patterns are balanced across the image.',
          severity: OpticalIssueSeverity.info,
        ),
    ];

    return OpticalTrainDiagnostics(
      tiltScore: tiltScore,
      collimationScore: collimationScore,
      dominantTiltDirection: dominantTiltDirection,
      issues: issues,
    );
  }

  int _midCol(List<PsfFieldTileRow> tiles) =>
      ((tiles.map((tile) => tile.tileCol).fold<int>(0, (a, b) => a > b ? a : b) + 1) / 2).floor();

  int _midRow(List<PsfFieldTileRow> tiles) =>
      ((tiles.map((tile) => tile.tileRow).fold<int>(0, (a, b) => a > b ? a : b) + 1) / 2).floor();

  String _dominantTiltDirection({
    required double left,
    required double right,
    required double top,
    required double bottom,
  }) {
    final candidates = <String, double>{
      'left edge': left,
      'right edge': right,
      'top edge': top,
      'bottom edge': bottom,
    };
    final best = candidates.entries.reduce(
      (current, next) => current.value >= next.value ? current : next,
    );
    return best.key;
  }

  double _mean(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList(growable: false);
    if (list.isEmpty) {
      return 0.0;
    }
    return list.reduce((a, b) => a + b) / list.length;
  }
}
