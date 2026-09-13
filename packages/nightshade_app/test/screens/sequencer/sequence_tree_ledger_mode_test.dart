// Ledger-mode coverage for SequenceTree: the fixed-height row geometry, the
// four readout columns, collapsed-container rollup text, chevron-driven
// collapse, selection / multi-select / context menu, and a palette drop into a
// container — all with the tree's real gesture wiring rather than synthesized
// callbacks.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree_shortcuts.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequencer_density.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

/// Test-only bridge so a single test can flip the tree between densities and
/// exercise the AnimatedSwitcher without rebuilding the ProviderScope.
final _testDensityProvider =
    StateProvider<SequencerDensity>((ref) => SequencerDensity.ledger);

/// Root -> TargetHeader "M 42" -> Loop "Broadband" -> exposures. The smallest
/// three-level shape that exercises the container column totals, the target's
/// ledger-row form and the collapsed rollup line.
({
  Sequence sequence,
  String loopId,
  List<String> exposureIds,
}) _threeLevelSequence(List<ExposureNode> exposures) {
  final target = TargetHeaderNode(
    name: 'M 42',
    targetName: 'Orion',
    raHours: 5.5,
    decDegrees: -5.4,
  );
  final loop = LoopNode(
    name: 'Broadband',
    conditionType: LoopConditionType.count,
    repeatCount: 1,
  );
  final root = InstructionSetNode(name: 'Root');
  final placed = <ExposureNode>[
    for (var i = 0; i < exposures.length; i++)
      exposures[i].copyWith(parentId: loop.id, orderIndex: i),
  ];
  return (
    sequence: Sequence.create(
      name: 'T',
      rootNodeId: root.id,
      nodes: {
        for (final child in placed) child.id: child,
        loop.id: loop.copyWith(
          parentId: target.id,
          orderIndex: 0,
          childIds: [for (final child in placed) child.id],
        ),
        target.id: target.copyWith(
          parentId: root.id,
          orderIndex: 0,
          childIds: [loop.id],
        ),
        root.id: root.copyWith(childIds: [target.id]),
      },
    ),
    loopId: loop.id,
    exposureIds: [for (final child in placed) child.id],
  );
}

Future<HarnessHandle> _pumpTree(
  WidgetTester tester,
  Sequence sequence,
) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = sequence;

  final handle = await pumpAppScreen(
    tester,
    Builder(
      builder: (context) => SequenceTree(colors: NightshadeColors.of(context)),
    ),
    size: const Size(1200, 900),
    // Live validation debounces 500 ms; drain frames manually instead.
    settle: false,
    extraOverrides: [
      currentSequenceProvider.overrideWith((_) => notifier),
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.idle),
      sequencerDensityProvider
          .overrideWith((ref) => ref.watch(_testDensityProvider)),
    ],
  );
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull);
  return handle;
}

/// Live validation runs on a 500 ms debounce; without a drain the binding
/// fails the test on a pending timer at teardown.
Future<void> _drainValidationDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
}

