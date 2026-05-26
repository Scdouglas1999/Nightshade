// Per-device-type equipment defaults surfaced in Settings → Equipment
// (and the equipment-profile editor). Owns the connect-time defaults for
// camera, mount, focuser, and guider hardware behaviours.
//
// Owns:
//   * Camera: coolingBehavior, defaultGain, defaultOffset
//   * Mount: enableMeridianFlip
//   * Focuser: tempCompensation, tempCoefficient, backlashCompensation
//   * Guider: ditherScale, settleThreshold, settleTimeout
//
// Does NOT own:
//   * Per-device connection details (those live in EquipmentProfile) —
//     these are the FALLBACK defaults when a profile has no override.
//   * Autofocus algorithm tuning → see `autofocus.dart`.
//   * PHD2 connection (host/port/path) → see `phd2.dart`.
//   * Meridian-flip timing knob (`meridianFlipMinutes`) → see
//     `sequencer.dart`. The `enableMeridianFlip` toggle here owns whether
//     the mount supports flips at all; the timing is a sequencer concern.
part of '../settings_provider.dart';

/// Setters for per-device-type equipment-default knobs.
extension EquipmentSettingsSection on AppSettingsNotifier {
  // -------- Camera defaults --------
  Future<void> setCoolingBehavior(String value) async {
    await _saveSetting('cooling_behavior', value);
    _patchState((s) => s.copyWith(coolingBehavior: value));
  }

  Future<void> setDefaultGain(int value) async {
    await _saveSetting('default_gain', value.toString());
    _patchState((s) => s.copyWith(defaultGain: value));
  }

  Future<void> setDefaultOffset(int value) async {
    await _saveSetting('default_offset', value.toString());
    _patchState((s) => s.copyWith(defaultOffset: value));
  }

  // -------- Mount defaults --------
  Future<void> setEnableMeridianFlip(bool value) async {
    await _saveSetting('enable_meridian_flip', value.toString());
    _patchState((s) => s.copyWith(enableMeridianFlip: value));
  }

  // -------- Focuser defaults --------
  Future<void> setTempCompensation(bool value) async {
    await _saveSetting('temp_compensation', value.toString());
    _patchState((s) => s.copyWith(tempCompensation: value));
  }

  Future<void> setTempCoefficient(double value) async {
    await _saveSetting('temp_coefficient', value.toString());
    _patchState((s) => s.copyWith(tempCoefficient: value));
  }

  Future<void> setBacklashCompensation(int value) async {
    await _saveSetting('backlash_compensation', value.toString());
    _patchState((s) => s.copyWith(backlashCompensation: value));
  }

  // -------- Guider defaults --------
  Future<void> setDitherScale(String value) async {
    await _saveSetting('dither_scale', value);
    _patchState((s) => s.copyWith(ditherScale: value));
  }

  Future<void> setSettleThreshold(double value) async {
    await _saveSetting('settle_threshold', value.toString());
    _patchState((s) => s.copyWith(settleThreshold: value));
  }

  Future<void> setSettleTimeout(int value) async {
    await _saveSetting('settle_timeout', value.toString());
    _patchState((s) => s.copyWith(settleTimeout: value));
  }
}
