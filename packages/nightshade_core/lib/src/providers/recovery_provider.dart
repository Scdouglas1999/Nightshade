/// Wave 4 Recovery Mode â€” Riverpod providers for the recovery state machine.
///
/// Reads:
///   * the typed bridge event stream â€” `SequencerEvent_Recovery{Started,
///     Progress,Completed,GaveUp}` carry the full recovery context as
///     flat primitive fields. Wave 4 used a pre-FRB-regen workaround that
///     tunnelled the recovery context as JSON through the legacy
///     `InstructionProgress.detail` channel with a synthetic `_recovery`
///     node id; Wave 4.5's regen retires that hack.
///   * `sequenceProgressProvider` â€” used to derive the `isRecovering`
///     boolean even when the live recovery context hasn't arrived yet.
///
/// Exposes:
///   * `currentRecoveryProvider` â€” `RecoveryStatus?` for the dashboard
///     banner.
///   * `recoveryHistoryProvider` â€” list of every completed recovery loop in
///     the current run.
///   * `recoveryControlProvider` â€” command surface (try-now / abort).
///   * `recoveryAudibleBridgeProvider` â€” side-effect provider that plays
///     the platform alert sound on every recovery entry (gated by
///     `recoveryAudibleAlertWhenEntered`).
///   * `recoveryPushBridgeProvider` â€” side-effect provider that enqueues a
///     critical push notification on every recovery entry/exit (gated by
///     `pushCriticalAlerts`).
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_event;

import '../models/backend/event_types.dart' as core_events;
import '../models/sequencer/recovery_status.dart';
import '../models/sequence/sequence_models.dart';
import 'backend_provider.dart';
import 'critical_alert_provider.dart';
import 'event_provider.dart';
import 'push_notification_provider.dart';
import 'sequence_provider.dart';
import 'settings_provider.dart';

/// State of the current in-flight recovery loop. `null` whenever the
/// executor is not in `Recovering`.
class RecoveryNotifier extends StateNotifier<RecoveryStatus?> {
  RecoveryNotifier() : super(null);

  void update(RecoveryStatus? next) {
    if (!mounted) return;
    state = next;
  }

  void clear() {
    if (!mounted) return;
    state = null;
  }
}

final currentRecoveryProvider =
    StateNotifierProvider<RecoveryNotifier, RecoveryStatus?>(
        (ref) => RecoveryNotifier());

/// List of every completed recovery loop in the current run. The
/// post-session report dialog reads from this notifier.
class RecoveryHistoryNotifier
    extends StateNotifier<List<RecoveryHistoryEntry>> {
  RecoveryHistoryNotifier() : super(const []);

  void append(RecoveryHistoryEntry entry) {
    if (!mounted) return;
    state = [...state, entry];
  }

  void clearForNewRun() {
    if (!mounted) return;
    state = const [];
  }
}

final recoveryHistoryProvider =
    StateNotifierProvider<RecoveryHistoryNotifier, List<RecoveryHistoryEntry>>(
  (ref) => RecoveryHistoryNotifier(),
);

/// Convenience: whether the executor is currently in `Recovering`. Reads
/// `sequenceProgressProvider` so it never gets out of sync with the rest
/// of the dashboard's state machine.
final isRecoveringProvider = Provider<bool>((ref) {
  final progress = ref.watch(sequenceProgressProvider);
  return progress.state == SequenceExecutionState.recovering;
});

/// Operator command surface for the recovery banner. Delegates to the
/// backend so both FFI and network backends honour the same control path.
class RecoveryControl {
  final Ref _ref;
  RecoveryControl(this._ref);

