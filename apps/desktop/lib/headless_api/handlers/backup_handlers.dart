import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for backup and restore operations
class BackupHandlers {
  final ProviderContainer container;
  BackupHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'BackupHandlers');
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

      return Response.ok(
        jsonEncode({"backups": backups}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] List backups error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.ok(
          jsonEncode({
            "status": "created",
            "filePath": result.filePath,
            "itemsBackedUp": result.itemsBackedUp,
            "timestamp": result.timestamp.millisecondsSinceEpoch,
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        return Response.ok(
          jsonEncode({
            "status": "failed",
            "error": result.errorMessage,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    } catch (e) {
      _logError('[API] Create backup error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.ok(
          jsonEncode({
            "status": "restored",
            "itemsRestored": result.itemsRestored,
            "categoryCounts": result.categoryCounts,
            "timestamp": result.timestamp.millisecondsSinceEpoch,
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        return Response.ok(
          jsonEncode({
            "status": "failed",
            "error": result.errorMessage,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    } catch (e) {
      _logError('[API] Restore backup error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.notFound(
          jsonEncode({"error": "Backup not found: $id"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await file.delete();

      return Response.ok(
        jsonEncode({"status": "deleted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Delete backup error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.notFound(
          jsonEncode({"error": "Backup not found: $id"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Stream the file
      final fileLength = await file.length();
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': 'application/json',
          'content-length': fileLength.toString(),
          'content-disposition':
              'attachment; filename="${file.uri.pathSegments.last}"',
        },
      );
    } catch (e) {
      _logError('[API] Download backup error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.notFound(
          jsonEncode({"error": "Backup not found: $id"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final metadata = await service.readBackupMetadata(file.path);
      if (metadata == null) {
        return Response.ok(
          jsonEncode({"metadata": null}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          "metadata": metadata.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get backup metadata error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.ok(
          jsonEncode({
            "status": "created",
            "filePath": result.filePath,
            "itemsBackedUp": result.itemsBackedUp,
            "timestamp": result.timestamp.millisecondsSinceEpoch,
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        return Response.ok(
          jsonEncode({
            "status": "failed",
            "error": result.errorMessage,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    } catch (e) {
      _logError('[API] Auto save backup error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
