/// HTTP handlers for the headless API's first-run pairing flow (audit
/// §2.1).
///
/// The desktop console prints a 6-digit code; the dashboard or mobile
/// companion user retypes it into the Pair sheet, and the server mints
/// a long-lived bearer token in exchange. The code itself is NEVER
/// returned in any HTTP response body so a network observer (or a
/// logging proxy) cannot harvest it without console access — only the
/// operator-visible stdout/log breadcrumb prints the code.
///
/// Endpoints owned by this class:
///   * `POST /api/pairing/start` — begin a fresh pairing attempt. The
///     code is logged + (optionally) printed to stdout when
///     [PairingHandlerContext.pairingPrintCodes] is true.
///   * `POST /api/pairing/verify` — exchange a typed code for a session
///     token. Successful verify mints a `control`-scoped token by
///     default; `admin` is opt-in only via `requestedScope=admin`.
///   * `GET /api/pairing/active` — admin-only diagnostic listing of
///     unused, unexpired pairing codes (so a headless operator on a
///     paired admin client can retrieve a code without watching
///     stdout).
///
/// All three endpoints are gated by [PairingAttemptTracker] so a brute-
/// force on the verify endpoint locks the offending client out for the
/// configured backoff window.
library;

import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../auth/pairing_attempt_tracker.dart';
import '../auth/pairing_service.dart';
import '../auth_policy.dart';
import '../request_context.dart';
import '../response_helpers.dart';
import '../validation.dart';

/// Function the handler calls when a successful verify mints a fresh
/// session token. The server-side implementation appends the token +
/// scope to its in-memory `_pairedSessionTokens` map so subsequent
/// authenticated requests resolve immediately.
typedef RecordPairedSession = void Function(
  String sessionToken,
  HeadlessTokenScope scope,
);

/// Function the handler calls to look up the [PairingService], lazily
/// constructing one on first use. The server's implementation also
/// (re-)installs the revocation listener whenever a fresh service is
/// minted so revoke/expiry events propagate to the in-memory map
/// regardless of whether the service was injected at boot or lazily
/// created here.
typedef EnsurePairingService = PairingService Function();

/// Function the handler calls to compute a stable rate-limit key for
/// the request (typically `x-forwarded-for` ?? `x-real-ip` ?? the
/// connected client host).
typedef RateLimitClientKey = String Function(Request request);

/// HTTP handlers for the pairing endpoints. Constructed once per
/// server; the lifecycle callbacks make the dependency on the server's
/// private state explicit so the handler stays decoupled from the
/// HeadlessApiServer class.
class PairingHandlers {
  final PairingAttemptTracker pairingAttempts;
  final EnsurePairingService ensurePairingService;
  final RecordPairedSession recordPairedSession;
  final RateLimitClientKey rateLimitClientKey;
  final bool pairingPrintCodes;
  final LoggingService logger;

  PairingHandlers({
    required this.pairingAttempts,
    required this.ensurePairingService,
    required this.recordPairedSession,
    required this.rateLimitClientKey,
    required this.pairingPrintCodes,
    required this.logger,
  });

  void _logInfo(String message) =>
      logger.info(message, source: 'PairingHandlers');
  void _logWarning(String message) =>
      logger.warning(message, source: 'PairingHandlers');
  void _logError(String message) =>
      logger.error(message, source: 'PairingHandlers');

  /// `POST /api/pairing/start` — begin a fresh pairing attempt.
  ///
  /// Rate-limited by [PairingAttemptTracker] keyed on the client's IP
  /// (or the supplied forwarded-for header). On success the response
  /// body intentionally omits the code itself — only the
  /// `expiresAt` / `expiresInSeconds` envelope is returned; the code
  /// goes to the operator's structured log and, when
  /// [pairingPrintCodes] is true, to stdout.
  Future<Response> handlePairingStart(Request request) async {
    final requestId = requestIdFrom(request);
    final clientKey = rateLimitClientKey(request);

    final lockedFor = pairingAttempts.retryAfter(clientKey);
    if (lockedFor != null) {
      _logWarning(
        '[PAIR][$requestId] start rate-limited from $clientKey '
        'retry=${lockedFor.inSeconds}s',
      );
      return jsonRateLimited(
        {
          'error': 'Pairing attempts temporarily locked',
          'retryAfterSeconds':
              lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          requestIdHeader: requestId,
          'retry-after':
              (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds).toString(),
        },
      );
    }

    final service = ensurePairingService();
    final result = await service.startPairing();

    // The code itself goes only to the operator's stdout/log so an off-host
    // attacker cannot harvest it from HTTP traces. The dashboard polls for
    // success on /api/pairing/verify with the user-typed code.
    _logInfo(
      '[PAIR][$requestId] Pairing started; enter this code on the companion '
      'within ${service.codeLifetime.inMinutes} minutes: ${result.code}',
    );

    // P0-3: when the headless operator passed --pairing-print-codes (or set
    // NIGHTSHADE_PAIRING_PRINT_CODES=true), echo the code to stdout. Without
    // this, a Pi-headless first-run has no way to retrieve the code — the
    // HTTP response intentionally omits it and the structured log file is
    // not always tailed. Operators must opt in to this print so accidental
    // log capture in a CI/recording context does not leak the code.
    if (pairingPrintCodes) {
      // ignore: avoid_print
      print(
        '[PAIRING] code=${result.code} '
        'expires=${result.expiresAt.toUtc().toIso8601String()}',
      );
    }
    return jsonOk(
      {
        'expiresAt': result.expiresAt.toUtc().toIso8601String(),
        'expiresInSeconds':
            result.expiresAt.difference(DateTime.now()).inSeconds,
      },
      headers: {requestIdHeader: requestId},
    );
  }

