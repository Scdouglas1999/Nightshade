part of '../night_analysis_service.dart';

/// One sub's per-sub metrics, denormalized from `captured_images` (+ optional
/// science enrichment) into a plain value object the detectors operate on.
///
/// Public so tests can build synthetic series directly and drive
/// [NightAnalysisService.analyze] without a database.
class NightSub {
  const NightSub({
    required this.id,
    required this.capturedAt,
    this.filter,
    this.isAccepted = true,
    this.hfr,
    this.starCount,
    this.background,
    this.noise,
    this.guidingRmsTotal,
    this.focuserPosition,
    this.focuserTemp,
    this.sensorTemp,
    this.eccentricity,
    this.snr,
    this.fwhm,
  });

  final int id;
  final DateTime capturedAt;
  final String? filter;
  final bool isAccepted;
  final double? hfr;
  final int? starCount;
  final double? background;
  final double? noise;
  final double? guidingRmsTotal;
  final int? focuserPosition;
  final double? focuserTemp;
  final double? sensorTemp;
  final double? eccentricity;

  /// Background-corrected SNR (science table); null when the science pipeline
  /// did not run for this sub.
  final double? snr;

  /// Field-median FWHM (science PSF tiles); null when absent.
  final double? fwhm;
}

/// The analyzed night: a time-sorted list of [NightSub]s. Thin wrapper so the
/// detector signatures read clearly and future cross-sub aggregates have a home.
class NightData {
  NightData(List<NightSub> subs, {this.opticalDiagnostics})
    : subs = List.unmodifiable(
        [...subs]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt)),
      );

  final List<NightSub> subs;

  /// Session-level optical-train diagnostics (field tilt / collimation)
  /// computed from the science PSF field tiles + astrometric residuals.
  /// Null when the science pipeline produced no tiles for the session.
  final OpticalTrainDiagnostics? opticalDiagnostics;

  bool get isEmpty => subs.isEmpty;
  int get length => subs.length;
}
