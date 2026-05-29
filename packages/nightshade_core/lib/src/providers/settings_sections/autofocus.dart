// Autofocus algorithm and per-filter configuration surfaced in
// Settings → Autofocus. The biggest single section because the autofocus
// system has the most tunable parameters (curve fitting, step sizing,
// crop ratios, R² threshold, backlash compensation, per-filter overrides).
//
// Owns:
//   * Algorithm: afMethod, afCurveFitting, afStepSize, afExposureTime,
//     afInitialOffsetSteps, afNumberOfAttempts, afUseBrightestNStars
//   * Frame processing: afOuterCropRatio, afInnerCropRatio, afBinning,
//     afRSquaredThreshold
//   * Orchestration: afDisableGuidingDuringAf, afFocuserSettleTimeMs,
//     afExposuresPerPoint
//   * Backlash: afBacklashCompMethod, afBacklashIn, afBacklashOut
//   * Per-filter: afAutofocusFilterName, afFilterSettingsJson +
//     setFilterAutofocusConfig / removeFilterAutofocusConfig helpers
//
// Does NOT own:
//   * Sequence-level AF cadence (`autoFocusEveryMinutes`,
//     `autoFocusOnFilterChange`, `useFilterFocusOffsets`) → see
//     `sequencer.dart`.
//   * Smart Night default AF cadence (separate planning system) → see
//     `smart_night.dart`.
//   * Focuser hardware defaults (temp compensation, backlash compensation
//     on the focuser itself) → see `equipment.dart`.
part of '../settings_provider.dart';

/// Setters for autofocus algorithm and per-filter configuration.
extension AutofocusSettingsSection on AppSettingsNotifier {
  Future<void> setAfMethod(String value) async {
    await _saveSetting('af_method', value);
    _patchState((s) => s.copyWith(afMethod: value));
  }

  Future<void> setAfCurveFitting(String value) async {
    await _saveSetting('af_curve_fitting', value);
    _patchState((s) => s.copyWith(afCurveFitting: value));
  }

  Future<void> setAfStepSize(int value) async {
    await _saveSetting('af_step_size', value.toString());
    _patchState((s) => s.copyWith(afStepSize: value));
  }

  Future<void> setAfExposureTime(double value) async {
    await _saveSetting('af_exposure_time', value.toString());
    _patchState((s) => s.copyWith(afExposureTime: value));
  }

  Future<void> setAfInitialOffsetSteps(int value) async {
    await _saveSetting('af_initial_offset_steps', value.toString());
    _patchState((s) => s.copyWith(afInitialOffsetSteps: value));
  }

  Future<void> setAfNumberOfAttempts(int value) async {
    await _saveSetting('af_number_of_attempts', value.toString());
    _patchState((s) => s.copyWith(afNumberOfAttempts: value));
  }

  Future<void> setAfUseBrightestNStars(int value) async {
    await _saveSetting('af_use_brightest_n_stars', value.toString());
    _patchState((s) => s.copyWith(afUseBrightestNStars: value));
  }

  Future<void> setAfOuterCropRatio(double value) async {
    await _saveSetting('af_outer_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afOuterCropRatio: value));
  }

  Future<void> setAfInnerCropRatio(double value) async {
    await _saveSetting('af_inner_crop_ratio', value.toString());
    _patchState((s) => s.copyWith(afInnerCropRatio: value));
  }

  Future<void> setAfBinning(int value) async {
    await _saveSetting('af_binning', value.toString());
    _patchState((s) => s.copyWith(afBinning: value));
  }

  Future<void> setAfRSquaredThreshold(double value) async {
    await _saveSetting('af_r_squared_threshold', value.toString());
    _patchState((s) => s.copyWith(afRSquaredThreshold: value));
  }

  Future<void> setAfDisableGuidingDuringAf(bool value) async {
    await _saveSetting('af_disable_guiding', value.toString());
    _patchState((s) => s.copyWith(afDisableGuidingDuringAf: value));
  }

  Future<void> setAfFocuserSettleTimeMs(int value) async {
    await _saveSetting('af_focuser_settle_time_ms', value.toString());
    _patchState((s) => s.copyWith(afFocuserSettleTimeMs: value));
  }

  Future<void> setAfExposuresPerPoint(int value) async {
    await _saveSetting('af_exposures_per_point', value.toString());
    _patchState((s) => s.copyWith(afExposuresPerPoint: value));
  }

  Future<void> setAfBacklashCompMethod(String value) async {
    await _saveSetting('af_backlash_comp_method', value);
    _patchState((s) => s.copyWith(afBacklashCompMethod: value));
  }

  Future<void> setAfBacklashIn(int value) async {
    await _saveSetting('af_backlash_in', value.toString());
    _patchState((s) => s.copyWith(afBacklashIn: value));
  }

  Future<void> setAfBacklashOut(int value) async {
    await _saveSetting('af_backlash_out', value.toString());
    _patchState((s) => s.copyWith(afBacklashOut: value));
  }

  Future<void> setAfAutofocusFilterName(String value) async {
    await _saveSetting('af_autofocus_filter_name', value);
    _patchState((s) => s.copyWith(afAutofocusFilterName: value));
  }

  Future<void> setAfFilterSettingsJson(String value) async {
    await _saveSetting('af_filter_settings', value);
    _patchState((s) => s.copyWith(afFilterSettingsJson: value));
  }

  /// Update a single filter's autofocus configuration.
  ///
  /// Loads the current filter settings map, updates the entry for [filterName],
  /// serializes back to JSON, and persists to the database.
  Future<void> setFilterAutofocusConfig(
      String filterName, FilterAutofocusConfig config) async {
    final currentJson = _currentValueOrNull?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map[filterName] = config;
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }

  /// Remove a filter's autofocus configuration.
  Future<void> removeFilterAutofocusConfig(String filterName) async {
    final currentJson = _currentValueOrNull?.afFilterSettingsJson ?? '{}';
    final map = AutofocusSettings.parseFilterSettingsJson(currentJson);
    map.remove(filterName);
    final newJson = AutofocusSettings.encodeFilterSettingsJson(map);
    await setAfFilterSettingsJson(newJson);
  }
}
