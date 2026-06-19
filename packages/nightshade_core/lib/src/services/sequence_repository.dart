import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../backend/network_backend.dart';
import '../database/database.dart' as db;
import '../database/daos/sequence_runs_dao.dart';
import '../database/daos/sequence_versions_dao.dart';
import '../database/daos/sequences_dao.dart';
import '../models/notification/notification_categories.dart'
    show NotificationTransportKind;
import '../models/sequence/sequence_models.dart';
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import '../providers/sequence_stats_provider.dart'
    show sequenceRunsDaoProvider, sequenceVersionsDaoProvider;
import '../utils/json_validation.dart';
import 'scheduler/horizon_profile.dart';
import 'sequence_file_service.dart';
import 'sequence_summary.dart';

export 'sequence_summary.dart';

part 'sequence_repository/node_decoder.dart';
part 'sequence_repository/node_encoder.dart';

/// Repository for saving and loading sequences from the database
class SequenceRepository {
  final SequencesDao? _dao;
  final SequenceRunsDao? _runsDao;
  final SequenceVersionsDao? _versionsDao;
  final NetworkBackend? _remote;
  final SequenceFileService? _fileService;

  SequenceRepository._({
    SequencesDao? dao,
    SequenceRunsDao? runsDao,
    SequenceVersionsDao? versionsDao,
    NetworkBackend? remote,
    SequenceFileService? fileService,
  }) : _dao = dao,
       _runsDao = runsDao,
       _versionsDao = versionsDao,
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

  /// Local repository backed by the database.
  ///
  /// [runsDao], [versionsDao], and [fileService] are optional so existing
  /// callers (and tests) that only need save/load can pass the [SequencesDao]
  /// alone. The diff / version-history features ([loadPreviousRunSnapshot],
  /// [snapshotVersionOnSave], [listVersions], [restoreVersion]) require the
  /// matching dependency and throw a clear [StateError] if invoked without it;
  /// the production provider wires all four.
  factory SequenceRepository(
    SequencesDao dao, {
    SequenceRunsDao? runsDao,
    SequenceVersionsDao? versionsDao,
    SequenceFileService? fileService,
  }) => SequenceRepository._(
    dao: dao,
    runsDao: runsDao,
    versionsDao: versionsDao,
    fileService: fileService,
  );

  factory SequenceRepository.remote(
    NetworkBackend remote,
    SequenceFileService fileService,
  ) => SequenceRepository._(remote: remote, fileService: fileService);

  bool get _isRemote => _remote != null;

  SequenceFileService _requireFileService(String feature) {
    final service = _fileService;
    if (service == null) {
      throw StateError(
        'SequenceRepository.$feature requires a SequenceFileService. '
        'Construct the repository through sequenceRepositoryProvider, which '
        'wires it, rather than SequenceRepository(dao) alone.',
      );
    }
    return service;
  }

  SequenceRunsDao _requireRunsDao(String feature) {
    final dao = _runsDao;
    if (dao == null) {
      throw StateError(
        'SequenceRepository.$feature requires a SequenceRunsDao. '
        'Construct the repository through sequenceRepositoryProvider, which '
        'wires it, rather than SequenceRepository(dao) alone.',
      );
    }
    return dao;
  }

  SequenceVersionsDao _requireVersionsDao(String feature) {
    final dao = _versionsDao;
    if (dao == null) {
      throw StateError(
        'SequenceRepository.$feature requires a SequenceVersionsDao. '
        'Construct the repository through sequenceRepositoryProvider, which '
        'wires it, rather than SequenceRepository(dao) alone.',
      );
    }
    return dao;
  }

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
        tagsJson: existing.tagsJson,
        isFavorite: existing.isFavorite,
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

  /// Load lightweight summaries for every saved (non-template) sequence.
  ///
  /// Backed by a single grouped DAO query plus a batched run-history roll-up,
  /// so the library list renders without hydrating any node tree — the N+1 that
  /// [loadAllSequences] incurs (one full load per row). Newest-modified first.
  ///
  /// For a remote host this falls back to deriving summaries from the full
  /// sequence list, because the host read API exposes no dedicated summary
  /// endpoint; the remote client already pays the full-load cost.
  Future<List<SequenceSummary>> loadSequenceSummaries() async {
    if (_isRemote) {
      final sequences = await loadAllSequences();
      return [
        for (final sequence in sequences)
          SequenceSummary(
            id: sequence.databaseId ?? -1,
            name: sequence.name,
            nodeCount: sequence.nodes.length,
            targetCount: sequence.targetHeaders.length,
            exposureCount: sequence.nodes.values
                .where((n) => n is ExposureNode || n is SmartExposureNode)
                .length,
            totalIntegrationSecs: sequence.totalIntegrationSecs.round(),
            primaryTargetName: sequence.targetHeaders.isEmpty
                ? null
                : sequence.targetHeaders.first.targetName,
            lastRunAt: null,
            runCount: 0,
            tags: const [],
            isFavorite: false,
            modifiedAt: sequence.modifiedAt,
          ),
      ];
    }

    final rows = await _dao!.getSequenceSummaryRows();
    final runsDao = _runsDao;
    return [
      for (final row in rows)
        await () async {
          final runRollup = runsDao == null
              ? (runCount: 0, lastRunAt: null)
              : await runsDao.runSummaryForSequence(row.id);
          return SequenceSummary(
            id: row.id,
            name: row.name,
            nodeCount: row.nodeCount,
            targetCount: row.targetCount,
            exposureCount: row.exposureCount,
            totalIntegrationSecs: row.estimatedDurationMins * 60,
            primaryTargetName: row.primaryTargetName,
            lastRunAt: runRollup.lastRunAt,
            runCount: runRollup.runCount,
            tags: SequenceSummary.decodeTags(row.tagsJson),
            isFavorite: row.isFavorite,
            modifiedAt: row.updatedAt,
          );
        }(),
    ];
  }

