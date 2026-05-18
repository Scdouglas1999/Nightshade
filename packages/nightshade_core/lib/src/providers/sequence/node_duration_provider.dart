import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sequence/sequence_models.dart';
import '../sequence_provider.dart' show currentSequenceProvider;

/// Per-node estimated *integration + overhead* roll-up.
///
/// The sequencer tree shows a "~2h 14m" hint next to container rows
/// (Loop, Target, Parallel, Sequential / generic container). This file
/// produces those rolled-up [Duration] values without recomputing the
/// whole tree on every widget rebuild.
///
/// Semantics by node type:
///
///   * [TargetHeaderNode]      — sum of children durations.
///   * [LoopNode] (count)      — sum(children) * repeatCount.
///   * [LoopNode] (untilTime)  — sum(children) * fittable_iterations
///                               (uses the [Sequence] estimator output).
///   * [LoopNode] (unbounded)  — single-iteration duration (best we can do
///                               without a future end-time anchor).
///   * [ParallelNode]          — max(children).
///   * [InstructionSetNode]    — sum(children).
///   * any other container     — sum(children).
///   * leaf [ExposureNode]     — totalDurationSecs + per-exposure download
///                               overhead.
///   * other leaves            — per-node overhead from [SequenceOverheadConfig].
///
/// Disabled nodes contribute 0 — matching the executor's behaviour and the
/// existing [Sequence.estimateWithOverhead] math.
///
/// Caching: returned as a [Provider.family] keyed by node ID. Riverpod
/// memoizes per-key and invalidates the whole family when
/// [currentSequenceProvider] changes (because we `ref.watch` it). That is
/// fine — we *want* a single mutation to clear every node's cached value;
/// stale roll-ups deeper in the tree would be a "silent fallback" bug.
final nodeRollupDurationProvider =
    Provider.family<Duration, String>((ref, nodeId) {
  final sequence = ref.watch(currentSequenceProvider);
  if (sequence == null) return Duration.zero;
  final secs = _rollupSecs(sequence, nodeId, const SequenceOverheadConfig());
  return Duration(seconds: secs.round());
});

/// Format helper used by the tree row + tests. Public so test code can
/// assert on the exact string the tree shows.
///
/// Output: "~2h 14m", "~14m 30s", "~30s", "<1s". Always prefixed with `~`
/// because these are estimates.
String formatRollupDuration(Duration d) {
  final totalSecs = d.inSeconds;
  if (totalSecs <= 0) return '<1s';
  final hours = totalSecs ~/ 3600;
  final minutes = (totalSecs % 3600) ~/ 60;
  final seconds = totalSecs % 60;
  if (hours > 0) {
    return '~${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '~${minutes}m ${seconds}s';
  }
  return '~${seconds}s';
}

/// Recursive walk that returns the rolled-up duration *in seconds* for
/// [nodeId] given the current [sequence] structure.
///
/// Kept separate from [Sequence.estimateWithOverhead] because that method
/// produces a single tree-wide [SequenceEstimate]; here we need per-node
/// values during a single render pass. We deliberately walk the same tree
/// shape so the numbers agree with the timeline / sequence header.
double _rollupSecs(
  Sequence sequence,
  String nodeId,
  SequenceOverheadConfig overhead,
) {
  final node = sequence.nodes[nodeId];
  if (node == null || !node.isEnabled) return 0;

  // Leaf: ExposureNode contributes integration + per-exposure download
  // overhead. All other leaf node-types contribute their per-instance
  // overhead. This matches [Sequence._nodeOverhead] + the executor.
  if (node is ExposureNode) {
    final integration = node.durationSecs * node.count;
    final download =
        overhead.downloadOverheadPerExposureSecs * node.count;
    return integration + download;
  }

  // Compute child rollups first; we use them for every container shape.
  final childSecs = <double>[];
  double childSum = 0;
  for (final childId in node.childIds) {
    final s = _rollupSecs(sequence, childId, overhead);
    childSecs.add(s);
    childSum += s;
  }
  final childMax = childSecs.isEmpty
      ? 0.0
      : childSecs.reduce((a, b) => a > b ? a : b);

  // Self overhead for non-exposure nodes that have a fixed time cost
  // (slew, autofocus, etc). For containers this is 0.
  final selfOverhead = _selfOverhead(node, overhead);

  if (node is LoopNode) {
    switch (node.conditionType) {
      case LoopConditionType.count:
        final iterations = node.repeatCount ?? 1;
        return selfOverhead + (childSum * iterations);
      case LoopConditionType.untilTime:
        // We don't have a reference time here; reuse the Sequence-level
        // estimator's logic to get fittable iterations. Falling back to
        // single-iteration when the deadline is in the past matches
        // _estimateNodeIntegration().
        if (node.repeatUntil != null && childSum > 0) {
          final availableSecs = node.repeatUntil!
              .difference(DateTime.now())
              .inSeconds
              .toDouble();
          if (availableSecs > 0) {
            final iters = (availableSecs / childSum).floor();
            return selfOverhead + (childSum * iters);
          }
        }
        return selfOverhead + childSum;
      case LoopConditionType.integrationTime:
        if (node.integrationTimeTarget != null &&
            node.integrationTimeTarget! > 0 &&
            childSum > 0) {
          // Find exposure-only time per iteration; mirrors
          // _estimateNodeIntegration so the math agrees.
          double exposurePerIteration = 0;
          for (final childId in node.childIds) {
            final c = sequence.nodes[childId];
            if (c is ExposureNode && c.isEnabled) {
              exposurePerIteration += c.totalDurationSecs;
            }
          }
          if (exposurePerIteration > 0) {
            final iters =
                (node.integrationTimeTarget! / exposurePerIteration).ceil();
            return selfOverhead + (childSum * iters);
          }
        }
        return selfOverhead + childSum;
      case LoopConditionType.forever:
      case LoopConditionType.whileDark:
      case LoopConditionType.untilAltitude:
      case LoopConditionType.altitudeAbove:
        // Unbounded: report a single iteration. Marking this as "~∞"
        // would be more honest but the tree row already shows the loop
        // condition; the duration column reads as per-iteration cost.
        return selfOverhead + childSum;
    }
  }

  if (node is ParallelNode) {
    // Children run concurrently. Wall-clock cost is the slowest child
    // (plus any self-overhead, though Parallel has none today).
    return selfOverhead + childMax;
  }

  // TargetHeaderNode, InstructionSetNode, ConditionalNode, RecoveryNode,
  // and any other container: sum.
  return selfOverhead + childSum;
}

/// Per-node fixed overhead (slew time, autofocus, etc). Mirrors
/// [Sequence._nodeOverhead] but kept private here to avoid widening
/// nightshade_core's public surface.
double _selfOverhead(SequenceNode node, SequenceOverheadConfig c) {
  if (node is SlewNode) return c.slewSecs;
  if (node is CenterNode) return c.centerTargetSecs;
  if (node is AutofocusNode) return c.autofocusSecs;
  if (node is FilterChangeNode) return c.filterChangeSecs;
  if (node is DitherNode) return c.ditherSecs;
  if (node is StartGuidingNode) return c.guideAcquireSecs;
  if (node is MeridianFlipNode) return c.meridianFlipSecs;
  if (node is CoolCameraNode) return c.coolingSecs;
  if (node is WarmCameraNode) return c.warmingSecs;
  if (node is OpenCoverNode || node is CloseCoverNode) {
    return c.coverMoveSecs;
  }
  return 0;
}
