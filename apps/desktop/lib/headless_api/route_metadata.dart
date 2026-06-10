import 'dart:io';

const int oneMiB = 1024 * 1024;
const int defaultMaxRequestBodyBytes = oneMiB;
const int imageProcessingMaxRequestBodyBytes = 64 * oneMiB;
const int backupUploadMaxRequestBodyBytes = 256 * oneMiB;
// P1-12 — catalog archives are capped at 1 GiB per audit. HYG is
// ~35 MB decompressed, GLADE+ complete is ~2 GB so the cap rejects the
// full GLADE+ tier (operators must use the standard tier or stage the
// file out-of-band).
const int catalogUploadMaxRequestBodyBytes = 1024 * oneMiB;

const Duration defaultControlRateLimitWindow = Duration(minutes: 1);
const int defaultControlRateLimitMaxRequests = 60;
const int highRiskControlRateLimitMaxRequests = 12;

bool methodCanHaveBody(String method) {
  return method == 'POST' || method == 'PUT' || method == 'PATCH';
}

int requestBodyLimitForPath(String path) {
  if (path == '/api/backup/upload-restore') {
    return backupUploadMaxRequestBodyBytes;
  }

  // P1-10 — calibration dark upload may carry a master dark up to ~200 MB
  // from a full-frame camera. Share the backup-upload cap so a single
  // ceiling governs all multipart-style uploads.
  if (path == '/api/calibration/darks/upload') {
    return backupUploadMaxRequestBodyBytes;
  }

  // P1-12 — catalog upload (air-gap install path).
  if (path == '/api/catalog/upload') {
    return catalogUploadMaxRequestBodyBytes;
  }

  // P2-11 — plugin archives are small (manifests + small code bundles),
  // but a few MB ceiling is reasonable so the operator can ship
  // assets alongside. Share the backup-upload cap.
  if (path == '/api/plugins/upload') {
    return backupUploadMaxRequestBodyBytes;
  }

  if (path == '/api/imaging/stats' ||
      path == '/api/imaging/stretch' ||
      path == '/api/imaging/debayer' ||
      path == '/api/imaging/save-fits') {
    return imageProcessingMaxRequestBodyBytes;
  }

  return defaultMaxRequestBodyBytes;
}

Map<String, dynamic> buildOpenApiSpec({
  required List<String> routes,
  required int port,
}) {
  final paths = <String, Map<String, dynamic>>{};

  for (final route in routes) {
    final parts = route.split(' ');
    if (parts.length != 2) continue;

    final method = parts.first.toUpperCase();
    if (method == 'WS') continue;

    final routePath = parts.last;
    final path = openApiPath(routePath);
    final rateLimit = endpointRateLimitFor(method: method, path: routePath);
    final auditAction = highRiskAuditActionFor(method: method, path: routePath);
    final authScope = requiredAuthScopeNameForEndpoint(
      method: method,
      path: routePath,
    );
    final publicEndpoint = isPublicEndpoint(method: method, path: routePath);
    final responses = <String, Map<String, String>>{
      '200': {'description': 'Success'},
      '400': {'description': 'Bad request'},
      '500': {'description': 'Internal server error'},
      '426': {'description': 'Upgrade required for API version mismatch'},
    };
    final operation = <String, dynamic>{
      'summary': route,
      'tags': [openApiTag(path)],
      'responses': responses,
      'x-auth-required': !publicEndpoint,
      'x-required-scope': authScope,
    };

    if (!publicEndpoint) {
      responses['401'] = {'description': 'Unauthorized'};
      responses['403'] = {'description': 'Forbidden'};
      operation['security'] = [
        {'bearerAuth': <String>[]},
      ];
    }

    if (methodCanHaveBody(method)) {
      responses['413'] = {'description': 'Request body too large'};
      operation['x-max-request-body-bytes'] = requestBodyLimitForPath(
        routePath,
      );
    }

    if (rateLimit != null) {
      responses['429'] = {'description': 'Rate limit exceeded'};
      operation['x-rate-limit'] = {
        'maxRequests': rateLimit.maxRequests,
        'windowSeconds': rateLimit.window.inSeconds,
      };
    }

    if (auditAction != null) {
      operation['x-audit-action'] = auditAction;
    }

    final operations = paths.putIfAbsent(path, () => <String, dynamic>{});
    operations[method.toLowerCase()] = operation;
  }

  return {
    'openapi': '3.0.3',
    'info': {
      'title': 'Nightshade Headless API',
      // P1-1/P1-4 — minor bump for the additive event sequencing
      // (`seq`, `serverInstanceId`, `replay`, `resync_required`) and
      // command/event correlation (`commandId`, `correlatingCommandId`).
      // Existing clients ignore the new fields; no breaking change.
      'version': '2.6.0',
      'description':
          'Event envelope now carries `seq`, `serverInstanceId`, and '
          '`correlatingCommandId`. Action POSTs return a `commandId`. '
          'GET /api/info exposes `currentEventSeq`, '
          '`eventReplayBufferOldestSeq`, and `eventReplayBufferSize` '
          'so clients can decide between WS `?since=` replay and a '
          'full snapshot rehydrate.',
    },
    'servers': [
      {'url': 'http://localhost:$port'},
    ],
    'components': {
      'securitySchemes': {
        'bearerAuth': {
          'type': 'http',
          'scheme': 'bearer',
          'bearerFormat': 'Nightshade headless token',
        },
      },
    },
    'paths': paths,
  };
}

