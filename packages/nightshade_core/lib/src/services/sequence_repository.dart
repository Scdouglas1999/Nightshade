import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart' as db;
import '../database/daos/sequences_dao.dart';
import '../models/sequence/sequence_models.dart';
import '../providers/database_provider.dart';
import '../utils/json_validation.dart';

/// Repository for saving and loading sequences from the database
class SequenceRepository {
  final SequencesDao _dao;

  SequenceRepository(this._dao);

  /// Save a sequence to the database
  /// Returns the database ID of the saved sequence
  Future<int> saveSequence(Sequence sequence, {bool isTemplate = false}) async {
    // Check if this sequence already exists in database
    final existingId = sequence.databaseId;

    if (existingId != null) {
      // Update existing sequence
      await _updateSequence(existingId, sequence, isTemplate);
      return existingId;
    } else {
      // Create new sequence
      return await _createSequence(sequence, isTemplate);
    }
  }

  Future<int> _createSequence(Sequence sequence, bool isTemplate) async {
    // Create the sequence record
    final sequenceId = await _dao.createSequence(
      db.SequencesCompanion.insert(
        name: sequence.name,
        description: Value(sequence.description),
        rootNodeId: Value(sequence.rootNodeId),
        estimatedDurationMins: Value(
          (sequence.totalIntegrationSecs / 60).ceil(),
        ),
        isTemplate: Value(isTemplate),
      ),
    );

    // Save all nodes
    await _saveNodes(sequenceId, sequence.nodes);

    return sequenceId;
  }

  Future<void> _updateSequence(
      int sequenceId, Sequence sequence, bool isTemplate) async {
    // Get existing sequence
    final existing = await _dao.getSequenceById(sequenceId);
    if (existing == null) {
      throw Exception('Sequence $sequenceId not found');
    }

    // Update sequence metadata
    await _dao.updateSequence(
      db.Sequence(
        id: sequenceId,
        name: sequence.name,
        description: sequence.description,
        rootNodeId: sequence.rootNodeId,
        estimatedDurationMins: (sequence.totalIntegrationSecs / 60).ceil(),
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        isTemplate: isTemplate,
      ),
    );

    // Get existing nodes to diff against incoming nodes
    final existingNodes = await _dao.getNodesForSequence(sequenceId);
    final existingNodeIds = existingNodes.map((n) => n.nodeId).toSet();
    final incomingNodeIds = sequence.nodes.keys.toSet();

    // Determine which nodes to update, insert, or delete
    final toUpdate = existingNodeIds.intersection(incomingNodeIds);
    final toInsert = incomingNodeIds.difference(existingNodeIds);
    final toDelete = existingNodeIds.difference(incomingNodeIds);

    // Build a lookup from nodeId to database row for existing nodes
    final existingNodeMap = {
      for (final n in existingNodes) n.nodeId: n,
    };

    // Update existing nodes in place (preserves database row IDs)
    for (final nodeId in toUpdate) {
      final node = sequence.nodes[nodeId]!;
      final dbNode = existingNodeMap[nodeId]!;
      await _dao.updateNode(
        db.SequenceNode(
          id: dbNode.id,
          nodeId: node.id,
          sequenceId: sequenceId,
          targetId: dbNode.targetId,
          nodeType: _getNodeCategory(node),
          specificType: node.nodeType,
          name: node.name,
          properties: jsonEncode(_nodeToPropertiesWithComment(node)),
          // `recoveryConfig` is a legacy persistence field that is no longer
          // surfaced in the runtime model. Clearing it on save prevents stale
          // node-id references from surviving deletes and subsequent edits.
          recoveryConfig: null,
          parentNodeId: node.parentId,
          orderIndex: node.orderIndex,
          isEnabled: node.isEnabled,
        ),
      );
    }

    // Insert new nodes
    for (final nodeId in toInsert) {
      final node = sequence.nodes[nodeId]!;
      await _dao.createNode(
        db.SequenceNodesCompanion.insert(
          nodeId: node.id,
          sequenceId: sequenceId,
          nodeType: _getNodeCategory(node),
          specificType: node.nodeType,
          name: node.name,
          properties: Value(jsonEncode(_nodeToPropertiesWithComment(node))),
          parentNodeId: Value(node.parentId),
          orderIndex: Value(node.orderIndex),
          isEnabled: Value(node.isEnabled),
        ),
      );
    }

    // Delete removed nodes
    for (final nodeId in toDelete) {
      final dbNode = existingNodeMap[nodeId]!;
      await _dao.deleteNode(dbNode.id);
    }
  }

