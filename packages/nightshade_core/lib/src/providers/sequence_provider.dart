import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import '../models/sequence/sequence_models.dart';
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart';
import '../models/settings/app_settings.dart' show ObserverLocation;
import 'equipment_provider.dart';
import 'database_provider.dart';
import 'profiles_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';
import 'imaging_provider.dart';
import '../services/imaging_service.dart';
import '../services/device_service.dart';
import 'backend_provider.dart';
import '../backend/nightshade_backend.dart';

// =============================================================================
// VALIDATION
// =============================================================================

/// Severity of a validation issue
enum ValidationSeverity { error, warning }

/// A validation issue found in a sequence
class SequenceValidationIssue {
  final ValidationSeverity severity;
  final String message;
  final String? nodeId;

  const SequenceValidationIssue({
    required this.severity,
    required this.message,
    this.nodeId,
  });
}

// =============================================================================
// EXECUTION STATE
// =============================================================================

/// Current sequence execution state
final sequenceExecutionStateProvider = StateProvider<SequenceExecutionState>((ref) {
  return SequenceExecutionState.idle;
});

/// Current sequence progress
final sequenceProgressProvider = StateNotifierProvider<SequenceProgressNotifier, SequenceProgress>((ref) {
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

  void updateNodeProgress(String nodeId, double progressPercent, String detail) {
    final newProgressPercent = Map<String, double>.from(state.nodeProgressPercent);
    final newProgressDetail = Map<String, String>.from(state.nodeProgressDetail);

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

/// Current sequence being edited
final currentSequenceProvider = StateNotifierProvider<CurrentSequenceNotifier, Sequence?>((ref) {
  return CurrentSequenceNotifier();
});

class CurrentSequenceNotifier extends StateNotifier<Sequence?> {
  CurrentSequenceNotifier() : super(null);

  final _undoStack = <Sequence>[];
  final _redoStack = <Sequence>[];

  void _saveUndo() {
    if (state != null) {
      _undoStack.add(state!);
      _redoStack.clear();
      // Limit undo stack
      if (_undoStack.length > 50) {
        _undoStack.removeAt(0);
      }
    }
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    if (state != null) {
      _redoStack.add(state!);
    }
    state = _undoStack.removeLast();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    if (state != null) {
      _undoStack.add(state!);
    }
    state = _redoStack.removeLast();
  }

  /// Create a new sequence
  void createSequence({String name = 'New Sequence'}) {
    _saveUndo();
    
    // Create a root sequence node
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
  }

  /// Load an existing sequence
  void loadSequence(Sequence sequence) {
    _undoStack.clear();
    _redoStack.clear();
    state = sequence;
  }

  /// Clear the current sequence
  void clearSequence() {
    _undoStack.clear();
    _redoStack.clear();
    state = null;
  }

  /// Update sequence name
  void setName(String name) {
    if (state == null) return;
    _saveUndo();
    state = state!.copyWith(
      name: name,
      modifiedAt: DateTime.now(),
    );
  }

  /// Update sequence description
  void setDescription(String description) {
    if (state == null) return;
    _saveUndo();
    state = state!.copyWith(
      description: description,
      modifiedAt: DateTime.now(),
    );
  }

  /// Add a node to the sequence
  void addNode(SequenceNode node, {String? parentId, int? index}) {
    if (state == null) return;
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    newNodes[node.id] = node;

    // If parent specified, add to parent's children
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
      
      // Update order indices for following siblings if inserted
      if (index != null) {
        for (int i = index + 1; i < newChildIds.length; i++) {
          final childId = newChildIds[i];
          if (newNodes.containsKey(childId)) {
            newNodes[childId] = newNodes[childId]!.copyWith(orderIndex: i);
          }
        }
      }
    } else if (state!.rootNodeId != null) {
      // Add to root if no parent specified
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
      
      // Update order indices for following siblings if inserted
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
  /// If no sequence exists, one will be created automatically so that targets
  /// can be added from anywhere without requiring the sequencer tab to be opened first.
  void addTargetHeader(TargetHeaderNode targetNode) {
    // Auto-create a sequence if one doesn't exist
    if (state == null) {
      createSequence();
    }
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final rootNodeId = state!.rootNodeId;
    if (rootNodeId == null) return;

    final root = newNodes[rootNodeId];
    if (root == null) return;

    // Find orphan instructions (children of root that are NOT targets)
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

    // Create the target node with orphans as children
    final targetWithChildren = targetNode.copyWith(
      parentId: rootNodeId,
      childIds: orphanIds,
      orderIndex: remainingRootChildren.length,
    );
    newNodes[targetNode.id] = targetWithChildren;

    // Update orphans to have the target as their parent
    for (int i = 0; i < orphanIds.length; i++) {
      final orphanId = orphanIds[i];
      if (newNodes.containsKey(orphanId)) {
        newNodes[orphanId] = newNodes[orphanId]!.copyWith(
          parentId: targetNode.id,
          orderIndex: i,
        );
      }
    }

    // Add target to root's children
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
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final idMapping = <String, String>{};

    // Generate new IDs for all template nodes
    for (final entry in templateNodes.entries) {
      idMapping[entry.key] = const Uuid().v4();
    }

    // Find the target to merge into
    String? mergeParentId = targetId;
    if (mergeParentId == null) {
      // Find first target header
      for (final node in newNodes.values) {
        if (node is TargetHeaderNode) {
          mergeParentId = node.id;
          break;
        }
      }
    }
    // Fallback to root if no target found
    mergeParentId ??= state!.rootNodeId;
    if (mergeParentId == null) return;

    final mergeParent = newNodes[mergeParentId];
    if (mergeParent == null) return;

    // Get the template root's children (skip the root itself)
    final templateRoot = templateNodes[templateRootId];
    if (templateRoot == null) return;

    final childIdsToAdd = <String>[];

    // Clone template nodes with new IDs (excluding the template root)
    for (final entry in templateNodes.entries) {
      if (entry.key == templateRootId) continue; // Skip the template root

      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;

      // Determine new parent
      String? newParentId;
      if (oldNode.parentId == templateRootId) {
        // Direct child of template root -> becomes child of merge target
        newParentId = mergeParentId;
        childIdsToAdd.add(newId);
      } else if (oldNode.parentId != null) {
        newParentId = idMapping[oldNode.parentId];
      }

      final newChildIds = oldNode.childIds
          .map((id) => idMapping[id] ?? id)
          .toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    // Update merge parent's children
    final existingChildCount = mergeParent.childIds.length;
    final updatedChildIds = List<String>.from(mergeParent.childIds)..addAll(childIdsToAdd);
    newNodes[mergeParentId] = mergeParent.copyWith(childIds: updatedChildIds);

    // Update order indices for the newly added children
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

  /// Remove a node from the sequence
  void removeNode(String nodeId) {
    if (state == null) return;
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final nodeToRemove = newNodes[nodeId];
    if (nodeToRemove == null) return;

    // Remove from parent's children
    if (nodeToRemove.parentId != null && newNodes.containsKey(nodeToRemove.parentId)) {
      final parent = newNodes[nodeToRemove.parentId!]!;
      final newChildIds = parent.childIds.where((id) => id != nodeId).toList();
      newNodes[nodeToRemove.parentId!] = parent.copyWith(childIds: newChildIds);
    }

    // Recursively remove children
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
    final node = state!.nodes[nodeId];
    if (node == null) return;
    
    updateNode(node.copyWith(isEnabled: !node.isEnabled));
  }

  /// Reorder nodes within a parent
  void reorderNodes(String parentId, int oldIndex, int newIndex) {
    if (state == null) return;
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final parent = newNodes[parentId];
    if (parent == null) return;

    final children = List<String>.from(parent.childIds);
    final item = children.removeAt(oldIndex);
    children.insert(newIndex, item);

    // Update order indices
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
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final node = newNodes[nodeId];
    if (node == null) return;

    // Remove from old parent
    if (node.parentId != null && newNodes.containsKey(node.parentId)) {
      final oldParent = newNodes[node.parentId!]!;
      final newChildIds = oldParent.childIds.where((id) => id != nodeId).toList();
      newNodes[node.parentId!] = oldParent.copyWith(childIds: newChildIds);
    }

    // Add to new parent
    final newParent = newNodes[newParentId];
    if (newParent == null) return;

    final newChildIds = List<String>.from(newParent.childIds);
    newChildIds.insert(index.clamp(0, newChildIds.length), nodeId);
    newNodes[newParentId] = newParent.copyWith(childIds: newChildIds);

    // Update node's parent
    newNodes[nodeId] = node.copyWith(parentId: newParentId, orderIndex: index);

    // Update order indices
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

    _saveUndo();
    
    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    
    // Create duplicate with new ID
    SequenceNode duplicateRecursive(SequenceNode original, String? newParentId) {
      final newId = const Uuid().v4();
      final newChildIds = <String>[];
      
      // Duplicate children first
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

    // Add to parent's children
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
    
    _saveUndo();
    
    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final originalChildren = List<String>.from(parent.childIds);
    
    // Create new wrapper with the children
    // Ensure we use a fresh ID and explicitly set children
    final newWrapper = wrapper.copyWith(
      id: const Uuid().v4(),
      childIds: originalChildren,
      parentId: parentId,
      orderIndex: 0,
    );
    
    newNodes[newWrapper.id] = newWrapper;
    
    // Update parent to point to wrapper instead of children
    newNodes[parentId] = parent.copyWith(childIds: [newWrapper.id]);
    
    // Update children to point to wrapper as parent
    for (final childId in originalChildren) {
      if (newNodes.containsKey(childId)) {
        newNodes[childId] = newNodes[childId]!.copyWith(parentId: newWrapper.id);
      }
    }
    
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
    
    _saveUndo();
    
    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    
    // Create wrapper containing the node
    final newWrapper = wrapper.copyWith(
      id: const Uuid().v4(),
      childIds: [nodeId],
      parentId: parentId,
      orderIndex: node.orderIndex,
    );
    newNodes[newWrapper.id] = newWrapper;
    
    // Update node parent
    newNodes[nodeId] = node.copyWith(parentId: newWrapper.id, orderIndex: 0);
    
    // Replace node in parent with wrapper
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

  /// Reorder target groups (helper for Targets tab)
  void reorderTargets(int oldIndex, int newIndex) {
    if (state == null) return;
    
    final targets = state!.targetGroups;
    if (oldIndex < 0 || oldIndex >= targets.length) return;
    
    // Handle flutter reorder index adjustment
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= targets.length) return;
    
    final oldTarget = targets[oldIndex];
    final newTarget = targets[newIndex];
    
    // Only support reordering if they are siblings (share same parent)
    if (oldTarget.parentId == newTarget.parentId && oldTarget.parentId != null) {
      final parentId = oldTarget.parentId!;
      final parent = state!.nodes[parentId];
      if (parent == null) return;
      
      // Find their actual indices in the parent's child list (which may contain non-targets)
      final oldChildIndex = parent.childIds.indexOf(oldTarget.id);
      final newChildIndex = parent.childIds.indexOf(newTarget.id);
      
      if (oldChildIndex != -1 && newChildIndex != -1) {
        reorderNodes(parentId, oldChildIndex, newChildIndex);
      }
    }
  }
}

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
// SEQUENCE EXECUTOR
// =============================================================================

/// Whether to use native execution.
/// Set to true once flutter_rust_bridge bindings are generated.
/// To enable:
/// 1. Run: flutter_rust_bridge_codegen generate
/// 2. Import the generated bindings
/// 3. Change this to true
///
/// The native executor provides:
/// - Real device control via ASCOM/Alpaca/INDI
/// - Proper PHD2 integration for guiding/dithering
/// - FITS image capture and saving
/// - Plate solving integration
/// - Event streaming from Rust to Dart

/// Sequence executor that manages execution
final sequenceExecutorProvider = Provider<SequenceExecutor>((ref) {
  return SequenceExecutor(ref);
});

class SequenceExecutor {
  final Ref _ref;
  Timer? _progressTimer;
  DateTime? _startTime;
  bool _isPaused = false;
  StreamSubscription? _nativeEventSubscription;
  Timer? _checkpointTimer;

  SequenceExecutor(this._ref);

  /// Check if native execution is enabled in settings
  bool get _useNativeExecution {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useNativeExecution ?? true;
    } catch (_) {
      return true; // Default to native execution
    }
  }

  /// Check if simulation mode is enabled in settings
  bool get _useSimulationMode {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useSimulationMode ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Convert Dart sequence to JSON for native executor
  String _sequenceToJson(Sequence sequence) {
    final nodeDefinitions = <Map<String, dynamic>>[];
    
    void processNode(SequenceNode node) {
      final Map<String, dynamic> nodeType = _nodeToConfig(node);
      
      nodeDefinitions.add({
        'id': node.id,
        'name': node.name,
        'node_type': nodeType,
        'enabled': node.isEnabled,
        'children': node.childIds,
      });
      
      // Process children
      for (final childId in node.childIds) {
        final child = sequence.nodes[childId];
        if (child != null) {
          processNode(child);
        }
      }
    }
    
    if (sequence.rootNode != null) {
      processNode(sequence.rootNode!);
    }
    
    return jsonEncode({
      'id': sequence.id,
      'name': sequence.name,
      'description': sequence.description,
      'nodes': nodeDefinitions,
      'root_node_id': sequence.rootNodeId,
      'metadata': {},
    });
  }
  
  /// Convert a Dart node to native config format
  Map<String, dynamic> _nodeToConfig(SequenceNode node) {
    if (node is ExposureNode) {
      return {
        'type': 'TakeExposure',
        'duration_secs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'gain': node.gain,
        'offset': node.offset,
        'binning': _binningToString(node.binning),
        'dither_every': node.ditherEvery,
        'save_to': null,
      };
    } else if (node is SlewNode) {
      return {
        'type': 'SlewToTarget',
        'use_target_coords': node.useTargetCoords,
        'custom_ra': node.customRa,
        'custom_dec': node.customDec,
      };
    } else if (node is CenterNode) {
      return {
        'type': 'CenterTarget',
        'use_target_coords': node.useTargetCoords,
        'accuracy_arcsec': node.accuracyArcsec,
        'max_attempts': node.maxAttempts,
        'exposure_duration': 3.0, // Default exposure for centering
        'filter': null,
      };
    } else if (node is AutofocusNode) {
      return {
        'type': 'Autofocus',
        'method': _autofocusMethodToString(node.method),
        'step_size': node.stepSize,
        'steps_out': node.stepsOut,
        'exposure_duration': node.exposureDuration,
        'filter': null,
        'binning': 'One',
      };
    } else if (node is DitherNode) {
      return {
        'type': 'Dither',
        'pixels': node.pixels,
        'settle_pixels': node.settlePixels,
        'settle_time': node.settleTime,
        'settle_timeout': 60.0, // Default timeout
        'ra_only': false, // Default to both axes
      };
    } else if (node is StartGuidingNode) {
      return {
        'type': 'StartGuiding',
        'settle_pixels': node.settlePixels,
        'settle_time': node.settleTime,
        'settle_timeout': node.settleTimeout,
        'auto_select_star': node.autoSelectStar,
      };
    } else if (node is StopGuidingNode) {
      return {'type': 'StopGuiding'};
    } else if (node is FilterChangeNode) {
      return {
        'type': 'ChangeFilter',
        'filter_name': node.filterName,
        'filter_index': node.filterPosition,
      };
    } else if (node is CoolCameraNode) {
      return {
        'type': 'CoolCamera',
        'target_temp': node.targetTemp,
        'duration_mins': node.durationMins,
      };
    } else if (node is WarmCameraNode) {
      return {
        'type': 'WarmCamera',
        'rate_per_min': node.ratePerMin,
      };
    } else if (node is RotatorNode) {
      return {
        'type': 'MoveRotator',
        'target_angle': node.targetAngle,
        'relative': node.relative,
      };
    } else if (node is ParkNode) {
      return {'type': 'Park'};
    } else if (node is UnparkNode) {
      return {'type': 'Unpark'};
    } else if (node is WaitTimeNode) {
      return {
        'type': 'WaitForTime',
        'wait_until': node.waitUntil?.millisecondsSinceEpoch,
        'wait_for_twilight': node.waitForTwilight != null ? _twilightToString(node.waitForTwilight!) : null,
      };
    } else if (node is DelayNode) {
      return {
        'type': 'Delay',
        'seconds': node.seconds,
      };
    } else if (node is NotificationNode) {
      return {
        'type': 'Notification',
        'title': node.title,
        'message': node.message,
        'level': _notificationLevelToString(node.level),
      };
    } else if (node is ScriptNode) {
      return {
        'type': 'RunScript',
        'script_path': node.scriptPath,
        'arguments': node.arguments,
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is TargetHeaderNode) {
      return {
        'type': 'TargetHeader',
        'target_name': node.targetName,
        'ra_hours': node.raHours,
        'dec_degrees': node.decDegrees,
        'rotation': node.rotation,
        'min_altitude': node.minAltitude,
        'max_altitude': node.maxAltitude,
        'priority': node.priority,
        'start_after': node.startAfter?.millisecondsSinceEpoch,
        'end_before': node.endBefore?.millisecondsSinceEpoch,
        'mosaic_panel': node.mosaicPanel?.toJson(),
      };
    } else if (node is InstructionSetNode) {
      // InstructionSet maps to a Loop with count=1 on the backend
      return {
        'type': 'Loop',
        'iterations': 1,
        'condition': 'Count',
        'condition_value': 1,
      };
    } else if (node is LoopNode) {
      // Build condition value based on condition type
      dynamic conditionValue;
      switch (node.conditionType) {
        case LoopConditionType.count:
          conditionValue = node.repeatCount;
          break;
        case LoopConditionType.untilTime:
          conditionValue = node.repeatUntil?.millisecondsSinceEpoch;
          break;
        case LoopConditionType.untilAltitude:
          conditionValue = node.repeatUntilAltitude;
          break;
        case LoopConditionType.forever:
        case LoopConditionType.whileDark:
          conditionValue = null;
          break;
      }
      return {
        'type': 'Loop',
        'iterations': node.repeatCount,
        'condition': _loopConditionToString(node.conditionType),
        'condition_value': conditionValue,
      };
    } else if (node is ParallelNode) {
      return {
        'type': 'Parallel',
        'required_successes': node.requiredSuccesses,
      };
    } else if (node is ConditionalNode) {
      // Build condition value based on condition type
      dynamic conditionValue;
      switch (node.conditionType) {
        case ConditionalType.always:
        case ConditionalType.weatherSafe:
        case ConditionalType.safetyMonitorSafe:
          conditionValue = null;
          break;
        case ConditionalType.altitudeAbove:
        case ConditionalType.guidingRmsBelow:
        case ConditionalType.hfrBelow:
        case ConditionalType.moonSeparationAbove:
          conditionValue = node.thresholdValue;
          break;
        case ConditionalType.timeAfter:
          conditionValue = node.thresholdTime?.millisecondsSinceEpoch;
          break;
      }
      return {
        'type': 'Conditional',
        'condition': {
          'type': _conditionalTypeToString(node.conditionType),
          'value': conditionValue,
        },
      };
    } else if (node is RecoveryNode) {
      return {
        'type': 'Recovery',
        'trigger': null,
        'recovery_action': _recoveryActionToString(node.recoveryAction),
        'max_retries': node.maxRetries,
      };
    } else if (node is MeridianFlipNode) {
      return {
        'type': 'MeridianFlip',
        'minutes_past_meridian': node.minutesPastMeridian,
        'pause_guiding': node.pauseGuiding,
        'auto_center': node.autoCenter,
        'settle_time': node.settleTime,
      };
    } else if (node is OpenDomeNode) {
      return {
        'type': 'OpenDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is CloseDomeNode) {
      return {
        'type': 'CloseDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is ParkDomeNode) {
      return {
        'type': 'ParkDome',
        'shutter_only': node.shutterOnly,
      };
    } else if (node is PolarAlignmentNode) {
      return {
        'type': 'PolarAlignment',
        'step_size': node.rotationStep,
        'exposure_time': node.exposureDuration,
        'solve_timeout': 60.0, // Default timeout
        'manual_rotation': node.manualSlew,
        'rotate_east': node.isNorth, // Use isNorth as direction hint
        'gain': node.gain,
        'offset': node.offset,
        'binning': node.binning,
      };
    }

    return {'type': 'Unknown'};
  }
  
  String _binningToString(BinningMode binning) {
    switch (binning) {
      case BinningMode.one: return 'One';
      case BinningMode.two: return 'Two';
      case BinningMode.three: return 'Three';
      case BinningMode.four: return 'Four';
    }
  }
  
  String _autofocusMethodToString(AutofocusMethod method) {
    switch (method) {
      case AutofocusMethod.vCurve: return 'VCurve';
      case AutofocusMethod.hyperbolic: return 'Hyperbolic';
      case AutofocusMethod.parabolic: return 'Parabolic';
    }
  }
  
  String _twilightToString(TwilightType type) {
    switch (type) {
      case TwilightType.civil: return 'Civil';
      case TwilightType.nautical: return 'Nautical';
      case TwilightType.astronomical: return 'Astronomical';
    }
  }
  
  String _notificationLevelToString(NotificationLevel level) {
    switch (level) {
      case NotificationLevel.info: return 'Info';
      case NotificationLevel.warning: return 'Warning';
      case NotificationLevel.error: return 'Error';
      case NotificationLevel.success: return 'Success';
    }
  }
  
  String _loopConditionToString(LoopConditionType type) {
    switch (type) {
      case LoopConditionType.count: return 'Count';
      case LoopConditionType.untilTime: return 'UntilTime';
      case LoopConditionType.untilAltitude: return 'AltitudeBelow';
      case LoopConditionType.forever: return 'Forever';
      case LoopConditionType.whileDark: return 'WhileDark';
    }
  }
  
  String _conditionalTypeToString(ConditionalType type) {
    switch (type) {
      case ConditionalType.always: return 'Always';
      case ConditionalType.altitudeAbove: return 'AltitudeAbove';
      case ConditionalType.timeAfter: return 'TimeAfter';
      case ConditionalType.guidingRmsBelow: return 'GuidingRmsBelow';
      case ConditionalType.hfrBelow: return 'HfrBelow';
      case ConditionalType.weatherSafe: return 'WeatherSafe';
      case ConditionalType.moonSeparationAbove: return 'MoonSeparationAbove';
      case ConditionalType.safetyMonitorSafe: return 'SafetyMonitorSafe';
    }
  }
  
  String _recoveryActionToString(RecoveryActionType action) {
    switch (action) {
      case RecoveryActionType.continueExecution: return 'Continue';
      case RecoveryActionType.pause: return 'Pause';
      case RecoveryActionType.autofocus: return 'Autofocus';
      case RecoveryActionType.nextTarget: return 'NextTarget';
      case RecoveryActionType.retry: return 'Retry';
      case RecoveryActionType.parkAndAbort: return 'ParkAndAbort';
      case RecoveryActionType.customBranch: return 'CustomBranch';
    }
  }

  /// Validate sequence before execution
  /// Returns a list of validation issues (warnings and errors)
  List<SequenceValidationIssue> validateSequence(Sequence sequence) {
    final issues = <SequenceValidationIssue>[];

    // Check for empty sequence
    if (sequence.nodes.isEmpty) {
      issues.add(SequenceValidationIssue(
        severity: ValidationSeverity.error,
        message: 'Sequence is empty',
        nodeId: null,
      ));
      return issues;
    }

    // Check for root node
    if (sequence.rootNodeId == null) {
      issues.add(SequenceValidationIssue(
        severity: ValidationSeverity.error,
        message: 'Sequence has no root node',
        nodeId: null,
      ));
      return issues;
    }

    // Validate each node
    for (final node in sequence.nodes.values) {
      // Check for empty containers
      if (_isContainerNode(node) && node.childIds.isEmpty) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.warning,
          message: '${node.name} is empty and will be skipped',
          nodeId: node.id,
        ));
      }

      // Check exposure nodes
      if (node is ExposureNode) {
        if (node.durationSecs <= 0) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Exposure "${node.name}" has invalid duration',
            nodeId: node.id,
          ));
        }
        if (node.count <= 0) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Exposure "${node.name}" has invalid count',
            nodeId: node.id,
          ));
        }
      }

      // Check target header coordinates
      if (node is TargetHeaderNode) {
        if (node.raHours < 0 || node.raHours > 24) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Target "${node.name}" has invalid RA (must be 0-24 hours)',
            nodeId: node.id,
          ));
        }
        if (node.decDegrees < -90 || node.decDegrees > 90) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Target "${node.name}" has invalid Dec (must be -90 to +90 degrees)',
            nodeId: node.id,
          ));
        }
      }

      // Check slew coordinates
      if (node is SlewNode && !node.useTargetCoords) {
        if (node.customRa != null && (node.customRa! < 0 || node.customRa! > 24)) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Slew "${node.name}" has invalid RA',
            nodeId: node.id,
          ));
        }
        if (node.customDec != null && (node.customDec! < -90 || node.customDec! > 90)) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Slew "${node.name}" has invalid Dec',
            nodeId: node.id,
          ));
        }
      }
    }

    // Note: Device connection validation is done at execution time
    // The sequencer will report errors if required devices are not connected

    return issues;
  }

  bool _isContainerNode(SequenceNode node) {
    return node is TargetHeaderNode ||
        node is LoopNode ||
        node is ParallelNode ||
        node is ConditionalNode ||
        node is RecoveryNode ||
        node is InstructionSetNode;
  }

  Future<void> start() async {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) {
      throw Exception('No sequence loaded');
    }

    // Validate sequence before starting
    final issues = validateSequence(sequence);
    final errors = issues.where((i) => i.severity == ValidationSeverity.error).toList();
    if (errors.isNotEmpty) {
      throw Exception('Cannot start sequence: ${errors.first.message}');
    }

    // Initialize progress
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    progressNotifier.setTotals(
      sequence.totalExposures,
      sequence.totalIntegrationSecs,
    );
    progressNotifier.updateState(SequenceExecutionState.running);
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;

    // Start session tracking
    final sessionNotifier = _ref.read(sessionStateProvider.notifier);
    await sessionNotifier.startSession(
      targetName: sequence.name,
      // Use first target coordinates if available
      targetRa: sequence.targetGroups.isNotEmpty ? sequence.targetGroups.first.raHours : null,
      targetDec: sequence.targetGroups.isNotEmpty ? sequence.targetGroups.first.decDegrees : null,
    );
    sessionNotifier.setTotalExposures(sequence.totalExposures);

    _startTime = DateTime.now();
    _isPaused = false;

    // Start progress timer
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!).inSeconds.toDouble();
        progressNotifier.updateProgress(elapsedSecs: elapsed);
      }
    });

    // Start checkpoint auto-save timer
    _startCheckpointTimer();

    if (_useNativeExecution) {
      // Use native executor
      await _startNativeExecution(sequence);
    } else {
      // Execute with real equipment
      await _executeSequence(sequence);
    }
  }
  
  Future<void> _startNativeExecution(Sequence sequence) async {
    final backend = _ref.read(backendProvider);

    // Sync observer location to Rust backend before starting sequence
    // This ensures the sequencer has access to the current location from settings
    final settingsAsync = _ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    print('[SEQUENCE] _startNativeExecution: settings=${settings != null ? "loaded" : "null"}');
    if (settings != null) {
      print('[SEQUENCE] Location from settings: lat=${settings.latitude}, lon=${settings.longitude}, elev=${settings.elevation}');
    }
    if (settings != null && (settings.latitude != 0.0 || settings.longitude != 0.0)) {
      print('[SEQUENCE] Syncing location to backend...');
      await backend.setLocation(ObserverLocation(
        latitude: settings.latitude,
        longitude: settings.longitude,
        elevation: settings.elevation,
      ));
      print('[SEQUENCE] Location sync complete');
    } else {
      print('[SEQUENCE] Skipping location sync: settings null or location is 0,0');
    }

    // Set simulation mode based on settings
    await backend.sequencerSetSimulationMode(_useSimulationMode);

    // Get connected device IDs from equipment providers
    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final filterwheelState = _ref.read(filterWheelStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);

    // Pass connected device IDs to the sequencer
    final cameraId = cameraState.connectionState == DeviceConnectionState.connected ? cameraState.deviceId : null;
    final mountId = mountState.connectionState == DeviceConnectionState.connected ? mountState.deviceId : null;
    final focuserId = focuserState.connectionState == DeviceConnectionState.connected ? focuserState.deviceId : null;
    final filterwheelId = filterwheelState.connectionState == DeviceConnectionState.connected ? filterwheelState.deviceId : null;
    final rotatorId = rotatorState.connectionState == DeviceConnectionState.connected ? rotatorState.deviceId : null;

    await backend.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
    );

    // Convert sequence to JSON and load into native executor via backend
    final json = _sequenceToJson(sequence);
    await backend.sequencerLoadJson(json);

    // Subscribe to backend events for progress updates
    // Note: The FfiBackend eagerly initializes the event stream in its constructor,
    // so the Rust api_event_stream() function should already be running and subscribed
    // to the event bus. We just need to subscribe to the broadcast stream here.
    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
      onError: (e) => print('[SequenceProvider] Event stream error: $e'),
    );

    // Start the execution via backend
    await backend.sequencerStart();
  }
  
  /// Handle events from the backend (native or remote)
  void _handleSequencerEvent(NightshadeEvent event) {
    // Log all events to verify handler is being called
    print('[SequenceProvider] Received event: type=${event.eventType}, category=${event.category}');

    // Only process sequencer events
    if (event.category != EventCategory.sequencer) return;

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);

    switch (event.eventType) {
      case 'NodeStarted':
        final nodeId = event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final nodeName = event.data['node_type'] as String? ?? event.data['nodeName'] as String?;
        if (nodeId != null) {
          progressNotifier.updateProgress(
            currentNodeId: nodeId,
            currentNodeName: nodeName,
            currentNodeStatus: NodeStatus.running,
          );
          progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
        }
        break;

      case 'NodeCompleted':
        final nodeId = event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final success = event.data['success'] as bool? ?? true;
        if (nodeId != null) {
          progressNotifier.updateNodeStatus(
            nodeId,
            success ? NodeStatus.success : NodeStatus.failure,
          );
        }
        break;

      case 'ExposureStarted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        final filter = event.data['filter'] as String?;
        final exposureDetail = 'Frame $frame/$total${filter != null ? ' ($filter)' : ''}';
        progressNotifier.updateProgress(
          message: 'Exposing $exposureDetail',
          currentFilter: filter,
        );
        // Update node-specific progress for progress panels
        final exposureNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (exposureNodeId != null && total > 0) {
          final exposurePercent = (frame - 1) / total * 100.0; // frame-1 because exposure just started
          progressNotifier.updateNodeProgress(exposureNodeId, exposurePercent, exposureDetail);
        }
        break;

      case 'ExposureCompleted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 1;
        final durationSecs = (event.data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        // Calculate new completed integration time
        final newCompletedIntegration = _ref.read(sequenceProgressProvider).completedIntegrationSecs + durationSecs;
        progressNotifier.updateProgress(
          completedExposures: frame,
          completedIntegrationSecs: newCompletedIntegration,
        );
        // Update node-specific progress for progress panels
        final completedNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (completedNodeId != null) {
          final completedPercent = total > 0 ? (frame / total * 100.0) : 100.0;
          progressNotifier.updateNodeProgress(completedNodeId, completedPercent, 'Completed $frame/$total');
        }

        // Fetch and display the captured image in the UI
        _fetchAndDisplaySequenceImage(durationSecs);
        break;

      case 'Progress':
        final current = event.data['current'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        progressNotifier.updateProgress(
          completedExposures: current,
          message: 'Progress: $current/$total exposures',
        );
        break;

      case 'TargetStarted':
      case 'TargetChanged':
        final name = event.data['target_name'] as String? ?? event.data['name'] as String?;
        progressNotifier.updateProgress(
          currentTarget: name,
          message: name != null ? 'Started target: $name' : null,
        );
        break;

      case 'TargetCompleted':
        final name = event.data['target_name'] as String? ?? event.data['name'] as String?;
        progressNotifier.updateProgress(
          message: 'Completed target: ${name ?? 'unknown'}',
        );
        break;

      case 'Error':
        final message = event.data['message'] as String? ?? 'Unknown error';
        progressNotifier.updateProgress(message: 'Error: $message');
        // Update node-specific progress with error message for progress panels
        final errorNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (errorNodeId != null) {
          progressNotifier.updateNodeProgress(errorNodeId, 0.0, 'Error: $message');
        }
        break;

      case 'InstructionProgress':
        // Handle instruction progress updates from long-running instructions
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent = (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detail = event.data['detail'] as String? ?? '';

        print('[SequenceProvider] InstructionProgress: nodeId=$nodeId, instruction=$instruction, progress=$progressPercent%, detail=$detail');

        // Use node_id from event, fallback to currentNodeId for backwards compatibility
        final targetNodeId = nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        print('[SequenceProvider] Updating node progress for: $targetNodeId');
        if (targetNodeId != null) {
          progressNotifier.updateNodeProgress(targetNodeId, progressPercent, detail);
          // Also update the global message to show current instruction progress
          progressNotifier.updateProgress(
            message: '$instruction: $detail',
          );
        }
        break;

      case 'Started':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;
        break;

      case 'Paused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.paused;
        break;

      case 'Resumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;
        break;

      case 'Completed':
      case 'SequenceCompleted':
        _progressTimer?.cancel();
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.completed;
        break;

      case 'SequenceFailed':
        final error = event.data['error'] as String? ?? 'Unknown error';
        progressNotifier.updateProgress(message: error);
        progressNotifier.updateState(SequenceExecutionState.failed);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
        break;

      case 'Stopped':
      case 'SequenceStopped':
        _progressTimer?.cancel();
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.idle;
        break;
    }
  }

  /// Fetch the last captured image and update the UI providers
  /// This ensures sequence images are displayed in the Imaging tab and Dashboard
  void _fetchAndDisplaySequenceImage(double durationSecs) {
    // Run async fetch in a fire-and-forget manner
    Future(() async {
      try {
        final capturedImage = await bridge.apiGetLastImage();

        // Convert to CapturedImageData (same as ImagingService.captureImage does)
        final imageData = CapturedImageData(
          width: capturedImage.width,
          height: capturedImage.height,
          displayData: Uint8List.fromList(capturedImage.displayData),
          histogram: capturedImage.histogram,
          stats: ImageStats(
            min: capturedImage.stats.min,
            max: capturedImage.stats.max,
            mean: capturedImage.stats.mean,
            median: capturedImage.stats.median,
            stdDev: capturedImage.stats.stdDev,
            hfr: capturedImage.stats.hfr ?? 0.0,
            fwhm: (capturedImage.stats.hfr ?? 0.0) * 2.35, // FWHM ≈ 2.35 * HFR
            starCount: capturedImage.stats.starCount,
            background: capturedImage.stats.mean - capturedImage.stats.stdDev,
            noise: capturedImage.stats.stdDev,
            snr: capturedImage.stats.stdDev > 0
                ? capturedImage.stats.mean / capturedImage.stats.stdDev
                : 0.0,
          ),
          capturedAt: DateTime.now(),
          settings: ExposureSettings(
            exposureTime: durationSecs,
            gain: 0, // Not available from sequence event
            offset: 0,
            binningX: 1,
            binningY: 1,
            frameType: FrameType.light,
          ),
          isColor: capturedImage.isColor,
        );

        // Update providers to display the image in UI
        _ref.read(currentImageProvider.notifier).state = imageData;
        _ref.read(lastImageStatsProvider.notifier).state = imageData.stats;
      } catch (e) {
        // Log but don't fail - image display is non-critical
        print('Failed to fetch sequence image for display: $e');
      }
    });
  }

  bool _pauseResumeInProgress = false;

  /// Wait for state change with timeout
  Future<bool> _awaitStateChange(SequenceExecutionState expectedState, {Duration timeout = const Duration(seconds: 5)}) async {
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      final currentState = _ref.read(sequenceExecutionStateProvider);
      if (currentState == expectedState) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return false;
  }

  Future<void> pause() async {
    // Prevent multiple pause/resume calls
    if (_pauseResumeInProgress) {
      throw Exception('Pause/Resume operation already in progress');
    }

    final currentState = _ref.read(sequenceExecutionStateProvider);
    if (currentState != SequenceExecutionState.running) {
      throw Exception('Cannot pause: sequence is not running');
    }

    _pauseResumeInProgress = true;

    try {
      if (_useNativeExecution) {
        await bridge.NativeBridge.sequencerPause();

        // Wait for confirmation from event system
        final confirmed = await _awaitStateChange(SequenceExecutionState.paused);
        if (!confirmed) {
          throw Exception('Pause operation timed out - state not confirmed');
        }

        // Sync local state
        _isPaused = true;
      } else {
        // Non-native execution: update state immediately
        _isPaused = true;
        _ref.read(sequenceProgressProvider.notifier).updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.paused;
      }
    } finally {
      _pauseResumeInProgress = false;
    }
  }

  Future<void> resume() async {
    // Prevent multiple pause/resume calls
    if (_pauseResumeInProgress) {
      throw Exception('Pause/Resume operation already in progress');
    }

    final currentState = _ref.read(sequenceExecutionStateProvider);
    if (currentState != SequenceExecutionState.paused) {
      throw Exception('Cannot resume: sequence is not paused');
    }

    _pauseResumeInProgress = true;

    try {
      if (_useNativeExecution) {
        await bridge.NativeBridge.sequencerResume();

        // Wait for confirmation from event system
        final confirmed = await _awaitStateChange(SequenceExecutionState.running);
        if (!confirmed) {
          throw Exception('Resume operation timed out - state not confirmed');
        }

        // Sync local state
        _isPaused = false;
      } else {
        // Non-native execution: update state immediately
        _isPaused = false;
        _ref.read(sequenceProgressProvider.notifier).updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;
      }
    } finally {
      _pauseResumeInProgress = false;
    }
  }

  Future<void> stop() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;
    _startTime = null;
    _isPaused = false;
    _ref.read(sequenceProgressProvider.notifier).updateState(SequenceExecutionState.idle);
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.idle;

    // End session
    _ref.read(sessionStateProvider.notifier).endSession(status: 'stopped');

    if (_useNativeExecution) {
      await bridge.NativeBridge.sequencerStop();

      // Clear checkpoint when stopped gracefully
      try {
        final backend = _ref.read(backendProvider);
        await backend.discardCheckpoint();
      } catch (e) {
        // Ignore errors during cleanup
        print('Failed to clear checkpoint on stop: $e');
      }
    }
  }

  Future<void> skip() async {
    if (_useNativeExecution) {
      await bridge.NativeBridge.sequencerSkip();
    }
  }

  /// Reset the sequence execution state without modifying the sequence configuration.
  ///
  /// This clears all execution progress (completed exposures, node statuses, etc.)
  /// while preserving the sequence structure and instruction settings.
  /// Useful when you want to re-run a sequence from the beginning.
  Future<void> reset() async {
    final currentState = _ref.read(sequenceExecutionStateProvider);

    // If running or paused, stop first
    if (currentState == SequenceExecutionState.running ||
        currentState == SequenceExecutionState.paused) {
      await stop();
    }

    // Reset progress notifier to clear all execution stats
    _ref.read(sequenceProgressProvider.notifier).reset();

    // Reset native sequencer if using native execution
    if (_useNativeExecution) {
      try {
        await bridge.NativeBridge.sequencerReset();
      } catch (e) {
        print('[SequenceExecutor] Error resetting native sequencer: $e');
        // Continue anyway - the Dart-side reset is more important
      }
    }

    // Clear any checkpoints
    try {
      final backend = _ref.read(backendProvider);
      await backend.discardCheckpoint();
    } catch (e) {
      print('[SequenceExecutor] Error clearing checkpoint on reset: $e');
    }

    // Ensure we're in idle state
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.idle;

    print('[SequenceExecutor] Sequence reset - ready to run from beginning');
  }

  TargetHeaderNode? _findParentTargetHeader(Sequence sequence, String nodeId) {
    var currentId = nodeId;
    while (true) {
      final node = sequence.nodes[currentId];
      if (node == null) return null;

      if (node is TargetHeaderNode) {
        return node;
      }
      
      if (node.parentId == null) {
        return null;
      }
      
      currentId = node.parentId!;
    }
  }

  /// Execute sequence using real equipment
  Future<void> _executeSequence(Sequence sequence) async {
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    final imagingService = _ref.read(imagingServiceProvider);
    final sessionNotifier = _ref.read(sessionStateProvider.notifier);
    
    // Get all nodes in order
    final nodesToExecute = <SequenceNode>[];
    
    void collectNodes(String? parentId) {
      final children = parentId != null 
          ? sequence.getChildren(parentId)
          : sequence.rootNode != null ? [sequence.rootNode!] : [];
      
      for (final child in children) {
        if (child.isEnabled) {
          nodesToExecute.add(child);
          collectNodes(child.id);
        }
      }
    }
    
    collectNodes(sequence.rootNodeId);

    int completedExposures = 0;

    for (final node in nodesToExecute) {
      if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
        break;
      }

      // Wait while paused
      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
          return;
        }
      }

      progressNotifier.updateProgress(
        currentNodeId: node.id,
        currentNodeName: node.name,
        currentNodeStatus: NodeStatus.running,
      );
      progressNotifier.updateNodeStatus(node.id, NodeStatus.running);

      try {
        // Execute node with real equipment
        if (node is ExposureNode) {
          final cameraState = _ref.read(cameraStateProvider);
          if (cameraState.connectionState != DeviceConnectionState.connected) {
            final error = 'Camera not connected. Cannot execute exposure node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }

          for (int i = 0; i < node.count; i++) {
            if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
              break;
            }
            
            while (_isPaused) {
              await Future.delayed(const Duration(milliseconds: 100));
            }

            progressNotifier.updateProgress(
              message: 'Exposing ${i + 1}/${node.count} (${node.durationSecs}s)',
              currentFilter: node.filter,
            );

            // Use real camera capture
            final settings = ExposureSettings(
              exposureTime: node.durationSecs,
              gain: node.gain ?? 0,
              offset: node.offset ?? 0,
              binningX: _binningToInt(node.binning),
              binningY: _binningToInt(node.binning),
              filter: node.filter,
            );

            final image = await imagingService.captureImage(
              settings: settings,
              targetName: sequence.name,
              frameNumber: completedExposures + 1,
            );

            if (image != null) {
              completedExposures++;
              progressNotifier.updateProgress(completedExposures: completedExposures);
              
              // Update session stats
              sessionNotifier.recordExposureComplete(
                exposureTime: node.durationSecs,
                hfr: image.stats.hfr,
              );
            } else {
              progressNotifier.updateProgress(
                message: 'Exposure ${i + 1} failed or was cancelled',
              );
              sessionNotifier.recordExposureFailed();
            }
          }
        } else if (node is FilterChangeNode) {
          final filterWheelState = _ref.read(filterWheelStateProvider);
          if (filterWheelState.connectionState != DeviceConnectionState.connected) {
            final error = 'Filter wheel not connected. Cannot execute filter change node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          progressNotifier.updateProgress(
            message: 'Changing to filter: ${node.filterName}',
            currentFilter: node.filterName,
          );
          // Find filter position by name
          final filterNames = filterWheelState.filterNames;
          final filterIndex = filterNames.indexWhere(
            (name) => name.toLowerCase() == node.filterName.toLowerCase()
          );
          if (filterIndex < 0) {
            throw Exception('Filter "${node.filterName}" not found');
          }
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.setFilterWheelPosition(filterIndex);
        } else if (node is SlewNode) {
          final mountState = _ref.read(mountStateProvider);
          if (mountState.connectionState != DeviceConnectionState.connected) {
            final error = 'Mount not connected. Cannot execute slew node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          
          // Determine coordinates to slew to
          double? ra, dec;
          if (node.useTargetCoords) {
            // Get coordinates from target group in sequence
            final sequence = _ref.read(currentSequenceProvider);
            if (sequence != null) {
              // Find parent target header by traversing up the tree
              TargetHeaderNode? targetHeader = _findParentTargetHeader(sequence, node.id);

              // If no parent found, use first target header in sequence (legacy fallback)
              if (targetHeader == null && sequence.targetHeaders.isNotEmpty) {
                targetHeader = sequence.targetHeaders.first;
              }

              if (targetHeader != null) {
                ra = targetHeader.raHours;
                dec = targetHeader.decDegrees;
              }
            }
          } else {
            ra = node.customRa;
            dec = node.customDec;
          }
          
          if (ra == null || dec == null) {
            throw Exception('No target coordinates available for slew');
          }
          
          progressNotifier.updateProgress(message: 'Slewing to RA=${ra.toStringAsFixed(2)}h Dec=${dec.toStringAsFixed(1)}°...');
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.slewMountToCoordinates(ra, dec);
        } else if (node is ParkNode) {
          final mountState = _ref.read(mountStateProvider);
          if (mountState.connectionState != DeviceConnectionState.connected) {
            final error = 'Mount not connected. Cannot execute park node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          progressNotifier.updateProgress(message: 'Parking mount...');
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.parkMount();
        } else if (node is UnparkNode) {
          final mountState = _ref.read(mountStateProvider);
          if (mountState.connectionState != DeviceConnectionState.connected) {
            final error = 'Mount not connected. Cannot execute unpark node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          progressNotifier.updateProgress(message: 'Unparking mount...');
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.unparkMount();
        } else if (node is CenterNode) {
          final mountState = _ref.read(mountStateProvider);
          final cameraState = _ref.read(cameraStateProvider);
          if (mountState.connectionState != DeviceConnectionState.connected) {
            final error = 'Mount not connected. Cannot execute center node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          if (cameraState.connectionState != DeviceConnectionState.connected) {
            final error = 'Camera not connected. Cannot execute center node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          
          // Get target coordinates
          double? targetRa, targetDec;
          if (node.useTargetCoords) {
            final sequence = _ref.read(currentSequenceProvider);
            if (sequence != null) {
              // Find parent target header by traversing up the tree
              final targetHeader = _findParentTargetHeader(sequence, node.id);

              if (targetHeader != null) {
                targetRa = targetHeader.raHours;
                targetDec = targetHeader.decDegrees;
              } else if (sequence.targetHeaders.isNotEmpty) {
                 // Fallback to first target
                 targetRa = sequence.targetHeaders.first.raHours;
                 targetDec = sequence.targetHeaders.first.decDegrees;
              }
            }
          }
          
          if (targetRa == null || targetDec == null) {
            throw Exception('No target coordinates available for centering');
          }
          
          // Centering loop with plate solving
          final deviceService = _ref.read(deviceServiceProvider);
          for (int attempt = 0; attempt < node.maxAttempts; attempt++) {
            progressNotifier.updateProgress(
              message: 'Centering attempt ${attempt + 1}/${node.maxAttempts}...',
            );
            
            // Take exposure for plate solving
            final settings = ExposureSettings(
              exposureTime: 5.0, // Quick exposure for plate solve
              gain: 100,
              offset: 10,
              binningX: 2,
              binningY: 2,
            );
            final image = await imagingService.captureImage(
              settings: settings,
              targetName: 'platesolve',
            );
            
            if (image == null) {
              continue;
            }
            
            // Plate solve the image
            // Note: Full plate solving integration requires external solver (ASTAP, etc.)
            // For now, we use the bridge plate solver
            final result = await bridge.NativeBridge.plateSolveNear(
              image.filePath ?? '',
              targetRa * 15.0, // Convert hours to degrees
              targetDec,
              30.0, // Search radius
            );
            
            if (!result.success) {
              progressNotifier.updateProgress(message: 'Plate solve failed, retrying...');
              continue;
            }
            
            // Calculate offset
            final raOffset = (result.ra - targetRa * 15.0) * 3600; // arcsec
            final decOffset = (result.dec - targetDec) * 3600; // arcsec
            final totalOffset = (raOffset * raOffset + decOffset * decOffset).abs();
            
            if (totalOffset <= node.accuracyArcsec * node.accuracyArcsec) {
              progressNotifier.updateProgress(message: 'Centered within ${node.accuracyArcsec}"');
              break;
            }
            
            // Correction slew
            final newRa = targetRa - (raOffset / 3600 / 15.0);
            final newDec = targetDec - (decOffset / 3600);
            await deviceService.slewMountToCoordinates(newRa, newDec);
          }
        } else if (node is AutofocusNode) {
          final cameraState = _ref.read(cameraStateProvider);
          final focuserState = _ref.read(focuserStateProvider);
          if (cameraState.connectionState != DeviceConnectionState.connected) {
            final error = 'Camera not connected. Cannot execute autofocus node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          if (focuserState.connectionState != DeviceConnectionState.connected) {
            final error = 'Focuser not connected. Cannot execute autofocus node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }

          progressNotifier.updateProgress(message: 'Running autofocus...');
          final deviceService = _ref.read(deviceServiceProvider);

          // Map Dart enum to Rust API string
          String methodString;
          switch (node.method) {
            case AutofocusMethod.vCurve:
              methodString = 'VCurve';
              break;
            case AutofocusMethod.hyperbolic:
              methodString = 'Hyperbolic';
              break;
            case AutofocusMethod.parabolic:
              methodString = 'Quadratic';
              break;
          }

          // Use production Rust autofocus engine with curve fitting,
          // backlash compensation, and outlier rejection
          final result = await deviceService.runAutofocus(
            exposureTime: node.exposureDuration,
            stepSize: node.stepSize,
            stepsOut: node.stepsOut,
            method: methodString,
            binning: 1,
          );

          progressNotifier.updateProgress(
            message: 'Autofocus complete: position ${result.bestPosition.toInt()}, HFR ${result.bestHfr.toStringAsFixed(2)}',
          );
        } else if (node is DitherNode) {
          final guiderState = _ref.read(guiderStateProvider);
          if (guiderState.connectionState != DeviceConnectionState.connected) {
            // Dither without guider - just skip silently
            progressNotifier.updateProgress(message: 'Guider not connected, skipping dither');
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            progressNotifier.updateProgress(message: 'Dithering...');
            final deviceService = _ref.read(deviceServiceProvider);
            await deviceService.dither(
              amount: node.pixels,
              raOnly: false, // Default to both axes
              settlePixels: node.settlePixels,
              settleTime: node.settleTime,
              settleTimeout: 120.0, // Default timeout
            );
          }
        } else if (node is StartGuidingNode) {
          progressNotifier.updateProgress(message: 'Starting guiding...');
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.startGuiding(
            settlePixels: node.settlePixels,
            settleTime: node.settleTime,
            settleTimeout: node.settleTimeout,
          );
          progressNotifier.updateProgress(message: 'Guiding started and settled');
        } else if (node is StopGuidingNode) {
          progressNotifier.updateProgress(message: 'Stopping guiding...');
          final deviceService = _ref.read(deviceServiceProvider);
          await deviceService.stopGuiding();
          progressNotifier.updateProgress(message: 'Guiding stopped');
        } else if (node is CoolCameraNode) {
          final cameraState = _ref.read(cameraStateProvider);
          if (cameraState.connectionState != DeviceConnectionState.connected) {
            final error = 'Camera not connected. Cannot execute cool camera node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          progressNotifier.updateProgress(message: 'Cooling camera to ${node.targetTemp}°C...');
          
          // Enable cooler with target temperature
          await bridge.NativeBridge.setCameraCooler(
            cameraState.deviceName ?? '',
            true,
            node.targetTemp,
          );
          
          // Wait for temperature to stabilize (poll until target reached)
          final timeout = Duration(minutes: (node.durationMins ?? 10).toInt());
          final deadline = DateTime.now().add(timeout);
          
          while (DateTime.now().isBefore(deadline)) {
            final status = await bridge.NativeBridge.getCameraStatus(cameraState.deviceName ?? '');
            final currentTemp = status.sensorTemp ?? 20.0;
            
            progressNotifier.updateProgress(
              message: 'Cooling: ${currentTemp.toStringAsFixed(1)}°C -> ${node.targetTemp}°C',
            );
            
            if (currentTemp <= node.targetTemp + 1.0) {
              // Within 1 degree of target
              break;
            }
            
            await Future.delayed(const Duration(seconds: 5));
          }
        } else if (node is WarmCameraNode) {
          final cameraState = _ref.read(cameraStateProvider);
          if (cameraState.connectionState != DeviceConnectionState.connected) {
            final error = 'Camera not connected. Cannot execute warm camera node "${node.name}"';
            progressNotifier.updateProgress(message: error);
            progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
            progressNotifier.updateState(SequenceExecutionState.failed);
            _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.failed;
            throw Exception(error);
          }
          progressNotifier.updateProgress(message: 'Warming camera...');
          
          // Get current temperature
          final status = await bridge.NativeBridge.getCameraStatus(cameraState.deviceName ?? '');
          final startTemp = status.sensorTemp ?? -10.0;
          final ambientTemp = 15.0; // Target to warm up to
          
          // Gradual warming by stepping up temperature
          final rate = node.ratePerMin; // degrees per minute
          var currentTarget = startTemp;
          
          while (currentTarget < ambientTemp) {
            currentTarget = (currentTarget + rate).clamp(startTemp, ambientTemp);
            
            progressNotifier.updateProgress(
              message: 'Warming: target ${currentTarget.toStringAsFixed(1)}°C',
            );
            
            await bridge.NativeBridge.setCameraCooler(
              cameraState.deviceName ?? '',
              true,
              currentTarget,
            );
            
            await Future.delayed(const Duration(minutes: 1));
          }
          
          // Turn off cooler
          await bridge.NativeBridge.setCameraCooler(
            cameraState.deviceName ?? '',
            false,
            null,
          );
        } else if (node is RotatorNode) {
          // Rotator is optional - skip silently if not connected
          progressNotifier.updateProgress(message: 'Moving rotator to ${node.targetAngle}°...');
          
          // Get the rotator ID from the active equipment profile
          final profile = _ref.read(activeEquipmentProfileProvider);
          final rotatorId = profile?.rotatorId;
          
          if (rotatorId != null && rotatorId.isNotEmpty) {
            final backend = _ref.read(backendProvider);
            await backend.rotatorMoveTo(rotatorId, node.targetAngle);
          } else {
            // No rotator configured - skip silently with brief delay
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } else if (node is DelayNode) {
          progressNotifier.updateProgress(message: 'Waiting ${node.seconds}s...');
          await Future.delayed(Duration(seconds: node.seconds.toInt()));
        } else if (node is WaitTimeNode) {
          // Wait until specified time
          if (node.waitUntil != null) {
            final waitUntil = node.waitUntil!;
            while (DateTime.now().isBefore(waitUntil)) {
              final remaining = waitUntil.difference(DateTime.now());
              progressNotifier.updateProgress(
                message: 'Waiting until ${waitUntil.toLocal()} (${remaining.inMinutes}m remaining)',
              );
              await Future.delayed(const Duration(seconds: 10));
              
              // Check for cancellation
              if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
                break;
              }
            }
          } else {
            progressNotifier.updateProgress(message: 'No wait time specified');
          }
        } else if (node is NotificationNode) {
          progressNotifier.updateProgress(message: 'Notification: ${node.title}');
          // Notifications don't require equipment
        } else if (node is ScriptNode) {
          progressNotifier.updateProgress(message: 'Running script: ${node.scriptPath}');
          
          // Execute external script
          try {
            final result = await Process.run(
              node.scriptPath,
              node.arguments,
              runInShell: true,
            );
            
            if (result.exitCode != 0) {
              progressNotifier.updateProgress(
                message: 'Script failed with exit code ${result.exitCode}: ${result.stderr}',
              );
              // Always fail on script error
              throw Exception('Script failed: ${result.stderr}');
            } else {
              progressNotifier.updateProgress(message: 'Script completed successfully');
            }
          } catch (e) {
            progressNotifier.updateProgress(message: 'Script error: $e');
            rethrow;
          }
        } else if (node is TargetHeaderNode || node is LoopNode ||
                   node is ParallelNode || node is ConditionalNode ||
                   node is RecoveryNode || node is InstructionSetNode) {
          // Logic nodes don't require equipment checks
          progressNotifier.updateProgress(message: 'Executing ${node.name}...');
        } else {
          final error = 'Unknown node type: ${node.runtimeType}';
          progressNotifier.updateProgress(message: error);
          progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
          throw Exception(error);
        }

        progressNotifier.updateNodeStatus(node.id, NodeStatus.success);
      } catch (e) {
        progressNotifier.updateProgress(
          message: 'Error executing ${node.name}: $e',
        );
        progressNotifier.updateNodeStatus(node.id, NodeStatus.failure);
      }
    }

    // Completion
    _progressTimer?.cancel();
    sessionNotifier.endSession(status: 'completed');
    progressNotifier.updateState(SequenceExecutionState.completed);
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.completed;
  }

  int _binningToInt(BinningMode binning) {
    switch (binning) {
      case BinningMode.one: return 1;
      case BinningMode.two: return 2;
      case BinningMode.three: return 3;
      case BinningMode.four: return 4;
    }
  }

  Future<void> _simulateNode(SequenceNode node, SequenceProgressNotifier progressNotifier) async {
    if (node is TargetHeaderNode) {
      progressNotifier.updateProgress(
        currentTarget: node.targetName,
        message: 'Starting target: ${node.displayName}',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    } else if (node is CenterNode) {
      progressNotifier.updateProgress(message: 'Centering on target...');
      await Future.delayed(const Duration(seconds: 3));
    } else if (node is AutofocusNode) {
      progressNotifier.updateProgress(message: 'Running autofocus...');
      await Future.delayed(const Duration(seconds: 5));
    } else if (node is DitherNode) {
      progressNotifier.updateProgress(message: 'Dithering...');
      await Future.delayed(const Duration(seconds: 1));
    } else if (node is StartGuidingNode) {
      progressNotifier.updateProgress(message: 'Starting guiding...');
      await Future.delayed(const Duration(seconds: 2));
    } else if (node is StopGuidingNode) {
      progressNotifier.updateProgress(message: 'Stopping guiding...');
      await Future.delayed(const Duration(seconds: 1));
    } else if (node is UnparkNode) {
      progressNotifier.updateProgress(message: 'Unparking mount...');
      await Future.delayed(const Duration(seconds: 2));
    } else if (node is CoolCameraNode) {
      progressNotifier.updateProgress(message: 'Cooling camera to ${node.targetTemp}°C...');
      await Future.delayed(const Duration(seconds: 5));
    } else if (node is WarmCameraNode) {
      progressNotifier.updateProgress(message: 'Warming camera...');
      await Future.delayed(const Duration(seconds: 3));
    } else if (node is DelayNode) {
      progressNotifier.updateProgress(message: 'Waiting ${node.seconds}s...');
      await Future.delayed(Duration(milliseconds: (node.seconds * 100).toInt().clamp(100, 3000)));
    } else if (node is NotificationNode) {
      progressNotifier.updateProgress(message: 'Notification: ${node.title}');
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _simulateExecution(Sequence sequence) async {
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    
    // Get all nodes in order
    final nodesToExecute = <SequenceNode>[];
    
    void collectNodes(String? parentId) {
      final children = parentId != null 
          ? sequence.getChildren(parentId)
          : sequence.rootNode != null ? [sequence.rootNode!] : [];
      
      for (final child in children) {
        if (child.isEnabled) {
          nodesToExecute.add(child);
          collectNodes(child.id);
        }
      }
    }
    
    collectNodes(sequence.rootNodeId);

    int completedExposures = 0;

    for (final node in nodesToExecute) {
      if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
        break;
      }

      // Wait while paused
      while (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
          return;
        }
      }

      progressNotifier.updateProgress(
        currentNodeId: node.id,
        currentNodeName: node.name,
        currentNodeStatus: NodeStatus.running,
      );
      progressNotifier.updateNodeStatus(node.id, NodeStatus.running);

      // Simulate node execution
      if (node is ExposureNode) {
        for (int i = 0; i < node.count; i++) {
          if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.idle) {
            break;
          }
          
          while (_isPaused) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

          progressNotifier.updateProgress(
            message: 'Exposing ${i + 1}/${node.count} (${node.durationSecs}s)',
            currentFilter: node.filter,
          );

          // Simulate exposure time (shortened for demo)
          await Future.delayed(Duration(milliseconds: (node.durationSecs * 100).toInt().clamp(100, 5000)));
          
          completedExposures++;
          progressNotifier.updateProgress(completedExposures: completedExposures);
        }
      } else if (node is TargetHeaderNode) {
        progressNotifier.updateProgress(
          currentTarget: node.targetName,
          message: 'Starting target: ${node.displayName}',
        );
        await Future.delayed(const Duration(milliseconds: 500));
      } else if (node is SlewNode) {
        progressNotifier.updateProgress(message: 'Slewing to target...');
        await Future.delayed(const Duration(seconds: 2));
      } else if (node is CenterNode) {
        progressNotifier.updateProgress(message: 'Centering on target...');
        await Future.delayed(const Duration(seconds: 3));
      } else if (node is AutofocusNode) {
        progressNotifier.updateProgress(message: 'Running autofocus...');
        await Future.delayed(const Duration(seconds: 5));
      } else if (node is FilterChangeNode) {
        progressNotifier.updateProgress(
          message: 'Changing to filter: ${node.filterName}',
          currentFilter: node.filterName,
        );
        await Future.delayed(const Duration(seconds: 2));
      } else if (node is DitherNode) {
        progressNotifier.updateProgress(message: 'Dithering...');
        await Future.delayed(const Duration(seconds: 1));
      } else if (node is StartGuidingNode) {
        progressNotifier.updateProgress(message: 'Starting guiding...');
        await Future.delayed(const Duration(seconds: 2));
      } else if (node is StopGuidingNode) {
        progressNotifier.updateProgress(message: 'Stopping guiding...');
        await Future.delayed(const Duration(seconds: 1));
      } else if (node is ParkNode) {
        progressNotifier.updateProgress(message: 'Parking mount...');
        await Future.delayed(const Duration(seconds: 3));
      } else if (node is UnparkNode) {
        progressNotifier.updateProgress(message: 'Unparking mount...');
        await Future.delayed(const Duration(seconds: 2));
      } else if (node is CoolCameraNode) {
        progressNotifier.updateProgress(message: 'Cooling camera to ${node.targetTemp}°C...');
        await Future.delayed(const Duration(seconds: 5));
      } else if (node is WarmCameraNode) {
        progressNotifier.updateProgress(message: 'Warming camera...');
        await Future.delayed(const Duration(seconds: 3));
      } else if (node is DelayNode) {
        progressNotifier.updateProgress(message: 'Waiting ${node.seconds}s...');
        await Future.delayed(Duration(milliseconds: (node.seconds * 100).toInt().clamp(100, 3000)));
      } else if (node is NotificationNode) {
        progressNotifier.updateProgress(message: 'Notification: ${node.title}');
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // Simulate other node types
        await Future.delayed(const Duration(milliseconds: 500));
      }

      progressNotifier.updateNodeStatus(node.id, NodeStatus.success);
    }

    // Completion
    _progressTimer?.cancel();
    progressNotifier.updateState(SequenceExecutionState.completed);
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.completed;
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  /// Initialize checkpoint system with app's documents directory
  Future<void> initializeCheckpoints(String documentsPath) async {
    final backend = _ref.read(backendProvider);
    await backend.sequencerSetCheckpointDir(documentsPath);
  }

  /// Check if there's a checkpoint available to resume
  Future<bool> hasCheckpoint() async {
    final backend = _ref.read(backendProvider);
    return await backend.hasCheckpoint();
  }

  /// Get information about the current checkpoint
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final backend = _ref.read(backendProvider);
    return await backend.getCheckpointInfo();
  }

  /// Resume sequence from checkpoint
  Future<void> resumeFromCheckpoint() async {
    final backend = _ref.read(backendProvider);

    // Load checkpoint info first
    final info = await backend.getCheckpointInfo();
    if (info == null || !info.canResume) {
      throw Exception('No valid checkpoint to resume from');
    }

    // Initialize progress with checkpoint data
    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);
    progressNotifier.updateState(SequenceExecutionState.running);
    _ref.read(sequenceExecutionStateProvider.notifier).state = SequenceExecutionState.running;

    // Restore completed exposures and integration time
    progressNotifier.updateProgress(
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      message: 'Resuming from checkpoint...',
    );

    _startTime = DateTime.now();
    _isPaused = false;

    // Start progress timer
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!).inSeconds.toDouble();
        progressNotifier.updateProgress(elapsedSecs: elapsed);
      }
    });

    // Start checkpoint auto-save timer (every 30 seconds)
    _startCheckpointTimer();

    if (_useNativeExecution) {
      // Subscribe to backend events for progress updates
      _nativeEventSubscription = backend.eventStream.listen(
        _handleSequencerEvent,
      );

      // Resume from checkpoint in native executor
      await backend.resumeFromCheckpoint();
    } else {
      throw Exception('Checkpoint resume only supported with native execution');
    }
  }

  /// Discard the current checkpoint
  Future<void> discardCheckpoint() async {
    final backend = _ref.read(backendProvider);
    await backend.discardCheckpoint();
  }

  /// Start periodic checkpoint saves
  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_ref.read(sequenceExecutionStateProvider) == SequenceExecutionState.running) {
        try {
          final backend = _ref.read(backendProvider);
          await backend.saveCheckpoint();
        } catch (e) {
          // Log error but don't interrupt sequence
          print('Failed to save checkpoint: $e');
        }
      }
    });
  }

  /// Stop checkpoint timer
  void _stopCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
  }
}

