import 'dart:io';

const int oneMiB = 1024 * 1024;
const int defaultMaxRequestBodyBytes = oneMiB;
const int imageProcessingMaxRequestBodyBytes = 64 * oneMiB;
const int backupUploadMaxRequestBodyBytes = 256 * oneMiB;

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
      operation['x-max-request-body-bytes'] =
          requestBodyLimitForPath(routePath);
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
      'version': '2.5.0',
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

String? highRiskAuditActionFor({
  required String method,
  required String path,
}) {
  if (method.toUpperCase() == 'GET' && path == '/api/files/browse') {
    return 'file_browse';
  }

  if (method.toUpperCase() != 'POST') {
    return null;
  }

  return _highRiskAuditActions[path];
}

/// Whether [path] is in the high-risk control allow-list (used by CORS
/// policy and rate-limit tier selection). Why exposed: the CORS middleware
/// needs to apply a stricter origin allow-list rule for these endpoints.
bool isHighRiskControlPath(String path) {
  return _highRiskControlPaths.contains(path);
}

bool isPublicEndpoint({
  required String method,
  required String path,
}) {
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

  if (_adminOnlyPathPrefixes.any(normalizedPath.startsWith) ||
      _adminOnlyPaths.contains(normalizedPath)) {
    return 'admin';
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
  '/api/files',
  '/api/settings',
};

const _adminOnlyPaths = {
  '/api/self-test',
  '/api/session-handoff',
};

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
];

const _rateLimitedReadPaths = {
  '/api/files/browse',
};

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
};

class EndpointRateLimit {
  final int maxRequests;
  final Duration window;

  const EndpointRateLimit({
    required this.maxRequests,
    required this.window,
  });
}

class RateLimitDecision {
  final bool allowed;
  final int maxRequests;
  final int retryAfterSeconds;

  const RateLimitDecision({
    required this.allowed,
    required this.maxRequests,
    required this.retryAfterSeconds,
  });
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
