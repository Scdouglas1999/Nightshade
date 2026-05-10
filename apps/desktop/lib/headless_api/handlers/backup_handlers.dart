import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for backup and restore operations
class BackupHandlers {
  static const int _maxBackupUploadBytes = 256 * 1024 * 1024;

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
    try {
      final service = container.read(backupServiceProvider);
      final backupFiles = await service.listBackups();

      final backups = <Map<String, dynamic>>[];
      for (final file in backupFiles) {
        final metadata = await service.readBackupMetadata(file.path);
        final stat = await file.stat();

        backups.add({
          'id': file.path.hashCode.toString(),
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

      return jsonOk({"backups": backups});
    } catch (e) {
      _logError('[API] List backups error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Create Backup
  // ===========================================================================

  Future<Response> handleCreateBackup(Request request) async {
    _logInfo('[API] POST /api/backup/create');
    try {
      final payload = jsonDecode(await request.readAsString());
      final customPath = payload['customPath'] as String?;
      final autoSave = payload['autoSave'] as bool? ?? false;

      final service = container.read(backupServiceProvider);

      BackupResult result;
      if (autoSave) {
        result = await service.autoSaveBackup();
      } else {
        result = await service.createBackup(customPath: customPath);
      }

      if (result.success) {
        return jsonOk({
          "status": "created",
          "filePath": result.filePath,
          "itemsBackedUp": result.itemsBackedUp,
          "timestamp": result.timestamp.millisecondsSinceEpoch,
        });
      } else {
        return jsonOk({
          "status": "failed",
          "error": result.errorMessage,
        });
      }
    } catch (e) {
      _logError('[API] Create backup error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Restore Backup
  // ===========================================================================

  Future<Response> handleRestoreBackup(Request request) async {
    _logInfo('[API] POST /api/backup/restore');
    try {
      final payload = jsonDecode(await request.readAsString());
      final filePath = payload['filePath'] as String;
      final replaceExisting = payload['replaceExisting'] as bool? ?? false;

      final service = container.read(backupServiceProvider);
      final result = await service.restoreBackup(
        filePath: filePath,
        replaceExisting: replaceExisting,
      );

      if (result.success) {
        return jsonOk({
          "status": "restored",
          "itemsRestored": result.itemsRestored,
          "categoryCounts": result.categoryCounts,
          "timestamp": result.timestamp.millisecondsSinceEpoch,
        });
      } else {
        return jsonOk({
          "status": "failed",
          "error": result.errorMessage,
        });
      }
    } catch (e) {
      _logError('[API] Restore backup error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Delete Backup
  // ===========================================================================

  Future<Response> handleDeleteBackup(Request request, String id) async {
    _logInfo('[API] DELETE /api/backup/$id');
    try {
      final service = container.read(backupServiceProvider);
      final backupFiles = await service.listBackups();

      // Find backup by ID (hash of path)
      final file = backupFiles
          .where((f) => f.path.hashCode.toString() == id)
          .firstOrNull;

      if (file == null) {
        return jsonNotFound({"error": "Backup not found: $id"});
      }

      await file.delete();

      return jsonOk({"status": "deleted"});
    } catch (e) {
      _logError('[API] Delete backup error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Download Backup
  // ===========================================================================

  Future<Response> handleDownloadBackup(Request request, String id) async {
    _logInfo('[API] GET /api/backup/$id/download');
    try {
      final service = container.read(backupServiceProvider);
      final backupFiles = await service.listBackups();

      // Find backup by ID (hash of path)
      final file = backupFiles
          .where((f) => f.path.hashCode.toString() == id)
          .firstOrNull;

      if (file == null) {
        return jsonNotFound({"error": "Backup not found: $id"});
      }

      // Stream the file
      final fileLength = await file.length();
      return attachmentResponse(
        file.openRead(),
        fileName: file.uri.pathSegments.last,
        contentType: jsonContentType,
        contentLength: fileLength,
      );
    } catch (e) {
      _logError('[API] Download backup error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Get Backup Metadata
  // ===========================================================================

  Future<Response> handleGetBackupMetadata(Request request, String id) async {
    _logInfo('[API] GET /api/backup/$id/metadata');
    try {
      final service = container.read(backupServiceProvider);
      final backupFiles = await service.listBackups();

      // Find backup by ID (hash of path)
      final file = backupFiles
          .where((f) => f.path.hashCode.toString() == id)
          .firstOrNull;

      if (file == null) {
        return jsonNotFound({"error": "Backup not found: $id"});
      }

      final metadata = await service.readBackupMetadata(file.path);
      if (metadata == null) {
        return jsonOk({"metadata": null});
      }

      return jsonOk({
        "metadata": metadata.toJson(),
      });
    } catch (e) {
      _logError('[API] Get backup metadata error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Auto Save Backup
  // ===========================================================================

  Future<Response> handleAutoSaveBackup(Request request) async {
    _logInfo('[API] POST /api/backup/auto-save');
    try {
      final service = container.read(backupServiceProvider);
      final result = await service.autoSaveBackup();

      if (result.success) {
        return jsonOk({
          "status": "created",
          "filePath": result.filePath,
          "itemsBackedUp": result.itemsBackedUp,
          "timestamp": result.timestamp.millisecondsSinceEpoch,
        });
      } else {
        return jsonOk({
          "status": "failed",
          "error": result.errorMessage,
        });
      }
    } catch (e) {
      _logError('[API] Auto save backup error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
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

      return jsonOk({
        'status': 'failed',
        'error': result.errorMessage,
      });
    } catch (e) {
      _logError('[API] Upload restore backup error: $e');
      return jsonInternalServerError({'error': e.toString()});
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
  /// or the stringified error if deletion failed. §7A.13: callers must
  /// surface a non-null result instead of swallowing it — a leftover
  /// upload file after a failed restore is an orphan that will
  /// accumulate across attempts and confuse the user.
  Future<String?> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