// =============================================================================
// NODE PALETTE
// =============================================================================

/// Provider for sequencer default settings (persisted)
final sequencerDefaultsProvider = StateNotifierProvider<SequencerDefaultsNotifier, SequencerDefaults>((ref) {
  return SequencerDefaultsNotifier(ref);
});

class SequencerDefaults {
  // Autofocus defaults
  final int autofocusStepSize;
  final int autofocusStepsOut;
  final double autofocusExposureDuration;
  
  // Dither defaults
  final double ditherPixels;
  final double ditherSettleTime;
  final double ditherSettlePixels;
  
  // Exposure defaults
  final double exposureDuration;
  final int exposureCount;
  final String? exposureFilter;
  final int? exposureGain;
  final int? exposureOffset;
  final BinningMode exposureBinning;
  final int exposureDitherEvery;

  const SequencerDefaults({
    this.autofocusStepSize = 100,
    this.autofocusStepsOut = 7,
    this.autofocusExposureDuration = 3.0,
    this.ditherPixels = 5.0,
    this.ditherSettleTime = 30.0,
    this.ditherSettlePixels = 1.5,
    this.exposureDuration = 60.0,
    this.exposureCount = 10,
    this.exposureFilter,
    this.exposureGain,
    this.exposureOffset,
    this.exposureBinning = BinningMode.one,
    this.exposureDitherEvery = 1,
  });

