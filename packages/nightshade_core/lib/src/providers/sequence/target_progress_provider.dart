import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sequence/sequence_models.dart';
import '../sequence_provider.dart'
    show currentSequenceProvider, sequenceProgressProvider;

/// Snapshot of execution progress *aggregated across a single
/// [TargetHeaderNode]*.
///
/// The tree shows a "8/24 frames • 32m / 96m" status under each target row
/// while a sequence is running. The math is non-trivial (walk the subtree
/// once, sum planned vs completed exposures) and is also used by the
/// target-card progress bar, so it lives in a derived provider that can be
/// watched in multiple places without recomputing per rebuild.
class TargetExecutionProgress {
  /// Planned exposure count under this target (sum of `ExposureNode.count`).
  final int totalFrames;

  /// Completed exposures attributed to this target.
  ///
  /// Comes from cross-referencing
  /// [SequenceProgress.completedExposures] against per-node statuses:
  /// every [ExposureNode] under this target that is `success` contributes
  /// its `count`; the currently-running exposure contributes the partial
  /// frame count derived from `nodeProgressPercent`.
  final int completedFrames;

  /// Planned integration time under this target, in seconds.
  final double totalIntegrationSecs;

  /// Completed integration time under this target, in seconds.
  /// Same accounting rule as [completedFrames] but in seconds.
  final double completedIntegrationSecs;

  const TargetExecutionProgress({
    required this.totalFrames,
    required this.completedFrames,
    required this.totalIntegrationSecs,
    required this.completedIntegrationSecs,
  });

  static const empty = TargetExecutionProgress(
    totalFrames: 0,
    completedFrames: 0,
    totalIntegrationSecs: 0,
    completedIntegrationSecs: 0,
  );

  /// Fraction of frames completed, in [0.0, 1.0]. Returns 0 when no frames
  /// are planned to avoid a divide-by-zero (the UI also hides the bar in
  /// that case).
  double get fraction {
    if (totalFrames <= 0) return 0;
    return (completedFrames / totalFrames).clamp(0.0, 1.0);
  }

  bool get hasPlannedFrames => totalFrames > 0;
}

/// Per-target progress, keyed by `TargetHeaderNode.id`.
///
/// Watches [currentSequenceProvider] (to know the planned shape) and
/// [sequenceProgressProvider] (to know what's been done). Returning the
/// empty snapshot when the target is missing keeps the call-site
/// branch-free.
final targetExecutionProgressProvider =
    Provider.family<TargetExecutionProgress, String>((ref, targetNodeId) {
  final sequence = ref.watch(currentSequenceProvider);
  final progress = ref.watch(sequenceProgressProvider);

  if (sequence == null) return TargetExecutionProgress.empty;
  final root = sequence.nodes[targetNodeId];
  if (root == null) return TargetExecutionProgress.empty;

  int totalFrames = 0;
  int completedFrames = 0;
  double totalIntegrationSecs = 0;
  double completedIntegrationSecs = 0;

  // Defense in depth against import-malformed trees that contain cycles.
  final visited = <String>{targetNodeId};

  void visit(SequenceNode node) {
    if (node is ExposureNode && node.isEnabled) {
      totalFrames += node.count;
      totalIntegrationSecs += node.totalDurationSecs;

      final status = progress.nodeStatuses[node.id];
      if (status == NodeStatus.success) {
        // Fully completed: every frame counts.
        completedFrames += node.count;
        completedIntegrationSecs += node.totalDurationSecs;
      } else if (status == NodeStatus.running) {
        // Partial: derive how many frames have finished within this node
        // from the per-node progress percent. The executor publishes
        // 0..100; clamp defensively because some backends round above
        // 100 on the final tick.
        final pct = (progress.nodeProgressPercent[node.id] ?? 0).clamp(0, 100);
        final partial = (node.count * pct / 100.0).floor();
        completedFrames += partial;
        completedIntegrationSecs += node.durationSecs * partial;
      }
      // pending / failure / skipped / cancelled contribute 0.
    }

    for (final childId in node.childIds) {
      if (!visited.add(childId)) continue;
      final child = sequence.nodes[childId];
      if (child == null) continue;
      visit(child);
    }
  }

  visit(root);

  return TargetExecutionProgress(
    totalFrames: totalFrames,
    completedFrames: completedFrames,
    totalIntegrationSecs: totalIntegrationSecs,
    completedIntegrationSecs: completedIntegrationSecs,
  );
});
