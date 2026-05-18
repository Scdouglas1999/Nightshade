import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/imaging/imaging_models.dart';
import '../../models/sequence/sequence_models.dart';
import '../../models/sequence/template_snippet.dart';
import '../sequence_provider.dart' show sequenceExecutionStateProvider;
import 'sequence_editor_exceptions.dart';
import 'sequence_undo_batch.dart';

export 'sequence_editor_exceptions.dart';

/// Provider exposing whether the current sequence can be edited.
///
/// Returns `false` while the sequence is Running / Paused / Stopping — those
/// are the phases where the executor owns the tree. Returns `true` for Idle,
/// Completed, and Failed.
///
/// UI should `watch` this provider to gray out edit affordances. The notifier
/// itself enforces the gate by throwing [SequenceLockedException] from
/// mutating methods, so this provider is for UX, not security.
final canEditSequenceProvider = Provider<bool>((ref) {
  final state = ref.watch(sequenceExecutionStateProvider);
  return _isEditable(state);
});

bool _isEditable(SequenceExecutionState state) {
  switch (state) {
    case SequenceExecutionState.idle:
    case SequenceExecutionState.completed:
    case SequenceExecutionState.failed:
      return true;
    case SequenceExecutionState.running:
    case SequenceExecutionState.paused:
    case SequenceExecutionState.stopping:
      return false;
  }
}

