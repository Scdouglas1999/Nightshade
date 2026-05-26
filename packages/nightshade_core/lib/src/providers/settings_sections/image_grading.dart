// Pack G — Wave 3 Image Grading defaults. Owns the live-frame Pass/Reject
// thresholds the executor consults to auto-reject obviously-bad frames
// (catastrophic focus drift, trailed stars, clouds rolling in, etc.).
//
// Each threshold is independently nullable: passing `null` disables that
// specific check while keeping other grading active. The master switch
// [setEnableImageGrading] gates the whole subsystem.
//
// Owns:
//   * enableImageGrading (master)
//   * imageGradingHfrThresholdPx, imageGradingHfrBaselinePercent
//   * imageGradingEccentricityThreshold, imageGradingStarCountMin
//   * imageGradingMaxConsecutiveRejects, imageGradingRejectFolderPath
//
// Does NOT own:
//   * Per-node `quality_check` overrides on TakeExposure nodes — those live
//     in the sequence model, not in app settings.
//   * Adaptive exposure (which is a separate Wave 5 system) → see
//     `adaptive_exposure.dart`.
part of '../settings_provider.dart';

/// Setters for Pack G live-frame Pass/Reject grading defaults.
extension ImageGradingSettingsSection on AppSettingsNotifier {
  /// Master switch: when false, live frame Pass/Reject grading is disabled
  /// at the executor level. Per-node `quality_check` on TakeExposure
  /// nodes still wins; this only toggles the *default*.
  Future<void> setEnableImageGrading(bool value) async {
    await _saveSetting('image_grading_enabled', value.toString());
    _patchState((s) => s.copyWith(enableImageGrading: value));
  }

  /// Reject if HFR exceeds this absolute pixel value. Pass `null` to
  /// disable the check while keeping other grading enabled.
  Future<void> setImageGradingHfrThreshold(double? value) async {
    await _saveSetting(
      'image_grading_hfr_threshold_px',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingHfrThresholdPx: value));
  }

  /// Reject if HFR exceeds `baseline * (1 + percent / 100)`. Pass `null`
  /// to disable.
  Future<void> setImageGradingHfrBaselinePercent(double? value) async {
    await _saveSetting(
      'image_grading_hfr_baseline_percent',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingHfrBaselinePercent: value));
  }

  /// Reject if star eccentricity exceeds this value. Typical thresholds:
  /// 0.6 catches trailed frames; 0.8 catches catastrophic tracking
  /// failure. Pass `null` to disable.
  Future<void> setImageGradingEccentricityThreshold(double? value) async {
    await _saveSetting(
      'image_grading_eccentricity_threshold',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingEccentricityThreshold: value));
  }

  /// Reject if star count drops below this value. Pass `null` to disable.
  Future<void> setImageGradingStarCountMin(int? value) async {
    await _saveSetting(
      'image_grading_star_count_min',
      value == null ? 'null' : value.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingStarCountMin: value));
  }

  /// Pause the sequence after this many consecutive rejects. Required;
  /// the strategic-report default is 3. Clamped to >= 1 so the safety
  /// valve is always active.
  Future<void> setImageGradingMaxConsecutiveRejects(int value) async {
    final clamped = value < 1 ? 1 : value;
    await _saveSetting(
      'image_grading_max_consecutive_rejects',
      clamped.toString(),
    );
    _patchState((s) => s.copyWith(imageGradingMaxConsecutiveRejects: clamped));
  }

  /// Override for the reject folder. `null` or empty => use the default
  /// `<save_path>/Reject/`. Relative paths resolve against the run
  /// save_path; absolute paths are honoured verbatim.
  Future<void> setImageGradingRejectFolderPath(String? value) async {
    final normalised = (value == null || value.trim().isEmpty) ? null : value;
    await _saveSetting(
      'image_grading_reject_folder_path',
      normalised ?? '',
    );
    _patchState((s) => s.copyWith(imageGradingRejectFolderPath: normalised));
  }
}
