import 'dart:convert';

import 'package:http/http.dart' as http;

import 'server_compatibility.dart';

/// Result of `POST /api/pairing/start`.
class RemotePairingStartResult {
  final DateTime expiresAt;
  final int expiresInSeconds;

  const RemotePairingStartResult({
    required this.expiresAt,
    required this.expiresInSeconds,
  });

  factory RemotePairingStartResult.fromJson(Map<String, dynamic> json) {
    final expiresAtRaw = json['expiresAt'] as String?;
    final expiresAt = expiresAtRaw != null
        ? DateTime.parse(expiresAtRaw).toUtc()
        : DateTime.now().toUtc().add(const Duration(minutes: 5));
    return RemotePairingStartResult(
      expiresAt: expiresAt,
      expiresInSeconds: json['expiresInSeconds'] as int? ??
          expiresAt.difference(DateTime.now().toUtc()).inSeconds,
    );
  }
}

/// Result of `POST /api/pairing/verify`.
class RemotePairingVerifyResult {
  final bool success;
  final String? token;
  final String? tokenScope;
  final DateTime? expiresAt;
  final String? error;
  final String? message;
  final int? statusCode;

  const RemotePairingVerifyResult({
    required this.success,
    this.token,
    this.tokenScope,
    this.expiresAt,
    this.error,
    this.message,
    this.statusCode,
  });

  factory RemotePairingVerifyResult.successFromJson(
    Map<String, dynamic> json,
  ) {
    final expiresAtRaw = json['expiresAt'] as String?;
    return RemotePairingVerifyResult(
      success: true,
      token: json['token'] as String?,
      tokenScope: json['tokenScope'] as String?,
      expiresAt: expiresAtRaw != null ? DateTime.parse(expiresAtRaw) : null,
    );
  }

  factory RemotePairingVerifyResult.failure({
    required int statusCode,
    required Map<String, dynamic> body,
  }) {
    return RemotePairingVerifyResult(
      success: false,
      statusCode: statusCode,
      error: body['error'] as String?,
      message: body['message'] as String? ?? body['error'] as String?,
    );
  }
}

/// HTTP client for the headless pairing endpoints (`/api/pairing/*`).
///
/// Pairing codes are entered by the operator on the desktop (or embedded in a
/// QR payload). The six-digit dashboard flow and the `WORD-WORD-NNNN` GUI flow
/// share the same Drift-backed session table via [TokenManager].
class RemotePairingClient {
  final String host;
  final int port;
  final Duration timeout;

  const RemotePairingClient({
    required this.host,
    required this.port,
    this.timeout = const Duration(seconds: 15),
  });

  Uri _uri(String path) => Uri.parse('http://$host:$port$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        NightshadeServerCompatibility.apiVersionHeader:
            NightshadeServerCompatibility.clientApiVersion.format(),
      };

  /// Opens a pairing session on the desktop host. The pairing code itself is
  /// shown on the desktop UI / QR — it is intentionally omitted from the HTTP
  /// body so passive network observers cannot harvest it.
  Future<RemotePairingStartResult> start() async {
    final response = await http
        .post(_uri('/api/pairing/start'), headers: _headers)
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw RemotePairingException(
        'Pairing start failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return RemotePairingStartResult.fromJson(decoded);
  }

  /// Claims a pairing code and returns a scoped bearer token.
  ///
  /// [requestedScope] defaults to `control`. Pass `admin` only when the
  /// operator explicitly opts in on the mobile/tablet UI.
  Future<RemotePairingVerifyResult> verify({
    required String code,
    required String deviceId,
    required String deviceName,
    String deviceType = 'mobile',
    String requestedScope = 'control',
  }) async {
    final response = await http
        .post(
          _uri('/api/pairing/verify'),
          headers: _headers,
          body: jsonEncode({
            'code': code.trim(),
            'deviceId': deviceId,
            'deviceName': deviceName,
            'deviceType': deviceType,
            'requestedScope': requestedScope,
          }),
        )
        .timeout(timeout);

    final dynamic decoded = response.body.isNotEmpty
        ? jsonDecode(response.body)
        : <String, dynamic>{};
    final body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    if (response.statusCode == 200) {
      return RemotePairingVerifyResult.successFromJson(body);
    }

    return RemotePairingVerifyResult.failure(
      statusCode: response.statusCode,
      body: body,
    );
  }
}

class RemotePairingException implements Exception {
  final String message;
  const RemotePairingException(this.message);

  @override
  String toString() => 'RemotePairingException: $message';
}
