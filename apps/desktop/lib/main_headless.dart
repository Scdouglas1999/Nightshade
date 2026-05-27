import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:path_provider/path_provider.dart';

import 'desktop_app_bootstrap.dart';
import 'desktop_logging_init.dart';
import 'headless_api/auth/pairing_service.dart';
import 'headless_api/auth_policy.dart';
import 'headless_api/tls_provisioner.dart';
import 'headless_api/update_wiring.dart';
import 'headless_api_server.dart';

const _headlessLogSource = 'HeadlessMain';

/// Headless entry point for Nightshade
///
/// This entry point runs without a GUI window, suitable for:
/// - Server/daemon mode
/// - Background sequence execution
/// - Remote control via mobile app or API
///
/// Usage:
///   Windows: flutter run -d windows --target=lib/main_headless.dart
///   Linux:   flutter run -d linux --target=lib/main_headless.dart
///
///   Or build and run:
///   Windows: .\\build\\windows\\x64\\runner\\Release\\nightshade_desktop.exe --headless
///   Linux:   ./build/linux/x64/release/bundle/nightshade_desktop --headless
///
/// Authentication:
///   --auth-token=<token>  Set a specific authentication token
///                         (admin scope)
///   --view-token=<token>  Set a read-only monitoring token
///   --control-token=<token>
///                         Set an imaging-control token
///   --require-auth        Generate a random token
///   --allow-unauthenticated-lan
///                         Bind to the LAN without auth. Unsafe; intended only
///                         for isolated development networks.
///   --cors-origin=<origin>
///                         Add an origin to the CORS allow-list (may be passed
///                         multiple times). Why explicit list: the dashboard's
///                         own origin is always allowed, but cross-origin
///                         control from other web apps must be opted in here.
///   --pairing-print-codes
///                         (P0-3) Print every successful pairing code to
///                         stdout. Required for headless Pi/embedded
///                         deployments where the operator otherwise has no
///                         way to retrieve the code.
///   --tls                 (P0-9) Enable transport encryption. Generates a
///                         self-signed cert under $APPDATA/server.{crt,key}
///                         on first launch and binds HTTPS instead of HTTP.
///   --tls-cert=<path>     (P0-9) Use the supplied certificate PEM instead
///                         of generating a self-signed one.
///   --tls-key=<path>      (P0-9) Use the supplied private-key PEM instead
///                         of generating a self-signed one.
///
///   Environment variables:
///   NIGHTSHADE_AUTH_TOKEN  Authentication token
///   NIGHTSHADE_VIEW_TOKEN  Optional read-only token
///   NIGHTSHADE_CONTROL_TOKEN
///                         Optional imaging-control token
///   NIGHTSHADE_PORT        Server port (default: 8080)
///   NIGHTSHADE_DATA_DIR    Native persistence root (defect maps, etc.). When
///                         unset, matches the GUI application-support path.
///   NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN=true
///                         Same as --allow-unauthenticated-lan
///   NIGHTSHADE_CORS_ORIGINS
///                         Comma-separated CORS allow-list (same effect as
///                         passing --cors-origin repeatedly).
///   NIGHTSHADE_PAIRING_PRINT_CODES=true
///                         Same as --pairing-print-codes.
///   NIGHTSHADE_TLS=true   Same as --tls.
///   NIGHTSHADE_TLS_CERT   Same as --tls-cert=<path>.
///   NIGHTSHADE_TLS_KEY    Same as --tls-key=<path>.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Operator-facing stdout banner. The LoggingService isn't bootable yet
  // (no ProviderContainer), so write directly to stdout. Once the logger
  // is initialised below, all subsequent diagnostics route through it.
  stdout.writeln('Nightshade 2.0 - Headless Mode');
  stdout.writeln('==============================');

  LoggingService? logger;
  ProviderContainer? container;
  HeadlessApiServer? apiServer;
  // Push-notification stream is owned by HeadlessApiServer.stop() (it holds
  // the StreamSubscription internally and cancels it on shutdown); we keep
  // no top-level handle here.
  StreamSubscription<DiskSpaceWatchdogEvent>? diskWatchdogSubscription;
  DiskSpaceGuardService? diskGuard;
  // P1-11: headless OTA update stack. Owned at the entry point so SIGINT
  // can shut both the controller and the LAN push receiver cleanly.
  UpdateStack? updateStack;

  try {
    final appVersion = await loadDesktopAppVersion();
    stdout.writeln('Initializing native bridge and data directories...');
    final bootPaths = await initialiseDesktopLogging();
    stdout.writeln('[OK] Native bridge initialized');
    stdout.writeln('[OK] Data directory: ${bootPaths.dataDirectory}');
    stdout.writeln('[OK] Profile and settings storage initialized');

    stdout.writeln('Initializing services...');
    container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue(appVersion),
        pluginNodeDispatcherOverride(),
        // Audit §11 — even in headless mode we install the palette
        // blueprint override so an upstream UI client (mobile companion,
        // headless API consumer) sees plugin sequence nodes in the
        // palette listing.
        pluginNodePaletteBlueprintsOverride(),
      ],
    );
    final runtimeLogger = container.read(loggingServiceProvider);
    logger = runtimeLogger;
    await runtimeLogger.initialize();
    await initialiseCatalogManager(runtimeLogger);
    // Why unawaited: the backend notifier's local-backend wiring is
    // fire-and-forget; the rest of bootstrap reads `backendProvider`
    // synchronously and `useLocalBackend()` just installs the FfiBackend
    // before any reads occur on this isolate. This matches the original
    // pre-refactor behaviour.
    unawaited(container.read(backendProvider.notifier).useLocalBackend());
    runtimeLogger.info('Services initialized', source: _headlessLogSource);

    final authConfig = _parseAuthConfig(args);
    runtimeLogger.info(
      'Starting headless API server on port ${authConfig.port}',
      source: _headlessLogSource,
    );

    apiServer = await _startHeadlessServices(
      container,
      logger: runtimeLogger,
      authToken: authConfig.token,
      scopedAuthTokens: authConfig.scopedTokens,
      requireAuth: authConfig.requireAuth,
      bindLocalOnly: authConfig.bindLocalOnly,
      port: authConfig.port,
      corsAllowedOrigins: authConfig.corsAllowedOrigins,
      pairingPrintCodes: authConfig.pairingPrintCodes,
      tlsEnabled: authConfig.tlsEnabled,
      tlsCertPath: authConfig.tlsCertPath,
      tlsKeyPath: authConfig.tlsKeyPath,
    );
    runtimeLogger.info('Headless API server started',
        source: _headlessLogSource);

    // P1-6: register `_nightshade._tcp` via mDNS. This MUST happen after
    // `apiServer.start()` so the advertised port is the actually-bound one
    // (matters when the caller started us with port 0). Failures here are
    // logged-and-continue — UDP broadcast and manual entry remain available.
    if (!authConfig.bindLocalOnly) {
      try {
        _mdnsRegistration = await _startMdnsAdvertisement(
          logger: runtimeLogger,
          apiServer: apiServer,
          appVersion: appVersion.version,
        );
      } catch (e, st) {
        // The MdnsServiceRegistration class already swallows NsdError and
        // platform errors internally and routes them through onWarning. This
        // catch-all is a belt-and-braces guard against a programming error
        // (e.g. a future maintainer making the constructor itself throw) so
        // a coding regression in the discovery surface can't take down the
        // whole headless daemon.
        runtimeLogger.warning(
          'Unexpected mDNS registration failure: $e\n$st',
          source: _headlessLogSource,
        );
      }
    } else {
      runtimeLogger.info(
        'Headless server is loopback-only; mDNS advertisement skipped',
        source: _headlessLogSource,
      );
    }

    // P0-1: wire push notifications to the API server so weather aborts,
    // sequence failures, and guiding-lost events are delivered as
    // `type:'push_notification'` envelopes to connected phones during
    // unattended overnight runs. GUI mode (desktop_app_bootstrap.dart:234)
    // already does this; headless mode previously did not, so phones never
    // saw a push notification for a sequence failure on a Pi-hosted server.
    try {
      final pushService = container.read(pushNotificationServiceProvider);
      apiServer.setPushNotificationStream(
        pushService.notifications.map((n) => n.toJson()),
      );
      runtimeLogger.info(
        'Push notifications wired to headless API server',
        source: _headlessLogSource,
      );
    } catch (e, st) {
      // Push wiring failure is non-fatal — the rest of the server still
      // works — but the operator needs to know that overnight push
      // notifications are off. Surface a hard warning instead of a quiet
      // fallback (the user's "errors are a feature" directive).
      runtimeLogger.error(
        'Failed to wire push notifications: $e\n$st',
        source: _headlessLogSource,
      );
    }

    // P0-6: wire the disk-space watchdog. In GUI mode the sequencer
    // controller subscribes to this stream and pauses on blocking severity;
    // in headless mode nothing was consuming it, so the rig would keep
    // imaging past the abort threshold until raw write() failures aborted
    // the sequence mid-frame. Hook the watchdog into backend.sequencerStop
    // here so overnight unattended runs halt cleanly before the disk fills.
    try {
      final guard = container.read(diskSpaceGuardProvider);
      diskGuard = guard;
      diskWatchdogSubscription = await _startDiskSpaceWatchdog(
        container: container,
        guard: guard,
        logger: runtimeLogger,
      );
    } catch (e, st) {
      runtimeLogger.error(
        'Disk-space watchdog failed to start: $e\n$st',
        source: _headlessLogSource,
      );
    }

    // P1-11: provision the OTA update stack and wire it into the
    // headless API server. Without this, paired phones could not check,
    // download, or apply updates on a headless host because the entire
    // /api/system/update/* surface would 404. Failures here are logged
    // and tolerated — OTA is non-essential to imaging — but the operator
    // sees a warning so they know why the endpoints are unavailable.
    try {
      final stack = await provisionUpdateStack(
        currentVersion: appVersion.version,
        currentBuildNumber: appVersion.buildNumber,
        logger: runtimeLogger,
        logSource: _headlessLogSource,
      );
      if (stack != null) {
        updateStack = stack;
        apiServer.setUpdateController(stack.controller);
        runtimeLogger.info(
          'OTA update endpoints wired to headless API server',
          source: _headlessLogSource,
          fields: {
            'channel': stack.controller.channel,
            'serverUrl':
                stack.controller.updateServerUrl ?? 'unconfigured',
          },
        );

        // Best-effort start the LAN-push receiver. It requires a trusted
        // public key compiled into the build (Ed25519 signature
        // verification); when that's absent, startServer throws and we
        // log-and-continue — HTTPS pull updates still work.
        try {
          await stack.lanPushReceiver.startServer();
          runtimeLogger.info(
            'LAN push receiver started on port 45680',
            source: _headlessLogSource,
          );
        } catch (e) {
          runtimeLogger.warning(
            'LAN push receiver did not start (no trusted public key '
            'compiled in?). HTTPS pull updates remain available.',
            source: _headlessLogSource,
            fields: {'error': '$e'},
          );
        }
      } else {
        runtimeLogger.info(
          'OTA update stack not provisioned (no server URL configured); '
          '/api/system/update/* will be unavailable. Set '
          'NIGHTSHADE_UPDATE_SERVER to enable.',
          source: _headlessLogSource,
        );
      }
    } catch (e, st) {
      runtimeLogger.warning(
        'OTA update stack failed to provision; /api/system/update/* '
        'will be unavailable for this session',
        source: _headlessLogSource,
        fields: {'error': '$e', 'stack': '$st'},
      );
    }

    // Operator-facing console message announcing service readiness. Logged
    // through the structured logger too so it shows up in log files alongside
    // the timestamped service-started events.
    stdout.writeln('\nNightshade is running in headless mode.');
    stdout.writeln('Press Ctrl+C to stop.\n');
    runtimeLogger.info('Headless mode running; waiting for SIGINT/SIGTERM',
        source: _headlessLogSource);

    Future<void> shutdown(String reason) async {
      logger?.info('$reason; shutting down', source: _headlessLogSource);
      await diskWatchdogSubscription?.cancel();
      diskGuard?.stop();
      _discoverySocket?.stop();
      // mDNS unregister BEFORE the HTTP server stops so peers stop trying to
      // dial a port that is about to go away. Failures inside stop() are
      // already swallowed and logged by the class itself.
      await _mdnsRegistration?.stop();
      _mdnsRegistration = null;
      // P1-11: detach the update controller from the server BEFORE
      // stopping it so the controller's event subscription is cancelled
      // cleanly. The stack dispose call below then closes the controller
      // and stops the LAN push receiver.
      apiServer?.setUpdateController(null);
      await apiServer?.stop();
      await updateStack?.dispose();
      container?.dispose();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) async {
      await shutdown('Received SIGINT');
    });

    if (Platform.isLinux || Platform.isMacOS) {
      ProcessSignal.sigterm.watch().listen((_) async {
        await shutdown('Received SIGTERM');
      });
    }

    final backend = container.read(diagnosticsBackendProvider);
    backend.eventStream.listen(
      (event) => apiServer?.broadcastEvent(event),
      onError: (Object error, StackTrace stackTrace) {
        logger?.warning(
          'Backend event stream error: $error',
          source: _headlessLogSource,
        );
      },
    );

    while (true) {
      await Future.delayed(const Duration(seconds: 1));
    }
  } catch (e, stackTrace) {
    logger?.critical(
      'Error starting headless mode: $e\n$stackTrace',
      source: _headlessLogSource,
    );
    // Always also surface to stderr — if the logger itself failed to
    // initialise (the path that often triggers this catch), the operator
    // still needs to see why the daemon refused to start.
    stderr.writeln('Error starting headless mode: $e');
    stderr.writeln('Stack trace: $stackTrace');
    await diskWatchdogSubscription?.cancel();
    diskGuard?.stop();
    await _mdnsRegistration?.stop();
    _mdnsRegistration = null;
    apiServer?.setUpdateController(null);
    await apiServer?.stop();
    await updateStack?.dispose();
    container?.dispose();
    exit(1);
  }
}

