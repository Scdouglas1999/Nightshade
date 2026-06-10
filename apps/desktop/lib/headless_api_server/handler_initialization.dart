part of '../headless_api_server.dart';

extension _HeadlessApiServerHandlerInitialization on HeadlessApiServer {
  void _initializeHandlers() {
    // P1-2 / P1-3 — job manager. Constructed BEFORE the device/imaging/
    // framing/session handlers so they can be wired to it. broadcastEvent
    // is a method on this class so we can pass the bound reference even
    // though the server hasn't bound a socket yet — the event stream
    // becomes active in start().
    _jobManager = JobManager(
      emitEvent: broadcastEvent,
    );

    // P1-5 — session ownership manager. The digest function reuses the
    // existing `computeServerFingerprint` helper so token-digest values
    // share the same domain-separated SHA-256 prefix as everywhere else
    // we hash a credential.
    _sessionOwnership = SessionOwnershipManager(
      emitEvent: broadcastEvent,
      digestToken: computeServerFingerprint,
    );

    // Initialize handler instances. Long-running ops (autofocus, plate-
    // solve, center-on-target, polar-alignment) receive the JobManager
    // so their handlers return `{jobId, status: queued}` immediately and
    // run the work in the background. Other handlers don't need it.
    _deviceHandlers = DeviceHandlers(
      container,
      jobManager: _jobManager,
    );
    _deviceDiscoveryHandlers = DeviceDiscoveryHandlers(container);
    _collaborationHandlers = CollaborationHandlers(
      manager: _collaborationManager,
      logger: container.read(loggingServiceProvider),
    );
    _staticFileHandlers = StaticFileHandlers(
      logger: container.read(loggingServiceProvider),
    );
    _authHandlers = AuthHandlers(
      wsTicketManager: _wsTicketManager,
      authCookieManager: _authCookieManager,
      scopeForToken: _scopeForToken,
      logger: container.read(loggingServiceProvider),
    );
    _pairingHandlers = PairingHandlers(
      pairingAttempts: _pairingAttempts,
      ensurePairingService: _ensurePairingService,
      // Why a closure: PairingHandlers does not have visibility into
      // [_pairedSessionTokens], and we deliberately do not want to leak
      // that map past the server boundary. The closure mutates it
      // through a typed, intent-named entry point so the call site is
      // unambiguous.
      recordPairedSession: (token, scope) {
        _pairedSessionTokens[token] = scope;
      },
      rateLimitClientKey: _rateLimitClientKey,
      pairingPrintCodes: pairingPrintCodes,
      logger: container.read(loggingServiceProvider),
    );
    // Phase D — push token/preference endpoints. Reuses `_ensurePairingService`
    // so the `device_push_tokens` / `device_push_prefs` tables live in the same
    // Drift DB as the paired-device rows they reference.
    _pushHandlers = PushHandlers(
      ensurePairingService: _ensurePairingService,
      logger: container.read(loggingServiceProvider),
    );
    _systemHandlers = SystemHandlers(
      container: container,
      view: SystemServerView(
        // Wrap every server field in a closure so the handler always
        // reads the live value (the event-seq counter advances on
        // every broadcast, so a one-shot capture would be wrong by
        // the second request).
        fingerprint: () => _serverFingerprint,
        instanceId: () => _serverInstanceId,
        currentEventSeq: () => _eventSeq,
        eventReplayBufferSize: () => eventReplayBufferSize,
        eventReplayBufferOldestSeq: () => _eventReplayBuffer.oldestSeq,
        port: () => port,
        bindLocalOnly: () => bindLocalOnly,
        authRequired: () => _effectiveAuthTokensByValue.isNotEmpty,
        availableAuthScopes: _availableAuthScopes,
      ),
      staticFileHandlers: _staticFileHandlers,
      logger: container.read(loggingServiceProvider),
    );
    _guidingHandlers = GuidingHandlers(container);
    _sequencerHandlers = SequencerHandlers(container);
    _equipmentHandlers = EquipmentHandlers(container);
    // [Wave 6B settings sync] inject `broadcastEvent` so handleUpdateSettings
    // can fan settings.changed events out to every connected WS client.
    _profileHandlers = ProfileHandlers(container, emitEvent: broadcastEvent);
    _imagingHandlers = ImagingHandlers(
      container,
      jobManager: _jobManager,
    );
    _sessionHandlers = SessionHandlers(
      container,
      jobManager: _jobManager,
    );

    // Initialize new feature parity handlers
    _targetHandlers = TargetHandlers(container);
    _sequenceManagementHandlers = SequenceManagementHandlers(container);
    _flatWizardHandlers = FlatWizardHandlers(container);
    _mosaicHandlers = MosaicHandlers(container);
    _analyticsHandlers = AnalyticsHandlers(container);
    _weatherHandlers = WeatherHandlers(container);
    _suggestionHandlers = SuggestionHandlers(container);
    _transientHandlers = TransientHandlers(container);
    _backupHandlers = BackupHandlers(container);
    _syncHandlers = SyncHandlers(container);
    _framingHandlers = FramingHandlers(
      container,
      jobManager: _jobManager,
    );
    _fileSystemHandlers = FileSystemHandlers(container);
    _scienceHandlers = ScienceHandlers(container);

    // Initialize auxiliary device handlers
    _domeHandlers = DomeHandlers(container);
    _safetyMonitorHandlers = SafetyMonitorHandlers(container);
    _auxiliaryHandlers = AuxiliaryHandlers(container);

    // Initialize planetarium handlers
    _planetariumHandlers = PlanetariumHandlers(container);

    // Initialize intelligent scheduler and focus model handlers
    _schedulerHandlers = SchedulerHandlers(container);
    _focusModelHandlers = FocusModelHandlers(container);

    // Wave 6 — broadcast controller that fans out NightshadeEvents from
    // the backend stream to every connected SSE subscriber. Created here
    // (rather than in `start()`) so it can be passed to the handler ctor
    // and survive a stop()/start() pair without rebuilding the handler.
    _runWatchEventBroadcast = StreamController<NightshadeEvent>.broadcast();
    _runWatchHandlers = RunWatchHandlers(
      container: container,
      eventBroadcast: _runWatchEventBroadcast!.stream,
    );

    // Wave 7 Agent 2 — broadcast endpoint handler (live-stacking
    // viewer for EAA / outreach). Lives independently of the run-watch
    // surface because the broadcast is public-by-default whereas
    // run-watch is paired-only.
    _broadcastHandlers = BroadcastHandlers(container: container);

    // P2-10 — Hub owns the producer loop + subscriber registry across
    // socket churn so we never lose the "is anyone listening?" signal
    // between client reconnects. The handler is a thin wrapper that
    // exposes the WS upgrade callback to the router.
    _liveViewStreamHub = LiveViewStreamHub(container: container);
    _liveViewStreamHandlers = LiveViewStreamHandlers(
      container: container,
      hub: _liveViewStreamHub,
    );

    // Wave 7A — WebRTC live-view fan-out. Each session attaches to the
    // SAME hub via attachRaw with a custom sink that pushes binary
    // frames into an outbound RTCDataChannel. No re-encode, no second
    // producer loop.
    _webRtcLiveViewHandlers = WebRtcLiveViewHandlers(
      container: container,
      hub: _liveViewStreamHub,
    );

    // P1-14 — remote log retrieval/tail for mobile operators on
    // headless deployments (Pi/embedded). The handler is stateless
    // beyond what's in the LoggingService it reads from the container.
    _logHandlers = LogHandlers(container);

    // P1-10 — remote calibration library management. Stateless beyond the
    // DAOs it reads from the container; no upstream service to dispose.
    _calibrationHandlers = CalibrationHandlers(container);

    // v46 — unified Calibration Library Manager (browse / match / tag).
    // Stateless beyond the CalibrationLibraryService it reads off the
    // container.
    _calibrationLibraryHandlers = CalibrationLibraryHandlers(container);

    // P1-12 — catalog management. The handler dispatches long-running
    // downloads through the JobManager so the action POST returns
    // {jobId} immediately. Catalog lifecycle events are bridged onto
    // the WS event stream in start() below.
    _catalogHandlers = CatalogHandlers(
      jobManager: _jobManager,
      logger: container.read(loggingServiceProvider),
    );

    // P2-8 — db read endpoints. Reads from existing DAOs; no service
    // dependency, so construction is trivial.
    _dbReadHandlers = DbReadHandlers(container);

    // P2-11 — plugin management endpoints. The service is fetched from
    // the container so test fixtures can override
    // `pluginManagementServiceProvider` to point at a temp directory.
    _pluginHandlers = PluginHandlers(container);

    // P1-2 / P1-3 — REST surface for the JobManager that was constructed
    // earlier (before the device handlers so they could be wired).
    _jobHandlers = JobHandlers(jobManager: _jobManager);

    // P1-5 — REST surface for the SessionOwnershipManager.
    _sessionOwnershipHandlers = SessionOwnershipHandlers(
      manager: _sessionOwnership,
      tokenResolver: _extractBearerToken,
    );
  }
}