String openApiPath(String routePath) {
  return routePath.replaceAllMapped(
    RegExp(r'<([^>|]+)(?:\|[^>]+)?>'),
    (match) => '{${match.group(1)}}',
  );
}

String openApiTag(String routePath) {
  final segments = routePath.split('/').where((segment) {
    return segment.isNotEmpty && segment != 'api';
  }).toList();
  if (segments.isEmpty) return 'core';
  return segments.first.replaceAll('-', ' ');
}

Map<String, dynamic>? validateContentLength({
  required String method,
  required String path,
  required String? contentLengthHeader,
}) {
  if (!methodCanHaveBody(method)) {
    return null;
  }

  if (contentLengthHeader == null || contentLengthHeader.isEmpty) {
    return null;
  }

  final contentLength = int.tryParse(contentLengthHeader);
  if (contentLength == null || contentLength < 0) {
    return {
      'statusCode': HttpStatus.badRequest,
      'body': {'error': 'Invalid Content-Length header'},
    };
  }

  final limit = requestBodyLimitForPath(path);
  if (contentLength <= limit) {
    return null;
  }

  return {
    'statusCode': HttpStatus.requestEntityTooLarge,
    'body': {
      'error': 'Request body too large',
      'maxBytes': limit,
      'contentLength': contentLength,
    },
  };
}

EndpointRateLimit? endpointRateLimitFor({
  required String method,
  required String path,
}) {
  final normalizedMethod = method.toUpperCase();
  if (!_rateLimitedMethods.contains(normalizedMethod) &&
      !_rateLimitedReadPaths.contains(path)) {
    return null;
  }

  if (_highRiskControlPaths.contains(path)) {
    return const EndpointRateLimit(
      maxRequests: highRiskControlRateLimitMaxRequests,
      window: defaultControlRateLimitWindow,
    );
  }

  if (_controlPathPrefixes.any(path.startsWith) ||
      _rateLimitedReadPaths.contains(path)) {
    return const EndpointRateLimit(
      maxRequests: defaultControlRateLimitMaxRequests,
      window: defaultControlRateLimitWindow,
    );
  }

  return null;
}

String? highRiskAuditActionFor({required String method, required String path}) {
  if (method.toUpperCase() == 'GET' && path == '/api/files/browse') {
    return 'file_browse';
  }

  // P1-14 — log-file downloads are audited so an operator can trace
  // who pulled a log archive after an incident. Treated like
  // `/api/files/browse`: read-only but sensitive enough to warrant
  // an audit row. The route uses a `<filename>` parameter so we
  // normalise the path before lookup.
  if (method.toUpperCase() == 'GET') {
    if (_isLogDownloadPath(path)) {
      return 'log_download';
    }
  }

  // P1-11 — DELETE /api/system/update/staged is destructive but uses the
  // DELETE method. The remaining update audit actions live in
  // `_highRiskAuditActions` below and are matched via the POST branch.
  if (method.toUpperCase() == 'DELETE' && path == '/api/system/update/staged') {
    return 'update_discard_staged';
  }

  // P1-10 — every DELETE on the calibration surface is destructive and
  // worth auditing. The parameterised path (`/api/calibration/darks/123`)
  // is matched here on both the templated and instantiated forms; the
  // templated path appears in the route enumeration list while the
  // instantiated path appears at request time.
  if (method.toUpperCase() == 'DELETE') {
    if (_isCalibrationDarkPath(path)) return 'calibration_dark_delete';
    if (_isCalibrationFlatPath(path)) return 'calibration_flat_delete';
    if (_isCalibrationDefectMapPath(path)) {
      return 'calibration_defect_map_delete';
    }
    // P1-12 — DELETE /api/catalog/<name> removes a star/DSO catalog
    // from disk. Plate solving stops working until the catalog is
    // re-downloaded, so this is destructive enough to audit.
    if (_isCatalogNamedPath(path)) return 'catalog_delete';
  }

  if (method.toUpperCase() != 'POST') {
    return null;
  }

  // P1-13: per-row thumbnail regeneration. Templated path is
  // `/api/images/<imageId>/regenerate-thumbnail`; instantiated paths
  // carry a numeric id. Audited (but not in the high-risk rate tier)
  // because it does a one-shot FFI re-encode per call.
  if (_isRegenerateThumbnailPath(path)) {
    return 'image_regenerate_thumbnail';
  }

  return _highRiskAuditActions[path];
}

