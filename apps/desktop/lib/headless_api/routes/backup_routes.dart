/// Declarative route table for backup/restore endpoints.
///
/// Counterpart to `handlers/backup_handlers.dart`. Auto-save runs on
/// the scheduler; the upload-restore endpoint accepts a multipart
/// upload and is the only `/api/backup/*` route covered by the
/// large-body limit in `route_metadata.dart`.
library;

import '../handlers/backup_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [BackupHandlers].
List<HeadlessRoute> buildBackupRoutes(BackupHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/backup/list', h.handleListBackups),
  HeadlessRoute(HttpMethod.post, '/api/backup/create', h.handleCreateBackup),
  HeadlessRoute(HttpMethod.post, '/api/backup/restore', h.handleRestoreBackup),
  HeadlessRoute(
    HttpMethod.post,
    '/api/backup/auto-save',
    h.handleAutoSaveBackup,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/backup/upload-restore',
    h.handleUploadRestoreBackup,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/backup/<id>/metadata',
    h.handleGetBackupMetadata,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/backup/<id>/download',
    h.handleDownloadBackup,
  ),
  HeadlessRoute(HttpMethod.delete, '/api/backup/<id>', h.handleDeleteBackup),
];
