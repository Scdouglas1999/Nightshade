import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/daos/science_dao.dart';
import '../../database/database.dart' as db;
import '../../models/science/science_models.dart';
import '../../providers/database_provider.dart';
import '../../services/logging_service.dart';

/// Service for computing and applying photometric transformation coefficients.
///
/// The standard photometric equation is:
///   M_std = m_inst - k*X + T*(B-V) + zp
///
/// where:
///   M_std  = standard (catalog) magnitude
///   m_inst = instrumental magnitude = -2.5 * log10(flux)
///   k      = atmospheric extinction coefficient (magnitudes per airmass)
///   X      = airmass
///   T      = color transform coefficient
///   (B-V)  = color index
///   zp     = photometric zero point
class PhotometricTransformService {
  final Ref _ref;

  PhotometricTransformService(this._ref);

  ScienceDao get _scienceDao => _ref.read(scienceDaoProvider);
  LoggingService get _logger => _ref.read(loggingServiceProvider);

  /// Compute transformation coefficients from a set of catalog star matches
  /// using ordinary least-squares regression.
  ///
  /// The model is:  catalogMag = m_inst - k*X + T*(B-V) + zp
  /// Rearranged:    catalogMag - m_inst = -k*X + T*(B-V) + zp
  ///
  /// So we fit:  y = a0 + a1*X + a2*(B-V)
  /// where y = catalogMag - m_inst, a0 = zp, a1 = -k, a2 = T
  ///
  /// Requires at least 4 star matches (3 unknowns + 1 DOF).
  PhotometricTransformCoefficients? computeTransformCoefficients({
    required List<CatalogStarMatch> starMatches,
    required String filterName,
    int? equipmentProfileId,
    String catalogSource = 'auto',
  }) {
    if (starMatches.length < 4) {
      _logger.warning(
        'Need at least 4 star matches for transform fit, got ${starMatches.length}',
        source: 'PhotometricTransformService',
      );
      return null;
    }

    // Filter out saturated or very faint stars
    final validStars = starMatches.where((star) {
      return star.instrumentalFlux > 0 &&
          star.snr >= 5.0 &&
          star.catalogMagV.isFinite &&
          star.catalogMagB.isFinite &&
          star.airmass > 0 &&
          star.airmass < 10.0;
    }).toList(growable: false);

    if (validStars.length < 4) {
      _logger.warning(
        'After filtering, only ${validStars.length} valid stars remain (need 4)',
        source: 'PhotometricTransformService',
      );
      return null;
    }

    // Build the system: y = zp + (-k)*X + T*(B-V)
    final n = validStars.length;
    final y = List<double>.filled(n, 0.0);
    final x1 = List<double>.filled(n, 0.0); // airmass
    final x2 = List<double>.filled(n, 0.0); // color index

    for (var i = 0; i < n; i++) {
      final star = validStars[i];
      final instMag =
          -2.5 * math.log(star.instrumentalFlux.clamp(1e-30, double.infinity)) / math.ln10;
      y[i] = star.catalogMagV - instMag;
      x1[i] = star.airmass;
      x2[i] = star.colorIndex;
    }

    // Solve 3x3 normal equations: A^T A x = A^T y
    // A = [1, X, (B-V)] for each star
    var s00 = 0.0, s01 = 0.0, s02 = 0.0;
    var s11 = 0.0, s12 = 0.0, s22 = 0.0;
    var sy0 = 0.0, sy1 = 0.0, sy2 = 0.0;

    for (var i = 0; i < n; i++) {
      s00 += 1.0;
      s01 += x1[i];
      s02 += x2[i];
      s11 += x1[i] * x1[i];
      s12 += x1[i] * x2[i];
      s22 += x2[i] * x2[i];
      sy0 += y[i];
      sy1 += x1[i] * y[i];
      sy2 += x2[i] * y[i];
    }

    // Solve A^T A * coeffs = A^T y using Cramer's rule for 3x3
    // Matrix:
    // | s00 s01 s02 | | a0 |   | sy0 |
    // | s01 s11 s12 | | a1 | = | sy1 |
    // | s02 s12 s22 | | a2 |   | sy2 |

    final det = s00 * (s11 * s22 - s12 * s12) -
        s01 * (s01 * s22 - s12 * s02) +
        s02 * (s01 * s12 - s11 * s02);

    if (det.abs() < 1e-20) {
      _logger.error(
        'Singular matrix in transform fit (det=$det). Stars may have no airmass '
        'or color index spread.',
        source: 'PhotometricTransformService',
      );
      return null;
    }

    final invDet = 1.0 / det;

    // Cofactors for each column
    final a0 = invDet *
        (sy0 * (s11 * s22 - s12 * s12) -
            s01 * (sy1 * s22 - s12 * sy2) +
            s02 * (sy1 * s12 - s11 * sy2));
    final a1 = invDet *
        (s00 * (sy1 * s22 - s12 * sy2) -
            sy0 * (s01 * s22 - s12 * s02) +
            s02 * (s01 * sy2 - sy1 * s02));
    final a2 = invDet *
        (s00 * (s11 * sy2 - sy1 * s12) -
            s01 * (s01 * sy2 - sy1 * s02) +
            sy0 * (s01 * s12 - s11 * s02));

    final zeroPoint = a0;
    final negativeExtinction = a1; // a1 = -k
    final extinctionCoefficient = -negativeExtinction;
    final colorTerm = a2;

    // Compute residuals
    var sumSqResidual = 0.0;
    final fitData = <TransformStarMatch>[];
    for (var i = 0; i < n; i++) {
      final predicted = a0 + a1 * x1[i] + a2 * x2[i];
      final residual = y[i] - predicted;
      sumSqResidual += residual * residual;
      fitData.add(TransformStarMatch(
        catalogMag: validStars[i].catalogMagV,
        instrumentalMag: validStars[i].catalogMagV - y[i], // m_inst
        colorIndex: x2[i],
        airmass: x1[i],
        residual: residual,
      ));
    }
    final rmsResidual = math.sqrt(sumSqResidual / n);

    if (!zeroPoint.isFinite || !extinctionCoefficient.isFinite || !colorTerm.isFinite) {
      _logger.error(
        'Transform fit produced non-finite coefficients: '
        'zp=$zeroPoint, k=$extinctionCoefficient, T=$colorTerm',
        source: 'PhotometricTransformService',
      );
      return null;
    }

    // Sanity checks — extinction should be positive and reasonable
    if (extinctionCoefficient < -0.5 || extinctionCoefficient > 2.0) {
      _logger.warning(
        'Extinction coefficient k=$extinctionCoefficient is outside '
        'typical range [0, 1.5]. Fit may be unreliable.',
        source: 'PhotometricTransformService',
      );
    }

    _logger.info(
      'Photometric transform computed for filter=$filterName: '
      'zp=${zeroPoint.toStringAsFixed(3)}, '
      'k=${extinctionCoefficient.toStringAsFixed(4)}, '
      'T=${colorTerm.toStringAsFixed(4)}, '
      'RMS=${rmsResidual.toStringAsFixed(4)}, '
      'N=$n stars',
      source: 'PhotometricTransformService',
    );

    return PhotometricTransformCoefficients(
      equipmentProfileId: equipmentProfileId,
      filterName: filterName,
      colorTerm: colorTerm,
      extinctionCoefficient: extinctionCoefficient,
      zeroPoint: zeroPoint,
      rmsResidual: rmsResidual,
      matchedStarCount: n,
      catalogSource: catalogSource,
      fitData: fitData,
      dateComputed: DateTime.now(),
    );
  }