/// P1-13 — matches the parameterised
/// `/api/images/<imageId>/regenerate-thumbnail` route and its concrete
/// request paths (`/api/images/42/regenerate-thumbnail`). Both the
/// templated form (route-enumeration list) and the instantiated form
/// (request-time) are accepted.
bool _isRegenerateThumbnailPath(String path) {
  if (path == '/api/images/<imageId>/regenerate-thumbnail') return true;
  if (!path.startsWith('/api/images/')) return false;
  return path.endsWith('/regenerate-thumbnail');
}

/// P1-14 — matches the parameterised `/api/logs/files/<filename>/download`
/// route and its concrete request paths (`/api/logs/files/nightshade.log/
/// download`). We accept both the templated form (used by the
/// route-enumeration list) and the instantiated form (used at request
/// time).
bool _isLogDownloadPath(String path) {
  if (path == '/api/logs/files/<filename>/download') return true;
  if (!path.startsWith('/api/logs/files/')) return false;
  return path.endsWith('/download');
}

/// P1-10 — matches `/api/calibration/darks/<id>` (and the templated
/// `<id>` form used in the route enumeration). Used by the DELETE audit
/// branch. Returns false for the collection root `/api/calibration/darks`
/// because DELETE there is not a valid route.
bool _isCalibrationDarkPath(String path) {
  if (path == '/api/calibration/darks/<id>') return true;
  if (!path.startsWith('/api/calibration/darks/')) return false;
  final tail = path.substring('/api/calibration/darks/'.length);
  // Reject sub-resources like `/upload` or `/find-match`.
  return !tail.contains('/');
}

bool _isCalibrationFlatPath(String path) {
  if (path == '/api/calibration/flats/<id>') return true;
  if (!path.startsWith('/api/calibration/flats/')) return false;
  final tail = path.substring('/api/calibration/flats/'.length);
  return !tail.contains('/');
}

bool _isCalibrationDefectMapPath(String path) {
  if (path == '/api/calibration/defect-maps/<id>') return true;
  if (!path.startsWith('/api/calibration/defect-maps/')) return false;
  final tail = path.substring('/api/calibration/defect-maps/'.length);
  return !tail.contains('/');
}

/// P1-12 — matches `/api/catalog/<name>` (and the templated `<name>`
/// form used in the route enumeration). Used by the DELETE audit and
/// admin-scope branches. Excludes the sibling `status` / `available` /
/// `download` / `upload` / `verify` / `reload` paths because those are
/// concrete and live in their own tables.
bool _isCatalogNamedPath(String path) {
  if (path == '/api/catalog/<name>') return true;
  if (!path.startsWith('/api/catalog/')) return false;
  final tail = path.substring('/api/catalog/'.length);
  if (tail.contains('/')) return false;
  const concreteEndpoints = {
    'status',
    'available',
    'download',
    'upload',
    'verify',
    'reload',
  };
  return !concreteEndpoints.contains(tail);
}

/// Whether [path] is in the high-risk control allow-list (used by CORS
/// policy and rate-limit tier selection). Why exposed: the CORS middleware
/// needs to apply a stricter origin allow-list rule for these endpoints.
bool isHighRiskControlPath(String path) {
  return _highRiskControlPaths.contains(path);
}

bool isPublicEndpoint({required String method, required String path}) {
  final normalizedMethod = method.toUpperCase();
  final normalizedPath = _normalizePath(path);
  return normalizedMethod == 'GET' && normalizedPath == '/api/info';
}