  SequencerDefaults copyWith({
    int? autofocusStepSize,
    int? autofocusStepsOut,
    double? autofocusExposureDuration,
    double? ditherPixels,
    double? ditherSettleTime,
    double? ditherSettlePixels,
    double? exposureDuration,
    int? exposureCount,
    String? exposureFilter,
    int? exposureGain,
    int? exposureOffset,
    BinningMode? exposureBinning,
    int? exposureDitherEvery,
  }) {
    return SequencerDefaults(
      autofocusStepSize: autofocusStepSize ?? this.autofocusStepSize,
      autofocusStepsOut: autofocusStepsOut ?? this.autofocusStepsOut,
      autofocusExposureDuration: autofocusExposureDuration ?? this.autofocusExposureDuration,
      ditherPixels: ditherPixels ?? this.ditherPixels,
      ditherSettleTime: ditherSettleTime ?? this.ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels ?? this.ditherSettlePixels,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      exposureCount: exposureCount ?? this.exposureCount,
      exposureFilter: exposureFilter ?? this.exposureFilter,
      exposureGain: exposureGain ?? this.exposureGain,
      exposureOffset: exposureOffset ?? this.exposureOffset,
      exposureBinning: exposureBinning ?? this.exposureBinning,
      exposureDitherEvery: exposureDitherEvery ?? this.exposureDitherEvery,
    );
  }
}

