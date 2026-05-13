import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

class FileSystemHandlers {
  final ProviderContainer container;

  /// Cached set of canonicalized root paths the caller may browse under.
  /// Recomputed on each request because the user can change save-path /
  /// backup-dir at runtime; the per-request cost is one stat call per root.
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
      // Compute the allow-listed roots once per request. Roots that don't
      // exist on disk are dropped (we can't canonicalize a non-existent path).
      final roots = await _resolveBrowseRoots();

      if (requestedPath == null || requestedPath.trim().isEmpty) {
        // Top-level listing: return only the allow-listed roots so the caller
        // cannot enumerate the full filesystem via a single empty-path request.
        return jsonOk({
          'currentPath': null,
          'parentPath': null,
          'directories': roots
              .map((r) => {
                    'name': r.label,
                    'path': r.canonicalPath,
                  })
              .toList(),
        });
      }

      final directory = Directory(requestedPath);
      final exists = await directory.exists();
      if (!exists) {
        return jsonNotFound({'error': 'Directory not found'});
      }

      // Canonicalize both the requested path and the roots to defeat path
      // traversal via "..", symlinks, or case-insensitive collisions on
      // Windows. Reject if the requested path doesn't sit under any allow-
      // listed root.
      final canonicalRequested = await _canonicalize(directory.path);
      final allowed = _isPathUnderAnyRoot(canonicalRequested, roots);
      if (!allowed) {
        _logError(
          '[API] Browse rejected: $canonicalRequested is not under any '
          'allow-listed root (${roots.map((r) => r.canonicalPath).join(", ")})',
        );
        return jsonForbidden({
          'error': 'path_not_allowed',
          'message':
              'The requested path is not under an allow-listed browse root',
          'allowedRoots': roots
              .map((r) => {
                    'name': r.label,
                    'path': r.canonicalPath,
                  })
              .toList(),
        });
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

      // Use the canonicalized path so the client sees the same shape we
      // verified against the allow-list, not whatever they passed in.
      final normalizedPath = canonicalRequested;
      final parentCanonical = p.dirname(normalizedPath);
      // Parent only exposed if it's also under an allow-listed root — prevents
      // a "browse up out of the allow-list" hop after reaching an allowed dir.
      final parentAllowed =
          parentCanonical != normalizedPath &&
              _isPathUnderAnyRoot(parentCanonical, roots);
      // Listed children must each be canonicalized + checked. A symlink in an
      // allowed root that targets /etc must not let the caller hop out.
      final children = <Map<String, dynamic>>[];
      for (final entry in entries) {
        final childCanonical = await _canonicalize(entry.path);
        if (!_isPathUnderAnyRoot(childCanonical, roots)) {
          continue;
        }
        children.add({
          'name': p.basename(entry.path),
          'path': childCanonical,
        });
      }

      return jsonOk({
        'currentPath': normalizedPath,
        'parentPath': parentAllowed ? parentCanonical : null,
        'directories': children,
      });
    } catch (e) {
      _logError('[API] Browse directories error: $e');
      return jsonInternalServerError({'error': 'internal_error'});
    }
  }

  Future<Response> handleValidateDirectory(Request request) async {
    _logInfo('[API] POST /api/files/validate');

    final payload = await readJsonObject(request);
    final path = optionalString(payload, 'path', allowEmpty: true) ?? '';
    final mustExist = optionalBool(payload, 'mustExist') ?? false;
    final mustBeWritable = optionalBool(payload, 'mustBeWritable') ?? false;

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
  }

  /// Allow-listed roots the caller may browse under.
  ///
  /// Why: §2.24 — without this restriction the admin-scoped endpoint accepts
  /// an arbitrary `?path=` and lists the whole readable filesystem, which is
  /// far more than the dashboard needs (it only ever points the user at the
  /// image save dir, sequences dir, logs dir, and backups dir). The roots are
  /// computed from the same settings/services the GUI uses, so the headless
  /// surface tracks user configuration. Any root that fails to resolve (e.g.
  /// the user has never set imageOutputPath) is dropped silently; we still
  /// always include the user's Documents dir and the platform-default backup
  /// dir so there is always at least one navigable root.
  Future<List<_BrowseRoot>> _resolveBrowseRoots() async {
    final roots = <_BrowseRoot>[];
    final seen = <String>{};

    Future<void> add(String label, String? rawPath) async {
      if (rawPath == null || rawPath.trim().isEmpty) return;
      final dir = Directory(rawPath);
      if (!await dir.exists()) return;
      final canonical = await _canonicalize(rawPath);
      // Why: Windows is case-insensitive; lower-case the dedupe key so
      // "C:\Users\X" and "c:\users\x" don't both appear.
      final key = Platform.isWindows ? canonical.toLowerCase() : canonical;
      if (seen.add(key)) {
        roots.add(_BrowseRoot(label: label, canonicalPath: canonical));
      }
    }

    // 1. User Documents — always available, anchors a sensible default.
    try {
      final docs = await getApplicationDocumentsDirectory();
      await add('Documents', docs.path);
    } on Object catch (e, stackTrace) {
      // Why: getApplicationDocumentsDirectory can fail under unusual
      // platform conditions (e.g. sandboxed CI without HOME); we keep the
      // method best-effort because other roots may still resolve. Log the
      // detail so operators can diagnose the no-roots case.
      _logger.warning(
        'getApplicationDocumentsDirectory failed: $e',
        source: 'FileSystemHandlers',
        fields: {'stack': stackTrace.toString()},
      );
    }

    // 2. Default backup directory used by BackupService.
    try {
      final backupService = container.read(backupServiceProvider);
      final backupDir = await backupService.getBackupDirectory();
      await add('Backups', backupDir.path);
    } on Object catch (e, stackTrace) {
      // Why: BackupService not yet initialised in this isolate — skip; the
      // Documents root covers the parent dir. Logged at warning so operators
      // can spot misconfiguration if the backups root is missing.
      _logger.warning(
        'BackupService.getBackupDirectory failed: $e',
        source: 'FileSystemHandlers',
        fields: {'stack': stackTrace.toString()},
      );
    }

    // 3. Configured image output directory (the primary "where new captures
    //    land" location, set in Settings → Output).
    final settings = container.read(appSettingsProvider).valueOrNull;
    await add('Image Output', settings?.imageOutputPath);
    await add('Sequences', settings?.sequencesPath);
    await add('Logs', settings?.logsPath);

    return roots;
  }

  /// Returns true iff [path] is the same as or a descendant of any root.
  ///
  /// Comparison is case-insensitive on Windows. Both inputs MUST already be
  /// canonical (resolved + normalized) — that is the caller's job.
  bool _isPathUnderAnyRoot(String canonicalPath, List<_BrowseRoot> roots) {
    for (final root in roots) {
      final rootPath = root.canonicalPath;
      final a = Platform.isWindows ? canonicalPath.toLowerCase() : canonicalPath;
      final b = Platform.isWindows ? rootPath.toLowerCase() : rootPath;
      if (a == b) return true;
      // Append a separator before the prefix check so "/foo/bar" doesn't
      // erroneously match a root of "/foo/ba".
      final bWithSep = b.endsWith(p.separator) ? b : '$b${p.separator}';
      if (a.startsWith(bWithSep)) return true;
    }
    return false;
  }

  /// Resolve a path through symlinks and `..` segments. Falls back to a
  /// normalized absolute path when the path doesn't exist on disk yet
  /// (Directory.resolveSymbolicLinks requires existence).
  Future<String> _canonicalize(String path) async {
    final dir = Directory(path);
    try {
      return await dir.resolveSymbolicLinks();
    } on FileSystemException {
      // Why: best-effort fallback — if the path doesn't exist or symlinks
      // can't be resolved, fall back to absolute-and-normalized. The earlier
      // existence check in the caller catches non-existent requested paths;
      // this fallback exists mainly for the roots branch, where a configured
      // setting might point at a not-yet-created directory. We deliberately
      // do not log here because the configured-but-missing case is a normal
      // user state, not an error.
      return p.normalize(dir.absolute.path);
    }
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
    } on FileSystemException {
      // Why: failure here means "not writable" — that's the whole point of
      // the probe. We surface a structured `writable: false` to the caller.
      return false;
    } finally {
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Why: best-effort cleanup of the probe file. Failure to delete a
          // temp file doesn't change the writable signal we just computed,
          // so we deliberately swallow it.
        }
      }
    }
  }
}

/// Single entry in the browse allow-list.
class _BrowseRoot {
  final String label;
  final String canonicalPath;

  const _BrowseRoot({required this.label, required this.canonicalPath});
}