  /// Request an immediate retry (skips the wait timer).
  Future<void> tryNow() async {
    final backend = _ref.read(sequencerBackendProvider);
    try {
      await backend.recoveryTryNow();
    } catch (e, st) {
      developer.log(
        'RecoveryControl.tryNow failed: $e',
        name: 'recovery_provider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Exit the recovery loop and transition the executor to `Failed`.
  Future<void> abort() async {
    final backend = _ref.read(sequencerBackendProvider);
    try {
      await backend.recoveryAbort();
    } catch (e, st) {
      developer.log(
        'RecoveryControl.abort failed: $e',
        name: 'recovery_provider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Skip the currently-failing node and resume the sequence past it.
  ///
  /// Implemented on top of the existing `sequencerSkip()` surface
  /// (`POST /api/sequencer/skip`); the executor's skip handler is
  /// recovery-aware â€” it clears the recovery loop and continues with the
  /// next sibling. Audit P1-8 â€” companion phones need a third option
  /// beyond Try Now / Abort: "the camera is wedged, but I want the rest
  /// of the run to keep going".
  Future<void> skipNode() async {
    final backend = _ref.read(sequencerBackendProvider);
    try {
      await backend.sequencerSkip();
    } catch (e, st) {
      developer.log(
        'RecoveryControl.skipNode failed: $e',
        name: 'recovery_provider',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }
}

final recoveryControlProvider = Provider<RecoveryControl>(
  (ref) => RecoveryControl(ref),
);

/// Bridge-event envelope built from a typed `SequencerEvent_Recovery*`
/// variant. Carries the rebuilt [RecoveryStatus] plus the discriminating
/// kind + abort flag. Wave 4.5 â€” the JSON-through-detail string parser is
/// gone; this comes straight from the FRB-typed payload.
enum RecoveryEventKind { started, progress, completed, gaveUp }

class RecoveryEventEnvelope {
  final RecoveryEventKind kind;
  final RecoveryStatus context;
  final bool? abortedByUser;

  const RecoveryEventEnvelope({
    required this.kind,
    required this.context,
    required this.abortedByUser,
  });
}

/// Side-effect provider: subscribes to [nightshadeEventsProvider] (typed
/// bridge events from local FRB or reconstructed from
/// [NetworkBackend.eventStream]) and forwards Recovery* events to
/// [currentRecoveryProvider] and [recoveryHistoryProvider]. Must be
/// `ref.watch`-ed somewhere in the widget tree (the Run Dashboard
/// scaffolding watches it).
final recoveryEventBridgeProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<bridge_event.NightshadeEvent>>(
    nightshadeEventsProvider,
    (previous, next) {
      next.when(
        data: (event) {
          final envelope = _recoveryEnvelopeFromBridge(event);
          if (envelope == null) return;
          _applyRecoveryEvent(ref, envelope);
        },
        loading: () {},
        error: (error, _) {
          developer.log(
            '[recoveryEventBridge] Event stream error: $error',
            name: 'recovery_provider',
            level: 1000,
          );
        },
      );
    },
    fireImmediately: true,
  );
});

/// Parses a [bridge_event.NightshadeEvent] into a typed
/// [RecoveryEventEnvelope] when the payload is one of the four
/// `SequencerEvent_Recovery*` variants. Returns `null` for anything else
/// so the caller can short-circuit.
RecoveryEventEnvelope? _recoveryEnvelopeFromBridge(
    bridge_event.NightshadeEvent event) {
  final payload = event.payload;
  if (payload is! bridge_event.EventPayload_Sequencer) return null;
  final inner = payload.field0;

  if (inner is bridge_event.SequencerEvent_RecoveryStarted) {
    return RecoveryEventEnvelope(
      kind: RecoveryEventKind.started,
      context: _recoveryStatusFromTypedStarted(inner),
      abortedByUser: null,
    );
  }
  if (inner is bridge_event.SequencerEvent_RecoveryProgress) {
    return RecoveryEventEnvelope(
      kind: RecoveryEventKind.progress,
      context: _recoveryStatusFromTypedProgress(inner),
      abortedByUser: null,
    );
  }
  if (inner is bridge_event.SequencerEvent_RecoveryCompleted) {
    return RecoveryEventEnvelope(
      kind: RecoveryEventKind.completed,
      context: _recoveryStatusFromTypedCompleted(inner),
      abortedByUser: null,
    );
  }
  if (inner is bridge_event.SequencerEvent_RecoveryGaveUp) {
    return RecoveryEventEnvelope(
      kind: RecoveryEventKind.gaveUp,
      context: _recoveryStatusFromTypedGaveUp(inner),
      abortedByUser: inner.abortedByUser,
    );
  }
  return null;
}

// ---------------------------------------------------------------------------
// Typed â†’ RecoveryStatus reconstruction helpers
// ---------------------------------------------------------------------------
//
// The four FRB variants carry identical-shaped payloads (flat primitives
// only â€” see `bridge/src/event.rs > SequencerEvent::Recovery*`). The Rust
// side denormalised the chrono-bearing `RecoveryContext` into ISO-8601
// strings + flat integers so we can rebuild a `RecoveryStatus` on the
// Dart side without bridging the Rust struct.

RecoveryStatus _recoveryStatusFromTypedStarted(
    bridge_event.SequencerEvent_RecoveryStarted ev) {
  return _rebuildRecoveryStatus(
    startedAtIso: ev.startedAtIso,
    causeKind: ev.causeKind,
    causeCustomLabel: ev.causeCustomLabel,
    lastAttemptAtIso: ev.lastAttemptAtIso,
    attemptCount: ev.attemptCount,
    maxAttempts: ev.maxAttempts,
    retryIntervalSecs: ev.retryIntervalSecs,
    maxDurationSecs: ev.maxDurationSecs,
    phase: ev.phase,
    lastError: ev.lastError,
  );
}

RecoveryStatus _recoveryStatusFromTypedProgress(
    bridge_event.SequencerEvent_RecoveryProgress ev) {
  return _rebuildRecoveryStatus(
    startedAtIso: ev.startedAtIso,
    causeKind: ev.causeKind,
    causeCustomLabel: ev.causeCustomLabel,
    lastAttemptAtIso: ev.lastAttemptAtIso,
    attemptCount: ev.attemptCount,
    maxAttempts: ev.maxAttempts,
    retryIntervalSecs: ev.retryIntervalSecs,
    maxDurationSecs: ev.maxDurationSecs,
    phase: ev.phase,
    lastError: ev.lastError,
  );
}

RecoveryStatus _recoveryStatusFromTypedCompleted(
    bridge_event.SequencerEvent_RecoveryCompleted ev) {
  return _rebuildRecoveryStatus(
    startedAtIso: ev.startedAtIso,
    causeKind: ev.causeKind,
    causeCustomLabel: ev.causeCustomLabel,
    lastAttemptAtIso: ev.lastAttemptAtIso,
    attemptCount: ev.attemptCount,
    maxAttempts: ev.maxAttempts,
    retryIntervalSecs: ev.retryIntervalSecs,
    maxDurationSecs: ev.maxDurationSecs,
    phase: ev.phase,
    lastError: ev.lastError,
  );
}

RecoveryStatus _recoveryStatusFromTypedGaveUp(
    bridge_event.SequencerEvent_RecoveryGaveUp ev) {
  return _rebuildRecoveryStatus(
    startedAtIso: ev.startedAtIso,
    causeKind: ev.causeKind,
    causeCustomLabel: ev.causeCustomLabel,
    lastAttemptAtIso: ev.lastAttemptAtIso,
    attemptCount: ev.attemptCount,
    maxAttempts: ev.maxAttempts,
    retryIntervalSecs: ev.retryIntervalSecs,
    maxDurationSecs: ev.maxDurationSecs,
    phase: ev.phase,
    lastError: ev.lastError,
  );
}

/// Shared rebuilder â€” keeps the typed â†’ status mapping in one place so a
/// schema bump touches a single function.
RecoveryStatus _rebuildRecoveryStatus({
  required String startedAtIso,
  required String causeKind,
  required String? causeCustomLabel,
  required String? lastAttemptAtIso,
  required int attemptCount,
  required int maxAttempts,
  required double retryIntervalSecs,
  required double maxDurationSecs,
  required String phase,
  required String? lastError,
}) {
  return RecoveryStatus(
    startedAt: DateTime.parse(startedAtIso),
    cause: _causeFromTyped(causeKind, causeCustomLabel),
    lastAttemptAt:
        lastAttemptAtIso == null ? null : DateTime.parse(lastAttemptAtIso),
    attemptCount: attemptCount,
    maxAttempts: maxAttempts,
    retryIntervalSecs: retryIntervalSecs,
    maxDurationSecs: maxDurationSecs,
    phase: _phaseFromTyped(phase),
    lastError: lastError,
  );
}

RecoveryCause _causeFromTyped(String kind, String? customLabel) {
  switch (kind) {
    case 'GuideStarLost':
      return RecoveryCause.guideStarLost();
    case 'SlewFailed':
      return RecoveryCause.slewFailed();
    case 'PlateSolveFailed':
      return RecoveryCause.plateSolveFailed();
    case 'WeatherUnsafe':
      return RecoveryCause.weatherUnsafe();
    case 'MountTrackingLost':
      return RecoveryCause.mountTrackingLost();
    case 'FocusDriftCritical':
      return RecoveryCause.focusDriftCritical();
    case 'ConsecutiveRejectsExceeded':
      return RecoveryCause.consecutiveRejectsExceeded();
    case 'DeviceDisconnected':
      return RecoveryCause.deviceDisconnected();
    case 'Custom':
      return RecoveryCause.custom(customLabel ?? '');
    default:
      // CLAUDE.md: "Errors are a feature." An unknown discriminant means
      // the Rust enum grew a variant and we didn't update the Dart
      // switch â€” surface it instead of silently falling back to a wrong
      // cause.
      throw FormatException(
          'Unknown RecoveryCause kind from typed bridge event: $kind');
  }
}

RecoveryPhase _phaseFromTyped(String phase) {
  switch (phase) {
    case 'Waiting':
      return RecoveryPhase.waiting;
    case 'Attempting':
      return RecoveryPhase.attempting;
    case 'Recovered':
      return RecoveryPhase.recovered;
    case 'GaveUp':
      return RecoveryPhase.gaveUp;
    default:
      throw FormatException(
          'Unknown RecoveryPhase wire value from typed bridge event: $phase');
  }
}

void _applyRecoveryEvent(Ref ref, RecoveryEventEnvelope envelope) {
  final currentNotifier = ref.read(currentRecoveryProvider.notifier);
  final historyNotifier = ref.read(recoveryHistoryProvider.notifier);
  final progressNotifier = ref.read(sequenceProgressProvider.notifier);

  switch (envelope.kind) {
    case RecoveryEventKind.started:
    case RecoveryEventKind.progress:
      currentNotifier.update(envelope.context);
      // Mirror the Rust ExecutorState transition into the Dart progress
      // notifier so the dashboard's other panels (status bar, mobile
      // playback bar, sequence progress card) react to recovery without
      // having to subscribe to currentRecoveryProvider individually.
      progressNotifier.updateState(SequenceExecutionState.recovering);
      break;
    case RecoveryEventKind.completed:
      currentNotifier.clear();
      historyNotifier.append(RecoveryHistoryEntry(
        startedAt: envelope.context.startedAt,
        endedAt: DateTime.now().toUtc(),
        cause: envelope.context.cause,
        attempts: envelope.context.attemptCount,
        recovered: true,
        abortedByUser: false,
        lastError: envelope.context.lastError,
      ));
      // Recovery succeeded â€” the Rust executor flips back to Running.
      // Mirror that on the Dart side so the LED returns to green.
      progressNotifier.updateState(SequenceExecutionState.running);
      break;
    case RecoveryEventKind.gaveUp:
      currentNotifier.clear();
      historyNotifier.append(RecoveryHistoryEntry(
        startedAt: envelope.context.startedAt,
        endedAt: DateTime.now().toUtc(),
        cause: envelope.context.cause,
        attempts: envelope.context.attemptCount,
        recovered: false,
        abortedByUser: envelope.abortedByUser ?? false,
        lastError: envelope.context.lastError,
      ));
      // Recovery exhausted â€” the Rust executor flips to Failed.
      progressNotifier.updateState(SequenceExecutionState.failed);
      break;
  }
}

/// Side-effect provider: plays the platform alert sound on every fresh
/// recovery entry. Gated by both [recoveryAudibleAlertWhenEntered] and
/// the global [audibleAlertsOnCritical] toggle.
final recoveryAudibleBridgeProvider = Provider<void>((ref) {
  ref.listen<RecoveryStatus?>(
    currentRecoveryProvider,
    (previous, next) {
      // Only ring on transition None -> Some (entry into a recovery).
      if (previous != null) return;
      if (next == null) return;
      final settings = ref.read(appSettingsProvider).valueOrNull;
      if (settings == null) return;
      if (!settings.recoveryAudibleAlertWhenEntered) return;
      if (!settings.audibleAlertsOnCritical) return;
      final player = ref.read(criticalAlertPlayerProvider);
      // Fire-and-forget; surface platform failures in developer.log.
      // ignore: discarded_futures
      player.play(sound: settings.criticalAlertSound).catchError((Object e) {
        developer.log('Recovery audible alert failed: $e',
            name: 'recovery_provider');
      });
    },
  );
});

/// Side-effect provider: forwards recovery entry events to paired mobile
/// clients via the push-notification service. Honours
/// [pushCriticalAlerts]; the per-event detail is the cause label.
final recoveryPushBridgeProvider = Provider<void>((ref) {
  ref.listen<RecoveryStatus?>(
    currentRecoveryProvider,
    (previous, next) {
      if (previous != null) return; // only on entry
      if (next == null) return;
      final settings = ref.read(appSettingsProvider).valueOrNull;
      if (settings == null) return;
      if (!settings.pushCriticalAlerts) return;
      final pushService = ref.read(pushNotificationServiceProvider);
      pushService.enqueueCriticalNotification(
        title: 'Recovering â€” ${next.cause.displayLabel}',
        body:
            'Sequence entered recovery mode. Attempt 1 of ${next.maxAttempts}.',
        eventType: 'recovery_started_${next.cause.wireKey}',
        category: core_events.EventCategory.sequencer,
      );
    },
  );
});

/// Visibility shim so widget tests can drive the bridge from a synthetic
/// event without reaching into the private helper. The shim is the same
/// function the production stream subscription calls â€” keeping the test
/// path on the production code path means the end-to-end recovery test
/// exercises the actual envelope-building logic.
@visibleForTesting
RecoveryEventEnvelope? recoveryEnvelopeFromBridgeForTest(
        bridge_event.NightshadeEvent event) =>
    _recoveryEnvelopeFromBridge(event);

/// Visibility shim: the test rig drives `_applyRecoveryEvent` directly
/// instead of routing through the stream subscription so it can fire a
/// synthetic envelope without depending on the backend mock surfacing it.
@visibleForTesting
void applyRecoveryEventForTest(Ref ref, RecoveryEventEnvelope envelope) =>
    _applyRecoveryEvent(ref, envelope);
