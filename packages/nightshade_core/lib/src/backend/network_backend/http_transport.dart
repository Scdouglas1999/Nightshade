part of '../network_backend.dart';

extension _NetworkBackendHttpTransport on _NetworkBackendTransport {
  String _nextRequestId(String endpoint) {
    _requestCounter = (_requestCounter + 1) % 0xFFFFF;
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = _requestCounter.toRadixString(36);
    final safeEndpoint = endpoint
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();
    return 'nb-$ts-$seq-${safeEndpoint.isEmpty ? 'request' : safeEndpoint}';
  }

  /// Add authentication, compatibility, and trace headers to HTTP requests.
  Map<String, String> _addAuthHeaders(
    Map<String, String> headers, {
    required String endpoint,
  }) {
    headers[RemoteApiCompatibility.apiVersionHeader] =
        RemoteApiCompatibility.clientApiVersion.format();
    headers[_NetworkBackendTransport._requestIdHeader] =
        _nextRequestId(endpoint);
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  Map<String, String> _buildRequestHeaders(
    String endpoint, {
    bool jsonContent = false,
    Map<String, String>? extraHeaders,
  }) {
    final headers = _addAuthHeaders({}, endpoint: endpoint);
    if (jsonContent) {
      headers[HttpHeaders.contentTypeHeader] = 'application/json';
    }
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<http.Response> _sendWithAuthRefresh({
    required String endpoint,
    required Future<http.Response> Function(Map<String, String> headers) send,
    bool jsonContent = false,
    Map<String, String>? extraHeaders,
  }) async {
    var headers = _buildRequestHeaders(
      endpoint,
      jsonContent: jsonContent,
      extraHeaders: extraHeaders,
    );
    final response = await send(headers);
    if (response.statusCode != 401 || refreshAuthToken == null) {
      return response;
    }

    final previousToken = authToken;
    final refreshedToken = await refreshAuthToken!();
    if (refreshedToken == null ||
        refreshedToken.isEmpty ||
        refreshedToken == previousToken) {
      return response;
    }

    authToken = refreshedToken;
    headers = _buildRequestHeaders(
      endpoint,
      jsonContent: jsonContent,
      extraHeaders: extraHeaders,
    );
    return send(headers);
  }

  /// Determine if an HTTP exception is a transient failure that can be retried
  bool _isTransientFailure(dynamic error) {
    // Check for structured NightshadeError
    if (error is dart_error.NightshadeError) {
      return error.isRecoverable;
    }
    // [Wave 6D error parsing] — the headless envelope's httpStatus tells
    // us whether the request should be retried. Mirror the same status
    // ranges as [_isTransientStatusCode] so retry behaviour is
    // consistent whether the failure was decoded into a [ServerError] or
    // a fallback [NightshadeError].
    if (error is ServerError) {
      final status = error.httpStatus;
      if (status != null) {
        return _isTransientStatusCode(status);
      }
      return false;
    }
    if (error is SocketException) {
      // Network errors are transient
      return true;
    }
    if (error is TimeoutException) {
      // Timeouts are transient
      return true;
    }
    if (error is HttpException) {
      // Connection reset, broken pipe, etc.
      return true;
    }
    if (error is Exception) {
      final errorStr = error.toString().toLowerCase();
      // Check for common transient error messages
      if (errorStr.contains('connection') ||
          errorStr.contains('timeout') ||
          errorStr.contains('reset') ||
          errorStr.contains('refused') ||
          errorStr.contains('network')) {
        return true;
      }
    }
    return false;
  }

  /// Check if an HTTP status code indicates a transient failure
  bool _isTransientStatusCode(int statusCode) {
    // 408 Request Timeout, 429 Too Many Requests, 500 Internal Server Error,
    // 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  /// Parse an error response from the server.
  ///
  /// Attempts to parse structured error JSON from the response body.
  /// Falls back to creating an error from the status code and endpoint.
  ///
  /// Return type is [Exception] rather than the narrower
  /// [dart_error.NightshadeError] because the headless server's new
  /// envelope ({code, message, details}) is surfaced as a typed
  /// [ServerError] — see the [Wave 6D error parsing] branch below.
  /// Existing callers `throw` the result so the widened type doesn't
  /// change their behaviour; the retry helper's
  /// `_isTransientFailure` accepts any Object via duck-typing.
  Exception _parseErrorResponse(
    int statusCode,
    String responseBody,
    String method,
    String endpoint,
  ) {
    // Try to parse as structured error JSON
    try {
      final json = jsonDecode(responseBody);
      if (json is Map<String, dynamic>) {
        // [Wave 6D error parsing] — the headless server emits a
        // {code, message, details} envelope on every 4xx/5xx; prefer
        // that shape over the legacy and category formats. The check
        // is positional (both keys, both non-empty strings) so we
        // don't accidentally swallow the richer NightshadeError
        // envelope, which always carries `category`.
        if (!json.containsKey('category')) {
          final serverError =
              ServerError.tryFromJson(json, httpStatus: statusCode);
          if (serverError != null) {
            return serverError;
          }
        }

        // Check for full structured error format
        if (json.containsKey('category') && json.containsKey('message')) {
          return dart_error.NightshadeError.fromJson(json);
        }

        // Check for legacy error format: {error: 'message', message: 'details'}
        if (json.containsKey('error') || json.containsKey('message')) {
          final errorMsg = json['error'] as String? ??
              json['message'] as String? ??
              'Unknown error';
          final detailMsg =
              json['message'] as String? ?? json['details'] as String? ?? '';
          final fullMessage = detailMsg.isNotEmpty && detailMsg != errorMsg
              ? '$errorMsg: $detailMsg'
              : errorMsg;

          return dart_error.NightshadeError.fromString(fullMessage);
        }
      }
    } catch (e, stackTrace) {
      // Why: the server may return a non-JSON body (HTML error page, plain
      // text from a misbehaving proxy, empty body). The structured-error
      // path is best-effort; the HTTP-status fallback below always produces
      // a useful NightshadeError. Logging at FINE keeps the dev console
      // signal-only when servers regularly return non-JSON 5xx pages.
      // Justification: trace-level (500) — diagnostic-only for the
      // best-effort JSON decode path; HTTP-status fallback below is the
      // real error surface.
      developer.log(
        '[NetworkBackend] _parseErrorResponse JSON decode failed '
        '(status=$statusCode endpoint=$endpoint): $e',
        name: 'NetworkBackend',
        level: 500,
        error: e,
        stackTrace: stackTrace,
      );
    }

    // Fallback: create error from HTTP status
    final isTransient = _isTransientStatusCode(statusCode);
    return dart_error.NightshadeError(
      category: statusCode == 404
          ? dart_error.BackendErrorCategory.connection
          : statusCode == 400
              ? dart_error.BackendErrorCategory.validation
              : statusCode == 408 || statusCode == 504
                  ? dart_error.BackendErrorCategory.timeout
                  : dart_error.BackendErrorCategory.system,
      message: 'HTTP $statusCode: $method $endpoint failed',
      isRecoverable: isTransient,
      isTimeout: statusCode == 408 || statusCode == 504,
    );
  }

  /// Retry a request with exponential backoff
  /// Max 3 attempts for transient failures only
  Future<T> _retryableRequest<T>(
    Future<T> Function() request, {
    int maxAttempts = 3,
    Duration? timeout,
  }) async {
    // Null `timeout` defers to the host-tuned [requestTimeout] (30 s on LAN,
    // 60 s on a tailnet). Callers that pass an explicit value override the
    // tuning.
    final effectiveTimeout = timeout ?? requestTimeout;
    int attempt = 0;
    Exception? lastException;

    while (attempt < maxAttempts) {
      try {
        return await request().timeout(effectiveTimeout);
      } catch (e) {
        lastException = e as Exception;
        attempt++;

        // Check if this is the last attempt
        if (attempt >= maxAttempts) {
          developer.log(
              '[NetworkBackend] Request failed after $maxAttempts attempts: $e',
              name: 'NetworkBackend',
              level: 1000,
              error: e);
          rethrow;
        }

        // Only retry transient failures
        if (!_isTransientFailure(e)) {
          developer.log(
              '[NetworkBackend] Non-transient failure, not retrying: $e',
              name: 'NetworkBackend',
              level: 1000,
              error: e);
          rethrow;
        }

        // Calculate backoff delay: 1s, 2s, 4s
        final delay = Duration(seconds: 1 << (attempt - 1));
        developer.log(
            '[NetworkBackend] Transient failure, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts): $e',
            name: 'NetworkBackend',
            level: 900,
            error: e);
        await Future.delayed(delay);
      }
    }

    // Should never reach here, but throw last exception just in case
    throw lastException!;
  }

  Future<Map<String, dynamic>> _get(String endpoint,
      [Map<String, dynamic>? queryParams]) async {
    return _retryableRequest(() async {
      final uri = _apiUri(
        endpoint,
        queryParams?.map((k, v) => MapEntry(k, v.toString())),
      );

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        send: (headers) => _http.get(uri, headers: headers),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'GET', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Map<String, dynamic>> _post(String endpoint,
      [Map<String, dynamic>? body, Map<String, String>? extraHeaders]) async {
    return _retryableRequest(() async {
      final uri = _apiUri(endpoint);

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        jsonContent: true,
        extraHeaders: extraHeaders,
        send: (headers) => _http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<void> _delete(String endpoint) async {
    return _retryableRequest(() async {
      final uri = _apiUri(endpoint);

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        send: (headers) => _http.delete(uri, headers: headers),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'DELETE', endpoint);
      }
    });
  }

  Future<Map<String, dynamic>> _put(String endpoint,
      [Map<String, dynamic>? body]) async {
    return _retryableRequest(() async {
      final uri = _apiUri(endpoint);

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        jsonContent: true,
        send: (headers) => _http.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'PUT', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Uint8List> _downloadBytes(
    String endpoint, [
    Map<String, dynamic>? queryParams,
  ]) async {
    final downloaded = await _downloadBytesWithHeaders(endpoint, queryParams);
    return downloaded.bytes;
  }

  Future<({Uint8List bytes, Map<String, String> headers})>
      _downloadBytesWithHeaders(
    String endpoint, [
    Map<String, dynamic>? queryParams,
  ]) async {
    return _retryableRequest(() async {
      final uri = _apiUri(
        endpoint,
        queryParams?.map((k, v) => MapEntry(k, v.toString())),
      );
      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        send: (headers) => _http.get(uri, headers: headers),
      );
      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'GET', endpoint);
      }
      return (
        bytes: response.bodyBytes,
        headers: Map<String, String>.from(response.headers),
      );
    });
  }

  Future<Map<String, dynamic>> _postRaw(
    String endpoint,
    Map<String, dynamic> queryParams,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    return _retryableRequest(() async {
      final uri = _apiUri(
        endpoint,
        queryParams.map((key, value) => MapEntry(key, value.toString())),
      );

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        extraHeaders: {HttpHeaders.contentTypeHeader: contentType},
        send: (headers) => _http.post(uri, headers: headers, body: bytes),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Uint8List> _postRawBytes(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    return _retryableRequest(() async {
      final uri = _apiUri(endpoint);

      final response = await _sendWithAuthRefresh(
        endpoint: endpoint,
        jsonContent: true,
        send: (headers) => _http.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ),
      );
      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }
      return response.bodyBytes;
    });
  }

  List<T> _rowsFromJson<T>(
    Object? source,
    T Function(Map<String, dynamic>) decoder,
  ) {
    final rows = source as List? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => decoder(row.cast<String, dynamic>()))
        .toList(growable: false);
  }
}
