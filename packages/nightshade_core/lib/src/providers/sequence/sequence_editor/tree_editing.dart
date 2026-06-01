part of '../sequence_editor.dart';

extension CurrentSequenceTreeEditing on CurrentSequenceNotifier {
  /// Add a node to the sequence
  void addNode(SequenceNode node, {String? parentId, int? index}) {
    if (_currentSequence == null) return;
    _ensureEditable('add node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    newNodes[node.id] = node;

    if (parentId != null && newNodes.containsKey(parentId)) {
      final parent = newNodes[parentId]!;
      final newChildIds = List<String>.from(parent.childIds);

      if (index != null && index >= 0 && index <= newChildIds.length) {
        newChildIds.insert(index, node.id);
      } else {
        newChildIds.add(node.id);
      }

      newNodes[parentId] = parent.copyWith(childIds: newChildIds);
      newNodes[node.id] = node.copyWith(
        parentId: parentId,
        orderIndex: index ?? newChildIds.length - 1,
      );

      if (index != null) {
        for (int i = index + 1; i < newChildIds.length; i++) {
          final childId = newChildIds[i];
          if (newNodes.containsKey(childId)) {
            newNodes[childId] = newNodes[childId]!.copyWith(orderIndex: i);
          }
        }
      }
    } else if (_currentSequence!.rootNodeId != null) {
      final root = newNodes[_currentSequence!.rootNodeId!]!;
      final newChildIds = List<String>.from(root.childIds);

      if (index != null && index >= 0 && index <= newChildIds.length) {
        newChildIds.insert(index, node.id);
      } else {
        newChildIds.add(node.id);
      }

      newNodes[_currentSequence!.rootNodeId!] =
          root.copyWith(childIds: newChildIds);
      newNodes[node.id] = node.copyWith(
        parentId: _currentSequence!.rootNodeId,
        orderIndex: index ?? newChildIds.length - 1,
      );

      if (index != null) {
        for (int i = index + 1; i < newChildIds.length; i++) {
          final childId = newChildIds[i];
          if (newNodes.containsKey(childId)) {
            newNodes[childId] = newNodes[childId]!.copyWith(orderIndex: i);
          }
        }
      }
    }

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Add a target header node, adopting any orphan instructions.
  /// If there are existing instruction nodes directly under the root (not wrapped
  /// in a target), those instructions will become children of the new target.
  ///
  /// Throws [NoActiveSequenceException] when no sequence is loaded — previously
  /// this silently created an unnamed sequence, hiding the UX failure that the
  /// user hadn't opened or created one yet. UI callers should catch and prompt
  /// (e.g. "Create a new sequence named '${targetNode.targetName}'?").
  void addTargetHeader(TargetHeaderNode targetNode) {
    if (_currentSequence == null) {
      throw NoActiveSequenceException(
        attemptedOperation: 'add target "${targetNode.targetName}"',
      );
    }
    _ensureEditable('add target');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    final rootNodeId = _currentSequence!.rootNodeId;
    if (rootNodeId == null) return;

    final root = newNodes[rootNodeId];
    if (root == null) return;

    final orphanIds = <String>[];
    final remainingRootChildren = <String>[];

    for (final childId in root.childIds) {
      final child = newNodes[childId];
      if (child != null && child is! TargetHeaderNode) {
        orphanIds.add(childId);
      } else {
        remainingRootChildren.add(childId);
      }
    }

    final targetWithChildren = targetNode.copyWith(
      parentId: rootNodeId,
      childIds: orphanIds,
      orderIndex: remainingRootChildren.length,
    );
    newNodes[targetNode.id] = targetWithChildren;

    for (int i = 0; i < orphanIds.length; i++) {
      final orphanId = orphanIds[i];
      if (newNodes.containsKey(orphanId)) {
        newNodes[orphanId] = newNodes[orphanId]!.copyWith(
          parentId: targetNode.id,
          orderIndex: i,
        );
      }
    }

    remainingRootChildren.add(targetNode.id);
    newNodes[rootNodeId] = root.copyWith(childIds: remainingRootChildren);

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Remove a node from the sequence.
  ///
  /// Removes the node and its entire subtree. The editor does not gate this
  /// on descendant count — confirmation dialogs are the UI's responsibility
  /// (see [Sequence.countDescendants]).
  void removeNode(String nodeId) {
    if (_currentSequence == null) return;
    _ensureEditable('remove node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    final nodeToRemove = newNodes[nodeId];
    if (nodeToRemove == null) return;

    if (nodeToRemove.parentId != null &&
        newNodes.containsKey(nodeToRemove.parentId)) {
      final parent = newNodes[nodeToRemove.parentId!]!;
      final newChildIds = parent.childIds.where((id) => id != nodeId).toList();
      newNodes[nodeToRemove.parentId!] = parent.copyWith(childIds: newChildIds);
    }

    void removeRecursive(String id) {
      final node = newNodes[id];
      if (node != null) {
        for (final childId in node.childIds) {
          removeRecursive(childId);
        }
        newNodes.remove(id);
      }
    }

    removeRecursive(nodeId);

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Update a node
  void updateNode(SequenceNode node) {
    if (_currentSequence == null) return;
    _ensureEditable('update node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    newNodes[node.id] = node;

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Toggle node enabled _currentSequence
  void toggleNodeEnabled(String nodeId) {
    if (_currentSequence == null) return;
    // No _ensureEditable here — updateNode below performs the guard.
    final node = _currentSequence!.nodes[nodeId];
    if (node == null) return;

    updateNode(node.copyWith(isEnabled: !node.isEnabled));
  }

  /// Reorder a child of [parentId] from [oldIndex] to [newIndex] within the
  /// parent's child list.
  ///
  /// W1.7: the defensive `containsKey` sweep over every sibling has been
  /// removed. With the parent-keyed index in [Sequence], every entry in
  /// `parent.childIds` is guaranteed to resolve in `nodes` by the
  /// [Sequence.invariants] contract — the only way to violate it is to
  /// directly construct a malformed `Sequence`, which the editor never does.
  ///
  /// Cost: O(K) where K = number of children of [parentId] (the splice
  /// itself plus the per-sibling `orderIndex` renumber needed for DB
  /// persistence round-trips). The pre-W1.7 implementation was O(N) over
  /// every node in the tree because of the clone-and-rescan pattern.
  void reorderNodes(String parentId, int oldIndex, int newIndex) {
    if (_currentSequence == null) return;
    _ensureEditable('reorder nodes');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    final parent = newNodes[parentId];
    if (parent == null) return;

    final children = List<String>.from(parent.childIds);
    // `removeAt` / `insert` throw RangeError on out-of-range indices, which
    // matches the legacy behaviour: callers passing stale Flutter
    // `ReorderableListView` indices learn loudly rather than silently no-op.
    final item = children.removeAt(oldIndex);
    children.insert(newIndex, item);

    // Renumber only the affected parent's children. orderIndex is
    // load-bearing for the SQL `ORDER BY` in `SequencesDao.getNodesForSequence`
    // (see `database/daos/sequences_dao.dart`) and for backup/restore
    // round-trips, so it must agree with the new sibling order at save time.
    for (int i = 0; i < children.length; i++) {
      final child = newNodes[children[i]]!;
      newNodes[children[i]] = child.copyWith(orderIndex: i);
    }

    newNodes[parentId] = parent.copyWith(childIds: children);

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Move a node to a different parent
  void moveNode(String nodeId, String newParentId, int index) {
    if (_currentSequence == null) return;
    _ensureEditable('move node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    final node = newNodes[nodeId];
    if (node == null) return;

    if (node.parentId != null && newNodes.containsKey(node.parentId)) {
      final oldParent = newNodes[node.parentId!]!;
      final newChildIds =
          oldParent.childIds.where((id) => id != nodeId).toList();
      newNodes[node.parentId!] = oldParent.copyWith(childIds: newChildIds);
    }

    final newParent = newNodes[newParentId];
    if (newParent == null) return;

    final newChildIds = List<String>.from(newParent.childIds);
    newChildIds.insert(index.clamp(0, newChildIds.length), nodeId);
    newNodes[newParentId] = newParent.copyWith(childIds: newChildIds);

    newNodes[nodeId] = node.copyWith(parentId: newParentId, orderIndex: index);

    for (int i = 0; i < newChildIds.length; i++) {
      final child = newNodes[newChildIds[i]]!;
      newNodes[newChildIds[i]] = child.copyWith(orderIndex: i);
    }

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Duplicate a node
  void duplicateNode(String nodeId) {
    if (_currentSequence == null) return;
    final node = _currentSequence!.nodes[nodeId];
    if (node == null) return;

    _ensureEditable('duplicate node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);

    SequenceNode duplicateRecursive(
        SequenceNode original, String? newParentId) {
      final newId = const Uuid().v4();
      final newChildIds = <String>[];

      for (final childId in original.childIds) {
        final child = _currentSequence!.nodes[childId];
        if (child != null) {
          final duplicatedChild = duplicateRecursive(child, newId);
          newChildIds.add(duplicatedChild.id);
          newNodes[duplicatedChild.id] = duplicatedChild;
        }
      }

      return original.copyWith(
        id: newId,
        name: '${original.name} (Copy)',
        childIds: newChildIds,
        parentId: newParentId,
      );
    }

    final duplicate = duplicateRecursive(node, node.parentId);
    newNodes[duplicate.id] = duplicate;

    if (node.parentId != null && newNodes.containsKey(node.parentId)) {
      final parent = newNodes[node.parentId!]!;
      final index = parent.childIds.indexOf(nodeId);
      final newChildIds = List<String>.from(parent.childIds);
      newChildIds.insert(index + 1, duplicate.id);
      newNodes[node.parentId!] = parent.copyWith(childIds: newChildIds);
    }

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Wrap all children of a node into a new container node
  void wrapChildren(String parentId, SequenceNode wrapper) {
    if (_currentSequence == null) return;
    final parent = _currentSequence!.nodes[parentId];
    if (parent == null) return;

    _ensureEditable('wrap children');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);
    final originalChildren = List<String>.from(parent.childIds);

    // Fresh id for the wrapper so it doesn't collide with any existing node.
    final newWrapper = wrapper.copyWith(
      id: const Uuid().v4(),
      childIds: originalChildren,
      parentId: parentId,
      orderIndex: 0,
    );

    newNodes[newWrapper.id] = newWrapper;

    newNodes[parentId] = parent.copyWith(childIds: [newWrapper.id]);

    for (final childId in originalChildren) {
      if (newNodes.containsKey(childId)) {
        newNodes[childId] =
            newNodes[childId]!.copyWith(parentId: newWrapper.id);
      }
    }

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Wrap a *contiguous* run of sibling children under [parentId] (identified
  /// by [childIds], in any order) into a single new container node.
  ///
  /// Used by the multi-select group action: when the user has 3 nodes
  /// selected and right-clicks "Group into Sequential Container", we want
  /// all 3 to land inside the new container in their original sibling
  /// order — *not* just the right-clicked node.
  ///
  /// Throws [StateError] if the supplied [childIds] are not all direct
  /// children of [parentId] (selection spans multiple parents → ambiguous;
  /// caller should refuse) or if they are not contiguous (would require
  /// reordering siblings, which we don't silently do). The empty case is a
  /// no-op so it composes safely with callers that don't pre-filter.
  void wrapChildrenSubset(
    String parentId,
    List<String> childIds,
    SequenceNode wrapper,
  ) {
    if (_currentSequence == null) return;
    if (childIds.isEmpty) return;
    final parent = _currentSequence!.nodes[parentId];
    if (parent == null) return;

    // Validate every requested child is in the parent's child list.
    final parentChildIds = parent.childIds;
    final indices = <int>[];
    for (final childId in childIds) {
      final idx = parentChildIds.indexOf(childId);
      if (idx < 0) {
        throw StateError(
          'wrapChildrenSubset: node $childId is not a child of $parentId. '
          'Multi-select group requires all selected nodes to share the '
          'same parent.',
        );
      }
      indices.add(idx);
    }
    indices.sort();

    // Contiguity: indices must be a run of consecutive integers. Wrapping
    // non-contiguous siblings would force us to reorder the parent's child
    // list as a side effect — which is the kind of silent rearrangement
    // that surprises users. Refuse and let the UI explain.
    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) {
        throw StateError(
          'wrapChildrenSubset: selected children are not contiguous '
          '(indices=${indices.join(",")}); refusing to silently reorder. '
          'Group adjacent nodes only or wrap them individually.',
        );
      }
    }

    _ensureEditable('group selected nodes');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);

    // Recover the children in their original sibling order (matches what
    // the user sees in the tree) instead of the click order.
    final selectedInParentOrder = <String>[
      for (final idx in indices) parentChildIds[idx],
    ];

    final firstIdx = indices.first;
    final newWrapper = wrapper.copyWith(
      id: const Uuid().v4(),
      childIds: selectedInParentOrder,
      parentId: parentId,
      orderIndex: firstIdx,
    );
    newNodes[newWrapper.id] = newWrapper;

    // Reparent each selected child onto the wrapper, preserving their
    // sibling order via the new orderIndex.
    for (int i = 0; i < selectedInParentOrder.length; i++) {
      final childId = selectedInParentOrder[i];
      final child = newNodes[childId];
      if (child == null) continue;
      newNodes[childId] = child.copyWith(
        parentId: newWrapper.id,
        orderIndex: i,
      );
    }

    // Rebuild the parent's child list with the wrapper in place of the
    // selected run, then renumber the remaining children's orderIndexes.
    final newParentChildren = <String>[];
    final selectedSet = selectedInParentOrder.toSet();
    var inserted = false;
    for (final id in parentChildIds) {
      if (selectedSet.contains(id)) {
        if (!inserted) {
          newParentChildren.add(newWrapper.id);
          inserted = true;
        }
        // Skip — child is now under the wrapper.
        continue;
      }
      newParentChildren.add(id);
    }
    // Sanity: contiguous + non-empty + at least one matched → inserted is
    // true. Defense-in-depth: if not, prepend so the wrapper is at least
    // reachable.
    if (!inserted) {
      newParentChildren.insert(0, newWrapper.id);
    }

    for (int i = 0; i < newParentChildren.length; i++) {
      final child = newNodes[newParentChildren[i]];
      if (child == null) continue;
      newNodes[newParentChildren[i]] = child.copyWith(orderIndex: i);
    }

    newNodes[parentId] = parent.copyWith(childIds: newParentChildren);

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Wrap a specific node into a new container node
  void wrapNode(String nodeId, SequenceNode wrapper) {
    if (_currentSequence == null) return;
    final node = _currentSequence!.nodes[nodeId];
    if (node == null) return;
    final parentId = node.parentId;
    if (parentId == null) return; // Cannot wrap root

    final parent = _currentSequence!.nodes[parentId];
    if (parent == null) return;

    _ensureEditable('wrap node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(_currentSequence!.nodes);

    final newWrapper = wrapper.copyWith(
      id: const Uuid().v4(),
      childIds: [nodeId],
      parentId: parentId,
      orderIndex: node.orderIndex,
    );
    newNodes[newWrapper.id] = newWrapper;

    newNodes[nodeId] = node.copyWith(parentId: newWrapper.id, orderIndex: 0);

    final newParentChildren = List<String>.from(parent.childIds);
    final index = newParentChildren.indexOf(nodeId);
    if (index >= 0) {
      newParentChildren[index] = newWrapper.id;
      newNodes[parentId] = parent.copyWith(childIds: newParentChildren);
    }

    _currentSequence = _currentSequence!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Reorder target groups (helper for Targets tab).
  ///
  /// Throws [CrossParentReorderException] when the source and destination
  /// targets do not share the same parent — that semantic is ambiguous
  /// (move? adopt? merge?) and must be expressed explicitly. UI should
  /// catch and show a snackbar.
  void reorderTargets(int oldIndex, int newIndex) {
    if (_currentSequence == null) return;
    // _ensureEditable runs implicitly through reorderNodes below; we also
    // check upfront so the ambiguity exception (CrossParent) doesn't
    // mask a SequenceLockedException for the same call.
    _ensureEditable('reorder targets');

    final targets = _currentSequence!.targetHeaders;
    if (oldIndex < 0 || oldIndex >= targets.length) return;

    // Flutter ReorderableListView reports newIndex as the post-removal slot;
    // adjust so we can index into the unchanged list.
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= targets.length) return;

    final oldTarget = targets[oldIndex];
    final newTarget = targets[newIndex];

    final sameSiblingParent =
        oldTarget.parentId == newTarget.parentId && oldTarget.parentId != null;
    if (!sameSiblingParent) {
      throw CrossParentReorderException(
        sourceTargetName: oldTarget.targetName,
        destinationTargetName: newTarget.targetName,
      );
    }

    final parentId = oldTarget.parentId!;
    final parent = _currentSequence!.nodes[parentId];
    if (parent == null) return;

    // Find actual indices in the parent's child list (may contain non-targets)
    final oldChildIndex = parent.childIds.indexOf(oldTarget.id);
    final newChildIndex = parent.childIds.indexOf(newTarget.id);

    if (oldChildIndex != -1 && newChildIndex != -1) {
      reorderNodes(parentId, oldChildIndex, newChildIndex);
    }
  }
}
