// SEQ-18, fifth look — the completed-node card, driven by the REAL event
// sequence the waveF run produced, through the REAL provider write path.
//
// The four earlier fixes all aimed at the reader: the node's status, a 20 s
// retention window, a second string wording, a structured-detail fallback.
// Every one of them passed its own test and changed nothing on screen, because
// the number was already gone from the provider before any reader ran.
//
// This test replays the events verbatim from
// /tmp/ns-audit/waveE-stop-pipeline/app.log (the waveF stop-pipeline drive),
// including the two that destroyed the count:
//
//   04:10:05.978189  Child 'Take Exposures' completed with status: Success
//   04:10:05.978204  NodeStarted            node=9617e5f0…   (the NEXT node)
//   04:10:05.978257  NodeProgress node=7837c026… instruction=Exposure          100%
//   04:10:05.978300  NodeProgress node=7837c026… instruction=IntegrationBudget   0%
//   04:10:05.978320  NodeProgress node=9617e5f0… instruction=AdaptiveExposure    0%
//
// The IntegrationBudget payload lands in the SAME per-node slot the exposure
// progress used, so node 1's card read "0 / 4 frames" with four empty boxes,
// and node 2 — which captured nothing — read the identical "0 / 4 frames".
//
// Note the NodeStarted for node 2 is logged 53 µs BEFORE node 1's final frame
// progress: any counter that attributes a frame to "the run's current node"
// credits node 2 with node 1's frames. That ordering is encoded below.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/mock_database.dart' show inMemoryDatabaseOverride;

/// One sequencer event, shaped exactly as the FFI bridge delivers it.
NightshadeEvent _seq(String type, Map<String, dynamic> data) => NightshadeEvent(
      timestamp: DateTime.now().microsecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.sequencer,
      eventType: type,
      data: data,
    );

NightshadeEvent _nodeStarted(String nodeId) =>
    _seq('NodeStarted', {'node_id': nodeId, 'node_type': 'Take Exposures'});

/// `SequencerEvent::InstructionProgressStructured` — what the bridge publishes
/// for every `ExecutorEvent::NodeProgress` that carries a structured detail.
NightshadeEvent _structured(
  String nodeId,
  String instruction,
  String detailKind,
  double percent,
  Map<String, dynamic> detailJson,
) =>
    _seq('InstructionProgressStructured', {
      'node_id': nodeId,
      'instruction': instruction,
      'progress_percent': percent,
      'detail_kind': detailKind,
      'detail_json': detailJson,
    });

NightshadeEvent _exposureProgress(String nodeId, int frame, int total) =>
    _structured(nodeId, 'Exposure', 'Exposure', frame / total * 100.0, {
      'frame': frame,
      'total': total,
      'duration_secs': 15.0,
    });

/// The event that erased the count: emitted once per successful burst by
/// `emit_budget_progress`, against the node that had just finished exposing.
NightshadeEvent _integrationBudget(String nodeId) =>
    _structured(nodeId, 'IntegrationBudget', 'IntegrationBudget', 0.0, {
      'target_id': 'target-1',
      'filter': '',
      'completed_secs': 0.0,
      'budget_secs': 0.0,
      'fraction': 0.0,
      'budget_met': false,
    });

/// The event that made the NEXT node read the same "0 / 4 frames".
NightshadeEvent _adaptiveExposure(String nodeId) =>
    _structured(nodeId, 'AdaptiveExposure', 'ExposureAdjusted', 0.0, {
      'nominal_secs': 15.0,
      'applied_secs': 15.0,
      'reason': 'disabled',
    });

/// Push one event through the SAME function production calls.
void _pump(ProviderContainer container, NightshadeEvent event) {
  applySequencerEventToNodeExposureTally(
    container.read(nodeExposureTallyProvider.notifier),
    event,
    currentNodeId: container.read(sequenceProgressProvider).currentNodeId,
  );
  applySequencerEventToSequenceProviders(container.read, event);
}

