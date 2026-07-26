/// Declarative route table for the Pillar A ("Your Sky") sky-atlas surface.
///
/// Counterpart to `handlers/atlas_handlers.dart`. Backs the atlas browser a
/// [NetworkBackend] mobile companion renders: region list, per-tile coverage
/// (the heat-overlay / contribution feed), per-region detail + live coverage, a
/// co-added cutout image, and the per-region fold timeline / growth curve.
library;

import '../handlers/atlas_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [AtlasHandlers].
List<HeadlessRoute> buildAtlasRoutes(AtlasHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/atlas/regions', h.handleGetRegions),
  HeadlessRoute(HttpMethod.post, '/api/atlas/regions', h.handleCreateRegion),
  HeadlessRoute(HttpMethod.get, '/api/atlas/coverage', h.handleGetCoverage),
  HeadlessRoute(HttpMethod.get, '/api/atlas/region/<id>', h.handleGetRegion),
  HeadlessRoute(
    HttpMethod.get,
    '/api/atlas/region/<id>/cutout',
    h.handleGetRegionCutout,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/atlas/region/<id>/timeline',
    h.handleGetRegionTimeline,
  ),
];
