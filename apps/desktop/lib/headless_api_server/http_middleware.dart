part of '../headless_api_server.dart';

extension _HeadlessApiServerHttpMiddleware on HeadlessApiServer {
  // ===========================================================================
  // Middleware
  // ===========================================================================

  Middleware _requestTrackingMiddleware() {
    return (innerHandler) {
      return (request) async {
        final requestId = request.headers[HeadlessApiServer._requestIdHeader] ??
            _nextRequestId();
        final path = '/${request.url.path}';
        final startedAt = DateTime.now();
        final scopedRequest = request.change(context: {
          ...request.context,
          HeadlessApiServer._requestIdContextKey: requestId,
        });

        _logInfo(
          '[REQ][$requestId] ${request.method} $path started',
          fields: {
            'requestId': requestId,
            'method': request.method,
            'path': path,
            'phase': 'started',
          },
        );
        try {
          final response = await innerHandler(scopedRequest);
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logInfo(
            '[REQ][$requestId] ${request.method} $path completed status=${response.statusCode} ms=$elapsedMs',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'phase': 'completed',
              'statusCode': response.statusCode,
              'elapsedMs': elapsedMs,
            },
          );
          if (path == '/api/ws' || path == '/events') {
            return response;
          }
          return response.change(headers: {
            ...response.headers,
            HeadlessApiServer._requestIdHeader: requestId,
          });
        } catch (e, stackTrace) {
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logError(
            '[REQ][$requestId] ${request.method} $path failed ms=$elapsedMs error=$e\n$stackTrace',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'phase': 'failed',
              'elapsedMs': elapsedMs,
              'error': e.toString(),
            },
          );
          rethrow;
        }
      };
    };
  }

  Middleware _corsMiddleware() {
    return (innerHandler) {
      return (request) async {
        final corsHeaders = _buildCorsHeaders(request);
        if (request.method == 'OPTIONS') {
          if (request.headers.containsKey('origin') && corsHeaders.isEmpty) {
            return jsonForbidden(
              {
                'error': 'origin_not_allowed',
                'message': 'Cross-origin requests are not allowed.',
              },
              headers: {'vary': 'Origin'},
            );
          }
          return Response.ok('', headers: corsHeaders);
        }

        final response = await innerHandler(request);
        final path = '/${request.url.path}';
        if (path == '/api/ws' || path == '/events') {
          return response;
        }
        if (corsHeaders.isEmpty) {
          return response;
        }
        return response.change(headers: {
          ...response.headers,
          ...corsHeaders,
        });
      };
    };
  }

  Middleware _requestSizeLimitMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final validation = route_metadata.validateContentLength(
          method: request.method,
          path: path,
          contentLengthHeader: request.headers[HttpHeaders.contentLengthHeader],
        );
        if (validation != null) {
          return jsonResponse(
            validation['body'],
            statusCode: validation['statusCode'] as int,
          );
        }

        if (!route_metadata.methodCanHaveBody(request.method)) {
          return innerHandler(request);
        }

        final declaredContentLength =
            request.headers[HttpHeaders.contentLengthHeader];
        if (declaredContentLength != null && declaredContentLength.isNotEmpty) {
          return innerHandler(request);
        }

        final limit = route_metadata.requestBodyLimitForPath(path);
        final body = await _readRequestBodyWithinLimit(request, limit);
        if (!body.accepted) {
          final requestId = _requestIdFrom(request);
          _logWarning(
            '[REQ][$requestId] ${request.method} $path body too large '
            'received=${body.receivedBytes} max=$limit',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'receivedBytes': body.receivedBytes,
              'maxBytes': limit,
            },
          );
          return jsonTooLarge({
            'error': 'Request body too large',
            'maxBytes': limit,
            'receivedBytes': body.receivedBytes,
            'requestId': requestId,
          });
        }

        return innerHandler(request.change(body: body.bytes));
      };
    };
  }

  Future<_RequestBodyLimitResult> _readRequestBodyWithinLimit(
    Request request,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var receivedBytes = 0;
    var exceededLimit = false;
    await for (final chunk in request.read()) {
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        exceededLimit = true;
        continue;
      }
      if (!exceededLimit) {
        bytes.add(chunk);
      }
    }
    if (exceededLimit) {
      return _RequestBodyLimitResult.rejected(receivedBytes);
    }
    return _RequestBodyLimitResult.accepted(
      bytes.takeBytes(),
      receivedBytes,
    );
  }

  Middleware _apiVersionMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final isWebSocket = path == '/api/ws' || path == '/events';
        final clientVersion = request
                .headers[RemoteApiCompatibility.apiVersionHeader] ??
            (isWebSocket ? request.url.queryParameters['apiVersion'] : null);
        if ((path.startsWith('/api/') || isWebSocket) &&
            clientVersion != null &&
            clientVersion.trim().isNotEmpty) {
          final compatibility =
              RemoteApiCompatibility.checkClient(clientVersion);
          if (!compatibility.isCompatible) {
            final requestId = _requestIdFrom(request);
            _logWarning(
              '[API][$requestId] Rejected incompatible client API version '
              '$clientVersion for $path: ${compatibility.code}',
            );
            return jsonUpgradeRequired(
              {
                'error': compatibility.code,
                'message': compatibility.message,
                'clientApiVersion':
                    compatibility.clientVersion ?? clientVersion,
                'serverApiVersion':
                    RemoteApiCompatibility.serverApiVersion.format(),
                'minimumSupportedApiVersion':
                    RemoteApiCompatibility.minimumSupportedVersion.format(),
                'requestId': requestId,
              },
              headers: {
                HeadlessApiServer._requestIdHeader: requestId,
                ..._apiCompatibilityHeaders(),
              },
            );
          }
        }

        final response = await innerHandler(request);
        if (isWebSocket) {
          return response;
        }
        return response.change(headers: {
          ...response.headers,
          ..._apiCompatibilityHeaders(),
        });
      };
    };
  }

  Map<String, String> _apiCompatibilityHeaders() {
    return {
      RemoteApiCompatibility.apiVersionHeader:
          RemoteApiCompatibility.serverApiVersion.format(),
      'x-nightshade-minimum-api-version':
          RemoteApiCompatibility.minimumSupportedVersion.format(),
    };
  }

  Middleware _rateLimitMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        final path = '/${request.url.path}';
        // P2-6: per-token / route-class bucket runs first. It supersedes
        // the endpoint window for authenticated requests because (a) it
        // is keyed by the principal rather than by the public IP (NAT-
        // safe), and (b) its route classes carve a per-token budget that
        // the endpoint window cannot express. The endpoint window stays
        // as a defence-in-depth backstop in case the route-class bucket
        // is somehow bypassed (unauthenticated path that still reaches
        // the rate limiter).
        final identity = _authIdentityFrom(request);
        final routeClass = _authRouteClassFrom(request);
        if (identity != null && routeClass != null) {
          final tokenDecision = _tokenBucketLimiter.tryConsume(
            tokenId: identity,
            routeClass: routeClass,
          );
          if (!tokenDecision.allowed) {
            return _denyRateLimited(
              request: request,
              path: path,
              decision: tokenDecision,
              bucketLabel: route_metadata.tokenRouteClassName(routeClass),
              identity: identity,
            );
          }
        }

        // Defence-in-depth: legacy sliding-window check keyed on IP/
        // path. Triggers for unauthenticated requests (which the auth
        // gate above already mostly rejected) and stays useful for
        // catching pathological per-endpoint bursts even after the
        // token bucket allowed the request.
        final decision = _rateLimiter.check(
          clientKey: _rateLimitClientKey(request),
          method: request.method,
          path: path,
        );
        if (decision.allowed) {
          return null;
        }

        return _denyRateLimited(
          request: request,
          path: path,
          decision: decision,
          bucketLabel: 'endpoint',
          identity: identity,
        );
      },
    );
  }

  /// Build the 429 response shared between the per-token and the legacy
  /// endpoint buckets. Body shape matches the task spec
  /// (`{code: 'rate_limited', message, retryAfterSecs}`) while still
  /// including the legacy `error` / `maxRequests` / `retryAfterSeconds`
  /// keys so existing dashboards (which key off `error`) keep working.
  Response _denyRateLimited({
    required Request request,
    required String path,
    required route_metadata.RateLimitDecision decision,
    required String bucketLabel,
    String? identity,
  }) {
    final requestId = _requestIdFrom(request);
    // Redacted form of the principal for log lines: the digest is itself
    // safe to log (it's not a credential) but it's noisy. We surface
    // only the first eight hex chars in human-readable logs while
    // retaining the full digest in the structured fields so log search
    // can correlate across requests.
    final principalLog = identity == null
        ? 'anonymous'
        : identity.substring(0, identity.length < 8 ? identity.length : 8);
    final principalForBody =
        identity == null ? 'anonymous' : 'token-$principalLog';
    final message = 'Token $principalForBody exceeded $bucketLabel bucket';
    _logWarning(
      '[RATE][$requestId] ${request.method} $path limited '
      'bucket=$bucketLabel principal=$principalLog '
      'max=${decision.maxRequests} retry=${decision.retryAfterSeconds}s',
      fields: {
        'requestId': requestId,
        'method': request.method,
        'path': path,
        'bucket': bucketLabel,
        'principal': identity,
        'maxRequests': decision.maxRequests,
        'retryAfterSeconds': decision.retryAfterSeconds,
      },
    );
    return jsonRateLimited(
      {
        'code': 'rate_limited',
        'error': 'Rate limit exceeded',
        'message': message,
        'bucket': bucketLabel,
        'maxRequests': decision.maxRequests,
        'retryAfterSecs': decision.retryAfterSeconds,
        'retryAfterSeconds': decision.retryAfterSeconds,
        'requestId': requestId,
      },
      headers: {
        'retry-after': decision.retryAfterSeconds.toString(),
      },
    );
  }

  Middleware _highRiskAuditMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final auditAction = route_metadata.highRiskAuditActionFor(
          method: request.method,
          path: path,
        );
        if (auditAction == null) {
          return innerHandler(request);
        }

        final requestId = _requestIdFrom(request);
        final clientKey = _rateLimitClientKey(request);
        _logger.info(
          '[AUDIT][$requestId] $auditAction requested '
          'method=${request.method} path=$path client=$clientKey',
          source: 'HeadlessApiAudit',
          fields: {
            'requestId': requestId,
            'auditAction': auditAction,
            'method': request.method,
            'path': path,
            'client': clientKey,
            'phase': 'requested',
          },
        );

        final response = await innerHandler(request);
        _logger.info(
          '[AUDIT][$requestId] $auditAction completed '
          'status=${response.statusCode}',
          source: 'HeadlessApiAudit',
          fields: {
            'requestId': requestId,
            'auditAction': auditAction,
            'method': request.method,
            'path': path,
            'client': clientKey,
            'phase': 'completed',
            'statusCode': response.statusCode,
          },
        );
        return response;
      };
    };
  }

  String _rateLimitClientKey(Request request) {
    final forwardedFor = request.headers['x-forwarded-for'];
    if (forwardedFor != null && forwardedFor.trim().isNotEmpty) {
      return forwardedFor.split(',').first.trim();
    }

    final forwardedHost = request.headers['x-real-ip'];
    if (forwardedHost != null && forwardedHost.trim().isNotEmpty) {
      return forwardedHost.trim();
    }

    return request.requestedUri.host;
  }

  Map<String, String> _buildCorsHeaders(Request request) {
    final origin = request.headers['origin'];
    final allowedOrigin = _resolveAllowedOrigin(request, origin);
    if (allowedOrigin == null) {
      return const {};
    }
    return {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      // Why include the CSRF header: cookie-bearing fetches from the
      // dashboard SPA echo the server-issued CSRF token via
      // `X-Nightshade-CSRF`; without it in the allow-list the browser
      // would block the request before our middleware ever ran (§2.5
      // long-form).
      'Access-Control-Allow-Headers':
          'Origin, Content-Type, X-Auth-Token, Authorization, '
              'X-Nightshade-API-Version, X-Request-ID, X-Nightshade-CSRF',
      // Why expose Set-Cookie on the wire but not allow-credentials: the
      // cookie is HttpOnly so the browser stores it without JS seeing it;
      // `credentials: 'include'` on the SPA fetch is what makes the cookie
      // round-trip, and that requires the next header.
      'Access-Control-Allow-Credentials': 'true',
      'Vary': 'Origin',
    };
  }

  String? _resolveAllowedOrigin(Request request, String? origin) {
    // Why delegate: previous behaviour reflected any origin that matched the
    // bound host:port, which let any local-loopback browser app bypass CORS
    // on a different port (§2.27). [CorsAllowList] applies the explicit
    // configured allow-list and an even stricter rule for high-risk control
    // paths; the same-origin escape hatch is preserved so the bundled
    // dashboard continues to work without configuration.
    return _corsAllowList.resolve(
      requestOrigin: origin,
      requestUri: request.requestedUri,
      path: '/${request.url.path}',
    );
  }

  /// Middleware that validates Bearer token authentication.
  ///
  /// Public endpoints are exempt from authentication:
  /// - GET /api/info
  ///
  /// WebSocket endpoints (/api/ws, /events) require authentication when enabled.
  /// They accept the token via Authorization header or `token` query parameter
  /// (since browsers cannot set custom headers on WebSocket upgrades).
  Middleware _authMiddleware() {
    // Endpoints that don't require authentication. Pairing endpoints are
    // public because the dashboard has no bearer token until the user
    // completes the first pairing flow; the 6-digit code shown on the
    // desktop console is the out-of-band trust factor (§2.1).
    const publicPaths = {
      '/api/info',
      '/api/pairing/start',
      '/api/pairing/verify',
      // Wave 7 Agent 2: live-stacking broadcast endpoints. The audience
      // at an outreach event has not paired the device; the
      // LiveStackingNode's own `auth_token` field is the access gate
      // (constant-time compared inside BroadcastService.authorize).
      // Adding these paths here bypasses the dashboard's pairing-token
      // middleware so a phone-in-the-audience can fetch them with no
      // bearer token; the broadcast handler does its own auth check.
      '/api/broadcast/info',
      '/api/broadcast/live-stack',
      '/api/broadcast/sse',
      '/broadcast',
    };

    // WebSocket paths that support query-param auth (legacy ?token=) or the
    // single-use ?ticket= flow added in §2.28.
    //
    // P2-10: /ws/live-view participates in the same query-param auth flow
    // because browser/WS clients can't always set custom headers on the
    // upgrade request — the phone passes the bearer token via ?token= and
    // we honour it here.
    const webSocketPaths = {'/api/ws', '/events', '/ws/live-view'};

    return (innerHandler) {
      return (request) {
        // Skip auth if no token is configured
        if (_effectiveAuthTokensByValue.isEmpty &&
            _pairedSessionTokens.isEmpty) {
          return innerHandler(request);
        }

        // Skip auth for public endpoints and dashboard static files
        final requestId = _requestIdFrom(request);
        final path = '/${request.url.path}';
        // /run-watch ships the phone SPA which must load before the user
        // has any token at all. Once the SPA fetches /api/run-watch/* it
        // attaches the bearer token like every other client, so only the
        // bundle itself is auth-exempt.
        if (publicPaths.contains(path) ||
            path.startsWith('/dashboard') ||
            path == '/run-watch' ||
            path.startsWith('/run-watch/')) {
          return innerHandler(request);
        }

        // For WebSocket paths, accept either the legacy ?token=<bearer> (with
        // a deprecation warning) or the §2.28 one-shot ?ticket= which is
        // consumed and invalidated here so it cannot be reused.
        if (webSocketPaths.contains(path)) {
          final queryTicket = request.url.queryParameters['ticket'];
          if (queryTicket != null && queryTicket.isNotEmpty) {
            // P2-15: ws_ticket_manager.consume now returns the digest of
            // the token that was used to mint the ticket, NOT the raw
            // token. That digest IS the authenticated identity for the
            // upcoming WS — stash it on the context so the upgrade
            // handler can bind it to the socket as the canonical viewer
            // id.
            final ticketIdentity = _wsTicketManager.consume(queryTicket);
            if (ticketIdentity != null) {
              return innerHandler(_attachAuthIdentity(
                request,
                identity: ticketIdentity,
                routeClass: route_metadata.tokenRouteClassFor(
                  method: request.method,
                  path: path,
                ),
              ));
            }
            // Bad/expired ticket — do NOT fall through to legacy token to
            // avoid masking a stolen-ticket replay attempt with a successful
            // bearer-token outcome. Reject explicitly.
            _logWarning(
              '[AUTH][$requestId] Rejected WS upgrade to $path - invalid or expired ticket',
            );
            return jsonUnauthorized(
              {
                'error': 'Authentication required',
                'message': 'Invalid or expired WebSocket ticket',
              },
              headers: {HeadlessApiServer._requestIdHeader: requestId},
            );
          }

          final queryToken = request.url.queryParameters['token'];
          if (queryToken != null && queryToken.isNotEmpty) {
            final queryScope = _scopeForToken(queryToken);
            if (queryScope != null &&
                HeadlessAuthPolicy.allows(
                  actual: queryScope,
                  method: 'WS',
                  path: path,
                )) {
              _logWarning(
                '[AUTH][$requestId] WS upgrade to $path used legacy ?token=. '
                'Switch to POST /api/ws/ticket + ?ticket= (audit §2.28).',
              );
              return innerHandler(_attachAuthIdentity(
                request,
                identity: computeServerFingerprint(queryToken),
                routeClass: route_metadata.tokenRouteClassFor(
                  method: request.method,
                  path: path,
                ),
              ));
            }
          }
          // Fall through to check Authorization header below.
        }

        // Resolve credentials. Acceptable forms:
        //  1. `Authorization: Bearer <token>` header (mobile clients, API
        //     consumers, the dashboard's pre-cookie path).
        //  2. The §2.5 long-form `nightshade_session` HttpOnly cookie set by
        //     `POST /api/auth/cookie` after a successful pairing. Cookie
        //     requests additionally require a matching CSRF token on every
        //     state-changing method.
        //  3. `?access_token=<bearer>` query parameter, but ONLY for the
        //     Wave 6 SSE endpoint. Why: browser EventSource cannot set
        //     custom headers and the SSE handler is GET-only / read-only,
        //     so a one-shot URL token is the only viable auth carrier
        //     for the phone client. This is gated to /api/run-watch/events
        //     so general endpoints still require the header form.
        //
        // We resolve the cookie BEFORE the Authorization header so a single
        // dashboard tab that has both (e.g. mid-migration) still gets the
        // CSRF check applied. If both are present the Authorization header
        // takes precedence (it is the active session the browser opted into
        // for this request).
        final authHeader = request.headers['authorization'];
        final cookieHeader = request.headers['cookie'];
        final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
        String? token;
        bool tokenFromCookie = false;
        // Wave 6 — accept ?access_token= on the SSE endpoint only.
        // P1-14 extends this to the /api/logs/tail SSE endpoint for the
        // same reason: browser EventSource cannot set custom headers,
        // so a one-shot query-param bearer is the only viable carrier
        // for the phone client. Both endpoints are GET-only and
        // read-only so a leaked URL token (e.g. via a screenshot) has
        // bounded blast radius.
        if (path == '/api/run-watch/events' || path == '/api/logs/tail') {
          final qToken = request.url.queryParameters['access_token'];
          if (qToken != null && qToken.isNotEmpty) {
            token = qToken;
          }
        }
        if (token == null && authHeader != null) {
          if (!authHeader.startsWith('Bearer ')) {
            _logWarning(
                '[AUTH][$requestId] Rejected request to $path - invalid auth format');
            return jsonUnauthorized(
              {
                'error': 'Authentication required',
                'message':
                    'Invalid Authorization header format. Expected: Bearer <token>',
              },
              headers: {
                HeadlessApiServer._requestIdHeader: requestId,
              },
            );
          }
          token = authHeader.substring(7); // Remove 'Bearer ' prefix
        }
        if (token == null && sessionCookie != null) {
          final cookieBearer = _authCookieManager.resolveBearer(sessionCookie);
          if (cookieBearer != null) {
            token = cookieBearer;
            tokenFromCookie = true;
          }
        }

        if (token == null) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - no Authorization header or session cookie');
          return jsonUnauthorized(
            {
              'error': 'Authentication required',
              'message': 'Missing Authorization header or session cookie',
            },
            headers: {
              HeadlessApiServer._requestIdHeader: requestId,
            },
          );
        }

        // CSRF gate for cookie-authenticated requests. Why only when the
        // token came from the cookie: bearer-header requests are not
        // ambient-credentialed by the browser, so a cross-origin attacker
        // cannot get the header attached automatically. Cookie requests,
        // however, are sent on every same-site fetch — the CSRF token
        // (in-memory in JS, mirrored to a request header) is what proves
        // the request actually originated from the dashboard SPA.
        //
        // GET/HEAD/OPTIONS are excluded because CSRF protects state
        // changes; read-only responses do not need it (and pre-flighting
        // every GET would break image/event endpoints).
        if (tokenFromCookie &&
            HeadlessApiServer._methodNeedsCsrf(request.method)) {
          final presented =
              request.headers[AuthCookieManager.csrfHeader.toLowerCase()];
          if (!_authCookieManager.validateCsrf(
            cookieToken: sessionCookie,
            presented: presented,
          )) {
            _logWarning(
              '[AUTH][$requestId] Rejected cookie request to $path - missing or invalid CSRF token',
            );
            return jsonForbidden(
              {
                'error': 'csrf_required',
                'message':
                    'A valid ${AuthCookieManager.csrfHeader} header is required for this method.',
              },
              headers: {HeadlessApiServer._requestIdHeader: requestId},
            );
          }
        }

        final clientKey = _rateLimitClientKey(request);
        // Why pre-check: the constant-time loop is O(N*L) over the token
        // table; an attacker spamming bad tokens could make it a CPU-burn
        // vector (§2.22). The resolver tracks per-client failure counts and
        // we shed load with 429 once the bucket fills.
        if (_tokenResolver.isRateLimited(clientKey)) {
          _logWarning(
            '[AUTH][$requestId] Rate-limited token comparisons from $clientKey on $path',
          );
          return jsonRateLimited(
            {
              'error': 'Rate limit exceeded',
              'message': 'Too many authentication failures',
              'requestId': requestId,
            },
            headers: {
              HeadlessApiServer._requestIdHeader: requestId,
              'retry-after': '60',
            },
          );
        }
        final tokenScope = _scopeForToken(token);
        if (tokenScope == null) {
          _tokenResolver.recordFailure(clientKey);
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - invalid token');
          return jsonForbidden(
            {
              'error': 'Access denied',
              'message': 'Invalid authentication token',
            },
            headers: {
              HeadlessApiServer._requestIdHeader: requestId,
            },
          );
        }
        // Token recognised — clear stale failures so a successful login
        // resets the counter for that client.
        _tokenResolver.clearFailures(clientKey);

        if (!HeadlessAuthPolicy.allows(
          actual: tokenScope,
          method: request.method,
          path: path,
        )) {
          final requiredScope = HeadlessAuthPolicy.requiredScopeFor(
            method: request.method,
            path: path,
          );
          _logWarning(
            '[AUTH][$requestId] Rejected request to $path - '
            'scope=${headlessTokenScopeName(tokenScope)} '
            'required=${headlessTokenScopeName(requiredScope)}',
          );
          return jsonForbidden(
            {
              'error': 'Access denied',
              'message': 'Token scope is not permitted for this endpoint',
              'requiredScope': headlessTokenScopeName(requiredScope),
              'tokenScope': headlessTokenScopeName(tokenScope),
            },
            headers: {
              HeadlessApiServer._requestIdHeader: requestId,
            },
          );
        }

        // Token is valid, continue to handler. Stash the digest of the
        // resolved token + the request's route class so the rate-limit
        // middleware (and any handler that wants to log the principal
        // without a re-resolution) can read it back. We MUST NOT pass
        // the raw token through the context — see [_authIdentityContextKey].
        return innerHandler(_attachAuthIdentity(
          request,
          identity: computeServerFingerprint(token),
          routeClass: route_metadata.tokenRouteClassFor(
            method: request.method,
            path: path,
          ),
        ));
      };
    };
  }

  /// P2-6 / P2-15: stash the authenticated principal's digest + the
  /// classified route class on the shelf request context so downstream
  /// middleware (rate limit) and the WS upgrade handler can bind to them.
  ///
  /// The raw bearer is NEVER placed on the context — only its SHA-256
  /// digest via `computeServerFingerprint`, which is the same value the
  /// session-ownership manager uses to identify owners and what every
  /// other code path digests to.
  Request _attachAuthIdentity(
    Request request, {
    required String identity,
    required route_metadata.TokenRouteClass routeClass,
  }) {
    return request.change(context: {
      HeadlessApiServer._authIdentityContextKey: identity,
      HeadlessApiServer._authRouteClassContextKey: routeClass,
    });
  }

  /// Read the authenticated principal digest off the request context.
  /// Returns null when the auth middleware didn't run (e.g. test fixtures
  /// with no token configured), in which case the rate limiter falls back
  /// to the IP-based key.
  String? _authIdentityFrom(Request request) {
    final value = request.context[HeadlessApiServer._authIdentityContextKey];
    return value is String ? value : null;
  }

  route_metadata.TokenRouteClass? _authRouteClassFrom(Request request) {
    final value = request.context[HeadlessApiServer._authRouteClassContextKey];
    return value is route_metadata.TokenRouteClass ? value : null;
  }

  /// P1-5: extract the raw bearer token (or cookie-backed session token)
  /// from [request]. The auth middleware has already validated whatever
  /// we resolve here; we re-extract because the validated value is not
  /// currently propagated into the request context.
  ///
  /// Returns null when no token is present — callers must treat that as
  /// an unauthenticated request even though the auth middleware should
  /// have rejected it first.
  String? _extractBearerToken(Request request) {
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    final cookieHeader = request.headers['cookie'];
    final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
    if (sessionCookie != null) {
      final cookieBearer = _authCookieManager.resolveBearer(sessionCookie);
      if (cookieBearer != null) {
        return cookieBearer;
      }
    }
    return null;
  }

  /// P1-5: gate destructive POSTs on the operator slot. Read-only and
  /// status endpoints fall through unchanged. The middleware also
  /// refreshes the owner's heartbeat on every authenticated mutating
  /// request so a phone polling the rig stays the owner without an
  /// explicit WS frame.
  Middleware _sessionOwnershipMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        final path = '/${request.url.path}';
        if (!isOwnershipRequired(method: request.method, path: path)) {
          return null;
        }
        // Reaching this branch means: (a) an authenticated request, (b)
        // a mutating verb, (c) a path on the destructive allow-list. If
        // there is no owner yet, the slot is unclaimed and every
        // control-scope client falls back to the legacy "first-come,
        // first-served" semantics — we do NOT block when nobody has
        // claimed the rig, because the dashboard's initial pairing flow
        // (which has not yet POSTed /api/session/claim) must still be
        // able to drive the gear.
        final owner = _sessionOwnership.current;
        if (owner == null) {
          return null;
        }
        final token = _extractBearerToken(request);
        if (token == null) {
          // Auth middleware should have caught this; defensive.
          return jsonForbidden({
            'error': 'auth_required',
            'message':
                'Session-ownership-gated endpoints require a bearer token.',
          });
        }
        if (!_sessionOwnership.isOwner(token)) {
          return jsonConflict({
            'error': 'not_session_owner',
            'message':
                'Another client is the operator. POST /api/session/take-over '
                    'with a reason to displace them.',
            'currentOwner': owner.toJson(),
            'retryWithTakeOver': true,
          });
        }
        // Heartbeat refresh so an actively-driving client never auto-
        // releases under the 5-minute idle timeout.
        _sessionOwnership.touchHeartbeat(token);
        return null;
      },
    );
  }

  HeadlessTokenScope? _scopeForToken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    // Why constant-time + full-iteration: a naive Map[token] short-circuits on
    // hash mismatch, leaking per-character timing of the bearer token to a
    // network attacker (§2.22). The resolver iterates the entire map and uses
    // XOR-based comparison so timing is independent of which entry matches.
    final scope = _tokenResolver.resolve(token);
    if (scope != null) {
      return scope;
    }
    // Paired-session tokens live outside the immutable static map (Drift-
    // backed). Mirror the same constant-time iteration here so the choice
    // between "static config token" and "paired token" is not observable.
    HeadlessTokenScope? pairedMatch;
    for (final entry in _pairedSessionTokens.entries) {
      if (constantTimeCompareStrings(entry.key, token)) {
        pairedMatch = entry.value;
      }
    }
    return pairedMatch;
  }
}
