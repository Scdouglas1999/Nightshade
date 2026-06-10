// Wave 5 Agent 2 — Sky-Brightness Adaptive Exposure defaults. Owns the
// global default exposure-scaling config the executor consults when a
// TakeExposure node has no per-node override. Captures both the scalar
// reference values and the per-filter override maps.
//
// Owns:
//   * adaptiveExposureEnabled (master), adaptiveExposureTargetSnr
//   * adaptiveExposureReferenceMag, adaptiveExposureMinSecs,
//     adaptiveExposureMaxSecs
//   * adaptiveExposurePerFilterEnabled, *PerFilterMinSecs, *PerFilterMaxSecs
//
// Does NOT own:
//   * Per-node `ExposureNode.adaptiveExposure` overrides — those live in
//     the sequence model.
//   * Smart Night exposure-floor / ceiling (a separate planning system
//     with its own clamps) → see `smart_night.dart`.
part of '../settings_provider.dart';

/// Setters for sky-brightness adaptive exposure defaults.
extension AdaptiveExposureSettingsSection on AppSettingsNotifier {
  /// Master switch for the global default sky-brightness adaptive
  /// exposure. Off => the executor's runtime default is cleared and
  /// only per-node `ExposureNode.adaptiveExposure` overrides apply.
  Future<void> setAdaptiveExposureEnabled(bool value) async {
    await _saveSetting('adaptive_exposure_enabled', value.toString());
    _patchState((s) => s.copyWith(adaptiveExposureEnabled: value));
  }

  /// Target SNR for the adaptive scaling (informational; the live
  /// math uses background flux ratio, not a direct SNR solver).
  Future<void> setAdaptiveExposureTargetSnr(double value) async {
    final clamped = value < 1.0 ? 1.0 : value;
    await _saveSetting('adaptive_exposure_target_snr', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureTargetSnr: clamped));
  }

  /// Reference sky brightness in mag/arcsec² that the nominal duration
  /// was calibrated for. Bigger = darker; a dark site is 21.5+, an
  /// urban backyard is 18-19.
  Future<void> setAdaptiveExposureReferenceMag(double value) async {
    // Sky brightness physically lives in [14, 23] mag/arcsec²; clamp
    // defensively but allow the user to type anything in that band.
    final clamped = value.clamp(14.0, 24.0);
    await _saveSetting('adaptive_exposure_reference_mag', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureReferenceMag: clamped));
  }

  /// Global minimum exposure clamp in seconds.
  Future<void> setAdaptiveExposureMinSecs(double value) async {
    final clamped = value < 0.001 ? 0.001 : value;
    await _saveSetting('adaptive_exposure_min_secs', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureMinSecs: clamped));
  }

  /// Global maximum exposure clamp in seconds.
  Future<void> setAdaptiveExposureMaxSecs(double value) async {
    final clamped = value < 0.001 ? 0.001 : value;
    await _saveSetting('adaptive_exposure_max_secs', clamped.toString());
    _patchState((s) => s.copyWith(adaptiveExposureMaxSecs: clamped));
  }

  /// Per-filter enable map. JSON-serialised for storage.
  Future<void> setAdaptiveExposurePerFilterEnabled(
    Map<String, bool> map,
  ) async {
    await _saveSetting('adaptive_exposure_per_filter_enabled', jsonEncode(map));
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterEnabled: map));
  }

  /// Per-filter minimum exposure clamp map (seconds).
  Future<void> setAdaptiveExposurePerFilterMinSecs(
    Map<String, double> map,
  ) async {
    await _saveSetting(
      'adaptive_exposure_per_filter_min_secs',
      jsonEncode(map),
    );
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterMinSecs: map));
  }

  /// Per-filter maximum exposure clamp map (seconds).
  Future<void> setAdaptiveExposurePerFilterMaxSecs(
    Map<String, double> map,
  ) async {
    await _saveSetting(
      'adaptive_exposure_per_filter_max_secs',
      jsonEncode(map),
    );
    _patchState((s) => s.copyWith(adaptiveExposurePerFilterMaxSecs: map));
  }
}