class _AuthConfig {
  final String? token;
  final bool requireAuth;
  final bool bindLocalOnly;
  final int port;
  final Map<String, HeadlessTokenScope> scopedTokens;
  final List<String> corsAllowedOrigins;
  final bool pairingPrintCodes;
  final bool tlsEnabled;
  final String? tlsCertPath;
  final String? tlsKeyPath;

  _AuthConfig({
    this.token,
    this.requireAuth = false,
    this.bindLocalOnly = true,
    this.port = 8080,
    this.scopedTokens = const {},
    this.corsAllowedOrigins = const [],
    this.pairingPrintCodes = false,
    this.tlsEnabled = false,
    this.tlsCertPath,
    this.tlsKeyPath,
  });
}

_AuthConfig _parseAuthConfig(List<String> args) {
  String? token;
  var requireAuth = false;
  var allowUnauthenticatedLan =
      _envFlag('NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN');
  var port = 8080;
  final scopedTokens = <String, HeadlessTokenScope>{};
  final corsAllowedOrigins = <String>[];
  var pairingPrintCodes = _envFlag('NIGHTSHADE_PAIRING_PRINT_CODES');
  var tlsEnabled = _envFlag('NIGHTSHADE_TLS');
  String? tlsCertPath = _trimToNull(Platform.environment['NIGHTSHADE_TLS_CERT']);
  String? tlsKeyPath = _trimToNull(Platform.environment['NIGHTSHADE_TLS_KEY']);

  token = Platform.environment['NIGHTSHADE_AUTH_TOKEN'];
  _addScopedTokenFromEnv(
    scopedTokens,
    'NIGHTSHADE_VIEW_TOKEN',
    HeadlessTokenScope.view,
  );
  _addScopedTokenFromEnv(
    scopedTokens,
    'NIGHTSHADE_CONTROL_TOKEN',
    HeadlessTokenScope.control,
  );
  if (Platform.environment['NIGHTSHADE_PORT'] != null) {
    port = int.tryParse(Platform.environment['NIGHTSHADE_PORT']!) ?? 8080;
  }

  // Why env-first: NIGHTSHADE_CORS_ORIGINS is the systemd/docker idiom; CLI
  // overrides allow operators to extend the list at launch time.
  final envCors = Platform.environment['NIGHTSHADE_CORS_ORIGINS'];
  if (envCors != null && envCors.trim().isNotEmpty) {
    for (final raw in envCors.split(',')) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        corsAllowedOrigins.add(trimmed);
      }
    }
  }

  for (final arg in args) {
    if (arg.startsWith('--auth-token=')) {
      token = arg.substring('--auth-token='.length);
    } else if (arg == '--require-auth') {
      requireAuth = true;
    } else if (arg == '--allow-unauthenticated-lan') {
      allowUnauthenticatedLan = true;
    } else if (arg.startsWith('--view-token=')) {
      _addScopedToken(
        scopedTokens,
        arg.substring('--view-token='.length),
        HeadlessTokenScope.view,
      );
    } else if (arg.startsWith('--control-token=')) {
      _addScopedToken(
        scopedTokens,
        arg.substring('--control-token='.length),
        HeadlessTokenScope.control,
      );
    } else if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring('--port='.length)) ?? port;
    } else if (arg.startsWith('--cors-origin=')) {
      final value = arg.substring('--cors-origin='.length).trim();
      if (value.isNotEmpty) {
        corsAllowedOrigins.add(value);
      }
    } else if (arg == '--pairing-print-codes') {
      pairingPrintCodes = true;
    } else if (arg == '--tls') {
      tlsEnabled = true;
    } else if (arg.startsWith('--tls-cert=')) {
      tlsCertPath = _trimToNull(arg.substring('--tls-cert='.length));
    } else if (arg.startsWith('--tls-key=')) {
      tlsKeyPath = _trimToNull(arg.substring('--tls-key='.length));
    }
  }

  if (token != null && token.trim().isEmpty) {
    token = null;
  }

  // Explicit cert/key paths imply TLS even without --tls; otherwise the
  // operator's paths would be silently ignored. Same rule for the env-var
  // equivalents — passing NIGHTSHADE_TLS_CERT must enable TLS.
  if (tlsCertPath != null || tlsKeyPath != null) {
    tlsEnabled = true;
  }

  final hasAuthentication =
      token != null || requireAuth || scopedTokens.isNotEmpty;
  return _AuthConfig(
    token: token,
    requireAuth: requireAuth,
    bindLocalOnly: !hasAuthentication && !allowUnauthenticatedLan,
    port: port,
    scopedTokens: Map.unmodifiable(scopedTokens),
    corsAllowedOrigins: List.unmodifiable(corsAllowedOrigins),
    pairingPrintCodes: pairingPrintCodes,
    tlsEnabled: tlsEnabled,
    tlsCertPath: tlsCertPath,
    tlsKeyPath: tlsKeyPath,
  );
}

