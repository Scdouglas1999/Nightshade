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
