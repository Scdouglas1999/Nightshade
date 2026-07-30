// Plate-solver defaults surfaced in Settings → Plate Solving. Owns the
// solver-selection knob plus the per-solver path / search radius / timeout
// fields the PlateSolveService consults.
//
// Owns:
//   * plateSolver (ASTAP / Astrometry.net / PlateSolve2)
//   * astapPath, astrometryPath
//   * plateSolveTimeout, plateSolveSearchRadius, blindSolve
//   * centeringSyncMount — whether centering syncs the mount to the solved
//     position between iterations, read by the callers that build a
//     CenteringConfig
//
// Does NOT own:
//   * Centering tolerance / framing-assistant defaults — those live in the
//     CenteringService config, not in app settings.
part of '../settings_provider.dart';

/// Setters for plate-solver defaults.
extension PlateSolveSettingsSection on AppSettingsNotifier {
  Future<void> setPlateSolver(String value) async {
    await _saveSetting('plate_solver', value);
    _patchState((s) => s.copyWith(plateSolver: value));
  }

  Future<void> setAstapPath(String value) async {
    await _saveSetting('astap_path', value);
    _patchState((s) => s.copyWith(astapPath: value));
  }

  Future<void> setAstrometryPath(String value) async {
    await _saveSetting('astrometry_path', value);
    _patchState((s) => s.copyWith(astrometryPath: value));
  }

  Future<void> setPlateSolveTimeout(int value) async {
    await _saveSetting('plate_solve_timeout', value.toString());
    _patchState((s) => s.copyWith(plateSolveTimeout: value));
  }

  Future<void> setPlateSolveSearchRadius(double value) async {
    await _saveSetting('plate_solve_search_radius', value.toString());
    _patchState((s) => s.copyWith(plateSolveSearchRadius: value));
  }

  Future<void> setBlindSolve(bool value) async {
    await _saveSetting('blind_solve', value.toString());
    _patchState((s) => s.copyWith(blindSolve: value));
  }

  Future<void> setCenteringSyncMount(bool value) async {
    await _saveSetting('centering_sync_mount', value.toString());
    _patchState((s) => s.copyWith(centeringSyncMount: value));
  }
}
