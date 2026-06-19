// Part of ../main.dart -- extracted for maintainability.
//
// Discovery and pairing operations: the user-facing entry points that
// FIND or NAME a server (auto-discovery, QR scan, manual entry, Tailscale
// onboarding, the relay-connect dialog, the saved-servers screen) and the
// code-pairing dialog. Each ultimately hands a resolved
// [DiscoveredServer] to [_connectToServer] (or routes through
// [_connectViaRelay]) in the (re)connect/disconnect ops mixin.
//
// Shared session state lives in [_MobileConnectionState]; this mixin
// constrains `on` it so it can read/write the same fields.
part of '../main.dart';

mixin _MobileDiscoveryOps on _MobileConnectionState {
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
        developer.log(
          'Found server: ${server.name} at ${server.host}',
          name: 'Discovery',
          level: 800,
        );

        // Save for future reconnects
        await _connectToServer(server);
      } else {
        developer.log(
          'No server found via any method',
          name: 'Discovery',
          level: 900,
        );
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error =
              'No Nightshade server found on this network.\n\n'
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
      developer.log(
        'Discovery error: $e',
        name: 'Discovery',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error =
            'Discovery failed: $e\n\nTry entering the IP address manually or scan QR code.';
      });
    }
  }

  @override
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
                    'Enter the pairing code shown on the appliance. Read it '
                    'from the pairing page in a browser — open '
                    'http://$host:$port/pair — or from the desktop\'s Remote '
                    'Access screen.',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
        _error =
            result.message ??
            'Pairing failed (${result.statusCode ?? 'unknown'}).';
      });
      return null;
    }

    return result.token;
  }

  /// Prompt for a relay URL + appliance id, then dial through the relay.
  /// Uses the connection-screen navigator context (the same one the QR scanner
  /// and pairing dialogs use) so the dialog mounts inside the MaterialApp.
  Future<void> _showRelayConnectDialog() async {
    // Prefill the relay URL + appliance id from a previously-connected relay
    // row so a returning operator taps Connect instead of re-reading the id
    // off the headless daemon. loadAll() is sorted most-recent-first. Done
    // before grabbing the UI context so the context is fetched fresh on the
    // far side of this await.
    String initialRelayUrl = '';
    String initialApplianceId = '';
    bool initialAllowInsecure = false;
    try {
      final saved = await ref.read(savedServersServiceProvider).loadAll();
      for (final s in saved) {
        if (s.isRelay) {
          initialRelayUrl = s.relayUrl ?? '';
          initialApplianceId = s.relayApplianceId ?? '';
          initialAllowInsecure = s.relayAllowInsecureTls;
          break;
        }
      }
    } catch (e) {
      developer.log(
        'relay prefill lookup failed: $e',
        name: 'Relay',
        level: 900,
      );
    }
    if (!mounted) return;

    final dialogContext = _connectionUiContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final relayController = TextEditingController(text: initialRelayUrl);
    final idController = TextEditingController(text: initialApplianceId);
    var allowInsecure = initialAllowInsecure;

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
                  onChanged: (v) => setLocal(() => allowInsecure = v ?? false),
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

  /// Open the Saved Servers screen from the connection screen.
  ///
  /// This is the DEFAULT-UI entry point into the roaming list. The screen's
  /// "Add server" FAB routes back here via [onAddServer]: rather than forking
  /// the QR / manual-entry / discovery plumbing, the callback simply pops the
  /// list so the operator lands back on the connection screen and uses its
  /// existing Search / Scan QR / Enter manually / Tailscale / Relay actions.
  /// Each of those now upserts the rig into Saved Servers on a successful
  /// connect, so the new row appears the next time the list is opened.
  ///
  /// Tapping a saved row connects through the screen's own activate path,
  /// which swaps the backend; [_connectedServer] is repopulated on the next
  /// build via the backend listener, so we simply pop back to the connection
  /// screen here.
  Future<void> _openSavedServers() async {
    final uiContext = _connectionUiContext;
    if (uiContext == null || !uiContext.mounted) {
      setState(() {
        _error = 'Connection UI is not ready yet. Try again in a moment.';
      });
      return;
    }
    await Navigator.of(uiContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SavedServersScreen(
          // "Add server" returns to the connection screen so the operator can
          // use the existing pairing flows. Returning null means "no row added
          // inline" — the screen just closes without a spurious snackbar.
          onAddServer: (screenContext) async {
            Navigator.of(screenContext).pop();
            return null;
          },
        ),
      ),
    );
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
      developer.log(
        'QR scanner failed: $e',
        name: 'Discovery',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
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
        // harvest the code because the pin won't match.
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
    // Prefill the host from a previously-connected rig's recorded tailnet
    // address so a returning operator taps Connect instead of retyping the
    // MagicDNS name. We pick the most-recently-connected saved server that
    // carries a tailscaleHost (loadAll() is sorted most-recent-first). Done
    // before grabbing the UI context so the context is fetched fresh on the
    // far side of this await.
    String? initialHost;
    try {
      final saved = await ref.read(savedServersServiceProvider).loadAll();
      for (final s in saved) {
        if (s.hasTailscaleHost) {
          initialHost = s.tailscaleHost;
          break;
        }
        // A rig whose primary host is itself a tailnet endpoint also seeds the
        // field — it is already a usable Tailscale address.
        if (s.isPrimaryTailscale) {
          initialHost = s.host;
          break;
        }
      }
    } catch (e) {
      // Best-effort prefill — fall through to an empty field on any failure.
      developer.log(
        'tailscale prefill lookup failed: $e',
        name: 'Discovery',
        level: 900,
      );
    }
    if (!mounted) return;

    final uiContext = _connectionUiContext;
    if (uiContext == null || !uiContext.mounted) {
      setState(() {
        _error = 'Connection UI is not ready yet. Try again in a moment.';
      });
      return;
    }
    final result = await TailscaleSetupSheet.show(
      uiContext,
      initialHost: initialHost,
    );
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
}