class SequencerDefaultsNotifier extends StateNotifier<SequencerDefaults> {
  final Ref _ref;

  SequencerDefaultsNotifier(this._ref) : super(const SequencerDefaults()) {
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final settingsDao = _ref.read(settingsDaoProvider);
    
    final stepSize = int.tryParse(await settingsDao.getSetting('sequencer_autofocus_step_size') ?? '100') ?? 100;
    final stepsOut = int.tryParse(await settingsDao.getSetting('sequencer_autofocus_steps_out') ?? '7') ?? 7;
    final exposureDuration = double.tryParse(await settingsDao.getSetting('sequencer_autofocus_exposure_duration') ?? '3.0') ?? 3.0;
    
    final ditherPixels = double.tryParse(await settingsDao.getSetting('sequencer_dither_pixels') ?? '5.0') ?? 5.0;
    final ditherSettleTime = double.tryParse(await settingsDao.getSetting('sequencer_dither_settle_time') ?? '30.0') ?? 30.0;
    final ditherSettlePixels = double.tryParse(await settingsDao.getSetting('sequencer_dither_settle_pixels') ?? '1.5') ?? 1.5;
    
    final exposureDurationDefault = double.tryParse(await settingsDao.getSetting('sequencer_exposure_duration') ?? '60.0') ?? 60.0;
    final exposureCount = int.tryParse(await settingsDao.getSetting('sequencer_exposure_count') ?? '10') ?? 10;
    final exposureFilter = await settingsDao.getSetting('sequencer_exposure_filter');
    final exposureGainStr = await settingsDao.getSetting('sequencer_exposure_gain');
    final exposureGain = exposureGainStr != null ? int.tryParse(exposureGainStr) : null;
    final exposureOffsetStr = await settingsDao.getSetting('sequencer_exposure_offset');
    final exposureOffset = exposureOffsetStr != null ? int.tryParse(exposureOffsetStr) : null;
    final exposureBinningStr = await settingsDao.getSetting('sequencer_exposure_binning') ?? 'one';
    final exposureBinning = BinningMode.values.firstWhere(
      (e) => e.name == exposureBinningStr,
      orElse: () => BinningMode.one,
    );
    final exposureDitherEvery = int.tryParse(await settingsDao.getSetting('sequencer_exposure_dither_every') ?? '1') ?? 1;
    
    state = SequencerDefaults(
      autofocusStepSize: stepSize,
      autofocusStepsOut: stepsOut,
      autofocusExposureDuration: exposureDuration,
      ditherPixels: ditherPixels,
      ditherSettleTime: ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels,
      exposureDuration: exposureDurationDefault,
      exposureCount: exposureCount,
      exposureFilter: exposureFilter,
      exposureGain: exposureGain,
      exposureOffset: exposureOffset,
      exposureBinning: exposureBinning,
      exposureDitherEvery: exposureDitherEvery,
    );
  }

