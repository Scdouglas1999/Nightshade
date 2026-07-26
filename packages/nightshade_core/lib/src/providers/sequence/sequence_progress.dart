import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/backend/event_types.dart';
import '../../models/sequence/instruction_progress_detail.dart';
import '../../models/sequence/sequence_models.dart';
import '../equipment/camera_state_provider.dart';

// =============================================================================
// EXECUTION STATE
// =============================================================================

/// Current sequence execution state
final sequenceExecutionStateProvider = StateProvider<SequenceExecutionState>((
  ref,
) {
  return SequenceExecutionState.idle;
});

/// True while a start or checkpoint-resume transaction is still being
/// admitted. During this window the execution state may legitimately remain
/// idle while settings and preflight validation are awaited, so backend swaps
/// must consult this latch as well as [sequenceExecutionStateProvider].
final sequenceLaunchInFlightProvider = StateProvider<bool>((ref) => false);

/// Current sequence progress
final sequenceProgressProvider =
    StateNotifierProvider<SequenceProgressNotifier, SequenceProgress>((ref) {
      return SequenceProgressNotifier();
    });

class SequenceProgressNotifier extends StateNotifier<SequenceProgress> {
  SequenceProgressNotifier() : super(const SequenceProgress());

  void updateState(SequenceExecutionState executionState) {
    state = state.copyWith(state: executionState);
  }

  // Phase 3 Step 2 — `updateProgress` keeps its caller-friendly "null
  // argument means leave alone" semantic without relying on the pre-freezed
  // `copyWith(x: x ?? this.x)` quirk. Freezed's generated copyWith treats
  // `null` differently per field-nullability: for non-null fields the
  // exposed type is non-null (a compile error if we pass `int?`); for
  // nullable fields `null` means "clear", not "omit". Both contradict the
  // historical `?? this.x` pattern this method has always implemented.
  //
  // We rebuild the next `SequenceProgress` explicitly: each non-null
  // method argument overrides the current field; `null` arguments fall
  // back to the existing value. This is independent of how `copyWith` is
  // implemented (Equatable today, freezed in Step 3) and preserves every
  // observable behaviour the current event pump relies on.
  void updateProgress({
    String? currentNodeId,
    String? currentNodeName,
    NodeStatus? currentNodeStatus,
    int? completedExposures,
    double? completedIntegrationSecs,
    double? elapsedSecs,
    double? estimatedRemainingSecs,
    String? currentTarget,
    String? currentFilter,
    String? message,
  }) {
    final current = state;
    state = SequenceProgress(
      state: current.state,
      currentNodeId: currentNodeId ?? current.currentNodeId,
      currentNodeName: currentNodeName ?? current.currentNodeName,
      currentNodeStatus: currentNodeStatus ?? current.currentNodeStatus,
      totalExposures: current.totalExposures,
      completedExposures: completedExposures ?? current.completedExposures,
      totalIntegrationSecs: current.totalIntegrationSecs,
      completedIntegrationSecs:
          completedIntegrationSecs ?? current.completedIntegrationSecs,
      elapsedSecs: elapsedSecs ?? current.elapsedSecs,
      estimatedRemainingSecs:
          estimatedRemainingSecs ?? current.estimatedRemainingSecs,
      currentTarget: currentTarget ?? current.currentTarget,
      currentFilter: currentFilter ?? current.currentFilter,
      message: message ?? current.message,
      nodeStatuses: current.nodeStatuses,
      nodeProgressPercent: current.nodeProgressPercent,
      nodeProgressDetail: current.nodeProgressDetail,
      nodeProgressStructuredDetail: current.nodeProgressStructuredDetail,
    );
  }

  void updateNodeStatus(String nodeId, NodeStatus status) {
    final newStatuses = Map<String, NodeStatus>.from(state.nodeStatuses);
    newStatuses[nodeId] = status;
    state = state.copyWith(nodeStatuses: newStatuses);
  }

