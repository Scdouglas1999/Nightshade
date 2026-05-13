import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/sequence/sequence_models.dart';
import 'sequence/sequence_editor.dart';

// Public surface for the sequencer providers. The heavy implementation pieces
// live in `sequence/`:
//
//   * sequence_executor.dart    — SequenceExecutor + sequenceExecutorProvider
//   * sequence_validation.dart  — validateSequence / SequenceValidationIssue
//   * sequencer_defaults.dart   — SequencerDefaults(+Notifier) provider
//   * node_palette.dart         — NodePaletteCategory / NodePaletteItem provider
//   * sequence_editor.dart      — CurrentSequenceNotifier (tree mutations,
//                                  undo/redo, snippet insertion)
//
// This file holds only:
//   * the top-level providers callers reach for from the barrel
//   * SequenceProgressNotifier (small state-only notifier)
//   * MultiSelectNotifier (depends on currentSequenceProvider, so co-located)
//   * re-exports of the public types above
export 'sequence/sequence_editor.dart';
export 'sequence/sequence_executor.dart';
export 'sequence/sequence_validation.dart';
export 'sequence/sequencer_defaults.dart';
export 'sequence/node_palette.dart';

// =============================================================================
// EXECUTION STATE
// =============================================================================

/// Current sequence execution state
final sequenceExecutionStateProvider =
    StateProvider<SequenceExecutionState>((ref) {
  return SequenceExecutionState.idle;
});

/// Current sequence progress
final sequenceProgressProvider =
    StateNotifierProvider<SequenceProgressNotifier, SequenceProgress>((ref) {
  return SequenceProgressNotifier();
});

class SequenceProgressNotifier extends StateNotifier<SequenceProgress> {
  SequenceProgressNotifier() : super(const SequenceProgress());

  void updateState(SequenceExecutionState executionState) {
    state = state.copyWith(state: executionState);
  }

  void updateProgress({
    String? currentNodeId,
    String? currentNodeName,
    NodeStatus? currentNodeStatus,
    int? completedExposures,
    double? completedIntegrationSecs,
    double? elapsedSecs,
    double? estimatedRemainingSecs,
    String? currentTarget,
    String? currentFilter,
    String? message,
  }) {
    state = state.copyWith(
      currentNodeId: currentNodeId,
      currentNodeName: currentNodeName,
      currentNodeStatus: currentNodeStatus,
      completedExposures: completedExposures,
      completedIntegrationSecs: completedIntegrationSecs,
      elapsedSecs: elapsedSecs,
      estimatedRemainingSecs: estimatedRemainingSecs,
      currentTarget: currentTarget,
      currentFilter: currentFilter,
      message: message,
    );
  }

  void updateNodeStatus(String nodeId, NodeStatus status) {
    final newStatuses = Map<String, NodeStatus>.from(state.nodeStatuses);
    newStatuses[nodeId] = status;
    state = state.copyWith(nodeStatuses: newStatuses);
  }

  void updateNodeProgress(
      String nodeId, double progressPercent, String detail) {
    final newProgressPercent =
        Map<String, double>.from(state.nodeProgressPercent);
    final newProgressDetail =
        Map<String, String>.from(state.nodeProgressDetail);

    newProgressPercent[nodeId] = progressPercent;
    newProgressDetail[nodeId] = detail;

    state = state.copyWith(
      nodeProgressPercent: newProgressPercent,
      nodeProgressDetail: newProgressDetail,
    );
  }

  void setTotals(int totalExposures, double totalIntegrationSecs) {
    state = state.copyWith(
      totalExposures: totalExposures,
      totalIntegrationSecs: totalIntegrationSecs,
    );
  }

  void reset() {
    state = const SequenceProgress();
  }
}

// =============================================================================
// SEQUENCE EDITOR STATE
// =============================================================================

/// Current sequence being edited.
///
/// The notifier implementation lives in `sequence/sequence_editor.dart`.
final currentSequenceProvider =
    StateNotifierProvider<CurrentSequenceNotifier, Sequence?>((ref) {
  return CurrentSequenceNotifier();
});

// =============================================================================
// SELECTED NODE
// =============================================================================

/// Currently selected node ID
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);

/// Currently selected node (derived)
final selectedNodeProvider = Provider<SequenceNode?>((ref) {
  final sequence = ref.watch(currentSequenceProvider);
  final selectedId = ref.watch(selectedNodeIdProvider);

  if (sequence == null || selectedId == null) return null;
  return sequence.nodes[selectedId];
});

// =============================================================================
// MULTI-SELECT
// =============================================================================

/// Set of currently multi-selected node IDs.
final multiSelectedNodeIdsProvider =
    StateNotifierProvider<MultiSelectNotifier, Set<String>>(
  (ref) => MultiSelectNotifier(ref),
);

/// Whether multi-select mode is active (has >0 selections).
final isMultiSelectActiveProvider = Provider<bool>((ref) {
  return ref.watch(multiSelectedNodeIdsProvider).isNotEmpty;
});

/// Clipboard for batch copy/paste operations.
/// Stores serialized node trees ready for pasting.
final nodeCopyClipboardProvider =
    StateProvider<List<Map<String, dynamic>>?>((ref) => null);