  Future<void> updateAutofocusDefaults({
    int? stepSize,
    int? stepsOut,
    double? exposureDuration,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};
    
    if (stepSize != null) {
      updates['sequencer_autofocus_step_size'] = stepSize.toString();
      state = state.copyWith(autofocusStepSize: stepSize);
    }
    if (stepsOut != null) {
      updates['sequencer_autofocus_steps_out'] = stepsOut.toString();
      state = state.copyWith(autofocusStepsOut: stepsOut);
    }
    if (exposureDuration != null) {
      updates['sequencer_autofocus_exposure_duration'] = exposureDuration.toString();
      state = state.copyWith(autofocusExposureDuration: exposureDuration);
    }
    
    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }

  Future<void> updateDitherDefaults({
    double? pixels,
    double? settleTime,
    double? settlePixels,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};
    
    if (pixels != null) {
      updates['sequencer_dither_pixels'] = pixels.toString();
      state = state.copyWith(ditherPixels: pixels);
    }
    if (settleTime != null) {
      updates['sequencer_dither_settle_time'] = settleTime.toString();
      state = state.copyWith(ditherSettleTime: settleTime);
    }
    if (settlePixels != null) {
      updates['sequencer_dither_settle_pixels'] = settlePixels.toString();
      state = state.copyWith(ditherSettlePixels: settlePixels);
    }
    
    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }

