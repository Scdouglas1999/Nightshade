import 'dart:convert';

import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_error;
import 'package:shelf/shelf.dart';

import 'response_helpers.dart';

/// Map a flutter_rust_bridge [bridge_error.NightshadeError] to the HTTP status
/// that best describes it. Device-operation errors that reach the headless
/// error translator would otherwise all collapse to an opaque 500 — a remote
/// tablet should instead see "not supported", "not connected", "bad request",
/// etc. so it can react. Genuinely internal/driver faults stay 500.
/// Extract a human-readable message from a flutter_rust_bridge
/// [bridge_error.NightshadeError]. Its `toString()` leaks the freezed wrapper
/// (`NightshadeError.operationFailed(field0: <msg>)`); unwrap to just `<msg>`
/// so the wire response carries the actionable text a remote client should
/// show, not the Dart class plumbing.
String _cleanBackendErrorMessage(bridge_error.NightshadeError e) {
  final raw = e.toString();
  final match = RegExp(r'\(field0:\s*(.*)\)$', dotAll: true).firstMatch(raw);
  final inner = match?.group(1)?.trim();
  return (inner != null && inner.isNotEmpty) ? inner : raw;
}

/// Produce a short, single-line message from an arbitrary thrown object for the
/// generic-500 wire body. Strips the `Exception:`/`StateError:` prefixes, keeps
/// only the first line (so a multi-line message can't smuggle a stack trace),
/// and caps the length.
String _sanitizeErrorDetail(Object e) {
  var msg = e.toString().trim();
  for (final prefix in const ['Exception: ', 'StateError: ', 'Bad state: ']) {
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length).trim();
    }
  }
  final firstLine = msg.split('\n').first.trim();
  const maxLen = 300;
  return firstLine.length > maxLen
      ? '${firstLine.substring(0, maxLen)}…'
      : firstLine;
}

int _httpStatusForBackendError(bridge_error.NightshadeError e) {
  return e.maybeMap(
    notSupported: (_) => 501,
    notConnected: (_) => 409,
    deviceDisconnected: (_) => 409,
    deviceNotFound: (_) => 404,
    invalidParameter: (_) => 400,
    invalidInput: (_) => 400,
    invalidDeviceId: (_) => 400,
    parameterOutOfRange: (_) => 400,
    deviceBusy: (_) => 409,
    resourceExhausted: (_) => 409,
    timeout: (_) => 504,
    deviceTimeout: (_) => 504,
    connectionTimeout: (_) => 504,
    connectionFailed: (_) => 502,
    noImageAvailable: (_) => 404,
    exposureCancelled: (_) => 409,
    cancelled: (_) => 409,
    orElse: () => 500,
  );
}

/// Validation helpers for headless API request payloads.
///
/// Why: The previous pattern was `payload['x'] as String`, which throws a
/// generic [TypeError] on missing or wrong-type fields. The catch block then
/// formatted that error as `e.toString()` into a 500 response body, leaking
/// stack traces and internal type names. These helpers raise a single
/// [BadRequestError] type that the [errorMiddleware] (or per-handler glue)
/// translates into a structured 400 response. Internal errors instead become
/// 500 with a request-id reference and never echo `e.toString()` to the body.

class BadRequestError implements Exception {
  final String field;
  final String expected;
  final String? message;

  BadRequestError({required this.field, required this.expected, this.message});

  @override
  String toString() => 'BadRequestError(field=$field, expected=$expected)';

  String get displayMessage {
    if (message != null) return message!;
    return switch (expected) {
      'string' => '$field is required',
      'number' => '$field is required',
      'integer' => '$field is required',
      'boolean' => '$field is required',
      'object' => '$field is required',
      _ => 'Invalid request',
    };
  }

  Map<String, Object?> toJsonBody() => {
    'error': displayMessage,
    'code': 'invalid_request',
    'field': field,
    'expected': expected,
    if (message != null) 'message': message,
  };
}

/// Handler-level structured failure for fail-closed responses.
///
/// Why: handlers must not return `{'status': 'failed', 'error': e.toString()}`
/// — that ships HTTP 200/500 bodies with leaked Dart type names and stack
/// traces, and confuses clients about whether the operation succeeded. The
/// `errorTranslationMiddleware` catches this exception and renders a
/// non-2xx response with a stable machine-readable `code`, a sanitized
/// human `message`, and an optional `details` map. Full exception detail
/// (if any) goes to the structured log via [cause]/[stackTrace].
class HandlerFailure implements Exception {
  /// Stable machine-readable identifier, e.g. `backup_create_failed`.
  final String code;

  /// Sanitized human-readable summary safe to ship to the caller.
  ///
  /// MUST NOT include `e.toString()` output, stack traces, or internal
  /// Dart type names. Producer-supplied service messages (e.g. a
  /// BackupResult.errorMessage) are acceptable here because they are
  /// curated by the service layer for caller display.
  final String message;

