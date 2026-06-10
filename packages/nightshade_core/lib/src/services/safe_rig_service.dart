import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;

import '../backend/nightshade_backend.dart';
import '../backend/network_backend.dart';
import '../models/equipment/equipment_models.dart';
import '../providers/backend_provider.dart';
import '../providers/equipment/cover_calibrator_state_provider.dart';
import '../providers/equipment/dome_state_provider.dart';
import '../providers/equipment/mount_state_provider.dart';
import '../providers/ui_notification_provider.dart';

/// Outcome of a single [SafeRigService.safeTheRig] invocation.
///
/// Every step that was *attempted* is recorded so callers (and tests) can see
/// exactly what the safe-the-rig action did. [failures] is non-empty when one
/// or more attempted steps threw; in that case [SafeRigService.safeTheRig]
/// also throws a [SafeRigException] AFTER attempting every remaining step —
/// safing the rig must never short-circuit (a dome-close failure must not skip
/// the mount park, and vice-versa). Errors are a feature: they surface loudly
/// via the critical notification and the thrown exception.
@immutable
class SafeRigResult {
  /// True when the running sequence was paused (it was running and the
  /// pause call succeeded).
  final bool sequencePaused;

  /// True when the mount park command was issued successfully.
  final bool mountParked;

  /// True when the mount was already parked (or no mount connected) so no
  /// park command was needed.
  final bool mountAlreadySafe;

  /// True when the dome shutter close command was issued successfully.
  final bool domeClosed;

  /// True when the cover close command was issued successfully.
  final bool coverClosed;

  /// Per-step failures, keyed by step name (`pause`, `park`, `dome`,
  /// `cover`). Empty on full success.
  final Map<String, Object> failures;

  const SafeRigResult({
    this.sequencePaused = false,
    this.mountParked = false,
    this.mountAlreadySafe = false,
    this.domeClosed = false,
    this.coverClosed = false,
    this.failures = const {},
  });

  bool get hasFailures => failures.isNotEmpty;

  SafeRigResult copyWith({
    bool? sequencePaused,
    bool? mountParked,
    bool? mountAlreadySafe,
    bool? domeClosed,
    bool? coverClosed,
    Map<String, Object>? failures,
  }) {
    return SafeRigResult(
      sequencePaused: sequencePaused ?? this.sequencePaused,
      mountParked: mountParked ?? this.mountParked,
      mountAlreadySafe: mountAlreadySafe ?? this.mountAlreadySafe,
      domeClosed: domeClosed ?? this.domeClosed,
      coverClosed: coverClosed ?? this.coverClosed,
      failures: failures ?? this.failures,
    );
  }
}

/// Thrown when one or more safe-the-rig steps failed. Carries the partial
/// [result] so callers can still see what succeeded.
class SafeRigException implements Exception {
  final SafeRigResult result;
  final String reason;

  SafeRigException(this.reason, this.result);

  @override
  String toString() {
    final failed = result.failures.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('; ');
    return 'SafeRigException(reason="$reason", failures=[$failed])';
  }
}

/// Shared, reliable "safe the rig" action used by every unattended-night
/// safety path that must put the hardware into a non-imaging, non-tracking,
/// weather-protected state.
///
/// Why this exists: three independent P0 paths — weather-safety enforcement,
/// the low-disk watchdog, and end-of-night handling — each need the same
/// missing capability: pause the running sequence (preserving its
/// checkpoint), park the mount so it stops tracking into the ground/clouds,
/// and optionally close the dome shutter and cover. Before this service the
/// weather path *computed* the actions but never executed them, and the
/// low-disk watchdog only paused (leaving the mount tracking with the night
/// dead and unattended). Centralising the action means there is one
/// fail-closed, loudly-erroring implementation instead of three divergent
/// half-implementations.
///
/// Ordering rationale:
///   1. Pause the sequence FIRST so no new exposure / slew is issued while we
///      park (best-effort: if there is no running sequence, this is a no-op).
///   2. Park the mount — the safety-critical step. Stops tracking; on most
///      mounts also slews to a safe stow position.
///   3. Close the dome shutter, then the cover — physical weather protection.
///
/// Every requested step is attempted even if an earlier one throws; the
/// aggregated failures are surfaced via a CRITICAL notification and a thrown
/// [SafeRigException]. Device ids are resolved from the live equipment state
/// providers exactly as [_autoResumeAfterWeatherClear] resolves the mount.
class SafeRigService {
  final Ref _ref;

  SafeRigService(this._ref);

