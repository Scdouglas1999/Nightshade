import 'dart:convert';

import 'package:shelf/shelf.dart';

const jsonContentType = 'application/json';
const jsonResponseHeaders = {'content-type': jsonContentType};

Response jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {
      ...jsonResponseHeaders,
      if (headers != null) ...headers,
    },
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