String requiredAuthScopeNameForEndpoint({
  required String method,
  required String path,
}) {
  final normalizedMethod = method.toUpperCase();
  final normalizedPath = _normalizePath(path);

  if (isPublicEndpoint(method: normalizedMethod, path: normalizedPath)) {
    return 'public';
  }

  // P0-3: `/api/pairing/active` lists active pairing-session codes, which
  // are credentials in transit. Admin-only across every method so a paired
  // control-scope phone cannot read freshly-minted codes the operator is
  // sharing out-of-band.
  if (_pairingActivePaths.contains(normalizedPath)) {
    return 'admin';
  }

  if (_adminOnlyPathPrefixes.any(normalizedPath.startsWith) ||
      _adminOnlyPaths.contains(normalizedPath)) {
    return 'admin';
  }

  // P1-11: DELETE /api/system/update/staged (destructive — wipes staging
  // tree). All non-GET methods on the update surface are admin so a
  // control-scope token cannot, for example, DELETE the staged update
  // a paired admin operator queued for installation.
  if (normalizedPath.startsWith('/api/system/update/') &&
      normalizedMethod != 'GET') {
    return 'admin';
  }

  // P1-10: calibration library scope.
  //
  //   GET   /api/calibration/...                  → view
  //   POST  /api/calibration/darks/upload          → admin (file upload)
  //   POST  /api/calibration/darks/backfill-sizes  → admin (mutating sweep)
  //   POST  /api/calibration/.../* (others)        → control
  //   DELETE /api/calibration/...                  → admin (destructive)
  if (normalizedPath.startsWith('/api/calibration/')) {
    if (normalizedMethod == 'GET') {
      return 'view';
    }
    if (normalizedMethod == 'DELETE') {
      return 'admin';
    }
    if (normalizedMethod == 'POST') {
      if (normalizedPath == '/api/calibration/darks/upload' ||
          normalizedPath == '/api/calibration/darks/backfill-sizes') {
        return 'admin';
      }
      return 'control';
    }
    // Fall through to default control for any other mutating method.
  }

  // v46: unified Calibration Library Manager scope. Mirrors the per-table
  // calibration surface above, but the prefix is hyphenated so it does NOT
  // match the `/api/calibration/` block.
  //
  //   GET    /api/calibration-library            → view (list)
  //   POST   /api/calibration-library/match      → control (read-only preview)
  //   PUT    /api/calibration-library/.../tags   → control (annotate)
  //   DELETE /api/calibration-library/...        → admin (destructive)
  if (normalizedPath == '/api/calibration-library' ||
      normalizedPath.startsWith('/api/calibration-library/')) {
    if (normalizedMethod == 'GET') {
      return 'view';
    }
    if (normalizedMethod == 'DELETE') {
      return 'admin';
    }
    return 'control';
  }

  // P1-12: catalog management scope.
  //
  //   GET    /api/catalog/status        → view
  //   GET    /api/catalog/available     → view
  //   POST   /api/catalog/download      → admin (already in _adminOnlyPaths)
  //   POST   /api/catalog/upload        → admin
  //   POST   /api/catalog/verify        → admin
  //   POST   /api/catalog/reload        → admin
  //   DELETE /api/catalog/<name>        → admin
  //
  // The named DELETE is parameterised so the `_adminOnlyPaths` set
  // can't cover it; we resolve it via the path matcher here.
  if (normalizedPath.startsWith('/api/catalog/')) {
    if (normalizedMethod == 'DELETE' && _isCatalogNamedPath(normalizedPath)) {
      return 'admin';
    }
    // Concrete admin-only POSTs are caught by the `_adminOnlyPaths`
    // check above. GET status/available falls through to view.
  }

  final auditAction = highRiskAuditActionFor(
    method: normalizedMethod,
    path: normalizedPath,
  );
  if (auditAction == 'file_browse' ||
      auditAction?.startsWith('backup_') == true) {
    return 'admin';
  }

  if (normalizedMethod == 'GET' || normalizedMethod == 'WS') {
    return 'view';
  }

  return 'control';
}

String _normalizePath(String path) {
  if (path.startsWith('/')) {
    return path;
  }
  return '/$path';
}

const _rateLimitedMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

const _adminOnlyPathPrefixes = {
  '/api/backup',
  // Cloud sync — POST /api/sync/push uploads the entire configuration
  // bundle off-box, so mutating sync calls are admin-only like backup.
  '/api/sync',
  '/api/files',
  '/api/settings',
  // P2-11 — plugin management. List (GET /api/plugins) is admin-scope
  // because it exposes installed-plugin metadata that a paired control
  // phone shouldn't see; every mutating method is destructive by design
  // (upload installs code-adjacent assets, delete drops the archive).
  '/api/plugins',
};

const _adminOnlyPaths = {
  '/api/self-test',
  '/api/session-handoff',
  // P1-14 — destructive / synthetic log operations. Reading is view
  // scope; mutating is admin only.
  '/api/logs/clear',
  '/api/logs/test-entry',
  // P1-13 — sidecar thumbnail backfill walks every captured-image row
  // and invokes the Rust FFI per missing sidecar. On Pi-class SD storage
  // this can run for several minutes and produce significant I/O — admin
  // scope so a paired control-phone can't accidentally kick off a
  // session-wide rebuild during live capture.
  '/api/images/backfill-thumbnails',
  // P1-11 — OTA update mutating endpoints. The two GET endpoints
  // (`/api/system/version`, `/api/system/update/status`,
  // `/api/system/update/staged`) stay at view scope so a paired phone
  // operator can monitor without being able to trigger a download.
  '/api/system/update/check',
  '/api/system/update/download',
  '/api/system/update/apply',
  '/api/system/update/abort',
  '/api/system/update/rollback',
  // P1-12 — catalog mutating endpoints. Status + available stay at view
  // scope so a paired control phone can render a "catalogs missing"
  // banner; everything that changes state is admin-only.
  '/api/catalog/download',
  '/api/catalog/upload',
  '/api/catalog/verify',
  '/api/catalog/reload',
};

