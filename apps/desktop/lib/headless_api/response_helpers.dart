import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonContentType = 'application/json';
const jsonResponseHeaders = {'content-type': jsonContentType};

/// Wire field name for the shared stop/abort no-op contract.
///
/// # The contract
///
/// Every endpoint that STOPS or ABORTS something (`/api/camera/abort`,
/// `/api/sequencer/stop`, `/api/stacking/stop`, `/api/framing/abort-slew`)
/// answers `200` whether or not anything was actually running — these are
/// idempotent safety operations and a panic-stop must never fail. But the
/// body MUST let the caller tell the two cases apart:
///
///   * `wasRunning: true`  — something was genuinely in progress and has now
///     been stopped.
///   * `wasRunning: false` — nothing was running; this call changed nothing.
///     The response also carries a plain-language `message` saying so.
///
/// # Why it exists
///
/// All four endpoints previously reported an action they had not performed.
/// Observed live with the sequencer idle, stacking inactive, no slew in
/// progress and the camera idle:
///
///   POST /api/sequencer/stop     -> 200 {"status":"stopped","preserveCheckpoint":true}
///   POST /api/stacking/stop      -> 200 {"status":"stopped"}
///   POST /api/framing/abort-slew -> 200 {"status":"aborted"}
///   POST /api/camera/abort       -> 200 {"status":"aborted"}
///
/// `{"status":"aborted"}` for a slew that was never running reads to an
/// operator hitting abort in a hurry as "the mount was stopped".
///
/// # Why additive rather than a new `status` value
///
/// The existing `status` strings are kept EXACTLY as they were so no pinned
/// client can break. A consumer audit (web dashboard `web_dashboard/js`,
/// the Flutter `NetworkBackend`, and the mobile app which shares it) found
/// no caller that branches on these `status` values — all four are consumed
/// as `Future<void>` / discarded promises — but keeping them stable costs
/// nothing and removes the risk entirely.
const String kWasRunningField = 'wasRunning';

/// Last line of defence for values JSON cannot represent.
///
/// `double.infinity` and `double.nan` are legitimate in-memory sentinels
/// ("no cloud front detected", "not measured yet") but have no JSON encoding,
/// so `jsonEncode` rejects them. Reaching that point used to abort the whole
/// response and surface as an opaque HTTP 500 — a client asking a perfectly
/// answerable question got an internal error instead of the answer, and the
/// one field that could not be encoded took the other twenty with it.
///
/// JSON's only honest representation of a non-finite number is null, so emit
/// null and keep the response. Handlers should still map their own sentinels
/// explicitly — this exists so that forgetting to cannot break an endpoint.
Object? _jsonSafe(Object? value) {
  if (value is double && !value.isFinite) return null;
  // Preserve the default behaviour for every other unencodable object: the
  // dynamic `toJson()` call is exactly what jsonEncode does without a
  // toEncodable hook, so unsupported types keep failing loudly as before.
  return (value as dynamic).toJson();
}

Response jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  return Response(
    statusCode,
    body: jsonEncode(body, toEncodable: _jsonSafe),
    headers: {...jsonResponseHeaders, if (headers != null) ...headers},
  );
}

Response jsonOk(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, headers: headers);
}

Response jsonCreated(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 201, headers: headers);
}

Response jsonBadRequest(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 400, headers: headers);
}

Response jsonUnauthorized(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 401, headers: headers);
}

Response jsonForbidden(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 403, headers: headers);
}

Response jsonNotFound(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 404, headers: headers);
}

Response jsonConflict(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 409, headers: headers);
}

Response jsonTooLarge(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 413, headers: headers);
}

Response jsonUpgradeRequired(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 426, headers: headers);
}

Response jsonRateLimited(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 429, headers: headers);
}

Response jsonInternalServerError(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 500, headers: headers);
}

Response jsonNotImplemented(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 501, headers: headers);
}

Response jsonServiceUnavailable(Object? body, {Map<String, String>? headers}) {
  return jsonResponse(body, statusCode: 503, headers: headers);
}

/// Emit the unified, backward-compatible error envelope (NAME-001).
///
/// The body carries BOTH the legacy and canonical keys so existing and new
/// clients are satisfied by a single response:
///
///   - `error`   — the human-readable [message]. Legacy clients that read
///                 `body['error']` as a display string keep working.
///   - `code`    — the machine-readable [code] new clients branch on.
///   - `message` — the same human string under the canonical key.
///   - `[details]` entries, spread inline.
///
/// [statusCode] is forwarded verbatim so the HTTP status for each error case
/// is unchanged. The canonical `error`/`code`/`message` keys are written last
/// so a stray same-named key inside [details] can never clobber the machine
/// code or human message.
Response jsonError({
  required String code,
  required String message,
  Map<String, dynamic>? details,
  int statusCode = 500,
  Map<String, String>? headers,
}) {
  return jsonResponse(
    {
      if (details != null) ...details,
      'error': message,
      'code': code,
      'message': message,
    },
    statusCode: statusCode,
    headers: headers,
  );
}

Response contentResponse(
  Object? body, {
  required String contentType,
  int? contentLength,
  Map<String, String>? headers,
}) {
  return Response.ok(
    body,
    headers: {
      'content-type': contentType,
      if (contentLength != null) 'content-length': contentLength.toString(),
      if (headers != null) ...headers,
    },
  );
}

Response streamResponse(
  Object? body, {
  required String contentType,
  int? contentLength,
  Map<String, String>? headers,
  Map<String, Object>? context,
}) {
  return Response.ok(
    body,
    headers: {
      'content-type': contentType,
      if (contentLength != null) 'content-length': contentLength.toString(),
      if (headers != null) ...headers,
    },
    context: context,
  );
}