/// The 28 px row box is the innermost SizedBox ancestor of a row's name text
/// that pins only its height — the chevron / marker / action boxes all carry a
/// width, so this predicate singles out the row shell.
Finder _rowShellOf(Finder nameText) => find.ancestor(
      of: nameText,
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 28.0 && w.width == null,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders ledger rows at 28 px with columns and a header',
      (tester) async {
    final built = _threeLevelSequence([
      ExposureNode(
        name: 'L subs',
        filter: 'L',
        durationSecs: 60,
        count: 10,
      ),
    ]);
    await _pumpTree(tester, built.sequence);

    // Column header appears once, above the rows.
    expect(find.text('Step'), findsOneWidget);
    expect(find.text('Filter / exp'), findsOneWidget);
    expect(find.text('Count'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('ETA'), findsOneWidget);

    // Row shell pins to the ledger height.
    expect(_rowShellOf(find.text('L subs')), findsOneWidget);
    final rowSize = tester.getSize(_rowShellOf(find.text('L subs')).first);
    expect(rowSize.height, 28.0);

    // Exposure columns: filter/exposure text and frame count. '10' also
    // appears on the two container rows (each totals 10 subtree frames).
    expect(find.text('L 60s'), findsOneWidget);
    expect(find.text('10'), findsNWidgets(3));

    // The target renders as a ledger row with coordinate chips, not the card.
    expect(find.text('M 42'), findsOneWidget);
    expect(find.text('05h30m'), findsOneWidget);
    expect(find.text("-05°24'"), findsOneWidget);
    await _drainValidationDebounce(tester);
  });

  testWidgets('chevron toggles collapsed state and shows the rollup summary',
      (tester) async {
    final built = _threeLevelSequence([
      ExposureNode(
        name: 'L subs',
        filter: 'L',
        durationSecs: 60,
        count: 10,
        ditherEvery: 0,
      ),
      ExposureNode(
        name: 'R subs',
        filter: 'R',
        durationSecs: 60,
        count: 10,
        ditherEvery: 0,
      ),
    ]);
    final handle = await _pumpTree(tester, built.sequence);

    // Collapse 'Broadband' via its chevron (carries the 'Collapse' semantic).
    final setRow = _rowShellOf(find.text('Broadband')).first;
    final chevron = find.descendant(
        of: setRow, matching: find.bySemanticsLabel('Collapse'));
    await tester.tap(chevron);
    await tester.pumpAndSettle();

    expect(handle.container.read(collapsedNodeIdsProvider),
        contains(built.loopId));
    // Children are hidden and the rollup summary rides on the row.
    expect(find.text('L subs'), findsNothing);
    expect(find.text('L · R 60 s ×10 each'), findsOneWidget);

    // Expand again restores the children and drops the summary.
    final expandChevron = find.descendant(
        of: _rowShellOf(find.text('Broadband')).first,
        matching: find.bySemanticsLabel('Expand'));
    await tester.tap(expandChevron);
    await tester.pumpAndSettle();
    expect(find.text('L subs'), findsOneWidget);
    expect(find.text('L · R 60 s ×10 each'), findsNothing);
    await _drainValidationDebounce(tester);
  });

  testWidgets('selection, multi-select, and context menu still work in ledger',
      (tester) async {
    final target = TargetHeaderNode(
      name: 'M 42',
      targetName: 'Orion',
      raHours: 5.5,
      decDegrees: -5.4,
    );
    final e1 =
        ExposureNode(name: 'L subs', filter: 'L', durationSecs: 60, count: 10);
    final e2 =
        ExposureNode(name: 'R subs', filter: 'R', durationSecs: 60, count: 10);
    final root = InstructionSetNode(name: 'Root');
    final sequence = Sequence.create(
      name: 'T',
      rootNodeId: root.id,
      nodes: {
        e1.id: e1.copyWith(parentId: target.id, orderIndex: 0),
        e2.id: e2.copyWith(parentId: target.id, orderIndex: 1),
        target.id: target.copyWith(
          parentId: root.id,
          orderIndex: 0,
          childIds: [e1.id, e2.id],
        ),
        root.id: root.copyWith(childIds: [target.id]),
      },
    );
    final handle = await _pumpTree(tester, sequence);

    await tester.tap(find.text('L subs'));
    await tester.pump();
    expect(handle.container.read(selectedNodeIdProvider), e1.id);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('R subs'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(handle.container.read(multiSelectedNodeIdsProvider),
        containsAll(<String>[e1.id, e2.id]));

    // Right-click opens the real context menu for the row. (Long-press is
    // claimed by the row's LongPressDraggable on desktop; the secondary-tap
    // branch is the desktop path.)
    await tester.tap(find.text('L subs'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Insert Above'), findsOneWidget);
    await _drainValidationDebounce(tester);
  });

  testWidgets('palette drop into an expanded container inserts the node',
      (tester) async {
    final built = _threeLevelSequence([
      ExposureNode(
        name: 'L subs',
        filter: 'L',
        durationSecs: 60,
        count: 10,
      ),
    ]);
    final handle = await _pumpTree(tester, built.sequence);

    final payload = NodePaletteItem(
      name: 'Delay',
      icon: 'timer',
      description: 'Wait',
      createNode: () => DelayNode(name: 'Dropped delay', seconds: 5),
    );

    // The innermost DragTarget enclosing a child row is the container's
    // children-area target.
    final childrenTarget = find
        .ancestor(
            of: find.text('L subs'), matching: find.byType(DragTarget<Object>))
        .first;
    final target = tester.widget<DragTarget<Object>>(childrenTarget);
    final details =
        DragTargetDetails<Object>(data: payload, offset: Offset.zero);
    expect(target.onWillAcceptWithDetails!.call(details), isTrue);
    target.onAcceptWithDetails!.call(details);
    await tester.pump();

    final updated = handle.container.read(currentSequenceProvider)!;
    final set = updated.nodes[built.loopId]!;
    expect(set.childIds.length, 2);
    expect(updated.nodes[set.childIds.last], isA<DelayNode>());
    expect(find.text('Dropped delay'), findsOneWidget);
    await _drainValidationDebounce(tester);
  });

  testWidgets('palette drop onto a collapsed header lands inside the container',
      (tester) async {
    // Two exposures so the collapsed rollup is the filter-run line — with a
    // single child the generic summary re-prints that child's name, which is
    // indistinguishable from the row still being there.
    final built = _threeLevelSequence([
      ExposureNode(
        name: 'L subs',
        filter: 'L',
        durationSecs: 60,
        count: 10,
        ditherEvery: 0,
      ),
      ExposureNode(
        name: 'R subs',
        filter: 'R',
        durationSecs: 60,
        count: 10,
        ditherEvery: 0,
      ),
    ]);
    final handle = await _pumpTree(tester, built.sequence);

    handle.container
        .read(collapsedNodeIdsProvider.notifier)
        .toggle(built.loopId);
    await tester.pumpAndSettle();
    expect(find.text('L subs'), findsNothing);
    expect(find.text('L · R 60 s ×10 each'), findsOneWidget);

    final payload = NodePaletteItem(
      name: 'Delay',
      icon: 'timer',
      description: 'Wait',
      createNode: () => DelayNode(name: 'Dropped delay', seconds: 5),
    );

    // With the container collapsed, the innermost DragTarget around its row is
    // the collapsed-header target.
    final headerTarget = find
        .ancestor(
            of: find.text('Broadband'),
            matching: find.byType(DragTarget<Object>))
        .first;
    final target = tester.widget<DragTarget<Object>>(headerTarget);
    final details =
        DragTargetDetails<Object>(data: payload, offset: Offset.zero);
    expect(target.onWillAcceptWithDetails!.call(details), isTrue);
    target.onAcceptWithDetails!.call(details);
    await tester.pump();

    final updated = handle.container.read(currentSequenceProvider)!;
    final set = updated.nodes[built.loopId]!;
    expect(set.childIds.length, 3);
    expect(updated.nodes[set.childIds.last], isA<DelayNode>());
    await _drainValidationDebounce(tester);
  });

  testWidgets('density switching hides and shows inline extras',
      (tester) async {
    final target = TargetHeaderNode(
      name: 'M 42',
      targetName: 'Orion',
      raHours: 5.5,
      decDegrees: -5.4,
    );
    final e1 = ExposureNode(
      name: 'L subs',
      filter: 'L',
      durationSecs: 60,
      count: 10,
      comment: 'seeing bad',
    );
    final root = InstructionSetNode(name: 'Root');
    final sequence = Sequence.create(
      name: 'T',
      rootNodeId: root.id,
      nodes: {
        e1.id: e1.copyWith(parentId: target.id, orderIndex: 0),
        target.id: target.copyWith(
          parentId: root.id,
          orderIndex: 0,
          childIds: [e1.id],
        ),
        root.id: root.copyWith(childIds: [target.id]),
      },
    );
    final handle = await _pumpTree(tester, sequence);

    // Ledger: no comment line, column header present.
    expect(find.text('seeing bad'), findsNothing);
    expect(find.text('Filter / exp'), findsOneWidget);

    // Compact: card rows return but inline extras stay suppressed.
    handle.container.read(_testDensityProvider.notifier).state =
        SequencerDensity.compact;
    await tester.pumpAndSettle();
    expect(find.text('seeing bad'), findsNothing);
    expect(find.text('Filter / exp'), findsNothing);

    // Comfortable: the comment line comes back. The target card animates
    // continuously (altitude chart), so settle on a fixed pump instead of
    // pumpAndSettle.
    handle.container.read(_testDensityProvider.notifier).state =
        SequencerDensity.comfortable;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('seeing bad'), findsOneWidget);
    await _drainValidationDebounce(tester);
  });
}