/// P0-3 — pairing-session diagnostic endpoint(s). Admin-only across every
/// method because the response body contains live pairing codes that the
/// operator may be sharing out of band. Keeping the table separate from
/// `_adminOnlyPaths` makes it explicit that this set covers GETs too,
/// whereas `_adminOnlyPaths` only escalates mutating methods.
const _pairingActivePaths = {'/api/pairing/active'};

const _controlPathPrefixes = [
  '/api/devices/',
  '/api/camera/',
  '/api/mount/',
  '/api/focuser/',
  '/api/filter-wheel/',
  '/api/rotator/',
  '/api/phd2/',
  '/api/guider/',
  '/api/builtin-guider/',
  '/api/sequencer/',
  '/api/framing/',
  '/api/dome/',
  '/api/safety/',
  '/api/switch/',
  '/api/cover/',
  '/api/backup/',
  '/api/files/',
  // P1-11 — system / OTA update endpoints. Most do nothing destructive
  // on their own but the underlying work is heavy (HTTP fetch, file
  // staging) so we rate-limit them like the rest of the control surface.
  '/api/system/',
  // P1-10 — calibration library mutating endpoints. Rate-limited like
  // the rest of the control surface so a runaway client cannot pummel
  // the DB with delete loops or upload-and-delete cycles.
  '/api/calibration/',
];

const _rateLimitedReadPaths = {'/api/files/browse'};

const _highRiskControlPaths = {
  '/api/devices/connect',
  '/api/devices/disconnect',
  '/api/mount/slew',
  '/api/mount/slew-alt-az',
  '/api/mount/park',
  '/api/mount/unpark',
  '/api/framing/slew-to-target',
  '/api/framing/center-on-target',
  '/api/framing/park',
  '/api/framing/unpark',
  '/api/dome/open',
  '/api/dome/close',
  '/api/dome/slew',
  '/api/dome/park',
  '/api/backup/restore',
  '/api/backup/upload-restore',
  '/api/sequencer/start',
  '/api/sequencer/stop',
  '/api/sequencer/resume',
  // P1-14 — clear permanently deletes log files, test-entry can be
  // abused as a write amplifier; both belong in the high-risk tier
  // so an aggressive client gets throttled to 12 calls/min.
  '/api/logs/clear',
  '/api/logs/test-entry',
  // P1-11 — OTA update apply / rollback / discard. Apply triggers a
  // server-process restart, rollback is destructive, and a malicious
  // client repeatedly hammering these endpoints could DoS the
  // operator. 12 calls/min is plenty for legitimate use.
  '/api/system/update/apply',
  '/api/system/update/rollback',
  '/api/system/update/staged',
  // P1-10 — calibration uploads and the on-disk verifier are destructive
  // / I/O-heavy. The fine-grained DELETE paths are handled via the
  // calibration DELETE branch in `highRiskAuditActionFor` rather than
  // being enumerated here, because each id-bearing instance is unique.
  '/api/calibration/darks/upload',
  '/api/calibration/darks/backfill-sizes',
  // P1-13 — sidecar thumbnail backfill: heavy-I/O FFI walk over every
  // captured-image row. 12 calls/min is plenty for legitimate retries.
  '/api/images/backfill-thumbnails',
  // P1-12 — catalog management. Download triggers a multi-MB HTTPS
  // fetch + decompression + atomic rename; verify computes SHA-256
  // over multi-MB files; both are heavy and should be throttled to
  // 12 calls/min so a misbehaving client cannot pummel the upstream
  // mirrors or the SD card.
  '/api/catalog/download',
  '/api/catalog/upload',
  '/api/catalog/verify',
};

