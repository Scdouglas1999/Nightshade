import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'auth/account_service.dart';
import 'auth/token_service.dart';
import 'db/hub_database.dart';
import 'http/audit_log.dart';
import 'http/error_envelope.dart';
import 'http/rate_limiter.dart';
import 'scheduler/follow_the_night.dart';
import 'scheduler/handoff_service.dart';
import 'tiles/fusion_service.dart';
import 'tiles/subframe_service.dart';
import 'tiles/subframe_store.dart';
import 'tiles/tile_builder.dart';
import 'tiles/tile_codec.dart';
import 'tiles/tile_store.dart';

/// Configuration for a [HubServer].
class HubConfig {
  HubConfig({
    required this.databasePath,
    required this.atlasRoot,
    required this.serverSecret,
    this.name = 'Nightshade Constellation Hub',
    this.port = 8088,
    this.bindAddress = '0.0.0.0',
    this.openSignup = true,
    this.acceptsRawSubs = false,
    this.maxContributionBytes = 64 * 1024 * 1024,
    this.maxSubframeBytes = 256 * 1024 * 1024,
    this.healpixOrder = TileBuilder.atlasHealpixOrder,
    this.tilePixels = TileBuilder.tilePixels,
  });

  /// Path to the sqlite file, or `':memory:'` for tests.
  final String databasePath;

  /// Directory under which fused tile sidecars live.
  final String atlasRoot;

  /// Secret material the SHA-256 server fingerprint is derived from (and the
  /// admin bootstrap token is derived from on first run).
  final String serverSecret;

  final String name;
  final int port;
  final String bindAddress;

  /// When true, `POST /v1/accounts` is open to anyone (community hub). When
  /// false, only an admin token may create accounts (invite-only hub).
  final bool openSignup;

  /// Upload size cap for a single contribution body.
  final int maxContributionBytes;

  /// When true, the hub accepts raw FITS subframes (the
  /// `POST /v1/tiles/.../subframes` route) in addition to additive sums,
  /// advertised via `/v1/info` so a
  /// client can offer the SUBS privacy option. Default FALSE — raw subframes
  /// reveal far more than additive sums (exact pixels/pointing, re-derivable by
  /// anyone with read access), so a hub must opt in explicitly. When false the
  /// subframe routes return 405 so the client can say "this hub does not accept
  /// raw subframes".
  final bool acceptsRawSubs;

  /// Upload size cap for a single raw subframe body (larger than a sums delta).
  final int maxSubframeBytes;

  final int healpixOrder;
  final int tilePixels;
}

/// The Constellation hub: a self-hostable, multi-tenant Dart shelf service that
/// fuses additive sky-atlas tile contributions from many imagers. Mirrors the
/// conventions of `apps/desktop/lib/headless_api_server.dart` — bearer-token
/// middleware with scopes, a structured error envelope, per-identity rate
/// limiting, and an append-only audit log — over the REST surface in §5 of the
/// 5.0 contract.
class HubServer {
  HubServer(this.config)
    : _db = HubDatabase.open(config.databasePath),
      _store = TileStore(config.atlasRoot),
      _subframeStore = SubframeStore(config.atlasRoot) {
    _tokens = TokenService(_db);
    _accounts = AccountService(_db, _tokens);
    _subframes = SubframeService(db: _db, store: _subframeStore);
    _fusion = FusionService(
      db: _db,
      store: _store,
      accounts: _accounts,
      expectedTilePixels: config.tilePixels,
      expectedHealpixOrder: config.healpixOrder,
    );
    _scheduler = FollowTheNightScheduler(_db);
    _handoff = HandoffService(_db);
    _audit = AuditLog(_db);
    _rateLimiter = RateLimiter();
    _loginThrottle = LoginThrottle();
    _ensureAdminBootstrap();
  }