void _addScopedTokenFromEnv(
  Map<String, HeadlessTokenScope> scopedTokens,
  String envName,
  HeadlessTokenScope scope,
) {
  _addScopedToken(scopedTokens, Platform.environment[envName], scope);
}

void _addScopedToken(
  Map<String, HeadlessTokenScope> scopedTokens,
  String? token,
  HeadlessTokenScope scope,
) {
  final normalizedToken = token?.trim();
  if (normalizedToken == null || normalizedToken.isEmpty) {
    return;
  }
  scopedTokens[normalizedToken] = scope;
}

bool _envFlag(String name) {
  final value = Platform.environment[name]?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

String? _trimToNull(String? input) {
  final t = input?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}

Future<HeadlessApiServer> _startHeadlessServices(
  ProviderContainer container, {
  required LoggingService logger,
  String? authToken,
  Map<String, HeadlessTokenScope> scopedAuthTokens = const {},
  bool requireAuth = false,
  bool bindLocalOnly = true,
  int port = 8080,
  List<String> corsAllowedOrigins = const [],
  bool pairingPrintCodes = false,
  bool tlsEnabled = false,
  String? tlsCertPath,
  String? tlsKeyPath,
}) async {
  try {
    container.read(databaseProvider);
    logger.info('Database initialized', source: _headlessLogSource);
  } catch (e) {
    logger.critical(
      'Database initialization failed: $e — headless server cannot function without a database',
      source: _headlessLogSource,
    );
    rethrow;
  }

  // P0-9: provision the TLS context BEFORE bind so a cert generation
  // failure surfaces as a clean startup error instead of an HTTPS 5xx
  // mid-flight.
  TlsProvisionResult? tlsProvision;
  if (tlsEnabled) {
    final appData = await getApplicationSupportDirectory();
    try {
      tlsProvision = await provisionTlsContext(
        appDataDirectory: appData.path,
        certPath: tlsCertPath,
        keyPath: tlsKeyPath,
      );
      logger.info(
        'TLS provisioning OK: cert=${tlsProvision.certificatePath} '
        'spki_sha256=${tlsProvision.publicKeyFingerprintSha256} '
        'validity=${tlsProvision.validity.notBefore.toUtc().toIso8601String()}..'
        '${tlsProvision.validity.notAfter.toUtc().toIso8601String()}',
        source: _headlessLogSource,
      );
    } catch (e, st) {
      logger.critical(
        'TLS provisioning failed: $e\n$st — refusing to start the server. '
        'Remove --tls to fall back to plain HTTP, or pass --tls-cert + '
        '--tls-key with a hand-issued PEM pair.',
        source: _headlessLogSource,
      );
      rethrow;
    }
  }

  if (!bindLocalOnly) {
    try {
      final appVersion = container.read(appVersionProvider);
      await _startDiscoveryServer(
        logger: logger,
        advertisedPort: port,
        appVersion: appVersion.version,
      );
      logger.info(
        'Discovery server started on UDP port 45679 (advertising $port)',
        source: _headlessLogSource,
      );
    } catch (e) {
      logger.warning('Discovery server failed: $e', source: _headlessLogSource);
    }
  } else {
    logger.info(
      'Headless server is bound to loopback; LAN discovery is disabled',
      source: _headlessLogSource,
    );
  }

  // P0-2: eagerly construct the PairingService so the server can hydrate
  // _pairedSessionTokens from the on-disk Drift DB at startup. Without
  // this, the server lazy-creates the service only when a client hits
  // /api/pairing/verify, and any previously-paired clients are rejected
  // with 403 until they re-pair — exactly the silent-eviction bug the
  // audit flagged. Construction is cheap (no DB I/O); the actual file
  // open happens the first time a query runs.
  final pairingService = PairingService();

  final apiServer = HeadlessApiServer(
    port: port,
    container: container,
    authToken: authToken,
    scopedAuthTokens: scopedAuthTokens,
    requireAuth: requireAuth,
    bindLocalOnly: bindLocalOnly,
    corsAllowedOrigins: corsAllowedOrigins,
    pairingPrintCodes: pairingPrintCodes,
    tlsContext: tlsProvision?.securityContext,
    tlsPublicKeyFingerprint: tlsProvision?.publicKeyFingerprintSha256,
    pairingService: pairingService,
  );

  await apiServer.start();
  logger.info('API server started on port $port', source: _headlessLogSource);

  // P1-19: spin up the LAN UDP push broadcaster when the server is
  // exposed on the LAN. Loopback-only deployments have no LAN clients to
  // wake, so the broadcaster is skipped (its `start()` would still warn
  // about no interfaces — clearer to skip explicitly). The broadcaster's
  // fingerprint MUST match the server's `/api/info` fingerprint, which
  // is the same one paired phones learned during enrollment; that
  // identity binding is what stops a malicious LAN host from forging
  // alerts (see lan_push_broadcaster.dart header for the threat model).
  if (!bindLocalOnly) {
    try {
      final pushBroadcaster = LanPushBroadcaster(
        serverFingerprint: apiServer.serverFingerprint,
        logger: (level, message, {fields}) {
          switch (level) {
            case LanPushLogLevel.info:
              logger.info(message,
                  source: _headlessLogSource, fields: fields);
              break;
            case LanPushLogLevel.warning:
              logger.warning(message,
                  source: _headlessLogSource, fields: fields);
              break;
            case LanPushLogLevel.error:
              logger.error(message,
                  source: _headlessLogSource, fields: fields);
              break;
          }
        },
      );
      apiServer.setLanPushBroadcaster(pushBroadcaster);
      await pushBroadcaster.start();
      logger.info(
        'LAN push broadcaster started '
        '(port=${pushBroadcaster.port}, interfaces=${pushBroadcaster.activeSinkCount})',
        source: _headlessLogSource,
      );
    } catch (e, st) {
      // Bind failure is non-fatal — see P1-19 doc reference in
      // setPushNotificationStream. Phones still get critical pushes via
      // the WebSocket when their WS is alive; UDP is the supplement.
      logger.warning(
        'LAN push broadcaster failed to start: $e\n$st',
        source: _headlessLogSource,
      );
    }
  } else {
    logger.info(
      'Headless server is loopback-only; LAN push broadcaster is skipped',
      source: _headlessLogSource,
    );
  }

  try {
    final interfaces = await NetworkInterface.list();
    String? localIp;

    for (final interface in interfaces) {
      final isLoopback = interface.name.contains('lo') ||
          interface.name.contains('Loopback');
      if (isLoopback) {
        continue;
      }
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          localIp = addr.address;
          break;
        }
      }
      if (localIp != null) {
        break;
      }
    }

    final scheme = tlsProvision != null ? 'https' : 'http';

    // Operator-facing connect-URL block. These are intentionally on stdout
    // (not the structured logger) so a sysadmin invoking the headless server
    // sees them immediately in the console; the redacted token form keeps
    // the captured stdout safe to share for debugging.
    if (!bindLocalOnly && localIp != null) {
      stdout.writeln('\n  Mobile devices can connect to:');
      stdout.writeln('    $scheme://$localIp:$port');
      if (apiServer.effectiveAuthToken != null) {
        stdout.writeln('\n  Authentication required:');
        stdout.writeln(
            '    Authorization: Bearer ${_redactToken(apiServer.effectiveAuthToken!)}');
      } else {
        stdout.writeln(
            '\n  WARNING: unauthenticated LAN control is enabled for this run.');
      }
      if (tlsProvision != null) {
        stdout.writeln(
            '  TLS fingerprint (SPKI SHA-256): ${tlsProvision.publicKeyFingerprintSha256}');
      }
      stdout.writeln('');
    } else {
      stdout.writeln('\n  Headless API is available on:');
      stdout.writeln('    $scheme://127.0.0.1:$port');
      stdout.writeln(
          '  Add --require-auth or --auth-token to expose authenticated LAN access.');
      if (tlsProvision != null) {
        stdout.writeln(
            '  TLS fingerprint (SPKI SHA-256): ${tlsProvision.publicKeyFingerprintSha256}');
      }
      stdout.writeln('');
    }
  } catch (_) {
    // Best-effort local IP discovery only.
  }

  return apiServer;
}