const _highRiskAuditActions = {
  '/api/devices/connect': 'device_connect',
  '/api/devices/disconnect': 'device_disconnect',
  '/api/mount/slew': 'mount_slew',
  '/api/mount/slew-alt-az': 'mount_slew_alt_az',
  '/api/mount/park': 'mount_park',
  '/api/mount/unpark': 'mount_unpark',
  '/api/framing/slew-to-target': 'framing_slew_to_target',
  '/api/framing/center-on-target': 'framing_center_on_target',
  '/api/framing/park': 'framing_park',
  '/api/framing/unpark': 'framing_unpark',
  '/api/dome/open': 'dome_open',
  '/api/dome/close': 'dome_close',
  '/api/dome/slew': 'dome_slew',
  '/api/dome/park': 'dome_park',
  '/api/backup/restore': 'backup_restore',
  '/api/backup/upload-restore': 'backup_upload_restore',
  '/api/sequencer/start': 'sequence_start',
  '/api/sequencer/stop': 'sequence_stop',
  '/api/sequencer/resume': 'sequence_resume',
  // P1-14 — destructive log operations. Audit row records who and
  // when, status comes from the response code in the middleware.
  '/api/logs/clear': 'log_clear',
  '/api/logs/test-entry': 'log_test_entry',
  // P1-11 — OTA update audit trail. `update_discard_staged` is matched
  // via the DELETE branch above; the rest are POST.
  '/api/system/update/download': 'update_download',
  '/api/system/update/apply': 'update_apply',
  '/api/system/update/rollback': 'update_rollback',
  // P1-10 — calibration mutating endpoints. `calibration_dark_delete` and
  // friends are matched via the DELETE branch in highRiskAuditActionFor
  // because the id is parameterised. The POST paths are concrete and live
  // in this table.
  '/api/calibration/darks/upload': 'calibration_dark_upload',
  '/api/calibration/darks/backfill-sizes': 'calibration_backfill',
  // P1-12 — catalog mutating endpoints. The DELETE audit action is
  // resolved via `_isCatalogNamedPath` above because the path is
  // parameterised.
  '/api/catalog/download': 'catalog_download',
  '/api/catalog/upload': 'catalog_upload',
  '/api/catalog/verify': 'catalog_verify',
  // P1-13 — thumbnail-cache mutations. The backfill walks every row +
  // invokes the Rust FFI for each missing sidecar (heavy I/O on Pi SD
  // storage); the regenerate endpoint is a per-row escape hatch when a
  // FITS is replaced out-of-band. The regenerate POST is matched via
  // `_isRegenerateThumbnailPath` because the row id is parameterised.
  '/api/images/backfill-thumbnails': 'image_backfill_thumbnails',
};

class EndpointRateLimit {
  final int maxRequests;
  final Duration window;

  const EndpointRateLimit({required this.maxRequests, required this.window});
}

class RateLimitDecision {
  final bool allowed;
  final int maxRequests;
  final int retryAfterSeconds;

  /// P2-6: which bucket — endpoint window or per-token route-class — produced
  /// this decision. `endpoint` is the legacy sliding-window check tied to a
  /// (clientKey, method, path) triple; `token-<class>` is the new token-
  /// bucket gate keyed by (tokenId, routeClass). Surfaced so 429 responses
  /// can name the bucket that tripped and the operator can tell whether the
  /// throttle came from "you've called this endpoint too often" or "your
  /// token used its read budget across many endpoints".
  final String bucket;

  const RateLimitDecision({
    required this.allowed,
    required this.maxRequests,
    required this.retryAfterSeconds,
    this.bucket = 'endpoint',
  });
}

/// P2-6: per-token route class. NAT collapses many phones onto a single
/// public IP, so an IP-keyed rate limit either treats every device behind
/// the NAT as one client (DoS by neighbour) or wastes the gate entirely.
/// Keying the bucket on the authenticated token + a coarse route class
/// gives every token its own budget while still throttling pathological
/// callers within that token's session.
enum TokenRouteClass {
  /// Read-only state pulls (GET). 60 req/s allows a phone dashboard to
  /// poll status, devices, sequencer state, etc. at ~1 Hz across a dozen
  /// endpoints without bumping the limit.
  read,

  /// State-changing operations (POST/PUT/PATCH/DELETE). 20 req/s
  /// accommodates batched device-connect-on-startup and rapid sequence
  /// edits while still rate-limiting destructive bursts.
  write,

  /// JPEG live-view frames (`/api/camera/live-view/frame`). 30 req/s
  /// covers the design upper bound of ~10 fps with retry headroom.
  liveView,

  /// Full image downloads (`/api/images/.../download`, raw FITS pulls).
  /// 5 req/s — these are multi-MB transfers and the bottleneck is the
  /// disk + network, not the CPU, so we keep a tight ceiling.
  imageDownload,
}

/// Default per-second budgets for each token route class. Held in a
/// separate const so tests can override them via [TokenBucketRateLimiter]'s
/// `configForClass` injection point without having to monkey-patch the
/// router.
const Map<TokenRouteClass, TokenBucketConfig> defaultTokenBucketConfigs = {
  TokenRouteClass.read: TokenBucketConfig(
    capacity: 60,
    refillTokens: 60,
    refillPeriod: Duration(seconds: 1),
  ),
  TokenRouteClass.write: TokenBucketConfig(
    capacity: 20,
    refillTokens: 20,
    refillPeriod: Duration(seconds: 1),
  ),
  TokenRouteClass.liveView: TokenBucketConfig(
    capacity: 30,
    refillTokens: 30,
    refillPeriod: Duration(seconds: 1),
  ),
  TokenRouteClass.imageDownload: TokenBucketConfig(
    capacity: 5,
    refillTokens: 5,
    refillPeriod: Duration(seconds: 1),
  ),
};