  final HubConfig config;
  final HubDatabase _db;
  final TileStore _store;
  final SubframeStore _subframeStore;
  late final TokenService _tokens;
  late final AccountService _accounts;
  late final FusionService _fusion;
  late final SubframeService _subframes;
  late final FollowTheNightScheduler _scheduler;
  late final HandoffService _handoff;
  late final AuditLog _audit;
  late final RateLimiter _rateLimiter;
  late final LoginThrottle _loginThrottle;

  HttpServer? _server;

  /// SHA-256 fingerprint of the hub identity, derived from [HubConfig.serverSecret]
  /// — the same derivation as `nightshade_remote_protocol/server_identity`.
  String get fingerprint => sha256
      .convert(
        utf8.encode('nightshade-remote-v1:${config.serverSecret.trim()}'),
      )
      .toString();

  /// Exposed for tests: the in-process request handler with all middleware.
  Handler get handler => _buildHandler();

  /// Direct access to the services, for tests and embedding.
  AccountService get accounts => _accounts;
  FusionService get fusion => _fusion;
  FollowTheNightScheduler get scheduler => _scheduler;
  HandoffService get handoff => _handoff;
  TokenService get tokens => _tokens;
  TileStore get store => _store;
  SubframeService get subframes => _subframes;

  /// Start listening. Returns the bound address:port for logging.
  Future<String> start() async {
    _server = await shelf_io.serve(
      _buildHandler(),
      config.bindAddress,
      config.port,
    );
    return '${_server!.address.address}:${_server!.port}';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    _db.dispose();
  }

  /// On a fresh DB, mint the first admin account from the server secret so an
  /// operator always has a way in without a chicken-and-egg signup problem. Its
  /// public key is the server fingerprint; its bootstrap token is printed by the
  /// entrypoint. Idempotent: skipped if any account already exists.
  void _ensureAdminBootstrap() {
    if (_accounts.count > 0) return;
    _accounts.signup(
      publicKey: 'admin:$fingerprint',
      displayName: 'hub-admin',
      password: config.serverSecret,
      isAdmin: true,
    );
  }

  Handler _buildHandler() {
    final router = Router();

    router.get('/v1/info', _infoHandler);
    router.post('/v1/accounts', _createAccountHandler);
    router.post('/v1/sessions', _loginHandler);

    router.get('/v1/tiles/<tileId>', _getTileHandler);
    router.post('/v1/tiles/<tileId>/contributions', _contributeHandler);
    router.delete(
      '/v1/contributions/<contributionId>',
      _retractContributionHandler,
    );

    // Raw subframe (opt-in) path — gated inside the handlers on
    // [HubConfig.acceptsRawSubs] (405 when off) rather than at the router so a
    // client gets the explanatory "this hub does not accept raw subframes"
    // status instead of a bare 404.
    router.post('/v1/tiles/<tileId>/subframes', _contributeSubframeHandler);
    router.delete('/v1/subframes/<contributionId>', _deleteSubframeHandler);

    router.get('/v1/targets', _listTargetsHandler);
    router.post('/v1/targets', _ensureTargetHandler);
    router.get('/v1/follow-the-night', _followTheNightHandler);
    router.get('/v1/handoff/<targetId>', _handoffStateHandler);
    router.post('/v1/handoff/<targetId>/claim', _handoffClaimHandler);
    router.post('/v1/handoff/<targetId>/release', _handoffReleaseHandler);

    router.get('/v1/audit', _auditHandler);

    final pipeline = const Pipeline()
        .addMiddleware(_requestIdMiddleware())
        .addMiddleware(_errorTrapMiddleware())
        .addMiddleware(_rateLimitMiddleware());
    return pipeline.addHandler(router.call);
  }

  // --- Middleware ----------------------------------------------------------

