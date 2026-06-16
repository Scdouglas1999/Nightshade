part of '../headless_api_server.dart';

extension _HeadlessApiServerLifecycle on HeadlessApiServer {
  Future<void> _startServer() async {
    final router = Router();

    // Route table — per-domain declarative lists live under
    // `headless_api/routes/`. Each handler class has a sibling
    // `routes/<name>_routes.dart` exporting a top-level
    // `build<Name>Routes(handler)`. The order below MIRRORS the
    // legacy inline-`router.<verb>(...)` block exactly; shelf_router
    // matches by registration order so any reordering across domain
    // boundaries (e.g. moving `/api/sessions/*` (analytics) before
    // `/api/sessions/<sessionId>/images` (sessions)) would change
    // first-hit semantics. See `routes/headless_route.dart` for the
    // typed primitives.
    final allRoutes = <HeadlessRoute>[
      ...buildSystemRoutes(_systemHandlers),
      ...buildPairingRoutes(_pairingHandlers),
      // Phase D — authenticated cellular-push token + preference routes.
      ...buildPushRoutes(_pushHandlers),
      ...buildAuthRoutes(_authHandlers),
      ...buildCollaborationRoutes(_collaborationHandlers),
      ...buildDeviceDiscoveryRoutes(_deviceDiscoveryHandlers),
      ...buildDeviceRoutes(_deviceHandlers),
      ...buildGuidingRoutes(_guidingHandlers),
      ...buildImagingRoutes(_imagingHandlers),
      ...buildSequencerRoutes(_sequencerHandlers),
      ...buildEquipmentRoutes(_equipmentHandlers),
      ...buildProfileRoutes(_profileHandlers),
      ...buildSessionRoutes(_sessionHandlers),
      ...buildTargetRoutes(_targetHandlers),
      ...buildSequenceManagementRoutes(_sequenceManagementHandlers),
      ...buildFlatWizardRoutes(_flatWizardHandlers),
      ...buildMosaicRoutes(_mosaicHandlers),
      ...buildAnalyticsRoutes(_analyticsHandlers),
      ...buildWeatherRoutes(_weatherHandlers),
      ...buildFileSystemRoutes(_fileSystemHandlers),
      ...buildScienceRoutes(_scienceHandlers),
      ...buildSuggestionRoutes(_suggestionHandlers),
      ...buildTransientRoutes(_transientHandlers),
      ...buildBackupRoutes(_backupHandlers),
      ...buildSyncRoutes(_syncHandlers),
      ...buildFramingRoutes(_framingHandlers),
      ...buildPlanetariumRoutes(_planetariumHandlers),
      ...buildDomeRoutes(_domeHandlers),
      ...buildNarratorRoutes(_narratorHandlers),
      ...buildSafetyMonitorRoutes(_safetyMonitorHandlers),
      ...buildAuxiliaryRoutes(_auxiliaryHandlers),
      ...buildSchedulerRoutes(_schedulerHandlers),
      ...buildFocusModelRoutes(_focusModelHandlers),
      ...buildStackingRoutes(_stackingHandlers),
      ...buildPostSessionRoutes(_postSessionHandlers),
      ...buildJobRoutes(_jobHandlers),
      ...buildSessionOwnershipRoutes(_sessionOwnershipHandlers),
    ];

    // OTA update routes are only registered when the host has
    // wired an UpdateController via [setUpdateController]. Tests and
    // headless deployments that opt out of OTA leave the controller
    // unset, in which case these routes return 404 from the router
    // itself — matching the legacy behaviour exactly.
    final updateHandlers = _updateHandlers;
    if (updateHandlers != null) {
      allRoutes.addAll(buildUpdateRoutes(updateHandlers));
    }

    // Continue appending the remaining per-domain route lists. These
    // come AFTER the OTA block above so the relative declaration order
    // of OTA routes vs. log / calibration / catalog routes is preserved
    // exactly — shelf_router matches on registration order.
    allRoutes
      ..addAll(buildRunWatchRoutes(_runWatchHandlers))
      ..addAll(buildBroadcastRoutes(_broadcastHandlers))
      ..addAll(buildLogRoutes(_logHandlers))
      ..addAll(buildCalibrationRoutes(_calibrationHandlers))
      ..addAll(buildCalibrationLibraryRoutes(_calibrationLibraryHandlers))
      ..addAll(buildCatalogRoutes(_catalogHandlers))
      ..addAll(buildDbReadRoutes(_dbReadHandlers))
      ..addAll(buildPluginRoutes(_pluginHandlers))
      // WebRTC live-view signalling. Must register before
      // the static-file catch-all so `/api/webrtc/live-view/*` is not
      // shadowed by the SPA fallback.
      ..addAll(buildWebRtcLiveViewRoutes(_webRtcLiveViewHandlers))
      ..addAll(buildStaticFileRoutes(_staticFileHandlers));

    // WebSocket-upgrade endpoints. Why these are NOT in
    // [buildWebSocketRoutes] as method-tear-offs:
    //
    // 1. `shelf_web_socket`'s `webSocketHandler` strips the original
    //    Request, so we capture it in an outer closure so the
    //    replay handler can read `?since=` and `?instance=` query
    //    parameters off the upgrade URL.
    // 2. we also lift the auth identity (digest of the bearer
    //    token that authenticated the upgrade) off the request context
    //    that `_authMiddleware` stashed there. Passing it down means
    //    the collaboration `viewerId` is always the authenticated
    //    principal, regardless of what the client puts in the
    //    `collaboration.join` payload.
    //
    // [buildWebSocketRoutes] accepts the pre-built Handler closures so
    // the route table stays purely declarative; the closure body itself
    // has to live here because it accesses private server state.
    Handler eventsHandler() {
      return (Request request) {
        final query = request.url.queryParameters;
        final authIdentity = _authIdentityFrom(request);
        return webSocketHandler((socket, _) {
          _handleWebSocketWithQuery(socket, query, authIdentity);
        }).call(request);
      };
    }

    // push-based live-view streaming. Distinct from the main
    // event WS because (a) it carries binary JPEG frames, not JSON
    // events, and (b) the message protocol is a per-socket
    // subscribe/unsubscribe model rather than the always-on event
    // broadcast.
    Handler liveViewHandler() {
      return (Request request) {
        return webSocketHandler((socket, _) {
          _liveViewStreamHandlers.handleSocket(socket);
        }).call(request);
      };
    }

    allRoutes.addAll(
      buildWebSocketRoutes(
        eventsHandler: eventsHandler(),
        liveViewHandler: liveViewHandler(),
      ),
    );

    // Single dispatch point — `registerRoutes` walks the list once and
    // calls the right `router.<verb>(...)` for each entry. See
    // `routes/headless_route.dart` for the typed-list design rationale.
    registerRoutes(router, allRoutes);

    final handler = Pipeline()
        .addMiddleware(_requestTrackingMiddleware())
        // Why placement: error translation must wrap downstream so
        // BadRequestError thrown anywhere lower becomes a structured 400.
        // It must be _outside_ auth/CORS so 4xx auth responses keep their
        // intended status (errorTranslationMiddleware only intercepts
        // exceptions, not non-2xx responses).
        .addMiddleware(
          errorTranslationMiddleware(
            logError: _logError,
            requestIdFor: _requestIdFrom,
            shouldBypass: (request) {
              final path = '/${request.url.path}';
              // also bypass /ws/live-view so shelf does not try to
              // wrap the WS upgrade response into a JSON error envelope.
              return path == '/api/ws' ||
                  path == '/events' ||
                  path == '/ws/live-view';
            },
          ),
        )
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_requestSizeLimitMiddleware())
        .addMiddleware(_apiVersionMiddleware())
        .addMiddleware(_authMiddleware())
        .addMiddleware(_rateLimitMiddleware())
        .addMiddleware(_highRiskAuditMiddleware())
        // ownership gate runs AFTER auth so we only check ownership
        // for requests that already presented a valid token. Placed
        // before the router so the 409 short-circuits the handler.
        .addMiddleware(_sessionOwnershipMiddleware())
        .addHandler(router.call);

