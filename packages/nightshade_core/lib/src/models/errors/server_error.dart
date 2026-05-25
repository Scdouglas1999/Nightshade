// [Wave 6D error parsing]
//
// Structured representation of the headless server's error envelope.
//
// Wave 1-onwards the headless API returns errors as JSON like:
//
//     { "code": "pairing_required",
//       "message": "No paired token presented",
//       "details": { "deviceId": "ascom:camera:foo" } }
//
// Old client code (and the existing `NightshadeError.fromString`) flattened
// those into a single string and the UI lost the machine-readable `code`.
// [ServerError] preserves both halves so mobile SnackBars can render
// "<message> (<code>)" and severity-tinted callsites can branch on the
// HTTP status without parsing the message text.
//
// This type lives alongside [NightshadeError] rather than replacing it:
// [NightshadeError] is the richer cross-FFI model used by Rust-originated
// failures; [ServerError] is the thin wire-envelope shape that comes back
// over HTTP from the headless API. Treating them separately keeps each
// faithful to its source of truth.

class ServerError implements Exception {
  /// Machine-readable error code (e.g. 'pairing_required',
  /// 'rate_limited', 'device_busy'). Lower-snake_case by convention.
  final String code;

  /// Human-readable message intended for direct display.
  final String message;

  /// HTTP status code the response carried. Null when [ServerError] was
  /// constructed from a non-HTTP source (e.g. a WebSocket error frame
  /// that uses the same envelope shape).
  final int? httpStatus;

  /// Optional structured details map. Free-form per-endpoint, but always
  /// JSON-serializable so it can be logged and round-tripped over the
  /// wire intact.
  final Map<String, dynamic>? details;

  const ServerError({
    required this.code,
    required this.message,
    this.httpStatus,
    this.details,
  });

  /// Decode the headless server's error envelope. Returns null when the
  /// JSON doesn't look like the envelope shape, so callers can fall
  /// through to a less-structured parser (e.g.
  /// [NightshadeError.fromString]).
  static ServerError? tryFromJson(
    Map<String, dynamic> json, {
    int? httpStatus,
  }) {
    final rawCode = json['code'];
    final rawMessage = json['message'];
    // The envelope is identified by the presence of BOTH `code` and
    // `message` as strings. Looser matching (`code` only, `error` only,
    // etc.) is handled by NetworkBackend._parseErrorResponse's legacy
    // fallback so this constructor doesn't have to guess.
    if (rawCode is! String || rawCode.isEmpty) return null;
    if (rawMessage is! String || rawMessage.isEmpty) return null;

    Map<String, dynamic>? details;
    final rawDetails = json['details'];
    if (rawDetails is Map<String, dynamic>) {
      details = rawDetails;
    } else if (rawDetails is Map) {
      details = rawDetails.cast<String, dynamic>();
    }

    return ServerError(
      code: rawCode,
      message: rawMessage,
      httpStatus: httpStatus,
      details: details,
    );
  }

  /// True if the underlying status code indicates a client-side problem
  /// (auth, validation, rate limit, etc.). Used by the mobile SnackBar
  /// helper to choose an amber tint over the harsher red.
  bool get isClientError {
    final status = httpStatus;
    return status != null && status >= 400 && status < 500;
  }

  /// True if the underlying status code indicates a server-side failure.
  bool get isServerError {
    final status = httpStatus;
    return status != null && status >= 500;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (details != null) 'details': details,
      };

  @override
  String toString() {
    final statusSuffix = httpStatus != null ? ' [HTTP $httpStatus]' : '';
    return '$message ($code)$statusSuffix';
  }
}
