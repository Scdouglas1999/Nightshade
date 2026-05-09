import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/sequences.dart';
import '../tables/targets.dart';

part 'sequences_dao.g.dart';

@DriftAccessor(tables: [Sequences, SequenceNodes, Targets])
class SequencesDao extends DatabaseAccessor<NightshadeDatabase>
    with _$SequencesDaoMixin {
  SequencesDao(NightshadeDatabase db) : super(db);

  /// Get all sequences
  Future<List<Sequence>> getAllSequences() {
    return (select(sequences)
          ..where((s) => s.isTemplate.equals(false))
          ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
        .get();
  }

  /// Watch all sequences
  Stream<List<Sequence>> watchAllSequences() {
    return (select(sequences)
          ..where((s) => s.isTemplate.equals(false))
          ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
        .watch();
  }

  /// Get all templates
  Future<List<Sequence>> getAllTemplates() {
    return (select(sequences)
          ..where((s) => s.isTemplate.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .get();
  }

  /// Watch all templates
  Stream<List<Sequence>> watchAllTemplates() {
    return (select(sequences)
          ..where((s) => s.isTemplate.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .watch();
  }

  /// Get sequence by ID
  Future<Sequence?> getSequenceById(int id) {
    return (select(sequences)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// Create a new sequence
  Future<int> createSequence(SequencesCompanion sequence) {
    return into(sequences).insert(sequence);
  }

  /// Update a sequence
  Future<bool> updateSequence(Sequence sequence) {
    return update(sequences).replace(sequence);
  }

  /// Delete a sequence and its nodes
  Future<void> deleteSequence(int id) async {
    await transaction(() async {
      // Delete all nodes
      await (delete(sequenceNodes)..where((n) => n.sequenceId.equals(id))).go();
      // Delete the sequence
      await (delete(sequences)..where((s) => s.id.equals(id))).go();
    });
  }

  /// Duplicate a sequence
  ///
  /// Generates fresh UUIDs for all duplicated nodes and remaps parent-child
  /// references (parentNodeId) and the sequence's rootNodeId to the new IDs.
  Future<int> duplicateSequence(int sourceId, String newName) async {
    final source = await getSequenceById(sourceId);
    if (source == null) {
      throw Exception('Sequence not found');
    }

    final sourceNodes = await getNodesForSequence(sourceId);
    const uuid = Uuid();

    // Build mapping from old nodeId → new nodeId
    final idMapping = <String, String>{};
    for (final node in sourceNodes) {
      idMapping[node.nodeId] = uuid.v4();
    }

    // Remap rootNodeId
    final newRootNodeId = source.rootNodeId != null
        ? idMapping[source.rootNodeId!] ?? source.rootNodeId
        : null;

    return transaction(() async {
      // Create new sequence with remapped root
      final newId = await into(sequences).insert(
        SequencesCompanion.insert(
          name: newName,
          description: Value(source.description),
          rootNodeId: Value(newRootNodeId),
          isTemplate: Value(source.isTemplate),
        ),
      );

      // Copy all nodes with new UUIDs and remapped parent references
      for (final node in sourceNodes) {
        final newNodeId = idMapping[node.nodeId]!;
        final newParentNodeId = node.parentNodeId != null
            ? idMapping[node.parentNodeId!] ?? node.parentNodeId
            : null;

        await into(sequenceNodes).insert(
          SequenceNodesCompanion.insert(
            nodeId: newNodeId,
            sequenceId: newId,
            targetId: Value(node.targetId),
            nodeType: node.nodeType,
            specificType: node.specificType,
            name: node.name,
            properties: Value(node.properties),
            recoveryConfig: Value(node.recoveryConfig),
            parentNodeId: Value(newParentNodeId),
            orderIndex: Value(node.orderIndex),
            isEnabled: Value(node.isEnabled),
          ),
        );
      }

      return newId;
    });
  }

  // Node operations

  /// Get all nodes for a sequence
  Future<List<SequenceNode>> getNodesForSequence(int sequenceId) {
    return (select(sequenceNodes)
          ..where((n) => n.sequenceId.equals(sequenceId))
          ..orderBy([(n) => OrderingTerm.asc(n.orderIndex)]))
        .get();
  }

  /// Watch nodes for a sequence
  Stream<List<SequenceNode>> watchNodesForSequence(int sequenceId) {
    return (select(sequenceNodes)
          ..where((n) => n.sequenceId.equals(sequenceId))
          ..orderBy([(n) => OrderingTerm.asc(n.orderIndex)]))
        .watch();
  }

  /// Get node by ID
  Future<SequenceNode?> getNodeById(int id) {
    return (select(sequenceNodes)..where((n) => n.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get node by UUID
  Future<SequenceNode?> getNodeByUuid(String nodeId) {
    return (select(sequenceNodes)..where((n) => n.nodeId.equals(nodeId)))
        .getSingleOrNull();
  }

  /// Create a new node
  Future<int> createNode(SequenceNodesCompanion node) {
    return into(sequenceNodes).insert(node);
  }

  /// Update a node
  Future<bool> updateNode(SequenceNode node) {
    return update(sequenceNodes).replace(node);
  }

  /// Delete a node
  Future<int> deleteNode(int id) {
    return (delete(sequenceNodes)..where((n) => n.id.equals(id))).go();
  }

  /// Enable/disable a node
  Future<void> setNodeEnabled(int id, bool enabled) {
    return (update(sequenceNodes)..where((n) => n.id.equals(id))).write(
      SequenceNodesCompanion(isEnabled: Value(enabled)),
    );
  }

  /// Reorder nodes
  Future<void> reorderNodes(int sequenceId, List<String> nodeIds) async {
    await batch((batch) {
      for (var i = 0; i < nodeIds.length; i++) {
        batch.update(
          sequenceNodes,
          SequenceNodesCompanion(orderIndex: Value(i)),
          where: (n) =>
              n.nodeId.equals(nodeIds[i]) & n.sequenceId.equals(sequenceId),
        );
      }
    });
  }

  /// Get children of a node
  Future<List<SequenceNode>> getChildNodes(int sequenceId, String parentNodeId) {
    return (select(sequenceNodes)
          ..where((n) =>
              n.sequenceId.equals(sequenceId) &
              n.parentNodeId.equals(parentNodeId))
          ..orderBy([(n) => OrderingTerm.asc(n.orderIndex)]))
        .get();
  }
}

