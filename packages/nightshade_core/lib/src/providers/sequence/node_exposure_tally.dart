/// How many frames each exposure node has actually captured — the ONE channel
/// that only exposure-shaped progress can write.
///
/// SEQ-18, fifth look. The node card counted frames by parsing the node's
/// *display string* out of `SequenceProgress.nodeProgressDetail[nodeId]`. That
/// map is a single slot shared by every instruction that reports against the
/// node, and the native executor writes it several times per node from
/// different producers. The waveF log shows exactly how the count died, one
/// millisecond after a four-frame burst finished:
///
/// ```
/// 04:10:05.978257  NodeProgress node=7837c026… instruction=Exposure          progress=100%
/// 04:10:05.978300  NodeProgress node=7837c026… instruction=IntegrationBudget progress=0%
/// 04:10:05.978320  NodeProgress node=9617e5f0… instruction=AdaptiveExposure  progress=0%
/// ```
///
/// `emit_budget_progress` (native `node/instructions/expose.rs`) fires once per
/// successful burst, against the SAME node id, and overwrites both the string
/// detail and the structured detail with an `IntegrationBudget` payload that no
/// exposure parser can read. So the card fell back to frame 0 and printed
/// "0 / 4 frames" with four empty boxes — directly above the four thumbnails
/// the node had just captured. The next node opened with an `AdaptiveExposure`
/// payload at 0%, which reads back as exactly the same "0 / 4 frames", which is
/// why the card could not tell "captured everything" from "captured nothing".
///
/// Four fixes had already been aimed at the reader (the node's status, a 20 s
/// retention window, a second string wording). None of them could work: the
/// number was gone from the provider before any reader ran. This tally is a
/// separate slot, so an unrelated instruction reporting against the node can no
/// longer erase the frames it took.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/backend/event_types.dart';

/// Frames captured, and frames planned, for one exposure node's current pass.
class NodeExposureTally {
  /// Frames the executor has reported CAPTURED for this node.
  final int captured;

  /// Frames the node planned for this pass.
  final int planned;

  const NodeExposureTally({required this.captured, required this.planned});

  @override
  bool operator ==(Object other) =>
      other is NodeExposureTally &&
      other.captured == captured &&
      other.planned == planned;

  @override
  int get hashCode => Object.hash(captured, planned);

  @override
  String toString() => 'NodeExposureTally($captured/$planned)';
}

class NodeExposureTallyNotifier
    extends StateNotifier<Map<String, NodeExposureTally>> {
  NodeExposureTallyNotifier() : super(const {});

  /// A fresh pass over [nodeId] — a loop's next iteration, or a new run. The
  /// previous pass's frames are no longer this node's story, and leaving them
  /// would let a re-run open showing the frames of the run before it.
  void startNode(String nodeId) {
    if (!state.containsKey(nodeId)) return;
    final next = Map<String, NodeExposureTally>.from(state)..remove(nodeId);
    state = next;
  }

  /// True once a source that NAMES the node it is reporting for has been seen.
  ///
  /// `ExposureStarted` / `ExposureCompleted` carry no node id, so a subscriber
  /// can only attribute them to the run's *current* node — and at a burst
  /// boundary the current node has already advanced to the next one (the waveF
  /// log has `NodeStarted` for node 2 logged 53 µs BEFORE the final frame of
  /// node 1). Crediting node 2 with node 1's four frames is the
  /// join-by-position mistake with the node ids right there in the other
  /// event. So once a host proves it emits node-addressed exposure progress,
  /// the id-less fallback stops being used.
  bool _namedSourceSeen = false;

  /// Record that [nodeId] has captured [captured] of [planned] frames.
  ///
  /// Monotonic within a pass: two independent subscribers see every event on a
  /// desktop host (see `applySequencerEventToNodeExposureTally`), and an
  /// out-of-order or repeated sighting must never walk the count backwards.
  ///
  /// [named] is true when the EVENT named [nodeId]; false when [nodeId] is the
  /// run's current node, inferred for an event that carries none.
  void recordFrames(
    String nodeId, {
    required int captured,
    required int planned,
    bool named = true,
  }) {
    if (nodeId.isEmpty || captured < 0 || planned <= 0) return;
    if (named) {
      _namedSourceSeen = true;
    } else if (_namedSourceSeen) {
      return;
    }
    final current = state[nodeId];
    final nextCaptured = current == null
        ? captured
        : (captured > current.captured ? captured : current.captured);
    final nextPlanned = planned;
    if (current != null &&
        current.captured == nextCaptured &&
        current.planned == nextPlanned) {
      return;
    }
    state = Map<String, NodeExposureTally>.from(state)
      ..[nodeId] = NodeExposureTally(
        captured: nextCaptured,
        planned: nextPlanned,
      );
  }

  void reset() {
    _namedSourceSeen = false;
    if (state.isEmpty) return;
    state = const {};
  }
}

/// Per-node captured-frame tally, keyed by node id.
final nodeExposureTallyProvider =
    StateNotifierProvider<
      NodeExposureTallyNotifier,
      Map<String, NodeExposureTally>
    >((ref) => NodeExposureTallyNotifier());

/// Fold ONE sequencer event into the per-node exposure tally.
///
/// This is the whole write path. Both live subscribers on a desktop host call
/// it — `SequenceExecutor._handleSequencerEvent` and the DeviceService-driven
/// pump in `sequence_progress.dart` — and so do the widget tests, which replay
/// the waveF event sequence through this function rather than hand-rolling the
/// provider writes. A test therefore cannot pass against an event shape
/// production does not handle.
///
/// [currentNodeId] is the run's current node, used only for the two events that
/// carry no node id of their own (`ExposureStarted` / `ExposureCompleted`). The
/// structured `InstructionProgressStructured` event DOES carry one and is the
/// preferred source, because it stays correct across the node boundary where
/// `currentNodeId` has already advanced to the next node.
void applySequencerEventToNodeExposureTally(
  NodeExposureTallyNotifier tally,
  NightshadeEvent event, {
  String? currentNodeId,
}) {
  switch (event.eventType) {
    case 'NodeStarted':
      final nodeId =
          event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
      if (nodeId != null) tally.startNode(nodeId);
      break;

    case 'InstructionProgressStructured':
      if (event.data['detail_kind'] != 'Exposure') break;
      final named = event.data['node_id'] as String?;
      final nodeId = named ?? currentNodeId;
      if (nodeId == null) break;
      final json = event.data['detail_json'];
      final map = json is Map ? json : const {};
      final frame = _asInt(map['frame']) ?? _asInt(map['current_frame']);
      final total = _asInt(map['total']) ?? _asInt(map['total_frames']);
      if (frame == null || total == null) break;
      // The native per-frame callback fires AFTER a frame lands
      // (`instructions/expose.rs` calls it once `completed_exposures += 1`), so
      // `frame` here is the number of frames CAPTURED, not the one in flight.
      tally.recordFrames(
        nodeId,
        captured: frame,
        planned: total,
        named: named != null,
      );
      break;

    case 'ExposureCompleted':
      final named = event.data['node_id'] as String?;
      final nodeId = named ?? currentNodeId;
      if (nodeId == null) break;
      final frame = _asInt(event.data['frame']);
      final total = _asInt(event.data['total']);
      if (frame == null || total == null) break;
      tally.recordFrames(
        nodeId,
        captured: frame,
        planned: total,
        named: named != null,
      );
      break;
  }
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
