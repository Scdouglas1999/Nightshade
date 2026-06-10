/// Declarative route table for the P2-8 read-only DB surface.
///
/// Counterpart to `handlers/db_read_handlers.dart`. Covers tables the
/// phone couldn't see before: sequence runs, notes journal, guide-RMS
/// history, polar alignment history, dark library, flat history. All
/// paginated, all under `/api` with the same `{items,total}` envelope
/// shape.
library;

import '../handlers/db_read_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [DbReadHandlers].
List<HeadlessRoute> buildDbReadRoutes(DbReadHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/sequence-runs', h.handleListSequenceRuns),
  // Wave 7B — session replay endpoints. ORDER MATTERS: specific path with
  // child segments (`/events`, `/frames`) registers before the catch-all
  // `/<runId>` so shelf_router doesn't shadow them with the by-id handler.
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-runs/<runId>/events',
    h.handleGetSequenceRunEvents,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-runs/<runId>/frames',
    h.handleGetSequenceRunFrames,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/sequence-runs/<runId>',
    h.handleGetSequenceRunById,
  ),
  HeadlessRoute(HttpMethod.get, '/api/notes-journal', h.handleListNotesJournal),
  HeadlessRoute(
    HttpMethod.get,
    '/api/guide-rms-history',
    h.handleListGuideRmsHistory,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/polar-alignment-history',
    h.handleListPolarAlignmentHistory,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/db/dark-library',
    h.handleListDarkLibrary,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/db/flat-history',
    h.handleListFlatHistory,
  ),
];