/// The waveF sequence shape: one Target holding two Take Exposures nodes.
Future<void> _pumpTree(
  WidgetTester tester,
  ProviderContainer container,
  List<SequenceNode> nodes,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  container.read(currentSequenceProvider.notifier).createSequence(name: 'run');
  final header =
      TargetHeaderNode(targetName: 'New Target', raHours: 3.0, decDegrees: 0.0);
  container.read(currentSequenceProvider.notifier).addNode(header);
  for (final node in nodes) {
    container
        .read(currentSequenceProvider.notifier)
        .addNode(node, parentId: header.id);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: SequenceTree(colors: NightshadeColors.dark)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets(
    'the waveF burst leaves the finished node reading 4 / 4, not 0 / 4',
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      // Only node 1 is in the tree, so `findsNothing` below is about THIS
      // card. The run's second Take Exposures node is still driven through the
      // events, because it is what erases node 1's count.
      final node1 = ExposureNode(durationSecs: 15, count: 4);
      const node2Id = '9617e5f0-ba43-466c-b83b-0bf6dedd6c86';
      await _pumpTree(tester, container, [node1]);

      // --- node 1 runs its four frames -----------------------------------
      _pump(container, _nodeStarted(node1.id));
      _pump(container, _adaptiveExposure(node1.id));
      for (var frame = 1; frame <= 4; frame++) {
        _pump(container, _exposureProgress(node1.id, frame, 4));
      }
      await tester.pump();
      expect(
        find.text('4 / 4 frames'),
        findsOneWidget,
        reason: 'the four frames the run captured must be on the card',
      );

      // --- the burst ends, in the order the log recorded ------------------
      _pump(container, _nodeStarted(node2Id));
      _pump(container, _exposureProgress(node1.id, 4, 4));
      _pump(container, _integrationBudget(node1.id));
      _pump(container, _adaptiveExposure(node2Id));
      _pump(
        container,
        _seq('NodeCompleted', {'node_id': node1.id, 'status': 'success'}),
      );
      await tester.pump();

      expect(
        find.text('0 / 4 frames'),
        findsNothing,
        reason: 'the node that captured four frames must not report zero — '
            'this is the assertion four previous fixes could not make hold',
      );
      expect(find.text('4 / 4 frames'), findsOneWidget);
    },
  );

  testWidgets(
    'a node that captured nothing still reads 0 / 4 beside one that captured everything',
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node1 = ExposureNode(durationSecs: 15, count: 4);
      final node2 = ExposureNode(durationSecs: 15, count: 4);
      await _pumpTree(tester, container, [node1, node2]);

      _pump(container, _nodeStarted(node1.id));
      for (var frame = 1; frame <= 4; frame++) {
        _pump(container, _exposureProgress(node1.id, frame, 4));
      }
      _pump(container, _nodeStarted(node2.id));
      _pump(container, _integrationBudget(node1.id));
      _pump(container, _adaptiveExposure(node2.id));
      await tester.pump();

      // The whole point of the counter: the two nodes must not read the same.
      expect(find.text('4 / 4 frames'), findsOneWidget);
      expect(find.text('0 / 4 frames'), findsOneWidget);
    },
  );

  testWidgets(
    "node 2's opening progress cannot claim node 1's frames",
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node1 = ExposureNode(durationSecs: 15, count: 4);
      final node2 = ExposureNode(durationSecs: 15, count: 4);
      await _pumpTree(tester, container, [node1, node2]);

      _pump(container, _nodeStarted(node1.id));
      for (var frame = 1; frame <= 3; frame++) {
        _pump(container, _exposureProgress(node1.id, frame, 4));
      }
      // The log's ordering: node 2 is already "current" when node 1's last
      // frame is reported. An id-less ExposureCompleted would land on node 2.
      _pump(container, _nodeStarted(node2.id));
      _pump(container, _exposureProgress(node1.id, 4, 4));
      _pump(container, _seq('ExposureCompleted', {'frame': 4, 'total': 4}));
      await tester.pump();

      final tally = container.read(nodeExposureTallyProvider);
      expect(tally[node1.id]?.captured, 4);
      expect(
        tally[node2.id],
        isNull,
        reason: 'node 2 exposed nothing; crediting it from the run\'s '
            '"current node" is the join-by-position mistake',
      );
    },
  );
}