  /// HTTP status code. Defaults to 500 (server-side failure). Use 4xx
  /// only when the caller can fix the request by itself.
  final int statusCode;

  /// Optional caller-visible additional fields (counts, ids, paths, etc.).
  /// Must not contain stack traces or Dart type names.
  final Map<String, Object?>? details;

  /// Underlying cause for log-side diagnostics. NEVER serialized.
  final Object? cause;

  /// Stack trace for log-side diagnostics. NEVER serialized.
  final StackTrace? stackTrace;

  HandlerFailure({
    required this.code,
    required this.message,
    this.statusCode = 500,
    this.details,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() => 'HandlerFailure(code=$code, status=$statusCode)';

  Map<String, Object?> toJsonBody({String? requestId}) => {
    'error': code,
    'message': message,
    if (requestId != null) 'requestId': requestId,
    if (details != null) ...details!,
  };
}

/// Reads the request body as a JSON object.
///
/// Throws [BadRequestError] if the body is not valid JSON or not a
/// [Map<String, dynamic>] at the top level.
Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) {
    throw BadRequestError(
      field: 'body',
      expected: 'json_object',
      message: 'Request body is empty',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw BadRequestError(
      field: 'body',
      expected: 'valid_json',
      message: 'Malformed JSON: ${e.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw BadRequestError(
      field: 'body',
      expected: 'json_object',
      message: 'Top-level JSON value must be an object',
    );
  }
  return decoded;
}

/// Required string. Empty strings throw unless [allowEmpty] is true.
String requireString(
  Map<String, dynamic> payload,
  String field, {
  bool allowEmpty = false,
  int? maxLength,
}) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'string');
  }
  if (value is! String) {
    throw BadRequestError(field: field, expected: 'string');
  }
  if (!allowEmpty && value.isEmpty) {
    throw BadRequestError(
      field: field,
      expected: 'string',
      message: 'Value must not be empty',
    );
  }
  if (maxLength != null && value.length > maxLength) {
    throw BadRequestError(
      field: field,
      expected: 'string',
      message: 'Value exceeds maximum length of $maxLength',
    );
  }
  return value;
}

String? optionalString(
  Map<String, dynamic> payload,
  String field, {
  bool allowEmpty = false,
  int? maxLength,
}) {
  final value = payload[field];
  if (value == null) return null;
  if (value is! String) {
    throw BadRequestError(field: field, expected: 'string');
  }
  if (!allowEmpty && value.isEmpty) {
    return null;
  }
  if (maxLength != null && value.length > maxLength) {
    throw BadRequestError(
      field: field,
      expected: 'string',
      message: 'Value exceeds maximum length of $maxLength',
    );
  }
  return value;
}

int requireInt(
  Map<String, dynamic> payload,
  String field, {
  int? min,
  int? max,
}) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'integer');
  }
  int parsed;
  if (value is int) {
    parsed = value;
  } else if (value is double && value == value.toInt().toDouble()) {
    parsed = value.toInt();
  } else if (value is String) {
    final maybe = int.tryParse(value);
    if (maybe == null) {
      throw BadRequestError(field: field, expected: 'integer');
    }
    parsed = maybe;
  } else {
    throw BadRequestError(field: field, expected: 'integer');
  }
  _checkRange(field, parsed.toDouble(), min?.toDouble(), max?.toDouble());
  return parsed;
}

int? optionalInt(
  Map<String, dynamic> payload,
  String field, {
  int? min,
  int? max,
}) {
  final value = payload[field];
  if (value == null) return null;
  return requireInt(payload, field, min: min, max: max);
}

double requireDouble(
  Map<String, dynamic> payload,
  String field, {
  double? min,
  double? max,
}) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'number');
  }
  double parsed;
  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    final maybe = double.tryParse(value);
    if (maybe == null) {
      throw BadRequestError(field: field, expected: 'number');
    }
    parsed = maybe;
  } else {
    throw BadRequestError(field: field, expected: 'number');
  }
  _checkRange(field, parsed, min, max);
  return parsed;
}

double? optionalDouble(
  Map<String, dynamic> payload,
  String field, {
  double? min,
  double? max,
}) {
  final value = payload[field];
  if (value == null) return null;
  return requireDouble(payload, field, min: min, max: max);
}

bool requireBool(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'boolean');
  }
  if (value is bool) return value;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
  }
  throw BadRequestError(field: field, expected: 'boolean');
}

bool? optionalBool(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value == null) return null;
  return requireBool(payload, field);
}

Map<String, dynamic> requireObject(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'object');
  }
  if (value is! Map<String, dynamic>) {
    throw BadRequestError(field: field, expected: 'object');
  }
  return value;
}

