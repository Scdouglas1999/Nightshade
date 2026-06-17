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

import 'dart:io';

import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../auth/pairing_attempt_tracker.dart';
import '../auth/pairing_service.dart';
import '../auth_policy.dart';
import '../request_context.dart';
import '../response_helpers.dart';
import '../validation.dart';

/// How a brand-new device is allowed to pair.
///
/// [lanOpen] (the default) lets a device on the same private LAN pair with one
/// tap and no code — being on the rig's own network is the trust boundary, the
/// same model as Chromecast/Sonos/ASIAIR. Remote (tailnet/relay/public) clients
/// always fall back to the code flow regardless of mode. [codeRequired] tightens
/// even LAN pairing to require the code (surfaced via the browser `/pair` page).
enum PairingMode {
  lanOpen('lan-open'),
  codeRequired('code-required');

  const PairingMode(this.wire);

  /// Stable wire/string form used in config + `/api/info`.
  final String wire;

  static PairingMode fromWire(String? value) => switch (value?.trim()) {
    'code-required' || 'codeRequired' || 'code' => PairingMode.codeRequired,
    _ => PairingMode.lanOpen,
  };
}

/// Returns the real TCP source [InternetAddress] when it is a non-loopback
/// private LAN address (RFC1918 / link-local), else null.
///
/// Trust is decided from the socket address shelf_io records
/// (`shelf.io.connection_info`), NEVER from client-supplied headers like
/// `x-forwarded-for` (those are trivially spoofable). Loopback is deliberately
/// rejected: a self-hosted relay tunnels remote clients in over loopback, so
/// treating loopback as "local" would let a remote relay client one-tap pair.
/// Tailnet CGNAT (100.64.0.0/10, fd7a:115c::/32) is rejected too — remote
/// access keeps using the code flow.
InternetAddress? lanTrustedSourceAddress(Request request) {
  final info = request.context['shelf.io.connection_info'];
  if (info is! HttpConnectionInfo) return null;
  final addr = info.remoteAddress;
  return isPrivateLanAddress(addr) ? addr : null;
}

/// True for non-loopback RFC1918 / link-local / ULA addresses, excluding the
/// Tailscale CGNAT ranges. See [lanTrustedSourceAddress] for the rationale.
bool isPrivateLanAddress(InternetAddress addr) {
  if (addr.isLoopback) return false;
  final bytes = addr.rawAddress;
  if (addr.type == InternetAddressType.IPv4 && bytes.length == 4) {
    final a = bytes[0], b = bytes[1];
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    // 100.64.0.0/10 (CGNAT/Tailscale) and all public ranges → not LAN-trusted.
    return false;
  }
  if (addr.type == InternetAddressType.IPv6 && bytes.length == 16) {
    // Tailscale ULA fd7a:115c::/32 sits inside fc00::/7 — exclude it first.
    if (bytes[0] == 0xfd &&
        bytes[1] == 0x7a &&
        bytes[2] == 0x11 &&
        bytes[3] == 0x5c) {
      return false;
    }
    if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
      return true; // fe80::/10 link-local
    }
    return false;
  }
  return false;
}