  Future<void> updateExposureDefaults({
    double? duration,
    int? count,
    String? filter,
    int? gain,
    int? offset,
    BinningMode? binning,
    int? ditherEvery,
  }) async {
    final settingsDao = _ref.read(settingsDaoProvider);
    final updates = <String, String>{};
    
    if (duration != null) {
      updates['sequencer_exposure_duration'] = duration.toString();
      state = state.copyWith(exposureDuration: duration);
    }
    if (count != null) {
      updates['sequencer_exposure_count'] = count.toString();
      state = state.copyWith(exposureCount: count);
    }
    if (filter != null) {
      updates['sequencer_exposure_filter'] = filter;
      state = state.copyWith(exposureFilter: filter);
    }
    if (gain != null) {
      updates['sequencer_exposure_gain'] = gain.toString();
      state = state.copyWith(exposureGain: gain);
    }
    if (offset != null) {
      updates['sequencer_exposure_offset'] = offset.toString();
      state = state.copyWith(exposureOffset: offset);
    }
    if (binning != null) {
      updates['sequencer_exposure_binning'] = binning.name;
      state = state.copyWith(exposureBinning: binning);
    }
    if (ditherEvery != null) {
      updates['sequencer_exposure_dither_every'] = ditherEvery.toString();
      state = state.copyWith(exposureDitherEvery: ditherEvery);
    }
    
    if (updates.isNotEmpty) {
      await settingsDao.setSettings(updates);
    }
  }
}

