import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../backend/network_backend.dart';
import '../database/database.dart' as db;
import '../database/daos/sequences_dao.dart';
import '../models/notification/notification_categories.dart'
    show NotificationTransportKind;
import '../models/sequence/sequence_models.dart';
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import '../utils/json_validation.dart';
import 'sequence_file_service.dart';

/// Repository for saving and loading sequences from the database
class SequenceRepository {
  final SequencesDao? _dao;
  final NetworkBackend? _remote;
  final SequenceFileService? _fileService;

  SequenceRepository._({
    SequencesDao? dao,
    NetworkBackend? remote,
    SequenceFileService? fileService,
  })  : _dao = dao,
        _remote = remote,
        _fileService = fileService {
    assert(
      (dao != null && remote == null) || (dao == null && remote != null),
      'SequenceRepository must be either local (dao) or remote (NetworkBackend)',
    );
    if (remote != null) {
      assert(fileService != null,
          'Remote SequenceRepository requires fileService');
    }
  }

  factory SequenceRepository(SequencesDao dao) =>
      SequenceRepository._(dao: dao);

  factory SequenceRepository.remote(
    NetworkBackend remote,
    SequenceFileService fileService,
  ) =>
      SequenceRepository._(remote: remote, fileService: fileService);

  bool get _isRemote => _remote != null;

  Sequence _sequenceFromRemoteMap(Map<String, dynamic> map) {
    final dbId = map.remove('databaseId');
    final sequence = _fileService!.parseFromMap(map);
    if (dbId is int) {
      return sequence.copyWith(databaseId: dbId);
    }
    return sequence;
  }

  Map<String, dynamic> _sequenceToRemoteMap(Sequence sequence) {
    final map = _fileService!.sequenceToMap(sequence);
    if (sequence.databaseId != null) {
      map['databaseId'] = sequence.databaseId;
    }
    return map;
  }

