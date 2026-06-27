import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

import 'desktop_app_bootstrap.dart';
import 'desktop_logging_init.dart';
import 'headless/headless_auth_config.dart';
import 'headless/headless_disk_watchdog_bootstrap.dart';
import 'headless/headless_discovery_bootstrap.dart';
import 'headless/headless_relay_bootstrap.dart';
import 'headless/headless_services_bootstrap.dart';
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
///   Linux:   ./build/linux/`<arch>`/release/bundle/nightshade_desktop --headless
///
/// Authentication:
///   --auth-token=`<token>`  Set a specific authentication token
///                         (admin scope)
///   --view-token=`<token>`  Set a read-only monitoring token
///   --control-token=`<token>`
///                         Set an imaging-control token
///   --require-auth        Generate a random token
///   --allow-unauthenticated-lan
///                         Bind to the LAN without auth. Unsafe; intended only
///                         for isolated development networks.
///   --cors-origin=`<origin>`
///                         Add an origin to the CORS allow-list (may be passed
///                         multiple times). Why explicit list: the dashboard's
///                         own origin is always allowed, but cross-origin
///                         control from other web apps must be opted in here.
///   --pairing-print-codes
/// Print every successful pairing code to
///                         stdout. Required for headless Pi/embedded
///                         deployments where the operator otherwise has no
///                         way to retrieve the code.
///   --tls Enable transport encryption. Generates a
///                         self-signed cert under $APPDATA/server.{crt,key}
///                         on first launch and binds HTTPS instead of HTTP.
///   --tls-cert=`<path>` Use the supplied certificate PEM instead
///                         of generating a self-signed one.
///   --tls-key=`<path>` Use the supplied private-key PEM instead
///                         of generating a self-signed one.
///   --relay-url=`<url>`     v4 couch-grade remote: dial OUT to a self-hosted
///                         Nightshade relay (ws(s)://host[:port]) so the rig
///                         is reachable from anywhere with no port-forwarding.
///                         The appliance id minted on first contact is printed
///                         to stdout/log; enter it + the relay URL in the app.
///   --relay-allow-insecure-tls
///                         Trust a self-signed relay TLS cert. Only for relays
///                         you operate yourself before getting a real cert.
///
///   Environment variables:
///   NIGHTSHADE_AUTH_TOKEN  Authentication token
///   NIGHTSHADE_VIEW_TOKEN  Optional read-only token
///   NIGHTSHADE_CONTROL_TOKEN
///                         Optional imaging-control token
///   NIGHTSHADE_PORT        Server port (default: 8080)
///   NIGHTSHADE_DATA_DIR    Native persistence root (defect maps, etc.). When
///                         unset, matches the GUI application-support path.
///   NIGHTSHADE_DATABASE_DIR
///                         Drift database directory. Headless systemd/Pi
///                         installs pin this under /var/lib/nightshade so the
///                         daemon does not depend on a user Documents folder.
///   NIGHTSHADE_BROWSE_ROOTS
///                         Semicolon-separated remote directory browse roots
///                         for headless clients, e.g.
///                         Captures=/mnt/captures;USB=/media/nightshade.
///   NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN=true
///                         Same as --allow-unauthenticated-lan
///   NIGHTSHADE_TRUST_PROXY=true
///                         Believe the X-Forwarded-For / X-Real-IP headers when
///                         deriving the rate-limit / pairing-lockout key. OFF by
///                         default: in direct-bind mode those headers are client-
///                         spoofable. Set to true ONLY behind the loopback nginx
///                         reverse proxy documented in docs/remote-control.md
///                         ("TLS with nginx"); without it every proxied client
///                         shares one rate-limit/lockout bucket. Honoured only
///                         when the socket peer is loopback.
///   NIGHTSHADE_ALLOW_INSECURE_UPDATE_SOURCE=true
///                         Testing only. Allow the OTA updater to fetch from a
///                         non-HTTPS / unpinned update source. Never set on a
///                         production appliance.
///   NIGHTSHADE_CORS_ORIGINS
///                         Comma-separated CORS allow-list (same effect as
///                         passing --cors-origin repeatedly).
///   NIGHTSHADE_PAIRING_PRINT_CODES=true
///                         Same as --pairing-print-codes.
///   NIGHTSHADE_TLS=true   Same as --tls.
///   NIGHTSHADE_TLS_CERT   Same as --tls-cert=`<path>`.
///   NIGHTSHADE_TLS_KEY    Same as --tls-key=`<path>`.
///   NIGHTSHADE_RELAY_URL  Same as --relay-url=`<url>`.
///   NIGHTSHADE_RELAY_ALLOW_INSECURE_TLS=true
///                         Same as --relay-allow-insecure-tls.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Operator-facing stdout banner. The LoggingService isn't bootable yet
  // (no ProviderContainer), so write directly to stdout. Once the logger
  // is initialised below, all subsequent diagnostics route through it.
  stdout.writeln('Nightshade - Headless Mode');
  stdout.writeln('==============================');

  LoggingService? logger;
  ProviderContainer? container;
  HeadlessApiServer? apiServer;
  // Push-notification stream is owned by HeadlessApiServer.stop() (it holds
  // the StreamSubscription internally and cancels it on shutdown); we keep
  // no top-level handle here.
  StreamSubscription<DiskSpaceWatchdogEvent>? diskWatchdogSubscription;
  DiskSpaceGuardService? diskGuard;
  // headless OTA update stack. Owned at the entry point so SIGINT
  // can shut both the controller and the LAN push receiver cleanly.
  UpdateStack? updateStack;
  // v4 couch-grade remote: outbound relay uplink (optional). Owned here so
  // SIGINT/SIGTERM tear down the WebSocket cleanly. Null unless a relay URL
  // was supplied via --relay-url / NIGHTSHADE_RELAY_URL.
  RelayUplink? relayUplink;

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
        // even in headless mode we install the palette
        // blueprint override so an upstream UI client (mobile companion,
        // headless API consumer) sees plugin sequence nodes in the
        // palette listing.
        pluginNodePaletteBlueprintsOverride(),
        // C4 — honour the persisted plugin enable/disable choices at
        // registration time. A headless host runs the same bundled plugins
        // (Discord/Pushover/Home Assistant sequence nodes), so a plugin the
        // operator disabled must not silently re-enable when the daemon
        // restarts.
        pluginEnablementStoreOverride(),
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

    final authConfig = parseHeadlessAuthConfig(args);
    runtimeLogger.info(
      'Starting headless API server on port ${authConfig.port}',
      source: _headlessLogSource,
    );

    apiServer = await startHeadlessServices(
      container,
      logger: runtimeLogger,
      authToken: authConfig.token,
      scopedAuthTokens: authConfig.scopedTokens,
      requireAuth: authConfig.requireAuth,
      bindLocalOnly: authConfig.bindLocalOnly,
      port: authConfig.port,
      corsAllowedOrigins: authConfig.corsAllowedOrigins,
      pairingPrintCodes: authConfig.pairingPrintCodes,
      pairingMode: authConfig.pairingMode,
      tlsEnabled: authConfig.tlsEnabled,
      tlsCertPath: authConfig.tlsCertPath,
      tlsKeyPath: authConfig.tlsKeyPath,
    );
    runtimeLogger.info(
      'Headless API server started',
      source: _headlessLogSource,
    );

    // v4 couch-grade remote: if a relay URL was supplied, dial OUT to the
    // self-hosted relay and proxy the loopback headless API through it so the
    // rig is reachable from anywhere with no port-forwarding. End-to-end auth
    // stays the existing pairing token / HMAC, which the relay never sees in
    // plaintext. Failures are logged-and-continue: the LAN/mDNS path is
    // unaffected if the relay is down.
    relayUplink = await startRelayUplink(
      args: args,
      logger: runtimeLogger,
      localPort: apiServer.actualPort,
      onApplianceId: (id) => apiServer?.setRelayApplianceId(id),
    );

    // register `_nightshade._tcp` via mDNS. This MUST happen after
    // `apiServer.start()` so the advertised port is the actually-bound one
    // (matters when the caller started us with port 0). Failures here are
    // logged-and-continue — UDP broadcast and manual entry remain available.
    if (!authConfig.bindLocalOnly) {
      // Refresh the static Avahi service file so the advertised <port> and
      // scheme= TXT match the actually-bound port/scheme. The file installed
      // by packaging/appliance/systemd/install.sh hardcodes 8080/http, so a
      // changed NIGHTSHADE_PORT or `--tls` would otherwise silently break
      // mDNS discovery. Best-effort: a missing/read-only services dir (i.e.
      // not running as the appliance) is logged-and-skipped.
      refreshAvahiServiceFile(
        logger: runtimeLogger,
        port: apiServer.actualPort,
        scheme: apiServer.isTlsActive ? 'https' : 'http',
        version: appVersion.version,
      );
      try {
        await startMdnsAdvertisement(
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

    // wire push notifications to the API server so weather aborts,
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

    // Architecture-unification, Subsystem 3: eager-mount the
    // NotificationRouter so the external transports (Discord, email, Telegram,
    // Pushover, MQTT, webhook) and the in-app/mobile-push fan-out fire for any
    // routed backend event even with no sequence running. On a Pi-hosted
    // headless server there is no widget tree to lazily build the router, so
    // without this read the router never attached its event subscription and
    // every external alert was dead. Push delivery to phones is wired
    // separately above (setPushNotificationStream); this read powers the
    // configurable external transports that the GUI shell mounts via its own
    // background-services bootstrap.
    try {
      container.read(notificationRouterProvider);
      runtimeLogger.info(
        'Notification router mounted (external transports active)',
        source: _headlessLogSource,
      );
    } catch (e, st) {
      runtimeLogger.error(
        'Failed to mount notification router: $e\n$st',
        source: _headlessLogSource,
      );
    }

    // v4 couch-grade remote: eager-mount Home Assistant MQTT discovery —
    // a headless appliance is exactly where the observatory should show
    // up as native HA entities. No-op until enabled in settings.
    try {
      container.read(homeAssistantDiscoveryProvider);
    } catch (e, st) {
      runtimeLogger.error(
        'Failed to mount Home Assistant discovery: $e\n$st',
        source: _headlessLogSource,
      );
    }

    // wire the disk-space watchdog. In GUI mode the sequencer
    // controller subscribes to this stream and pauses on blocking severity;
    // in headless mode nothing was consuming it, so the rig would keep
    // imaging past the abort threshold until raw write() failures aborted
    // the sequence mid-frame. Hook the watchdog into backend.sequencerStop
    // here so overnight unattended runs halt cleanly before the disk fills.
    try {
      final guard = container.read(diskSpaceGuardProvider);
      diskGuard = guard;
      diskWatchdogSubscription = await startDiskSpaceWatchdog(
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

    // provision the OTA update stack and wire it into the
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
            'serverUrl': stack.controller.updateServerUrl ?? 'unconfigured',
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
    runtimeLogger.info(
      'Headless mode running; waiting for SIGINT/SIGTERM',
      source: _headlessLogSource,
    );

    Future<void> shutdown(String reason) async {
      logger?.info('$reason; shutting down', source: _headlessLogSource);
      await diskWatchdogSubscription?.cancel();
      diskGuard?.stop();
      stopDiscoverySocket();
      // mDNS unregister BEFORE the HTTP server stops so peers stop trying to
      // dial a port that is about to go away. Failures inside stop() are
      // already swallowed and logged by the class itself.
      await stopMdnsAdvertisement();
      // Drop the relay uplink BEFORE the HTTP server so in-flight tunnelled
      // streams fail fast instead of dangling on a port that's about to close.
      await relayUplink?.stop();
      relayUplink = null;
      // detach the update controller from the server BEFORE
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
    await stopMdnsAdvertisement();
    await relayUplink?.stop();
    relayUplink = null;
    apiServer?.setUpdateController(null);
    await apiServer?.stop();
    await updateStack?.dispose();
    container?.dispose();
    exit(1);
  }
}