  Future<void> _saveNodes(
      int sequenceId, Map<String, SequenceNode> nodes) async {
    for (final node in nodes.values) {
      await _dao.createNode(
        db.SequenceNodesCompanion.insert(
          nodeId: node.id,
          sequenceId: sequenceId,
          nodeType: _getNodeCategory(node),
          specificType: node.nodeType,
          name: node.name,
          properties: Value(jsonEncode(_nodeToPropertiesWithComment(node))),
          parentNodeId: Value(node.parentId),
          orderIndex: Value(node.orderIndex),
          isEnabled: Value(node.isEnabled),
        ),
      );
    }
  }

  /// Map every node subtype to a serialized category string.
  ///
  /// `SequenceNode` is sealed, so every concrete subtype must be classified
  /// here — a new node type will produce a compile-time error rather than
  /// silently falling through to 'instruction'.
  String _getNodeCategory(SequenceNode node) {
    return switch (node) {
      TargetHeaderNode _ ||
      InstructionSetNode _ ||
      LoopNode _ ||
      ParallelNode _ ||
      ConditionalNode _ ||
      RecoveryNode _ =>
        'logic',
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
        'instruction',
    };
  }

  /// Load a sequence from the database
  Future<Sequence?> loadSequence(int sequenceId) async {
    final dbSequence = await _dao.getSequenceById(sequenceId);
    if (dbSequence == null) return null;

    final dbNodes = await _dao.getNodesForSequence(sequenceId);

    // Convert database nodes to model nodes
    final nodes = <String, SequenceNode>{};
    for (final dbNode in dbNodes) {
      final node = _dbNodeToModel(dbNode);
      if (node == null) {
        throw StateError(
          'Unsupported sequence node type '
          '"${dbNode.specificType}" for node ${dbNode.nodeId}',
        );
      }
      nodes[node.id] = node;
    }

    // Build child relationships
    for (final dbNode in dbNodes) {
      if (dbNode.parentNodeId != null &&
          nodes.containsKey(dbNode.parentNodeId)) {
        final parent = nodes[dbNode.parentNodeId!]!;
        final childIds = [...parent.childIds, dbNode.nodeId];
        nodes[dbNode.parentNodeId!] = parent.copyWith(childIds: childIds);
      }
    }

    return Sequence(
      id: dbSequence.id.toString(),
      databaseId: dbSequence.id,
      name: dbSequence.name,
      description: dbSequence.description ?? '',
      nodes: nodes,
      rootNodeId: dbSequence.rootNodeId,
      isTemplate: dbSequence.isTemplate,
      createdAt: dbSequence.createdAt,
      modifiedAt: dbSequence.updatedAt,
    );
  }

  /// Load all sequences from the database
  Future<List<Sequence>> loadAllSequences() async {
    final dbSequences = await _dao.getAllSequences();
    final sequences = <Sequence>[];

    for (final dbSequence in dbSequences) {
      final sequence = await loadSequence(dbSequence.id);
      if (sequence != null) {
        sequences.add(sequence);
      }
    }

    return sequences;
  }

  /// Load all templates from the database
  Future<List<Sequence>> loadAllTemplates() async {
    final dbTemplates = await _dao.getAllTemplates();
    final templates = <Sequence>[];

    for (final dbTemplate in dbTemplates) {
      final template = await loadSequence(dbTemplate.id);
      if (template != null) {
        templates.add(template);
      }
    }

    return templates;
  }

  /// Delete a sequence from the database
  Future<void> deleteSequence(int sequenceId) async {
    await _dao.deleteSequence(sequenceId);
  }