/// P0-6: subscribe to [DiskSpaceGuardService.events] and translate the
/// stream into structured log entries plus a hard sequencer-stop on the
/// blocking severity. The watchdog itself is started here against the
/// configured capture path so the headless run does not need an interactive
/// "Start watchdog" button.
///
/// The watchdog runs even when no sequence is active so the operator's logs
/// always show why a sequence aborts later if the disk fills overnight.
Future<StreamSubscription<DiskSpaceWatchdogEvent>?> _startDiskSpaceWatchdog({
  required ProviderContainer container,
  required DiskSpaceGuardService guard,
  required LoggingService logger,
}) async {
  // The capture path lives in the settings store. We listen to changes so a
  // mid-run setting change (the operator pointing at a different drive)
  // does not leave the watchdog polling a stale path.
  final settings = await container.read(appSettingsProvider.future);
  final initialPath = settings.imageOutputPath;
  if (initialPath.isEmpty) {
    logger.warning(
      'Disk-space watchdog disabled: no capture directory configured. '
      'Set the capture path in App Settings to enable overnight disk-fill '
      'protection.',
      source: _headlessLogSource,
    );
    return null;
  }

  guard.start(capturePath: initialPath);
  logger.info(
    'Disk-space watchdog started for capturePath=$initialPath',
    source: _headlessLogSource,
  );

  final subscription = guard.events.listen(
    (event) async {
      switch (event.severity) {
        case DiskSpaceSeverity.blocking:
          logger.critical(
            '[disk-watchdog] BLOCKING: ${event.message} — '
            'commanding sequencer to stop.',
            source: _headlessLogSource,
          );
          try {
            final backend = container.read(sequencerBackendProvider);
            await backend.sequencerStop();
            logger.info(
              '[disk-watchdog] Sequencer stop command issued successfully',
              source: _headlessLogSource,
            );
          } catch (e, st) {
            logger.error(
              '[disk-watchdog] Sequencer stop failed: $e\n$st — '
              'the next exposure will likely write a truncated FITS frame '
              'before the OS fails the write outright.',
              source: _headlessLogSource,
            );
          }
          break;
        case DiskSpaceSeverity.warning:
          logger.warning(
            '[disk-watchdog] ${event.message}',
            source: _headlessLogSource,
          );
          break;
        case DiskSpaceSeverity.info:
          logger.info(
            '[disk-watchdog] ${event.message}',
            source: _headlessLogSource,
          );
          break;
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      logger.error(
        '[disk-watchdog] Event stream error: $error\n$stackTrace',
        source: _headlessLogSource,
      );
    },
  );

  return subscription;
}

/// Redact a bearer token for log output: shows the first 4 and last 4
/// characters, masks the middle. Why: the headless server's first-run
/// message previously printed the full token via debugPrint, which would
/// persist in any log file the console output is captured to.
String _redactToken(String token) {
  if (token.length <= 8) return '*' * token.length;
  return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
}

DiscoveryBroadcaster? _discoverySocket;
MdnsServiceRegistration? _mdnsRegistration;

Future<void> _startDiscoveryServer({
  required LoggingService logger,
  required int advertisedPort,
  required String appVersion,
}) async {
  _discoverySocket = await NightshadeDiscovery.startBroadcasting(
    webPort: advertisedPort,
    signalingPort: advertisedPort,
    name: 'Nightshade Headless',
    version: appVersion,
  );
  logger.info(
    'Broadcasting headless server discovery beacons for port $advertisedPort',
    source: _headlessLogSource,
  );
}

/// P1-6: register `_nightshade._tcp` via mDNS so phones on modern Wi-Fi
/// (client-isolation enabled) and Tailscale segments discover the server
/// without UDP broadcast.
///
/// The registration is additive — failures (Avahi missing, Bonjour service
/// stopped, no permission) log a warning and continue. The UDP broadcaster
/// above remains the fallback for `nsd`-free clients.
Future<MdnsServiceRegistration?> _startMdnsAdvertisement({
  required LoggingService logger,
  required HeadlessApiServer apiServer,
  required String appVersion,
}) async {
  final txt = <String, String>{
    'version': appVersion,
    'scheme': apiServer.isTlsActive ? 'https' : 'http',
    'fingerprint': apiServer.serverFingerprint,
    'pairingSupported': 'true',
    'name': 'Nightshade Headless',
  };
  final registration = MdnsServiceRegistration(
    name: 'Nightshade Headless',
    port: apiServer.actualPort,
    txt: txt,
    onWarning: (msg) =>
        logger.warning(msg, source: _headlessLogSource),
  );
  await registration.start();
  if (registration.isRegistered) {
    logger.info(
      'mDNS advertisement active: _nightshade._tcp port=${apiServer.actualPort} '
      'scheme=${txt['scheme']} fingerprint=${apiServer.serverFingerprint}',
      source: _headlessLogSource,
    );
  }
  return registration;
}
