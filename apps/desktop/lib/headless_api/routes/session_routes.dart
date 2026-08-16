/// Declarative route table for the imaging-session surface — polar
/// alignment lifecycle, session images, and per-session export.
///
/// Counterpart to `handlers/session_handlers.dart`. Note the ordering
/// constraint: `/api/images/backfill-thumbnails` MUST appear before
/// `/api/images/<imageId>` because shelf_router matches in declaration
/// order — registering the parametric one first shadows the literal
/// segment. Same constraint applies for `/api/images/recent` and
/// `/api/images/standalone`. See `headless_route.dart` for the broader
/// rationale.
library;

import '../handlers/session_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SessionHandlers].
List<HeadlessRoute> buildSessionRoutes(SessionHandlers h) => <HeadlessRoute>[
  // Polar Alignment
  HeadlessRoute(
    HttpMethod.post,
    '/api/polar-alignment/start',
    h.handleStartPolarAlignment,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/polar-alignment/all-sky/start',
    h.handleStartAllSkyPolarAlignment,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/polar-alignment/stop',
    h.handleStopPolarAlignment,
  ),

  // Session Images
  HeadlessRoute(
    HttpMethod.get,
    '/api/sessions/<sessionId>/images',
    h.handleGetSessionImages,
  ),
  HeadlessRoute(HttpMethod.get, '/api/images', h.handleGetAllImages),
  // Legacy alias for mobile clients that pre-date /api/images. Kept because
  // dropping the path would break pinned mobile builds in the field.
  HeadlessRoute(HttpMethod.get, '/api/images/recent', h.handleGetRecentImages),
  HeadlessRoute(
    HttpMethod.get,
    '/api/images/standalone',
    h.handleGetStandaloneImages,
  ),
  // registered BEFORE the `<imageId>` patterns so the literal
  // `backfill-thumbnails` segment isn't matched as a path param.
  HeadlessRoute(
    HttpMethod.post,
    '/api/images/backfill-thumbnails',
    h.handleBackfillThumbnails,
  ),
  HeadlessRoute(HttpMethod.post, '/api/images', h.handleCreateImage),
  HeadlessRoute(HttpMethod.get, '/api/images/<imageId>', h.handleGetImageById),
  HeadlessRoute(HttpMethod.put, '/api/images/<imageId>', h.handleUpdateImage),
  HeadlessRoute(
    HttpMethod.get,
    '/api/images/<imageId>/thumbnail',
    h.handleGetImageThumbnail,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/images/<imageId>/regenerate-thumbnail',
    h.handleRegenerateImageThumbnail,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/images/<imageId>/download',
    h.handleDownloadImage,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sessions/<sessionId>/export/json',
    h.handleExportSessionJson,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sessions/<sessionId>/export/csv',
    h.handleExportSessionCsv,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sessions/<sessionId>/export/html',
    h.handleExportSessionHtml,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sessions/<sessionId>/export/<format>',
    h.handleExportSession,
  ),
];
