/// Declarative route table for stored-sequence CRUD (templates, nodes,
/// reorder/enable/disable).
///
/// Counterpart to `handlers/sequence_management_handlers.dart`. This is
/// the data-management surface; the live execution surface is in
/// `sequencer_routes.dart`.
///
/// Order constraint: the literal sub-paths (`list-full`, `templates`,
/// `templates-full`, `save-full`, `summaries`, `versions`) must register before any
/// `<id>`-parameterised route on the same prefix.
library;

import '../handlers/sequence_management_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SequenceManagementHandlers].
List<HeadlessRoute> buildSequenceManagementRoutes(
  SequenceManagementHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/list',
    h.handleGetAllSequences,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/list-full',
    h.handleListFullSequences,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/templates-full',
    h.handleListFullTemplates,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/save-full',
    h.handleSaveFullSequence,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/summaries',
    h.handleListSequenceSummaries,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/versions/<versionId>',
    h.handleGetVersion,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/<id>/full',
    h.handleGetFullSequence,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/templates',
    h.handleGetAllTemplates,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/<id>',
    h.handleGetSequenceById,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/<id>/nodes',
    h.handleGetNodesForSequence,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/<id>/nodes/<parentNodeId>/children',
    h.handleGetChildNodes,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-management/<id>/versions',
    h.handleListVersions,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management',
    h.handleCreateSequence,
  ),
  HeadlessRoute(
    HttpMethod.put,
    '/api/sequence-management/<id>',
    h.handleUpdateSequence,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/sequence-management/<id>',
    h.handleDeleteSequence,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/<id>/duplicate',
    h.handleDuplicateSequence,
  ),
  HeadlessRoute(
    HttpMethod.put,
    '/api/sequence-management/<id>/tags',
    h.handleSetTags,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/<id>/favorite',
    h.handleToggleFavorite,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/<id>/versions',
    h.handleSnapshotVersion,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/<id>/nodes',
    h.handleCreateNode,
  ),
  HeadlessRoute(
    HttpMethod.put,
    '/api/sequence-management/nodes/<nodeId>',
    h.handleUpdateNode,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/sequence-management/nodes/<nodeId>',
    h.handleDeleteNode,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/<id>/reorder',
    h.handleReorderNodes,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/sequence-management/nodes/<nodeId>/enabled',
    h.handleSetNodeEnabled,
  ),
];