/// Function the handler calls when a successful verify mints a fresh
/// session token. The server-side implementation appends the token +
/// scope to its in-memory `_pairedSessionTokens` map so subsequent
/// authenticated requests resolve immediately.
typedef RecordPairedSession =
    void Function(String sessionToken, HeadlessTokenScope scope);

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

  /// Resolves the active pairing policy at request time (operators can change
  /// it without restarting in future; today it's fixed at boot).
  final PairingMode Function() pairingMode;
  final LoggingService logger;

  PairingHandlers({
    required this.pairingAttempts,
    required this.ensurePairingService,
    required this.recordPairedSession,
    required this.rateLimitClientKey,
    required this.pairingPrintCodes,
    required this.pairingMode,
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
          'retryAfterSeconds': lockedFor.inSeconds < 1
              ? 1
              : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          requestIdHeader: requestId,
          'retry-after': (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds)
              .toString(),
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

    // when the headless operator passed --pairing-print-codes (or set
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
        'expiresInSeconds': result.expiresAt
            .difference(DateTime.now())
            .inSeconds,
      },
      headers: {requestIdHeader: requestId},
    );
  }

  /// `POST /api/pairing/lan-claim` — one-tap pairing for a device on the local
  /// network. No code required: see [lanTrustedSourceAddress] for the trust
  /// model. Accepted only when the pairing mode is [PairingMode.lanOpen] AND the
  /// TCP source is a non-loopback private LAN address. Always mints a
  /// `control`-scoped token (admin needs the explicit code flow). Rate-limited
  /// like the code endpoints.
  ///
  /// Body (all optional): `{deviceId?, deviceName?, deviceType?}`.
  Future<Response> handleLanClaim(Request request) async {
    final requestId = requestIdFrom(request);
    final clientKey = rateLimitClientKey(request);

    final lockedFor = pairingAttempts.retryAfter(clientKey);
    if (lockedFor != null) {
      final retryAfter = lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds;
      return jsonRateLimited(
        {
          'error': 'Pairing attempts temporarily locked',
          'retryAfterSeconds': retryAfter,
          'requestId': requestId,
        },
        headers: {
          requestIdHeader: requestId,
          'retry-after': retryAfter.toString(),
        },
      );
    }

    if (pairingMode() != PairingMode.lanOpen) {
      return jsonForbidden(
        {
          'error': 'lan_pairing_disabled',
          'message':
              'One-tap LAN pairing is disabled on this appliance. Pair with a '
              'code instead.',
          'pairingMode': pairingMode().wire,
          'requestId': requestId,
        },
        headers: {requestIdHeader: requestId},
      );
    }

    final source = lanTrustedSourceAddress(request);
    if (source == null) {
      _logWarning(
        '[PAIR][$requestId] lan-claim refused: source $clientKey is not a '
        'trusted private-LAN address',
      );
      return jsonForbidden(
        {
          'error': 'not_local_network',
          'message':
              'One-tap pairing is only available from the local network. For '
              'remote access, pair with a code.',
          'requestId': requestId,
        },
        headers: {requestIdHeader: requestId},
      );
    }

    final payload = await _readJsonBodyTolerant(request);
    final deviceId =
        optionalString(payload, 'deviceId', maxLength: 128) ??
        'lan:${source.address.replaceAll(':', '_')}';
    final deviceName =
        optionalString(payload, 'deviceName', maxLength: 128) ?? 'LAN device';
    final deviceType =
        optionalString(payload, 'deviceType', maxLength: 32) ?? 'mobile';

    // Mint through the exact tested code path: generate a code server-side and
    // consume it immediately. The code is never transmitted, so this reuses all
    // the verify-path persistence/expiry behaviour without a parallel mint.
    final service = ensurePairingService();
    final start = await service.startPairing();
    final verify = await service.verifyPairing(
      code: start.code,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
    );
    if (verify.outcome != PairingVerifyOutcome.success ||
        verify.sessionToken == null) {
      _logError(
        '[PAIR][$requestId] lan-claim internal mint failed: ${verify.outcome}',
      );
      return jsonInternalServerError(
        {
          'error': 'lan_claim_failed',
          'message': 'Could not complete LAN pairing.',
          'requestId': requestId,
        },
        headers: {requestIdHeader: requestId},
      );
    }

    final token = verify.sessionToken!;
    recordPairedSession(token, HeadlessTokenScope.control);
    pairingAttempts.clear(clientKey);
    _logInfo(
      '[PAIR][$requestId] LAN one-tap pairing granted to device=$deviceId '
      'from ${source.address}',
    );
    return jsonOk(
      {
        'token': token,
        'tokenScope': headlessTokenScopeName(HeadlessTokenScope.control),
        'expiresAt': verify.expiresAt!.toUtc().toIso8601String(),
        'pairing': 'lan',
      },
      headers: {requestIdHeader: requestId},
    );
  }

  /// Reads a JSON object body, tolerating an empty/absent body (every field on
  /// lan-claim is optional, so a bodyless POST must not 400).
  Future<Map<String, dynamic>> _readJsonBodyTolerant(Request request) async {
    try {
      return await readJsonObject(request);
    } on BadRequestError {
      return <String, dynamic>{};
    }
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
          'retryAfterSeconds': lockedFor.inSeconds < 1
              ? 1
              : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          requestIdHeader: requestId,
          'retry-after': (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds)
              .toString(),
        },
      );
    }

    final payload = await readJsonObject(request);
    final code = requireString(payload, 'code', maxLength: 32);
    // deviceId/deviceName/deviceType identify the dashboard instance for the
    // PairingDatabase. Defaults are conservative so a minimal browser client
    // can pair without sending hardware fingerprints.
    final deviceId =
        optionalString(payload, 'deviceId', maxLength: 128) ??
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
        _logWarning('[PAIR][$requestId] Invalid pairing code from $clientKey');
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
        _logWarning('[PAIR][$requestId] Expired pairing code from $clientKey');
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
        _logWarning('[PAIR][$requestId] Reused pairing code from $clientKey');
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
