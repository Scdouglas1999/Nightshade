import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/sequence/sequence_models.dart';
import '../models/sequence/template_snippet.dart';
import '../models/equipment/equipment_models.dart';
import '../models/imaging/imaging_models.dart';
import '../models/settings/app_settings.dart' show ObserverLocation;
import '../services/logging_service.dart';
import 'equipment_provider.dart';
import 'database_provider.dart';
import 'profiles_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';
import 'imaging_provider.dart';
import 'sequence_stats_provider.dart';
import '../services/imaging_service.dart';
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

/// Current sequence being edited
final currentSequenceProvider =
    StateNotifierProvider<CurrentSequenceNotifier, Sequence?>((ref) {
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

      final newChildIds =
          oldNode.childIds.map((id) => idMapping[id] ?? id).toList();

      newNodes[newId] = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
    }

    // Update merge parent's children
    final existingChildCount = mergeParent.childIds.length;
    final updatedChildIds = List<String>.from(mergeParent.childIds)
      ..addAll(childIdsToAdd);
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

  /// Insert a template snippet into the sequence.
  /// The snippet's nodes are deserialized and inserted at the specified parent,
  /// or the currently selected node if no parent is specified.
  void insertSnippet(
    TemplateSnippet snippet, {
    String? parentId,
    int? index,
    List<String>? profileFilterNames,
  }) {
    if (state == null) return;
    if (snippet.nodeData.isEmpty) return;
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final idMapping = <String, String>{};
    final createdNodes = <SequenceNode>[];

    // Find the parent to insert into
    String? insertParentId = parentId;
    if (insertParentId != null) {
      // Check if the specified parent can have children
      final parentNode = newNodes[insertParentId];
      if (parentNode != null && !_canHaveChildren(parentNode)) {
        // Use the parent's parent instead
        insertParentId = parentNode.parentId;
      }
    }

    // Fallback to root if no valid parent found
    insertParentId ??= state!.rootNodeId;
    if (insertParentId == null) {
      // Create root if sequence is empty
      final rootNode = InstructionSetNode(name: 'Sequence Root');
      newNodes[rootNode.id] = rootNode;
      insertParentId = rootNode.id;
    }

    final insertParent = newNodes[insertParentId];
    if (insertParent == null) return;

    // Helper function to deserialize a single node and its children
    SequenceNode deserializeNodeData(
      Map<String, dynamic> json, {
      String? parentIdOverride,
      int orderIdx = 0,
    }) {
      // Generate new ID for this node
      final originalId = json['id'] as String? ?? const Uuid().v4();
      final newId = const Uuid().v4();
      idMapping[originalId] = newId;

      // Parse children recursively first to get their IDs
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

      // Create the node with the new ID and children
      final nodeJson = Map<String, dynamic>.from(json);
      nodeJson['id'] = newId;
      nodeJson['parentId'] = parentIdOverride;
      nodeJson['childIds'] = childIds;
      nodeJson['orderIndex'] = orderIdx;
      nodeJson.remove(
          'children'); // Remove children from JSON as we've processed them

      final node = _deserializeSnippetNode(nodeJson);
      createdNodes.add(node);
      return node;
    }

    // Deserialize all top-level snippet nodes
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

    // Match template filter names to actual profile filter names
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

    // Add all created nodes to the sequence
    for (final node in createdNodes) {
      newNodes[node.id] = node;
    }

    // Update parent's children list
    final newChildIds = List<String>.from(insertParent.childIds);
    newChildIds.insertAll(insertIdx, topLevelNodeIds);

    // Update order indices for all children after insertion point
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

  /// Check if a node type can have children
  bool _canHaveChildren(SequenceNode node) {
    return node is TargetHeaderNode ||
        node is LoopNode ||
        node is InstructionSetNode ||
        node is ParallelNode ||
        node is ConditionalNode ||
        node is RecoveryNode;
  }

  /// Deserialize a single node from snippet JSON data
  SequenceNode _deserializeSnippetNode(Map<String, dynamic> json) {
    final rawType = json['nodeType'] as String?;
    if (rawType == null || rawType.trim().isEmpty) {
      throw FormatException('Snippet node missing nodeType');
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
        // Default to InstructionSetNode for unknown types
        return InstructionSetNode(
          id: id,
          name: name ?? nodeType,
          parentId: parentId,
          childIds: childIds,
          orderIndex: orderIndex,
          isEnabled: isEnabled,
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
      if (templateLower.startsWith(profileLower) && profileLower.isNotEmpty)
        return i;
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

    // Pass 5: Reverse - check if any abbreviation key matches a profile name that starts with the template
    for (final entry in _filterAbbreviations.entries) {
      for (final alias in entry.value) {
        if (alias == templateLower || templateLower.startsWith(alias)) {
          // Found our template in the aliases, now match the key against profiles
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

  /// Remove a node from the sequence
  void removeNode(String nodeId) {
    if (state == null) return;
    _saveUndo();

    final newNodes = Map<String, SequenceNode>.from(state!.nodes);
    final nodeToRemove = newNodes[nodeId];
    if (nodeToRemove == null) return;

    // Remove from parent's children
    if (nodeToRemove.parentId != null &&
        newNodes.containsKey(nodeToRemove.parentId)) {
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

    // Validate all children exist before mutating
    for (final childId in children) {
      if (!newNodes.containsKey(childId)) {
        throw StateError('Reorder failed: node $childId not found');
      }
    }

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
      final newChildIds =
          oldParent.childIds.where((id) => id != nodeId).toList();
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
    SequenceNode duplicateRecursive(
        SequenceNode original, String? newParentId) {
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
        newNodes[childId] =
            newNodes[childId]!.copyWith(parentId: newWrapper.id);
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

    final targets = state!.targetHeaders;
    if (oldIndex < 0 || oldIndex >= targets.length) return;

    // Handle flutter reorder index adjustment
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= targets.length) return;

    final oldTarget = targets[oldIndex];
    final newTarget = targets[newIndex];

    // Only support reordering if they are siblings (share same parent)
    if (oldTarget.parentId == newTarget.parentId &&
        oldTarget.parentId != null) {
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

    // Find the anchor: last single-selected node or first in current selection
    final anchor = ref.read(selectedNodeIdProvider) ?? state.lastOrNull;
    if (anchor == null) {
      // No anchor, just select this node
      state = {nodeId};
      return;
    }

    final anchorNode = sequence.nodes[anchor];
    if (anchorNode == null ||
        anchorNode.parentId == null ||
        anchorNode.parentId != node.parentId) {
      // Different parents or invalid anchor — just toggle
      state = {nodeId};
      return;
    }

    // Get siblings sorted by orderIndex
    final siblings = sequence.getChildren(node.parentId!);
    final anchorIndex =
        siblings.indexWhere((n) => n.id == anchor);
    final targetIndex =
        siblings.indexWhere((n) => n.id == nodeId);

    if (anchorIndex < 0 || targetIndex < 0) {
      state = {nodeId};
      return;
    }

    final start =
        anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end =
        anchorIndex < targetIndex ? targetIndex : anchorIndex;

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

    // Determine paste target: the single selected node's parent, or root
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
  Map<String, dynamic>? _serializeNodeTree(
      Sequence sequence, String nodeId) {
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

    // Create a new copy with a fresh ID
    final newNode = originalNode.copyWith(
      id: const Uuid().v4(),
      parentId: parentId,
      childIds: [],
    );
    notifier.addNode(newNode, parentId: parentId);

    // Recursively paste children
    for (final childTree in children) {
      _pasteNodeTree(notifier, sequence, childTree, newNode.id);
    }
  }
}

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
  final executor = SequenceExecutor(ref);
  // Owned timers/subscriptions must be torn down with the provider lifetime —
  // otherwise an invalidation mid-sequence leaks the periodic progress timer,
  // the checkpoint timer, and the native event stream subscription past the
  // disposed Ref. stop() handles the running case; this handles teardown.
  ref.onDispose(executor.dispose);
  return executor;
});

class SequenceExecutor {
  final Ref _ref;
  Timer? _progressTimer;
  DateTime? _startTime;
  bool _isPaused = false;
  StreamSubscription? _nativeEventSubscription;
  Timer? _checkpointTimer;
  bool _runFinalized = false;
  /// Subscriptions for propagating settings changes to the backend mid-sequence
  final List<ProviderSubscription> _settingsSubscriptions = [];
  LoggingService get _logger => _ref.read(loggingServiceProvider);

  SequenceExecutor(this._ref);

  /// Check if native execution is enabled in settings
  bool get _useNativeExecution {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useNativeExecution ?? false;
    } catch (error, stack) {
      _logger.warning(
        'Failed to read useNativeExecution setting; defaulting to false: $error\n$stack',
        source: 'SequenceExecutor',
      );
      return false;
    }
  }

  /// Check if simulation mode is enabled in settings
  bool get _useSimulationMode {
    if (kReleaseMode) {
      return false;
    }
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      return settings?.useSimulationMode ?? false;
    } catch (error, stack) {
      _logger.warning(
        'Failed to read useSimulationMode setting; defaulting to false: $error\n$stack',
        source: 'SequenceExecutor',
      );
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

  /// Look up filter index from profile by name (case-insensitive)
  int? _lookupFilterIndex(String? filterName) {
    if (filterName == null || filterName.isEmpty) return null;
    final profile = _ref.read(activeEquipmentProfileProvider);
    if (profile == null) return null;
    final filterNames = profile.filterNames;
    for (int i = 0; i < filterNames.length; i++) {
      if (filterNames[i].toLowerCase() == filterName.toLowerCase()) {
        return i;
      }
    }
    return null;
  }

  /// Convert a Dart node to native config format
  Map<String, dynamic> _nodeToConfig(SequenceNode node) {
    if (node is ExposureNode) {
      final defaults = _ref.read(sequencerDefaultsProvider);
      // Auto-populate filter_index from profile if not set
      final filterIndex = node.filterIndex ?? _lookupFilterIndex(node.filter);
      return {
        'type': 'TakeExposure',
        'duration_secs': node.durationSecs,
        'count': node.count,
        'filter': node.filter,
        'filter_index': filterIndex,
        'gain': node.gain,
        'offset': node.offset,
        'binning': _binningToString(node.binning),
        'dither_every': node.ditherEvery,
        'dither_pixels': defaults.ditherPixels,
        'dither_settle_pixels': defaults.ditherSettlePixels,
        'dither_settle_time': defaults.ditherSettleTime,
        'dither_settle_timeout': defaults.ditherSettleTimeout,
        'dither_ra_only': defaults.ditherRaOnly,
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
        'settle_timeout': node.settleTimeout,
        'ra_only': node.raOnly,
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
      // Auto-populate filter_index from profile if not set
      final filterIndex =
          node.filterPosition ?? _lookupFilterIndex(node.filterName);
      return {
        'type': 'ChangeFilter',
        'filter_name': node.filterName,
        'filter_index': filterIndex,
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
        'target_temp': node.targetTemp,
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
        'wait_for_twilight': node.waitForTwilight != null
            ? _twilightToString(node.waitForTwilight!)
            : null,
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
        case LoopConditionType.altitudeAbove:
          conditionValue = node.repeatUntilAltitude;
          break;
        case LoopConditionType.integrationTime:
          conditionValue = node.repeatCount;
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
    } else if (node is OpenCoverNode) {
      return {
        'type': 'OpenCover',
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CloseCoverNode) {
      return {
        'type': 'CloseCover',
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CalibratorOnNode) {
      return {
        'type': 'CalibratorOn',
        'brightness': node.brightness,
        'timeout_secs': node.timeoutSecs,
      };
    } else if (node is CalibratorOffNode) {
      return {
        'type': 'CalibratorOff',
        'timeout_secs': node.timeoutSecs,
      };
    }

    throw StateError(
      'Unrecognized sequence node type "${node.runtimeType}" (name="${node.name}", id="${node.id}"). '
      'This node cannot be converted to a native executor config. '
      'Ensure all node types are handled in _nodeToConfig().',
    );
  }

  String _binningToString(BinningMode binning) {
    switch (binning) {
      case BinningMode.one:
        return 'One';
      case BinningMode.two:
        return 'Two';
      case BinningMode.three:
        return 'Three';
      case BinningMode.four:
        return 'Four';
    }
  }

  String _autofocusMethodToString(AutofocusMethod method) {
    switch (method) {
      case AutofocusMethod.vCurve:
        return 'VCurve';
      case AutofocusMethod.hyperbolic:
        return 'Hyperbolic';
      case AutofocusMethod.quadratic:
        return 'Quadratic';
    }
  }

  String _twilightToString(TwilightType type) {
    switch (type) {
      case TwilightType.civil:
        return 'Civil';
      case TwilightType.nautical:
        return 'Nautical';
      case TwilightType.astronomical:
        return 'Astronomical';
    }
  }

  String _notificationLevelToString(NotificationLevel level) {
    switch (level) {
      case NotificationLevel.info:
        return 'Info';
      case NotificationLevel.warning:
        return 'Warning';
      case NotificationLevel.error:
        return 'Error';
      case NotificationLevel.success:
        return 'Success';
    }
  }

  String _loopConditionToString(LoopConditionType type) {
    switch (type) {
      case LoopConditionType.count:
        return 'Count';
      case LoopConditionType.untilTime:
        return 'UntilTime';
      case LoopConditionType.untilAltitude:
        return 'AltitudeBelow';
      case LoopConditionType.altitudeAbove:
        return 'AltitudeAbove';
      case LoopConditionType.integrationTime:
        return 'IntegrationTime';
      case LoopConditionType.forever:
        return 'Forever';
      case LoopConditionType.whileDark:
        return 'WhileDark';
    }
  }

  String _conditionalTypeToString(ConditionalType type) {
    switch (type) {
      case ConditionalType.always:
        return 'Always';
      case ConditionalType.altitudeAbove:
        return 'AltitudeAbove';
      case ConditionalType.timeAfter:
        return 'TimeAfter';
      case ConditionalType.guidingRmsBelow:
        return 'GuidingRmsBelow';
      case ConditionalType.hfrBelow:
        return 'HfrBelow';
      case ConditionalType.weatherSafe:
        return 'WeatherSafe';
      case ConditionalType.moonSeparationAbove:
        return 'MoonSeparationAbove';
      case ConditionalType.safetyMonitorSafe:
        return 'SafetyMonitorSafe';
    }
  }

  String _recoveryActionToString(RecoveryActionType action) {
    switch (action) {
      case RecoveryActionType.continueExecution:
        return 'Continue';
      case RecoveryActionType.pause:
        return 'Pause';
      case RecoveryActionType.autofocus:
        return 'Autofocus';
      case RecoveryActionType.nextTarget:
        return 'NextTarget';
      case RecoveryActionType.retry:
        return 'Retry';
      case RecoveryActionType.parkAndAbort:
        return 'ParkAndAbort';
      case RecoveryActionType.customBranch:
        return 'CustomBranch';
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
            message:
                'Target "${node.name}" has invalid RA (must be 0-24 hours)',
            nodeId: node.id,
          ));
        }
        if (node.decDegrees < -90 || node.decDegrees > 90) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message:
                'Target "${node.name}" has invalid Dec (must be -90 to +90 degrees)',
            nodeId: node.id,
          ));
        }
      }

      // Check unbounded loops without safety limits
      if (node is LoopNode && node.isUnbounded && node.maxSafetyIterations == null) {
        issues.add(SequenceValidationIssue(
          severity: ValidationSeverity.warning,
          message:
              'Loop "${node.name}" has no safety iteration limit and could run indefinitely',
          nodeId: node.id,
        ));
      }

      // Check slew coordinates
      if (node is SlewNode && !node.useTargetCoords) {
        if (node.customRa != null &&
            (node.customRa! < 0 || node.customRa! > 24)) {
          issues.add(SequenceValidationIssue(
            severity: ValidationSeverity.error,
            message: 'Slew "${node.name}" has invalid RA',
            nodeId: node.id,
          ));
        }
        if (node.customDec != null &&
            (node.customDec! < -90 || node.customDec! > 90)) {
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
    final errors =
        issues.where((i) => i.severity == ValidationSeverity.error).toList();
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
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    // Start session tracking
    final sessionNotifier = _ref.read(sessionStateProvider.notifier);
    await sessionNotifier.startSession(
      targetName: sequence.name,
      // Use first target coordinates if available
      targetRa: sequence.targetHeaders.isNotEmpty
          ? sequence.targetHeaders.first.raHours
          : null,
      targetDec: sequence.targetHeaders.isNotEmpty
          ? sequence.targetHeaders.first.decDegrees
          : null,
    );
    sessionNotifier.setTotalExposures(sequence.totalExposures);
    final runId = await _ref.read(sequenceRunsDaoProvider).startRun(
          sequenceId: sequence.databaseId,
          sequenceName: sequence.name,
        );
    _ref.read(currentRunIdProvider.notifier).state = runId;
    _ref.read(liveSequenceStatsProvider.notifier).state = SequenceRunStats();
    _runFinalized = false;

    _startTime = DateTime.now();
    _isPaused = false;

    // Start progress timer with ETA computation
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final completedFrames = progress.completedExposures;
        final totalFrames = progress.totalExposures;
        double? eta;
        if (completedFrames > 0 && totalFrames > 0) {
          final remainingFrames = totalFrames - completedFrames;
          if (remainingFrames > 0) {
            // Wall-clock elapsed includes overhead (download, dither, slew, etc.)
            final avgSecsPerFrame = elapsed / completedFrames;
            eta = avgSecsPerFrame * remainingFrames;
          } else {
            eta = 0.0;
          }
        }
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    // Start checkpoint auto-save timer
    _startCheckpointTimer();

    if (!_useNativeExecution) {
      _logger.warning(
        'Legacy Dart sequencer path is deprecated; forcing backend executor for deterministic behavior',
        source: 'SequenceExecutor',
      );
    }

    // Always use backend/native sequencer engine to avoid divergent semantics.
    await _startNativeExecution(sequence);
  }

  Future<void> _startNativeExecution(Sequence sequence) async {
    final backend = _ref.read(backendProvider);

    // Sync observer location to Rust backend before starting sequence
    // This ensures the sequencer has access to the current location from settings
    final settingsAsync = _ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    _logger.debug(
        '_startNativeExecution: settings=${settings != null ? "loaded" : "null"}',
        source: 'SequenceExecutor');
    if (settings != null) {
      _logger.debug(
          'Location from settings: lat=${settings.latitude}, lon=${settings.longitude}, elev=${settings.elevation}',
          source: 'SequenceExecutor');
    }
    if (settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0)) {
      _logger.debug('Syncing location to backend...',
          source: 'SequenceExecutor');
      await backend.setLocation(ObserverLocation(
        latitude: settings.latitude,
        longitude: settings.longitude,
        elevation: settings.elevation,
      ));
      _logger.debug('Location sync complete', source: 'SequenceExecutor');
    } else {
      _logger.debug('Skipping location sync: settings null or location is 0,0',
          source: 'SequenceExecutor');
    }

    // Simulation is disabled in release builds.
    if (kReleaseMode) {
      await backend.sequencerSetSimulationMode(false);
    } else {
      await backend.sequencerSetSimulationMode(_useSimulationMode);
    }

    // Set safety fail mode from app settings
    if (settings != null) {
      // Strict fail-closed behavior is enforced at runtime.
      final modeString = 'fail_closed';
      await backend.sequencerSetSafetyFailMode(modeString);
      _logger.debug('Safety fail mode set to: $modeString',
          source: 'SequenceExecutor');
    }

    // Set save path for captured images
    final savePath = settings?.imageOutputPath;
    if (savePath != null && savePath.isNotEmpty) {
      await backend.sequencerSetSavePath(savePath);
      _logger.debug('Save path set to: $savePath', source: 'SequenceExecutor');
    } else {
      await backend.sequencerSetSavePath(null);
      _logger.warning(
          'No save path configured - images will NOT be saved to disk!',
          source: 'SequenceExecutor');
    }

    // Get connected device IDs from equipment providers
    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final filterwheelState = _ref.read(filterWheelStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);

    // Pass connected device IDs to the sequencer
    final cameraId =
        cameraState.connectionState == DeviceConnectionState.connected
            ? cameraState.deviceId
            : null;
    final mountId =
        mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : null;
    final focuserId =
        focuserState.connectionState == DeviceConnectionState.connected
            ? focuserState.deviceId
            : null;
    final filterwheelId =
        filterwheelState.connectionState == DeviceConnectionState.connected
            ? filterwheelState.deviceId
            : null;
    final rotatorId =
        rotatorState.connectionState == DeviceConnectionState.connected
            ? rotatorState.deviceId
            : null;

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
      onError: (e) =>
          _logger.error('Event stream error: $e', source: 'SequenceExecutor'),
    );

    // Watch for settings changes during execution and propagate to backend
    _startSettingsWatchers(backend);

    // Start the execution via backend
    await backend.sequencerStart();
  }

  /// Start watching for settings changes that should be propagated to the
  /// backend executor during sequence execution (dither config, location,
  /// filter offsets).
  void _startSettingsWatchers(NightshadeBackend backend) {
    _stopSettingsWatchers(); // Clean up any existing watchers

    // Watch dither settings changes
    _settingsSubscriptions.add(
      _ref.listen(sequencerDefaultsProvider, (previous, next) {
        if (previous == null) return;
        if (previous.ditherPixels != next.ditherPixels ||
            previous.ditherSettlePixels != next.ditherSettlePixels ||
            previous.ditherSettleTime != next.ditherSettleTime ||
            previous.ditherSettleTimeout != next.ditherSettleTimeout ||
            previous.ditherRaOnly != next.ditherRaOnly) {
          _logger.debug(
            'Dither settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateDitherConfig(
            pixels: next.ditherPixels,
            settlePixels: next.ditherSettlePixels,
            settleTime: next.ditherSettleTime,
            settleTimeout: next.ditherSettleTimeout,
            raOnly: next.ditherRaOnly,
          );
        }
      }),
    );

    // Watch location changes
    _settingsSubscriptions.add(
      _ref.listen(appSettingsProvider, (previous, next) {
        final prevSettings = previous?.valueOrNull;
        final nextSettings = next.valueOrNull;
        if (prevSettings == null || nextSettings == null) return;
        if (prevSettings.latitude != nextSettings.latitude ||
            prevSettings.longitude != nextSettings.longitude) {
          _logger.debug(
            'Location changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateLocation(
            latitude: nextSettings.latitude,
            longitude: nextSettings.longitude,
          );
        }
      }),
    );

    // Watch filter focus offset changes from active equipment profile
    _settingsSubscriptions.add(
      _ref.listen(activeEquipmentProfileProvider, (previous, next) {
        if (previous == null || next == null) return;
        final prevRaw = previous.filterFocusOffsets;
        final nextRaw = next.filterFocusOffsets;
        if (prevRaw != nextRaw) {
          _logger.debug(
            'Filter focus offsets changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          // filterFocusOffsets is a JSON-encoded string; decode to Map<String, int>
          Map<String, int> offsets = {};
          if (nextRaw != null && nextRaw.isNotEmpty) {
            try {
              final decoded = json.decode(nextRaw) as Map<String, dynamic>;
              offsets = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
            } catch (e) {
              _logger.error(
                'Failed to decode filter focus offsets: $e',
                source: 'SequenceExecutor',
              );
              return;
            }
          }
          backend.sequencerUpdateFilterOffsets(offsets);
        }
      }),
    );
  }

  /// Stop all settings watchers
  void _stopSettingsWatchers() {
    for (final sub in _settingsSubscriptions) {
      sub.close();
    }
    _settingsSubscriptions.clear();
  }

  /// Handle events from the backend (native or remote)
  void _handleSequencerEvent(NightshadeEvent event) {
    // Log all events to verify handler is being called
    _logger.debug(
        'Received event: type=${event.eventType}, category=${event.category}',
        source: 'SequenceExecutor');

    // Handle imaging events for image preview during sequences
    // This MUST be before the category filter since ExposureComplete has category=imaging
    if (event.category == EventCategory.imaging &&
        event.eventType == 'ExposureComplete') {
      _logger.debug(
          'ExposureComplete imaging event received - fetching image for preview',
          source: 'SequenceExecutor');
      final durationSecs =
          (event.data['duration_secs'] as num?)?.toDouble() ?? 2.0;
      _fetchAndDisplaySequenceImage(durationSecs);
      return;
    }

    // Only process sequencer events for progress tracking
    if (event.category != EventCategory.sequencer) return;

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);

    switch (event.eventType) {
      case 'NodeStarted':
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final nodeName = event.data['node_type'] as String? ??
            event.data['nodeName'] as String?;
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
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final statusStr = event.data['status'] as String? ?? 'failed';
        final nodeStatus = switch (statusStr) {
          'success' => NodeStatus.success,
          'skipped' => NodeStatus.skipped,
          'cancelled' => NodeStatus.skipped,
          _ => NodeStatus.failure,
        };
        if (nodeId != null) {
          progressNotifier.updateNodeStatus(nodeId, nodeStatus);
        }
        break;

      case 'ExposureStarted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        final filter = event.data['filter'] as String?;
        final exposureDetail =
            'Frame $frame/$total${filter != null ? ' ($filter)' : ''}';
        progressNotifier.updateProgress(
          message: 'Exposing $exposureDetail',
          currentFilter: filter,
        );
        // Update node-specific progress for progress panels
        final exposureNodeId =
            _ref.read(sequenceProgressProvider).currentNodeId;
        if (exposureNodeId != null && total > 0) {
          final exposurePercent = (frame - 1) /
              total *
              100.0; // frame-1 because exposure just started
          progressNotifier.updateNodeProgress(
              exposureNodeId, exposurePercent, exposureDetail);
        }
        break;

      case 'ExposureCompleted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 1;
        final durationSecs =
            (event.data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        _recordRunFrame(
          exposureSecs: durationSecs,
          filter: event.data['filter'] as String?,
          accepted: true,
        );
        // Calculate new completed integration time
        final newCompletedIntegration =
            _ref.read(sequenceProgressProvider).completedIntegrationSecs +
                durationSecs;
        progressNotifier.updateProgress(
          completedExposures: frame,
          completedIntegrationSecs: newCompletedIntegration,
        );
        // Update node-specific progress for progress panels
        final completedNodeId =
            _ref.read(sequenceProgressProvider).currentNodeId;
        if (completedNodeId != null) {
          final completedPercent = total > 0 ? (frame / total * 100.0) : 100.0;
          progressNotifier.updateNodeProgress(
              completedNodeId, completedPercent, 'Completed $frame/$total');
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
        final name = event.data['target_name'] as String? ??
            event.data['name'] as String?;
        final ra = (event.data['ra'] as num?)?.toDouble();
        final dec = (event.data['dec'] as num?)?.toDouble();
        progressNotifier.updateProgress(
          currentTarget: name,
          message: name != null ? 'Started target: $name' : null,
        );
        // Update session with target coordinates if available
        if (name != null && ra != null && dec != null) {
          _logger.debug(
            'Target changed: $name (RA=${ra.toStringAsFixed(4)}h, Dec=${dec.toStringAsFixed(4)}°)',
            source: 'SequenceExecutor',
          );
          final sessionNotifier = _ref.read(sessionStateProvider.notifier);
          sessionNotifier.updateTargetCoordinates(ra: ra, dec: dec);
        }
        break;

      case 'TargetCompleted':
        final name = event.data['target_name'] as String? ??
            event.data['name'] as String?;
        progressNotifier.updateProgress(
          message: 'Completed target: ${name ?? 'unknown'}',
        );
        break;

      case 'Error':
        final message = event.data['message'] as String? ?? 'Unknown error';
        _recordRunError(message);
        progressNotifier.updateProgress(message: 'Error: $message');
        // Update node-specific progress with error message for progress panels
        final errorNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (errorNodeId != null) {
          progressNotifier.updateNodeProgress(
              errorNodeId, 0.0, 'Error: $message');
        }
        break;

      case 'InstructionProgress':
        // Handle instruction progress updates from long-running instructions
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent =
            (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detail = event.data['detail'] as String? ?? '';

        _logger.debug(
            'InstructionProgress: nodeId=$nodeId, instruction=$instruction, progress=$progressPercent%, detail=$detail',
            source: 'SequenceExecutor');

        // Use node_id from event, fallback to currentNodeId for backwards compatibility
        final targetNodeId =
            nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        _logger.debug('Updating node progress for: $targetNodeId',
            source: 'SequenceExecutor');
        if (targetNodeId != null) {
          progressNotifier.updateNodeProgress(
              targetNodeId, progressPercent, detail);
          // Also update the global message to show current instruction progress
          progressNotifier.updateProgress(
            message: '$instruction: $detail',
          );
        }
        break;

      case 'TriggerFired':
        final triggerName =
            event.data['trigger_name'] as String? ?? 'Unknown trigger';
        final action = event.data['action'] as String? ?? '';
        _incrementRunStat((stats) => stats.recordTriggerFire());
        _logger.info(
            'Trigger fired: $triggerName -> $action',
            source: 'SequenceExecutor');
        progressNotifier.updateProgress(
          message: 'Trigger "$triggerName" fired: $action',
        );
        break;

      case 'Started':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Paused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
        break;

      case 'Resumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Completed':
      case 'SequenceCompleted':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('completed');
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.completed;
        break;

      case 'SequenceFailed':
        final error = event.data['error'] as String? ?? 'Unknown error';
        _stopSettingsWatchers();
        _recordRunError(error);
        _finalizeRun('failed');
        progressNotifier.updateProgress(message: error);
        progressNotifier.updateState(SequenceExecutionState.failed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.failed;
        break;

      case 'Stopped':
      case 'SequenceStopped':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('stopped');
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.idle;
        break;
    }
  }

  void _recordRunFrame({
    required double exposureSecs,
    required bool accepted,
    String? filter,
  }) {
    _incrementRunStat((stats) {
      final progress = _ref.read(sequenceProgressProvider);
      stats.recordFrame(
        target: progress.currentTarget ??
            _ref.read(currentSequenceProvider)?.name ??
            'Sequence',
        filter: (filter != null && filter.isNotEmpty) ? filter : 'Unknown',
        exposureSecs: exposureSecs,
        accepted: accepted,
      );
    });
  }

  void _recordRunError(String message) {
    _incrementRunStat((stats) => stats.recordError(message));
  }

  void _incrementRunStat(void Function(SequenceRunStats stats) update) {
    final stats = _ref.read(liveSequenceStatsProvider);
    if (stats == null) {
      return;
    }
    update(stats);
    _ref.read(liveSequenceStatsProvider.notifier).state = stats;
    _persistLiveRunStats();
  }

  void _persistLiveRunStats() {
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    unawaited(
      _ref.read(sequenceRunsDaoProvider).updateStats(runId, stats.toJson()),
    );
  }

  void _finalizeRun(String status) {
    if (_runFinalized) {
      return;
    }
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    _runFinalized = true;
    stats.endTime = DateTime.now();
    final statsJson = stats.toJson();
    unawaited(
      _ref.read(sequenceRunsDaoProvider).finishRun(runId, status, statsJson),
    );
  }

  /// Fetch the last captured image and update the UI providers
  /// This ensures sequence images are displayed in the Imaging tab and Dashboard
  void _fetchAndDisplaySequenceImage(double durationSecs) {
    // Run async fetch in a fire-and-forget manner
    Future(() async {
      try {
        // Get the camera device ID for fetching the last image
        final cameraState = _ref.read(cameraStateProvider);
        final cameraDeviceId = cameraState.deviceId;
        if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
          _logger.debug('No camera device ID available, skipping image fetch',
              source: 'SequenceExecutor');
          return;
        }
        final backend = _ref.read(backendProvider);
        final capturedImage = await backend.cameraGetLastImage(cameraDeviceId);
        if (capturedImage == null) {
          _logger.debug('No image data available from camera',
              source: 'SequenceExecutor');
          return;
        }

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
        _logger.warning('Failed to fetch sequence image for display: $e',
            source: 'SequenceExecutor');
      }
    });
  }

  bool _pauseResumeInProgress = false;

  /// Wait for state change with timeout
  Future<bool> _awaitStateChange(SequenceExecutionState expectedState,
      {Duration timeout = const Duration(seconds: 5)}) async {
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
      final backend = _ref.read(backendProvider);
      await backend.sequencerPause();

      // Wait for confirmation from event system
      final confirmed = await _awaitStateChange(SequenceExecutionState.paused);
      if (!confirmed) {
        final status = await backend.sequencerGetStatus();
        if (status.state.toLowerCase() != 'paused') {
          throw Exception('Pause operation timed out - state not confirmed');
        }
        _ref
            .read(sequenceProgressProvider.notifier)
            .updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
      }

      // Sync local state
      _isPaused = true;
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
      final backend = _ref.read(backendProvider);
      await backend.sequencerResume();

      // Wait for confirmation from event system
      final confirmed = await _awaitStateChange(SequenceExecutionState.running);
      if (!confirmed) {
        final status = await backend.sequencerGetStatus();
        if (status.state.toLowerCase() != 'running') {
          throw Exception('Resume operation timed out - state not confirmed');
        }
        _ref
            .read(sequenceProgressProvider.notifier)
            .updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
      }

      // Sync local state
      _isPaused = false;
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
    _stopSettingsWatchers();
    _startTime = null;
    _isPaused = false;
    _ref
        .read(sequenceProgressProvider.notifier)
        .updateState(SequenceExecutionState.idle);
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;
    _finalizeRun('stopped');

    // End session
    _ref.read(sessionStateProvider.notifier).endSession(status: 'stopped');

    final backend = _ref.read(backendProvider);
    await backend.sequencerStop();

    // Clear checkpoint when stopped gracefully
    try {
      await backend.discardCheckpoint();
    } catch (e) {
      // Ignore errors during cleanup
      _logger.warning('Failed to clear checkpoint on stop: $e',
          source: 'SequenceExecutor');
    }
  }

  Future<void> skip() async {
    final backend = _ref.read(backendProvider);
    await backend.sequencerSkip();
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

    final backend = _ref.read(backendProvider);
    try {
      await backend.sequencerReset();
    } catch (e) {
      _logger.warning('Error resetting native sequencer: $e',
          source: 'SequenceExecutor');
      // Continue anyway - the Dart-side reset is more important
    }

    // Clear any checkpoints
    try {
      await backend.discardCheckpoint();
    } catch (e) {
      _logger.warning('Error clearing checkpoint on reset: $e',
          source: 'SequenceExecutor');
    }

    // Ensure we're in idle state
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.idle;

    _logger.info('Sequence reset - ready to run from beginning',
        source: 'SequenceExecutor');
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
    _ref.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    // Restore completed exposures and integration time
    progressNotifier.updateProgress(
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      message: 'Resuming from checkpoint...',
    );

    _startTime = DateTime.now();
    _isPaused = false;

    // Start progress timer with ETA computation
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _startTime != null) {
        final elapsed =
            DateTime.now().difference(_startTime!).inSeconds.toDouble();
        final progress = _ref.read(sequenceProgressProvider);
        final completedFrames = progress.completedExposures;
        final totalFrames = progress.totalExposures;
        double? eta;
        if (completedFrames > 0 && totalFrames > 0) {
          final remainingFrames = totalFrames - completedFrames;
          if (remainingFrames > 0) {
            final avgSecsPerFrame = elapsed / completedFrames;
            eta = avgSecsPerFrame * remainingFrames;
          } else {
            eta = 0.0;
          }
        }
        progressNotifier.updateProgress(
          elapsedSecs: elapsed,
          estimatedRemainingSecs: eta,
        );
      }
    });

    // Start checkpoint auto-save timer (every 30 seconds)
    _startCheckpointTimer();

    // Subscribe to backend events for progress updates
    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
    );

    // Resume from checkpoint in backend executor
    await backend.resumeFromCheckpoint();
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
      if (_ref.read(sequenceExecutionStateProvider) ==
          SequenceExecutionState.running) {
        try {
          final backend = _ref.read(backendProvider);
          await backend.saveCheckpoint();
        } catch (e) {
          // Log error but don't interrupt sequence
          _logger.warning('Failed to save checkpoint: $e',
              source: 'SequenceExecutor');
        }
      }
    });
  }

  /// Cancel all owned timers and subscriptions.
  ///
  /// Wired into the owning Provider's `ref.onDispose`. Safe to call even when
  /// no sequence is running — all cancels are null-tolerant. Distinct from
  /// `stop()`, which also mutates execution state and ends the session.
  void dispose() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;
  }
}

// =============================================================================
// NODE PALETTE
// =============================================================================

/// Provider for sequencer default settings (persisted)
final sequencerDefaultsProvider =
    StateNotifierProvider<SequencerDefaultsNotifier, SequencerDefaults>((ref) {
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
  final double ditherSettleTimeout;
  final bool ditherRaOnly;

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
    this.ditherSettleTimeout = 120.0,
    this.ditherRaOnly = false,
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
    double? ditherSettleTimeout,
    bool? ditherRaOnly,
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
      autofocusExposureDuration:
          autofocusExposureDuration ?? this.autofocusExposureDuration,
      ditherPixels: ditherPixels ?? this.ditherPixels,
      ditherSettleTime: ditherSettleTime ?? this.ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels ?? this.ditherSettlePixels,
      ditherSettleTimeout: ditherSettleTimeout ?? this.ditherSettleTimeout,
      ditherRaOnly: ditherRaOnly ?? this.ditherRaOnly,
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

    final stepSize = int.tryParse(
            await settingsDao.getSetting('sequencer_autofocus_step_size') ??
                '100') ??
        100;
    final stepsOut = int.tryParse(
            await settingsDao.getSetting('sequencer_autofocus_steps_out') ??
                '7') ??
        7;
    final exposureDuration = double.tryParse(await settingsDao
                .getSetting('sequencer_autofocus_exposure_duration') ??
            '3.0') ??
        3.0;

    final ditherPixels = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_pixels') ?? '5.0') ??
        5.0;
    final ditherSettleTime = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_time') ??
                '30.0') ??
        30.0;
    final ditherSettlePixels = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_pixels') ??
                '1.5') ??
        1.5;
    final ditherSettleTimeout = double.tryParse(
            await settingsDao.getSetting('sequencer_dither_settle_timeout') ??
                '120.0') ??
        120.0;
    final ditherRaOnly =
        (await settingsDao.getSetting('sequencer_dither_ra_only') ?? 'false') ==
            'true';

    final exposureDurationDefault = double.tryParse(
            await settingsDao.getSetting('sequencer_exposure_duration') ??
                '60.0') ??
        60.0;
    final exposureCount = int.tryParse(
            await settingsDao.getSetting('sequencer_exposure_count') ?? '10') ??
        10;
    final exposureFilter =
        await settingsDao.getSetting('sequencer_exposure_filter');
    final exposureGainStr =
        await settingsDao.getSetting('sequencer_exposure_gain');
    final exposureGain =
        exposureGainStr != null ? int.tryParse(exposureGainStr) : null;
    final exposureOffsetStr =
        await settingsDao.getSetting('sequencer_exposure_offset');
    final exposureOffset =
        exposureOffsetStr != null ? int.tryParse(exposureOffsetStr) : null;
    final exposureBinningStr =
        await settingsDao.getSetting('sequencer_exposure_binning') ?? 'one';
    final exposureBinning = BinningMode.values.firstWhere(
      (e) => e.name == exposureBinningStr,
      orElse: () => BinningMode.one,
    );
    final exposureDitherEvery = int.tryParse(
            await settingsDao.getSetting('sequencer_exposure_dither_every') ??
                '1') ??
        1;

    state = SequencerDefaults(
      autofocusStepSize: stepSize,
      autofocusStepsOut: stepsOut,
      autofocusExposureDuration: exposureDuration,
      ditherPixels: ditherPixels,
      ditherSettleTime: ditherSettleTime,
      ditherSettlePixels: ditherSettlePixels,
      ditherSettleTimeout: ditherSettleTimeout,
      ditherRaOnly: ditherRaOnly,
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
      updates['sequencer_autofocus_exposure_duration'] =
          exposureDuration.toString();
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
    double? settleTimeout,
    bool? raOnly,
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
    if (settleTimeout != null) {
      updates['sequencer_dither_settle_timeout'] = settleTimeout.toString();
      state = state.copyWith(ditherSettleTimeout: settleTimeout);
    }
    if (raOnly != null) {
      updates['sequencer_dither_ra_only'] = raOnly.toString();
      state = state.copyWith(ditherRaOnly: raOnly);
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

/// Helper to convert int binning value to BinningMode enum
BinningMode _binningModeFromInt(int binning) {
  switch (binning) {
    case 1:
      return BinningMode.one;
    case 2:
      return BinningMode.two;
    case 3:
      return BinningMode.three;
    case 4:
      return BinningMode.four;
    default:
      return BinningMode.one;
  }
}

/// Available node types for the palette
final nodePaletteProvider = Provider<List<NodePaletteCategory>>((ref) {
  final defaults = ref.watch(sequencerDefaultsProvider);
  final profile = ref.watch(activeEquipmentProfileProvider);

  // Use profile defaults as fallback when sequencer defaults are not set
  final effectiveGain = defaults.exposureGain ?? profile?.defaultGain;
  final effectiveOffset = defaults.exposureOffset ?? profile?.defaultOffset;
  final effectiveBinning = defaults.exposureBinning != BinningMode.one
      ? defaults.exposureBinning
      : _binningModeFromInt(profile?.defaultBinX ?? 1);
  final effectiveFilter =
      defaults.exposureFilter ?? profile?.filterNames.firstOrNull;

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
            filter: effectiveFilter,
            gain: effectiveGain,
            offset: effectiveOffset,
            binning: effectiveBinning,
            ditherEvery: defaults.exposureDitherEvery,
          ),
        ),
        NodePaletteItem(
          name: 'Change Filter',
          icon: 'circle',
          description: 'Change the filter wheel position',
          createNode: () => FilterChangeNode(
            filterName: effectiveFilter ?? 'L',
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
            settleTimeout: defaults.ditherSettleTimeout,
            raOnly: defaults.ditherRaOnly,
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
      name: 'Flat Panel',
      icon: 'lightbulb',
      items: [
        NodePaletteItem(
          name: 'Open Cover',
          icon: 'door-open',
          description: 'Open dust cover / flat panel lid',
          createNode: () => OpenCoverNode(),
        ),
        NodePaletteItem(
          name: 'Close Cover',
          icon: 'door-closed',
          description: 'Close dust cover / flat panel lid',
          createNode: () => CloseCoverNode(),
        ),
        NodePaletteItem(
          name: 'Calibrator On',
          icon: 'lightbulb',
          description: 'Turn on flat panel at brightness',
          createNode: () => CalibratorOnNode(),
        ),
        NodePaletteItem(
          name: 'Calibrator Off',
          icon: 'lightbulb-off',
          description: 'Turn off flat panel light',
          createNode: () => CalibratorOffNode(),
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
  final List<SequenceNode> Function()? createChildren;

  NodePaletteItem({
    required this.name,
    required this.icon,
    required this.description,
    required this.createNode,
    this.createChildren,
  });
}