/// Editor StateNotifier for the sequence currently being authored.
///
/// Holds undo/redo stacks plus tree-mutation helpers. The notifier itself is
/// stateful but owns no streams or timers, so it does not require a dispose
/// override — Riverpod tears down the underlying state when the provider is
/// disposed.
///
/// Construction takes the owning [Ref] so mutating methods can read the
/// `sequenceExecutionStateProvider` and refuse edits while the run is active.
/// Pass `null` only in unit tests that never exercise the execution-state
/// gate; production wiring in `sequence_provider.dart` always passes a Ref.
class CurrentSequenceNotifier extends StateNotifier<Sequence?>
    with UndoBatchMixin {
  CurrentSequenceNotifier({Ref? ref})
      : _ref = ref,
        super(null);

  final Ref? _ref;
  final _undoStack = <Sequence>[];
  final _redoStack = <Sequence>[];

  /// True when the in-editor sequence has been mutated since the last
  /// load / create / explicit [markSaved] call. Used by [createSequence]
  /// and [loadSequence] to refuse to clobber unsaved work, and exposed
  /// publicly via [isDirty] so the UI can show a "*" on the title bar.
  ///
  /// Why a separate flag instead of comparing the current sequence to the
  /// last-saved snapshot: snapshots would have to be deep copies (Sequence
  /// is immutable but its nodes map is a fresh Map each mutation), and
  /// would double the editor's memory footprint for a feature the user
  /// experiences as a binary. A flag is also robust against renames /
  /// reorderings that produce structurally-different sequences that the
  /// user considers "saved" (because they just hit Save).
  bool _dirty = false;

  /// Whether the in-editor sequence has unsaved changes since the last
  /// save (or since it was loaded fresh). UI may surface this via title-
  /// bar indicators or by gating destructive nav actions.
  bool get isDirty => _dirty;

  /// Mark the in-editor sequence as saved. Called by:
  ///   * [SequenceRepository] write paths (manual Save button, OK in
  ///     property dialogs that persist directly).
  ///   * [AutoSaveService] after a successful auto-save tick.
  ///   * [SequenceFileService.exportSequence] after a successful export.
  /// After this returns, [isDirty] is `false` and [createSequence] /
  /// [loadSequence] will not throw [UnsavedChangesException].
  void markSaved() {
    _dirty = false;
  }

  @override
  List<Sequence> get undoStack => _undoStack;

  @override
  List<Sequence> get redoStack => _redoStack;

  @override
  Sequence? get currentState => state;

  /// Wrap a multi-step edit so all internal `_saveUndo()` calls collapse into
  /// one undo entry. Exposed publicly so callers performing batched edits
  /// (e.g. drag-drop of a snippet, "apply mosaic plan") can opt in.
  T withUndoGroup<T>(T Function() action) => withUndoBatch(action);

  void _saveUndo() {
    // Every mutation that takes an undo snapshot is by definition a
    // dirtying event. Flip the flag here instead of in every call site so
    // we can't forget — and so the dirty-tracking and undo invariants
    // stay in lockstep.
    _dirty = true;
    saveUndo();
  }

  /// Guard mutating operations against being called while the sequence is
  /// running. Throws [SequenceLockedException] when blocked.
  ///
  /// When constructed without a [Ref] (test fixtures), no guard is enforced —
  /// the test is responsible for asserting state directly.
  void _ensureEditable(String operationDescription) {
    final ref = _ref;
    if (ref == null) return;
    final execState = ref.read(sequenceExecutionStateProvider);
    if (!_isEditable(execState)) {
      throw SequenceLockedException(
        attemptedOperation: operationDescription,
        executionState: execState,
      );
    }
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Roll back the last mutation.
  ///
  /// Gated by [_ensureEditable] — calling `undo()` while a sequence is
  /// Running / Paused / Stopping would rewind Dart-side state while the
  /// native executor keeps marching through the *old* tree, producing the
  /// most pernicious class of split-brain bug imaginable. The notifier
  /// refuses to do that even though the UI also disables Ctrl+Z and the
  /// undo button via [canEditSequenceProvider].
  void undo() {
    _ensureEditable('undo');
    if (_undoStack.isEmpty) return;
    if (state != null) {
      _redoStack.add(state!);
    }
    state = _undoStack.removeLast();
  }

  /// Re-apply the last undone mutation. Same trust-patch reasoning as
  /// [undo] — see that doc.
  void redo() {
    _ensureEditable('redo');
    if (_redoStack.isEmpty) return;
    if (state != null) {
      _undoStack.add(state!);
    }
    state = _redoStack.removeLast();
  }

  /// Create a new sequence.
  ///
  /// If the current sequence has unsaved edits ([isDirty]), throws
  /// [UnsavedChangesException] unless [discardUnsaved] is true. UI
  /// callers should catch the exception, prompt "Discard unsaved
  /// changes?", and retry with `discardUnsaved: true` on confirm.
  void createSequence({
    String name = 'New Sequence',
    bool discardUnsaved = false,
  }) {
    _ensureEditable('create sequence');
    _guardUnsavedClobber(
      attemptedOperation: 'create a new sequence',
      discardUnsaved: discardUnsaved,
    );
    _saveUndo();

    final rootId = const Uuid().v4();
    final rootNode = InstructionSetNode(
      id: rootId,
      name: 'Sequence',
    );

    state = Sequence(
      name: name,
      nodes: {rootId: rootNode},
      rootNodeId: rootId,
    );
    // A brand-new blank sequence has no on-disk counterpart so it is
    // "dirty from birth" — saving will create the row. We still reset
    // the flag here so the prompt doesn't fire on a freshly-created
    // sequence; the next mutation will dirty it again.
    _dirty = false;
  }

  /// Load an existing sequence into the editor.
  ///
  /// If the current sequence has unsaved edits ([isDirty]), throws
  /// [UnsavedChangesException] unless [discardUnsaved] is true. Used by
  /// the import flow, library-open path, and recently-opened menu.
  void loadSequence(Sequence sequence, {bool discardUnsaved = false}) {
    _guardUnsavedClobber(
      attemptedOperation: 'open another sequence',
      discardUnsaved: discardUnsaved,
    );
    _undoStack.clear();
    _redoStack.clear();
    state = sequence;
    // Loaded from disk → considered clean.
    _dirty = false;
  }

  /// Clear the current sequence
  void clearSequence({bool discardUnsaved = false}) {
    _guardUnsavedClobber(
      attemptedOperation: 'clear the sequence',
      discardUnsaved: discardUnsaved,
    );
    _undoStack.clear();
    _redoStack.clear();
    state = null;
    _dirty = false;
  }

  void _guardUnsavedClobber({
    required String attemptedOperation,
    required bool discardUnsaved,
  }) {
    if (discardUnsaved) return;
    if (!_dirty) return;
    final current = state;
    if (current == null) return;
    throw UnsavedChangesException(
      attemptedOperation: attemptedOperation,
      currentSequenceName: current.name,
    );
  }

  /// Update sequence name
  void setName(String name) {
    if (state == null) return;
    _ensureEditable('rename sequence');
    _saveUndo();
    state = state!.copyWith(
      name: name,
      modifiedAt: DateTime.now(),
    );
  }

  /// Update sequence description
  void setDescription(String description) {
    if (state == null) return;
    _ensureEditable('edit description');
    _saveUndo();
    state = state!.copyWith(
      description: description,
      modifiedAt: DateTime.now(),
    );
  }

  /// Add a node to the sequence
  void addNode(SequenceNode node, {String? parentId, int? index}) {
    if (state == null) return;
    _ensureEditable('add node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
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
    } else if (state!.rootNodeId != null) {
      final root = newNodes[state!.rootNodeId!]!;
      final newChildIds = List<String>.from(root.childIds);

      if (index != null && index >= 0 && index <= newChildIds.length) {
        newChildIds.insert(index, node.id);
      } else {
        newChildIds.add(node.id);
      }

      newNodes[state!.rootNodeId!] = root.copyWith(childIds: newChildIds);
      newNodes[node.id] = node.copyWith(
        parentId: state!.rootNodeId,
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

    state = state!.copyWith(
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
    if (state == null) {
      throw NoActiveSequenceException(
        attemptedOperation:
            'add target "${targetNode.targetName}"',
      );
    }
    _ensureEditable('add target');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final rootNodeId = state!.rootNodeId;
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

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Merge template nodes into an existing target.
  /// If targetId is null, merges into the first target found, or directly to root.
  /// The template's root node children are added as children of the target.
  void mergeTemplateNodes({
    required Map<String, SequenceNode> templateNodes,
    required String? templateRootId,
    String? targetId,
  }) {
    if (state == null) return;
    if (templateRootId == null) return;
    _ensureEditable('merge template');
    // Single undo entry for the whole merge — the helper writes the new
    // state map atomically below, but a future refactor that splits the
    // write into per-node updates will still be correctly coalesced.
    withUndoBatch(() {
      _saveUndo();
      _mergeTemplateNodesImpl(
        templateNodes: templateNodes,
        templateRootId: templateRootId,
        targetId: targetId,
      );
    });
  }

  void _mergeTemplateNodesImpl({
    required Map<String, SequenceNode> templateNodes,
    required String templateRootId,
    String? targetId,
  }) {

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final idMapping = <String, String>{};

    for (final entry in templateNodes.entries) {
      idMapping[entry.key] = const Uuid().v4();
    }

    String? mergeParentId = targetId;
    if (mergeParentId == null) {
      for (final node in newNodes.values) {
        if (node is TargetHeaderNode) {
          mergeParentId = node.id;
          break;
        }
      }
    }
    mergeParentId ??= state!.rootNodeId;
    if (mergeParentId == null) return;

    final mergeParent = newNodes[mergeParentId];
    if (mergeParent == null) return;

    final templateRoot = templateNodes[templateRootId];
    if (templateRoot == null) return;

    final childIdsToAdd = <String>[];

    for (final entry in templateNodes.entries) {
      if (entry.key == templateRootId) continue;

      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;

      String? newParentId;
      if (oldNode.parentId == templateRootId) {
        // Direct child of template root -> becomes child of merge target
        newParentId = mergeParentId;
        childIdsToAdd.add(newId);
      } else if (oldNode.parentId != null) {
        newParentId = idMapping[oldNode.parentId];
      }

      final newChildIds =
          oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    final existingChildCount = mergeParent.childIds.length;
    final updatedChildIds = List<String>.from(mergeParent.childIds)
      ..addAll(childIdsToAdd);
    newNodes[mergeParentId] = mergeParent.copyWith(childIds: updatedChildIds);

    for (int i = 0; i < childIdsToAdd.length; i++) {
      final childId = childIdsToAdd[i];
      if (newNodes.containsKey(childId)) {
        newNodes[childId] = newNodes[childId]!.copyWith(
          orderIndex: existingChildCount + i,
        );
      }
    }

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Insert a template snippet into the sequence.
  /// The snippet's nodes are deserialized and inserted at the specified parent,
  /// or the currently selected node if no parent is specified.
  ///
  /// Throws [SnippetDeserializationException] if any node in the snippet
  /// carries a `nodeType` value the editor does not recognize. The whole
  /// insertion is rejected (undo entry is still pushed; state is unchanged).
  void insertSnippet(
    TemplateSnippet snippet, {
    String? parentId,
    int? index,
    List<String>? profileFilterNames,
  }) {
    if (state == null) return;
    if (snippet.nodeData.isEmpty) return;
    _ensureEditable('insert snippet');
    // Single undo entry for the whole multi-node insertion.
    withUndoBatch(() {
      _saveUndo();
      _insertSnippetImpl(
        snippet,
        parentId: parentId,
        index: index,
        profileFilterNames: profileFilterNames,
      );
    });
  }

  void _insertSnippetImpl(
    TemplateSnippet snippet, {
    String? parentId,
    int? index,
    List<String>? profileFilterNames,
  }) {
    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final idMapping = <String, String>{};
    final createdNodes = <SequenceNode>[];

    String? insertParentId = parentId;
    if (insertParentId != null) {
      final parentNode = newNodes[insertParentId];
      if (parentNode != null && !_canHaveChildren(parentNode)) {
        // Substitute the parent's parent — keeps the insertion semantically
        // attached to a valid container instead of dropping it on a leaf.
        insertParentId = parentNode.parentId;
      }
    }

    insertParentId ??= state!.rootNodeId;
    if (insertParentId == null) {
      // Create root if sequence is empty
      final rootNode = InstructionSetNode(name: 'Sequence Root');
      newNodes[rootNode.id] = rootNode;
      insertParentId = rootNode.id;
    }

    final insertParent = newNodes[insertParentId];
    if (insertParent == null) return;

    SequenceNode deserializeNodeData(
      Map<String, dynamic> json, {
      String? parentIdOverride,
      int orderIdx = 0,
    }) {
      final originalId = json['id'] as String? ?? const Uuid().v4();
      final newId = const Uuid().v4();
      idMapping[originalId] = newId;

      final childrenJson = json['children'] as List<dynamic>? ?? [];
      final childNodes = <SequenceNode>[];
      for (int i = 0; i < childrenJson.length; i++) {
        final childJson = childrenJson[i] as Map<String, dynamic>;
        final childNode = deserializeNodeData(
          childJson,
          parentIdOverride: newId,
          orderIdx: i,
        );
        childNodes.add(childNode);
      }
      final childIds = childNodes.map((n) => n.id).toList();

      final nodeJson = Map<String, dynamic>.from(json);
      nodeJson['id'] = newId;
      nodeJson['parentId'] = parentIdOverride;
      nodeJson['childIds'] = childIds;
      nodeJson['orderIndex'] = orderIdx;
      // Remove children from JSON — already processed into childIds.
      nodeJson.remove('children');

      final node = _deserializeSnippetNode(nodeJson, snippetName: snippet.name);
      createdNodes.add(node);
      return node;
    }

    final topLevelNodeIds = <String>[];
    final existingChildCount = insertParent.childIds.length;
    final insertIdx = index ?? existingChildCount;

    for (int i = 0; i < snippet.nodeData.length; i++) {
      final nodeJson = snippet.nodeData[i];
      final node = deserializeNodeData(
        nodeJson,
        parentIdOverride: insertParentId,
        orderIdx: insertIdx + i,
      );
      topLevelNodeIds.add(node.id);
    }

    developer.log(
        'insertSnippet: profileFilterNames=$profileFilterNames, createdNodes=${createdNodes.length}',
        name: 'Sequence');
    if (profileFilterNames != null && profileFilterNames.isNotEmpty) {
      for (int i = 0; i < createdNodes.length; i++) {
        final node = createdNodes[i];
        if (node is ExposureNode &&
            node.filter != null &&
            node.filter!.isNotEmpty) {
          final matchedIndex =
              _matchFilterToProfile(node.filter!, profileFilterNames);
          if (matchedIndex != null) {
            createdNodes[i] = node.copyWith(
              filter: profileFilterNames[matchedIndex],
              filterIndex: matchedIndex,
            );
            developer.log(
                'insertSnippet: Mapped filter "${node.filter}" -> "${profileFilterNames[matchedIndex]}" (index $matchedIndex)',
                name: 'Sequence');
          }
        } else if (node is FilterChangeNode) {
          final matchedIndex =
              _matchFilterToProfile(node.filterName, profileFilterNames);
          if (matchedIndex != null) {
            createdNodes[i] = node.copyWith(
              filterName: profileFilterNames[matchedIndex],
              filterPosition: matchedIndex,
            );
          }
        }
      }
    }

    for (final node in createdNodes) {
      newNodes[node.id] = node;
    }

    final newChildIds = List<String>.from(insertParent.childIds);
    newChildIds.insertAll(insertIdx, topLevelNodeIds);

    for (int i = insertIdx + topLevelNodeIds.length;
        i < newChildIds.length;
        i++) {
      final childId = newChildIds[i];
      if (newNodes.containsKey(childId)) {
        newNodes[childId] = newNodes[childId]!.copyWith(orderIndex: i);
      }
    }

    newNodes[insertParentId] = insertParent.copyWith(childIds: newChildIds);

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Check if a node type can have children.
  ///
  /// `SequenceNode` is sealed, so every concrete subtype must be classified
  /// below — a new node type will produce a compile-time error here.
  bool _canHaveChildren(SequenceNode node) {
    return switch (node) {
      TargetHeaderNode _ ||
      LoopNode _ ||
      InstructionSetNode _ ||
      ParallelNode _ ||
      ConditionalNode _ ||
      RecoveryNode _ =>
        true,
      ExposureNode _ ||
      SlewNode _ ||
      CenterNode _ ||
      AutofocusNode _ ||
      DitherNode _ ||
      StartGuidingNode _ ||
      StopGuidingNode _ ||
      FilterChangeNode _ ||
      CoolCameraNode _ ||
      WarmCameraNode _ ||
      RotatorNode _ ||
      ParkNode _ ||
      UnparkNode _ ||
      WaitTimeNode _ ||
      DelayNode _ ||
      NotificationNode _ ||
      ScriptNode _ ||
      MeridianFlipNode _ ||
      OpenDomeNode _ ||
      CloseDomeNode _ ||
      ParkDomeNode _ ||
      PolarAlignmentNode _ ||
      OpenCoverNode _ ||
      CloseCoverNode _ ||
      CalibratorOnNode _ ||
      CalibratorOffNode _ =>
        false,
    };
  }

  /// Deserialize a single node from snippet JSON data.
  ///
  /// [snippetName] is propagated into [SnippetDeserializationException] so
  /// the user can identify which snippet referenced the bad node type.
  SequenceNode _deserializeSnippetNode(
    Map<String, dynamic> json, {
    required String snippetName,
  }) {
    final rawType = json['nodeType'] as String?;
    if (rawType == null || rawType.trim().isEmpty) {
      throw SnippetDeserializationException(
        unknownType: '<missing>',
        snippetName: snippetName,
      );
    }

    final nodeType = rawType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final id = json['id'] as String? ?? const Uuid().v4();
    final name = json['name'] as String?;
    final parentId = json['parentId'] as String?;
    final childIds =
        (json['childIds'] as List<dynamic>?)?.cast<String>() ?? const [];
    final orderIndex = (json['orderIndex'] as num?)?.toInt() ?? 0;
    final isEnabled = json['isEnabled'] as bool? ?? false;

    switch (nodeType) {
      case 'targetheader':
      case 'targetgroup':
        return TargetHeaderNode(
          id: id,
          name: name ?? 'Target',
          targetName: json['targetName'] as String? ?? 'Target',
          raHours: (json['raHours'] as num?)?.toDouble() ?? 0.0,
          decDegrees: (json['decDegrees'] as num?)?.toDouble() ?? 0.0,
          rotation: (json['rotation'] as num?)?.toDouble(),
          priority: (json['priority'] as num?)?.toInt() ?? 0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'loop':
        return LoopNode(
          id: id,
          name: name ?? 'Loop',
          conditionType: _parseLoopType(json['conditionType']),
          repeatCount: (json['repeatCount'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'parallel':
        return ParallelNode(
          id: id,
          name: name ?? 'Parallel',
          requiredSuccesses: (json['requiredSuccesses'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'conditional':
        return ConditionalNode(
          id: id,
          name: name ?? 'Conditional',
          conditionType: _parseConditionType(json['conditionType']),
          thresholdValue: (json['thresholdValue'] as num?)?.toDouble(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'recovery':
        return RecoveryNode(
          id: id,
          name: name ?? 'Recovery',
          recoveryAction: _parseRecoveryAction(json['recoveryAction']),
          maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 3,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'instructionset':
        return InstructionSetNode(
          id: id,
          name: name ?? 'Instructions',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'slewtotarget':
      case 'slew':
        return SlewNode(
          id: id,
          name: name ?? 'Slew to Target',
          useTargetCoords: json['useTargetCoords'] as bool? ?? false,
          customRa: (json['customRa'] as num?)?.toDouble(),
          customDec: (json['customDec'] as num?)?.toDouble(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'centertarget':
      case 'center':
        return CenterNode(
          id: id,
          name: name ?? 'Center Target',
          useTargetCoords: json['useTargetCoords'] as bool? ?? false,
          accuracyArcsec: (json['accuracyArcsec'] as num?)?.toDouble() ?? 5.0,
          maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 5,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'takeexposure':
      case 'exposure':
        return ExposureNode(
          id: id,
          name: name ?? 'Take Exposures',
          durationSecs: (json['durationSecs'] as num?)?.toDouble() ?? 60.0,
          count: (json['count'] as num?)?.toInt() ?? 10,
          frameType: _parseFrameTypeForSnippet(json['frameType']),
          filter: json['filter'] as String?,
          filterIndex: (json['filterIndex'] as num?)?.toInt(),
          gain: (json['gain'] as num?)?.toInt(),
          offset: (json['offset'] as num?)?.toInt(),
          binning: _parseBinningForSnippet(json['binning']),
          ditherEvery: (json['ditherEvery'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'autofocus':
        return AutofocusNode(
          id: id,
          name: name ?? 'Autofocus',
          method: _parseAutofocusMethodForSnippet(json['method']),
          stepSize: (json['stepSize'] as num?)?.toInt() ?? 100,
          stepsOut: (json['stepsOut'] as num?)?.toInt() ?? 7,
          exposuresPerPoint: (json['exposuresPerPoint'] as num?)?.toInt() ?? 1,
          exposureDuration:
              (json['exposureDuration'] as num?)?.toDouble() ?? 3.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'dither':
        return DitherNode(
          id: id,
          name: name ?? 'Dither',
          pixels: (json['pixels'] as num?)?.toDouble() ?? 5.0,
          settlePixels: (json['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 30.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'startguiding':
        return StartGuidingNode(
          id: id,
          name: name ?? 'Start Guiding',
          settlePixels: (json['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 10.0,
          settleTimeout: (json['settleTimeout'] as num?)?.toDouble() ?? 60.0,
          autoSelectStar: json['autoSelectStar'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'stopguiding':
        return StopGuidingNode(
          id: id,
          name: name ?? 'Stop Guiding',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'changefilter':
      case 'filterchange':
        return FilterChangeNode(
          id: id,
          name: name ?? 'Change Filter',
          filterName:
              json['filterName'] as String? ?? json['filter'] as String? ?? 'L',
          filterPosition: (json['filterPosition'] as num?)?.toInt() ??
              (json['filterIndex'] as num?)?.toInt(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'coolcamera':
        return CoolCameraNode(
          id: id,
          name: name ?? 'Cool Camera',
          targetTemp: (json['targetTemp'] as num?)?.toDouble() ?? -10.0,
          durationMins: (json['durationMins'] as num?)?.toDouble(),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'warmcamera':
        return WarmCameraNode(
          id: id,
          name: name ?? 'Warm Camera',
          ratePerMin: (json['ratePerMin'] as num?)?.toDouble() ?? 5.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'park':
        return ParkNode(
          id: id,
          name: name ?? 'Park Mount',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'unpark':
        return UnparkNode(
          id: id,
          name: name ?? 'Unpark Mount',
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'meridianflip':
        return MeridianFlipNode(
          id: id,
          name: name ?? 'Meridian Flip',
          minutesPastMeridian:
              (json['minutesPastMeridian'] as num?)?.toDouble() ?? 5.0,
          pauseGuiding: json['pauseGuiding'] as bool? ?? false,
          autoCenter: json['autoCenter'] as bool? ?? false,
          settleTime: (json['settleTime'] as num?)?.toDouble() ?? 10.0,
          // Why: legacy JSON has no flag; pin values verbatim (audit §1.2).
          useGlobalDefaults: json['useGlobalDefaults'] as bool? ?? false,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'delay':
        return DelayNode(
          id: id,
          name: name ?? 'Delay',
          seconds: (json['seconds'] as num?)?.toDouble() ?? 0.0,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      case 'notification':
        return NotificationNode(
          id: id,
          name: name ?? 'Notification',
          title: json['title'] as String? ?? 'Notification',
          message: json['message'] as String? ?? '',
          level: _parseNotificationLevel(json['level']),
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
        );

      default:
        // Unknown discriminator — fail loudly so the importer can surface
        // a meaningful error to the user instead of silently dropping
        // unrelated nodes into the tree as empty containers.
        throw SnippetDeserializationException(
          unknownType: rawType,
          snippetName: snippetName,
        );
    }
  }

  LoopConditionType _parseLoopType(dynamic value) {
    if (value == null) return LoopConditionType.count;
    final str = value.toString().toLowerCase();
    return LoopConditionType.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => LoopConditionType.count,
    );
  }

  ConditionalType _parseConditionType(dynamic value) {
    if (value == null) return ConditionalType.weatherSafe;
    final str = value.toString().toLowerCase();
    return ConditionalType.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => ConditionalType.weatherSafe,
    );
  }

  RecoveryActionType _parseRecoveryAction(dynamic value) {
    if (value == null) return RecoveryActionType.retry;
    final str = value.toString().toLowerCase();
    return RecoveryActionType.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => RecoveryActionType.retry,
    );
  }

  FrameType _parseFrameTypeForSnippet(dynamic value) {
    if (value == null) return FrameType.light;
    final str = value.toString().toLowerCase();
    return FrameType.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => FrameType.light,
    );
  }

  BinningMode _parseBinningForSnippet(dynamic value) {
    if (value == null) return BinningMode.one;
    final str = value.toString().toLowerCase();
    return BinningMode.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => BinningMode.one,
    );
  }

  AutofocusMethod _parseAutofocusMethodForSnippet(dynamic value) {
    if (value == null) return AutofocusMethod.vCurve;
    final str = value.toString().toLowerCase();
    return AutofocusMethod.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => AutofocusMethod.vCurve,
    );
  }

  NotificationLevel _parseNotificationLevel(dynamic value) {
    if (value == null) return NotificationLevel.info;
    final str = value.toString().toLowerCase();
    return NotificationLevel.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => NotificationLevel.info,
    );
  }

  /// Common abbreviation map for filter name matching.
  /// Maps normalized template names to possible profile name patterns.
  static const _filterAbbreviations = <String, List<String>>{
    'l': ['lum', 'luminance', 'luminosity', 'clear'],
    'r': ['red'],
    'g': ['green'],
    'b': ['blue'],
    'ha': ['halpha', 'h-alpha', 'h_alpha', 'hydrogen', 'hydrogen-alpha'],
    'oiii': ['o3', 'oxygen', 'oxygeniii'],
    'sii': ['s2', 'sulfur', 'sulphur', 'sulfurii'],
    'nii': ['n2', 'nitrogen', 'nitrogenii'],
  };

  /// Try to match a template filter name to one of the profile filter names.
  /// Returns the matched index (0-based) or null if no match found.
  int? _matchFilterToProfile(String templateFilter, List<String> profileNames) {
    final templateLower = templateFilter.toLowerCase().trim();
    if (templateLower.isEmpty) return null;

    // Pass 1: Exact match (case-insensitive)
    for (int i = 0; i < profileNames.length; i++) {
      if (profileNames[i].toLowerCase().trim() == templateLower) return i;
    }

    // Pass 2: Profile name starts with template name (e.g. "L" matches "Lum")
    for (int i = 0; i < profileNames.length; i++) {
      final profileLower = profileNames[i].toLowerCase().trim();
      if (profileLower.startsWith(templateLower)) return i;
    }

    // Pass 3: Template name starts with profile name (e.g. "Luminance" matches "Lum")
    for (int i = 0; i < profileNames.length; i++) {
      final profileLower = profileNames[i].toLowerCase().trim();
      if (templateLower.startsWith(profileLower) && profileLower.isNotEmpty) {
        return i;
      }
    }

    // Pass 4: Known abbreviation matching
    final knownAliases = _filterAbbreviations[templateLower];
    if (knownAliases != null) {
      for (int i = 0; i < profileNames.length; i++) {
        final profileLower = profileNames[i].toLowerCase().trim();
        for (final alias in knownAliases) {
          if (profileLower == alias ||
              profileLower.startsWith(alias) ||
              alias.startsWith(profileLower)) {
            return i;
          }
        }
      }
    }

    // Pass 5: Reverse — match abbreviation aliases against profile names.
    for (final entry in _filterAbbreviations.entries) {
      for (final alias in entry.value) {
        if (alias == templateLower || templateLower.startsWith(alias)) {
          for (int i = 0; i < profileNames.length; i++) {
            final profileLower = profileNames[i].toLowerCase().trim();
            if (profileLower.startsWith(entry.key) ||
                entry.key.startsWith(profileLower)) {
              return i;
            }
          }
        }
      }
    }

    return null;
  }

  /// Remove a node from the sequence.
  ///
  /// Removes the node and its entire subtree. The editor does not gate this
  /// on descendant count — confirmation dialogs are the UI's responsibility
  /// (see [Sequence.countDescendants]).
  void removeNode(String nodeId) {
    if (state == null) return;
    _ensureEditable('remove node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
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

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Update a node
  void updateNode(SequenceNode node) {
    if (state == null) return;
    _ensureEditable('update node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    newNodes[node.id] = node;

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Toggle node enabled state
  void toggleNodeEnabled(String nodeId) {
    if (state == null) return;
    // No _ensureEditable here — updateNode below performs the guard.
    final node = state!.nodes[nodeId];
    if (node == null) return;

    updateNode(node.copyWith(isEnabled: !node.isEnabled));
  }

  /// Reorder nodes within a parent
  void reorderNodes(String parentId, int oldIndex, int newIndex) {
    if (state == null) return;
    _ensureEditable('reorder nodes');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final parent = newNodes[parentId];
    if (parent == null) return;

    final children = List<String>.from(parent.childIds);

    for (final childId in children) {
      if (!newNodes.containsKey(childId)) {
        throw StateError('Reorder failed: node $childId not found');
      }
    }

    final item = children.removeAt(oldIndex);
    children.insert(newIndex, item);

    for (int i = 0; i < children.length; i++) {
      final child = newNodes[children[i]]!;
      newNodes[children[i]] = child.copyWith(orderIndex: i);
    }

    newNodes[parentId] = parent.copyWith(childIds: children);

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Move a node to a different parent
  void moveNode(String nodeId, String newParentId, int index) {
    if (state == null) return;
    _ensureEditable('move node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
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

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Duplicate a node
  void duplicateNode(String nodeId) {
    if (state == null) return;
    final node = state!.nodes[nodeId];
    if (node == null) return;

    _ensureEditable('duplicate node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);

    SequenceNode duplicateRecursive(
        SequenceNode original, String? newParentId) {
      final newId = const Uuid().v4();
      final newChildIds = <String>[];

      for (final childId in original.childIds) {
        final child = state!.nodes[childId];
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

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Wrap all children of a node into a new container node
  void wrapChildren(String parentId, SequenceNode wrapper) {
    if (state == null) return;
    final parent = state!.nodes[parentId];
    if (parent == null) return;

    _ensureEditable('wrap children');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
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

    state = state!.copyWith(
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
    if (state == null) return;
    if (childIds.isEmpty) return;
    final parent = state!.nodes[parentId];
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

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);

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

    state = state!.copyWith(
      nodes: newNodes,
      modifiedAt: DateTime.now(),
    );
  }

  /// Wrap a specific node into a new container node
  void wrapNode(String nodeId, SequenceNode wrapper) {
    if (state == null) return;
    final node = state!.nodes[nodeId];
    if (node == null) return;
    final parentId = node.parentId;
    if (parentId == null) return; // Cannot wrap root

    final parent = state!.nodes[parentId];
    if (parent == null) return;

    _ensureEditable('wrap node');
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);

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

    state = state!.copyWith(
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
    if (state == null) return;
    // _ensureEditable runs implicitly through reorderNodes below; we also
    // check upfront so the ambiguity exception (CrossParent) doesn't
    // mask a SequenceLockedException for the same call.
    _ensureEditable('reorder targets');

    final targets = state!.targetHeaders;
    if (oldIndex < 0 || oldIndex >= targets.length) return;

    // Flutter ReorderableListView reports newIndex as the post-removal slot;
    // adjust so we can index into the unchanged list.
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= targets.length) return;

    final oldTarget = targets[oldIndex];
    final newTarget = targets[newIndex];

    final sameSiblingParent = oldTarget.parentId == newTarget.parentId &&
        oldTarget.parentId != null;
    if (!sameSiblingParent) {
      throw CrossParentReorderException(
        sourceTargetName: oldTarget.targetName,
        destinationTargetName: newTarget.targetName,
      );
    }

    final parentId = oldTarget.parentId!;
    final parent = state!.nodes[parentId];
    if (parent == null) return;

    // Find actual indices in the parent's child list (may contain non-targets)
    final oldChildIndex = parent.childIds.indexOf(oldTarget.id);
    final newChildIndex = parent.childIds.indexOf(newTarget.id);

    if (oldChildIndex != -1 && newChildIndex != -1) {
      reorderNodes(parentId, oldChildIndex, newChildIndex);
    }
  }
}
