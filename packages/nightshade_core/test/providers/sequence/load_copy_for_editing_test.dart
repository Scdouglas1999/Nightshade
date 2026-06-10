import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';

/// Coverage for [CurrentSequenceNotifier.loadCopyForEditing] — the copy-on-open
/// helper the Framing "add target to an existing sequence" flow uses to load a
/// chosen library sequence under fresh node IDs before appending a target.

ProviderContainer _newContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

CurrentSequenceNotifier _notifier(ProviderContainer c) =>
    c.read(currentSequenceProvider.notifier);

/// A two-node source sequence: root InstructionSet + one TargetHeader child.
Sequence _sourceSequence() {
  const rootId = 'root-original';
  const targetId = 'target-original';
  final root = InstructionSetNode(
    id: rootId,
    name: 'Sequence',
    childIds: const [targetId],
  );
  final target = TargetHeaderNode(
    id: targetId,
    name: 'M31',
    targetName: 'M31',
    raHours: 0.71,
    decDegrees: 41.27,
    parentId: rootId,
  );
  return Sequence.create(
    name: 'My Manual Sequence',
    databaseId: 42,
    nodes: {rootId: root, targetId: target},
    rootNodeId: rootId,
  );
}

void main() {
  group('loadCopyForEditing', () {
    test('loads a deep copy under fresh node IDs, preserving topology', () {
      final c = _newContainer();
      final source = _sourceSequence();

      _notifier(c).loadCopyForEditing(source);

      final loaded = c.read(currentSequenceProvider);
      expect(loaded, isNotNull);
      // Original library row reference preserved so Save updates the same row.
      expect(loaded!.databaseId, 42);
      expect(loaded.name, 'My Manual Sequence');

      // Every node was re-keyed: no original ID survives.
      expect(loaded.nodes.containsKey('root-original'), isFalse);
      expect(loaded.nodes.containsKey('target-original'), isFalse);
      expect(loaded.nodes, hasLength(2));

      // Topology preserved: the root has one child and it is the target.
      final root = loaded.nodes[loaded.rootNodeId!]!;
      expect(root, isA<InstructionSetNode>());
      expect(root.childIds, hasLength(1));
      final childId = root.childIds.first;
      final child = loaded.nodes[childId]!;
      expect(child, isA<TargetHeaderNode>());
      expect((child as TargetHeaderNode).targetName, 'M31');
      expect(child.parentId, loaded.rootNodeId);
    });

    test(
      'appending a bare target after a copy-open does not alias originals',
      () {
        final c = _newContainer();
        _notifier(c).loadCopyForEditing(_sourceSequence());

        _notifier(c).addTargetHeader(
          TargetHeaderNode(
            name: 'NGC 891',
            targetName: 'NGC 891',
            raHours: 2.37,
            decDegrees: 42.35,
          ),
        );

        final loaded = c.read(currentSequenceProvider)!;
        final targets = loaded.nodes.values
            .whereType<TargetHeaderNode>()
            .toList();
        expect(
          targets.map((t) => t.targetName),
          containsAll(['M31', 'NGC 891']),
        );
        // The new header is a child of the copied root, not orphaned.
        final root = loaded.nodes[loaded.rootNodeId!]!;
        expect(root.childIds, hasLength(2));
      },
    );

    test('refuses to clobber unsaved edits unless discardUnsaved is true', () {
      final c = _newContainer();
      _notifier(c).createSequence(name: 'work in progress');
      // Dirty the editor.
      _notifier(c).addTargetHeader(
        TargetHeaderNode(
          name: 'dirty',
          targetName: 'dirty',
          raHours: 1.0,
          decDegrees: 1.0,
        ),
      );

      expect(
        () => _notifier(c).loadCopyForEditing(_sourceSequence()),
        throwsA(isA<UnsavedChangesException>()),
      );

      // With discardUnsaved the load proceeds.
      _notifier(c).loadCopyForEditing(_sourceSequence(), discardUnsaved: true);
      expect(c.read(currentSequenceProvider)!.databaseId, 42);
    });

    test('throws SequenceLockedException while a run is active', () {
      final c = _newContainer();
      _notifier(c).createSequence();
      c.read(sequenceExecutionStateProvider.notifier).state =
          SequenceExecutionState.running;
      expect(
        () => _notifier(c).loadCopyForEditing(_sourceSequence()),
        throwsA(isA<SequenceLockedException>()),
      );
    });
  });
}