    final bindAddress = bindLocalOnly
        ? InternetAddress.loopbackIPv4
        : InternetAddress.anyIPv4;
    // when a TLS SecurityContext is supplied, bind HTTPS instead of
    // HTTP. shelf_io.serve transparently upgrades the WebSocket layer to
    // WSS for us because the underlying HttpServer is secure.
    _server = await shelf_io.serve(
      handler,
      bindAddress,
      port,
      securityContext: tlsContext,
    );
    final scheme = tlsContext != null ? 'https' : 'http';
    _logInfo(
      'Headless API server running on $scheme://${_server!.address.host}:${_server!.port}',
    );
    if (tlsContext != null) {
      _logInfo(
        '[TLS] Transport encryption is ENABLED. Bearer tokens and pairing codes are protected on the wire.',
      );
    }
    if (_effectiveAuthTokensByValue.isNotEmpty) {
      _logInfo(
        '[AUTH] Authentication is ENABLED. All requests require Bearer token.',
      );
    } else {
      _logInfo('[AUTH] Authentication is DISABLED. All requests are allowed.');
      if (!bindLocalOnly) {
        _logWarning(
          '[AUTH] Unauthenticated LAN access is enabled. This is unsafe for normal rig control.',
        );
      }
    }

    // + hydrate `_pairedSessionTokens` from the Drift DB and
    // register a revocation listener so revokeDevice() / token expiry / the
    // periodic sweep all evict the in-memory entry synchronously without a
    // server restart. Must run AFTER bind so a hydration error doesn't trap
    // operator-facing connect-URL printing in main_headless.dart.
    await _hydratePairedSessionTokens();
    _installRevocationListener();
    _scheduleTokenSweep();

