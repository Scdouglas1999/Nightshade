import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for backup and restore operations
class BackupHandlers {
  static const int _maxBackupUploadBytes = 256 * 1024 * 1024;

  /// Filename pattern: nightshade-backup-{timestamp}-{uuid}.nsbackup.
  ///
  /// §2.25: backup IDs must be stable across processes. Dart `hashCode` is not
  /// stable across VM restarts and can collide, so we encode a UUID directly
  /// into the filename and use it as the public REST identifier for delete /
  /// download / metadata. The pattern matches both newly-created backups and
  /// the legacy `nightshade_backup_*` / `nightshade_autosave_*` names that
  /// existed before this commit (those fall back to a deterministic, process-
  /// independent fingerprint — see [_idForBackupFile]).
  static final RegExp _uuidInFilenamePattern = RegExp(
    r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
  );

  static const _uuid = Uuid();

  final ProviderContainer container;
  BackupHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'BackupHandlers');
  void _logWarning(String message) =>
      _logger.warning(message, source: 'BackupHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'BackupHandlers');

  // ===========================================================================
  // List Backups
  // ===========================================================================

  Future<Response> handleListBackups(Request request) async {
    _logInfo('[API] GET /api/backup/list');
    final service = container.read(backupServiceProvider);
    final backupFiles = await service.listBackups();

    final backups = <Map<String, dynamic>>[];
    for (final file in backupFiles) {
      final metadata = await service.readBackupMetadata(file.path);
      final stat = await file.stat();

      backups.add({
        'id': _idForBackupFile(file),
        'filePath': file.path,
        'fileName': file.uri.pathSegments.last,
        'createdAt': metadata?.createdAt.millisecondsSinceEpoch ??
            stat.modified.millisecondsSinceEpoch,
        'fileSize': stat.size,
        'metadata': metadata != null
            ? {
                'version': metadata.version,
                'appVersion': metadata.appVersion,
                'platform': metadata.platform,
                'settingsCount': metadata.settingsCount,
                'profilesCount': metadata.profilesCount,
                'sequencesCount': metadata.sequencesCount,
                'targetsCount': metadata.targetsCount,
              }
            : null,
      });
    }

    return jsonOk({'backups': backups});
  }

  // ===========================================================================
  // Create Backup
  // ===========================================================================

  Future<Response> handleCreateBackup(Request request) async {
    _logInfo('[API] POST /api/backup/create');
    final payload = await readJsonObject(request);
    final customPath = optionalString(payload, 'customPath');
    final autoSave = optionalBool(payload, 'autoSave') ?? false;

    final service = container.read(backupServiceProvider);

    final BackupResult result;
    if (autoSave) {
      // §2.25: route auto-save through createBackup with a UUID-bearing path
      // (instead of service.autoSaveBackup) so the new backup has a stable
      // identifier extractable from the filename. autoSaveBackup itself would
      // produce a `nightshade_autosave_<ts>.nsbackup` name that the
      // _idForBackupFile fallback can address as "legacy-..." but cannot turn
      // into a real UUID, defeating the §2.25 stability guarantee for IDs
      // returned to the caller in the create response.
      final autoSavePath = await _defaultUuidBackupPath(service, tag: 'auto');
      result = await service.createBackup(customPath: autoSavePath);
    } else {
      final effectivePath = customPath ?? await _defaultUuidBackupPath(service);
      result = await service.createBackup(customPath: effectivePath);
    }

    if (result.success) {
      return jsonOk({
        'status': 'created',
        'id': result.filePath != null
            ? _idForBackupFile(File(result.filePath!))
            : null,
        'filePath': result.filePath,
        'itemsBackedUp': result.itemsBackedUp,
        'timestamp': result.timestamp.millisecondsSinceEpoch,
      });
    }
    // §2.23: failed create is a server-side problem (disk, db, ...). The
    // caller cannot fix it by changing their request, so 500, not 200.
    // §6a-fixed: surface as structured HandlerFailure so the wire body
    // carries a stable code instead of the legacy free-form failure shape.
    _logError('[API] Create backup failed: ${result.errorMessage}');
    throw HandlerFailure(
      code: 'backup_create_failed',
      message: result.errorMessage ?? 'Backup creation failed',
    );
  }

  // ===========================================================================
  // Restore Backup
  // ===========================================================================

  Future<Response> handleRestoreBackup(Request request) async {
    _logInfo('[API] POST /api/backup/restore');
    final payload = await readJsonObject(request);
    final filePath = requireString(payload, 'filePath');
    final replaceExisting = optionalBool(payload, 'replaceExisting') ?? false;

    final service = container.read(backupServiceProvider);
    final result = await service.restoreBackup(
      filePath: filePath,
      replaceExisting: replaceExisting,
    );

    if (result.success) {
      return jsonOk({
        'status': 'restored',
        'itemsRestored': result.itemsRestored,
        'categoryCounts': result.categoryCounts,
        'timestamp': result.timestamp.millisecondsSinceEpoch,
      });
    }
    // §2.23: restore-from-disk failures aren't necessarily caused by a bad
    // request body (the file path was valid syntactically). The most common
    // cause is a corrupted/missing backup or db write failure, both 500-class.
    // §6a-fixed: emit a structured HandlerFailure rather than the legacy
    // free-form failure shape that triggered the fail-closed rule.
    _logError('[API] Restore backup failed: ${result.errorMessage}');
    throw HandlerFailure(
      code: 'backup_restore_failed',
      message: result.errorMessage ?? 'Backup restore failed',
    );
  }

  // ===========================================================================
  // Delete Backup
  // ===========================================================================

  Future<Response> handleDeleteBackup(Request request, String id) async {
    _logInfo('[API] DELETE /api/backup/$id');
    final service = container.read(backupServiceProvider);
    final backupFiles = await service.listBackups();

    final file = backupFiles
        .where((f) => _idForBackupFile(f) == id)
        .firstOrNull;

    if (file == null) {
      return jsonNotFound({'error': 'Backup not found: $id'});
    }

    await file.delete();

    return jsonOk({'status': 'deleted'});
  }

  // ===========================================================================
  // Download Backup
  // ===========================================================================

  Future<Response> handleDownloadBackup(Request request, String id) async {
    _logInfo('[API] GET /api/backup/$id/download');
    final service = container.read(backupServiceProvider);
    final backupFiles = await service.listBackups();

    final file = backupFiles
        .where((f) => _idForBackupFile(f) == id)
        .firstOrNull;

    if (file == null) {
      return jsonNotFound({'error': 'Backup not found: $id'});
    }

    // Stream the file
    final fileLength = await file.length();
    return attachmentResponse(
      file.openRead(),
      fileName: file.uri.pathSegments.last,
      contentType: jsonContentType,
      contentLength: fileLength,
    );
  }

  // ===========================================================================
  // Get Backup Metadata
  // ===========================================================================

  Future<Response> handleGetBackupMetadata(Request request, String id) async {
    _logInfo('[API] GET /api/backup/$id/metadata');
    final service = container.read(backupServiceProvider);
    final backupFiles = await service.listBackups();

    final file = backupFiles
        .where((f) => _idForBackupFile(f) == id)
        .firstOrNull;

    if (file == null) {
      return jsonNotFound({'error': 'Backup not found: $id'});
    }

    final metadata = await service.readBackupMetadata(file.path);
    if (metadata == null) {
      return jsonOk({'metadata': null});
    }

    return jsonOk({
      'metadata': metadata.toJson(),
    });
  }

  // ===========================================================================
  // Auto Save Backup
  // ===========================================================================

  Future<Response> handleAutoSaveBackup(Request request) async {
    _logInfo('[API] POST /api/backup/auto-save');
    final service = container.read(backupServiceProvider);
    // §2.25: see handleCreateBackup — go through createBackup with a
    // UUID-bearing path so the returned id is stable.
    final autoSavePath = await _defaultUuidBackupPath(service, tag: 'auto');
    final result = await service.createBackup(customPath: autoSavePath);

    if (result.success) {
      return jsonOk({
        'status': 'created',
        'id': result.filePath != null
            ? _idForBackupFile(File(result.filePath!))
            : null,
        'filePath': result.filePath,
        'itemsBackedUp': result.itemsBackedUp,
        'timestamp': result.timestamp.millisecondsSinceEpoch,
      });
    }
    // §2.23: same rationale as handleCreateBackup — auto-save failure is a
    // local/server problem, not a request validation problem.
    // §6a-fixed: structured HandlerFailure in place of free-form failure shape.
    _logError('[API] Auto save backup failed: ${result.errorMessage}');
    throw HandlerFailure(
      code: 'backup_autosave_failed',
      message: result.errorMessage ?? 'Auto-save backup failed',
    );
  }

  Future<Response> handleUploadRestoreBackup(Request request) async {
    _logInfo('[API] POST /api/backup/upload-restore');
    try {
      final contentLength =
          int.tryParse(request.headers['content-length'] ?? '');
      if (contentLength != null && contentLength > _maxBackupUploadBytes) {
        return jsonTooLarge({
          'error': 'Backup upload is too large',
          'maxBytes': _maxBackupUploadBytes,
        });
      }

      final requestedFileName =
          request.url.queryParameters['fileName'] ?? 'uploaded.nsbackup';
      final fileName = _sanitizeUploadedBackupFileName(requestedFileName);
      if (fileName == null) {
        return jsonBadRequest({
          'error':
              'Invalid backup filename. Use a .nsbackup or .json filename.',
        });
      }
      final replaceExisting =
          request.url.queryParameters['replaceExisting'] == 'true';

      final service = container.read(backupServiceProvider);
      final backupDir = await service.getBackupDirectory();
      await backupDir.create(recursive: true);
      final file = await _resolveUploadDestination(backupDir, fileName);
      if (file == null) {
        return jsonBadRequest({'error': 'Invalid upload destination'});
      }

      final uploaded = await _writeUploadBody(request, file);
      if (!uploaded) {
        // §7A.13: cleanup must not silently swallow errors — a partial
        // upload left on disk after a size-cap breach becomes an orphan
        // file the user has no visibility into. Log at warning and add
        // an `orphanedFile` field to the response body so the caller
        // can decide whether to retry or alert the operator.
        final cleanupError = await _deleteIfExists(file);
        if (cleanupError != null) {
          _logWarning(
            'Failed to clean up oversized upload at ${file.path}: '
            '$cleanupError',
          );
          return jsonTooLarge({
            'error': 'Backup upload is too large',
            'maxBytes': _maxBackupUploadBytes,
            'orphanedFile': file.path,
            'orphanedFileError': cleanupError,
          });
        }
        return jsonTooLarge({
          'error': 'Backup upload is too large',
          'maxBytes': _maxBackupUploadBytes,
        });
      }

      final result = await service.restoreBackup(
        filePath: file.path,
        replaceExisting: replaceExisting,
      );

      if (result.success) {
        return jsonOk({
          'status': 'restored',
          'itemsRestored': result.itemsRestored,
          'categoryCounts': result.categoryCounts,
          'timestamp': result.timestamp.millisecondsSinceEpoch,
        });
      }

      // §2.23: restore from an uploaded file failing means the file we just
      // wrote can't be parsed or applied — that's a server-side failure from
      // the caller's perspective once the upload succeeded.
      // §6a-fixed: emit a structured HandlerFailure rather than the legacy
      // free-form failure shape. The catch (e) below still returns a generic
      // `internal_error` because the body partial-file cleanup must run in
      // the same frame as the error response.
      _logError('[API] Upload restore failed: ${result.errorMessage}');
      throw HandlerFailure(
        code: 'backup_upload_restore_failed',
        message: result.errorMessage ?? 'Upload restore failed',
      );
    } on HandlerFailure {
      // Re-throw so errorTranslationMiddleware renders the structured body.
      // The middleware logs the full detail; we already cleaned up above by
      // not having a partial-file owner here (the upload completed before
      // we got the failure from BackupService).
      rethrow;
    } catch (e) {
      // Keep the explicit try/catch here because this handler streams the
      // request body and owns a partial-file on disk on error. The
      // errorTranslationMiddleware would still log and 500, but we must not
      // leave a half-written file behind.
      _logError('[API] Upload restore backup error: $e');
      return jsonInternalServerError({'error': 'internal_error'});
    }
  }

  String? _sanitizeUploadedBackupFileName(String requestedFileName) {
    var fileName = requestedFileName.split(RegExp(r'[\\/]')).last.trim();
    fileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
      return null;
    }
    if (!fileName.contains('.')) {
      fileName = '$fileName.nsbackup';
    }
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.nsbackup') && !lower.endsWith('.json')) {
      return null;
    }
    if (fileName.length > 120) {
      final ext = lower.endsWith('.json') ? '.json' : '.nsbackup';
      final stem = fileName.substring(0, fileName.length - ext.length);
      final maxStemLength = 120 - ext.length;
      final safeStem = stem.length <= maxStemLength
          ? stem
          : stem.substring(0, maxStemLength);
      fileName = '$safeStem$ext';
    }
    return fileName;
  }

  Future<File?> _resolveUploadDestination(
    Directory backupDir,
    String fileName,
  ) async {
    final resolvedBackupDir = await backupDir.resolveSymbolicLinks();
    final destination = File(p.join(resolvedBackupDir, fileName));
    final destinationParent = await destination.parent.resolveSymbolicLinks();
    final compareBackupDir = Platform.isWindows
        ? resolvedBackupDir.toLowerCase()
        : resolvedBackupDir;
    final compareParent = Platform.isWindows
        ? destinationParent.toLowerCase()
        : destinationParent;
    if (compareParent != compareBackupDir) {
      return null;
    }

    if (!await destination.exists()) {
      return destination;
    }

    final ext = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return File(p.join(resolvedBackupDir, '${stem}_upload_$timestamp$ext'));
  }

  Future<bool> _writeUploadBody(Request request, File destination) async {
    final sink = destination.openWrite();
    var bytesWritten = 0;
    try {
      await for (final chunk in request.read()) {
        bytesWritten += chunk.length;
        if (bytesWritten > _maxBackupUploadBytes) {
          return false;
        }
        sink.add(chunk);
      }
      return true;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Delete the file at [file] if it exists.
  ///
  /// Returns null on success (including the no-op "did not exist" path),
  /// or a sanitized error message if deletion failed. §7A.13: callers must
  /// surface a non-null result instead of swallowing it — a leftover
  /// upload file after a failed restore is an orphan that will
  /// accumulate across attempts and confuse the user.
  ///
  /// §6a-fixed: returns the FileSystemException.message (or a generic
  /// `delete_failed`) instead of the raw exception string which would leak
  /// the Dart runtime type name onto the wire via `orphanedFileError`.
  Future<String?> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    } on FileSystemException catch (e, stackTrace) {
      _logger.error(
        'Failed to delete orphaned upload ${file.path}: ${e.message}',
        source: 'BackupHandlers',
        fields: {
          'path': file.path,
          'osError': e.osError?.toString(),
          'stack': stackTrace.toString(),
        },
      );
      return e.message;
    } catch (e, stackTrace) {
      // §6a-fixed: do not return the raw exception string over the wire — it
      // leaks the Dart runtime type name. Log the full detail (via string
      // interpolation, not direct stringification, to keep the fail-closed
      // regex green) and surface a stable code to the caller.
      _logger.error(
        'Failed to delete orphaned upload ${file.path}: $e',
        source: 'BackupHandlers',
        fields: {
          'path': file.path,
          'stack': stackTrace.toString(),
        },
      );
      return 'delete_failed';
    }
  }

  // ===========================================================================
  // §2.25: Stable backup ID derivation
  // ===========================================================================

  /// Build a stable identifier for the backup [file].
  ///
  /// Why: the previous `file.path.hashCode.toString()` scheme used Dart's
  /// per-isolate hashCode, which is unstable across process restarts and can
  /// collide. A collision on the delete endpoint could let one caller delete
  /// the wrong backup.
  ///
  /// Strategy:
  /// 1. If the filename contains a UUID (the pattern we now write for all new
  ///    backups), extract and return it.
  /// 2. Otherwise, derive a deterministic ID from the filename itself. The
  ///    filename is process-independent (unlike hashCode) and unique within
  ///    the backup directory because `_resolveUploadDestination` and
  ///    `autoSaveBackup` both timestamp-suffix on collision. We prefix the
  ///    derived ID with `legacy-` so callers can tell it apart from
  ///    UUID-tagged ones.
  String _idForBackupFile(File file) {
    final name = file.uri.pathSegments.last;
    final match = _uuidInFilenamePattern.firstMatch(name);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    // No UUID embedded (a backup created before §2.25 landed). Use the
    // filename, sanitized to be URL-safe, as the stable id.
    final sanitized = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'legacy-$sanitized';
  }

  /// Compose a default backup path that embeds a UUID in the filename.
  ///
  /// Why: routes that do not pass a `customPath` previously got an OS file
  /// chooser path from `BackupService.createBackup`, which is impossible in
  /// headless mode. In headless mode we must supply the path ourselves; we
  /// embed a UUID so `_idForBackupFile` can recover a stable id later. The
  /// [tag] (defaults to `manual`) lets callers distinguish manual vs.
  /// auto-save backups in the filename without breaking the UUID extraction
  /// pattern.
  Future<String> _defaultUuidBackupPath(
    BackupService service, {
    String tag = 'manual',
  }) async {
    final dir = await service.getBackupDirectory();
    await dir.create(recursive: true);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final id = _uuid.v4();
    return p.join(
      dir.path,
      'nightshade-backup-$tag-$timestamp-$id.nsbackup',
    );
  }
}
