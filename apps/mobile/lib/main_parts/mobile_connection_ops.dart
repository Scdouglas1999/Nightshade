// Part of ../main.dart -- extracted for maintainability.
//
// Discovery, pairing, reconnection, and checkpoint-resume operations.
part of '../main.dart';

mixin _NightshadeMobileConnectionOps on ConsumerState<NightshadeMobileApp> {
  /// Navigator for the connection-screen [MaterialApp]. Dialogs and the QR
  /// scanner must use this context — [State.context] sits *above* that
  /// [MaterialApp], so [Navigator.of] on it returns null in release builds.
  final GlobalKey<NavigatorState> _connectionNavigatorKey =
      GlobalKey<NavigatorState>();

  DiscoveredServer? _connectedServer;
  // v4 couch-grade remote: when connected via a self-hosted relay, this holds
  // the loopback tunnel that the whole session rides on. It MUST outlive the
  // backend connect (it is the transport) and be torn down whenever the
  // session ends. Null for direct LAN/Tailscale connections.
  RelayTunnelClient? _activeRelayTunnel;
  bool _isDiscovering = false;
  String? _error;
  String _statusMessage = '';
  final TextEditingController _ipController = TextEditingController(text: '');
  final TextEditingController _accessTokenController =
      TextEditingController(text: '');
  bool _showManualEntry = false;
  bool _skippedConnection = false;
  // Tokens are sensitive — default to obscured. Trailing icon toggles for
  // operators who need to verify the value during pairing.
  bool _accessTokenVisible = false;

  // WebSocket-driven liveness replaces the old 5 s HTTP poll (audit §3.6).
  // The NetworkBackend already runs a ping/pong heartbeat and a backoff
  // reconnector; this state machine just translates its connection-state
  // stream into UI banners and a final tear-down once the grace expires.
  StreamSubscription<BackendConnectionState>? _connectionStateSubscription;
  Timer? _disconnectGraceTimer;
  bool _connectionStale = false;

  /// Phase E (iOS): registers this device's APNs token with the paired desktop
  /// for cellular critical-alert delivery. Lazily created on first use so the
  /// MethodChannel handler is only attached when we actually have a session to
  /// register against. Inert on non-iOS.
  PushRegistrationService? _pushRegistration;

  /// How long the WebSocket can stay disconnected before we declare the
  /// session dead and route the user back to the connection screen. The
  /// backend's own reconnector backs off up to 30 s; we wait the full
  /// grace before kicking the user out so transient blips don't drop a
  /// running session.
  static const Duration _connectionGracePeriod = Duration(seconds: 30);

  /// Build context inside the connection [MaterialApp] tree (has Navigator,
  /// Theme, and localizations). Returns null before the first frame.
  BuildContext? get _connectionUiContext =>
      _connectionNavigatorKey.currentContext;

  void _stopConnectionMonitor() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    if (_connectionStale) {
      _connectionStale = false;
      // Clear the global banner so a re-connect doesn't briefly show stale.
      // Skip the write if the State has already been unmounted — the
      // provider scope is gone and the banner will be rebuilt fresh.
      if (mounted) {
        ref.read(connectionStaleProvider.notifier).state = false;
      }
    }
  }

  void _setNetworkHeartbeatPaused(bool paused) {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      return;
    }
    if (paused) {
      backend.pauseWebSocketHeartbeatForAppLifecycle();
    } else {
      backend.resumeWebSocketHeartbeatForAppLifecycle();
    }
  }

  /// Phase E (iOS): register this device's APNs token with the now-connected
  /// desktop so cellular critical alerts can reach a backgrounded phone.
  ///
  /// Gated three ways so it no-ops cleanly off the happy path:
  ///   * non-iOS — `PushRegistrationService` short-circuits internally
  ///     (Platform.isIOS guard), so the channel is never touched and no
  ///     MissingPluginException can fire;
  ///   * not a [NetworkBackend] — local/FFI session, nothing to register with;
  ///   * not paired — empty deviceId, the service skips the POST.
  ///
  /// Best-effort: the service swallows and logs all network/host errors, so a
  /// failure here never disturbs the live session.
  Future<void> _registerPushTokenIfIos() async {
    if (!Platform.isIOS) {
      return;
    }
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      return;
    }
    final deviceId = await MobilePairingService.deviceId();
    final service = _pushRegistration ??= PushRegistrationService();
    await service.ensureRegistered(backend: backend, deviceId: deviceId);
  }

  void _startConnectionMonitor() {
    _stopConnectionMonitor();
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      // Only NetworkBackend exposes the WS heartbeat. Other backends
      // either run locally (FfiBackend) or are explicitly disconnected.
      return;
    }

    _connectionStateSubscription =
        backend.connectionStateStream.listen((state) {
      if (!mounted) return;

      switch (state) {
        case BackendConnectionState.connected:
          _disconnectGraceTimer?.cancel();
          _disconnectGraceTimer = null;
          if (_connectionStale) {
            _connectionStale = false;
            ref.read(connectionStaleProvider.notifier).state = false;
            setState(() {
              _statusMessage = '';
            });
          }
          break;

        case BackendConnectionState.connecting:
          // First-time handshake in flight. Don't show the stale banner
          // yet — there was no prior session to go stale — but reset
          // the disconnect-grace timer so a slow first handshake doesn't
          // trigger the post-disconnect tear-down path.
          _disconnectGraceTimer?.cancel();
          _disconnectGraceTimer = null;
          break;

        case BackendConnectionState.error:
          // Terminal failure (e.g. version mismatch). The backend has
          // stopped retrying so we mirror the disconnected branch for
          // the stale-banner UX but skip the grace timer — there's no
          // point waiting for an automatic recovery that will never
          // happen.
          if (!_connectionStale) {
            _connectionStale = true;
            ref.read(connectionStaleProvider.notifier).state = true;
          }
          break;

        case BackendConnectionState.reconnecting:
        case BackendConnectionState.disconnected:
          // Show the stale-state banner immediately but give the backend
          // a chance to reconnect before we tear the session down.
          if (!_connectionStale) {
            _connectionStale = true;
            ref.read(connectionStaleProvider.notifier).state = true;
          }
          _disconnectGraceTimer ??= Timer(_connectionGracePeriod, () {
            if (!mounted) return;
            final current = ref.read(backendProvider);
            if (current is! NetworkBackend ||
                current.connectionState == BackendConnectionState.connected) {
              return;
            }
            developer.log(
              'WebSocket disconnected for ${_connectionGracePeriod.inSeconds}s — declaring connection lost',
              name: 'Connection',
              level: 1000,
            );
            _stopConnectionMonitor();
            // Drop cached APNs registration state: the next connect may land on
            // a different desktop, and APNs hands back the same token across
            // servers. Without this the target-keyed gate in the service is the
            // only thing forcing a re-POST; resetting here is belt-and-braces so
            // a re-pair can never be assumed already-registered. (Blocker #8.)
            _pushRegistration?.reset();
            ref.read(backendProvider.notifier).disconnect();
            // v4 relay: the session is dead — drop the loopback tunnel too.
            unawaited(_closeActiveRelayTunnel());
            ref.read(connectionStaleProvider.notifier).state = false;
            // Audit P1-18: reset the once-per-lifetime checkpoint flag so
            // a future reconnect re-runs the resume dialog if the server
            // now has a fresh interrupted sequence to recover. Without
            // this, dropping mid-session and reconnecting in the same
            // app lifecycle would silently skip the recovery prompt.
            _checkpointChecked = false;
            setState(() {
              _connectedServer = null;
              _isDiscovering = false;
              _connectionStale = false;
              _error = 'Connection to server lost. Please reconnect.';
              _statusMessage = '';
            });
          });
          break;
      }
    });
  }

  Future<void> _autoConnect() async {
    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Starting discovery...';
    });

    try {
      developer.log('Starting enhanced auto-discovery...', name: 'Discovery');

      // Use enhanced discovery with cascading fallback
      final server = await EnhancedNightshadeDiscovery.discoverWithFallback(
        onStatus: (status) {
          if (mounted) {
            setState(() => _statusMessage = status);
          }
        },
      );

      if (server != null) {
        developer.log('Found server: ${server.name} at ${server.host}',
            name: 'Discovery', level: 800);

        // Save for future reconnects
        await _connectToServer(server);
      } else {
        developer.log('No server found via any method',
            name: 'Discovery', level: 900);
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error = 'No Nightshade server found on this network.\n\n'
              'If you are away from the observatory, use "Connect over '
              'Tailscale" to reach it by its MagicDNS name — local discovery '
              'only works on the same WiFi.\n\n'
              'On the same network, try:\n'
              '- Scanning the QR code from the desktop\n'
              '- Entering the host address manually\n'
              '- Allowing UDP 45679 and HTTP 8080 through the firewall';
        });
      }
    } catch (e, stackTrace) {
      developer.log('Discovery error: $e',
          name: 'Discovery', level: 1000, error: e, stackTrace: stackTrace);
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error =
            'Discovery failed: $e\n\nTry entering the IP address manually or scan QR code.';
      });
    }
  }

  Future<String?> _pairWithServer({
    required String host,
    required int port,
    String scheme = 'http',
    String? pinnedFingerprint,
    String? initialCode,
  }) async {
    final codeController = TextEditingController(text: initialCode ?? '');
    var requestAdmin = false;

    final uiContext = _connectionUiContext;
    if (uiContext == null || !uiContext.mounted) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Connection UI is not ready yet. Try again in a moment.';
      });
      return null;
    }

    final pairingInput = await showDialog<({String code, bool admin})>(
      context: uiContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = NightshadeColors.of(context);
            return NightshadeDialog(
              title: 'Pair with Nightshade',
              icon: LucideIcons.link,
              width: 420,
              actions: [
                NightshadeButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
                NightshadeButton(
                  onPressed: () {
                    final trimmed = codeController.text.trim();
                    if (trimmed.isEmpty) return;
                    Navigator.of(ctx).pop((code: trimmed, admin: requestAdmin));
                  },
                  label: 'Pair',
                  size: ButtonSize.small,
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the pairing code shown on the desktop '
                    '(Remote Access settings or pairing screen).',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      hintText: 'STAR-LYRA-1234',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Grant full admin access'),
                    subtitle: const Text(
                      'Off by default. Enable only if this device should '
                      'manage backups and filesystem paths.',
                    ),
                    value: requestAdmin,
                    onChanged: (value) {
                      setDialogState(() => requestAdmin = value ?? false);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    codeController.dispose();

    if (pairingInput == null || pairingInput.code.isEmpty || !mounted) {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
        });
      }
      return null;
    }

    setState(() {
      _statusMessage = 'Pairing with $host:$port...';
    });

    final pairing = MobilePairingService(
      host: host,
      port: port,
      // A TLS-fronted tailnet rig answers pairing only on https; speaking the
      // wrong scheme returns 400. Carry the scheme learned from the saved
      // server / discovery record.
      scheme: scheme,
      // When the server identity is already known (saved server, prior
      // /api/info), enforce it BEFORE the pairing code is transmitted so a
      // MITM cannot harvest the code. Null on a genuine first-pair where the
      // fingerprint is not yet known (LAN trust establishes it out-of-band).
      pinnedFingerprint: pinnedFingerprint,
    );

    final RemotePairingVerifyResult result;
    try {
      result = await pairing.pairWithCode(
        code: pairingInput.code,
        requestAdminScope: pairingInput.admin,
      );
    } on RemotePairingFingerprintMismatch catch (e) {
      // Fail-closed: the pre-flight identity check refused to send the code.
      // Surface it loudly rather than letting it read as a generic failure.
      if (!mounted) return null;
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = e.message;
      });
      return null;
    }

    if (!mounted) return null;

    if (!result.success || result.token == null || result.token!.isEmpty) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = result.message ??
            'Pairing failed (${result.statusCode ?? 'unknown'}).';
      });
      return null;
    }

    return result.token;
  }

  /// Close any active relay tunnel. Idempotent; safe to call from every
  /// session-teardown path. The backend disconnect that accompanies a session
  /// end races this close — that is fine, the loopback socket simply errors and
  /// the tunnel completes.
  Future<void> _closeActiveRelayTunnel() async {
    final tunnel = _activeRelayTunnel;
    _activeRelayTunnel = null;
    if (tunnel != null) {
      try {
        await tunnel.close();
      } catch (_) {
        // Best-effort teardown only.
      }
    }
  }

  /// v4 couch-grade remote: connect to an appliance through a self-hosted
  /// relay. The relay exposes the remote rig's headless API as a LOCAL
  /// loopback port, so the rest of the connect flow (pairing, HMAC tokens,
  /// the event WebSocket, even TLS if the appliance serves https) reuses the
  /// existing [_connectToServer] path unchanged — the tunnel is just another
  /// base URL pointing at 127.0.0.1.
  ///
  /// [relayUrl] is the operator's relay (ws(s)://host[:port]); [applianceId]
  /// is the id the relay minted for the rig (printed by the daemon on first
  /// contact). End-to-end auth is unchanged; the relay only splices bytes.
  Future<void> _connectViaRelay({
    required String relayUrl,
    required String applianceId,
    bool allowInsecureTls = false,
  }) async {
    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Connecting via relay...';
    });

    final trimmedId = applianceId.trim();
    if (!isValidApplianceId(trimmedId)) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Appliance id must look like xxxx-xxxx-xxxx.';
      });
      return;
    }

    final Uri parsedRelay;
    try {
      parsedRelay = Uri.parse(relayUrl.trim());
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Invalid relay URL: $e';
      });
      return;
    }

    // A fresh tunnel per connect attempt — drop any previous one first.
    await _closeActiveRelayTunnel();

    try {
      final tunnel = await RelayTunnelClient.connect(
        relayUrl: parsedRelay,
        applianceId: trimmedId,
        allowBadTlsCertificate: allowInsecureTls,
        onLog: (message) => developer.log(message, name: 'Relay'),
      );
      _activeRelayTunnel = tunnel;

      // If the relay/appliance drops, surface it: closing the backend kicks
      // the user back to the connection screen through the normal monitor.
      unawaited(tunnel.done.then((_) {
        if (!mounted || !identical(_activeRelayTunnel, tunnel)) return;
        _activeRelayTunnel = null;
      }));

      // The relay carries opaque bytes end-to-end; the appliance behind it may
      // still serve plain http (typical) — the loopback hop is local-only, so
      // dialling the tunnel over http is correct regardless of the appliance's
      // own TLS. The appliance's pairing token / HMAC remain end-to-end.
      final relayServer = DiscoveredServer(
        name: 'Relay: $trimmedId',
        host: '127.0.0.1',
        webPort: tunnel.localPort,
        signalingPort: tunnel.localPort,
        version: '2.0.0',
        mode: 'headless',
        scheme: 'http',
        authRequired: true,
        pairingSupported: true,
      );
      await _connectToServer(relayServer);

      // If the connect failed (no backend swap happened), tear the tunnel back
      // down so we don't leak a loopback listener.
      if (!mounted || ref.read(backendProvider) is! NetworkBackend) {
        await _closeActiveRelayTunnel();
      }
    } on RelayTunnelException catch (e) {
      await _closeActiveRelayTunnel();
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Relay refused the connection (${e.code}): ${e.message}';
      });
    } catch (e) {
      await _closeActiveRelayTunnel();
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Could not reach the relay: $e';
      });
    }
  }

  /// Prompt for a relay URL + appliance id, then dial through the relay.
  /// Uses the connection-screen navigator context (the same one the QR scanner
  /// and pairing dialogs use) so the dialog mounts inside the MaterialApp.
  Future<void> _showRelayConnectDialog() async {
    final dialogContext = _connectionUiContext;
    if (dialogContext == null) return;
    final relayController = TextEditingController();
    final idController = TextEditingController();
    var allowInsecure = false;

    final submitted = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Connect via Relay'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Reach your rig from anywhere through a self-hosted '
                  'Nightshade relay — no VPN or port forwarding. The appliance '
                  'id is printed by the headless daemon on first connect.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relayController,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'wss://relay.example.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: idController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Appliance id',
                    hintText: 'xxxx-xxxx-xxxx',
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowInsecure,
                  onChanged: (v) =>
                      setLocal(() => allowInsecure = v ?? false),
                  title: const Text(
                    'Trust self-signed relay TLS',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Connect'),
              ),
            ],
          ),
        );
      },
    );

    if (submitted != true) return;
    final relayUrl = relayController.text.trim();
    final applianceId = idController.text.trim();
    if (relayUrl.isEmpty || applianceId.isEmpty) {
      setState(() => _error = 'Enter both a relay URL and an appliance id.');
      return;
    }
    await _connectViaRelay(
      relayUrl: relayUrl,
      applianceId: applianceId,
      allowInsecureTls: allowInsecure,
    );
  }

  Future<void> _connectToServer(DiscoveredServer server) async {
    setState(() {
      _statusMessage = 'Connecting to ${server.name}...';
    });

    try {
      // Audit §3.7: do not persist last-server based on synthetic
      // metadata. Track whether the /api/info call actually returned
      // server-supplied fields; if it didn't, we still allow the user
      // to connect for this session but refuse to write the server to
      // disk (next launch should re-discover or re-prompt).
      final fetched = await EnhancedNightshadeDiscovery.fetchServerInfo(server);
      var enrichedServer = fetched ?? server;
      final compatibility = NightshadeServerCompatibility.check(
        enrichedServer.apiVersion ?? enrichedServer.version,
      );
      if (!compatibility.isCompatible) {
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error = compatibility.message;
        });
        return;
      }

      var authToken = enrichedServer.authToken;
      if (enrichedServer.authRequired &&
          (authToken == null || authToken.isEmpty) &&
          enrichedServer.pairingSupported) {
        final pairedToken = await _pairWithServer(
          host: enrichedServer.host,
          port: enrichedServer.webPort,
          scheme: enrichedServer.scheme,
          // Pin the server identity (when known from /api/info) so the pairing
          // pre-flight verifies it before the code is sent — the MITM defense
          // matters most on the Tailscale / Internet-reachable path.
          pinnedFingerprint: enrichedServer.fingerprint,
        );
        if (pairedToken == null) {
          return;
        }
        authToken = pairedToken;
        enrichedServer = enrichedServer.copyWith(authToken: authToken);
      }

      // Test connection first
      final isReachable =
          await EnhancedNightshadeDiscovery.testServerConnection(
        enrichedServer.host,
        enrichedServer.webPort,
        authToken: authToken,
      );

      if (isReachable) {
        developer.log('Connection successful!', name: 'Discovery', level: 800);

        // Update state
        setState(() {
          _connectedServer = enrichedServer;
          _isDiscovering = false;
          _statusMessage = '';
        });

        if (fetched != null) {
          // Only persist after fetchServerInfo confirmed real metadata
          // (audit §3.7). Otherwise we'd cache the manual-entry
          // hardcoded version='2.0.0' / signalingPort=45678 lies.
          await EnhancedNightshadeDiscovery.saveLastServer(enrichedServer);
        } else {
          developer.log(
              'Skipping saveLastServer — /api/info did not return metadata',
              name: 'Discovery',
              level: 900);
        }

        // Update global backend state to use NetworkBackend.
        //
        // P2-2: also wire up the collaboration identity so the backend
        // can emit a `collaboration.join` frame as soon as the WS upgrade
        // completes. The viewerId we derive matches what the server
        // computes from the authenticated bearer (see P2-15 +
        // computeServerFingerprint) so the join is a no-op override
        // rather than an impersonation attempt for hosts with auth on;
        // for auth-off hosts the value still gives the operator a stable
        // human-readable slot label. Display-name preference lookup is
        // best-effort — failures fall back to the platform default.
        final collabIdentity = await _buildCollaborationIdentity(
          enrichedServer.authToken,
        );
        await ref.read(backendProvider.notifier).connect(
              enrichedServer.host,
              enrichedServer.webPort,
              authToken: enrichedServer.authToken,
              // Carry the transport scheme so a TLS-fronted tailnet host is
              // dialled over wss, not plain ws. NetworkBackend classifies the
              // host (LAN vs tailnet) itself for timeout tuning.
              scheme: enrichedServer.scheme,
              // Pin the server identity (when /api/info advertised one) so the
              // handshake verifies it before opening the socket — a mismatch
              // becomes a terminal identity error rather than a connect. This
              // is the MITM defense on the tailnet / Internet-reachable path.
              pinnedFingerprint: enrichedServer.fingerprint,
              collaborationViewerId: collabIdentity.viewerId,
              collaborationDeviceName: collabIdentity.deviceName,
              collaborationDisplayName: collabIdentity.displayName,
            );

        // Start monitoring the WS heartbeat (audit §3.6)
        _startConnectionMonitor();

        // Phase E (iOS): register this device's APNs token with the desktop so
        // it can deliver cellular critical alerts when the phone is asleep and
        // out of LAN-UDP push range. No-op on non-iOS and best-effort (never
        // throws) — a registration failure must not affect the live session.
        unawaited(_registerPushTokenIfIos());

        // Reload host-backed providers now that NetworkBackend is live.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.invalidate(appSettingsProvider);
          ref.invalidate(equipmentProfilesProvider);
        });
      } else {
        final authMessage = enrichedServer.authRequired &&
                (enrichedServer.authToken == null ||
                    enrichedServer.authToken!.isEmpty)
            ? '\n\nThis host requires an access token or paired-device QR code.'
            : '';
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error =
              'Could not connect to ${enrichedServer.host}:${enrichedServer.webPort}\n\nServer may be offline, or this device is not authorized.$authMessage';
        });
      }
    } catch (e, stackTrace) {
      developer.log('Connection error: $e',
          name: 'Discovery', level: 1000, error: e, stackTrace: stackTrace);
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Connection error: $e';
      });
    }
  }

  Future<void> _scanQrCode() async {
    // Scanner now performs strict schema + host-locality validation and pops
    // a confirmed [QrConnectionData] (or null on cancel). The previous
    // string-based round-trip went through a permissive parser.
    final uiContext = _connectionUiContext;
    if (uiContext == null || !uiContext.mounted) {
      setState(() {
        _error = 'Connection UI is not ready yet. Try again in a moment.';
      });
      return;
    }

    QrConnectionData? data;
    try {
      data = await Navigator.of(uiContext).push<QrConnectionData>(
        MaterialPageRoute(
          builder: (_) => const QrScannerScreen(),
          fullscreenDialog: true,
        ),
      );
    } catch (e, stackTrace) {
      developer.log('QR scanner failed: $e',
          name: 'Discovery', level: 1000, error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = 'QR scanner failed: $e';
      });
      return;
    }

    if (data == null) return;

    setState(() {
      _isDiscovering = true;
      _statusMessage = 'Connecting via QR code...';
      _error = null;
    });

    var authToken = data.authToken;
    if ((authToken == null || authToken.isEmpty) &&
        data.pairingCode != null &&
        data.pairingCode!.isNotEmpty) {
      final pairing = MobilePairingService(
        host: data.host,
        port: data.webPort,
        // Speak the scheme the QR advertised (https for a TLS-fronted tailnet
        // rig, which answers pairing only over https).
        scheme: data.scheme,
        // Verify the server's identity BEFORE the pairing code leaves the
        // device. This runs the /api/info pre-flight inside the pairing
        // client; a hostile node presenting its own pairing endpoint cannot
        // harvest the code because the pin won't match. This replaces the old
        // post-hoc fingerprint compare, which only fired after the code had
        // already been transmitted.
        pinnedFingerprint: data.fingerprint,
      );
      final RemotePairingVerifyResult result;
      try {
        result = await pairing.pairWithCode(code: data.pairingCode!);
      } on RemotePairingFingerprintMismatch catch (e) {
        if (!mounted) return;
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error = e.message;
        });
        return;
      }
      if (!mounted) return;
      if (!result.success || result.token == null) {
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error = result.message ?? 'QR pairing failed.';
        });
        return;
      }
      authToken = result.token;
    }

    final server = data.toDiscoveredServer().copyWith(authToken: authToken);
    // Defense-in-depth: even when no pairing happened (the QR already carried a
    // token, so the pre-flight pin check above did not run), re-verify the live
    // server identity against the fingerprint baked into the QR before we hand
    // the connection to _connectToServer. _connectToServer's NetworkBackend
    // also pins via /api/info, but checking here keeps the failure local to the
    // QR flow with a QR-specific message.
    final fetched = await EnhancedNightshadeDiscovery.fetchServerInfo(server);
    if (!mounted) return;
    if (fetched?.fingerprint != null &&
        fetched!.fingerprint != data.fingerprint) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error =
            'Server fingerprint does not match the QR code. Refusing to connect.';
      });
      return;
    }

    await _connectToServer(server);
  }

  /// Off-site onboarding: collect a Tailscale endpoint via the guided
  /// setup sheet, then run it through the canonical [_connectToServer]
  /// path (which handles /api/info enrichment, pairing, compatibility, and
  /// persistence). This is the primary path when the phone is NOT on the
  /// observatory LAN — discovery finds nothing because Tailscale has no
  /// broadcast domain, so the operator reaches the rig by its MagicDNS
  /// name / 100.x address.
  Future<void> _connectViaTailscale() async {
    final uiContext = _connectionUiContext;
    if (uiContext == null || !uiContext.mounted) {
      setState(() {
        _error = 'Connection UI is not ready yet. Try again in a moment.';
      });
      return;
    }
    final result = await TailscaleSetupSheet.show(uiContext);
    if (result == null || !mounted) return;

    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Connecting to ${result.host}:${result.port}...';
    });

    // Build a DiscoveredServer carrying the operator's scheme + token so
    // fetchServerInfo probes the right protocol and the pairing branch in
    // _connectToServer only fires when no token was supplied.
    final server = DiscoveredServer(
      name: result.host,
      host: result.host,
      webPort: result.port,
      signalingPort: 45678,
      version: '2.0.0',
      mode: 'headless',
      scheme: result.scheme,
      authToken: result.authToken,
      authRequired: result.authToken == null,
      pairingSupported: true,
    );
    await _connectToServer(server);
  }

  Future<void> _connectManually() async {
    final input = _ipController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _error = 'Please enter a host name or IP address';
      });
      return;
    }

    var host = input;
    var port = 8080;
    final separator = input.lastIndexOf(':');
    if (separator > 0 && separator < input.length - 1) {
      final parsedPort = int.tryParse(input.substring(separator + 1));
      if (parsedPort != null) {
        host = input.substring(0, separator);
        port = parsedPort;
      }
    }

    var authToken = _accessTokenController.text.trim().isEmpty
        ? null
        : _accessTokenController.text.trim();

    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Connecting to $host:$port...';
    });

    var server = DiscoveredServer(
      name: 'Nightshade Server',
      host: host,
      webPort: port,
      signalingPort: 45678,
      version: '2.0.0',
      mode: 'headless',
      authToken: authToken,
      pairingSupported: true,
    );

    final fetched = await EnhancedNightshadeDiscovery.fetchServerInfo(server);
    if (fetched != null) {
      server = fetched;
      if ((authToken == null || authToken.isEmpty) &&
          server.authRequired &&
          server.pairingSupported) {
        final paired = await _pairWithServer(
          host: host,
          port: port,
          // Use the scheme + identity the enriched /api/info reported so a
          // TLS-fronted host pairs over https and the pre-flight pins the
          // server before the code is sent.
          scheme: server.scheme,
          pinnedFingerprint: server.fingerprint,
        );
        if (paired == null) {
          return;
        }
        authToken = paired;
        server = server.copyWith(authToken: authToken);
      }
    } else {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error =
            'Cannot reach http://$host:$port/api/info from this device.\n\n'
            'On the Windows PC: confirm Settings → Remote Access shows '
            '"Running", note the LAN URL, and allow port $port through '
            'Windows Firewall (private network).\n\n'
            'On the tablet: open that URL in Chrome — you should see JSON. '
            'Then try Connect again or scan the QR after starting pairing.';
      });
      return;
    }

    await _connectToServer(server);
  }

  void _skipConnection() {
    setState(() {
      _skippedConnection = true;
      _isDiscovering = false;
      _error = null;
    });
    // Ensure backend is disconnected. Drop cached APNs registration so a later
    // connect to a (possibly different) desktop re-POSTs the token rather than
    // assuming it is already registered there (Blocker #8).
    _pushRegistration?.reset();
    ref.read(backendProvider.notifier).disconnect();
    // v4 relay: tear down any active loopback tunnel on explicit skip.
    unawaited(_closeActiveRelayTunnel());
  }

  bool _checkpointChecked = false;

  void _checkForCheckpoint(BuildContext context, WidgetRef ref) {
    // Only check once after connection
    if (_checkpointChecked) return;
    _checkpointChecked = true;

    // Schedule the check for after the current frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final executor = ref.read(sequenceExecutorProvider);

        // Initialize checkpoint directory
        final docsDir = await getApplicationDocumentsDirectory();
        await executor.initializeCheckpoints(docsDir.path);

        // Get checkpoint info
        final info = await executor.getCheckpointInfo();
        if (info == null || !info.canResume) return;

        // Show dialog to user
        if (context.mounted) {
          final shouldResume = await CheckpointResumeDialog.show(context, info);

          if (shouldResume == true) {
            // Resume from checkpoint
            try {
              await executor.resumeFromCheckpoint();
              if (context.mounted) {
                final colors = Theme.of(context).extension<NightshadeColors>();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Sequence resumed from checkpoint'),
                    backgroundColor: colors?.success ??
                        Theme.of(context).colorScheme.primary,
                  ),
                );
              }
            } catch (e) {
              // [Wave 6D error parsing] — surface parsed ServerError
              // {code, message} via the shared mobile helper so the
              // operator sees a machine-actionable code instead of
              // "Exception: Future was already completed."
              if (context.mounted) {
                showApiErrorWithPrefix(context, 'Failed to resume', e);
              }
            }
          } else if (shouldResume == false) {
            // Discard checkpoint
            await executor.discardCheckpoint();
          }
        }
      } catch (e) {
        developer.log('Error checking for checkpoint: $e',
            name: 'Main', level: 1000);
      }
    });
  }
}