  void updateNodeProgress(
    String nodeId,
    double progressPercent,
    String detail,
  ) {
    final newProgressPercent = Map<String, double>.from(
      state.nodeProgressPercent,
    );
    final newProgressDetail = Map<String, String>.from(
      state.nodeProgressDetail,
    );

    newProgressPercent[nodeId] = progressPercent;
    newProgressDetail[nodeId] = detail;

    state = state.copyWith(
      nodeProgressPercent: newProgressPercent,
      nodeProgressDetail: newProgressDetail,
    );
  }

  void updateNodeStructuredProgress(
    String nodeId,
    double progressPercent,
    InstructionProgressDetail detail,
  ) {
    final newProgressPercent = Map<String, double>.from(
      state.nodeProgressPercent,
    );
    final newStructuredDetail = Map<String, InstructionProgressDetail>.from(
      state.nodeProgressStructuredDetail,
    );

    newProgressPercent[nodeId] = progressPercent;
    newStructuredDetail[nodeId] = detail;

    state = state.copyWith(
      nodeProgressPercent: newProgressPercent,
      nodeProgressStructuredDetail: newStructuredDetail,
    );
  }

  /// Set the run's denominators. [totalIntegrationSecs] is optional: pass it
  /// only when a real value is known, otherwise the existing one is kept.
  ///
  /// The native `Progress` event carries a frame count but no integration
  /// total, and its handler used to pass a literal `0` — clobbering, roughly
  /// once a second, the real total [SequenceExecutor._acquireAndStartRun] had
  /// seeded from the sequence at start. Observed on the live rig: a
  /// `/api/run-watch/snapshot` reading
  /// `"totalIntegrationSecs": 0.0, "completedIntegrationSecs": 18.0` — a run
  /// that had done more integration than the zero it claimed to need.
  void setTotals(int totalExposures, [double? totalIntegrationSecs]) {
    state = state.copyWith(
      totalExposures: totalExposures,
      totalIntegrationSecs: totalIntegrationSecs ?? state.totalIntegrationSecs,
    );
  }

  /// Signature of the last `ExposureCompleted` already folded into
  /// [SequenceProgress.completedIntegrationSecs]. See
  /// [recordCompletedFrameIntegration].
  String? _lastIntegrationEventKey;

  /// Add one completed frame's shutter time to the run's integration total,
  /// exactly once per event.
  ///
  /// Two independent subscribers handle `ExposureCompleted` on a desktop host —
  /// the DeviceService-driven pump in this file and [SequenceExecutor]'s own
  /// handler — and BOTH were doing a read-modify-write
  /// (`completedIntegrationSecs + durationSecs`). The frame COUNT was already
  /// made idempotent (both writers assign the event's absolute frame index),
  /// but the integration total was not, so every frame was counted twice.
  ///
  /// Measured on the live rig: a run launch whose frames totalled 9.0 s of
  /// shutter time (a 1 s light, then 2x2 s + 1x4 s) reported
  /// `"completedIntegrationSecs": 18.0` in `/api/run-watch/snapshot` — exactly
  /// double, while the same run's `sequence_runs.stats_json` and the imaging
  /// session row both correctly recorded 8.0 s for the second run.
  ///
  /// [eventKey] must identify the originating event, not the frame: both
  /// subscribers receive the SAME event object, so its timestamp plus the frame
  /// index distinguishes "the other subscriber already handled this" from "a
  /// genuinely new frame".
  void recordCompletedFrameIntegration({
    required String eventKey,
    required double durationSecs,
  }) {
    if (_lastIntegrationEventKey == eventKey) return;
    _lastIntegrationEventKey = eventKey;
    state = state.copyWith(
      completedIntegrationSecs: state.completedIntegrationSecs + durationSecs,
    );
  }

  void reset() {
    _lastIntegrationEventKey = null;
    state = const SequenceProgress();
  }
}

