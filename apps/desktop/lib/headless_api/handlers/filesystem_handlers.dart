import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

class FileSystemHandlers {
  final ProviderContainer container;

  FileSystemHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FileSystemHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'FileSystemHandlers');

  Future<Response> handleBrowseDirectories(Request request) async {
    final requestedPath = request.url.queryParameters['path'];
    _logInfo('[API] GET /api/files/browse?path=${requestedPath ?? ""}');

    try {
      if (requestedPath == null || requestedPath.trim().isEmpty) {
        final roots = await _listRoots();
        return jsonOk({
          'currentPath': null,
          'parentPath': null,
          'directories': roots,
        });
      }

      final directory = Directory(requestedPath);
      final exists = await directory.exists();
      if (!exists) {
        return jsonNotFound({'error': 'Directory not found'});
      }

      final entries = await directory
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
      entries.sort((a, b) => p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase()));

      final normalizedPath = p.normalize(directory.absolute.path);
      final parentPath = p.dirname(normalizedPath);
      final isRoot = parentPath == normalizedPath;

      return jsonOk({
        'currentPath': normalizedPath,
        'parentPath': isRoot ? null : parentPath,
        'directories': entries
            .map((entry) => {
                  'name': p.basename(entry.path),
                  'path': p.normalize(entry.absolute.path),
                })
            .toList(),
      });
    } catch (e) {
      _logError('[API] Browse directories error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleValidateDirectory(Request request) async {
    _logInfo('[API] POST /api/files/validate');

    try {
      final payload = jsonDecode(await request.readAsString()) as Map;
      final path = payload['path'] as String? ?? '';
      final mustExist = payload['mustExist'] as bool? ?? false;
      final mustBeWritable = payload['mustBeWritable'] as bool? ?? false;

      if (path.trim().isEmpty) {
        return jsonOk({
          'valid': false,
          'exists': false,
          'writable': false,
          'error': 'Path is required',
        });
      }

      final directory = Directory(path);
      final exists = await directory.exists();
      final writable =
          exists && (!mustBeWritable || await _isWritable(directory));
      final valid = (!mustExist || exists) && (!mustBeWritable || writable);

      return jsonOk({
        'valid': valid,
        'exists': exists,
        'writable': writable,
        'normalizedPath': p.normalize(directory.absolute.path),
      });
    } catch (e) {
      _logError('[API] Validate directory error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<List<Map<String, dynamic>>> _listRoots() async {
    if (!Platform.isWindows) {
      final roots = <Map<String, dynamic>>[
        {'name': '/', 'path': '/'}
      ];
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty && home != '/') {
        roots.add({'name': 'Home', 'path': home});
      }
      return roots;
    }

    final roots = <Map<String, dynamic>>[];
    for (var code = 67; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      final drive = '$letter:\\';
      if (await Directory(drive).exists()) {
        roots.add({'name': drive, 'path': drive});
      }
    }
    return roots;
  }

  Future<bool> _isWritable(Directory directory) async {
    File? tempFile;
    try {
      tempFile = await File(
        p.join(
          directory.path,
          '.nightshade_write_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (_) {
          // Best effort cleanup only.
        }
      }
    }
  }
}