class MultiSelectNotifier extends StateNotifier<Set<String>> {
  final Ref ref;

  MultiSelectNotifier(this.ref) : super({});

  /// Toggle a single node in the selection (Ctrl+Click).
  void toggle(String nodeId) {
    if (state.contains(nodeId)) {
      state = Set.from(state)..remove(nodeId);
    } else {
      state = Set.from(state)..add(nodeId);
    }
  }

  /// Range select: select all siblings between the last selected node
  /// and the clicked node (Shift+Click).
  void rangeSelect(String nodeId) {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    final node = sequence.nodes[nodeId];
    if (node == null || node.parentId == null) return;

    // Anchor priority: last single-selected node, else last item in current set.
    final anchor = ref.read(selectedNodeIdProvider) ?? state.lastOrNull;
    if (anchor == null) {
      state = {nodeId};
      return;
    }

    final anchorNode = sequence.nodes[anchor];
    if (anchorNode == null ||
        anchorNode.parentId == null ||
        anchorNode.parentId != node.parentId) {
      // Different parents or invalid anchor — just toggle to this node.
      state = {nodeId};
      return;
    }

    final siblings = sequence.getChildren(node.parentId!);
    final anchorIndex = siblings.indexWhere((n) => n.id == anchor);
    final targetIndex = siblings.indexWhere((n) => n.id == nodeId);

    if (anchorIndex < 0 || targetIndex < 0) {
      state = {nodeId};
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;

    final rangeIds = <String>{};
    for (int i = start; i <= end; i++) {
      rangeIds.add(siblings[i].id);
    }

    state = rangeIds;
  }

  /// Clear all selections.
  void clear() {
    state = {};
  }

  /// Select specific nodes.
  void selectAll(Iterable<String> nodeIds) {
    state = Set.from(nodeIds);
  }

  /// Delete all selected nodes.
  void deleteSelected() {
    final notifier = ref.read(currentSequenceProvider.notifier);
    for (final nodeId in state) {
      notifier.removeNode(nodeId);
    }
    clear();
    ref.read(selectedNodeIdProvider.notifier).state = null;
  }

  /// Enable all selected nodes.
  void enableSelected() {
    final notifier = ref.read(currentSequenceProvider.notifier);
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    for (final nodeId in state) {
      final node = sequence.nodes[nodeId];
      if (node != null && !node.isEnabled) {
        notifier.updateNode(node.copyWith(isEnabled: true));
      }
    }
  }

  /// Disable all selected nodes.
  void disableSelected() {
    final notifier = ref.read(currentSequenceProvider.notifier);
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    for (final nodeId in state) {
      final node = sequence.nodes[nodeId];
      if (node != null && node.isEnabled) {
        notifier.updateNode(node.copyWith(isEnabled: false));
      }
    }
  }

  /// Copy selected nodes to clipboard.
  void copySelected() {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    final clipboard = <Map<String, dynamic>>[];
    for (final nodeId in state) {
      final tree = _serializeNodeTree(sequence, nodeId);
      if (tree != null) {
        clipboard.add(tree);
      }
    }

    if (clipboard.isNotEmpty) {
      ref.read(nodeCopyClipboardProvider.notifier).state = clipboard;
    }
  }

  /// Paste nodes from clipboard into the currently selected parent.
  void pasteFromClipboard() {
    final clipboard = ref.read(nodeCopyClipboardProvider);
    if (clipboard == null || clipboard.isEmpty) return;

    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return;

    final notifier = ref.read(currentSequenceProvider.notifier);

    // Paste target: the single selected node's parent, else the root.
    final selectedId = ref.read(selectedNodeIdProvider);
    String? parentId;
    if (selectedId != null) {
      final selectedNode = sequence.nodes[selectedId];
      parentId = selectedNode?.parentId;
    }
    parentId ??= sequence.rootNode?.id;
    if (parentId == null) return;

    for (final tree in clipboard) {
      _pasteNodeTree(notifier, sequence, tree, parentId);
    }
  }

  /// Serialize a node and its children to a map for clipboard storage.
  Map<String, dynamic>? _serializeNodeTree(Sequence sequence, String nodeId) {
    final node = sequence.nodes[nodeId];
    if (node == null) return null;

    final children = <Map<String, dynamic>>[];
    for (final childId in node.childIds) {
      final childTree = _serializeNodeTree(sequence, childId);
      if (childTree != null) {
        children.add(childTree);
      }
    }

    return {
      'node': node,
      'children': children,
    };
  }

  /// Paste a serialized node tree, creating new IDs.
  void _pasteNodeTree(
    CurrentSequenceNotifier notifier,
    Sequence sequence,
    Map<String, dynamic> tree,
    String parentId,
  ) {
    final originalNode = tree['node'] as SequenceNode;
    final children = tree['children'] as List<Map<String, dynamic>>;

    // Fresh id so the pasted copy doesn't collide with the source node.
    final newNode = originalNode.copyWith(
      id: const Uuid().v4(),
      parentId: parentId,
      childIds: [],
    );
    notifier.addNode(newNode, parentId: parentId);

    for (final childTree in children) {
      _pasteNodeTree(notifier, sequence, childTree, newNode.id);
    }
  }
}