/// Classify a request to its [TokenRouteClass]. Live-view frames and
/// image downloads take precedence over the read/write split because they
/// have their own (tighter) budgets.
TokenRouteClass tokenRouteClassFor({
  required String method,
  required String path,
}) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  final normalizedMethod = method.toUpperCase();
  // Live-view frames are the highest-throughput endpoint and must not
  // share a bucket with cheap state polls.
  if (normalizedPath == '/api/camera/live-view/frame') {
    return TokenRouteClass.liveView;
  }
  // Wave 7A — WebRTC live-view signalling endpoints share the
  // live-view bucket because the SSE candidate stream + ICE POSTs
  // burst during session setup (potentially many candidates per
  // second on a complex network) and we don't want a paired phone
  // bringing up a fresh peer connection to exhaust its `read`
  // budget mid-handshake. The actual JPEG datachannel traffic
  // doesn't pass through this gate (it's WebRTC, not HTTP), so the
  // bucket only governs the signalling overhead.
  if (normalizedPath.startsWith('/api/webrtc/live-view/')) {
    return TokenRouteClass.liveView;
  }
  // Multi-MB transfers: image download + raw image bytes + binary FITS
  // pull. They live in their own (tightest) bucket.
  if (normalizedPath.startsWith('/api/images/') &&
      normalizedPath.endsWith('/download')) {
    return TokenRouteClass.imageDownload;
  }
  if (normalizedPath == '/api/imaging/raw-data' ||
      (normalizedPath.startsWith('/api/calibration/') &&
          normalizedPath.endsWith('/download')) ||
      (normalizedPath.startsWith('/api/backup/') &&
          normalizedPath.endsWith('/download')) ||
      (normalizedPath.startsWith('/api/logs/files/') &&
          normalizedPath.endsWith('/download'))) {
    return TokenRouteClass.imageDownload;
  }
  if (normalizedMethod == 'GET' || normalizedMethod == 'HEAD') {
    return TokenRouteClass.read;
  }
  return TokenRouteClass.write;
}

/// Human-readable name used in 429 bodies + log lines. Aligns with the
/// task spec wording (`read`, `write`, `live-view`, `image-download`).
String tokenRouteClassName(TokenRouteClass cls) {
  switch (cls) {
    case TokenRouteClass.read:
      return 'read';
    case TokenRouteClass.write:
      return 'write';
    case TokenRouteClass.liveView:
      return 'live-view';
    case TokenRouteClass.imageDownload:
      return 'image-download';
  }
}

/// Configuration for a single token-bucket. The bucket holds at most
/// [capacity] tokens and refills [refillTokens] every [refillPeriod].
class TokenBucketConfig {
  final int capacity;
  final int refillTokens;
  final Duration refillPeriod;

  const TokenBucketConfig({
    required this.capacity,
    required this.refillTokens,
    required this.refillPeriod,
  });

  /// Tokens added per microsecond. Computed lazily by the limiter; held as
  /// a method (not a getter) to keep the type a const-friendly value type.
  double refillPerMicrosecond() => refillTokens / refillPeriod.inMicroseconds;
}

/// P2-6: token-bucket rate limiter keyed by `(tokenId, route_class)`.
///
/// In-memory only — counters reset on server restart. Memory bound: one
/// bucket per (token × class) pair, evicted by LRU once the table exceeds
/// [maxBuckets]. Default [maxBuckets] (8192) holds 2048 tokens at four
/// classes each, well past any realistic paired-device count.
class TokenBucketRateLimiter {
  final Map<TokenRouteClass, TokenBucketConfig> _configByClass;
  final DateTime Function() _now;
  final int maxBuckets;

  // Linked-map preserves insertion order, which we use as a poor-man's LRU:
  // every touch removes-and-reinserts the entry so the front of the map is
  // the coldest bucket we'll evict next.
  final _buckets = <String, _TokenBucketState>{};

  TokenBucketRateLimiter({
    Map<TokenRouteClass, TokenBucketConfig>? configByClass,
    DateTime Function()? now,
    this.maxBuckets = 8192,
  }) : _configByClass = configByClass ?? defaultTokenBucketConfigs,
       _now = now ?? DateTime.now;

