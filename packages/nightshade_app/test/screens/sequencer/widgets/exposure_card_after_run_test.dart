// SEQ-18 / SEQ-19 — what the exposure node's card says once its frames are on
// disk, driven through the real SequenceTree rather than the panel widget.
//
// Wave D refuted the first SEQ-18 fix. That fix keyed "this node finished" off
// `nodeStatus == NodeStatus.success` and its test pumped exactly that, but in
// the running app the per-node progress entries are GONE by the time the
// operator reads the card: a 4x15s run whose Session Report said "Frames
// accepted 4/4" left the node reading "Exposure: No Filter - 0 / 4 frames"
// with four empty boxes above four R-labelled thumbnails, and a 12-frame run
// did the same. A run STOPPED at frame 1 still read "1 / 4", which is what
// made the zeroing look specific to the success path.
//
// So the counter-input these tests encode is the one the refuter observed: the
// card is still on screen (the panel deliberately persists for 20s after the
// node stops running) while the progress maps no longer hold anything for it.
//
// SEQ-19 is the same card's other half: the node carries no filter of its own,
// but the run imaged through R and said so everywhere else — telemetry strip,
// thumbnails, FITS filenames, session report — while this header alone said
// "No Filter", two rows under a target rollup reading "R 180s".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/mock_database.dart' show inMemoryDatabaseOverride;

/// The node under test: four 15s frames, no filter chosen in the builder.
ExposureNode _exposure() => ExposureNode(durationSecs: 15, count: 4);

Future<void> _pumpTree(
  WidgetTester tester,
  ProviderContainer container,
  SequenceNode node,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  container.read(currentSequenceProvider.notifier).createSequence(name: 'run');
  container.read(currentSequenceProvider.notifier).addNode(node);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: SequenceTree(colors: NightshadeColors.dark),
        ),
      ),
    ),
  );
  // liveValidationProvider debounces with a 500ms one-shot Timer on mutation.
  await tester.pump(const Duration(milliseconds: 600));
}

/// Drive the node through a complete four-frame run: running, frame 4 of 4
/// captured through filter R.
void _runAllFrames(ProviderContainer container, String nodeId) {
  final progress = container.read(sequenceProgressProvider.notifier);
  progress.updateNodeStatus(nodeId, NodeStatus.running);
  progress.updateProgress(currentFilter: 'R');
  progress.updateNodeStructuredProgress(
    nodeId,
    100,
    const ExposureInstructionProgressDetail(
        frame: 4, total: 4, durationSecs: 15),
  );
}

void main() {
  testWidgets(
    'the card keeps its frame count after the run clears the progress maps',
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node = _exposure();
      await _pumpTree(tester, container, node);
      _runAllFrames(container, node.id);
      await tester.pump();

      // Sanity: while the run is live the card reports the frame in flight.
      expect(find.text('4 / 4 frames'), findsOneWidget);

      // The success path: the run's per-node entries disappear while the card
      // is still on screen inside its 20s persistence window.
      container.read(sequenceProgressProvider.notifier).reset();
      await tester.pump();

      expect(
        find.text('0 / 4 frames'),
        findsNothing,
        reason: 'a node that captured every frame must not report zero',
      );
      expect(find.text('4 / 4 frames'), findsOneWidget);
    },
  );

  testWidgets(
    'the card names the filter the run used when the node names none',
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node = _exposure();
      expect(node.filter, isNull);

      await _pumpTree(tester, container, node);
      _runAllFrames(container, node.id);
      await tester.pump();

      expect(find.text('Exposure: No Filter'), findsNothing);
      expect(find.text('Exposure: R (current)'), findsOneWidget);
    },
  );

  testWidgets(
    'with no filter anywhere the card says the node has none set',
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node = _exposure();
      await _pumpTree(tester, container, node);
      final progress = container.read(sequenceProgressProvider.notifier);
      progress.updateNodeStatus(node.id, NodeStatus.running);
      progress.updateNodeStructuredProgress(
        node.id,
        25,
        const ExposureInstructionProgressDetail(
            frame: 1, total: 4, durationSecs: 15),
      );
      await tester.pump();

      expect(find.text('Exposure: No filter set'), findsOneWidget);
    },
  );

  testWidgets(
    "a node's own filter still wins over the run's",
    (tester) async {
      final container =
          ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
      addTearDown(container.dispose);

      final node = ExposureNode(durationSecs: 15, count: 4, filter: 'Ha');
      await _pumpTree(tester, container, node);
      _runAllFrames(container, node.id);
      await tester.pump();

      expect(find.text('Exposure: Ha'), findsOneWidget);
    },
  );
}
