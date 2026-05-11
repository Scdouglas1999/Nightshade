import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/polar_alignment_config.dart';
import '../providers/backend_provider.dart';

/// Service entry points for polar alignment routines.
///
/// The Riverpod state machine for polar alignment lives in
/// `polar_alignment_provider.dart` (`PolarAlignmentStateNotifier`). This
/// service is a thin layer that exposes algorithm-specific entry points
/// (`threePoint`, `allSky`) so callers don't have to thread mode flags
/// through the rest of the codebase.
class PolarAlignmentService {
  final Ref _ref;

  PolarAlignmentService(this._ref);

  /// Start the legacy Three-Point Polar Alignment routine. Requires a clear
  /// view of the celestial pole region.
  Future<void> threePoint(PolarAlignmentConfig config) async {
    final validationErrors = config.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError(
        'Invalid polar alignment configuration: ${validationErrors.join(', ')}',
      );
    }

    final backend = _ref.read(backendProvider);
    await backend.startPolarAlignment(
      exposureTime: config.exposureTime,
      stepSize: config.stepSize,
      binning: config.binning,
      isNorth: config.isNorth,
      manualRotation: config.manualRotation,
      rotateEast: config.rotateEast,
      gain: config.gain,
      offset: config.offset,
      solveTimeout: config.solveTimeout,
      startFromCurrent: config.startFromCurrent,
    );
  }

  /// Start the all-sky (Sharpcap-style) polar alignment routine. Works from
  /// any direction in the sky — does **not** require the pole region to be
  /// visible. Requires an external plate solver (ASTAP); the backend throws
  /// if one is not installed.
  ///
  /// The `acceptanceThresholdArcsec` argument controls when the alignment
  /// auto-completes: the total error must stay below this value for 3
  /// consecutive seconds. The default (30″) corresponds to ~3-minute
  /// unguided imaging precision. Use 10″ for guided long-sub work,
  /// 60–120″ for visual / planetary use.
  ///
  /// The `iterationCadenceSecs` argument throttles re-solves so the user
  /// can read the on-screen arrows. Defaults to 3 seconds.
  Future<void> allSky({
    required PolarAlignmentConfig config,
    double? acceptanceThresholdArcsec,
    double? iterationCadenceSecs,
  }) async {
    final validationErrors = config.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError(
        'Invalid polar alignment configuration: ${validationErrors.join(', ')}',
      );
    }

    final threshold = acceptanceThresholdArcsec ?? config.autoCompleteThreshold;
    final cadence = iterationCadenceSecs ?? 3.0;
    if (threshold <= 0) {
      throw ArgumentError(
        'All-sky acceptance threshold must be positive (got $threshold)',
      );
    }
    if (cadence < 0.5) {
      throw ArgumentError(
        'All-sky iteration cadence must be at least 0.5 seconds (got $cadence)',
      );
    }

    final backend = _ref.read(backendProvider);
    try {
      await backend.startAllSkyPolarAlignment(
        exposureTime: config.exposureTime,
        solveTimeout: config.solveTimeout,
        binning: config.binning,
        isNorth: config.isNorth,
        acceptanceThresholdArcsec: threshold,
        iterationCadenceSecs: cadence,
        gain: config.gain,
        offset: config.offset,
      );
    } catch (e) {
      // Re-emit as a structured exception so the UI can show an actionable
      // message. The Rust layer returns a clear "Plate solver required —
      // install ASTAP" error when no solver is configured; surface it
      // verbatim rather than wrapping.
      debugPrint('[PolarAlignmentService] allSky failed: $e');
      rethrow;
    }
  }

  /// Stop any currently-running polar alignment (TPPA or all-sky).
  Future<void> stop() async {
    final backend = _ref.read(backendProvider);
    await backend.stopPolarAlignment();
  }
}

/// Riverpod provider for the polar alignment service.
final polarAlignmentServiceProvider = Provider<PolarAlignmentService>((ref) {
  return PolarAlignmentService(ref);
});
