// Tests for the secondary-tap / long-press context menu wired around
// tree nodes. We mount only the wrapper widget itself with a known
// sequence so the test stays focused on the menu's lifecycle (open ->
// pick item -> mutate sequence).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree_context_menu.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

({Sequence sequence, String containerId, String childId})
    _containerWithOneChild() {
  final child = ExposureNode(name: 'child', durationSecs: 1, count: 1);
  final container = InstructionSetNode(name: 'container');
  final root = InstructionSetNode(name: 'Root');
  final tree = <String, SequenceNode>{
    child.id: child.copyWith(parentId: container.id),
    container.id:
        container.copyWith(parentId: root.id, childIds: [child.id]),
    root.id: root.copyWith(childIds: [container.id]),
  };
  return (
    sequence: Sequence.create(name: 'T', nodes: tree, rootNodeId: root.id),
    containerId: container.id,
    childId: child.id,
  );
}

ProviderContainer _seed(Sequence seq) {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = seq;
  final container = ProviderContainer(overrides: [
    currentSequenceProvider.overrideWith((_) => notifier),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
}

NightshadeColors _colors() {
  return NightshadeColors.dark;
}

/// Open the context menu via long-press. The wrapper exposes both
/// `onSecondaryTapUp` and `onLongPressStart`, and exercising the
/// long-press branch is enough to validate the menu lifecycle from the
/// test surface (the secondary-tap branch is identical except for the
/// trigger gesture). Tested separately on the desktop platform during
/// manual QA.
Future<void> _openMenu(WidgetTester tester, Finder finder) async {
  await tester.longPress(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click opens menu and selects the node', (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(
          width: 200,
          height: 40,
          child: Center(child: Text('row')),
        ),
      ),
    );

    await _openMenu(tester, find.text('row'));

    // Menu should be open and the node should be selected as a side
    // effect of opening it (matches OS conventions).
    expect(find.text('Insert Above'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Group into Sequential Container'), findsOneWidget);
    expect(find.text('Group into Parallel Container'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget); // child starts enabled
    expect(find.text('Delete'), findsOneWidget);
    expect(container.read(selectedNodeIdProvider), t.childId);
  });

  testWidgets('Duplicate creates a sibling copy', (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));

    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    final seq = container.read(currentSequenceProvider)!;
    final parent = seq.nodes[t.containerId]!;
    expect(parent.childIds.length, 2);
  });

  testWidgets('Group into Sequential Container wraps the node',
      (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Group into Sequential Container'));
    await tester.pumpAndSettle();

    final seq = container.read(currentSequenceProvider)!;
    final wrappedChild = seq.nodes[t.childId]!;
    // The child's parent should no longer be the original container — it
    // should be a freshly created InstructionSetNode sitting between
    // them.
    expect(wrappedChild.parentId, isNot(t.containerId));
    final newParent = seq.nodes[wrappedChild.parentId!]!;
    expect(newParent, isA<InstructionSetNode>());
    expect(newParent.parentId, t.containerId);
  });

  testWidgets('Group into Parallel Container wraps the node',
      (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Group into Parallel Container'));
    await tester.pumpAndSettle();

    final seq = container.read(currentSequenceProvider)!;
    final wrappedChild = seq.nodes[t.childId]!;
    expect(seq.nodes[wrappedChild.parentId!], isA<ParallelNode>());
  });

  testWidgets('Disable toggles isEnabled', (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Disable'));
    await tester.pumpAndSettle();

    expect(
      container.read(currentSequenceProvider)!.nodes[t.childId]!.isEnabled,
      isFalse,
    );

    // Reopen the menu; the same entry should now read "Enable".
    await _openMenu(tester, find.text('row'));
    expect(find.text('Enable'), findsOneWidget);
  });

  testWidgets('Delete on a leaf prompts for confirmation, then removes',
      (tester) async {
    // Post-consolidation: every user-initiated delete surface (Properties
    // panel, targets tab, tree trash, right-click Delete, Delete key)
    // funnels through `confirmAndDeleteSequenceNode`, which always
    // prompts. Leaves get a simpler "removed from sequence" body without
    // a descendant count.
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(
            width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirmation dialog is on screen and the leaf is still alive.
    expect(find.text('Cancel'), findsOneWidget);
    expect(
        container.read(currentSequenceProvider)!.nodes.containsKey(t.childId),
        isTrue);

    // Confirm — the "Delete" action button (not the menu entry which
    // closed when we tapped it). The dialog uses a NightshadeButton with
    // text "Delete".
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
        container.read(currentSequenceProvider)!.nodes.containsKey(t.childId),
        isFalse);
  });

  testWidgets(
      'Delete on a leaf can be cancelled and leaves the node in place',
      (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.childId,
        colors: _colors(),
        child: const SizedBox(
            width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
        container.read(currentSequenceProvider)!.nodes.containsKey(t.childId),
        isTrue);
  });

  testWidgets('Delete on a container with descendants asks for confirmation',
      (tester) async {
    final t = _containerWithOneChild();
    final container = _seed(t.sequence);

    await _pump(
      tester,
      container,
      SequenceTreeContextMenu(
        nodeId: t.containerId,
        colors: _colors(),
        child: const SizedBox(width: 200, height: 40, child: Center(child: Text('row'))),
      ),
    );

    await _openMenu(tester, find.text('row'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirmation dialog should now be on screen.
    expect(find.text('Cancel'), findsOneWidget);
    // The container is still present until the user confirms.
    expect(container.read(currentSequenceProvider)!.nodes.containsKey(t.containerId),
        isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(currentSequenceProvider)!.nodes.containsKey(t.containerId),
        isTrue);
  });
}