  /// Safe the rig.
  ///
  /// [reason] is the human-readable trigger ("Weather turned unsafe",
  /// "Disk space critically low", …) used in the critical notification.
  ///
  /// [park] / [closeDome] / [closeCover] gate the optional physical-protection
  /// steps; the sequence pause always runs (it is the cheapest, safest first
  /// move). When [park] is true but no mount is connected, or the mount is
  /// already parked, the park step is skipped and recorded as
  /// [SafeRigResult.mountAlreadySafe] — that is success, not a failure.
  ///
  /// [notify] controls whether the CRITICAL UI notification is posted (default
  /// true). Callers that emit their own richer notification can disable it.
  ///
  /// Throws [SafeRigException] if any attempted step failed (after attempting
  /// all of them).
  Future<SafeRigResult> safeTheRig({
    required String reason,
    bool park = true,
    bool closeDome = false,
    bool closeCover = false,
    bool notify = true,
  }) async {
    final backend = _ref.read(backendProvider);
    final failures = <String, Object>{};
    var result = const SafeRigResult();

    // 1. Pause the running sequence so no further exposure/slew is dispatched
    //    while we park. Pause preserves the checkpoint (unlike stop), so the
    //    night can resume once conditions allow.
    try {
      await backend.sequencerPause();
      result = result.copyWith(sequencePaused: true);
    } catch (e) {
      failures['pause'] = e;
    }

    // 2. Park the mount (the safety-critical step).
    if (park) {
      final mount = _ref.read(mountStateProvider);
      final connected =
          mount.connectionState == DeviceConnectionState.connected &&
          mount.deviceId != null &&
          mount.deviceId!.isNotEmpty;
      if (!connected) {
        // No mount to park — nothing tracking under our control.
        result = result.copyWith(mountAlreadySafe: true);
      } else if (mount.isParked) {
        // Already parked — already safe.
        result = result.copyWith(mountAlreadySafe: true);
      } else {
        try {
          await backend.mountPark(mount.deviceId!);
          _ref.read(mountStateProvider.notifier).setParked(true);
          _ref.read(mountStateProvider.notifier).setTracking(false);
          result = result.copyWith(mountParked: true);
        } catch (e) {
          failures['park'] = e;
        }
      }
    }

    // 3. Close the dome shutter (physical weather protection).
    if (closeDome) {
      final dome = _ref.read(domeStateProvider);
      final connected =
          dome.connectionState == DeviceConnectionState.connected &&
          dome.deviceId != null &&
          dome.deviceId!.isNotEmpty;
      final alreadyClosed =
          dome.shutterStatus == ShutterStatus.closed ||
          dome.shutterStatus == ShutterStatus.closing;
      if (connected && !alreadyClosed) {
        try {
          await closeDomeShutter(backend, dome.deviceId!);
          result = result.copyWith(domeClosed: true);
        } catch (e) {
          failures['dome'] = e;
        }
      }
    }

    // 4. Close the cover (physical weather protection).
    if (closeCover) {
      final cover = _ref.read(coverCalibratorStateProvider);
      final connected =
          cover.connectionState == DeviceConnectionState.connected &&
          cover.deviceId != null &&
          cover.deviceId!.isNotEmpty;
      if (connected && cover.hasCover && !cover.isCoverClosed) {
        try {
          await closeCalibratorCover(backend, cover.deviceId!);
          result = result.copyWith(coverClosed: true);
        } catch (e) {
          failures['cover'] = e;
        }
      }
    }

    result = result.copyWith(failures: Map.unmodifiable(failures));

    if (notify) {
      _emitNotification(reason, result);
    }

    if (result.hasFailures) {
      throw SafeRigException(reason, result);
    }
    return result;
  }

  /// Issue the dome-shutter close command against [deviceId].
  ///
  /// Routed through the active backend: a [NetworkBackend] forwards to the
  /// imaging host's `dome/close` endpoint; the local FFI backend calls the
  /// Rust bridge directly (the dome/cover close operations are not part of the
  /// role interface, so this mirrors the established `command_handlers.dart`
  /// dispatch). `@visibleForTesting` so unit tests can record the call without
  /// a live bridge.
  @visibleForTesting
  Future<void> closeDomeShutter(NightshadeBackend backend, String deviceId) {
    if (backend is NetworkBackend) {
      return backend.domeClose();
    }
    return bridge_api.apiDomeCloseShutter(deviceId: deviceId);
  }

  /// Issue the cover close command against [deviceId]. See [closeDomeShutter].
  @visibleForTesting
  Future<void> closeCalibratorCover(
    NightshadeBackend backend,
    String deviceId,
  ) {
    if (backend is NetworkBackend) {
      return backend.coverClose();
    }
    return bridge_api.apiCoverCalibratorCloseCover(deviceId: deviceId);
  }

  void _emitNotification(String reason, SafeRigResult result) {
    final notifier = _ref.read(uiNotificationProvider.notifier);
    if (result.hasFailures) {
      final failed = result.failures.keys.join(', ');
      notifier.showError(
        'CRITICAL: $reason. Safe-the-rig partially FAILED ($failed). '
        'Operator intervention required.',
        title: 'Safe the rig',
        duration: const Duration(seconds: 20),
      );
      return;
    }

    final steps = <String>[];
    if (result.sequencePaused) steps.add('sequence paused');
    if (result.mountParked) steps.add('mount parked');
    if (result.mountAlreadySafe && !result.mountParked) {
      steps.add('mount already safe');
    }
    if (result.domeClosed) steps.add('dome closed');
    if (result.coverClosed) steps.add('cover closed');
    final detail = steps.isEmpty ? 'no action needed' : steps.join(', ');
    notifier.showError(
      'CRITICAL: $reason. Rig safed: $detail.',
      title: 'Safe the rig',
      duration: const Duration(seconds: 16),
    );
  }
}

/// Provider for the shared safe-the-rig action.
final safeRigServiceProvider = Provider<SafeRigService>((ref) {
  return SafeRigService(ref);
});
