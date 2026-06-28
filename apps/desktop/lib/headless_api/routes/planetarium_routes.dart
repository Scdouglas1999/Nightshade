/// Declarative route table for the remote-planetarium client surface.
///
/// Counterpart to `handlers/planetarium_handlers.dart`. Exposes the
/// in-process planetarium state (mount position, FOV config, catalog
/// search/region/object lookup) to mobile and web clients that render
/// the sky locally.
library;

import '../handlers/planetarium_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PlanetariumHandlers].
List<HeadlessRoute> buildPlanetariumRoutes(
  PlanetariumHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/mount-position',
    h.handleGetMountPosition,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/fov-config',
    h.handleGetFovConfig,
  ),
  HeadlessRoute(HttpMethod.post, '/api/planetarium/slew-to', h.handleSlewTo),
  HeadlessRoute(
    HttpMethod.post,
    '/api/planetarium/center-on',
    h.handleCenterOn,
  ),
  HeadlessRoute(HttpMethod.post, '/api/planetarium/sync-to', h.handleSyncTo),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/catalog/search',
    h.handleCatalogSearch,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/catalog/region',
    h.handleCatalogRegion,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/catalog/object/<objectId>',
    h.handleGetCatalogObject,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/subscribe-info',
    h.handleGetSubscribeInfo,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/planetarium/location',
    h.handleGetLocation,
  ),
  // Observing lists (host-backed favorites/lists subsystem).
  HeadlessRoute(
    HttpMethod.get,
    '/api/observing-lists',
    h.handleGetObservingLists,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/observing-lists/items',
    h.handleGetObservingListItems,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/observing-lists/listed-catalog-ids',
    h.handleGetListedCatalogIds,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/observing-lists/containing',
    h.handleGetListsContaining,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/observing-lists',
    h.handleCreateObservingList,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/observing-lists/update',
    h.handleUpdateObservingList,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/observing-lists',
    h.handleDeleteObservingList,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/observing-lists/duplicate',
    h.handleDuplicateObservingList,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/observing-lists/items',
    h.handleAddObservingListItem,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/observing-lists/items',
    h.handleRemoveObservingListItem,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/observing-lists/items/update-notes',
    h.handleUpdateObservingListItemNotes,
  ),
];
