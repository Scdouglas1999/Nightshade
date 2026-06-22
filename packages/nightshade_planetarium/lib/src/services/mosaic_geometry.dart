import 'dart:math' as math;

/// A single mosaic panel center, expressed in equatorial coordinates.
///
/// This is the unit of the *one* canonical panel-layout calculation
/// ([mosaicPanelCenters]) shared by the planetarium preview
/// (`MosaicPlanner`) and the imaging-side `MosaicService`. It carries only
/// the geometry both sides agree on — the RA/Dec center plus its grid index
/// — so that neither package has to duplicate the spherical-grid math.
class MosaicPanelCenter {
  /// Right ascension of the panel center, in hours, normalized to [0, 24).
  final double raHours;

  /// Declination of the panel center, in degrees.
  final double decDegrees;

  /// 0-based row-major panel index.
  final int index;

  /// 0-based row index.
  final int row;

  /// 0-based column index.
  final int col;

  const MosaicPanelCenter({
    required this.raHours,
    required this.decDegrees,
    required this.index,
    required this.row,
    required this.col,
  });
}

/// Normalize an RA value in hours into the half-open range [0, 24).
double normalizeRaHours(double raHours) {
  final normalized = raHours % 24.0;
  return normalized < 0 ? normalized + 24.0 : normalized;
}

/// Convert an east-pointing angular offset (degrees on the sky) into an RA
/// offset in hours at the given declination, applying the cos(dec)
/// compression so a fixed sky-plane step spans more RA near the poles.
///
/// Returns 0 at the singular poles (|cos(dec)| < 1e-6) where RA is undefined.
double raOffsetHoursFromDegrees(double eastOffsetDegrees, double decDegrees) {
  final cosDec = math.cos(decDegrees * math.pi / 180.0);
  if (cosDec.abs() < 1e-6) {
    return 0.0;
  }
  return eastOffsetDegrees / 15.0 / cosDec;
}

/// Compute the panel centers of a rectangular mosaic grid — the single
/// source of truth for panel layout across the app.
///
/// All angular inputs are in **degrees on the sky**:
///
/// * [centerRaHours] / [centerDecDegrees] — the grid center.
/// * [stepRaDegrees] / [stepDecDegrees] — the *effective* center-to-center
///   spacing between adjacent panels (already reduced by overlap).
/// * [columns] / [rows] — grid dimensions (column = RA axis, row = Dec axis).
/// * [rotationDegrees] — camera/grid rotation in the tangent plane.
///
/// The grid is centered on ([centerRaHours], [centerDecDegrees]): column `c`
/// sits at offset `(c - (columns-1)/2) * stepRaDegrees` east and row `r` at
/// `(r - (rows-1)/2) * stepDecDegrees` north, optionally rotated, then mapped
/// to RA/Dec with the cos(dec) compression via [raOffsetHoursFromDegrees].
/// Panels are returned in row-major order (row outer, column inner).
List<MosaicPanelCenter> mosaicPanelCenters({
  required double centerRaHours,
  required double centerDecDegrees,
  required double stepRaDegrees,
  required double stepDecDegrees,
  required int columns,
  required int rows,
  double rotationDegrees = 0.0,
}) {
  final centers = <MosaicPanelCenter>[];

  final halfHorizontal = (columns - 1) / 2.0;
  final halfVertical = (rows - 1) / 2.0;

  final hasRotation = rotationDegrees != 0.0;
  final rotRad = rotationDegrees * math.pi / 180.0;
  final cosRot = hasRotation ? math.cos(rotRad) : 1.0;
  final sinRot = hasRotation ? math.sin(rotRad) : 0.0;

  var index = 0;
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < columns; col++) {
      final colOffset = (col - halfHorizontal) * stepRaDegrees;
      final rowOffset = (row - halfVertical) * stepDecDegrees;

      final double dRaDeg;
      final double dDecDeg;
      if (hasRotation) {
        dRaDeg = colOffset * cosRot - rowOffset * sinRot;
        dDecDeg = colOffset * sinRot + rowOffset * cosRot;
      } else {
        dRaDeg = colOffset;
        dDecDeg = rowOffset;
      }

      final raHours = normalizeRaHours(
        centerRaHours + raOffsetHoursFromDegrees(dRaDeg, centerDecDegrees),
      );
      final decDegrees = centerDecDegrees + dDecDeg;

      centers.add(
        MosaicPanelCenter(
          raHours: raHours,
          decDegrees: decDegrees,
          index: index++,
          row: row,
          col: col,
        ),
      );
    }
  }

  return centers;
}
