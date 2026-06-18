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
///
/// Performance: the family reads its id out of [_nodeRollupMapProvider],
/// which computes the WHOLE tree's rollup in a single post-order DFS and
/// caches the result. Previously each family element re-walked the subtree
/// under its node, so painting an N-node tree (every row reads its own
/// element) was O(N^2) per edit — a deep loop-heavy sequence re-walked the
/// same exposure leaves once per ancestor. Now the map is built once per
/// sequence identity and every row is an O(1) map lookup.
final nodeRollupDurationProvider = Provider.family<Duration, String>((
  ref,
  nodeId,
) {
  final map = ref.watch(_nodeRollupMapProvider);
  return map[nodeId] ?? Duration.zero;
});

/// Single memoized post-order DFS over the current sequence producing every
/// node's rolled-up [Duration] in one pass. Each node is computed exactly
/// once and its child results are reused by its parent, so the whole map is
/// O(N) per edit instead of O(N) per node. Recomputes once whenever
/// [currentSequenceProvider] changes (sequence identity).
final _nodeRollupMapProvider = Provider<Map<String, Duration>>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  if (sequence == null) return const <String, Duration>{};
  const overhead = SequenceOverheadConfig();
  final secsById = <String, double>{};
  if (sequence.rootNodeId != null) {
    _computeRollupSecs(sequence, sequence.rootNodeId!, overhead, secsById);
  }
  // Compute any node not reached from the root (detached subtrees, or the
  // no-root case) so every tree row still gets its own value — matching the
  // pre-memoization behaviour where the family computed each id on demand.
  // Already-computed nodes short-circuit via the cache inside the walk.
  for (final id in sequence.nodes.keys) {
    if (!secsById.containsKey(id)) {
      _computeRollupSecs(sequence, id, overhead, secsById);
    }
  }
  return secsById.map(
    (id, secs) => MapEntry(id, Duration(seconds: secs.round())),
  );
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

/// Single memoizing post-order walk that returns the rolled-up duration *in
/// seconds* for [nodeId] AND records every node it visits into [out]. Each
/// node is computed once: the first time it is reached the result is stored
/// in [out]; subsequent reaches (shared ids are not expected in a tree, but
/// the guard makes the walk idempotent) reuse the cached value.
///
/// Kept separate from [Sequence.estimateWithOverhead] because that method
/// produces a single tree-wide [SequenceEstimate]; here we need per-node
/// values during a single render pass. We deliberately walk the same tree
/// shape so the numbers agree with the timeline / sequence header.
double _computeRollupSecs(
  Sequence sequence,
  String nodeId,
  SequenceOverheadConfig overhead,
  Map<String, double> out,
) {
  final cached = out[nodeId];
  if (cached != null) return cached;

  final node = sequence.nodes[nodeId];
  if (node == null || !node.isEnabled) {
    out[nodeId] = 0;
    return 0;
  }

  // Leaf: ExposureNode contributes integration + per-exposure download
  // overhead. All other leaf node-types contribute their per-instance
  // overhead. This matches [Sequence._nodeOverhead] + the executor.
  if (node is ExposureNode) {
    final integration = node.durationSecs * node.count;
    final download = overhead.downloadOverheadPerExposureSecs * node.count;
    final total = integration + download;
    out[nodeId] = total;
    return total;
  }

  // SmartExposure is a leaf that internally dispatches
  // per-filter batches. Integration time is the sum of plan integrations;
  // download overhead is one per planned frame. Filter-change and dither
  // overheads are intentionally NOT modeled here — `sequence_time_estimator`
  // has the rotation/batch-aware math and this provider rolls up totals
  // for the tree-row "Duration" column, where a slight under-estimate is
  // less misleading than double-counting overheads. When `rotateFilters`
  // is true and `integrationBudgetSecs > 0` we cap the integration at the
  // budget to match Rust runtime behaviour.
  if (node is SmartExposureNode) {
    var integration = 0.0;
    var frameCount = 0;
    for (final plan in node.plans) {
      integration += plan.integrationSecs;
      frameCount += plan.count;
    }
    if (node.integrationBudgetSecs > 0 &&
        integration > node.integrationBudgetSecs) {
      integration = node.integrationBudgetSecs;
    }
    final download = overhead.downloadOverheadPerExposureSecs * frameCount;
    final total = integration + download;
    out[nodeId] = total;
    return total;
  }

  // Compute child rollups first; we use them for every container shape.
  // Each child writes its own value into [out] as a side effect.
  final childSecs = <double>[];
  double childSum = 0;
  for (final childId in node.childIds) {
    final s = _computeRollupSecs(sequence, childId, overhead, out);
    childSecs.add(s);
    childSum += s;
  }
  final childMax = childSecs.isEmpty
      ? 0.0
      : childSecs.reduce((a, b) => a > b ? a : b);

  // Self overhead for non-exposure nodes that have a fixed time cost
  // (slew, autofocus, etc). For containers this is 0.
  final selfOverhead = _selfOverhead(node, overhead);

  final double result;
  if (node is LoopNode) {
    result = switch (node.conditionType) {
      LoopConditionType.count =>
        selfOverhead + (childSum * (node.repeatCount ?? 1)),
      // We don't have a reference time here; reuse the Sequence-level
      // estimator's logic to get fittable iterations. Falling back to
      // single-iteration when the deadline is in the past matches
      // _estimateNodeIntegration().
      LoopConditionType.untilTime => _untilTimeRollup(
        node,
        childSum,
        selfOverhead,
      ),
      LoopConditionType.integrationTime => _integrationTimeRollup(
        sequence,
        node,
        childSum,
        selfOverhead,
      ),
      // Unbounded: report a single iteration. Marking this as "~∞" would be
      // more honest but the tree row already shows the loop condition; the
      // duration column reads as per-iteration cost.
      LoopConditionType.forever ||
      LoopConditionType.whileDark ||
      LoopConditionType.untilAltitude ||
      LoopConditionType.altitudeAbove => selfOverhead + childSum,
    };
  } else if (node is ParallelNode) {
    // Children run concurrently. Wall-clock cost is the slowest child
    // (plus any self-overhead, though Parallel has none today).
    result = selfOverhead + childMax;
  } else {
    // TargetHeaderNode, InstructionSetNode, ConditionalNode, RecoveryNode,
    // and any other container: sum.
    result = selfOverhead + childSum;
  }

  out[nodeId] = result;
  return result;
}

/// untilTime loop rollup: fit as many child iterations as the deadline
/// allows (single iteration when the deadline is in the past / unset).
double _untilTimeRollup(LoopNode node, double childSum, double selfOverhead) {
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
}

/// integrationTime loop rollup: iterate until the target integration time is
/// met, mirroring `_estimateNodeIntegration` so the numbers agree.
double _integrationTimeRollup(
  Sequence sequence,
  LoopNode node,
  double childSum,
  double selfOverhead,
) {
  if (node.integrationTimeTarget != null &&
      node.integrationTimeTarget! > 0 &&
      childSum > 0) {
    double exposurePerIteration = 0;
    for (final childId in node.childIds) {
      final c = sequence.nodes[childId];
      if (c is ExposureNode && c.isEnabled) {
        exposurePerIteration += c.totalDurationSecs;
      }
    }
    if (exposurePerIteration > 0) {
      final iters = (node.integrationTimeTarget! / exposurePerIteration).ceil();
      return selfOverhead + (childSum * iters);
    }
  }
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
