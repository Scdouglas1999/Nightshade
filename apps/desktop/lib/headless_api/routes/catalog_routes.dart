/// Declarative route table for the P1-12 catalog-management surface.
///
/// Counterpart to `handlers/catalog_handlers.dart`. Without these
/// endpoints a freshly imaged Pi has no way to populate its star/DSO
/// catalogs without SSH; plate solving fails until someone runs the
/// desktop GUI.
///
/// Order constraint: the literal sub-paths (`status`, `available`,
/// `download`, `upload`, `verify`, `reload`) MUST register before the
/// `<name>` route or shelf_router will match `status` etc. as the path-
/// param value and the DELETE will shadow every read endpoint.
library;

import '../handlers/catalog_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [CatalogHandlers].
List<HeadlessRoute> buildCatalogRoutes(CatalogHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/catalog/status', h.handleStatus),
  HeadlessRoute(HttpMethod.get, '/api/catalog/available', h.handleAvailable),
  HeadlessRoute(HttpMethod.post, '/api/catalog/download', h.handleDownload),
  HeadlessRoute(HttpMethod.post, '/api/catalog/upload', h.handleUpload),
  HeadlessRoute(HttpMethod.post, '/api/catalog/verify', h.handleVerify),
  HeadlessRoute(HttpMethod.post, '/api/catalog/reload', h.handleReload),
  HeadlessRoute(HttpMethod.delete, '/api/catalog/<name>', h.handleDelete),
];
