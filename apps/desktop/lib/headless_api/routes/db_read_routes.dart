/// Declarative route table for the host-authoritative DB surface.
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
  // session replay endpoints. ORDER MATTERS: specific path with
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
    HttpMethod.post,
    '/api/notes-journal',
    h.handleCreateObservationLog,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/notes-journal/<id>',
    h.handleDeleteObservationLog,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/notes-journal',
    h.handleDeleteAllObservationLogs,
  ),
  HeadlessRoute(HttpMethod.get, '/api/db/notes', h.handleListJournalNotes),
  HeadlessRoute(HttpMethod.post, '/api/db/notes', h.handleCreateJournalNote),
  HeadlessRoute(
    HttpMethod.put,
    '/api/db/notes/<id>',
    h.handleUpdateJournalNote,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/db/notes/<id>',
    h.handleDeleteJournalNote,
  ),
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