typedef SequenceProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Apply a backend sequencer event to the sequence state providers.
///
/// This keeps sequencer-state ownership inside the sequence provider layer
/// instead of having hardware/device services write those providers directly.
void applySequencerEventToSequenceProviders(
  SequenceProviderReader read,
  NightshadeEvent event,
) {
  final progressNotifier = read(sequenceProgressProvider.notifier);
  final data = event.data;

  switch (event.eventType) {
    case 'SequenceStarted':
      final sequenceName = data['sequence_name'] as String? ?? 'Unknown';
      progressNotifier.updateState(SequenceExecutionState.running);
      progressNotifier.updateProgress(
        message: 'Started sequence: $sequenceName',
      );
      read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      break;

    case 'SequencePaused':
      progressNotifier.updateState(SequenceExecutionState.paused);
      read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.paused;
      break;

    case 'SequenceResumed':
      progressNotifier.updateState(SequenceExecutionState.running);
      read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      break;

    case 'SequenceStopped':
      progressNotifier.updateState(SequenceExecutionState.idle);
      read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.idle;
      break;

    case 'SequenceCompleted':
      progressNotifier.updateState(SequenceExecutionState.completed);
      read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.completed;
      break;

    case 'NodeStarted':
      final nodeId = data['node_id'] as String? ?? '';
      final nodeType = data['node_type'] as String? ?? '';
      progressNotifier.updateProgress(
        currentNodeId: nodeId,
        currentNodeName: nodeType,
        currentNodeStatus: NodeStatus.running,
      );
      progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
      break;

    case 'NodeCompleted':
      final nodeId = data['node_id'] as String? ?? '';
      final success = data['success'] as bool? ?? false;
      progressNotifier.updateNodeStatus(
        nodeId,
        success ? NodeStatus.success : NodeStatus.failure,
      );
      break;

    case 'Progress':
      final current = (data['current'] as num?)?.toInt() ?? 0;
      final total = (data['total'] as num?)?.toInt() ?? 0;
      progressNotifier.updateProgress(completedExposures: current);
      progressNotifier.setTotals(total);
      break;

    case 'TargetChanged':
      final targetName = data['target_name'] as String? ?? '';
      progressNotifier.updateProgress(currentTarget: targetName);
      break;

    case 'TargetCompleted':
      final targetName = data['target_name'] as String? ?? '';
      progressNotifier.updateProgress(message: 'Completed target: $targetName');
      break;

    case 'ExposureStarted':
      final frame = (data['frame'] as num?)?.toInt() ?? 0;
      final total = (data['total'] as num?)?.toInt() ?? 0;
      final filter = data['filter'] as String?;
      final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
      progressNotifier.updateProgress(
        currentFilter: filter,
        message:
            'Exposure $frame/$total - ${durationSecs}s${filter != null ? " ($filter)" : ""}',
      );
      // Reflect sequencer-driven exposures on the camera card. The manual
      // imaging path sets this directly, but a sequence exposes in Rust and
      // only surfaces via events, so the Equipment card showed "Idle" all run.
      read(cameraStateProvider.notifier).setExposing(true);
      break;

    case 'ExposureCompleted':
      final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
      final currentProgress = read(sequenceProgressProvider);
      // Use the event's ABSOLUTE frame index (matching the SequenceExecutor
      // event handler) rather than incrementing the current count. The two
      // subscribers (this one, driven by DeviceService, and the executor's
      // own handler) previously diverged: this path did current+1 while the
      // executor wrote the absolute frame, so when both were live for the
      // same run the count double-advanced. Reading the absolute frame makes
      // the two writers idempotent — whichever fires, the count lands on the
      // same value. `frame` is 1-based from the backend.
      final absoluteFrame =
          (data['frame'] as num?)?.toInt() ??
          currentProgress.completedExposures + 1;
      progressNotifier.updateProgress(completedExposures: absoluteFrame);
      progressNotifier.recordCompletedFrameIntegration(
        eventKey: '${event.timestamp}:$absoluteFrame',
        durationSecs: durationSecs,
      );
      // Exposure done — the camera is idle again during download/dither/slew.
      read(cameraStateProvider.notifier).setExposing(false);
      break;

    case 'Error':
      final message = data['message'] as String? ?? 'Unknown error';
      progressNotifier.updateProgress(message: 'Error: $message');
      break;
  }

  // Whenever the run leaves the exposing path (completed, stopped, failed, or
  // an error), make sure the camera card doesn't get stuck showing "Exposing".
  switch (event.eventType) {
    case 'SequenceCompleted':
    case 'SequenceStopped':
    case 'SequenceFailed':
    case 'SequenceCancelled':
    case 'Error':
      read(cameraStateProvider.notifier).setExposing(false);
      break;
  }
}
