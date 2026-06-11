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
import 'scheduler/horizon_profile.dart';
import 'sequence_file_service.dart';

part 'sequence_repository/node_decoder.dart';
part 'sequence_repository/node_encoder.dart';

/// Repository for saving and loading sequences from the database
class SequenceRepository {
  final SequencesDao? _dao;
  final NetworkBackend? _remote;
  final SequenceFileService? _fileService;

  SequenceRepository._({
    SequencesDao? dao,
    NetworkBackend? remote,
    SequenceFileService? fileService,
  }) : _dao = dao,
       _remote = remote,
       _fileService = fileService {
    assert(
      (dao != null && remote == null) || (dao == null && remote != null),
      'SequenceRepository must be either local (dao) or remote (NetworkBackend)',
    );
    if (remote != null) {
      assert(
        fileService != null,
        'Remote SequenceRepository requires fileService',
      );
    }
  }

  factory SequenceRepository(SequencesDao dao) =>
      SequenceRepository._(dao: dao);

  factory SequenceRepository.remote(
    NetworkBackend remote,
    SequenceFileService fileService,
  ) => SequenceRepository._(remote: remote, fileService: fileService);

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
    int sequenceId,
    Sequence sequence,
    bool isTemplate,
  ) async {
    // Get existing sequence
    final existing = await _dao!.getSequenceById(sequenceId);
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
    final existingNodeMap = {for (final n in existingNodes) n.nodeId: n};

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
    int sequenceId,
    Map<String, SequenceNode> nodes,
  ) async {
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

  /// Serialize a node's coarse category for the persisted
  /// `sequence_nodes.node_type` column.
  ///
  /// Single source of truth: delegates to the model's `node.category`
  /// getter and maps the [NodeCategory] enum to its wire string. This
  /// previously hand-classified every subtype here, which let the
  /// persisted value drift from `node.category` (e.g. C6 reclassified
  /// `MeridianFlipNode` to [NodeCategory.trigger] but this switch still
  /// emitted 'instruction'). Deriving from the getter makes that class of
  /// divergence structurally impossible.
  String _getNodeCategory(SequenceNode node) =>
      _categoryWireString(node.category);

  /// Map a [NodeCategory] to the string persisted in
  /// `sequence_nodes.node_type`. Exhaustive over the enum so a future
  /// category produces a compile-time error rather than a silent
  /// mis-bucket.
  static String _categoryWireString(NodeCategory category) {
    return switch (category) {
      NodeCategory.instruction => 'instruction',
      NodeCategory.trigger => 'trigger',
      NodeCategory.logic => 'logic',
      NodeCategory.target => 'target',
    };
  }

  /// Load a sequence from the database
  Future<Sequence?> loadSequence(int sequenceId) async {
    if (_isRemote) {
      final all = [
        ...await _remote!.listFullSequences(),
        ...await _remote.listFullTemplates(),
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

  /// DB-side round-trip of NotificationNode's explicit
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
      // Cloud-motion-aware actions stored as
      // camelCase identifiers so they round-trip through the SQLite
      // sequence repository the same way every other recovery action does.
      case RecoveryActionType.pauseAndWaitForClear:
        return 'pauseAndWaitForClear';
      case RecoveryActionType.slewToGapAndContinue:
        return 'slewToGapAndContinue';
      // Science — transparency-adaptive recovery.
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
      // Cloud-motion-aware actions.
      case 'pauseAndWaitForClear':
        return RecoveryActionType.pauseAndWaitForClear;
      case 'slewToGapAndContinue':
        return RecoveryActionType.slewToGapAndContinue;
      // Science — transparency-adaptive recovery.
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

/// Persist a [TargetSchedulerNode]'s azimuth horizon mask as
/// `{id?, name, samples:[{az,alt}]}`. `null` profile encodes to `null`.
Map<String, dynamic>? _schedulerHorizonToJson(HorizonProfile? profile) {
  if (profile == null) return null;
  return {
    if (profile.id != null) 'id': profile.id,
    'name': profile.name,
    'samples': profile.samples.map((s) => s.toJson()).toList(),
  };
}

/// Inverse of [_schedulerHorizonToJson]. Tolerates a missing/empty samples
/// list (returns `null` — flat altitude floor) so legacy saved nodes load.
HorizonProfile? _schedulerHorizonFromJson(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final samplesRaw = map['samples'] as List<dynamic>? ?? const [];
  if (samplesRaw.isEmpty) return null;
  return HorizonProfile(
    id: (map['id'] as num?)?.toInt(),
    name: map['name'] as String? ?? 'Site horizon',
    samples: samplesRaw
        .map((e) => HorizonSample.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
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