  /// The sequence JSON of the most recent COMPLETED run of [sequenceId] that
  /// started strictly before [beforeRunId]'s run.
  ///
  /// Used by the run-history "diff vs previous run" view: pass the run the user
  /// is inspecting as [beforeRunId] and this returns the snapshot of the run
  /// immediately before it, so the diff compares the two sequences that
  /// actually executed. Returns `null` when there is no earlier completed run,
  /// when the earlier run predates the snapshot column, or when [beforeRunId]
  /// is unknown. Local-only — the remote host owns its own run store.
  Future<String?> loadPreviousRunSnapshot(
    int sequenceId, {
    required int beforeRunId,
  }) async {
    if (_isRemote) {
      throw UnsupportedError(
        'loadPreviousRunSnapshot is local-only; run history lives on the host.',
      );
    }
    final runsDao = _requireRunsDao('loadPreviousRunSnapshot');
    final before = await runsDao.getRunById(beforeRunId);
    return runsDao.previousCompletedRunSnapshot(
      sequenceId,
      before: before?.startedAt,
    );
  }

  /// Set the library tags for [sequenceId]. Replaces the full tag list.
  Future<void> setTags(int sequenceId, List<String> tags) async {
    if (_isRemote) {
      throw UnsupportedError(
        'setTags is local-only; the host owns its sequence catalog metadata.',
      );
    }
    // Normalise: trim, drop blanks, de-duplicate while preserving order.
    final seen = <String>{};
    final cleaned = <String>[
      for (final tag in tags)
        if (tag.trim().isNotEmpty && seen.add(tag.trim())) tag.trim(),
    ];
    await _dao!.setTagsJson(sequenceId, jsonEncode(cleaned));
  }

  /// Toggle the favorite flag for [sequenceId]; returns the new value.
  Future<bool> toggleFavorite(int sequenceId) async {
    if (_isRemote) {
      throw UnsupportedError(
        'toggleFavorite is local-only; the host owns its catalog metadata.',
      );
    }
    final dao = _dao!;
    final existing = await dao.getSequenceById(sequenceId);
    if (existing == null) {
      throw Exception('Sequence $sequenceId not found');
    }
    final next = !existing.isFavorite;
    await dao.setFavorite(sequenceId, next);
    return next;
  }

  /// Capture a point-in-time version snapshot of [sequence] in its version
  /// history. No-op (returns `null`) for an unsaved sequence (no `databaseId`)
  /// since version history is keyed by the persisted row.
  ///
  /// Call this on a meaningful save so the user can later review and restore an
  /// earlier shape of the sequence. Returns the new version row id, or `null`
  /// when the sequence has no `databaseId`. History is capped per sequence by
  /// the DAO ([SequenceVersionsDao.maxVersionsPerSequence]).
  Future<int?> snapshotVersionOnSave(Sequence sequence, {String? label}) async {
    if (_isRemote) {
      throw UnsupportedError(
        'snapshotVersionOnSave is local-only; the host owns its history.',
      );
    }
    final sequenceId = sequence.databaseId;
    if (sequenceId == null) return null;
    final fileService = _requireFileService('snapshotVersionOnSave');
    final versionsDao = _requireVersionsDao('snapshotVersionOnSave');
    final snapshotJson = jsonEncode(fileService.sequenceToMap(sequence));
    return versionsDao.appendVersion(
      sequenceId: sequenceId,
      snapshotJson: snapshotJson,
      label: label,
    );
  }

  /// List the version history of [sequenceId], newest first.
  Future<List<db.SequenceVersion>> listVersions(int sequenceId) async {
    if (_isRemote) {
      throw UnsupportedError(
        'listVersions is local-only; the host owns its version history.',
      );
    }
    return _requireVersionsDao('listVersions').listVersions(sequenceId);
  }

  /// Rebuild an editable [Sequence] from the stored version with row id
  /// [versionId]. Returns `null` when that version no longer exists.
  ///
  /// The returned sequence keeps the version's owning `databaseId` so a
  /// subsequent save updates the same library row (restoring in place rather
  /// than forking a copy). The caller (editor) loads it into the editor and
  /// saves to persist the restore.
  Future<Sequence?> restoreVersion(int versionId) async {
    if (_isRemote) {
      throw UnsupportedError(
        'restoreVersion is local-only; the host owns its version history.',
      );
    }
    final versionsDao = _requireVersionsDao('restoreVersion');
    final fileService = _requireFileService('restoreVersion');
    final version = await versionsDao.loadVersion(versionId);
    if (version == null) return null;
    final decoded = jsonDecode(version.snapshotJson);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Version $versionId snapshot is not a JSON object '
        '(got ${decoded.runtimeType}).',
      );
    }
    final restored = fileService.parseFromMap(decoded);
    // Re-anchor to the owning sequence row so saving updates in place.
    return restored.copyWith(databaseId: version.sequenceId);
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
  return SequenceRepository(
    ref.watch(sequencesDaoProvider),
    runsDao: ref.watch(sequenceRunsDaoProvider),
    versionsDao: ref.watch(sequenceVersionsDaoProvider),
    fileService: ref.watch(sequenceFileServiceProvider),
  );
});
