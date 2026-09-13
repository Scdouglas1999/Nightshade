// Inspector tabs (spec §8): the NodePropertiesPanel gains a
// Settings / Activity / Notes tab bar shared by the desktop sidebar and the
// mobile sheet, with the selection remembered per node CATEGORY.
//
// These tests assert the observable contract — the tab strip exists for leaf
// and container nodes, the validation banner stays pinned across tab
// switches, the Activity tab shows the seeded frame count, the Notes editor
// commits to SequenceNode.comment, and tab memory is per-category — rather
// than the private widget names inside the tab bodies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/node_activity_tab.dart';
import 'package:nightshade_app/screens/sequencer/widgets/node_progress_panels.dart';
import 'package:nightshade_app/screens/sequencer/widgets/node_properties_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HarnessHandle> pumpPanel(WidgetTester tester) => pumpAppScreen(
        tester,
        const SizedBox(
          width: 340,
          height: 800,
          child: NodePropertiesPanel(colors: NightshadeColors.dark),
        ),
        size: const Size(420, 900),
      );

  void loadAndSelect(
    HarnessHandle handle,
    Sequence sequence,
    String nodeId,
  ) {
    handle.container
        .read(currentSequenceProvider.notifier)
        .loadSequence(sequence, discardUnsaved: true);
    handle.container.read(selectedNodeIdProvider.notifier).state = nodeId;
  }

  Sequence singleNodeSequence(SequenceNode node) => Sequence.create(
        name: 'Tabs test',
        rootNodeId: node.id,
        nodes: {node.id: node},
      );

  testWidgets('tabs render for an exposure node', (tester) async {
    final handle = await pumpPanel(tester);
    final node = ExposureNode(name: 'Ha 300s', filter: 'Ha', count: 12);
    loadAndSelect(handle, singleNodeSequence(node), node.id);
    await tester.pump();

    expect(find.byType(AdaptiveTabBar), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.textContaining('Notes'), findsOneWidget);
    // The Settings tab is the default body: the node editor's Name field.
    expect(find.text('Name'), findsOneWidget);
    // Drain live validation's 500ms debounce before teardown.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tabs render for a target node', (tester) async {
    final handle = await pumpPanel(tester);
    final node = TargetHeaderNode(
      targetName: 'M42',
      raHours: 5.5,
      decDegrees: -5.4,
    );
    loadAndSelect(handle, singleNodeSequence(node), node.id);
    await tester.pump();

    expect(find.byType(AdaptiveTabBar), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.textContaining('Notes'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('switching tabs keeps the selected-node banner pinned',
      (tester) async {
    final handle = await pumpPanel(tester);
    // An unset target fires a real validation issue that names the node, so
    // the banner has something to show.
    final node = TargetHeaderNode(
      targetName: 'Unset target',
      raHours: 0,
      decDegrees: 0,
    );
    loadAndSelect(handle, singleNodeSequence(node), node.id);
    await tester.pump();
    // liveValidationProvider debounces 500 ms before issues land.
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(NightshadeBanner), findsOneWidget);

    await tester.tap(find.text('Activity'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(NightshadeBanner), findsOneWidget);

    await tester.tap(find.text('Notes'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(NightshadeBanner), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'Activity tab shows the frame grid with the seeded captured '
      'count', (tester) async {
    final handle = await pumpPanel(tester);
    final node = ExposureNode(
      name: 'L 60s',
      filter: 'L',
      count: 12,
      durationSecs: 60,
    );
    loadAndSelect(handle, singleNodeSequence(node), node.id);
    await tester.pump();

    handle.container
        .read(sequenceProgressProvider.notifier)
        .updateNodeStatus(node.id, NodeStatus.running);
    handle.container
        .read(nodeExposureTallyProvider.notifier)
        .recordFrames(node.id, captured: 6, planned: 12);

    await tester.tap(find.text('Activity'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('6 of 12 done · capturing 7'), findsOneWidget);
    expect(
      find.bySemanticsLabel('6 of 12 frames captured'),
      findsOneWidget,
    );
    // Total integration: 12 frames x 60s = 12m (compactTrimmed).
    expect(find.text('12m'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Notes edit commits to the node comment', (tester) async {
    final handle = await pumpPanel(tester);
    final node = ExposureNode(name: 'Ha 300s', count: 4);
    loadAndSelect(handle, singleNodeSequence(node), node.id);
    await tester.pump();

    await tester.tap(find.text('Notes'), warnIfMissed: false);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('node-comment-field')),
      'check flats at dawn',
    );
    // Focus loss commits: switching tabs drops the field's focus.
    await tester.tap(find.text('Settings'), warnIfMissed: false);
    await tester.pump();

    final updated =
        handle.container.read(currentSequenceProvider)!.nodes[node.id]!;
    expect(updated.comment, 'check flats at dawn');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tab memory is per node category across selection changes',
      (tester) async {
    final handle = await pumpPanel(tester);
    final expA = ExposureNode(name: 'Exp A', count: 2);
    final expB = ExposureNode(name: 'Exp B', count: 2);
    final target = TargetHeaderNode(
      targetName: 'M31',
      raHours: 0.7,
      decDegrees: 41.3,
    );
    final loop = LoopNode(name: 'Loop', repeatCount: 3);
    final root = InstructionSetNode(name: 'Root');
    final children = [expA.id, expB.id, target.id, loop.id];
    final sequence = Sequence.create(
      name: 'Memory test',
      rootNodeId: root.id,
      nodes: {
        root.id: root.copyWith(childIds: children),
        for (final node in [expA, expB, target, loop])
          node.id: node.copyWith(parentId: root.id),
      },
    );
    handle.container
        .read(currentSequenceProvider.notifier)
        .loadSequence(sequence, discardUnsaved: true);

    void select(String id) {
      handle.container.read(selectedNodeIdProvider.notifier).state = id;
    }

    select(expA.id);
    await tester.pump();
    // Settings is the default: the editor's Name field is present.
    expect(find.text('Name'), findsOneWidget);

    await tester.tap(find.text('Activity'), warnIfMissed: false);
    await tester.pump();
    // An unrun node's Activity body is the muted empty-state sentence.
    expect(
      find.text('Nothing has run for this node yet.'),
      findsOneWidget,
    );

    // Another node of the SAME category (instruction) restores Activity.
    select(expB.id);
    await tester.pump();
    expect(
      find.text('Nothing has run for this node yet.'),
      findsOneWidget,
      reason: 'same-category selection should keep the Activity tab',
    );
    expect(find.text('Name'), findsNothing);

    // A different category (target) has its own slot: Settings.
    select(target.id);
    await tester.pump();
    expect(find.text('Name'), findsOneWidget);

    // And logic is a third slot, also defaulting to Settings.
    select(loop.id);
    await tester.pump();
    expect(find.text('Name'), findsOneWidget);

    // Back to the instruction category — its Activity choice is remembered.
    select(expB.id);
    await tester.pump();
    expect(
      find.text('Nothing has run for this node yet.'),
      findsOneWidget,
      reason: 'the instruction category should restore Activity',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  group('subtreeActivityProgress', () {
    Sequence sequenceOf(
      SequenceNode root,
      Map<String, SequenceNode> descendants,
    ) =>
        Sequence.create(
          name: 'subtree test',
          rootNodeId: root.id,
          nodes: {root.id: root, ...descendants},
        );

    test('counts done frames from node statuses against the plan', () {
      final exp = ExposureNode(count: 4, durationSecs: 60);
      final target = TargetHeaderNode(
        targetName: 'M42',
        raHours: 5.5,
        decDegrees: -5.4,
        childIds: [exp.id],
      );
      final sequence = sequenceOf(target, {
        exp.id: exp.copyWith(parentId: target.id),
      });
      final stats = subtreeActivityProgress(
        sequence,
        SequenceProgress(nodeStatuses: {exp.id: NodeStatus.success}),
        const {},
        target.id,
      );

      expect(stats.plannedFrames, 4);
      expect(stats.doneFrames, 4);
      expect(stats.hasKnownCompletion, isTrue);
      expect(stats.ran, isTrue);
      expect(sequence.totalExposures, 4);
    });

    test('a running node contributes its tally as partial progress', () {
      final exp = ExposureNode(count: 10, durationSecs: 60);
      final target = TargetHeaderNode(
        targetName: 'M42',
        raHours: 5.5,
        decDegrees: -5.4,
        childIds: [exp.id],
      );
      final sequence = sequenceOf(target, {
        exp.id: exp.copyWith(parentId: target.id),
      });
      final stats = subtreeActivityProgress(
        sequence,
        SequenceProgress(nodeStatuses: {exp.id: NodeStatus.running}),
        {exp.id: const NodeExposureTally(captured: 3, planned: 10)},
        target.id,
      );
      expect(stats.plannedFrames, 10);
      expect(stats.doneFrames, 3);
      expect(stats.fraction, closeTo(0.3, 0.001));
    });

    test(
        'a count loop defers to the run-level counter when the subtree is '
        'the whole plan', () {
      final exp = ExposureNode(count: 4, durationSecs: 60);
      final loop = LoopNode(repeatCount: 10, childIds: [exp.id]);
      final sequence = sequenceOf(loop, {
        exp.id: exp.copyWith(parentId: loop.id),
      });
      // Per-node statuses cannot scale a 10-pass loop — but the loop IS the
      // whole plan, so the executor's absolute frame counter applies.
      final stats = subtreeActivityProgress(
        sequence,
        SequenceProgress(
          nodeStatuses: {exp.id: NodeStatus.running},
          completedExposures: 18,
        ),
        {exp.id: const NodeExposureTally(captured: 2, planned: 4)},
        loop.id,
      );
      expect(stats.plannedFrames, 40);
      expect(stats.doneFrames, 18);
      expect(stats.hasKnownCompletion, isTrue);
    });

    test('a repeat inside a partial plan stays completion-unknown', () {
      final inside = ExposureNode(count: 4, durationSecs: 60);
      final outside = ExposureNode(count: 4, durationSecs: 60);
      final loop = LoopNode(repeatCount: 10, childIds: [inside.id]);
      final target = TargetHeaderNode(
        targetName: 'M42',
        raHours: 5.5,
        decDegrees: -5.4,
        childIds: [loop.id],
      );
      final root = InstructionSetNode(name: 'Root');
      final sequence = Sequence.create(
        name: 'subtree test',
        rootNodeId: root.id,
        nodes: {
          root.id: root.copyWith(childIds: [target.id, outside.id]),
          target.id: target.copyWith(parentId: root.id),
          loop.id: loop.copyWith(parentId: target.id),
          inside.id: inside.copyWith(parentId: loop.id),
          outside.id: outside.copyWith(parentId: root.id),
        },
      );
      // The run's 18 frames cannot be attributed between the looped node and
      // the sibling exposure — the honest answer is "unknown".
      final stats = subtreeActivityProgress(
        sequence,
        SequenceProgress(
          nodeStatuses: {inside.id: NodeStatus.running},
          completedExposures: 18,
        ),
        const {},
        target.id,
      );
      expect(stats.plannedFrames, 40);
      expect(stats.hasKnownCompletion, isFalse);
    });
  });

  group('lastKnownNodeActivityProvider', () {
    test(
        'keeps last values through progress resets and clears on a fresh '
        'pass', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final progress = container.read(sequenceProgressProvider.notifier);

      // Read first so the notifier is alive while progress flows — the
      // inspector watches it, and a lazy read afterwards would only see the
      // post-reset empty maps.
      container.read(lastKnownNodeActivityProvider);

      progress.updateNodeStatus('n1', NodeStatus.running);
      progress.updateNodeProgress('n1', 50, 'Frame 2/4');
      progress.updateNodeStatus('n1', NodeStatus.success);
      // The success path empties the per-node maps; the snapshot must keep
      // the last true reading.
      progress.reset();

      var snapshot = container.read(lastKnownNodeActivityProvider)['n1'];
      expect(snapshot, isNotNull);
      expect(snapshot!.status, NodeStatus.success);
      expect(snapshot.detail, 'Frame 2/4');
      expect(snapshot.percent, 50);

      // A fresh pass drops the previous run's story entirely.
      progress.updateNodeStatus('n1', NodeStatus.running);
      snapshot = container.read(lastKnownNodeActivityProvider)['n1'];
      expect(snapshot!.status, NodeStatus.running);
      expect(snapshot.detail, isNull);
      expect(snapshot.percent, isNull);
    });
  });
}