  /// `GET /api/pairing/active` — admin-only diagnostic listing of
  /// currently-valid pairing sessions. Behind the auth middleware (the
  /// path is NOT in `publicPaths`) and gated to admin scope via
  /// `_adminOnlyPaths`; the handler itself does not need a secondary
  /// scope check.
  ///
  /// Returns `{ sessions: [{code, expiresAt, expiresInSeconds}, ...] }`.
  Future<Response> handlePairingActiveList(Request request) async {
    final requestId = requestIdFrom(request);
    try {
      final service = ensurePairingService();
      // Query the underlying Drift DB directly — TokenManager has no need to
      // expose unused pairing sessions because the only consumer is this
      // admin-facing diagnostic. Walking the DB rather than caching in
      // memory keeps the source of truth in one place.
      final allSessions = await service.database
          .select(service.database.pairingSessions)
          .get();
      final now = DateTime.now();
      final sessions = <Map<String, Object?>>[];
      for (final row in allSessions) {
        if (row.isUsed) continue;
        if (!row.expiresAt.isAfter(now)) continue;
        sessions.add({
          'code': row.pairingCode,
          'expiresAt': row.expiresAt.toUtc().toIso8601String(),
          'expiresInSeconds': row.expiresAt.difference(now).inSeconds,
        });
      }
      return jsonOk(
        {'sessions': sessions},
        headers: {requestIdHeader: requestId},
      );
    } catch (e) {
      _logError('[PAIR][$requestId] Failed to list active sessions: $e');
      return jsonInternalServerError(
        {'error': 'Failed to list active pairing sessions: $e'},
        headers: {requestIdHeader: requestId},
      );
    }
  }

  /// `POST /api/pairing/verify` — exchange a typed code for a session
  /// token.
  ///
  /// Body: `{code, deviceId?, deviceName?, deviceType?, requestedScope?}`.
  /// Defaults to `control` scope (imaging + devices); `admin` is opt-in
  /// via `requestedScope=admin` so a scanned QR or LAN pairing cannot
  /// silently gain backup/filesystem privileges.
  Future<Response> handlePairingVerify(Request request) async {
    final requestId = requestIdFrom(request);
    final clientKey = rateLimitClientKey(request);

    final lockedFor = pairingAttempts.retryAfter(clientKey);
    if (lockedFor != null) {
      _logWarning(
        '[PAIR][$requestId] verify rate-limited from $clientKey '
        'retry=${lockedFor.inSeconds}s',
      );
      return jsonRateLimited(
        {
          'error': 'Pairing attempts temporarily locked',
          'retryAfterSeconds':
              lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          requestIdHeader: requestId,
          'retry-after':
              (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds).toString(),
        },
      );
    }

    final payload = await readJsonObject(request);
    final code = requireString(payload, 'code', maxLength: 32);
    // deviceId/deviceName/deviceType identify the dashboard instance for the
    // PairingDatabase. Defaults are conservative so a minimal browser client
    // can pair without sending hardware fingerprints.
    final deviceId = optionalString(payload, 'deviceId', maxLength: 128) ??
        'dashboard:${clientKey.replaceAll(':', '_')}';
    final deviceName =
        optionalString(payload, 'deviceName', maxLength: 128) ?? 'Dashboard';
    final deviceType =
        optionalString(payload, 'deviceType', maxLength: 32) ?? 'browser';
    final requestedScopeRaw =
        optionalString(payload, 'requestedScope', maxLength: 16) ?? 'control';
    final requestedScope = parseHeadlessTokenScope(requestedScopeRaw);

    final service = ensurePairingService();
    final result = await service.verifyPairing(
      code: code,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
    );

    switch (result.outcome) {
      case PairingVerifyOutcome.success:
        final token = result.sessionToken!;
        // Default to control (imaging + devices). Admin is opt-in only via
        // requestedScope=admin so a scanned QR or LAN pairing cannot silently
        // gain backup/filesystem privileges.
        final grantedScope = requestedScope == HeadlessTokenScope.admin
            ? HeadlessTokenScope.admin
            : HeadlessTokenScope.control;
        recordPairedSession(token, grantedScope);
        pairingAttempts.clear(clientKey);
        _logInfo(
          '[PAIR][$requestId] Pairing succeeded for device=$deviceId '
          'scope=${headlessTokenScopeName(grantedScope)}',
        );
        return jsonOk(
          {
            'token': token,
            'tokenScope': headlessTokenScopeName(grantedScope),
            'expiresAt': result.expiresAt!.toUtc().toIso8601String(),
          },
          headers: {requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.invalidCode:
        pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Invalid pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'invalid_pairing_code',
            'message': 'The pairing code is not recognised.',
            'requestId': requestId,
          },
          headers: {requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.codeExpired:
        pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Expired pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'pairing_code_expired',
            'message':
                'The pairing code has expired. Request a new one from the desktop console.',
            'requestId': requestId,
          },
          headers: {requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.codeAlreadyUsed:
        pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Reused pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'pairing_code_already_used',
            'message':
                'The pairing code has already been claimed. Request a new one.',
            'requestId': requestId,
          },
          headers: {requestIdHeader: requestId},
        );
    }
  }
}
