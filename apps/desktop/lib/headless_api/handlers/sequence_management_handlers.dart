import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart'
    show Sequence, SequenceNode, SequencesCompanion, SequenceNodesCompanion;
import 'package:nightshade_core/nightshade_core.dart'
    hide Sequence, SequenceNode; // Hide domain models
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for sequence management (CRUD operations)
/// This is SEPARATE from sequencer_handlers.dart which controls sequencer execution.
class SequenceManagementHandlers {
  final ProviderContainer container;

  SequenceManagementHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequenceManagementHandlers');

  /// Parse a numeric URL path segment to an int.
  ///
  /// Why a dedicated helper: `int.parse(id)` throws `FormatException` on a
  /// bad segment, which the errorTranslationMiddleware would map to 500 +
  /// requestId. That's wrong — a non-numeric path segment is a client-side
  /// error, so we raise BadRequestError and the middleware emits a clean 400.
  int _parsePathId(String value, String field) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw BadRequestError(
        field: field,
        expected: 'integer',
        message: 'Path segment "$value" is not a valid integer id',
      );
    }
    return parsed;
  }

  // ===========================================================================
  // Get All Sequences
  // ===========================================================================

  Future<Response> handleGetAllSequences(Request request) async {
    _logInfo('[API] GET /api/sequence-management/list');
    final database = container.read(databaseProvider);
    final sequences = await database.sequencesDao.getAllSequences();

    return jsonOk({
      'sequences': sequences.map((s) => _sequenceToJson(s)).toList(),
    });
  }

  // ===========================================================================
  // Get All Templates
  // ===========================================================================

  Future<Response> handleGetAllTemplates(Request request) async {
    _logInfo('[API] GET /api/sequence-management/templates');
    final database = container.read(databaseProvider);
    final templates = await database.sequencesDao.getAllTemplates();

    return jsonOk({
      'templates': templates.map((s) => _sequenceToJson(s)).toList(),
    });
  }

  // ===========================================================================
  // Get Sequence By ID
  // ===========================================================================

  Future<Response> handleGetSequenceById(Request request, String id) async {
    _logInfo('[API] GET /api/sequence-management/$id');
    final sequenceId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final sequence = await database.sequencesDao.getSequenceById(sequenceId);

    if (sequence == null) {
      return jsonNotFound({'error': 'Sequence not found: $id'});
    }

    return jsonOk({'sequence': _sequenceToJson(sequence)});
  }

  // ===========================================================================
  // Get Nodes For Sequence
  // ===========================================================================

  Future<Response> handleGetNodesForSequence(Request request, String id) async {
    _logInfo('[API] GET /api/sequence-management/$id/nodes');
    final sequenceId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);
    final nodes = await database.sequencesDao.getNodesForSequence(sequenceId);

    return jsonOk({
      'nodes': nodes.map((n) => _nodeToJson(n)).toList(),
    });
  }

  // ===========================================================================
  // Create Sequence
  // ===========================================================================

  Future<Response> handleCreateSequence(Request request) async {
    _logInfo('[API] POST /api/sequence-management');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    final companion = SequencesCompanion.insert(
      name: requireString(payload, 'name'),
      description: Value(optionalString(payload, 'description')),
      rootNodeId: Value(optionalString(payload, 'rootNodeId')),
      isTemplate: Value(optionalBool(payload, 'isTemplate') ?? false),
    );

    final id = await database.sequencesDao.createSequence(companion);

    return jsonOk({'status': 'created', 'id': id});
  }

  // ===========================================================================
  // Update Sequence
  // ===========================================================================

  Future<Response> handleUpdateSequence(Request request, String id) async {
    _logInfo('[API] PUT /api/sequence-management/$id');
    final sequenceId = _parsePathId(id, 'id');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    // Get existing sequence
    final existing = await database.sequencesDao.getSequenceById(sequenceId);
    if (existing == null) {
      return jsonNotFound({'error': 'Sequence not found: $id'});
    }

    // Build updated sequence. optionalString returning null when the field is
    // absent means we fall back to the existing values, preserving partial-
    // update semantics.
    final updated = existing.copyWith(
      name: optionalString(payload, 'name') ?? existing.name,
      description:
          Value(optionalString(payload, 'description') ?? existing.description),
      rootNodeId:
          Value(optionalString(payload, 'rootNodeId') ?? existing.rootNodeId),
      isTemplate: optionalBool(payload, 'isTemplate') ?? existing.isTemplate,
      updatedAt: DateTime.now(),
    );

    await database.sequencesDao.updateSequence(updated);

    return jsonOk({'status': 'updated'});
  }

  // ===========================================================================
  // Delete Sequence
  // ===========================================================================

  Future<Response> handleDeleteSequence(Request request, String id) async {
    _logInfo('[API] DELETE /api/sequence-management/$id');
    final sequenceId = _parsePathId(id, 'id');
    final database = container.read(databaseProvider);

    await database.sequencesDao.deleteSequence(sequenceId);

    return jsonOk({'status': 'deleted'});
  }

  // ===========================================================================
  // Duplicate Sequence
  // ===========================================================================

  Future<Response> handleDuplicateSequence(Request request, String id) async {
    _logInfo('[API] POST /api/sequence-management/$id/duplicate');
    final sequenceId = _parsePathId(id, 'id');
    final payload = await readJsonObject(request);
    final newName = optionalString(payload, 'name') ?? 'Copy';
    final database = container.read(databaseProvider);

    final newId =
        await database.sequencesDao.duplicateSequence(sequenceId, newName);

    return jsonOk({'status': 'duplicated', 'id': newId});
  }

  // ===========================================================================
  // Create Node
  // ===========================================================================

  Future<Response> handleCreateNode(Request request, String sequenceId) async {
    _logInfo('[API] POST /api/sequence-management/$sequenceId/nodes');
    final seqId = _parsePathId(sequenceId, 'sequenceId');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    final propertiesValue = optionalString(payload, 'properties') ?? '{}';
    final companion = SequenceNodesCompanion.insert(
      nodeId: requireString(payload, 'nodeId'),
      sequenceId: seqId,
      targetId: Value(optionalInt(payload, 'targetId')),
      nodeType: requireString(payload, 'nodeType'),
      specificType: requireString(payload, 'specificType'),
      name: requireString(payload, 'name'),
      properties: Value(propertiesValue),
      recoveryConfig: Value(optionalString(payload, 'recoveryConfig')),
      parentNodeId: Value(optionalString(payload, 'parentNodeId')),
      orderIndex: Value(optionalInt(payload, 'orderIndex') ?? 0),
      isEnabled: Value(optionalBool(payload, 'isEnabled') ?? false),
    );

    final id = await database.sequencesDao.createNode(companion);

    return jsonOk({'status': 'created', 'id': id});
  }

  // ===========================================================================
  // Update Node
  // ===========================================================================

  Future<Response> handleUpdateNode(Request request, String nodeId) async {
    _logInfo('[API] PUT /api/sequence-management/nodes/$nodeId');
    final nid = _parsePathId(nodeId, 'nodeId');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    // Get existing node
    final existing = await database.sequencesDao.getNodeById(nid);
    if (existing == null) {
      return jsonNotFound({'error': 'Node not found: $nodeId'});
    }

    // Build updated node. As with handleUpdateSequence, missing fields fall
    // back to existing values.
    final updatedProperties =
        optionalString(payload, 'properties') ?? existing.properties;
    final updated = existing.copyWith(
      name: optionalString(payload, 'name') ?? existing.name,
      nodeType: optionalString(payload, 'nodeType') ?? existing.nodeType,
      specificType:
          optionalString(payload, 'specificType') ?? existing.specificType,
      properties: updatedProperties,
      recoveryConfig: Value(
          optionalString(payload, 'recoveryConfig') ?? existing.recoveryConfig),
      parentNodeId: Value(
          optionalString(payload, 'parentNodeId') ?? existing.parentNodeId),
      orderIndex: optionalInt(payload, 'orderIndex') ?? existing.orderIndex,
      isEnabled: optionalBool(payload, 'isEnabled') ?? existing.isEnabled,
    );

    await database.sequencesDao.updateNode(updated);

    return jsonOk({'status': 'updated'});
  }

  // ===========================================================================
  // Delete Node
  // ===========================================================================

  Future<Response> handleDeleteNode(Request request, String nodeId) async {
    _logInfo('[API] DELETE /api/sequence-management/nodes/$nodeId');
    final nid = _parsePathId(nodeId, 'nodeId');
    final database = container.read(databaseProvider);

    final deleted = await database.sequencesDao.deleteNode(nid);
    if (deleted == 0) {
      return jsonNotFound({'error': 'Node not found: $nodeId'});
    }

    return jsonOk({'status': 'deleted'});
  }

  // ===========================================================================
  // Reorder Nodes
  // ===========================================================================

  Future<Response> handleReorderNodes(
      Request request, String sequenceId) async {
    _logInfo('[API] POST /api/sequence-management/$sequenceId/reorder');
    final seqId = _parsePathId(sequenceId, 'sequenceId');
    final payload = await readJsonObject(request);
    final nodeIds = requireList<String>(payload, 'nodeIds');
    final database = container.read(databaseProvider);

    await database.sequencesDao.reorderNodes(seqId, nodeIds);

    return jsonOk({'status': 'reordered'});
  }

  // ===========================================================================
  // Set Node Enabled
  // ===========================================================================

  Future<Response> handleSetNodeEnabled(Request request, String nodeId) async {
    _logInfo('[API] POST /api/sequence-management/nodes/$nodeId/enabled');
    final nid = _parsePathId(nodeId, 'nodeId');
    final payload = await readJsonObject(request);
    final enabled = requireBool(payload, 'enabled');
    final database = container.read(databaseProvider);

    await database.sequencesDao.setNodeEnabled(nid, enabled);

    return jsonOk({'status': 'updated'});
  }

  // ===========================================================================
  // Get Child Nodes
  // ===========================================================================

  Future<Response> handleGetChildNodes(
      Request request, String sequenceId, String parentNodeId) async {
    _logInfo(
        '[API] GET /api/sequence-management/$sequenceId/nodes/$parentNodeId/children');
    final seqId = _parsePathId(sequenceId, 'sequenceId');
    final database = container.read(databaseProvider);
    final nodes =
        await database.sequencesDao.getChildNodes(seqId, parentNodeId);

    return jsonOk({
      'nodes': nodes.map((n) => _nodeToJson(n)).toList(),
    });
  }

  // ===========================================================================
  // Helper: Convert Sequence to JSON
  // ===========================================================================

  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return {
      'id': sequence.id,
      'name': sequence.name,
      'description': sequence.description,
      'rootNodeId': sequence.rootNodeId,
      'isTemplate': sequence.isTemplate,
      'createdAt': sequence.createdAt.millisecondsSinceEpoch,
      'updatedAt': sequence.updatedAt.millisecondsSinceEpoch,
    };
  }

  // ===========================================================================
  // Helper: Convert SequenceNode to JSON
  // ===========================================================================

  Map<String, dynamic> _nodeToJson(SequenceNode node) {
    return {
      'id': node.id,
      'nodeId': node.nodeId,
      'sequenceId': node.sequenceId,
      'targetId': node.targetId,
      'nodeType': node.nodeType,
      'specificType': node.specificType,
      'name': node.name,
      'properties': node.properties,
      'recoveryConfig': node.recoveryConfig,
      'parentNodeId': node.parentNodeId,
      'orderIndex': node.orderIndex,
      'isEnabled': node.isEnabled,
    };
  }
}