Response noContentResponse({Map<String, String>? headers}) {
  return Response(204, headers: headers);
}

Response attachmentResponse(
  Object? body, {
  required String fileName,
  required String contentType,
  int? contentLength,
  Map<String, String>? headers,
}) {
  return contentResponse(
    body,
    contentType: contentType,
    contentLength: contentLength,
    headers: {
      'content-disposition': attachmentDisposition(fileName),
      if (headers != null) ...headers,
    },
  );
}

/// 206 Partial Content response for HTTP Range requests (RFC 7233).
///
/// [body] is the stream/bytes covering exactly the requested byte range.
/// [start] / [end] are inclusive byte offsets within the full resource;
/// [totalLength] is the full resource size (NOT the slice length). The
/// returned slice length is `end - start + 1` and must match what [body]
/// emits or the client will see a truncated download.
Response partialContentResponse(
  Object? body, {
  required int start,
  required int end,
  required int totalLength,
  required String contentType,
  String? fileName,
  Map<String, String>? headers,
}) {
  final sliceLength = end - start + 1;
  return Response(
    206,
    body: body,
    headers: {
      'content-type': contentType,
      'content-length': sliceLength.toString(),
      'content-range': 'bytes $start-$end/$totalLength',
      'accept-ranges': 'bytes',
      if (fileName != null)
        'content-disposition': attachmentDisposition(fileName),
      if (headers != null) ...headers,
    },
  );
}

/// 416 Requested Range Not Satisfiable per RFC 7233 §4.4. The
/// `content-range: bytes */N` header tells the client the resource size
/// so they can re-issue a valid range request.
Response rangeNotSatisfiableResponse(int totalLength, {String? reason}) {
  return Response(
    416,
    body: jsonEncode({
      'error': 'range_not_satisfiable',
      'totalLength': totalLength,
      if (reason != null) 'reason': reason,
    }),
    headers: {
      'content-type': jsonContentType,
      'content-range': 'bytes */$totalLength',
      'accept-ranges': 'bytes',
    },
  );
}

/// Parse an RFC 7233 `Range` header value. Returns `null` if the header
/// is absent. Throws [FormatException] for any malformed/unsupported
/// shape (multi-range, non-bytes unit, missing bounds, etc.) so callers
/// can map to 416. Returns the resolved inclusive `[start, end]` pair
/// against [totalLength].
({int start, int end}) parseRangeHeader(String headerValue, int totalLength) {
  final value = headerValue.trim();
  if (!value.startsWith('bytes=')) {
    throw const FormatException('Range unit must be "bytes"');
  }
  final spec = value.substring('bytes='.length).trim();
  if (spec.isEmpty) {
    throw const FormatException('Range header has no byte spec');
  }
  if (spec.contains(',')) {
    // Multi-range requests are explicitly out of scope.
    throw const FormatException('Multi-range requests are not supported');
  }
  final dashIdx = spec.indexOf('-');
  if (dashIdx < 0) {
    throw const FormatException('Range spec missing "-" separator');
  }
  final startStr = spec.substring(0, dashIdx).trim();
  final endStr = spec.substring(dashIdx + 1).trim();

  int start;
  int end;
  if (startStr.isEmpty) {
    // Suffix range: "bytes=-N" — last N bytes.
    if (endStr.isEmpty) {
      throw const FormatException('Range spec must specify start or suffix');
    }
    final suffix = int.tryParse(endStr);
    if (suffix == null || suffix <= 0) {
      throw const FormatException('Invalid suffix length');
    }
    if (suffix >= totalLength) {
      // Suffix >= total means the entire resource.
      start = 0;
      end = totalLength - 1;
    } else {
      start = totalLength - suffix;
      end = totalLength - 1;
    }
  } else {
    final parsedStart = int.tryParse(startStr);
    if (parsedStart == null || parsedStart < 0) {
      throw const FormatException('Invalid range start');
    }
    start = parsedStart;
    if (endStr.isEmpty) {
      // Open-ended: "bytes=START-" — from START to EOF.
      end = totalLength - 1;
    } else {
      final parsedEnd = int.tryParse(endStr);
      if (parsedEnd == null || parsedEnd < 0) {
        throw const FormatException('Invalid range end');
      }
      end = parsedEnd;
    }
    if (end >= totalLength) {
      // Per RFC 7233 §2.1, an end value >= length is clamped to length-1
      // when start is satisfiable. This is the standard "be liberal in
      // what you accept" handling.
      end = totalLength - 1;
    }
    if (start > end) {
      throw const FormatException('Range start exceeds end');
    }
  }

  if (start >= totalLength) {
    throw const FormatException('Range start beyond resource length');
  }
  return (start: start, end: end);
}

String attachmentDisposition(String fileName) {
  return 'attachment; filename="${safeAttachmentFilename(fileName)}"';
}

String safeAttachmentFilename(String fileName, {String fallback = 'download'}) {
  final leaf = fileName.split(RegExp(r'[\\/]')).last.trim();
  final source = leaf.isEmpty ? fallback : leaf;
  final sanitized = source
      .replaceAll(RegExp(r'[\x00-\x1F\x7F"]'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  final withoutDots = sanitized.replaceAll(RegExp(r'^\.+'), '');
  final result = withoutDots.isEmpty ? fallback : withoutDots;
  return result.length <= 120 ? result : result.substring(result.length - 120);
}
