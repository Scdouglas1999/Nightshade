// Sequencer-execution defaults surfaced in Settings → Sequencer. Owns the
// behaviour-tree-level knobs the executor consults: park triggers, the
// meridian-flip warning window, autofocus cadence, dither cadence, and
// the native-vs-simulation execution toggle.
//
// Owns:
//   * parkOnUnsafeWeather, parkBeforeDawn, safetyFailMode
//   * meridianFlipMinutes, autoFocusOnFilterChange, useFilterFocusOffsets
//   * autoFocusEveryMinutes
//   * ditherEnabled, ditherEveryFrames
//   * useNativeExecution, useSimulationMode
//
// Does NOT own:
//   * Per-instruction recovery defaults → see `recovery.dart`.
//   * Per-filter dither scale / settle parameters → see `equipment.dart`
//     (those describe the guider hardware, not sequence orchestration).
//   * Autofocus algorithm knobs → see `autofocus.dart`.
//   * Smart Night auto-builder defaults → see `smart_night.dart`.
part of '../settings_provider.dart';

/// Setters for sequencer-execution defaults.
extension SequencerSettingsSection on AppSettingsNotifier {
  Future<void> setParkOnUnsafeWeather(bool value) async {
    await _saveSetting('park_on_unsafe_weather', value.toString());
    _patchState((s) => s.copyWith(parkOnUnsafeWeather: value));
  }

  Future<void> setParkBeforeDawn(bool value) async {
    await _saveSetting('park_before_dawn', value.toString());
    _patchState((s) => s.copyWith(parkBeforeDawn: value));
  }

  Future<void> setSafetyFailMode(SafetyFailMode value) async {
    await _saveSetting('safety_fail_mode', value.name);
    _patchState((s) => s.copyWith(safetyFailMode: value));
  }

  Future<void> setMeridianFlipMinutes(int value) async {
    await _saveSetting('meridian_flip_minutes', value.toString());
    _patchState((s) => s.copyWith(meridianFlipMinutes: value));
  }

  Future<void> setAutoFocusOnFilterChange(bool value) async {
    await _saveSetting('auto_focus_on_filter_change', value.toString());
    _patchState((s) => s.copyWith(autoFocusOnFilterChange: value));
  }

  Future<void> setUseFilterFocusOffsets(bool value) async {
    await _saveSetting('use_filter_focus_offsets', value.toString());
    _patchState((s) => s.copyWith(useFilterFocusOffsets: value));
  }

  Future<void> setAutoFocusEveryMinutes(int value) async {
    await _saveSetting('auto_focus_every_minutes', value.toString());
    _patchState((s) => s.copyWith(autoFocusEveryMinutes: value));
  }

  Future<void> setDitherEnabled(bool value) async {
    await _saveSetting('dither_enabled', value.toString());
    _patchState((s) => s.copyWith(ditherEnabled: value));
  }

  Future<void> setDitherEveryFrames(int value) async {
    await _saveSetting('dither_every_frames', value.toString());
    _patchState((s) => s.copyWith(ditherEveryFrames: value));
  }

  Future<void> setUseNativeExecution(bool value) async {
    await _saveSetting('use_native_execution', value.toString());
    _patchState((s) => s.copyWith(useNativeExecution: value));
  }

  Future<void> setUseSimulationMode(bool value) async {
    await _saveSetting('use_simulation_mode', value.toString());
    _patchState((s) => s.copyWith(useSimulationMode: value));
  }
}
