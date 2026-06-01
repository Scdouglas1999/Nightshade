/// Static-file HTTP handlers for the headless API's bundled SPAs.
///
/// Owns the two top-level static-file surfaces shipped inside the
/// Nightshade executable so a headless deployment (Pi / embedded host /
/// remote ops) can serve them without an external web server:
///   * `/dashboard` — the desktop control dashboard. Sourced from
///     `web_dashboard/`.
///   * `/run-watch` — the mobile-first run-watch SPA + PWA. Sourced
///     from `web_run_watch/`.
///
/// Both surfaces share the same resolver heuristic (next to the
/// executable, inside `data/flutter_assets/`, walking up the source
/// tree, and finally relative to CWD) so a developer build and a
/// shipped installer behave the same way. Directory traversal is
/// blocked via [_normalizeRelative] + a post-resolve symlink check.
///
/// The bundled run-watch service worker (`sw.js`) gets a longer
/// `Service-Worker-Allowed: /run-watch/` response header so it can
/// claim the parent scope cleanly during registration; every other
/// asset is served with `cache-control: no-cache` so SPA updates ship
/// instantly without per-asset cache busting.
library;

import 'dart:io';

import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Maps file extensions to the response `content-type` value. Anything
/// not in the table is served as `application/octet-stream` so a
/// browser does not sniff content out of a binary blob.
const _mimeTypes = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
};

/// Default security headers shared by both static surfaces. The CSP
/// allows same-origin script/style + arbitrary connect targets because
/// the SPAs need to reach localhost/LAN backends; `object-src 'none'`
/// and `frame-ancestors 'none'` shut the typical XSS escalation paths.
const _staticFileSecurityHeaders = {
  'content-security-policy': "default-src 'self'; script-src 'self'; "
      "style-src 'self'; img-src 'self' data: blob:; connect-src 'self' "
      "http://*:* https://*:* ws://*:* wss://*:*; object-src 'none'; "
      "base-uri 'none'; frame-ancestors 'none'",
  'x-frame-options': 'DENY',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
};

/// Resolve the MIME type for [filePath] by extension lookup. Defaults to
/// `application/octet-stream` for unknown extensions so a misnamed file
/// isn't served as a sniff-able executable.
String _mimeFor(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return _mimeTypes[ext] ?? 'application/octet-stream';
}

/// HTTP handlers for the bundled `/dashboard` and `/run-watch` SPAs.
///
/// The class is stateless — every call re-resolves the SPA directory so
/// a developer can rebuild the SPA next to a running server without
/// restarting. Production deployments hit the "next to the executable"
/// branch on the first lookup so the cost is one stat() per request.
class StaticFileHandlers {
  final LoggingService logger;

  StaticFileHandlers({required this.logger});

  void _logWarning(String message) =>
      logger.warning(message, source: 'StaticFileHandlers');

  /// Locate the `web_dashboard/` source directory shipped alongside the
  /// executable (release) or somewhere up the source tree (development).
  /// Returns null when the directory cannot be found so callers can
  /// render a clean 404 instead of crashing.
  Directory? findDashboardDir() => _findStaticDir('web_dashboard');

  /// Locate the `web_run_watch/` source directory. Same heuristic as
  /// [findDashboardDir]; kept separate so each SPA can be relocated
  /// independently for ad-hoc deployments.
  Directory? findRunWatchDir() => _findStaticDir('web_run_watch');

  /// Whether the dashboard SPA is available. Used by `/api/info` and
  /// `/api/self-test` to advertise the bundled UI option.
  bool get dashboardAvailable => findDashboardDir() != null;

  /// `GET /dashboard` / `GET /dashboard/` — serve `index.html`.
  Future<Response> handleDashboardIndex(Request request) async {
    return _serveFile(findDashboardDir(), 'index.html', surface: 'dashboard');
  }

  /// `GET /dashboard/<path>` — serve any nested asset, blocking
  /// directory traversal at the normalisation step.
  Future<Response> handleDashboardFile(Request request, String path) async {
    final normalized = _normalizeRelative(path);
    if (normalized == null) {
      return jsonForbidden({'error': 'Invalid path'});
    }
    return _serveFile(findDashboardDir(), normalized, surface: 'dashboard');
  }

  /// `GET /run-watch` / `GET /run-watch/` — serve `index.html` for the
  /// phone SPA bootstrap.
  Future<Response> handleRunWatchIndex(Request request) async {
    return _serveFile(findRunWatchDir(), 'index.html', surface: 'run-watch');
  }