  Middleware _requestIdMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final requestId =
            request.headers['x-request-id'] ??
            DateTime.now().microsecondsSinceEpoch.toRadixString(16);
        final response = await inner(
          request.change(context: <String, Object>{'requestId': requestId}),
        );
        return response.change(
          headers: <String, String>{'x-request-id': requestId},
        );
      };
    };
  }

  Middleware _errorTrapMiddleware() => hubErrorTrapMiddleware();

  Middleware _rateLimitMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        _rateLimiter.sweep();
        final identity = _rateLimitIdentity(request);
        if (!_rateLimiter.allow(identity)) {
          final retry = _rateLimiter.retryAfterSeconds(identity);
          return HubError.rateLimited('too many requests').toResponse(
            requestId: request.context['requestId'] as String?,
            headers: <String, String>{'retry-after': '$retry'},
          );
        }
        return inner(request);
      };
    };
  }

  String _rateLimitIdentity(Request request) {
    final token = _bearer(request);
    if (token != null) return 'tok:${TokenService.hashToken(token)}';
    final conn = request.context['shelf.io.connection_info'];
    if (conn is HttpConnectionInfo) {
      return 'ip:${conn.remoteAddress.address}';
    }
    return 'anon';
  }

  // --- Auth helpers --------------------------------------------------------

  String? _bearer(Request request) {
    final header = request.headers['authorization'];
    if (header == null) return null;
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return null;
    final token = header.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Resolve and authorize a request to at least [required] scope. Returns the
  /// identity on success, or a ready-to-send error [Response] on failure.
  ({AuthIdentity? identity, Response? error}) _authorize(
    Request request,
    HubScope required,
  ) {
    final token = _bearer(request);
    final requestId = request.context['requestId'] as String?;
    if (token == null) {
      return (
        identity: null,
        error: HubError.unauthorized(
          'missing bearer token',
        ).toResponse(requestId: requestId),
      );
    }
    final identity = _tokens.resolve(token);
    if (identity == null) {
      return (
        identity: null,
        error: HubError.unauthorized(
          'invalid or expired token',
        ).toResponse(requestId: requestId),
      );
    }
    if (!identity.scope.satisfies(required)) {
      return (
        identity: null,
        error: HubError.forbidden(
          'requires ${required.name} scope',
        ).toResponse(requestId: requestId),
      );
    }
    return (identity: identity, error: null);
  }

  // --- Handlers ------------------------------------------------------------

  Response _infoHandler(Request request) {
    return hubJson(<String, Object?>{
      'name': config.name,
      'fingerprint': fingerprint,
      'version': '5.0.0',
      'healpixOrder': config.healpixOrder,
      'tilePixels': config.tilePixels,
      'selfHosted': true,
      'openSignup': config.openSignup,
      'acceptsRawSubs': config.acceptsRawSubs,
    });
  }

  Future<Response> _createAccountHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    if (!config.openSignup) {
      final auth = _authorize(request, HubScope.admin);
      if (auth.error != null) return auth.error!;
    }
    final body = await _readJson(request);
    final publicKey = body['publicKey'];
    final displayName = body['displayName'];
    if (publicKey is! String || displayName is! String) {
      return HubError.badRequest(
        'publicKey and displayName are required strings',
      ).toResponse(requestId: requestId);
    }
    final password = body['password'];
    try {
      final result = _accounts.signup(
        publicKey: publicKey,
        displayName: displayName,
        password: password is String ? password : null,
      );
      _audit.record(
        method: 'POST',
        path: '/v1/accounts',
        status: 201,
        accountId: result.account.id,
        detail: 'signup',
      );
      return hubJson(<String, Object?>{
        'accountId': result.account.id,
        'bearerToken': result.bearerToken,
        'trust': result.account.trust,
      }, statusCode: 201);
    } on AccountConflict catch (e) {
      return HubError.conflict(
        'accountConflict',
        e.message,
      ).toResponse(requestId: requestId);
    } on ArgumentError catch (e) {
      return HubError.badRequest(
        e.message?.toString() ?? 'invalid account fields',
      ).toResponse(requestId: requestId);
    }
  }

  Future<Response> _loginHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final body = await _readJson(request);
    final publicKey = body['publicKey'];
    final password = body['password'];
    if (publicKey is! String || password is! String) {
      return HubError.badRequest(
        'publicKey and password are required strings',
      ).toResponse(requestId: requestId);
    }
    // Per-account lockout, independent of the IP/token rate limiter: stop
    // credential stuffing against one account even when the attacker rotates
    // source addresses. Keyed by the submitted public key so a key that does
    // not resolve to an account is throttled identically (no existence oracle).
    final accountKey = publicKey.trim();
    _loginThrottle.sweep();
    if (_loginThrottle.isLocked(accountKey)) {
      final retry = _loginThrottle.retryAfterSeconds(accountKey);
      _audit.record(
        method: 'POST',
        path: '/v1/sessions',
        status: 429,
        accountId: null,
        detail: 'login locked out',
      );
      return HubError.rateLimited(
        'too many failed logins for this account',
      ).toResponse(
        requestId: requestId,
        headers: <String, String>{'retry-after': '$retry'},
      );
    }
    final result = _accounts.login(publicKey: publicKey, password: password);
    if (result == null) {
      _loginThrottle.recordFailure(accountKey);
      return HubError.unauthorized(
        'invalid credentials',
      ).toResponse(requestId: requestId);
    }
    _loginThrottle.recordSuccess(accountKey);
    _audit.record(
      method: 'POST',
      path: '/v1/sessions',
      status: 200,
      accountId: result.account.id,
      detail: 'login',
    );
    return hubJson(<String, Object?>{
      'accountId': result.account.id,
      'bearerToken': result.bearerToken,
      'trust': result.account.trust,
    });
  }

  Future<Response> _getTileHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.read);
    if (auth.error != null) return auth.error!;
    final tileId = int.tryParse(request.params['tileId'] ?? '');
    if (tileId == null) {
      return HubError.badRequest(
        'tileId must be an integer',
      ).toResponse(requestId: requestId);
    }
    final order = _orderQuery(request);
    final finalized =
        (request.url.queryParameters['finalized'] ?? 'true') == 'true';

    final tile = _store.load(tileId, order);
    if (tile == null) {
      return HubError.notFound(
        'no contributions for tile $tileId at order $order',
      ).toResponse(requestId: requestId);
    }

    final headers = <String, String>{
      'content-type': 'application/octet-stream',
      'x-total-frames': '${tile.totalFrames}',
      'x-integration-seconds': '${tile.totalIntegrationSeconds}',
      'x-contributors': '${tile.contributors.length}',
    };
    if (finalized) {
      // The finalized raster (mean per pixel) as raw little-endian f64 — a
      // compact, dependency-free representation the client decodes alongside
      // the tile WCS in the header. (FITS packaging is a client concern.)
      final mean = tile.finalizeMean();
      return Response.ok(mean.buffer.asUint8List(), headers: headers);
    }
    // finalized=false → the merged .nst accumulator bytes themselves.
    final bytes = _store.loadBytes(tileId, order)!;
    return Response.ok(bytes, headers: headers);
  }

  Future<Response> _contributeHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final identity = auth.identity!;
    final tileId = int.tryParse(request.params['tileId'] ?? '');
    if (tileId == null) {
      return HubError.badRequest(
        'tileId must be an integer',
      ).toResponse(requestId: requestId);
    }
    final order = _orderQuery(request);
    final q = request.url.queryParameters;
    final framesDelta = int.tryParse(q['framesDelta'] ?? '') ?? 0;
    final integrationSecondsDelta =
        double.tryParse(q['integrationSecondsDelta'] ?? '') ?? 0.0;
    final medianFwhm = double.tryParse(q['medianFwhm'] ?? '');
    final solver = q['solver'];
    final instrument = q['instrument'];

    final bytes = await _readBinary(request, config.maxContributionBytes);
    if (bytes == null) {
      return HubError.payloadTooLarge(
        'contribution exceeds ${config.maxContributionBytes} bytes',
      ).toResponse(requestId: requestId);
    }

    final ContributionOutcome outcome;
    try {
      outcome = _fusion.contribute(
        accountId: identity.accountId,
        tileId: tileId,
        order: order,
        deltaBytes: bytes,
        framesDelta: framesDelta,
        integrationSecondsDelta: integrationSecondsDelta,
        medianFwhm: medianFwhm,
        instrument: instrument,
        solver: solver,
      );
    } on ContributionRejected catch (e) {
      return HubError(400, e.code, e.message).toResponse(requestId: requestId);
    }

    _audit.record(
      method: 'POST',
      path: '/v1/tiles/$tileId/contributions',
      status: outcome.accepted ? 200 : 200,
      accountId: identity.accountId,
      detail: outcome.accepted
          ? 'accepted trust=${outcome.trustApplied}'
          : 'rejected ${outcome.verdict.reason}',
    );

    return hubJson(<String, Object?>{
      'contributionId': outcome.contributionId,
      'accepted': outcome.accepted,
      'trustApplied': outcome.trustApplied,
      'totalFramesAfter': outcome.totalFramesAfter,
      'integrationSecondsAfter': outcome.integrationSecondsAfter,
      'contributorsAfter': outcome.contributorsAfter,
      'quality': outcome.verdict.toJson(),
    });
  }

  Future<Response> _retractContributionHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final identity = auth.identity!;
    final contributionId = request.params['contributionId'];
    if (contributionId == null || contributionId.isEmpty) {
      return HubError.badRequest(
        'contributionId is required',
      ).toResponse(requestId: requestId);
    }
    try {
      // Admins may retract anyone's contribution; contributors only their own.
      final requesterId = identity.scope == HubScope.admin
          ? null
          : identity.accountId;
      final outcome = _fusion.retract(contributionId, requesterId: requesterId);
      _audit.record(
        method: 'DELETE',
        path: '/v1/contributions/$contributionId',
        status: 200,
        accountId: identity.accountId,
        detail: 'retracted',
      );
      return hubJson(<String, Object?>{
        'retracted': outcome.retracted,
        'totalFramesAfter': outcome.totalFramesAfter,
        'integrationSecondsAfter': outcome.integrationSecondsAfter,
        'contributorsAfter': outcome.contributorsAfter,
      });
    } on ContributionNotFound {
      return HubError.notFound(
        'no such contribution',
      ).toResponse(requestId: requestId);
    } on ContributionForbidden {
      return HubError.forbidden(
        'not your contribution',
      ).toResponse(requestId: requestId);
    } on ContributionStateError catch (e) {
      return HubError.conflict(
        'notRetractable',
        e.message,
      ).toResponse(requestId: requestId);
    }
  }

  /// `POST /v1/tiles/<tileId>/subframes?order=…` — store one raw FITS subframe.
  ///
  /// Gated on [HubConfig.acceptsRawSubs]: when the hub has not opted in, return
  /// 405 so the client surfaces "this hub does not accept raw subframes" rather
  /// than appearing to accept it. Provenance (capturedImageId, instrument,
  /// exposure) rides as query params, mirroring the sums contribution headers.
  Future<Response> _contributeSubframeHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    if (!config.acceptsRawSubs) {
      return HubError(
        405,
        'rawSubsDisabled',
        'this hub does not accept raw subframes',
      ).toResponse(requestId: requestId);
    }
    final identity = auth.identity!;
    final tileId = int.tryParse(request.params['tileId'] ?? '');
    if (tileId == null) {
      return HubError.badRequest(
        'tileId must be an integer',
      ).toResponse(requestId: requestId);
    }
    final order = _orderQuery(request);
    final q = request.url.queryParameters;
    final capturedImageId = int.tryParse(q['capturedImageId'] ?? '');
    final exposureSeconds = double.tryParse(q['exposureSeconds'] ?? '');
    final instrument = q['instrument'];

    final bytes = await _readBinary(request, config.maxSubframeBytes);
    if (bytes == null) {
      return HubError.payloadTooLarge(
        'subframe exceeds ${config.maxSubframeBytes} bytes',
      ).toResponse(requestId: requestId);
    }
    if (bytes.isEmpty) {
      return HubError.badRequest(
        'empty subframe body',
      ).toResponse(requestId: requestId);
    }

    final receipt = _subframes.store(
      accountId: identity.accountId,
      tileId: tileId,
      order: order,
      bytes: bytes,
      capturedImageId: capturedImageId,
      instrument: instrument,
      exposureSeconds: exposureSeconds,
    );
    _audit.record(
      method: 'POST',
      path: '/v1/tiles/$tileId/subframes',
      status: 200,
      accountId: identity.accountId,
      detail: 'raw subframe ${receipt.storedBytes}B',
    );
    return hubJson(receipt.toJson());
  }

  /// `DELETE /v1/subframes/<contributionId>` — delete a stored raw subframe.
  /// A raw-sub deletion is a FILE-DELETE (the frame is removed), not a clean
  /// subtraction from a co-add — the client copy makes that distinction.
  Future<Response> _deleteSubframeHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    if (!config.acceptsRawSubs) {
      return HubError(
        405,
        'rawSubsDisabled',
        'this hub does not accept raw subframes',
      ).toResponse(requestId: requestId);
    }
    final identity = auth.identity!;
    final contributionId = request.params['contributionId'];
    if (contributionId == null || contributionId.isEmpty) {
      return HubError.badRequest(
        'contributionId is required',
      ).toResponse(requestId: requestId);
    }
    try {
      final requesterId = identity.scope == HubScope.admin
          ? null
          : identity.accountId;
      _subframes.delete(contributionId, requesterId: requesterId);
      _audit.record(
        method: 'DELETE',
        path: '/v1/subframes/$contributionId',
        status: 200,
        accountId: identity.accountId,
        detail: 'raw subframe deleted',
      );
      return hubJson(<String, Object?>{'deleted': true});
    } on SubframeNotFound {
      return HubError.notFound(
        'no such subframe',
      ).toResponse(requestId: requestId);
    } on SubframeForbidden {
      return HubError.forbidden(
        'not your subframe',
      ).toResponse(requestId: requestId);
    }
  }

  /// `GET /v1/targets` — browse the swarm's shared targets (the entry point to
  /// join / contribute / pull). Emits the client-facing shape
  /// (`SharedTarget.fromJson`): `targetId`, `name`, `raDeg`, `decDeg`,
  /// `integrationSeconds`, `contributors` (distinct accounts on the active tile),
  /// and `activeTileId`.
  Future<Response> _listTargetsHandler(Request request) async {
    final auth = _authorize(request, HubScope.read);
    if (auth.error != null) return auth.error!;
    final targets = _scheduler.listTargets();
    final out = <Map<String, Object?>>[];
    for (final t in targets) {
      final activeTileId = FollowTheNightScheduler.activeTileFor(
        t,
        config.healpixOrder,
      );
      out.add(<String, Object?>{
        'targetId': t.id,
        'name': t.name,
        'raDeg': t.centerRaDeg,
        'decDeg': t.centerDecDeg,
        'integrationSeconds': t.integrationSeconds,
        'contributors': _contributorsForTile(activeTileId, config.healpixOrder),
        'activeTileId': activeTileId,
      });
    }
    return hubJson(<String, Object?>{'targets': out});
  }

  /// Distinct contributor count recorded for a tile in the fused index (0 if the
  /// tile has not been folded into yet).
  int _contributorsForTile(int tileId, int order) {
    final rows = _db.db.select(
      'SELECT contributors FROM tile_index WHERE tile_id = ? AND '
      'healpix_order = ?;',
      <Object?>[tileId, order],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['contributors'] as num?)?.toInt() ?? 0;
  }

  Future<Response> _ensureTargetHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final body = await _readJson(request);
    final name = body['name'];
    final ra = body['centerRaDeg'];
    final dec = body['centerDecDeg'];
    final radius = body['radiusDeg'];
    if (name is! String || ra is! num || dec is! num || radius is! num) {
      return HubError.badRequest(
        'name, centerRaDeg, centerDecDeg, radiusDeg required',
      ).toResponse(requestId: requestId);
    }
    final priority = body['priority'];
    final id = _scheduler.ensureTarget(
      name: name,
      centerRaDeg: ra.toDouble(),
      centerDecDeg: dec.toDouble(),
      radiusDeg: radius.toDouble(),
      priority: priority is num ? priority.toDouble() : 0.5,
    );
    final target = _scheduler.getTarget(id)!;
    final activeTileId = FollowTheNightScheduler.activeTileFor(
      target,
      config.healpixOrder,
    );
    return hubJson(<String, Object?>{
      'targetId': id,
      // Echo the target back in the SAME client-facing browse shape
      // `GET /v1/targets` uses (`targetId`/`raDeg`/`decDeg`/`activeTileId`) so
      // the client's `SharedTarget.fromJson` decodes it without a second fetch.
      'target': <String, Object?>{
        'targetId': id,
        'name': target.name,
        'raDeg': target.centerRaDeg,
        'decDeg': target.centerDecDeg,
        'integrationSeconds': target.integrationSeconds,
        'contributors': _contributorsForTile(activeTileId, config.healpixOrder),
        'activeTileId': activeTileId,
      },
    });
  }

  Future<Response> _followTheNightHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final q = request.url.queryParameters;
    final lat = double.tryParse(q['latitudeDeg'] ?? '');
    final lon = double.tryParse(q['longitudeDeg'] ?? '');
    if (lat == null || lon == null) {
      return HubError.badRequest(
        'latitudeDeg and longitudeDeg query params are required',
      ).toResponse(requestId: requestId);
    }
    final minAlt = double.tryParse(q['minAltitudeDeg'] ?? '') ?? 25.0;
    final plan = _scheduler.plan(
      latitudeDeg: lat,
      longitudeDeg: lon,
      minAltitudeDeg: minAlt,
    );
    return hubJson(<String, Object?>{
      'plan': plan.map((e) => e.toJson()).toList(),
    });
  }

  Future<Response> _handoffStateHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final targetId = int.tryParse(request.params['targetId'] ?? '');
    if (targetId == null) {
      return HubError.badRequest(
        'targetId must be an integer',
      ).toResponse(requestId: requestId);
    }
    final target = _scheduler.getTarget(targetId);
    if (target == null) {
      return HubError.notFound(
        'no such target',
      ).toResponse(requestId: requestId);
    }
    final state = _handoff.state(targetId);
    final q = request.url.queryParameters;
    final lat = double.tryParse(q['latitudeDeg'] ?? '');
    final lon = double.tryParse(q['longitudeDeg'] ?? '');
    var altitudeOk = true;
    if (lat != null && lon != null) {
      final alt = _scheduler.altitudeForTarget(
        target: target,
        latitudeDeg: lat,
        longitudeDeg: lon,
      );
      altitudeOk = alt >= (double.tryParse(q['minAltitudeDeg'] ?? '') ?? 25.0);
    }
    return hubJson(<String, Object?>{
      'targetId': targetId,
      'activeTileId': FollowTheNightScheduler.activeTileFor(
        target,
        config.healpixOrder,
      ),
      'holder': state.holder,
      'altitudeOk': altitudeOk,
      'claimToken': null,
    });
  }

  Future<Response> _handoffClaimHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final identity = auth.identity!;
    final targetId = int.tryParse(request.params['targetId'] ?? '');
    if (targetId == null) {
      return HubError.badRequest(
        'targetId must be an integer',
      ).toResponse(requestId: requestId);
    }
    if (_scheduler.getTarget(targetId) == null) {
      return HubError.notFound(
        'no such target',
      ).toResponse(requestId: requestId);
    }
    final claim = _handoff.claim(
      targetId: targetId,
      accountId: identity.accountId,
    );
    if (claim == null) {
      return HubError.conflict(
        'handoffHeld',
        'target $targetId is currently held by another contributor',
      ).toResponse(requestId: requestId);
    }
    return hubJson(<String, Object?>{
      'claimToken': claim.claimToken,
      'expiresAt': claim.expiresAt.toIso8601String(),
    });
  }

  Future<Response> _handoffReleaseHandler(Request request) async {
    final requestId = request.context['requestId'] as String?;
    final auth = _authorize(request, HubScope.contribute);
    if (auth.error != null) return auth.error!;
    final identity = auth.identity!;
    final targetId = int.tryParse(request.params['targetId'] ?? '');
    if (targetId == null) {
      return HubError.badRequest(
        'targetId must be an integer',
      ).toResponse(requestId: requestId);
    }
    final released = _handoff.release(
      targetId: targetId,
      accountId: identity.accountId,
    );
    return hubJson(<String, Object?>{'released': released});
  }

  Future<Response> _auditHandler(Request request) async {
    final auth = _authorize(request, HubScope.admin);
    if (auth.error != null) return auth.error!;
    return hubJson(<String, Object?>{'entries': _audit.recent()});
  }

  // --- Body helpers --------------------------------------------------------

  Future<Map<String, Object?>> _readJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('expected a JSON object');
    }
    return decoded.map(
      (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
    );
  }

  /// Read a binary body up to [maxBytes]; returns null if the body exceeds the
  /// cap. Streams so an oversized upload is rejected without buffering it all.
  Future<Uint8List?> _readBinary(Request request, int maxBytes) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > maxBytes) return null;
    }
    return builder.toBytes();
  }

  int _orderQuery(Request request) {
    return int.tryParse(request.url.queryParameters['order'] ?? '') ??
        config.healpixOrder;
  }

  static bool _isConflictCode(String code) {
    return code == 'geometryMismatch' ||
        code == 'orderMismatch' ||
        code == 'channelMismatch' ||
        code == 'idMismatch';
  }
}

