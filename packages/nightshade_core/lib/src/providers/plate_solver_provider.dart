import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plate_solver.dart';
import '../services/plate_solve_service.dart';

/// Detection snapshot for the Plate Solving settings page. Re-runs the
/// filesystem probe + ASTAP catalog scan via `PlateSolveService.detect()`
/// whenever invalidated (after the user picks a new path or hits "Re-scan").
final plateSolverDetectionProvider =
    FutureProvider.autoDispose<PlateSolverDetection>((ref) async {
  final service = ref.watch(plateSolveServiceProvider);
  return service.detect();
});

/// Persisted plate-solver UX configuration. Backed by Rust storage
/// (`platesolver.json`), exposed through `apiPlatesolveGetConfig`.
final plateSolverPreferenceProvider =
    FutureProvider.autoDispose<PlateSolverPreference>((ref) async {
  final service = ref.watch(plateSolveServiceProvider);
  return service.getConfig();
});

/// State + controller for the Plate Solving settings page.
///
/// The page interacts with this notifier rather than touching the service
/// directly so verify-result toasts, in-flight spinners, and the latest
/// preference round-trip all live in one observable place.
class PlateSolverSettingsState {
  /// Most recent verify-solver result for ASTAP. `null` until the user has
  /// pressed "Verify" at least once for the configured ASTAP binary.
  final PlateSolverInfo? astapVerifyInfo;

  /// Error message from the most recent ASTAP verify attempt, or `null` if
  /// verify hasn't run or succeeded.
  final String? astapVerifyError;

  /// Most recent verify-solver result for Astrometry.net.
  final PlateSolverInfo? astrometryVerifyInfo;

  /// Error message from the most recent Astrometry.net verify attempt.
  final String? astrometryVerifyError;

  /// True while a verify-solver call is in flight, irrespective of which
  /// engine. The UI disables both verify buttons during that window so the
  /// user can't queue overlapping `--help` invocations.
  final bool verifying;

  /// True while a `setConfig` write is in flight. Re-entering save before
  /// the previous write returns would race the cache invalidation.
  final bool savingPreference;

  const PlateSolverSettingsState({
    this.astapVerifyInfo,
    this.astapVerifyError,
    this.astrometryVerifyInfo,
    this.astrometryVerifyError,
    this.verifying = false,
    this.savingPreference = false,
  });

  PlateSolverSettingsState copyWith({
    PlateSolverInfo? astapVerifyInfo,
    String? astapVerifyError,
    PlateSolverInfo? astrometryVerifyInfo,
    String? astrometryVerifyError,
    bool? verifying,
    bool? savingPreference,
    bool clearAstapVerify = false,
    bool clearAstrometryVerify = false,
  }) {
    return PlateSolverSettingsState(
      astapVerifyInfo:
          clearAstapVerify ? null : (astapVerifyInfo ?? this.astapVerifyInfo),
      astapVerifyError:
          clearAstapVerify ? null : (astapVerifyError ?? this.astapVerifyError),
      astrometryVerifyInfo: clearAstrometryVerify
          ? null
          : (astrometryVerifyInfo ?? this.astrometryVerifyInfo),
      astrometryVerifyError: clearAstrometryVerify
          ? null
          : (astrometryVerifyError ?? this.astrometryVerifyError),
      verifying: verifying ?? this.verifying,
      savingPreference: savingPreference ?? this.savingPreference,
    );
  }
}

class PlateSolverSettingsNotifier
    extends StateNotifier<PlateSolverSettingsState> {
  final Ref ref;

  PlateSolverSettingsNotifier(this.ref)
      : super(const PlateSolverSettingsState());

  PlateSolveService get _service => ref.read(plateSolveServiceProvider);

  /// Force a fresh detection round (file system probe + catalog scan).
  Future<void> rescan() async {
    ref.invalidate(plateSolverDetectionProvider);
    // The `await` here ensures any test driver can observe the new detect
    // result before returning. Production callers can fire-and-forget.
    await ref.read(plateSolverDetectionProvider.future);
  }

  /// Persist a new preference and refresh both detection + preference
  /// providers so the UI rebuilds against the new paths.
  ///
  /// Surfaces failures as state-level errors rather than re-throwing so
  /// the settings page can render an inline message — but does NOT swallow
  /// the underlying error: callers checking the returned bool know whether
  /// to leave optimistic UI changes in place.
  Future<bool> updatePreference(PlateSolverPreference next) async {
    if (state.savingPreference) {
      // A previous save is still in flight. Refuse to queue duplicates —
      // the user can retry once the active save resolves.
      return false;
    }
    state = state.copyWith(savingPreference: true);
    try {
      await _service.setConfig(next);
      ref.invalidate(plateSolverPreferenceProvider);
      ref.invalidate(plateSolverDetectionProvider);
      state = state.copyWith(savingPreference: false);
      return true;
    } catch (e) {
      state = state.copyWith(savingPreference: false);
      rethrow;
    }
  }

  /// Run `--help` against the user-supplied ASTAP path. Updates state so
  /// the settings page can render a green check or red banner inline.
  Future<void> verifyAstap(String executablePath) async {
    if (state.verifying) return;
    state = state.copyWith(verifying: true, clearAstapVerify: true);
    try {
      final info = await _service.verify(executablePath);
      state = state.copyWith(
        verifying: false,
        astapVerifyInfo: info,
      );
    } catch (e) {
      state = state.copyWith(
        verifying: false,
        astapVerifyError: e.toString(),
      );
    }
  }

  /// Run `--help` against the user-supplied solve-field path.
  Future<void> verifyAstrometry(String executablePath) async {
    if (state.verifying) return;
    state = state.copyWith(verifying: true, clearAstrometryVerify: true);
    try {
      final info = await _service.verify(executablePath);
      state = state.copyWith(
        verifying: false,
        astrometryVerifyInfo: info,
      );
    } catch (e) {
      state = state.copyWith(
        verifying: false,
        astrometryVerifyError: e.toString(),
      );
    }
  }
}

final plateSolverSettingsNotifierProvider = StateNotifierProvider.autoDispose<
    PlateSolverSettingsNotifier, PlateSolverSettingsState>((ref) {
  return PlateSolverSettingsNotifier(ref);
});