  /// Apply a photometric transform to convert instrumental magnitude to
  /// standard magnitude.
  ///
  /// M_std = m_inst - k*X + T*(B-V) + zp
  double applyTransform({
    required double instrumentalMag,
    required double airmass,
    required double colorIndex,
    required PhotometricTransformCoefficients coefficients,
  }) {
    return instrumentalMag -
        coefficients.extinctionCoefficient * airmass +
        coefficients.colorTerm * colorIndex +
        coefficients.zeroPoint;
  }

  /// Save computed coefficients to the database.
  Future<int> saveTransform(PhotometricTransformCoefficients coefficients) async {
    final fitDataJson = jsonEncode(
      coefficients.fitData.map((match) => match.toJson()).toList(),
    );
    return _scienceDao.insertPhotometricTransform(
      db.PhotometricTransformsCompanion.insert(
        equipmentProfileId: drift.Value(coefficients.equipmentProfileId),
        filterName: coefficients.filterName,
        colorTerm: coefficients.colorTerm,
        extinctionCoefficient: coefficients.extinctionCoefficient,
        zeroPoint: coefficients.zeroPoint,
        rmsResidual: coefficients.rmsResidual,
        matchedStarCount: drift.Value(coefficients.matchedStarCount),
        catalogSource: drift.Value(coefficients.catalogSource),
        fitDataJson: drift.Value(fitDataJson),
        dateComputed: drift.Value(coefficients.dateComputed),
      ),
    );
  }

  /// Delete a saved transform.
  Future<void> deleteTransform(int id) {
    return _scienceDao.deletePhotometricTransform(id);
  }

  /// Load the best available transform for a given filter.
  Future<PhotometricTransformCoefficients?> getTransformForFilter(
    String filterName, {
    int? equipmentProfileId,
  }) async {
    final row = await _scienceDao.getTransformForFilter(
      filterName,
      equipmentProfileId: equipmentProfileId,
    );
    if (row == null) {
      return null;
    }
    return _rowToCoefficients(row);
  }

  /// Load all saved transforms.
  Future<List<PhotometricTransformCoefficients>> getAllTransforms() async {
    final rows = await _scienceDao.getAllTransforms();
    return rows.map(_rowToCoefficients).toList(growable: false);
  }

  PhotometricTransformCoefficients _rowToCoefficients(
      db.PhotometricTransformRow row) {
    List<TransformStarMatch> fitData = const [];
    if (row.fitDataJson != null && row.fitDataJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.fitDataJson!);
        if (decoded is List) {
          fitData = decoded
              .whereType<Map<String, dynamic>>()
              .map(TransformStarMatch.fromJson)
              .toList(growable: false);
        }
      } catch (error) {
        _logger.warning(
          'Failed to decode fit data JSON for transform ${row.id}: $error',
          source: 'PhotometricTransformService',
        );
      }
    }

    return PhotometricTransformCoefficients(
      id: row.id,
      equipmentProfileId: row.equipmentProfileId,
      filterName: row.filterName,
      colorTerm: row.colorTerm,
      extinctionCoefficient: row.extinctionCoefficient,
      zeroPoint: row.zeroPoint,
      rmsResidual: row.rmsResidual,
      matchedStarCount: row.matchedStarCount,
      catalogSource: row.catalogSource,
      fitData: fitData,
      dateComputed: row.dateComputed,
    );
  }
}

final photometricTransformServiceProvider =
    Provider<PhotometricTransformService>((ref) {
  return PhotometricTransformService(ref);
});