/// The production error-trap middleware, extracted to top level so its
/// redaction contract is unit-testable without standing up the full server +
/// DB. [HubServer] installs this verbatim ([HubServer._errorTrapMiddleware]).
///
/// Maps a [TileCodecException] to its 400/409 envelope and a [FormatException]
/// to a 400, but converts any OTHER thrown error into a generic 500
/// (`internal error`) that NEVER echoes the underlying exception text or stack
/// to the caller (those routinely embed absolute filesystem paths, SQL
/// fragments, and type internals). The full detail is logged server-side keyed
/// to the requestId so an operator can still correlate.
Middleware hubErrorTrapMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      final requestId = request.context['requestId'] as String?;
      try {
        return await inner(request);
      } on TileCodecException catch (e) {
        final status = HubServer._isConflictCode(e.code) ? 409 : 400;
        return HubError(
          status,
          e.code,
          e.message,
        ).toResponse(requestId: requestId);
      } on FormatException catch (e) {
        return HubError.badRequest(
          'malformed JSON: ${e.message}',
        ).toResponse(requestId: requestId);
      } catch (e, stack) {
        stderr.writeln(
          '[hub] unhandled error (requestId=${requestId ?? '-'}): $e\n$stack',
        );
        return HubError.internal(
          'internal error',
        ).toResponse(requestId: requestId);
      }
    };
  };
}
