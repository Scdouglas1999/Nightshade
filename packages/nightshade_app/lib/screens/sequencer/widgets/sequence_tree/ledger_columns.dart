// The four right-aligned readout columns of a Ledger-mode tree row, and the
// node -> predicted-start-clock map they read their ETA from.
//
// Deliberately widget-free: the row paints what [ledgerColumnsFor] returns and
// decides nothing about the numbers, so the column semantics (which node type
// fills which column, and with what) are unit-testable in isolation.
//
// The values come from the models the rest of the sequencer already quotes —
// `plannedCaptureUnder` for frame totals, `nodeRollupDurationProvider` for the
// duration (passed in), and the pre-session simulation for the clock — so a
// ledger row cannot disagree with the target header card, the estimate chip or
// the pre-flight dialog about the same subtree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../plan_math.dart';
import '../visual_timeline.dart';

/// The text of one ledger row's four columns. An empty string means the column
/// is blank for this node — the ledger says nothing rather than inventing a
/// zero.
class LedgerColumns {
  /// **Filter / exp** — the capture spec, e.g. `Ha 300s`.
  final String filterExp;

  /// **Count** — frames this row will produce (its subtree, for a container).
  final String count;

  /// **Duration** — the row's rolled-up estimate, e.g. `~1h 4m`.
  final String duration;

  /// **ETA** — predicted start, local wall clock `HH:mm`.
  final String eta;

  const LedgerColumns({
    this.filterExp = '',
    this.count = '',
    this.duration = '',
    this.eta = '',
  });

  static const empty = LedgerColumns();

  /// The four values in column order. Used by the row to lay the cells out and
  /// to build its accessibility label.
  List<String> get values => <String>[filterExp, count, duration, eta];

  @override
  bool operator ==(Object other) =>
      other is LedgerColumns &&
      other.filterExp == filterExp &&
      other.count == count &&
      other.duration == duration &&
      other.eta == eta;

  @override
  int get hashCode => Object.hash(filterExp, count, duration, eta);

  @override
  String toString() =>
      'LedgerColumns(filterExp: "$filterExp", count: "$count", '
      'duration: "$duration", eta: "$eta")';
}

/// Build the column text for [node].
///
/// [rollup] is the node's rolled-up estimate from `nodeRollupDurationProvider`
/// and [eta] its predicted start from [ledgerEtaProvider]; both are passed in
/// rather than looked up so this stays a pure function of the sequence.
///
/// The dispatch is a deliberate `is`-chain rather than the exhaustive
/// `switch (node)` `nodeSummary` uses: a node type this function has never
/// heard of still has a name, a duration and a start time, so the honest
/// default (duration + ETA, no capture columns) is right for it. A new
/// instruction that captures frames adds a branch here; one that does not
/// needs no edit.
LedgerColumns ledgerColumnsFor(
  SequenceNode node,
  Sequence sequence, {
  required Duration rollup,
  DateTime? eta,
}) {
  final etaText = eta == null ? '' : formatLedgerClock(eta);
  // `<1s` is what `formatRollupDuration` returns for zero, which in a column
  // of estimates reads as a measurement rather than as "this step has no
  // length". A node with no duration leaves the column empty instead.
  final durationText =
      rollup.inSeconds <= 0 ? '' : formatRollupDuration(rollup);

  if (node is ExposureNode) {
    return LedgerColumns(
      filterExp: _filterExp(node.filter, node.durationSecs),
      count: '${node.count}',
      duration: durationText,
      eta: etaText,
    );
  }

  if (node is SciencePhotometryNode) {
    // A photometry burst runs the same TakeExposure pipeline, so it fills the
    // capture columns exactly as an exposure node does.
    return LedgerColumns(
      filterExp: _filterExp(node.filter, node.exposureSecs),
      count: '${node.count}',
      duration: durationText,
      eta: etaText,
    );
  }

  if (node is SmartExposureNode) {
    return LedgerColumns(
      filterExp: _smartFilters(node),
      count: _frameCount(plannedCaptureUnder(sequence, node.id)),
      duration: durationText,
      eta: etaText,
    );
  }

  if (node.childIds.isNotEmpty) {
    // A container: the Count column totals the subtree, and the Filter / exp
    // column stays blank — a container has no single capture spec, and the
    // filters it uses are named by its rollup summary when it is collapsed.
    return LedgerColumns(
      count: _frameCount(plannedCaptureUnder(sequence, node.id)),
      duration: durationText,
      eta: etaText,
    );
  }

  // Delay, Wait, Slew, Autofocus, Cool Camera, an empty container … anything
  // with a length but nothing to capture.
  return LedgerColumns(duration: durationText, eta: etaText);
}

