import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/imaging/imaging_models.dart';
import '../../models/sequence/sequence_models.dart';
import '../../models/sequence/template_snippet.dart';

/// Editor StateNotifier for the sequence currently being authored.
///
/// Holds undo/redo stacks plus tree-mutation helpers. The notifier itself is
/// stateful but owns no streams or timers, so it does not require a dispose
/// override — Riverpod tears down the underlying state when the provider is
/// disposed.
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
  /// If no sequence exists, one will be created automatically so that targets
  /// can be added from anywhere without requiring the sequencer tab to be opened first.
  void addTargetHeader(TargetHeaderNode targetNode) {
    if (state == null) {
      createSequence();
    }
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
    _saveUndo();

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

      final node = _deserializeSnippetNode(nodeJson);
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

  /// Remove a node from the sequence
  void removeNode(String nodeId) {
    if (state == null) return;
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

  /// Reorder target groups (helper for Targets tab)
  void reorderTargets(int oldIndex, int newIndex) {
    if (state == null) return;

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

    // Only support reordering if they are siblings (share same parent)
    if (oldTarget.parentId == newTarget.parentId &&
        oldTarget.parentId != null) {
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
}
