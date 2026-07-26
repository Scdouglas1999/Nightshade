/// Declarative route table for mosaic-planning endpoints.
///
/// Counterpart to `handlers/mosaic_handlers.dart`. All reads/writes for
/// panel generation, area calculation, validation, and time estimation;
/// the recommended-exposure GET wraps the sequencer's exposure model.
library;

import '../handlers/mosaic_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [MosaicHandlers].
List<HeadlessRoute> buildMosaicRoutes(MosaicHandlers h) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/generate-panels',
    h.handleGeneratePanels,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/generate-sequence',
    h.handleGenerateSequence,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/calculate-area',
    h.handleCalculateArea,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/validate',
    h.handleValidateMosaic,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/estimate-time',
    h.handleEstimateTime,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/mosaic/recommended-exposure',
    h.handleRecommendExposure,
  ),
  // Collaborative Sky WS2 — distributed collaborative-mosaic flow for an
  // unattended rig. OWNER path: publish/claim/upload/assemble. PARTICIPANT path:
  // discover (list/get), join, status, and output-download — without join wired
  // the claim/upload routes are dead for non-owners.
  HeadlessRoute(
    HttpMethod.get,
    '/api/mosaic/collaborative',
    h.handleListCollaborative,
  ),
  // Literal sub-path `join` MUST register before the bare `<mosaicId>` GET on
  // the same prefix.
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/collaborative/<mosaicId>/join',
    h.handleJoinCollaborativeMosaic,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/mosaic/collaborative/<mosaicId>',
    h.handleGetCollaborative,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/publish',
    h.handlePublishCollaborative,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/join',
    h.handleJoinCollaborative,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/mosaic/projects/<projectId>/status',
    h.handleCollaborativeStatus,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/panels/<panelIndex>/claim',
    h.handleClaimPanel,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/panels/<panelIndex>/release',
    h.handleReleasePanel,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/panels/<panelIndex>/force-release',
    h.handleForceReleasePanel,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/panels/<panelIndex>/upload',
    h.handleUploadPanel,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/assemble',
    h.handleAssembleMosaic,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/mosaic/projects/<projectId>/output',
    h.handleDownloadCollaborativeOutput,
  ),
];