/// `Ha 300s`, or `300s` for an unfiltered exposure.
String _filterExp(String? filter, double durationSecs) {
  final secs = _fmtSecs(durationSecs);
  if (filter == null || filter.isEmpty) return '${secs}s';
  return '$filter ${secs}s';
}

/// The filter names a SmartExposure rotates through, e.g. `L R G B`. A plan
/// with no name is identified by its 1-based wheel position, matching
/// `nodeSummary`'s treatment of the same field.
String _smartFilters(SmartExposureNode node) {
  if (node.plans.isEmpty) return '';
  return node.plans
      .map((plan) => plan.filterName.isEmpty
          ? '#${(plan.filterIndex ?? 0) + 1}'
          : plan.filterName)
      .join(' ');
}

/// The Count column for a planned capture.
///
/// A `+` suffix marks a figure that is a floor rather than the plan: under a
/// non-`count` loop the walk deliberately counts one pass (the rest of the app
/// says "per pass"), and an open-ended SmartExposure contributes no fixed
/// frames at all. An em dash is the honest answer when the only imager is
/// open-ended — there is no number to print, and `0` would be a lie.
String _frameCount(PlannedCapture planned) {
  if (planned.isEmpty) return '';
  if (planned.frames == 0) return '—';
  final floor = planned.hasUnboundedRepeat || planned.hasOpenEndedLoop;
  return floor ? '${planned.frames}+' : '${planned.frames}';
}

/// Drop a trailing `.0` so a whole number of seconds reads `300`, not `300.0`,
/// while a fractional exposure keeps its one decimal. Mirrors `node_summary`'s
/// `_fmtSecs` so the row and the summary line agree on `1.5s`.
String _fmtSecs(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// Format [time] as a local 24-hour `HH:mm` wall clock.
///
/// Hand-formatted rather than via `DateFormat` so the ETA column is the same
/// string in every locale the sequencer runs under — the column is 62 px wide
/// and a 12-hour `10:14 PM` does not fit it.
String formatLedgerClock(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Predicted start time per node id, derived from the pre-session simulation.
///
/// [PreSessionSimulationResult.segments] only carries the nodes the estimator
/// bills time to (`_processNode` emits an entry solely when the node's own
/// duration is non-zero), so a target header, a loop or an instruction set has
/// no segment of its own. Those take the earliest start in their subtree —
/// spec §2, "Container: ETA = subtree start".
///
/// A node the simulation cannot place is absent from the map, and its ETA
/// column stays blank. That is the case whenever there is no observer location
/// or the sequence has not been simulated at all.
Map<String, DateTime> ledgerNodeStarts(
  Sequence sequence,
  PreSessionSimulationResult? simulation,
) {
  if (simulation == null || simulation.segments.isEmpty) {
    return const <String, DateTime>{};
  }

  final starts = <String, DateTime>{};
  for (final segment in simulation.segments) {
    final existing = starts[segment.nodeId];
    if (existing == null || segment.start.isBefore(existing)) {
      starts[segment.nodeId] = segment.start;
    }
  }

  final visited = <String>{};
  final rootId = sequence.rootNodeId;
  if (rootId != null) {
    _foldSubtreeStart(sequence, rootId, starts, visited);
  }
  // Detached subtrees (a sequence with no root, or nodes the root does not
  // reach) still render rows, so they get their container starts folded too.
  for (final id in sequence.nodes.keys) {
    _foldSubtreeStart(sequence, id, starts, visited);
  }
  return Map<String, DateTime>.unmodifiable(starts);
}

/// Post-order walk: give every node with children the earliest start found
/// under it, and return that start so the parent can fold it in turn.
DateTime? _foldSubtreeStart(
  Sequence sequence,
  String nodeId,
  Map<String, DateTime> starts,
  Set<String> visited,
) {
  if (!visited.add(nodeId)) return starts[nodeId];
  final node = sequence.nodes[nodeId];
  if (node == null) return null;

  var earliest = starts[nodeId];
  for (final childId in node.childIds) {
    final childStart = _foldSubtreeStart(sequence, childId, starts, visited);
    if (childStart == null) continue;
    if (earliest == null || childStart.isBefore(earliest)) {
      earliest = childStart;
    }
  }
  if (earliest != null) starts[nodeId] = earliest;
  return earliest;
}

/// Predicted start clock time for every node the pre-session simulation can
/// place, keyed by node id.
///
/// A single map rather than a family: the simulation is one walk over the
/// whole sequence, so computing it per node would re-run it per row. Rows read
/// their own entry with `.select`, which keeps a row out of the rebuild when
/// another row's ETA is the only thing that moved.
final ledgerEtaProvider = Provider<Map<String, DateTime>>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  if (sequence == null) return const <String, DateTime>{};
  return ledgerNodeStarts(sequence, ref.watch(sequenceTimelineProvider));
});