    // periodically evict expired pending commands so a hung driver
    // (or a sequence aborted before a completion event fires) doesn't keep
    // the correlator table growing forever.
    _commandCorrelatorSweepTimer?.cancel();
    _commandCorrelatorSweepTimer = Timer.periodic(const Duration(minutes: 5), (
      _,
    ) {
      try {
        _commandCorrelator.evictExpired();
      } catch (e) {
        _logWarning('CommandCorrelator sweep failed: $e');
      }
    });

    // purge terminated jobs older than the manager's
    // retention window. 5-minute cadence keeps the worst-case age at
    // `retention + 5min` which is well within the documented 24h budget.
    _jobSweepTimer?.cancel();
    _jobSweepTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      try {
        _jobManager.evictExpired();
      } catch (e) {
        _logWarning('JobManager sweep failed: $e');
      }
    });

    // Subscribe to backend events and broadcast to WebSocket clients
    _subscribeToBackendEvents();
    _subscribeToSequenceCatalogUpdates();
    _subscribeToHostMutationEvents();
    _subscribeToCatalogManagerEvents();
    _collaborationSubscription = _collaborationManager.stream.listen(
      _broadcastCollaborationState,
    );

    // start the LAN UDP push broadcaster (when wired). We start it
    // only when the server is non-loopback — loopback-only deployments
    // have no LAN to fan out on, so the bind would just waste sockets.
    final broadcaster = _lanPushBroadcaster;
    if (broadcaster != null && !bindLocalOnly && !broadcaster.isStarted) {
      try {
        await broadcaster.start();
        _logInfo(
          '[push] LAN push broadcaster started '
          '(port=${broadcaster.port}, interfaces=${broadcaster.activeSinkCount})',
        );
      } catch (e, st) {
        // Bind failure is not fatal — UDP push is a supplement to the WS
        // fan-out. Surface a warning so the operator knows phones won't
        // wake on critical alerts when the WS is broken.
        _logWarning(
          '[push] LAN push broadcaster failed to start: $e\n$st — '
          'critical alerts will only reach phones via the WebSocket.',
        );
      }
    } else if (broadcaster != null && bindLocalOnly) {
      _logInfo(
        '[push] LAN push broadcaster supplied but server is loopback-only; '
        'broadcaster will not start.',
      );
    }
  }

  /// Load all active, unexpired pairing tokens from Drift into the in-memory
  /// `_pairedSessionTokens` map. Without this, every server restart evicts
  /// every HTTP-paired client (audit F-3 in 01-connection-auth.md). The
  /// hydrated scope is heuristic: the DB doesn't currently store the granted
  /// scope per device, so we default to `control` — the same default the
  /// verify path uses when `requestedScope` is unset. Operators who pair as
  /// admin must re-pair if they want admin again after the next restart;
  /// this matches the verify-path default and is documented in the
  /// release notes.
  Future<void> _hydratePairedSessionTokens() async {
    // Skip hydration when no PairingService is available. The service is
    // either injected via the constructor (tests / GUI in-memory pairing
    // DB) or lazily constructed via [_ensurePairingService] on first use.
    // Constructing it eagerly inside `start()` would force every test that
    // does NOT exercise pairing to open the on-disk Drift DB, which in
    // turn needs path_provider — which is unavailable in widget-test
    // bindings. The verify endpoint still lazy-creates the service on
    // first paired call.
    final service = _pairingService;
    if (service == null) {
      _logInfo(
        '[AUTH] Skipping paired-session hydration: no PairingService '
        'configured yet (will be created on first pairing request).',
      );
      return;
    }
    try {
      final rows = await service.tokenManager.getActiveUnexpiredPairedDevices();
      var restored = 0;
      for (final row in rows) {
        // Default to `control` scope — see method-doc rationale above.
        _pairedSessionTokens[row.sessionToken] = HeadlessTokenScope.control;
        restored++;
      }
      _logInfo(
        '[AUTH] Restored $restored paired session token(s) from disk',
        fields: {'restored': restored},
      );
    } catch (e, st) {
      // We do NOT silently fall back to an empty map: the audit flagged
      // silent-restart-loses-clients as the actual production-breaking
      // failure mode. If hydration crashes we want the operator to know
      // their phones may need to re-pair, so log it loudly.
      _logError(
        '[AUTH] Failed to hydrate paired session tokens from disk: $e\n$st',
      );
    }
  }

  /// Register the [TokenManager] revocation listener so revocations from
  /// any code path (`TokenManager.revokeDevice`, the periodic sweep, the
  /// expiry path in `verifySessionToken`) propagate to the in-memory map.
  ///
  /// Skipped when no PairingService has been injected; the lazy-construct
  /// path inside [_handlePairingVerify] re-registers the listener via
  /// [_ensurePairingService] once a service exists. See
  /// [_hydratePairedSessionTokens] for the symmetric reasoning.
  void _installRevocationListener() {
    final service = _pairingService;
    if (service == null) return;
    service.tokenManager.setRevocationListener(_evictPairedSessionToken);
  }

  /// Remove a paired-session token from the in-memory map. Idempotent: if
  /// the token is unknown (already evicted, or never present) the call is a
  /// no-op so concurrent sweep + verify paths cannot fight.
  void _evictPairedSessionToken(String sessionToken) {
    final scope = _pairedSessionTokens.remove(sessionToken);
    if (scope != null) {
      _logInfo(
        '[AUTH] Evicted paired session token (${HeadlessApiServer._redactBearer(sessionToken)}) '
        'from in-memory map (scope=${headlessTokenScopeName(scope)})',
      );
    }
  }

  /// Periodic sweep that calls into `TokenManager.purgeExpiredAndRevokedSessions`.
  /// Why 60 s: revocation propagation is bounded by this interval. The
  /// `_evictPairedSessionToken` callback runs synchronously on direct revoke
  /// paths, but the sweep also catches tokens that hit `expires_at` between
  /// requests (no client ever attempted to use them, so the verify path
  /// never fired the listener).
  void _scheduleTokenSweep() {
    _tokenSweepTimer?.cancel();
    _tokenSweepTimer = Timer.periodic(tokenSweepInterval, (_) async {
      final service = _pairingService;
      if (service == null) return;
      try {
        final result = await service.tokenManager
            .purgeExpiredAndRevokedSessions();
        if (!result.isEmpty) {
          _logInfo(
            '[AUTH] Token sweep purged ${result.expiredTokens.length} expired '
            'and ${result.revokedTokens.length} revoked session token(s)',
          );
        }
      } catch (e, st) {
        _logWarning('[AUTH] Token sweep failed: $e\n$st');
      }
    });
  }

  void _subscribeToSequenceCatalogUpdates() {
    _catalogUpdateSubscription?.cancel();
    _catalogUpdateSubscription = container
        .read(sequenceCatalogUpdateBusProvider)
        .stream
        .listen((update) {
          broadcastEvent(update.toNightshadeEvent());
        });
  }

  void _subscribeToHostMutationEvents() {
    final hub = container.read(hostMutationEventHubProvider);
    hub.wsBroadcast = (event) {
      broadcastEvent(event);
      final ctrl = _runWatchEventBroadcast;
      if (ctrl != null && !ctrl.isClosed) {
        try {
          ctrl.add(event);
        } catch (e) {
          _logWarning('[run-watch] host-mutation SSE fan-out failed: $e');
        }
      }
    };
  }

  void _unsubscribeFromHostMutationEvents() {
    container.read(hostMutationEventHubProvider).wsBroadcast = null;
  }

  /// bridge [CatalogManager.events] onto the WS event stream so
  /// clients see structured catalog lifecycle messages
  /// (`CatalogDownloadStarted`, `CatalogDownloadProgress`,
  /// `CatalogVerified`, ...) in the `catalog` category. The fan-out
  /// happens inside the manager's stream listener so this works even
  /// when the catalog op was initiated from the local GUI rather than
  /// the REST API.
  void _subscribeToCatalogManagerEvents() {
    _catalogEventSubscription?.cancel();
    _catalogEventSubscription = CatalogManager.instance.events.listen(
      (event) {
        final severity = switch (event.eventType) {
          'CatalogDownloadFailed' => EventSeverity.error,
          'CatalogVerified' =>
            (event.data['ok'] == true)
                ? EventSeverity.info
                : EventSeverity.warning,
          _ => EventSeverity.info,
        };
        broadcastEvent(
          NightshadeEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            severity: severity,
            category: EventCategory.catalog,
            eventType: event.eventType,
            data: Map<String, dynamic>.from(event.data),
          ),
        );
      },
      onError: (Object e, _) {
        _logWarning('[catalog] event stream error: $e');
      },
    );
  }

  void _subscribeToBackendEvents() {
    try {
      final backend = container.read(backendProvider);
      _eventSubscription = backend.eventStream.listen((event) {
        broadcastEvent(event);
        // Host-side live-stacking auto-feed: every frame the host writes to
        // disk is offered to the stacker, which ignores it unless stacking is
        // armed. This is what lets a running sequence stack live with no client
        // in the loop. Fire-and-forget; the coordinator serializes internally.
        if (event.eventType == 'ImageSaved') {
          final path = event.data['file_path'];
          if (path is String && path.isNotEmpty) {
            _stackingHandlers.onImageSaved(path);
          }
        }
        // re-broadcast onto the SSE fan-out controller. Two
        // separate sinks (WS clients + SSE clients) read from the same
        // upstream so a phone subscribing via SSE sees the same events
        // as the desktop dashboard's WebSocket.
        final ctrl = _runWatchEventBroadcast;
        if (ctrl != null && !ctrl.isClosed) {
          try {
            ctrl.add(event);
          } catch (e) {
            // A failure inside the SSE fan-out must never crash the
            // upstream event subscription that the WS path depends on.
            _logWarning('[run-watch] SSE fan-out add failed: $e');
          }
        }
        _dispatchPluginNodeIfRequested(event);
      });
    } catch (e) {
      _logError('[API] Failed to subscribe to backend events: $e');
    }
  }

  void _dispatchPluginNodeIfRequested(NightshadeEvent event) {
    if (!dispatchPluginNodes ||
        event.category != EventCategory.sequencer ||
        event.eventType != 'PluginNodeRequested') {
      return;
    }

    final backend = container.read(backendProvider);
    if (!backend.dispatchPluginNodesLocally) {
      _logInfo(
        '[plugin-node] Remote backend event ignored; host-side dispatcher '
        'owns plugin node execution',
      );
      return;
    }

    final nodeId = event.data['node_id'] as String? ?? '';
    final pluginId = event.data['plugin_id'] as String? ?? '';
    final nodeTypeId = event.data['node_type_id'] as String? ?? '';
    final configJson = event.data['config_json'] as String? ?? '';
    final displayName = event.data['display_name'] as String?;
    final rawTimeout = event.data['timeout_secs'];
    final timeoutSecs = rawTimeout is num ? rawTimeout.toInt() : 600;

    if (nodeId.isEmpty) {
      _logWarning(
        '[plugin-node] PluginNodeRequested event missing node_id '
        '(plugin=$pluginId, node_type=$nodeTypeId)',
      );
      return;
    }

    final coordinator = container.read(pluginNodeDispatchCoordinatorProvider);
    if (!coordinator.claim(nodeId)) {
      _logInfo(
        '[plugin-node] PluginNodeRequested ignored; another local listener '
        'claimed node_id=$nodeId',
      );
      return;
    }

    final dispatcher = container.read(pluginNodeDispatcherProvider);
    unawaited(() async {
      late PluginNodeDispatchResult result;
      try {
        result = await dispatcher(
          PluginNodeDispatchRequest(
            nodeId: nodeId,
            pluginId: pluginId,
            nodeTypeId: nodeTypeId,
            configJson: configJson,
            displayName: displayName,
            timeoutSecs: timeoutSecs,
          ),
        );
      } catch (e, st) {
        _logError(
          '[plugin-node] Dispatcher threw for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
        );
        result = PluginNodeDispatchResult(
          success: false,
          message: 'dispatcher threw: $e',
        );
      }

      try {
        await backend.sequencerPluginNodeFinished(
          nodeId: nodeId,
          success: result.success,
          message: result.message,
          structuredDetailJson: result.structuredDetailJson,
        );
      } catch (e, st) {
        _logError(
          '[plugin-node] Failed to deliver verdict for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
        );
      } finally {
        coordinator.release(nodeId);
      }
    }());
  }

  Future<void> _stopServer() async {
    _unsubscribeFromHostMutationEvents();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _catalogUpdateSubscription?.cancel();
    _catalogUpdateSubscription = null;
    // drop the bridge from CatalogManager.events to the WS
    // broadcaster so the manager's controller can finish flushing on
    // disposal without us still listening.
    await _catalogEventSubscription?.cancel();
    _catalogEventSubscription = null;
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await _pushNotificationSubscription?.cancel();
    _pushNotificationSubscription = null;
    // tear down the LAN UDP broadcaster + remote delivery hooks.
    // Ownership note: the broadcaster's lifecycle is shared with the
    // server it was passed to. Calling stop() here is the right thing
    // because we constructed/owned its sockets via [start]; the caller
    // that supplied it expects this teardown when the server stops.
    final lanBroadcaster = _lanPushBroadcaster;
    _lanPushBroadcaster = null;
    if (lanBroadcaster != null) {
      await lanBroadcaster.stop();
    }
    final remote = _remotePushDelivery;
    _remotePushDelivery = null;
    if (remote != null) {
      await remote.dispose();
    }
    _webSocketHeartbeatTimer?.cancel();
    _webSocketHeartbeatTimer = null;
    // stop the periodic token sweep before tearing down the DB, and
    // clear the revocation listener so it does not retain a reference to
    // `this` past disposal.
    _tokenSweepTimer?.cancel();
    _tokenSweepTimer = null;
    // stop the correlator eviction sweep.
    _commandCorrelatorSweepTimer?.cancel();
    _commandCorrelatorSweepTimer = null;
    _commandCorrelator.clear();
    _eventReplayBuffer.clear();
    // stop job sweep + drain the manager. Any in-flight
    // work observes the cancellation flag and exits its next poll.
    _jobSweepTimer?.cancel();
    _jobSweepTimer = null;
    await _jobManager.dispose();
    // tear down ownership state and broadcast controller.
    await _sessionOwnership.dispose();
    final pairingForListener = _pairingService;
    if (pairingForListener != null) {
      pairingForListener.tokenManager.setRevocationListener(null);
    }
    // closing the broadcast controller signals all attached
    // SSE clients to disconnect cleanly. The handler's onCancel cleans
    // up its own per-client timer + subscription.
    final ctrl = _runWatchEventBroadcast;
    _runWatchEventBroadcast = null;
    if (ctrl != null && !ctrl.isClosed) {
      await ctrl.close();
    }
    // tear down WebRTC sessions BEFORE the hub so any pending
    // datachannel send during the hub's final detach iteration does
    // not race with libwebrtc's close path.
    await _webRtcLiveViewHandlers.dispose();
    // tear down the live-view hub before the HTTP server so any
    // in-flight producer tick observes the disposal flag and stops
    // touching the backend.
    await _liveViewStreamHub.dispose();
    await _server?.close(force: true);
    _server = null;
    for (final socket in List.of(_sockets)) {
      await socket.sink.close();
    }
    _socketViewerIds.clear();
    _socketAuthIdentities.clear();
    _socketLastSeenAt.clear();
    _sockets.clear();
    _collaborationManager.dispose();
    // Why close the pairing DB: PairingService owns a Drift connection.
    // Leaving it open across server restarts leaks file handles in tests.
    final pairing = _pairingService;
    if (pairing != null) {
      await pairing.close();
      _pairingService = null;
    }
  }
}