Map<String, dynamic>? optionalObject(
  Map<String, dynamic> payload,
  String field,
) {
  final value = payload[field];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) {
    throw BadRequestError(field: field, expected: 'object');
  }
  return value;
}

List<T> requireList<T>(Map<String, dynamic> payload, String field) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'array');
  }
  if (value is! List) {
    throw BadRequestError(field: field, expected: 'array');
  }
  for (final element in value) {
    if (element is! T) {
      throw BadRequestError(field: field, expected: 'array<${T.toString()}>');
    }
  }
  return value.cast<T>();
}

List<T>? optionalList<T>(Map<String, dynamic> payload, String field) {
  if (payload[field] == null) return null;
  return requireList<T>(payload, field);
}

void _checkRange(String field, double value, double? min, double? max) {
  if (min != null && value < min) {
    throw BadRequestError(
      field: field,
      expected: 'number',
      message: 'Value must be >= $min',
    );
  }
  if (max != null && value > max) {
    throw BadRequestError(
      field: field,
      expected: 'number',
      message: 'Value must be <= $max',
    );
  }
}

/// Translates uncaught exceptions into structured error responses.
///
/// Why a dedicated middleware: handlers previously returned 500 with
/// `{"error": e.toString()}`, leaking stack traces and Dart type names. This
/// middleware catches [BadRequestError] (-> 400 with structured body) and
/// any other exception (-> 500 with `internal_error` + `requestId`). Full
/// exception detail goes to the structured log only.
Middleware errorTranslationMiddleware({
  required void Function(String message, {Map<String, Object?>? fields})
  logError,
  required String Function(Request request) requestIdFor,
  bool Function(Request request)? shouldBypass,
}) {
  return (innerHandler) {
    return (request) async {
      if (shouldBypass?.call(request) ?? false) {
        return innerHandler(request);
      }
      try {
        return await innerHandler(request);
      } on BadRequestError catch (e) {
        return jsonBadRequest(e.toJsonBody());
      } on HandlerFailure catch (e, stackTrace) {
        final requestId = requestIdFor(request);
        // Log the full detail (cause + stack) on the server side; the wire
        // body only carries the curated code/message/details. Why two logs:
        // a HandlerFailure is an explicit handler decision and is logged
        // at warning (not error) unless the underlying cause is unexpected.
        logError(
          '[HANDLER-FAIL][$requestId] ${e.code}: ${e.message}',
          fields: {
            'requestId': requestId,
            'code': e.code,
            'statusCode': e.statusCode,
            if (e.cause != null) 'cause': e.cause.toString(),
            if (e.stackTrace != null) 'cause_stack': e.stackTrace.toString(),
            'handler_stack': stackTrace.toString(),
          },
        );
        return jsonResponse(
          e.toJsonBody(requestId: requestId),
          statusCode: e.statusCode,
        );
      } on bridge_error.NightshadeError catch (e, stackTrace) {
        // Device-operation errors from the native bridge: map the structured
        // category to a meaningful HTTP status (501 not-supported, 409
        // not-connected/busy, 404 not-found, 400 bad-params, 504 timeout, 502
        // unreachable) so a remote client gets an actionable response instead
        // of an opaque 500. Genuinely internal/driver faults fall through to
        // 500 via the mapper's orElse.
        final requestId = requestIdFor(request);
        final statusCode = _httpStatusForBackendError(e);
        final message = _cleanBackendErrorMessage(e);
        if (statusCode >= 500) {
          logError(
            '[ERR][$requestId] Backend error: $message',
            fields: {
              'requestId': requestId,
              'error': message,
              'stack': stackTrace.toString(),
            },
          );
        }
        return jsonResponse(
          {
            'error': statusCode >= 500 ? 'internal_error' : 'device_error',
            'message': message,
            'requestId': requestId,
          },
          statusCode: statusCode,
        );
      } catch (e, stackTrace) {
        final requestId = requestIdFor(request);
        logError(
          '[ERR][$requestId] Unhandled error: $e',
          fields: {
            'requestId': requestId,
            'error': e.toString(),
            'stack': stackTrace.toString(),
          },
        );
        // Surface a sanitized, truncated message even for unanticipated
        // exceptions. This is a self-hosted appliance accessed by its owner, so
        // "PHD2 launch failed: ..." / "session 1 not found" is far more useful
        // than a bare `internal_error` — and it turns the many precondition /
        // environment failures (a guider not running, no report data, a feature
        // not configured) into something a remote client can actually act on.
        // The full cause + stack stay server-side (logged above). Auth failures
        // never reach here (they're BadRequestError / HandlerFailure above).
        final detail = _sanitizeErrorDetail(e);
        return jsonInternalServerError({
          'error': 'internal_error',
          if (detail.isNotEmpty) 'message': detail,
          'requestId': requestId,
        });
      }
    };
  };
}
