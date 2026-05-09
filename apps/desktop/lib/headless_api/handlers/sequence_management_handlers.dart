import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/database_entities.dart'
    show Sequence, SequenceNode, SequencesCompanion, SequenceNodesCompanion;
import 'package:nightshade_core/nightshade_core.dart'
    hide Sequence, SequenceNode; // Hide domain models
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for sequence management (CRUD operations)
/// This is SEPARATE from sequencer_handlers.dart which controls sequencer execution.
class SequenceManagementHandlers {
  final ProviderContainer container;

  SequenceManagementHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequenceManagementHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'SequenceManagementHandlers');

  // ===========================================================================
  // Get All Sequences
  // ===========================================================================

  Future<Response> handleGetAllSequences(Request request) async {
    _logInfo('[API] GET /api/sequence-management/list');
    try {
      final database = container.read(databaseProvider);
      final sequences = await database.sequencesDao.getAllSequences();

      return jsonOk({
        "sequences": sequences.map((s) => _sequenceToJson(s)).toList(),
      });
    } catch (e) {
      _logError('[API] Get all sequences error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get All Templates
  // ===========================================================================

  Future<Response> handleGetAllTemplates(Request request) async {
    _logInfo('[API] GET /api/sequence-management/templates');
    try {
      final database = container.read(databaseProvider);
      final templates = await database.sequencesDao.getAllTemplates();

      return jsonOk({
        "templates": templates.map((s) => _sequenceToJson(s)).toList(),
      });
    } catch (e) {
      _logError('[API] Get all templates error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Sequence By ID
  // ===========================================================================

  Future<Response> handleGetSequenceById(Request request, String id) async {
    _logInfo('[API] GET /api/sequence-management/$id');
    try {
      final sequenceId = int.parse(id);
      final database = container.read(databaseProvider);
      final sequence = await database.sequencesDao.getSequenceById(sequenceId);

      if (sequence == null) {
        return jsonNotFound({"error": "Sequence not found: $id"});
      }

      return jsonOk({"sequence": _sequenceToJson(sequence)});
    } catch (e) {
      _logError('[API] Get sequence by ID error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Nodes For Sequence
  // ===========================================================================

  Future<Response> handleGetNodesForSequence(Request request, String id) async {
    _logInfo('[API] GET /api/sequence-management/$id/nodes');
    try {
      final sequenceId = int.parse(id);
      final database = container.read(databaseProvider);
      final nodes = await database.sequencesDao.getNodesForSequence(sequenceId);

      return jsonOk({
        "nodes": nodes.map((n) => _nodeToJson(n)).toList(),
      });
    } catch (e) {
      _logError('[API] Get nodes for sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Create Sequence
  // ===========================================================================

  Future<Response> handleCreateSequence(Request request) async {
    _logInfo('[API] POST /api/sequence-management');
    try {
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      final companion = SequencesCompanion.insert(
        name: payload['name'] as String,
        description: Value(payload['description'] as String?),
        rootNodeId: Value(payload['rootNodeId'] as String?),
        isTemplate: Value(payload['isTemplate'] as bool? ?? false),
      );

      final id = await database.sequencesDao.createSequence(companion);

      return jsonOk({"status": "created", "id": id});
    } catch (e) {
      _logError('[API] Create sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Sequence
  // ===========================================================================

  Future<Response> handleUpdateSequence(Request request, String id) async {
    _logInfo('[API] PUT /api/sequence-management/$id');
    try {
      final sequenceId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      // Get existing sequence
      final existing = await database.sequencesDao.getSequenceById(sequenceId);
      if (existing == null) {
        return jsonNotFound({"error": "Sequence not found: $id"});
      }

      // Build updated sequence
      final updated = existing.copyWith(
        name: payload['name'] as String? ?? existing.name,
        description:
            Value(payload['description'] as String? ?? existing.description),
        rootNodeId:
            Value(payload['rootNodeId'] as String? ?? existing.rootNodeId),
        isTemplate: payload['isTemplate'] as bool? ?? existing.isTemplate,
        updatedAt: DateTime.now(),
      );

      await database.sequencesDao.updateSequence(updated);

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Delete Sequence
  // ===========================================================================

  Future<Response> handleDeleteSequence(Request request, String id) async {
    _logInfo('[API] DELETE /api/sequence-management/$id');
    try {
      final sequenceId = int.parse(id);
      final database = container.read(databaseProvider);

      await database.sequencesDao.deleteSequence(sequenceId);

      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Duplicate Sequence
  // ===========================================================================

  Future<Response> handleDuplicateSequence(Request request, String id) async {
    _logInfo('[API] POST /api/sequence-management/$id/duplicate');
    try {
      final sequenceId = int.parse(id);
      final payload = jsonDecode(await request.readAsString());
      final newName = payload['name'] as String? ?? 'Copy';
      final database = container.read(databaseProvider);

      final newId =
          await database.sequencesDao.duplicateSequence(sequenceId, newName);

      return jsonOk({"status": "duplicated", "id": newId});
    } catch (e) {
      _logError('[API] Duplicate sequence error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Create Node
  // ===========================================================================

  Future<Response> handleCreateNode(Request request, String sequenceId) async {
    _logInfo('[API] POST /api/sequence-management/$sequenceId/nodes');
    try {
      final seqId = int.parse(sequenceId);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      final propertiesValue = payload['properties'] as String? ?? '{}';
      final companion = SequenceNodesCompanion.insert(
        nodeId: payload['nodeId'] as String,
        sequenceId: seqId,
        targetId: Value(payload['targetId'] as int?),
        nodeType: payload['nodeType'] as String,
        specificType: payload['specificType'] as String,
        name: payload['name'] as String,
        properties: Value(propertiesValue),
        recoveryConfig: Value(payload['recoveryConfig'] as String?),
        parentNodeId: Value(payload['parentNodeId'] as String?),
        orderIndex: Value(payload['orderIndex'] as int? ?? 0),
        isEnabled: Value(payload['isEnabled'] as bool? ?? false),
      );

      final id = await database.sequencesDao.createNode(companion);

      return jsonOk({"status": "created", "id": id});
    } catch (e) {
      _logError('[API] Create node error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Update Node
  // ===========================================================================

  Future<Response> handleUpdateNode(Request request, String nodeId) async {
    _logInfo('[API] PUT /api/sequence-management/nodes/$nodeId');
    try {
      final nid = int.parse(nodeId);
      final payload = jsonDecode(await request.readAsString());
      final database = container.read(databaseProvider);

      // Get existing node
      final existing = await database.sequencesDao.getNodeById(nid);
      if (existing == null) {
        return jsonNotFound({"error": "Node not found: $nodeId"});
      }

      // Build updated node
      final updatedProperties =
          payload['properties'] as String? ?? existing.properties;
      final updated = existing.copyWith(
        name: payload['name'] as String? ?? existing.name,
        nodeType: payload['nodeType'] as String? ?? existing.nodeType,
        specificType:
            payload['specificType'] as String? ?? existing.specificType,
        properties: updatedProperties,
        recoveryConfig: Value(
            payload['recoveryConfig'] as String? ?? existing.recoveryConfig),
        parentNodeId:
            Value(payload['parentNodeId'] as String? ?? existing.parentNodeId),
        orderIndex: payload['orderIndex'] as int? ?? existing.orderIndex,
        isEnabled: payload['isEnabled'] as bool? ?? existing.isEnabled,
      );

      await database.sequencesDao.updateNode(updated);

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Update node error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Delete Node
  // ===========================================================================

  Future<Response> handleDeleteNode(Request request, String nodeId) async {
    _logInfo('[API] DELETE /api/sequence-management/nodes/$nodeId');
    try {
      final nid = int.parse(nodeId);
      final database = container.read(databaseProvider);

      final deleted = await database.sequencesDao.deleteNode(nid);
      if (deleted == 0) {
        return jsonNotFound({"error": "Node not found: $nodeId"});
      }

      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete node error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Reorder Nodes
  // ===========================================================================

  Future<Response> handleReorderNodes(
      Request request, String sequenceId) async {
    _logInfo('[API] POST /api/sequence-management/$sequenceId/reorder');
    try {
      final seqId = int.parse(sequenceId);
      final payload = jsonDecode(await request.readAsString());
      final nodeIds = (payload['nodeIds'] as List).cast<String>();
      final database = container.read(databaseProvider);

      await database.sequencesDao.reorderNodes(seqId, nodeIds);

      return jsonOk({"status": "reordered"});
    } catch (e) {
      _logError('[API] Reorder nodes error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Set Node Enabled
  // ===========================================================================

  Future<Response> handleSetNodeEnabled(Request request, String nodeId) async {
    _logInfo('[API] POST /api/sequence-management/nodes/$nodeId/enabled');
    try {
      final nid = int.parse(nodeId);
      final payload = jsonDecode(await request.readAsString());
      final enabled = payload['enabled'] as bool;
      final database = container.read(databaseProvider);

      await database.sequencesDao.setNodeEnabled(nid, enabled);

      return jsonOk({"status": "updated"});
    } catch (e) {
      _logError('[API] Set node enabled error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Child Nodes
  // ===========================================================================

  Future<Response> handleGetChildNodes(
      Request request, String sequenceId, String parentNodeId) async {
    _logInfo(
        '[API] GET /api/sequence-management/$sequenceId/nodes/$parentNodeId/children');
    try {
      final seqId = int.parse(sequenceId);
      final database = container.read(databaseProvider);
      final nodes =
          await database.sequencesDao.getChildNodes(seqId, parentNodeId);

      return jsonOk({
        "nodes": nodes.map((n) => _nodeToJson(n)).toList(),
      });
    } catch (e) {
      _logError('[API] Get child nodes error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
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