  /// Save a sequence to the database
  /// Returns the database ID of the saved sequence
  Future<int> saveSequence(Sequence sequence, {bool isTemplate = false}) async {
    if (_isRemote) {
      return _remote!.saveFullSequence(
        _sequenceToRemoteMap(sequence),
        isTemplate: isTemplate,
        databaseId: sequence.databaseId,
      );
    }

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
    final dao = _dao!;
    // Create the sequence record
    final sequenceId = await dao.createSequence(
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
    final existing = await _dao!.getSequenceById(sequenceId);
    if (existing == null) {
      throw Exception('Sequence $sequenceId not found');
    }

    // Update sequence metadata
    await _dao!.updateSequence(
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
    final existingNodes = await _dao!.getNodesForSequence(sequenceId);
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
      await _dao!.updateNode(
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
      await _dao!.createNode(
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
      await _dao!.deleteNode(dbNode.id);
    }
  }

  Future<void> _saveNodes(
      int sequenceId, Map<String, SequenceNode> nodes) async {
    for (final node in nodes.values) {
      await _dao!.createNode(
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
      RecoveryNode _ ||
      // Wave 3 Agent 1: TargetScheduler — logic-category container.
      TargetSchedulerNode _ =>
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
      CalibratorOffNode _ ||
      // Wave 3 Agent 2: SmartExposure is an instruction (leaf, no children).
      SmartExposureNode _ ||
      // Wave 7 Agent 2: LiveStacking is a side-effect instruction (arms
      // the broadcast service then returns immediately, no children).
      LiveStackingNode _ ||
      // Wave 7 Science: SciencePhotometry — instruction leaf.
      SciencePhotometryNode _ ||
      // Audit §11 — plugin-contributed instruction (leaf; plugin owns
      // any internal fan-out).
      PluginInstructionNode _ =>
        'instruction',
    };
  }

  /// Load a sequence from the database
  Future<Sequence?> loadSequence(int sequenceId) async {
    if (_isRemote) {
      final all = [
        ...await _remote!.listFullSequences(),
        ...await _remote!.listFullTemplates(),
      ];
      for (final map in all) {
        if (map['databaseId'] == sequenceId) {
          return _sequenceFromRemoteMap(Map<String, dynamic>.from(map));
        }
      }
      return null;
    }

    final dbSequence = await _dao!.getSequenceById(sequenceId);
    if (dbSequence == null) return null;

    final dbNodes = await _dao!.getNodesForSequence(sequenceId);

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
    if (_isRemote) {
      final maps = await _remote!.listFullSequences();
      return maps
          .map((map) => _sequenceFromRemoteMap(Map<String, dynamic>.from(map)))
          .toList();
    }

    final dbSequences = await _dao!.getAllSequences();
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
    if (_isRemote) {
      final maps = await _remote!.listFullTemplates();
      return maps
          .map((map) => _sequenceFromRemoteMap(Map<String, dynamic>.from(map)))
          .toList();
    }

    final dbTemplates = await _dao!.getAllTemplates();
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
    if (_isRemote) {
      await _remote!.deleteSequence(sequenceId);
      return;
    }
    await _dao!.deleteSequence(sequenceId);
  }

  /// Duplicate a sequence with fresh UUIDs for all nodes.
  ///
  /// Generates new UUIDs for every node and remaps all parent/child references
  /// so the duplicated sequence is fully independent from the original.
  Future<Sequence?> duplicateSequence(int sequenceId, String newName) async {
    if (_isRemote) {
      final newId = await _remote!.duplicateSequence(sequenceId, newName);
      return loadSequence(newId);
    }

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
        // Wave 5 Agent 2 — recover the adaptive-exposure block. Both
        // camelCase (Dart canonical) and snake_case (Rust JSON shape)
        // are honoured so legacy + future-saved JSON both load.
        AdaptiveExposureConfig? adaptive;
        final adaptiveRaw =
            (props['adaptiveExposure'] ?? props['adaptive_exposure']) as Map?;
        if (adaptiveRaw != null) {
          adaptive = AdaptiveExposureConfig.fromJson(
            adaptiveRaw.cast<String, dynamic>(),
          );
        }
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
          triggers: ((props['triggers'] as List?) ?? const [])
              .whereType<Map>()
              .map((trigger) => trigger.cast<String, dynamic>())
              .toList(growable: false),
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
          adaptiveExposure: adaptive,
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
          pattern: _parseDitherPattern(props['pattern']),
          gridSize: (props['gridSize'] as num?)?.toInt() ?? 3,
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
          explicitTransports:
              _parseExplicitTransports(props['explicitTransports']),
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
          // Wave 3 Agent 3 — restore the integration budget. Absent
          // field stays null (pre-budget sequences keep working).
          integrationBudget: props['integrationBudget'] != null
              ? IntegrationBudget.fromJson(
                  props['integrationBudget'] as Map<String, dynamic>)
              : null,
          // Wave 4 — per-target altitude/time crossings.
          startWhen: props['startWhen'] != null
              ? TargetTrigger.fromJson(
                  props['startWhen'] as Map<String, dynamic>)
              : null,
          endWhen: props['endWhen'] != null
              ? TargetTrigger.fromJson(props['endWhen'] as Map<String, dynamic>)
              : null,
          triggerPollIntervalSecs:
              (props['triggerPollIntervalSecs'] as num?)?.toInt() ?? 30,
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
          // Audit C2: optional per-monitor targeting for multi-safety
          // setups. Absent on legacy sequences (deserialises to null,
          // i.e. fall back to the aggregated check).
          safetyMonitorId: props['safetyMonitorId'] as String?,
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
          // Why: legacy DB rows pre-§1.2 have no flag. Treat absence as
          // `false` (use persisted per-node values verbatim) so existing
          // user sequences keep behavior they had before the wire-up.
          useGlobalDefaults: props['useGlobalDefaults'] as bool? ?? false,
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

      // Wave 3 Agent 1: TargetScheduler. Two case strings cover both the
      // canonical Dart `nodeType` ('TargetScheduler') and the legacy
      // snake_case sent by the bridge layer ('target_scheduler').
      case 'targetScheduler':
      case 'TargetScheduler':
      case 'target_scheduler':
        return TargetSchedulerNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          altitudeWeight: (props['altitudeWeight'] as num?)?.toDouble() ?? 0.25,
          moonDistanceWeight:
              (props['moonDistanceWeight'] as num?)?.toDouble() ?? 0.25,
          transitProximityWeight:
              (props['transitProximityWeight'] as num?)?.toDouble() ?? 0.20,
          darknessWeight: (props['darknessWeight'] as num?)?.toDouble() ?? 0.15,
          airmassWeight: (props['airmassWeight'] as num?)?.toDouble() ?? 0.15,
          minScoreToRun: (props['minScoreToRun'] as num?)?.toDouble() ?? 30.0,
          recomputeEveryNExposures:
              (props['recomputeEveryNExposures'] as num?)?.toInt() ?? 0,
          finishIterationOnSwitch:
              props['finishIterationOnSwitch'] as bool? ?? true,
          swapOnConditionsBelow:
              (props['swapOnConditionsBelow'] as num?)?.toDouble() ??
                  (props['swap_on_conditions_below'] as num?)?.toDouble(),
          swapHysteresisSecs:
              (props['swapHysteresisSecs'] as num?)?.toDouble() ??
                  (props['swap_hysteresis_secs'] as num?)?.toDouble() ??
                  180.0,
          brightnessTierPreferences: _parseBrightnessTierPreferences(
            props['brightnessTierPreferences'] ??
                props['brightness_tier_preferences'],
          ),
          maxConditionsScoreAgeSecs:
              (props['maxConditionsScoreAgeSecs'] as num?)?.toInt() ??
                  (props['max_conditions_score_age_secs'] as num?)?.toInt() ??
                  300,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      // Wave 3 Agent 2: SmartExposure. Mirrors the case-string convention
      // above so DB rows written via `nodeType = 'SmartExposure'` or via
      // the snake_case bridge form both deserialize correctly.
      case 'smartExposure':
      case 'SmartExposure':
      case 'smart_exposure':
        return SmartExposureNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          plans: ((props['plans'] as List?) ?? const [])
              .whereType<Map>()
              .map((p) => FilterPlan.fromJson(p.cast<String, dynamic>()))
              .toList(growable: false),
          rotateFilters: props['rotateFilters'] as bool? ?? true,
          ditherOnFilterChange: props['ditherOnFilterChange'] as bool? ?? false,
          integrationBudgetSecs:
              (props['integrationBudgetSecs'] as num?)?.toDouble() ?? 0.0,
          batchSize: (props['batchSize'] as num?)?.toInt() ?? 1,
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      // Audit §11 — plugin-contributed instruction. Persisted node-type
      // string mirrors the Rust serde tag ("PluginNode"); we also accept
      // lower / snake-case spellings for resilience against legacy DB
      // rows. A persisted plugin node with no `pluginId`/`nodeTypeId`
      // is unusable, but we still rehydrate it (with empty identifiers)
      // so the editor can surface the broken node to the user rather
      // than silently dropping it.
      case 'pluginNode':
      case 'PluginNode':
      case 'plugin_node':
        return PluginInstructionNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          pluginId: props['pluginId'] as String? ?? '',
          nodeTypeId: props['nodeTypeId'] as String? ?? '',
          configJson: props['configJson'] as String? ?? '{}',
          timeoutSecs: (props['timeoutSecs'] as num?)?.toInt(),
          pluginName: props['pluginName'] as String? ?? '',
          iconHint: props['iconHint'] as String? ?? 'puzzle',
          parentId: dbNode.parentNodeId,
          orderIndex: dbNode.orderIndex,
          isEnabled: dbNode.isEnabled,
          comment: props['comment'] as String?,
        );

      // Wave 7 Agent 2: LiveStacking. Same case-string convention as
      // SmartExposure above so DB rows written via either spelling
      // round-trip correctly.
      case 'liveStacking':
      case 'LiveStacking':
      case 'live_stacking':
        return LiveStackingNode(
          id: dbNode.nodeId,
          name: dbNode.name,
          mode: LiveStackingMode.fromStorageKey(props['mode'] as String?),
          stackMethod: LiveStackingMethod.fromStorageKey(
              props['stackMethod'] as String?),
          maxFramesToStack: (props['maxFramesToStack'] as num?)?.toInt() ?? 0,
          broadcastEnabled: props['broadcastEnabled'] as bool? ?? true,
          broadcastPort: (props['broadcastPort'] as num?)?.toInt() ?? 8081,
          broadcastPath: props['broadcastPath'] as String? ?? '/broadcast',
          authToken: props['authToken'] as String?,
          watermarkText: props['watermarkText'] as String?,
          thumbnailWidth: (props['thumbnailWidth'] as num?)?.toInt() ?? 1280,
          thumbnailHeight: (props['thumbnailHeight'] as num?)?.toInt() ?? 720,
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
          'triggers': node.triggers,
          // Wave 5 Agent 2 — per-node adaptive-exposure override. `null`
          // means "inherit from global default"; we serialise `null` too
          // so the absent-key vs. explicit-null distinction is
          // preserved on reload.
          'adaptiveExposure': node.adaptiveExposure?.toJson(),
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
          'pattern': node.pattern.name,
          'gridSize': node.gridSize,
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
          if (node.explicitTransports != null)
            'explicitTransports':
                node.explicitTransports!.map((t) => t.storageKey).toList(),
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
          // Wave 3 Agent 3 — persist the per-target integration budget
          // when configured. `null`/absent means "no budget enforcement"
          // — current default behaviour for existing sequences.
          if (node.integrationBudget != null)
            'integrationBudget': node.integrationBudget!.toJson(),
          // Wave 4 — per-target altitude/time crossings. Both fields
          // are optional; absent => no gate, which is the pre-Wave-4
          // default for existing sequences.
          if (node.startWhen != null) 'startWhen': node.startWhen!.toJson(),
          if (node.endWhen != null) 'endWhen': node.endWhen!.toJson(),
          'triggerPollIntervalSecs': node.triggerPollIntervalSecs,
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
          // Audit C2 — per-monitor targeting for multi-safety setups.
          'safetyMonitorId': node.safetyMonitorId,
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
          // Why: persist the override flag so reopening the sequence preserves
          // whether the user pinned per-node values or pulls from settings
          // (audit §1.2).
          'useGlobalDefaults': node.useGlobalDefaults,
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
      // Wave 3 Agent 1: TargetScheduler — persist all eight knobs so reload
      // round-trips structurally and the validator can re-check the weight
      // sum / scheduler-children rules on load.
      TargetSchedulerNode() => {
          'altitudeWeight': node.altitudeWeight,
          'moonDistanceWeight': node.moonDistanceWeight,
          'transitProximityWeight': node.transitProximityWeight,
          'darknessWeight': node.darknessWeight,
          'airmassWeight': node.airmassWeight,
          'minScoreToRun': node.minScoreToRun,
          'recomputeEveryNExposures': node.recomputeEveryNExposures,
          'finishIterationOnSwitch': node.finishIterationOnSwitch,
          'swapOnConditionsBelow': node.swapOnConditionsBelow,
          'swapHysteresisSecs': node.swapHysteresisSecs,
          'brightnessTierPreferences': node.brightnessTierPreferences.toJson(),
          'maxConditionsScoreAgeSecs': node.maxConditionsScoreAgeSecs,
        },
      // Wave 3 Agent 2: SmartExposure — plans are serialised as a list of
      // FilterPlan JSON maps. We re-use FilterPlan.toJson() (which mirrors
      // the Rust serde shape) so the same blob round-trips through both
      // disk persistence and the executor's `_nodeToConfig` payload.
      SmartExposureNode() => {
          'plans': node.plans.map((p) => p.toJson()).toList(growable: false),
          'rotateFilters': node.rotateFilters,
          'ditherOnFilterChange': node.ditherOnFilterChange,
          'integrationBudgetSecs': node.integrationBudgetSecs,
          'batchSize': node.batchSize,
        },
      // Wave 7 Agent 2: LiveStacking — flat key/value persistence.
      // `authToken` and `watermarkText` may be null; we keep them as
      // distinct keys (versus omitting) so the load path always reads
      // the same shape.
      LiveStackingNode() => {
          'mode': node.mode.storageKey,
          'stackMethod': node.stackMethod.storageKey,
          'maxFramesToStack': node.maxFramesToStack,
          'broadcastEnabled': node.broadcastEnabled,
          'broadcastPort': node.broadcastPort,
          'broadcastPath': node.broadcastPath,
          'authToken': node.authToken,
          'watermarkText': node.watermarkText,
          'thumbnailWidth': node.thumbnailWidth,
          'thumbnailHeight': node.thumbnailHeight,
        },
      // Wave 7 Science: SciencePhotometry — cadence-enforced
      // photometric capture node config.
      SciencePhotometryNode() => {
          'targetDesignation': node.targetDesignation,
          'referenceStars': node.referenceStars,
          'maxCadenceGapSecs': node.maxCadenceGapSecs,
          'filter': node.filter,
          'exposureSecs': node.exposureSecs,
          'count': node.count,
          'reduceLive': node.reduceLive,
          'applyDifferential': node.applyDifferential,
          'quality': node.quality.toJson(),
          'gain': node.gain,
          'offset': node.offset,
          'binning': node.binning.name,
        },
      // Audit §11 — plugin-contributed instruction. Pin pluginId,
      // nodeTypeId, opaque config blob, and friendly metadata so a
      // sequence containing plugin nodes still round-trips when the
      // plugin is temporarily unavailable (the editor surfaces a
      // "plugin missing" notice rather than silently dropping the node).
      PluginInstructionNode() => {
          'pluginId': node.pluginId,
          'nodeTypeId': node.nodeTypeId,
          'configJson': node.configJson,
          'timeoutSecs': node.timeoutSecs,
          'pluginName': node.pluginName,
          'iconHint': node.iconHint,
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

  /// Wave 5 Agent 5 — DB-side round-trip of NotificationNode's explicit
  /// transports override. See [SequenceFileService._parseExplicitTransports]
  /// for the equivalent file-side parser.
  List<NotificationTransportKind>? _parseExplicitTransports(dynamic raw) {
    if (raw is! List) return null;
    final out = <NotificationTransportKind>[];
    for (final entry in raw) {
      if (entry is String) {
        final t = NotificationTransportKind.fromStorageKey(entry);
        if (t != null) out.add(t);
      }
    }
    return out.isEmpty ? null : out;
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
      // Wave 5 Agent 4 — cloud-motion-aware actions stored as
      // camelCase identifiers so they round-trip through the SQLite
      // sequence repository the same way every other recovery action does.
      case RecoveryActionType.pauseAndWaitForClear:
        return 'pauseAndWaitForClear';
      case RecoveryActionType.slewToGapAndContinue:
        return 'slewToGapAndContinue';
      // Wave 7 Science — transparency-adaptive recovery.
      case RecoveryActionType.switchTargetOrFilter:
        return 'switchTargetOrFilter';
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
      // Wave 5 Agent 4 — cloud-motion-aware actions.
      case 'pauseAndWaitForClear':
        return RecoveryActionType.pauseAndWaitForClear;
      case 'slewToGapAndContinue':
        return RecoveryActionType.slewToGapAndContinue;
      // Wave 7 Science — transparency-adaptive recovery.
      case 'switchTargetOrFilter':
        return RecoveryActionType.switchTargetOrFilter;
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

  DitherPattern _parseDitherPattern(Object? raw) {
    if (raw is String) {
      final v = raw.toLowerCase();
      if (v == 'grid') return DitherPattern.grid;
      if (v == 'random') return DitherPattern.random;
    }
    return DitherPattern.random;
  }
}

BrightnessTierPreferences _parseBrightnessTierPreferences(Object? value) {
  if (value is Map) {
    return BrightnessTierPreferences.fromJson(value.cast<String, dynamic>());
  }
  return const BrightnessTierPreferences();
}

/// Provider for the sequence repository
final sequenceRepositoryProvider = Provider<SequenceRepository>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return SequenceRepository.remote(
      backend,
      ref.watch(sequenceFileServiceProvider),
    );
  }
  return SequenceRepository(ref.watch(sequencesDaoProvider));
});
