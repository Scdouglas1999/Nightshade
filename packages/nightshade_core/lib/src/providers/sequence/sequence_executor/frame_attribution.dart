import '../../../models/sequence/sequence_models.dart';

/// Which catalog target a graded frame belongs to and how long it was
/// actually exposed, derived from the producing node and the sequence tree.
///
/// This replaces the former frame-registration constants — `target_id=NULL`
/// and a hardcoded `exposureDuration: 1.0` — that quietly broke two things on
/// every imaging path:
///   * per-target integration-goal completion (the live scheduler counted
///     `WHERE target_id = ?`, always got 0, and imaged one target all night), and
///   * all integration-time accounting (every frame recorded as 1 second).
class FrameAttribution {
  /// DB `targets.id` of the enclosing [TargetHeaderNode], or `null` when the
  /// producing node has no target ancestor carrying a catalog id (e.g. an
  /// ad-hoc manual sequence). `null` is the honest result: no per-target
  /// goal tracking, rather than a wrong attribution.
  final int? targetId;

  /// Exposure length in seconds for this frame: the producing
  /// [ExposureNode]'s configured duration, or — for a [SmartExposureNode] —
  /// the duration of the per-filter plan matching the filter currently
  /// exposing. `null` when it cannot be determined (the caller should surface
  /// that rather than paper over it with a fabricated value).
  final double? exposureSecs;

  const FrameAttribution({this.targetId, this.exposureSecs});
}

/// Resolve the [FrameAttribution] for the frame produced by [nodeId] within
/// [sequence].
///
/// Walks the tree upward from the producing node through any intervening
/// containers (Loop / Sequential / Parallel) until it reaches the enclosing
/// [TargetHeaderNode], reading its [catalogTargetId]. The exposure length
/// comes from the producing [ExposureNode]'s configured duration.
///
/// Parent links are derived by inverting each node's `childIds` rather than
/// using `Sequence.parentOf` / `node.parentId`: scheduler-generated, in-memory
/// sequences (the path with the original `target_id=NULL` bug) populate
/// `childIds` but NOT `parentId`, so a `parentId`-based walk silently returns
/// null and never reaches the target. `childIds` is the model's documented
/// canonical source and is always present. A `visited` guard makes a malformed
/// (cyclic) tree terminate rather than spin.
FrameAttribution resolveFrameAttribution(
  Sequence sequence,
  String nodeId, {
  String? currentFilter,
}) {
  final producing = sequence.nodes[nodeId];
  double? exposureSecs;
  if (producing is ExposureNode) {
    exposureSecs = producing.durationSecs;
  } else if (producing is SmartExposureNode && currentFilter != null) {
    // SmartExposure rotates per-filter plans; the duration of THIS sub is the
    // plan whose filter is currently exposing. (For adaptive/variable cases
    // the fully authoritative per-frame value would have to come from the
    // executor event — tracked separately.)
    for (final plan in producing.plans) {
      if (plan.filterName.toLowerCase() == currentFilter.toLowerCase()) {
        exposureSecs = plan.durationSecs;
        break;
      }
    }
  }

  final parentByChild = <String, String>{};
  for (final node in sequence.nodes.values) {
    for (final childId in node.childIds) {
      parentByChild[childId] = node.id;
    }
  }

  int? targetId;
  String? cursor = nodeId;
  final visited = <String>{};
  while (cursor != null && visited.add(cursor)) {
    final node = sequence.nodes[cursor];
    if (node is TargetHeaderNode) {
      targetId = node.catalogTargetId;
      break;
    }
    cursor = parentByChild[cursor];
  }

  return FrameAttribution(targetId: targetId, exposureSecs: exposureSecs);
}