  /// `GET /run-watch/<path>` — serve any nested run-watch asset. The
  /// service-worker file is given a stricter cache policy + the
  /// `Service-Worker-Allowed` header so it can claim the parent scope.
  Future<Response> handleRunWatchFile(Request request, String path) async {
    final normalized = _normalizeRelative(path);
    if (normalized == null) {
      return jsonForbidden({'error': 'Invalid path'});
    }
    return _serveFile(findRunWatchDir(), normalized, surface: 'run-watch');
  }

  /// Common file-serving path used by both static surfaces. Walks
  /// (a) the SPA root resolver, (b) a file-exists check, (c) a
  /// post-symlink-resolution containment check, and (d) the appropriate
  /// cache/security-header bundle.
  Future<Response> _serveFile(
    Directory? rootDir,
    String relativePath, {
    required String surface,
  }) async {
    if (rootDir == null) {
      _logWarning('[$surface] static directory not found');
      return jsonNotFound({
        'error': '${surface == 'dashboard' ? 'Dashboard' : 'Run-watch SPA'} '
            'not found',
        'message':
            'The ${surface == 'dashboard' ? 'web_dashboard' : 'web_run_watch'} '
                'directory could not be located. Ensure it is deployed '
                'alongside the application.',
      });
    }

    final filePath = p.join(rootDir.path, relativePath);
    final file = File(filePath);

    if (!await file.exists()) {
      return jsonNotFound({'error': 'File not found: $relativePath'});
    }

    // Ensure the resolved path is still inside the SPA root after any
    // symlink traversal — otherwise a symlink inside the bundle could
    // be used to escape the sandbox.
    final resolvedPath = await file.resolveSymbolicLinks();
    final resolvedRoot = await rootDir.resolveSymbolicLinks();
    final rootWithSep = resolvedRoot.endsWith(Platform.pathSeparator)
        ? resolvedRoot
        : resolvedRoot + Platform.pathSeparator;
    if (!resolvedPath.startsWith(rootWithSep) && resolvedPath != resolvedRoot) {
      return jsonForbidden({'error': 'Access denied'});
    }

    final bytes = await file.readAsBytes();
    final isServiceWorker = surface == 'run-watch' && relativePath == 'sw.js';
    // Why a stricter policy for the service worker only: the bootstrap
    // script must always reload to honour updates. Every other asset
    // can be cached aggressively by the browser within a single
    // session.
    final cacheControl =
        isServiceWorker ? 'no-cache, no-store, must-revalidate' : 'no-cache';

    return contentResponse(
      bytes,
      contentType: _mimeFor(filePath),
      headers: {
        'cache-control': cacheControl,
        if (isServiceWorker) 'service-worker-allowed': '/run-watch/',
        ..._staticFileSecurityHeaders,
      },
    );
  }

  /// Resolve a relative path the client supplied as a path parameter.
  /// Returns null when the path attempts directory traversal (a
  /// leading `/` or a `..` segment); callers should respond with 403.
  String? _normalizeRelative(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    if (normalized.contains('..') || normalized.startsWith('/')) {
      return null;
    }
    return normalized;
  }

  /// Resolve a bundled static directory by name, checking the four
  /// locations the desktop installer + developer build trees can place
  /// it: next to the executable inside `data/flutter_assets/`, next to
  /// the executable directly, walking up the source tree, and finally
  /// relative to the current working directory.
  Directory? _findStaticDir(String name) {
    final exeDir = p.dirname(Platform.resolvedExecutable);

    // 1. Next to the executable inside the Flutter assets bundle.
    final releaseAssets =
        Directory(p.join(exeDir, 'data', 'flutter_assets', name));
    if (releaseAssets.existsSync()) return releaseAssets;

    // 2. Next to the executable directly (some installer layouts).
    final sameDir = Directory(p.join(exeDir, name));
    if (sameDir.existsSync()) return sameDir;

    // 3. Walk up the source tree (development - the exe lives somewhere
    //    under build/<platform>/.../).
    var current = exeDir;
    for (var i = 0; i < 10; i++) {
      final candidate = Directory(p.join(current, name));
      if (candidate.existsSync()) return candidate;
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }

    // 4. Relative to the current working directory.
    final cwd = Directory(p.join(Directory.current.path, name));
    if (cwd.existsSync()) return cwd;

    return null;
  }
}
