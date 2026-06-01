import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/backend/event_types.dart';
import '../../models/sequence/instruction_progress_detail.dart';
import '../../models/sequence/sequence_models.dart';

// =============================================================================
// EXECUTION STATE
// =============================================================================

/// Current sequence execution state
final sequenceExecutionStateProvider =
    StateProvider<SequenceExecutionState>((ref) {
  return SequenceExecutionState.idle;
});

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
  // observable behaviour the current Wave-4/-7 event pump relies on.
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
      String nodeId, double progressPercent, String detail) {
    final newProgressPercent =
        Map<String, double>.from(state.nodeProgressPercent);
    final newProgressDetail =
        Map<String, String>.from(state.nodeProgressDetail);

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
    final newProgressPercent =
        Map<String, double>.from(state.nodeProgressPercent);
    final newStructuredDetail = Map<String, InstructionProgressDetail>.from(
        state.nodeProgressStructuredDetail);

    newProgressPercent[nodeId] = progressPercent;
    newStructuredDetail[nodeId] = detail;

    state = state.copyWith(
      nodeProgressPercent: newProgressPercent,
      nodeProgressStructuredDetail: newStructuredDetail,
    );
  }

  void setTotals(int totalExposures, double totalIntegrationSecs) {
    state = state.copyWith(
      totalExposures: totalExposures,
      totalIntegrationSecs: totalIntegrationSecs,
    );
  }

  void reset() {
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
      progressNotifier.setTotals(total, 0);
      break;

    case 'TargetChanged':
      final targetName = data['target_name'] as String? ?? '';
      progressNotifier.updateProgress(currentTarget: targetName);
      break;

    case 'TargetCompleted':
      final targetName = data['target_name'] as String? ?? '';
      progressNotifier.updateProgress(
        message: 'Completed target: $targetName',
      );
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
      break;

    case 'ExposureCompleted':
      final durationSecs = (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
      final currentProgress = read(sequenceProgressProvider);
      progressNotifier.updateProgress(
        completedExposures: currentProgress.completedExposures + 1,
        completedIntegrationSecs:
            currentProgress.completedIntegrationSecs + durationSecs,
      );
      break;

    case 'Error':
      final message = data['message'] as String? ?? 'Unknown error';
      progressNotifier.updateProgress(message: 'Error: $message');
      break;
  }
}