  /// Look up the configuration for a class. Returns the default config if
  /// the caller-supplied map omitted it (defensive — every class should
  /// have an entry but a partial override should still produce a valid
  /// decision rather than a null deref).
  TokenBucketConfig configFor(TokenRouteClass cls) {
    return _configByClass[cls] ?? defaultTokenBucketConfigs[cls]!;
  }

  /// Attempt to consume one token from `(tokenId, routeClass)`'s bucket.
  /// Returns a decision indicating whether the request is allowed plus
  /// the [Duration] until the next token becomes available on a denial.
  RateLimitDecision tryConsume({
    required String tokenId,
    required TokenRouteClass routeClass,
  }) {
    final config = configFor(routeClass);
    final key = '$tokenId|${tokenRouteClassName(routeClass)}';
    final now = _now();
    var state = _buckets.remove(key);
    state ??= _TokenBucketState(
      tokens: config.capacity.toDouble(),
      lastRefillMicros: now.microsecondsSinceEpoch,
    );

    // Refill based on wall-clock elapsed. Why microsecond resolution: at
    // 60 req/s the per-token interval is ~16.6 ms, so millisecond math
    // would round trips into 0 and starve the bucket between two close
    // requests. Microseconds give us the precision the budget needs.
    final elapsedMicros = now.microsecondsSinceEpoch - state.lastRefillMicros;
    if (elapsedMicros > 0) {
      final added = elapsedMicros * config.refillPerMicrosecond();
      state.tokens = (state.tokens + added).clamp(
        0.0,
        config.capacity.toDouble(),
      );
      state.lastRefillMicros = now.microsecondsSinceEpoch;
    }

    final bucketName = 'token-${tokenRouteClassName(routeClass)}';

    if (state.tokens < 1.0) {
      // How long until tokens >= 1? deficit / refill-rate.
      final deficit = 1.0 - state.tokens;
      final refillRate = config.refillPerMicrosecond();
      final retryMicros = refillRate > 0
          ? (deficit / refillRate).ceil()
          : config.refillPeriod.inMicroseconds;
      // Re-insert at the back of the LRU.
      _buckets[key] = state;
      _evictIfOverCapacity();
      final retrySeconds = (retryMicros / 1000000).ceil();
      return RateLimitDecision(
        allowed: false,
        maxRequests: config.capacity,
        retryAfterSeconds: retrySeconds < 1 ? 1 : retrySeconds,
        bucket: bucketName,
      );
    }

    state.tokens -= 1.0;
    _buckets[key] = state;
    _evictIfOverCapacity();
    return RateLimitDecision(
      allowed: true,
      maxRequests: config.capacity,
      retryAfterSeconds: 0,
      bucket: bucketName,
    );
  }

  void _evictIfOverCapacity() {
    while (_buckets.length > maxBuckets) {
      _buckets.remove(_buckets.keys.first);
    }
  }

  /// Test helper: drop all state.
  void clear() {
    _buckets.clear();
  }

  /// Test helper: current token level for a key (useful for asserting
  /// refill behaviour without driving the public path).
  double? tokensFor({
    required String tokenId,
    required TokenRouteClass routeClass,
  }) {
    final key = '$tokenId|${tokenRouteClassName(routeClass)}';
    return _buckets[key]?.tokens;
  }
}

class _TokenBucketState {
  double tokens;
  int lastRefillMicros;
  _TokenBucketState({required this.tokens, required this.lastRefillMicros});
}

class EndpointRateLimiter {
  final DateTime Function() _now;
  final _requestsByKey = <String, List<DateTime>>{};

  EndpointRateLimiter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  RateLimitDecision check({
    required String clientKey,
    required String method,
    required String path,
  }) {
    final limit = endpointRateLimitFor(method: method, path: path);
    if (limit == null) {
      return const RateLimitDecision(
        allowed: true,
        maxRequests: 0,
        retryAfterSeconds: 0,
      );
    }

    final now = _now();
    final key = '$clientKey ${method.toUpperCase()} $path';
    final cutoff = now.subtract(limit.window);
    final requests = _requestsByKey.putIfAbsent(key, () => <DateTime>[]);
    requests.removeWhere((timestamp) => !timestamp.isAfter(cutoff));

    if (requests.length >= limit.maxRequests) {
      final oldest = requests.first;
      final retryAfter = oldest.add(limit.window).difference(now);
      return RateLimitDecision(
        allowed: false,
        maxRequests: limit.maxRequests,
        retryAfterSeconds: retryAfter.inSeconds < 1 ? 1 : retryAfter.inSeconds,
      );
    }

    requests.add(now);
    return RateLimitDecision(
      allowed: true,
      maxRequests: limit.maxRequests,
      retryAfterSeconds: 0,
    );
  }

  void clear() {
    _requestsByKey.clear();
  }
}