  /// Duplicate a sequence with fresh UUIDs for all nodes.
  ///
  /// Generates new UUIDs for every node and remaps all parent/child references
  /// so the duplicated sequence is fully independent from the original.
  Future<Sequence?> duplicateSequence(int sequenceId, String newName) async {
    // Load the source sequence with its full node tree
    final source = await loadSequence(sequenceId);
    if (source == null) {
      throw Exception('Sequence $sequenceId not found');
    }

    const uuid = Uuid();

    // Build a mapping from old node ID to new node ID
    final idMapping = <String, String>{};
    for (final oldId in source.nodes.keys) {
      idMapping[oldId] = uuid.v4();
    }

    // Remap the root node ID
    final newRootNodeId = source.rootNodeId != null
        ? idMapping[source.rootNodeId] ?? source.rootNodeId
        : null;

    // Rebuild nodes with new IDs, remapping parent and child references
    final newNodes = <String, SequenceNode>{};
    for (final entry in source.nodes.entries) {
      final oldNode = entry.value;
      final newId = idMapping[entry.key]!;
      final newParentId = oldNode.parentId != null
          ? idMapping[oldNode.parentId] ?? oldNode.parentId
          : null;
      final newChildIds = oldNode.childIds
          .map((childId) => idMapping[childId] ?? childId)
          .toList();

      final remappedNode = oldNode.copyWith(
        id: newId,
        parentId: newParentId,
        childIds: newChildIds,
      );
      newNodes[newId] = remappedNode;
    }

    // Create a new sequence with the remapped nodes
    final duplicated = Sequence(
      id: uuid.v4(),
      name: newName,
      description: source.description,
      nodes: newNodes,
      rootNodeId: newRootNodeId,
      isTemplate: source.isTemplate,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    final newDbId = await _createSequence(duplicated, source.isTemplate);
    return loadSequence(newDbId);
  }

  SequenceNode? _dbNodeToModel(db.SequenceNode dbNode) {
    final props = decodeJsonObjectString(
      dbNode.properties,
      context:
          'sequence_nodes.properties for node ${dbNode.nodeId} (${dbNode.specificType})',
    );

    switch (dbNode.specificType) {
      case 'exposure':
      case 'TakeExposure':
        return ExposureNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          durationSecs: (props['durationSecs'] as num?)?.toDouble() ?? 60.0,
          count: (props['count'] as num?)?.toInt() ?? 1,
          filter: props['filter'] as String?,
          filterIndex: (props['filterIndex'] as num?)?.toInt(),
          gain: (props['gain'] as num?)?.toInt(),
          offset: (props['offset'] as num?)?.toInt(),
          binning: _stringToBinning(props['binning'] as String?),
          ditherEvery: (props['ditherEvery'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'slew':
      case 'SlewToTarget':
        return SlewNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          useTargetCoords: props['useTargetCoords'] as bool? ?? true,
          customRa: (props['customRa'] as num?)?.toDouble(),
          customDec: (props['customDec'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'center':
      case 'CenterTarget':
        return CenterNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          useTargetCoords: props['useTargetCoords'] as bool? ?? true,
          customRa: (props['customRa'] as num?)?.toDouble(),
          customDec: (props['customDec'] as num?)?.toDouble(),
          accuracyArcsec: (props['accuracyArcsec'] as num?)?.toDouble() ?? 5.0,
          maxAttempts: (props['maxAttempts'] as num?)?.toInt() ?? 5,
          exposureDuration:
              (props['exposureDuration'] as num?)?.toDouble() ?? 5.0,
          filter: props['filter'] as String?,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'autofocus':
      case 'Autofocus':
        return AutofocusNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          method: _stringToAutofocusMethod(props['method'] as String?),
          stepSize: (props['stepSize'] as num?)?.toInt() ?? 100,
          stepsOut: (props['stepsOut'] as num?)?.toInt() ?? 7,
          exposureDuration:
              (props['exposureDuration'] as num?)?.toDouble() ?? 3.0,
          useSettingsDefaults: props['useSettingsDefaults'] as bool? ?? true,
          maxDurationSecs:
              (props['maxDurationSecs'] as num?)?.toDouble() ?? 600.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'dither':
      case 'Dither':
        return DitherNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          pixels: (props['pixels'] as num?)?.toDouble() ?? 5.0,
          settlePixels: (props['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (props['settleTime'] as num?)?.toDouble() ?? 30.0,
          settleTimeout: (props['settleTimeout'] as num?)?.toDouble() ?? 120.0,
          raOnly: props['raOnly'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'filterChange':
      case 'ChangeFilter':
        return FilterChangeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          filterName: props['filterName'] as String? ?? '',
          filterPosition: (props['filterPosition'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'coolCamera':
      case 'CoolCamera':
        return CoolCameraNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetTemp: (props['targetTemp'] as num?)?.toDouble() ?? -10.0,
          durationMins: (props['durationMins'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'warmCamera':
      case 'WarmCamera':
        return WarmCameraNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          ratePerMin: (props['ratePerMin'] as num?)?.toDouble() ?? 2.0,
          targetTemp: (props['targetTemp'] as num?)?.toDouble() ?? 20.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'rotator':
      case 'MoveRotator':
        return RotatorNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetAngle: (props['targetAngle'] as num?)?.toDouble() ?? 0.0,
          relative: props['relative'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'park':
      case 'Park':
        return ParkNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'unpark':
      case 'Unpark':
        return UnparkNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'waitTime':
      case 'WaitForTime':
        return WaitTimeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          waitUntil: props['waitUntil'] != null
              ? DateTime.fromMillisecondsSinceEpoch(props['waitUntil'] as int)
              : null,
          waitForTwilight:
              _stringToTwilight(props['waitForTwilight'] as String?),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'delay':
      case 'Delay':
        return DelayNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          seconds: (props['seconds'] as num?)?.toDouble() ?? 5.0,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'notification':
      case 'Notification':
        return NotificationNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          title: props['title'] as String? ?? '',
          message: props['message'] as String? ?? '',
          level: _stringToNotificationLevel(props['level'] as String?),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'script':
      case 'RunScript':
        return ScriptNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          scriptPath: props['scriptPath'] as String? ?? '',
          arguments:
              (props['arguments'] as List<dynamic>?)?.cast<String>() ?? [],
          timeoutSecs: (props['timeoutSecs'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'targetGroup':
      case 'TargetHeader':
        return TargetHeaderNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          targetName: props['targetName'] as String? ?? '',
          raHours: (props['raHours'] as num?)?.toDouble() ?? 0.0,
          decDegrees: (props['decDegrees'] as num?)?.toDouble() ?? 0.0,
          rotation: (props['rotation'] as num?)?.toDouble(),
          minAltitude: (props['minAltitude'] as num?)?.toDouble(),
          maxAltitude: (props['maxAltitude'] as num?)?.toDouble(),
          priority: (props['priority'] as num?)?.toInt() ?? 0,
          startAfter: props['startAfter'] != null
              ? DateTime.fromMillisecondsSinceEpoch(props['startAfter'] as int)
              : null,
          endBefore: props['endBefore'] != null
              ? DateTime.fromMillisecondsSinceEpoch(props['endBefore'] as int)
              : null,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'loop':
      case 'Loop':
        return LoopNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          conditionType:
              _stringToLoopCondition(props['conditionType'] as String?),
          repeatCount: (props['repeatCount'] as num?)?.toInt() ?? 1,
          repeatUntil: props['repeatUntil'] != null
              ? DateTime.fromMillisecondsSinceEpoch(props['repeatUntil'] as int)
              : null,
          repeatUntilAltitude:
              (props['repeatUntilAltitude'] as num?)?.toDouble(),
          integrationTimeTarget:
              (props['integrationTimeTarget'] as num?)?.toDouble(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'parallel':
      case 'Parallel':
        return ParallelNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          requiredSuccesses: (props['requiredSuccesses'] as num?)?.toInt(),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'conditional':
      case 'Conditional':
        return ConditionalNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          conditionType:
              _stringToConditionalType(props['conditionType'] as String?),
          thresholdValue: (props['thresholdValue'] as num?)?.toDouble(),
          thresholdTime: props['thresholdTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  props['thresholdTime'] as int)
              : null,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'recovery':
      case 'Recovery':
        return RecoveryNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          recoveryAction:
              _stringToRecoveryAction(props['recoveryAction'] as String?),
          maxRetries: (props['maxRetries'] as num?)?.toInt() ?? 3,
          triggerType: _stringToTriggerType(props['triggerType'] as String?),
          triggerThreshold: (props['triggerThreshold'] as num?)?.toDouble(),
          hfrThresholdPercent:
              (props['hfrThresholdPercent'] as num?)?.toDouble() ?? 20.0,
          hfrConsecutiveFrames:
              (props['hfrConsecutiveFrames'] as num?)?.toInt() ?? 3,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'startGuiding':
      case 'StartGuiding':
        return StartGuidingNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          settlePixels: (props['settlePixels'] as num?)?.toDouble() ?? 1.5,
          settleTime: (props['settleTime'] as num?)?.toDouble() ?? 10.0,
          settleTimeout: (props['settleTimeout'] as num?)?.toDouble() ?? 60.0,
          autoSelectStar: props['autoSelectStar'] as bool? ?? true,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'stopGuiding':
      case 'StopGuiding':
        return StopGuidingNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'meridianFlip':
      case 'MeridianFlip':
        return MeridianFlipNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          triggerMethod:
              _stringToMeridianTriggerMethod(props['triggerMethod'] as String?),
          minutesPastMeridian:
              (props['minutesPastMeridian'] as num?)?.toDouble() ?? 5.0,
          minutesBeforeLimit:
              (props['minutesBeforeLimit'] as num?)?.toDouble() ?? 10.0,
          hourAngleThreshold:
              (props['hourAngleThreshold'] as num?)?.toDouble() ?? 0.5,
          pauseGuiding: props['pauseGuiding'] as bool? ?? true,
          autoCenter: props['autoCenter'] as bool? ?? true,
          refocusAfter: props['refocusAfter'] as bool? ?? false,
          settleTime: (props['settleTime'] as num?)?.toDouble() ?? 10.0,
          resumeGuiding: props['resumeGuiding'] as bool? ?? true,
          maxRetries: (props['maxRetries'] as num?)?.toInt() ?? 3,
          failureAction:
              _stringToFlipFailureAction(props['failureAction'] as String?),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'openDome':
      case 'OpenDome':
        return OpenDomeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          shutterOnly: props['shutterOnly'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'closeDome':
      case 'CloseDome':
        return CloseDomeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          shutterOnly: props['shutterOnly'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'parkDome':
      case 'ParkDome':
        return ParkDomeNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          shutterOnly: props['shutterOnly'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'polarAlignment':
      case 'PolarAlignment':
        return PolarAlignmentNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          exposureDuration:
              (props['exposureDuration'] as num?)?.toDouble() ?? 2.0,
          binning: (props['binning'] as num?)?.toInt() ?? 2,
          startAltitude: (props['startAltitude'] as num?)?.toDouble() ?? 45.0,
          rotationStep: (props['rotationStep'] as num?)?.toDouble() ?? 20.0,
          gain: (props['gain'] as num?)?.toInt(),
          offset: (props['offset'] as num?)?.toInt(),
          startFromCurrent: props['startFromCurrent'] as bool? ?? true,
          isNorth: props['isNorth'] as bool? ?? true,
          manualSlew: props['manualSlew'] as bool? ?? false,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      case 'instructionSet':
      case 'InstructionSet':
        return InstructionSetNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      default:
        return null;
    }
  }

  Map<String, dynamic> _nodeToProperties(SequenceNode node) {
    // Exhaustive switch on the sealed SequenceNode hierarchy. Adding a new
    // node subtype produces a compile-time error here, preventing silent
    // empty-property persistence that would lose user-configured settings.
    return switch (node) {
      ExposureNode() => {
          'durationSecs': node.durationSecs,
          'count': node.count,
          'filter': node.filter,
          'filterIndex': node.filterIndex,
          'gain': node.gain,
          'offset': node.offset,
          'binning': _binningToString(node.binning),
          'ditherEvery': node.ditherEvery,
        },
      SlewNode() => {
          'useTargetCoords': node.useTargetCoords,
          'customRa': node.customRa,
          'customDec': node.customDec,
        },
      CenterNode() => {
          'useTargetCoords': node.useTargetCoords,
          'customRa': node.customRa,
          'customDec': node.customDec,
          'accuracyArcsec': node.accuracyArcsec,
          'maxAttempts': node.maxAttempts,
          'exposureDuration': node.exposureDuration,
          'filter': node.filter,
        },
      AutofocusNode() => {
          'method': _autofocusMethodToString(node.method),
          'stepSize': node.stepSize,
          'stepsOut': node.stepsOut,
          'exposureDuration': node.exposureDuration,
          'useSettingsDefaults': node.useSettingsDefaults,
          'maxDurationSecs': node.maxDurationSecs,
        },
      DitherNode() => {
          'pixels': node.pixels,
          'settlePixels': node.settlePixels,
          'settleTime': node.settleTime,
          'settleTimeout': node.settleTimeout,
          'raOnly': node.raOnly,
        },
      FilterChangeNode() => {
          'filterName': node.filterName,
          'filterPosition': node.filterPosition,
        },
      CoolCameraNode() => {
          'targetTemp': node.targetTemp,
          'durationMins': node.durationMins,
        },
      WarmCameraNode() => {
          'ratePerMin': node.ratePerMin,
          'targetTemp': node.targetTemp,
        },
      RotatorNode() => {
          'targetAngle': node.targetAngle,
          'relative': node.relative,
        },
      WaitTimeNode() => {
          'waitUntil': node.waitUntil?.millisecondsSinceEpoch,
          'waitForTwilight': node.waitForTwilight != null
              ? _twilightToString(node.waitForTwilight!)
              : null,
        },
      DelayNode() => {
          'seconds': node.seconds,
        },
      NotificationNode() => {
          'title': node.title,
          'message': node.message,
          'level': _notificationLevelToString(node.level),
        },
      ScriptNode() => {
          'scriptPath': node.scriptPath,
          'arguments': node.arguments,
          'timeoutSecs': node.timeoutSecs,
        },
      TargetHeaderNode() => {
          'targetName': node.targetName,
          'raHours': node.raHours,
          'decDegrees': node.decDegrees,
          'rotation': node.rotation,
          'minAltitude': node.minAltitude,
          'maxAltitude': node.maxAltitude,
          'priority': node.priority,
          'startAfter': node.startAfter?.millisecondsSinceEpoch,
          'endBefore': node.endBefore?.millisecondsSinceEpoch,
        },
      LoopNode() => {
          'conditionType': _loopConditionToString(node.conditionType),
          'repeatCount': node.repeatCount,
          'repeatUntil': node.repeatUntil?.millisecondsSinceEpoch,
          'repeatUntilAltitude': node.repeatUntilAltitude,
          'integrationTimeTarget': node.integrationTimeTarget,
        },
      ParallelNode() => {
          'requiredSuccesses': node.requiredSuccesses,
        },
      ConditionalNode() => {
          'conditionType': _conditionalTypeToString(node.conditionType),
          'thresholdValue': node.thresholdValue,
          'thresholdTime': node.thresholdTime?.millisecondsSinceEpoch,
        },
      RecoveryNode() => {
          'recoveryAction': _recoveryActionToString(node.recoveryAction),
          'maxRetries': node.maxRetries,
          'triggerType': node.triggerType?.name,
          'triggerThreshold': node.triggerThreshold,
          'hfrThresholdPercent': node.hfrThresholdPercent,
          'hfrConsecutiveFrames': node.hfrConsecutiveFrames,
        },
      MeridianFlipNode() => {
          'triggerMethod': node.triggerMethod.name,
          'minutesPastMeridian': node.minutesPastMeridian,
          'minutesBeforeLimit': node.minutesBeforeLimit,
          'hourAngleThreshold': node.hourAngleThreshold,
          'pauseGuiding': node.pauseGuiding,
          'autoCenter': node.autoCenter,
          'refocusAfter': node.refocusAfter,
          'settleTime': node.settleTime,
          'resumeGuiding': node.resumeGuiding,
          'maxRetries': node.maxRetries,
          'failureAction': node.failureAction.name,
        },
      OpenDomeNode() => {
          'shutterOnly': node.shutterOnly,
        },
      CloseDomeNode() => {
          'shutterOnly': node.shutterOnly,
        },
      ParkDomeNode() => {
          'shutterOnly': node.shutterOnly,
        },
      StartGuidingNode() => {
          'settlePixels': node.settlePixels,
          'settleTime': node.settleTime,
          'settleTimeout': node.settleTimeout,
          'autoSelectStar': node.autoSelectStar,
        },
      PolarAlignmentNode() => {
          'exposureDuration': node.exposureDuration,
          'binning': node.binning,
          'startAltitude': node.startAltitude,
          'rotationStep': node.rotationStep,
          'gain': node.gain,
          'offset': node.offset,
          'startFromCurrent': node.startFromCurrent,
          'isNorth': node.isNorth,
          'manualSlew': node.manualSlew,
        },
      // Side-effect-only nodes have no extra properties to persist beyond
      // the base fields (id/name/parentId/orderIndex/isEnabled/comment).
      InstructionSetNode() ||
      StopGuidingNode() ||
      ParkNode() ||
      UnparkNode() ||
      OpenCoverNode() ||
      CloseCoverNode() ||
      CalibratorOnNode() ||
      CalibratorOffNode() =>
        const <String, dynamic>{},
    };
  }

  /// Wraps _nodeToProperties to include base-class fields like comment
  Map<String, dynamic> _nodeToPropertiesWithComment(SequenceNode node) {
    final props = _nodeToProperties(node);
    if (node.comment != null && node.comment!.isNotEmpty) {
      props['comment'] = node.comment;
    }
    return props;
  }

  // Helper methods for enum conversion
  String _binningToString(BinningMode mode) {
    switch (mode) {
      case BinningMode.one:
        return 'one';
      case BinningMode.two:
        return 'two';
      case BinningMode.three:
        return 'three';
      case BinningMode.four:
        return 'four';
    }
  }

  BinningMode _stringToBinning(String? s) {
    switch (s) {
      case 'two':
        return BinningMode.two;
      case 'three':
        return BinningMode.three;
      case 'four':
        return BinningMode.four;
      default:
        return BinningMode.one;
    }
  }

  String _autofocusMethodToString(AutofocusMethod method) {
    switch (method) {
      case AutofocusMethod.vCurve:
        return 'vCurve';
      case AutofocusMethod.hyperbolic:
        return 'hyperbolic';
      case AutofocusMethod.quadratic:
        return 'quadratic';
    }
  }

  AutofocusMethod _stringToAutofocusMethod(String? s) {
    switch (s) {
      case 'hyperbolic':
        return AutofocusMethod.hyperbolic;
      case 'quadratic':
      case 'parabolic': // Legacy DB entries
        return AutofocusMethod.quadratic;
      default:
        return AutofocusMethod.vCurve;
    }
  }

  String _twilightToString(TwilightType type) {
    switch (type) {
      case TwilightType.civil:
        return 'civil';
      case TwilightType.nautical:
        return 'nautical';
      case TwilightType.astronomical:
        return 'astronomical';
    }
  }

  TwilightType? _stringToTwilight(String? s) {
    switch (s) {
      case 'civil':
        return TwilightType.civil;
      case 'nautical':
        return TwilightType.nautical;
      case 'astronomical':
        return TwilightType.astronomical;
      default:
        return null;
    }
  }

  String _notificationLevelToString(NotificationLevel level) {
    switch (level) {
      case NotificationLevel.info:
        return 'info';
      case NotificationLevel.warning:
        return 'warning';
      case NotificationLevel.error:
        return 'error';
      case NotificationLevel.success:
        return 'success';
    }
  }

  NotificationLevel _stringToNotificationLevel(String? s) {
    switch (s) {
      case 'warning':
        return NotificationLevel.warning;
      case 'error':
        return NotificationLevel.error;
      case 'success':
        return NotificationLevel.success;
      default:
        return NotificationLevel.info;
    }
  }

  String _loopConditionToString(LoopConditionType type) {
    switch (type) {
      case LoopConditionType.count:
        return 'count';
      case LoopConditionType.untilTime:
        return 'untilTime';
      case LoopConditionType.untilAltitude:
        return 'untilAltitude';
      case LoopConditionType.altitudeAbove:
        return 'altitudeAbove';
      case LoopConditionType.integrationTime:
        return 'integrationTime';
      case LoopConditionType.forever:
        return 'forever';
      case LoopConditionType.whileDark:
        return 'whileDark';
    }
  }

  LoopConditionType _stringToLoopCondition(String? s) {
    switch (s) {
      case 'untilTime':
        return LoopConditionType.untilTime;
      case 'untilAltitude':
        return LoopConditionType.untilAltitude;
      case 'altitudeAbove':
        return LoopConditionType.altitudeAbove;
      case 'integrationTime':
        return LoopConditionType.integrationTime;
      case 'forever':
        return LoopConditionType.forever;
      case 'whileDark':
        return LoopConditionType.whileDark;
      default:
        return LoopConditionType.count;
    }
  }

  String _conditionalTypeToString(ConditionalType type) {
    switch (type) {
      case ConditionalType.always:
        return 'always';
      case ConditionalType.altitudeAbove:
        return 'altitudeAbove';
      case ConditionalType.timeAfter:
        return 'timeAfter';
      case ConditionalType.guidingRmsBelow:
        return 'guidingRmsBelow';
      case ConditionalType.hfrBelow:
        return 'hfrBelow';
      case ConditionalType.weatherSafe:
        return 'weatherSafe';
      case ConditionalType.moonSeparationAbove:
        return 'moonSeparationAbove';
      case ConditionalType.safetyMonitorSafe:
        return 'safetyMonitorSafe';
    }
  }

  ConditionalType _stringToConditionalType(String? s) {
    switch (s) {
      case 'altitudeAbove':
        return ConditionalType.altitudeAbove;
      case 'timeAfter':
        return ConditionalType.timeAfter;
      case 'guidingRmsBelow':
        return ConditionalType.guidingRmsBelow;
      case 'hfrBelow':
        return ConditionalType.hfrBelow;
      case 'weatherSafe':
        return ConditionalType.weatherSafe;
      case 'moonSeparationAbove':
        return ConditionalType.moonSeparationAbove;
      case 'safetyMonitorSafe':
        return ConditionalType.safetyMonitorSafe;
      default:
        return ConditionalType.always;
    }
  }

  String _recoveryActionToString(RecoveryActionType action) {
    switch (action) {
      case RecoveryActionType.continueExecution:
        return 'continue';
      case RecoveryActionType.pause:
        return 'pause';
      case RecoveryActionType.autofocus:
        return 'autofocus';
      case RecoveryActionType.nextTarget:
        return 'nextTarget';
      case RecoveryActionType.retry:
        return 'retry';
      case RecoveryActionType.parkAndAbort:
        return 'parkAndAbort';
      case RecoveryActionType.customBranch:
        return 'customBranch';
    }
  }

  RecoveryActionType _stringToRecoveryAction(String? s) {
    switch (s) {
      case 'pause':
        return RecoveryActionType.pause;
      case 'autofocus':
        return RecoveryActionType.autofocus;
      case 'nextTarget':
        return RecoveryActionType.nextTarget;
      case 'retry':
        return RecoveryActionType.retry;
      case 'parkAndAbort':
        return RecoveryActionType.parkAndAbort;
      case 'customBranch':
        return RecoveryActionType.customBranch;
      default:
        return RecoveryActionType.continueExecution;
    }
  }

  MeridianTriggerMethod _stringToMeridianTriggerMethod(String? s) {
    switch (s) {
      case 'minutesBeforeLimit':
        return MeridianTriggerMethod.minutesBeforeLimit;
      case 'hourAngleThreshold':
        return MeridianTriggerMethod.hourAngleThreshold;
      default:
        return MeridianTriggerMethod.minutesPastMeridian;
    }
  }

  FlipFailureAction _stringToFlipFailureAction(String? s) {
    switch (s) {
      case 'abortAndPark':
        return FlipFailureAction.abortAndPark;
      default:
        return FlipFailureAction.pauseAndAlert;
    }
  }

  TriggerType? _stringToTriggerType(String? s) {
    if (s == null) return null;
    for (final value in TriggerType.values) {
      if (value.name == s) return value;
    }
    return null;
  }
}

/// Provider for the sequence repository
final sequenceRepositoryProvider = Provider<SequenceRepository>((ref) {
  return SequenceRepository(ref.watch(sequencesDaoProvider));
});