/// Available node types for the palette
final nodePaletteProvider = Provider<List<NodePaletteCategory>>((ref) {
  final defaults = ref.watch(sequencerDefaultsProvider);
  
  return [
    NodePaletteCategory(
      name: 'Target',
      icon: 'target',
      items: [
        NodePaletteItem(
          name: 'Target',
          icon: 'target',
          description: 'Root node containing imaging instructions for a target',
          createNode: () => TargetHeaderNode(
            targetName: 'New Target',
            raHours: 0,
            decDegrees: 0,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Imaging',
      icon: 'camera',
      items: [
        NodePaletteItem(
          name: 'Take Exposures',
          icon: 'camera',
          description: 'Capture images with specified settings',
          createNode: () => ExposureNode(
            durationSecs: defaults.exposureDuration,
            count: defaults.exposureCount,
            filter: defaults.exposureFilter,
            gain: defaults.exposureGain,
            offset: defaults.exposureOffset,
            binning: defaults.exposureBinning,
            ditherEvery: defaults.exposureDitherEvery,
          ),
        ),
        NodePaletteItem(
          name: 'Change Filter',
          icon: 'circle',
          description: 'Change the filter wheel position',
          createNode: () => FilterChangeNode(
            filterName: defaults.exposureFilter ?? 'L',
          ),
        ),
        NodePaletteItem(
          name: 'Dither',
          icon: 'shuffle',
          description: 'Dither the guiding for better results',
          createNode: () => DitherNode(
            pixels: defaults.ditherPixels,
            settleTime: defaults.ditherSettleTime,
            settlePixels: defaults.ditherSettlePixels,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Guiding',
      icon: 'crosshair',
      items: [
        NodePaletteItem(
          name: 'Start Guiding',
          icon: 'crosshair',
          description: 'Start PHD2 guiding and wait for settle',
          createNode: () => StartGuidingNode(
            settlePixels: defaults.ditherSettlePixels,
            settleTime: defaults.ditherSettleTime,
          ),
        ),
        NodePaletteItem(
          name: 'Stop Guiding',
          icon: 'x-circle',
          description: 'Stop PHD2 guiding',
          createNode: () => StopGuidingNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Mount',
      icon: 'compass',
      items: [
        NodePaletteItem(
          name: 'Slew to Target',
          icon: 'compass',
          description: 'Slew mount to target coordinates',
          createNode: () => SlewNode(),
        ),
        NodePaletteItem(
          name: 'Center Target',
          icon: 'crosshair',
          description: 'Plate solve and center on target',
          createNode: () => CenterNode(),
        ),
        NodePaletteItem(
          name: 'Park Mount',
          icon: 'parking-circle',
          description: 'Park the mount',
          createNode: () => ParkNode(),
        ),
        NodePaletteItem(
          name: 'Unpark Mount',
          icon: 'unlock',
          description: 'Unpark the mount',
          createNode: () => UnparkNode(),
        ),
        NodePaletteItem(
          name: 'Meridian Flip',
          icon: 'refresh-cw',
          description: 'Perform meridian flip',
          createNode: () => MeridianFlipNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Dome',
      icon: 'home',
      items: [
        NodePaletteItem(
          name: 'Open Dome',
          icon: 'home',
          description: 'Open dome shutter',
          createNode: () => OpenDomeNode(),
        ),
        NodePaletteItem(
          name: 'Close Dome',
          icon: 'home',
          description: 'Close dome shutter',
          createNode: () => CloseDomeNode(),
        ),
        NodePaletteItem(
          name: 'Park Dome',
          icon: 'parking-circle',
          description: 'Park the dome',
          createNode: () => ParkDomeNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Focus',
      icon: 'focus',
      items: [
        NodePaletteItem(
          name: 'Autofocus',
          icon: 'focus',
          description: 'Run autofocus routine',
          createNode: () => AutofocusNode(
            stepSize: defaults.autofocusStepSize,
            stepsOut: defaults.autofocusStepsOut,
            exposureDuration: defaults.autofocusExposureDuration,
          ),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Camera',
      icon: 'aperture',
      items: [
        NodePaletteItem(
          name: 'Cool Camera',
          icon: 'snowflake',
          description: 'Cool camera to target temperature',
          createNode: () => CoolCameraNode(),
        ),
        NodePaletteItem(
          name: 'Warm Camera',
          icon: 'flame',
          description: 'Warm camera at controlled rate',
          createNode: () => WarmCameraNode(),
        ),
        NodePaletteItem(
          name: 'Move Rotator',
          icon: 'rotate-cw',
          description: 'Move rotator to angle',
          createNode: () => RotatorNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Logic',
      icon: 'workflow',
      items: [
        NodePaletteItem(
          name: 'Instruction Set',
          icon: 'list',
          description: 'Group instructions sequentially (no loop)',
          createNode: () => InstructionSetNode(),
        ),
        NodePaletteItem(
          name: 'Loop',
          icon: 'repeat',
          description: 'Repeat instructions',
          createNode: () => LoopNode(),
        ),
        NodePaletteItem(
          name: 'Conditional',
          icon: 'git-merge',
          description: 'Execute if condition is met',
          createNode: () => ConditionalNode(),
        ),
        NodePaletteItem(
          name: 'Parallel',
          icon: 'git-branch',
          description: 'Execute instructions in parallel',
          createNode: () => ParallelNode(),
        ),
        NodePaletteItem(
          name: 'Recovery',
          icon: 'shield-check',
          description: 'Handle errors with recovery logic',
          createNode: () => RecoveryNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Timing',
      icon: 'clock',
      items: [
        NodePaletteItem(
          name: 'Wait for Time',
          icon: 'clock',
          description: 'Wait until specific time',
          createNode: () => WaitTimeNode(),
        ),
        NodePaletteItem(
          name: 'Delay',
          icon: 'timer',
          description: 'Wait for duration',
          createNode: () => DelayNode(),
        ),
      ],
    ),
    NodePaletteCategory(
      name: 'Utilities',
      icon: 'wrench',
      items: [
        NodePaletteItem(
          name: 'Notification',
          icon: 'bell',
          description: 'Send notification',
          createNode: () => NotificationNode(),
        ),
        NodePaletteItem(
          name: 'Run Script',
          icon: 'code',
          description: 'Execute custom script',
          createNode: () => ScriptNode(),
        ),
      ],
    ),
  ];
});

class NodePaletteCategory {
  final String name;
  final String icon;
  final List<NodePaletteItem> items;

  NodePaletteCategory({
    required this.name,
    required this.icon,
    required this.items,
  });
}

class NodePaletteItem {
  final String name;
  final String icon;
  final String description;
  final SequenceNode Function() createNode;

  NodePaletteItem({
    required this.name,
    required this.icon,
    required this.description,
    required this.createNode,
  });
}
