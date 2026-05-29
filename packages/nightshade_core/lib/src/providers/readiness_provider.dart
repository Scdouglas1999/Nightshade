import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/equipment/equipment_models.dart';
import '../models/readiness/readiness_models.dart';
import 'dark_library_provider.dart';
import 'equipment/camera_state_provider.dart';
import 'equipment/focuser_state_provider.dart';
import 'equipment/mount_state_provider.dart';
import 'plate_solver_provider.dart';
import 'profiles_provider.dart';
import 'settings_provider.dart';

/// Composes the app's existing setup signals into a single, fail-closed
/// [ReadinessReport].
///
/// This is the provider layer that feeds the pure [buildReadinessReport]
/// decision function (see `models/readiness/readiness_models.dart`). It owns
/// exactly one responsibility: collect a handful of booleans from the
/// device-state / settings / plate-solver / dark-library providers and hand
/// them to the pure builder. All readiness *rules* live in the model so they
/// are unit-testable without Riverpod; this file only wires inputs.
///
/// ## Fail-closed contract
///
/// Every input is collected so that *absence of positive evidence is treated
/// as "not satisfied"*. Concretely:
///
/// * Async providers ([appSettingsProvider], [plateSolverDetectionProvider],
///   [darkLibraryStatsProvider]) are read via `.valueOrNull`; a `null` (still
///   loading) or an error state collapses the corresponding flag to `false`.
///   We never optimistically assume a setting is configured just because we
///   have not finished reading it.
/// * Device connection is satisfied only on an explicit
///   [DeviceConnectionState.connected]. `connecting`, `error`, and
///   `disconnected` all read as not-connected.
///
/// This is deliberate: per the project's "errors are a feature" stance, a
/// genuinely disconnected camera or an unreadable settings store must surface
/// as a blocking readiness item, not silently degrade to "ready".
///
/// Because each input provider is itself reactive, this `Provider` recomputes
/// automatically whenever any underlying signal changes — there is no manual
/// invalidation to maintain.
final readinessReportProvider = Provider<ReadinessReport>((ref) {
  // --- Critical devices -----------------------------------------------------
  // A profile is "present" if any equipment profile exists. The active-profile
  // selector is derived from the same state, so watching the list is the
  // single, cheapest signal that the user has completed equipment setup.
  final hasProfile = ref.watch(equipmentProfileListProvider).isNotEmpty;

  // Connection is satisfied ONLY on an explicit `connected` state. Every other
  // state (disconnected / connecting / error) is fail-closed to false.
  final cameraConnected = ref.watch(cameraStateProvider).connectionState ==
      DeviceConnectionState.connected;
  final mountConnected = ref.watch(mountStateProvider).connectionState ==
      DeviceConnectionState.connected;

  // --- Location & output path (persisted settings) --------------------------
  // `appSettingsProvider` is async; while it loads (`valueOrNull == null`) or
  // on error, both derived flags fail closed to false.
  final settings = ref.watch(appSettingsProvider).valueOrNull;

  // 0.0/0.0 is the unset sentinel used throughout settings_provider; a
  // location counts as configured only when BOTH coordinates are non-zero.
  final locationSet = settings != null &&
      settings.latitude != 0.0 &&
      settings.longitude != 0.0;

  // The capture output directory is persisted via
  // `SettingsDao.setDefaultImageDirectory`, surfaced here as
  // `imageOutputPath`. Onboarding's `complete()` writes the same field.
  final outputPathSet = settings != null && settings.imageOutputPath.trim().isNotEmpty;

  // --- Plate solver ---------------------------------------------------------
  // A rig is solver-ready when ANY usable solver is configured — ASTAP (with a
  // catalog) OR astrometry.net. `hasAnySolver` encodes exactly that. Gating on
  // `astapReady` alone would falsely flag an astrometry.net-only setup as
  // "no solver configured", contradicting `PlateSolveService.solveWithFallback`
  // which solves via astrometry.net when ASTAP is absent.
  // Loading/error -> null -> false.
  final plateSolverReady =
      ref.watch(plateSolverDetectionProvider).valueOrNull?.hasAnySolver ??
          false;

  // --- Dark library ---------------------------------------------------------
  // Coverage is satisfied once at least one master dark exists. The stats
  // provider re-runs whenever the library changes; loading/error -> false.
  final stats = ref.watch(darkLibraryStatsProvider).valueOrNull;
  final darkLibraryHasCoverage = stats != null && stats.masterCount > 0;

  // --- Focus state ----------------------------------------------------------
  // Focus is "known" only when the focuser is connected AND it reports a
  // current position. A connected focuser that has never reported a position
  // is treated as unknown (caution), never assumed in focus.
  final focuser = ref.watch(focuserStateProvider);
  final focusKnown =
      focuser.connectionState == DeviceConnectionState.connected &&
          focuser.position != null;

  return buildReadinessReport(
    cameraConnected: cameraConnected,
    mountConnected: mountConnected,
    hasProfile: hasProfile,
    locationSet: locationSet,
    outputPathSet: outputPathSet,
    plateSolverReady: plateSolverReady,
    darkLibraryHasCoverage: darkLibraryHasCoverage,
    focusKnown: focusKnown,
  );
});

/// Cheap selector for the top-line readiness level.
///
/// Watch this from chips/pills/badges that only need the traffic-light color
/// and label — it rebuilds only when the *overall* level changes, not on every
/// per-item detail tweak that leaves [ReadinessReport.overall] unchanged.
final readinessOverallProvider = Provider<ReadinessLevel>((ref) {
  return ref.watch(readinessReportProvider).overall;
});
