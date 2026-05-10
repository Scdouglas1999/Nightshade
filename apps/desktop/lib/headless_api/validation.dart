import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'response_helpers.dart';

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

  BadRequestError({
    required this.field,
    required this.expected,
    this.message,
  });

  @override
  String toString() => 'BadRequestError(field=$field, expected=$expected)';

  Map<String, Object?> toJsonBody() => {
        'error': 'invalid_request',
        'field': field,
        'expected': expected,
        if (message != null) 'message': message,
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

Map<String, dynamic> requireObject(
  Map<String, dynamic> payload,
  String field,
) {
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

List<T> requireList<T>(
  Map<String, dynamic> payload,
  String field,
) {
  final value = payload[field];
  if (value == null) {
    throw BadRequestError(field: field, expected: 'array');
  }
  if (value is! List) {
    throw BadRequestError(field: field, expected: 'array');
  }
  for (final element in value) {
    if (element is! T) {
      throw BadRequestError(
        field: field,
        expected: 'array<${T.toString()}>',
      );
    }
  }
  return value.cast<T>();
}

List<T>? optionalList<T>(
  Map<String, dynamic> payload,
  String field,
) {
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
}) {
  return (innerHandler) {
    return (request) async {
      try {
        return await innerHandler(request);
      } on BadRequestError catch (e) {
        return jsonBadRequest(e.toJsonBody());
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
        return jsonInternalServerError({
          'error': 'internal_error',
          'requestId': requestId,
        });
      }
    };
  };
}
